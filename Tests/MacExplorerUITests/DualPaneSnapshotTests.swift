import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

/// Populated production panes: the second browser is not a duplicated bitmap.
final class DualPaneSnapshotTests: XCTestCase {
    @MainActor private final class Probe { var regions: [String: CGRect] = [:] }
    @MainActor func testPopulatedDualPaneAndInputMatrix() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job only") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory)
        let fm = FileManager.default, preferences = PreferenceStore.shared, input = InputPreferences.shared
        let previous = preferences.value, previousTouch = input.touchFriendly, previousColumns = DetailsColumnStore.shared.value
        let previousJobs = OperationCenter.shared.jobs
        let fixture = fm.temporaryDirectory.appendingPathComponent("MacExplorer-Dual-" + UUID().uuidString)
        let left = fixture.appendingPathComponent("Documents"), right = fixture.appendingPathComponent("Release assets")
        try fm.createDirectory(at: left, withIntermediateDirectories: true)
        try fm.createDirectory(at: right, withIntermediateDirectories: false)
        defer {
            preferences.value = previous; input.touchFriendly = previousTouch; DetailsColumnStore.shared.value = previousColumns
            OperationCenter.shared.jobs = previousJobs; AppRouter.shared.active = nil
            try? fm.removeItem(at: fixture)
        }
        let names = ["Brand guidelines.md", "Budget 2026.csv", "Meeting notes.txt", "Project proposal.txt", "Release checklist.md", "Research notes.txt", "Website roadmap.md", "Zażółć gęślą jaźń.txt"]
        for (index, name) in names.enumerated() {
            let url = left.appendingPathComponent(name)
            try Data((String(repeating: "MacExplorer design fixture.\n", count: 40 + index)).utf8).write(to: url)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_789_099_200)], ofItemAtPath: url.path)
        }
        for name in ["Brand kit", "Campaign images", "Documentation", "Screenshots"] {
            try fm.createDirectory(at: right.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        try Data("Release manifest\n".utf8).write(to: right.appendingPathComponent("Manifest.txt"))
        try makePoster(at: right.appendingPathComponent("Color study.png"))
        let leftEntries = try names.map { try FileEntry(url: left.appendingPathComponent($0)) }
        let rightEntries = try fm.contentsOfDirectory(at: right, includingPropertiesForKeys: nil).map { try FileEntry(url: $0) }
        var settings = Preferences(); settings.restoreTabs = false; settings.pins = [Bookmark(left), Bookmark(right)]
        settings.recent = []; settings.inspector = true; settings.previewPane = false
        preferences.value = settings; DetailsColumnStore.shared.value = DetailsColumns(); OperationCenter.shared.jobs = []
        let scenarios: [(String, CGFloat, CGFloat, PaneOrientation, PaneSide, Bool)] = [
            ("dual-side-by-side", 1440, 860, .sideBySide, .primary, false),
            ("dual-secondary", 1440, 860, .sideBySide, .secondary, false),
            ("dual-stacked", 1260, 1000, .stacked, .primary, false),
            ("dual-narrow", 800, 900, .sideBySide, .primary, false),
            ("dual-inspector", 1760, 900, .sideBySide, .primary, false),
            ("dual-touch", 1440, 900, .sideBySide, .secondary, true)
        ]
        var captures: [NativeViewSnapshotTests.Capture] = []
        var evidence: [[String: String]] = []
        for dark in [false, true] {
            preferences.value.theme = dark ? "dark" : "light"
            for (name, width, height, preferred, side, touch) in scenarios {
                input.touchFriendly = touch
                let root = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(left)), options: FolderOptions(), query: "", allLocations: false, selection: []))
                root.dualPane = DualPaneController(primary: root)
                let dual = try XCTUnwrap(root.dualPane), other = dual.secondary
                other.current.history = NavigationHistory(.folder(right))
                root.current.stop(); other.current.stop()
                root.current.entries = leftEntries; other.current.entries = rightEntries
                root.current.loading = false; other.current.loading = false
                root.current.selection = Set(leftEntries.prefix(2).map(\.url))
                other.current.selection = Set(rightEntries.filter { $0.url.pathExtension == "png" }.map(\.url))
                other.current.options.view = .large
                root.touchSelecting = touch; other.touchSelecting = touch
                dual.geometry.orientation = preferred; dual.geometry.focused = side
                let probe = Probe(), captureName = (dark ? "dark-" : "light-") + name
                let content = AnyView(WindowWorkspaceShell(workspace: root).environmentObject(root).environmentObject(preferences).environmentObject(AppUpdater())
                    .onPreferenceChange(ExplorerLayoutRegions.self) { probe.regions = $0 })
                captures.append(try await NativeSnapshotCapture.render(content, named: captureName, size: NSSize(width: width, height: height), dark: dark, output: output))
                let first = try XCTUnwrap(probe.regions["pane.primary"], captureName)
                let second = try XCTUnwrap(probe.regions["pane.secondary"], captureName)
                let files = try XCTUnwrap(probe.regions["files"], captureName)
                let policy = DualPaneLayout(width: files.width, height: files.height, preferred: preferred, ratio: 0.5)
                for rect in [first, second] {
                    XCTAssertGreaterThan(rect.width, 300, captureName); XCTAssertGreaterThan(rect.height, 160, captureName)
                    XCTAssertGreaterThanOrEqual(rect.minX, files.minX - 1, captureName)
                    XCTAssertLessThanOrEqual(rect.maxX, files.maxX + 1, captureName)
                    XCTAssertGreaterThanOrEqual(rect.minY, files.minY - 1, captureName)
                    XCTAssertLessThanOrEqual(rect.maxY, files.maxY + 1, captureName)
                }
                XCTAssertTrue(first.intersection(second).isNull, captureName)
                if policy.orientation == .sideBySide {
                    XCTAssertEqual(first.height, second.height, accuracy: 1, captureName)
                    XCTAssertEqual(second.minX - first.maxX, 7, accuracy: 1, captureName)
                } else { XCTAssertEqual(second.minY - first.maxY, 7, accuracy: 1, captureName) }
                XCTAssertEqual(root.current.selection.count, 2, captureName)
                XCTAssertEqual(other.current.selection.count, 1, captureName)
                XCTAssertEqual(dual.geometry.orientation, preferred, "Responsive fallback must not overwrite saved intent")
                evidence.append(["capture": captureName, "orientation": policy.orientation.rawValue, "focus": side.rawValue, "touchFriendly": String(touch)])
                root.tabs.forEach { $0.stop() }; other.tabs.forEach { $0.stop() }
            }
            input.touchFriendly = true
            let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(left)), options: FolderOptions(), query: "", allLocations: false, selection: []))
            workspace.current.stop(); workspace.current.entries = leftEntries; workspace.current.selection = Set(leftEntries.prefix(2).map(\.url))
            let theme = dark ? "dark-" : "light-"
            captures.append(try await NativeSnapshotCapture.render(AnyView(FileActionSheet(workspace: workspace)), named: theme + "touch-file-actions", size: NSSize(width: 620, height: 600), dark: dark, output: output))
            input.touchFriendly = false
            captures.append(try await NativeSnapshotCapture.render(AnyView(KeyboardHelpView()), named: theme + "keyboard-help", size: NSSize(width: 800, height: 740), dark: dark, output: output))
            workspace.current.stop()
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("dual-captures.json"), options: .atomic)
        try encoder.encode(evidence).write(to: output.appendingPathComponent("dual-assertions.json"), options: .atomic)
        XCTAssertEqual(captures.count, 16); XCTAssertEqual(evidence.count, 12)
    }
    @MainActor private func makePoster(at url: URL) throws {
        let image = NSImage(size: NSSize(width: 640, height: 480)); image.lockFocus()
        NSColor(srgbRed: 0.09, green: 0.18, blue: 0.30, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 640, height: 480).fill()
        NSColor(srgbRed: 0.18, green: 0.69, blue: 0.71, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 60, y: 70, width: 340, height: 340), xRadius: 52, yRadius: 52).fill()
        NSColor(srgbRed: 0.97, green: 0.73, blue: 0.37, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 310, y: 120, width: 260, height: 260)).fill(); image.unlockFocus()
        let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}
