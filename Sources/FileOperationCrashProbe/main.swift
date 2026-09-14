import Foundation
import ExplorerCore
import ExplorerJournal
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A disposable integration process. _exit skips Swift defers and SQLite close.
@main struct FileOperationCrashProbe {
    final class Trigger: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private var armed = true
        let point: JournalFaultPoint
        let ordinal: Int
        init(point: JournalFaultPoint, ordinal: Int, armed: Bool) { self.point = point; self.ordinal = ordinal; self.armed = armed }
        func arm() { lock.lock(); count = 0; armed = true; lock.unlock() }
        func hit(_ actual: JournalFaultPoint) {
            lock.lock(); defer { lock.unlock() }
            guard armed, actual == point else { return }; count += 1
            if count == ordinal { _exit(73) }
        }
    }
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 4, let point = JournalFaultPoint(rawValue: args[2]), let ordinal = Int(args[3]), (1...32).contains(ordinal) else { _exit(64) }
        let root = URL(fileURLWithPath: args[0]).standardizedFileURL
        guard root.lastPathComponent.hasPrefix("MacExplorer-EngineCrash-"),
              root.deletingLastPathComponent().resolvingSymlinksInPath().path == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path,
              ["copy", "move", "rename", "create", "undo"].contains(args[1]) else { _exit(64) }
        do {
            let trigger = Trigger(point: point, ordinal: ordinal, armed: args[1] != "undo")
            let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"), journalFault: { trigger.hit($0) })
            let source = root.appendingPathComponent("from/file.txt"), destination = root.appendingPathComponent("to")
            let result: FileJobResult
            switch args[1] {
            case "rename": result = await engine.rename([(root.appendingPathComponent("a.txt"), "b.txt"), (root.appendingPathComponent("b.txt"), "a.txt")], control: OperationControl())
            case "create": result = await engine.run(FileJob(.createFolder, destination: destination.appendingPathComponent("New Folder")), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.cancel) })
            case "undo":
                let moved = await engine.run(FileJob(.move, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.replace) })
                guard moved.errors.isEmpty else { throw ExplorerError.message(moved.errors.joined(separator: "\n")) }
                trigger.arm(); result = await engine.undo(moved.receipt, control: OperationControl())
            default: result = await engine.run(FileJob(args[1] == "move" ? .move : .copy, sources: [source], destination: destination), control: OperationControl(), progress: { _ in }, resolve: { _ in CollisionAnswer(.replace) })
            }
            if !result.errors.isEmpty { FileHandle.standardError.write(Data(result.errors.joined(separator: "\n").utf8)) }
            _exit(result.errors.isEmpty ? 0 : 1)
        } catch { FileHandle.standardError.write(Data(error.localizedDescription.utf8)); _exit(1) }
    }
}
