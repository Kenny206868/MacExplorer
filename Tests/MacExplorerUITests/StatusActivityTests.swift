import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class StatusActivityTests: XCTestCase {
    @MainActor func testRealActivityAndVolumeViews() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path), center = OperationCenter.shared
        let previous = center.jobs
        defer { center.jobs = previous }
        var captures: [NativeViewSnapshotTests.Capture] = []
        for dark in [false, true] {
            let prefix = dark ? "dark-" : "light-"
            center.jobs = []
            captures.append(try await NativeSnapshotCapture.render(AnyView(FileActivityPopover()), named: prefix + "status-idle", size: NSSize(width: 440, height: 340), dark: dark, output: output))
            let running = OperationRow(title: "Copy Release Assets")
            running.progress = FileProgress(completed: 4, total: 12, name: "Architecture.pdf", bytes: 8_000_000, logicalBytes: 8_000_000, totalBytes: 20_000_000, phase: .copying, sequence: 1)
            running.status = "Copying"
            let now = ProcessInfo.processInfo.systemUptime
            for index in 0..<25 { running.statistics.record(bytes: Int64(index) * 320_000, at: now - 2.5 + Double(index) * 0.1) }
            let stopped = OperationRow(title: "Move Documents")
            stopped.finished = true; stopped.cancelled = true; stopped.status = "Cancelled — completed items retained"
            center.jobs = [running, stopped]
            captures.append(try await NativeSnapshotCapture.render(AnyView(FileActivityPopover()), named: prefix + "status-running", size: NSSize(width: 440, height: 580), dark: dark, output: output))
            let volume = StatusVolume(name: "Project SSD", available: 250_000_000_000, total: 1_000_000_000_000, format: "APFS", readOnly: false)
            captures.append(try await NativeSnapshotCapture.render(AnyView(StatusVolumeView(volume: volume)), named: prefix + "status-storage", size: NSSize(width: 350, height: 260), dark: dark, output: output))
            XCTAssertFalse(running.finished)
            XCTAssertFalse(running.control.isCancelled, "Rendering activity must not alter operation state")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("status-captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 6)
    }
}
