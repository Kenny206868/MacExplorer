import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class ChromeDensitySnapshotTests: XCTestCase {
    @MainActor private final class Probe { var regions: [String: CGRect] = [:] }
    @MainActor func testEfficientChromeHasOneShelfAndBoundedNativeControls() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory), preferences = PreferenceStore.shared, original = preferences.value
        let settings = CommanderPreferences.shared
        let saved = (settings.showCommandBar, settings.classicFunctionKeys, settings.compactTitlebar, settings.paneTerminalButtons)
        let input = InputPreferences.shared, originalTouch = input.touchFriendly, originalColumns = DetailsColumnStore.shared.value
        let fixture = try CommanderFixture(), owner = fixture.owner
        defer {
            fixture.close(); preferences.value = original; DetailsColumnStore.shared.value = originalColumns
            input.touchFriendly = originalTouch; settings.showCommandBar = saved.0; settings.classicFunctionKeys = saved.1
            settings.compactTitlebar = saved.2; settings.paneTerminalButtons = saved.3; AppRouter.shared.active = nil
        }
        settings.classicFunctionKeys = true; settings.compactTitlebar = false; settings.paneTerminalButtons = false
        preferences.value.inspector = false; preferences.value.previewPane = false; DetailsColumnStore.shared.value = DetailsColumns()
        let destination = fixture.root.appendingPathComponent("Release Assets — Desktop and Mobile Builds")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let readme = destination.appendingPathComponent("Release notes.md"); try Data("Release documentation".utf8).write(to: readme)
        for name in ["Assets", "Documentation", "Sources", "Tests"] {
            let url = fixture.root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); owner.current.entries.append(try FileEntry(url: url))
        }
        for name in ["Architecture.md", "Package.swift", "settings.json", "Release checklist.txt"] {
            let url = fixture.root.appendingPathComponent(name); try Data(repeating: 65, count: 4096).write(to: url)
            owner.current.entries.append(try FileEntry(url: url))
        }
        preferences.value.pins = [Bookmark(fixture.root), Bookmark(destination)]
        owner.current.selection = [fixture.files[0].url, fixture.files[2].url]
        owner.dualPane = DualPaneController(primary: owner)
        let panes = try XCTUnwrap(owner.dualPane), other = panes.secondary
        other.current.stop(); other.current.history = NavigationHistory(.folder(destination))
        other.current.entries = [try FileEntry(url: readme)]; other.current.loading = false
        var captures: [NativeViewSnapshotTests.Capture] = [], evidence: [[String: String]] = []
        let scenarios: [(String, CGFloat, CGFloat, Bool, Bool)] = [
            ("native-efficient-window", 1440, 720, false, true),
            ("native-efficient-narrow", 800, 720, false, true),
            ("native-efficient-touch", 800, 800, true, true),
            ("native-efficient-standard", 1260, 720, false, false)
        ]
        for dark in [false, true] {
            preferences.value.theme = dark ? "dark" : "light"
            for (name, width, height, touch, commander) in scenarios {
                input.touchFriendly = touch; settings.showCommandBar = commander
                let probe = Probe(), captureName = (dark ? "dark-" : "light-") + name
                let content = AnyView(WindowWorkspaceShell(workspace: owner).environmentObject(owner).environmentObject(preferences).environmentObject(AppUpdater())
                    .onPreferenceChange(ExplorerLayoutRegions.self) { probe.regions = $0 })
                captures.append(try await NativeSnapshotCapture.render(content, named: captureName, size: NSSize(width: width, height: height), dark: dark, output: output, chromeOwner: owner) { window in
                    let policy = WorkspaceChromeLayout(width: width, touch: touch)
                    let footer = try XCTUnwrap(probe.regions["status"], captureName)
                    XCTAssertEqual(footer.height, policy.footerHeight, accuracy: 0.5, "One shared footer only")
                    for side in ["primary", "secondary"] {
                        let status = try XCTUnwrap(probe.regions["pane.status." + side], captureName)
                        XCTAssertEqual(status.height, policy.paneStatusHeight, accuracy: 0.5, captureName)
                    }
                    if commander {
                        let commands = try XCTUnwrap(probe.regions["footer.commands"], captureName)
                        XCTAssertLessThan(commands.width, touch ? 370 : 590, "Commands must be content-sized, not stretched across the window")
                        var previous = commands
                        for key in ["footer.context", "footer.selectionTools", "footer.activity", "footer.tools"] {
                            let next = try XCTUnwrap(probe.regions[key], key)
                            XCTAssertGreaterThanOrEqual(next.minX, previous.maxX - 0.5, "Footer overlap: " + key)
                            XCTAssertLessThanOrEqual(next.maxX, footer.maxX + 0.5, "Footer overflow: " + key)
                            XCTAssertGreaterThan(next.width, 0, key)
                            previous = next
                        }
                    }
                    let toolbar = try XCTUnwrap(window.toolbar)
                    let item = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "workspace" })
                    let host = try XCTUnwrap(item.view)
                    XCTAssertFalse(host.isHiddenOrHasHiddenAncestor, "Workspace controls must not be silently moved out of the toolbar")
                    XCTAssertGreaterThan(host.bounds.width, 150)
                    XCTAssertEqual(host.bounds.width, policy.titlebarWidth, accuracy: 1)
                    XCTAssertEqual(host.bounds.height, policy.titlebarHeight, accuracy: 1)
                    XCTAssertNotNil(item.menuFormRepresentation?.submenu, "Native toolbar overflow retains every workspace command")
                    XCTAssertEqual(owner.current.selection.count, 2); XCTAssertTrue(other.current.selection.isEmpty)
                    evidence.append(["capture": captureName, "footerHeight": String(policy.footerHeight), "paneStatusHeight": String(policy.paneStatusHeight),
                        "titlebarWidth": String(policy.titlebarWidth), "commander": String(commander), "touch": String(touch),
                        "checks": "one shelf; bounded content-sized groups; no footer overlap; visible native workspace host; preserved selection"])
                })
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("chrome-density-captures.json"), options: .atomic)
        try encoder.encode(evidence).write(to: output.appendingPathComponent("chrome-density-assertions.json"), options: .atomic)
        XCTAssertEqual(captures.count, 8)
    }
}
