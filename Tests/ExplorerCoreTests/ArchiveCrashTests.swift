import XCTest
import ExplorerJournal
@testable import ExplorerCore

final class ArchiveCrashTests: XCTestCase {
    private static let fixture = "UEsDBBQAAAAAAAAAIViFcHIvCAAAAAgAAAAPAAAAZG9jcy9yZWFkbWUudHh0b3JpZ2luYWxQSwMEFAAAAAAAAAAhWGP+6XQJAAAACQAAAAgAAABrZWVwLnR4dHVudG91Y2hlZFBLAQIUAxQAAAAAAAAAIViFcHIvCAAAAAgAAAAPAAAAAAAAAAAAAACggQAAAABkb2NzL3JlYWRtZS50eHRQSwECFAMUAAAAAAAAACFYY/7pdAkAAAAJAAAACAAAAAAAAAAAAAAAoIE1AAAAa2VlcC50eHRQSwUGAAAAAAIAAgBzAAAAZAAAAAAA"
    private func probe(_ root: URL, point: JournalFaultPoint, ordinal: Int) throws {
        let own = URL(fileURLWithPath: CommandLine.arguments[0])
        let candidates = [own.deletingLastPathComponent().appendingPathComponent("FileOperationCrashProbe"),
            own.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("FileOperationCrashProbe"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/debug/FileOperationCrashProbe")]
        let executable = try XCTUnwrap(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
        let process = Process(), pipe = Pipe(); process.executableURL = executable
        process.arguments = [root.path, "archive", point.rawValue, String(ordinal)]
        process.standardError = pipe; process.standardOutput = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(15)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 73 else { throw ExplorerError.message("Crash boundary was not reached: \(point) #\(ordinal): \(output)") }
    }
    func testEveryArchiveInstallBoundaryRestoresOriginalOrDurableCheckpoint() async throws {
        var boundaries = [JournalFaultPoint.intentCommitted, .filesystemApplied, .appliedCommitted].flatMap { point in [1, 2].map { (point, $0) } }
        boundaries.append((.checkpointCommitted, 1))
        for (point, ordinal) in boundaries {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-EngineCrash-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            let source = root.appendingPathComponent("sample.zip"), original = try XCTUnwrap(Data(base64Encoded: Self.fixture))
            try original.write(to: source)
            try probe(root, point: point, ordinal: ordinal)
            let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"))
            let interrupted = try await engine.interruptedOperations(); XCTAssertEqual(interrupted.count, 1)
            let id = try XCTUnwrap(interrupted.first?.id)
            let report = try await engine.recoverInterrupted(id)
            XCTAssertTrue(report.resolved, report.notices.joined(separator: "\n"))
            let repeated = try await engine.recoverInterrupted(id); XCTAssertTrue(repeated.resolved)
            let history = await engine.history()
            if point == .checkpointCommitted {
                XCTAssertEqual(Set(try ArchiveCatalog.read(source).members.map(\.path)), ["manual/readme.txt", "keep.txt"])
                XCTAssertEqual(history.count, 1)
                let result = await engine.undo(try XCTUnwrap(history.first), control: OperationControl())
                XCTAssertTrue(result.errors.isEmpty, result.errors.description)
            } else { XCTAssertTrue(history.isEmpty) }
            XCTAssertEqual(try Data(contentsOf: source), original, "The original archive must survive exactly: \(point) #\(ordinal)")
        }
    }
}
