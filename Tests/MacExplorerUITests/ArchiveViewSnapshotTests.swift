import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class ArchiveViewSnapshotTests: XCTestCase {
    @MainActor func testArchiveBrowserInBothAppearances() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job only") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveViews-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Project materials.zip")
        try XCTUnwrap(Data(base64Encoded: Self.archive)).write(to: source)
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        workspace.current.stop(); defer { workspace.tabs.forEach { $0.stop() } }
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            captures.append(try await NativeSnapshotCapture.render(AnyView(ArchiveBrowserSheet(workspace: workspace, source: source)),
                named: dark ? "dark-archive-browser" : "light-archive-browser", size: NSSize(width: 840, height: 650), dark: dark, output: output, verify: { window in
                    let nativeTable = try XCTUnwrap(Self.findTable(in: window.contentView), "The production archive table must render")
                    XCTAssertFalse(nativeTable.usesAlternatingRowBackgroundColors, "Empty archive canvas must not contain fake zebra rows")
                }))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("archive-captures.json"), options: .atomic)
    }
    @MainActor private static func findTable(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let nativeTable = view as? NSTableView { return nativeTable }
        for child in view.subviews { if let nativeTable = findTable(in: child) { return nativeTable } }
        return nil
    }
    static let archive = "UEsDBBQAAAAIAKqxblecUSL7DwAAAA0AAAAQAAAAbmVzdGVkL2hlbGxvLnR4dPNIzcnJV0gsSs7ILEsFAFBLAwQUAAAACACqsW5XDGaWKw8AAAANAAAACQAAAG90aGVyLnR4dPMvyUgtUkjOzytJzSsBAFBLAQIUAxQAAAAIAKqxblecUSL7DwAAAA0AAAAQAAAAAAAAAAAAAACggQAAAABuZXN0ZWQvaGVsbG8udHh0UEsBAhQDFAAAAAgAqrFuVwxmlisPAAAADQAAAAkAAAAAAAAAAAAAAKCBPQAAAG90aGVyLnR4dFBLBQYAAAAAAgACAHUAAABzAAAAAAA="
}
