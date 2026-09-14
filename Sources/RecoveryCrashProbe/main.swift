import Foundation
import ExplorerJournal
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

final class CrashCounter: @unchecked Sendable {
    let point: JournalFaultPoint?
    let occurrence: Int
    private let lock = NSLock()
    private var count = 0
    init(_ point: String, _ occurrence: Int) { self.point = JournalFaultPoint(rawValue: point); self.occurrence = occurrence }
    func hit(_ point: JournalFaultPoint) {
        lock.lock(); defer { lock.unlock() }
        guard point == self.point else { return }; count += 1
        if count == occurrence { _exit(73) } // No defer, destructors or SQLite close.
    }
}
let args = CommandLine.arguments
if args.count != 5 { fputs("Usage: RecoveryCrashProbe root mutate|recover faultPoint occurrence\n", stderr); exit(64) }
let root = URL(fileURLWithPath: args[1]), counter = CrashCounter(args[3], Int(args[4]) ?? 1)
do {
    let journal = try FileJournal(directory: root.appendingPathComponent("journal"), fault: { counter.hit($0) })
    if args[2] == "mutate" {
        let transaction = try journal.begin(title: "Crash replacement fixture")
        try transaction.move(root.appendingPathComponent("source"), to: root.appendingPathComponent(".stage"))
        try transaction.move(root.appendingPathComponent("destination"), to: root.appendingPathComponent(".backup"))
        try transaction.move(root.appendingPathComponent(".stage"), to: root.appendingPathComponent("destination"))
        try transaction.checkpoint(receipt: Data("retained-undo-receipt".utf8))
        try transaction.finish(receipt: Data("retained-undo-receipt".utf8))
    } else if args[2] == "recover" {
        for item in try journal.summaries() { _ = try journal.recover(item.id) }
    } else { exit(64) }
} catch { fputs(error.localizedDescription + "\n", stderr); exit(1) }
