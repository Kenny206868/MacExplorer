import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class CommanderSnapshotTests: XCTestCase {
    @MainActor func testCommanderWorkspaceSettingsAndMasksInBothAppearances() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path), preferences = PreferenceStore.shared, saved = preferences.value
        let settings = CommanderPreferences.shared
        let original = (settings.showCommandBar, settings.classicFunctionKeys, settings.compactTitlebar, settings.paneStorage, settings.paneTerminalButtons)
        let input = InputPreferences.shared.touchFriendly, columns = DetailsColumnStore.shared.value
        defer {
            preferences.value = saved; InputPreferences.shared.touchFriendly = input; DetailsColumnStore.shared.value = columns
            settings.showCommandBar = original.0; settings.classicFunctionKeys = original.1; settings.compactTitlebar = original.2
            settings.paneStorage = original.3; settings.paneTerminalButtons = original.4; AppRouter.shared.active = nil
        }
        settings.showCommandBar = true; settings.classicFunctionKeys = true; settings.compactTitlebar = false
        settings.paneStorage = true; settings.paneTerminalButtons = true
        InputPreferences.shared.touchFriendly = false; DetailsColumnStore.shared.value = DetailsColumns()
        preferences.value.inspector = false; preferences.value.previewPane = false
        let fixture = try CommanderFixture(); defer { fixture.close() }
        let owner = fixture.owner, destination = fixture.root.appendingPathComponent("Release Assets")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let readme = destination.appendingPathComponent("README.md"); try Data("Release documentation".utf8).write(to: readme)
        for name in ["Assets", "Documentation", "Sources"] {
            let folder = fixture.root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            owner.current.entries.append(try FileEntry(url: folder))
        }
        for name in ["Architecture.md", "Package.swift", "settings.json", "Release checklist.txt"] {
            let file = fixture.root.appendingPathComponent(name); try Data(repeating: 65, count: 4096).write(to: file)
            owner.current.entries.append(try FileEntry(url: file))
        }
        preferences.value.pins = [Bookmark(fixture.root), Bookmark(destination)]
        owner.current.selection = [fixture.files[0].url, fixture.files[2].url]
        owner.dualPane = DualPaneController(primary: owner)
        let dual = try XCTUnwrap(owner.dualPane)
        dual.secondary.current.stop(); dual.secondary.current.history = NavigationHistory(.folder(destination))
        dual.secondary.current.entries = [try FileEntry(url: readme)]; dual.secondary.current.loading = false
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            preferences.value.theme = dark ? "dark" : "light"
            for (name, width) in [("native-commander-window", 1440.0), ("native-commander-narrow", 800)] {
                let content = AnyView(WindowWorkspaceShell(workspace: owner).environmentObject(owner).environmentObject(preferences).environmentObject(AppUpdater()))
                captures.append(try await NativeSnapshotCapture.render(content, named: (dark ? "dark-" : "light-") + name,
                    size: NSSize(width: width, height: 720), dark: dark, output: output, chromeOwner: owner) { window in
                        XCTAssertEqual(window.toolbarStyle, .unified)
                        XCTAssertTrue(window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "power" } == true)
                        XCTAssertEqual(owner.current.selection.count, 2)
                        XCTAssertEqual(owner.current.selectionStatistics.files, 2)
                        XCTAssertTrue(dual.secondary.current.selection.isEmpty)
                    })
            }
            captures.append(try await NativeSnapshotCapture.render(AnyView(CommanderSettingsView()), named: (dark ? "dark-" : "light-") + "commander-settings",
                size: NSSize(width: 590, height: 570), dark: dark, output: output))
            captures.append(try await NativeSnapshotCapture.render(AnyView(SelectionMaskView(workspace: owner, tab: owner.current, initialPattern: "*.swift;*.txt | *.g.swift")),
                named: (dark ? "dark-" : "light-") + "selection-masks", size: NSSize(width: 570, height: 540), dark: dark, output: output))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("commander-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 8)
    }
}
