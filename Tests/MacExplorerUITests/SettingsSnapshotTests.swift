import XCTest
import SwiftUI
import AppKit
@testable import MacExplorer

final class SettingsSnapshotTests: XCTestCase {
    @MainActor func testAllSettingsPagesInBothAppearances() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job only") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory), store = PreferenceStore.shared
        let original = store.value, touch = InputPreferences.shared.touchFriendly
        defer { store.value = original; InputPreferences.shared.touchFriendly = touch }
        InputPreferences.shared.touchFriendly = false
        let updater = AppUpdater()
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            store.value.theme = dark ? "dark" : "light"
            for (name, page) in [("appearance", SettingsPage.appearance), ("input", .input), ("integration", .integration), ("updates", .updates)] {
                let view = AnyView(PreferencesView(initialPage: page).environmentObject(store).environmentObject(updater))
                captures.append(try await NativeSnapshotCapture.render(view, named: (dark ? "dark-" : "light-") + "settings-" + name, size: NSSize(width: 700, height: 580), dark: dark, output: output))
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(captures).write(to: output.appendingPathComponent("settings-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 8)
    }
}
