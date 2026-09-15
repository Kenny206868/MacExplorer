import XCTest
import AppKit
import SwiftUI
import ExplorerCore
@testable import MacExplorer

final class NativeWindowChromeTests: XCTestCase {
    @MainActor func testRealWindowChromeAndNativeCaptureMatrix() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path), manager = FileManager.default
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let root = manager.temporaryDirectory.appendingPathComponent("NativeChrome-" + UUID().uuidString)
        let folder = root.appendingPathComponent("Project Documents"), second = root.appendingPathComponent("Release Assets")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        try manager.createDirectory(at: second, withIntermediateDirectories: true)
        for name in ["Design specification.md", "Budget.csv", "Release notes.txt", "Zażółć gęślą.txt"] {
            try Data("MacExplorer native titlebar fixture\n".utf8).write(to: folder.appendingPathComponent(name))
        }
        let prefs = PreferenceStore.shared, original = prefs.value
        let originalInput = InputPreferences.shared.touchFriendly, originalColumns = DetailsColumnStore.shared.value
        defer { prefs.value = original; InputPreferences.shared.touchFriendly = originalInput; DetailsColumnStore.shared.value = originalColumns; try? manager.removeItem(at: root); AppRouter.shared.active = nil }
        prefs.value.pins = [Bookmark(folder), Bookmark(second)]; prefs.value.inspector = true; prefs.value.previewPane = false
        InputPreferences.shared.touchFriendly = false; DetailsColumnStore.shared.value = DetailsColumns()
        let files = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).map { try FileEntry(url: $0) }
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            prefs.value.theme = dark ? "dark" : "light"
            for (name, width, dual) in [("native-window", 1260.0, false), ("native-dual-window", 1440, true), ("native-narrow-window", 800, false)] {
                let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(folder)), options: FolderOptions(), query: "", allLocations: false, selection: []))
                workspace.current.stop(); workspace.current.entries = files; workspace.current.loading = false
                workspace.current.selection = Set(files.prefix(2).map(\.url))
                if dual {
                    workspace.dualPane = DualPaneController(primary: workspace)
                    workspace.dualPane?.secondary.current.history = NavigationHistory(.folder(second))
                    workspace.dualPane?.secondary.current.stop(); workspace.dualPane?.secondary.current.entries = []
                }
                let content = AnyView(WindowWorkspaceShell(workspace: workspace).environmentObject(workspace).environmentObject(prefs).environmentObject(AppUpdater()))
                let capture = try await NativeSnapshotCapture.render(content, named: (dark ? "dark-" : "light-") + name,
                    size: NSSize(width: width, height: 720), dark: dark, output: output, chromeOwner: workspace) { window in
                        XCTAssertEqual(window.title, "Project Documents")
                        XCTAssertEqual(window.representedURL?.standardizedFileURL.path, folder.standardizedFileURL.path)
                        XCTAssertEqual(window.toolbarStyle, .unified)
                        let toolbar = try XCTUnwrap(window.toolbar)
                        XCTAssertTrue(toolbar.allowsUserCustomization)
                        XCTAssertFalse(window.isMovableByWindowBackground)
                        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                            let button = try XCTUnwrap(window.standardWindowButton(kind))
                            XCTAssertFalse(button.isHiddenOrHasHiddenAncestor)
                            XCTAssertGreaterThan(button.bounds.width, 0)
                        }
                        XCTAssertGreaterThan(toolbar.items.count, 5)
                        XCTAssertTrue(toolbar.items.allSatisfy { $0.itemIdentifier == .flexibleSpace || $0.menuFormRepresentation != nil })
                    }
                XCTAssertGreaterThan(capture.height, 720, "Capture must include the native titlebar")
                captures.append(capture)
                workspace.tabs.forEach { $0.stop() }; workspace.dualPane?.secondary.tabs.forEach { $0.stop() }
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("window-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 6)
    }
    @MainActor func testToolbarLocationTracksPaneFocusAndRetainsCustomization() throws {
        _ = NSApplication.shared
        let root = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        root.current.stop()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; root.window = window
        let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false; chrome.attach(to: window, owner: root)
        defer { root.current.stop(); root.dualPane?.secondary.current.stop(); window.close(); AppRouter.shared.active = nil }
        let toolbar = try XCTUnwrap(window.toolbar)
        toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier("operations"), at: 0)
        chrome.refresh(); XCTAssertEqual(toolbar.items.first?.itemIdentifier.rawValue, "operations")
        root.dualPane = DualPaneController(primary: root)
        root.dualPane?.secondary.current.history = NavigationHistory(.folder(URL(fileURLWithPath: "/tmp")))
        root.dualPane?.focus(.secondary); chrome.refresh()
        XCTAssertEqual(window.title, "tmp"); XCTAssertTrue(window.subtitle.contains("Right pane"))
        root.dualPane?.secondary.sheet = .properties
        XCTAssertFalse(WindowChromeAction.copy.enabled(for: root))
        let originalView = root.dualPane?.secondary.current.options.view
        WindowChromeAction.icons.perform(on: root)
        XCTAssertEqual(root.dualPane?.secondary.current.options.view, originalView)
    }
}
