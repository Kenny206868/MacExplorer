import AppKit
import Combine
import ExplorerCore

/// Cut intent belongs to a particular pasteboard generation, not to a path. A
/// cancelled/partial move keeps the unprocessed items cut, and completion never
/// overwrites a newer clipboard written by this app or another application.
@MainActor final class FileClipboard: ObservableObject {
    static let shared = FileClipboard()
    struct CutTicket { let generation: Int; let sources: [URL] }
    @Published private(set) var revision = 0
    private var cutURLs: [URL] = []
    private var cutChangeCount = -1
    private var reserved = false

    func write(_ urls: [URL], cut: Bool) {
        let board = NSPasteboard.general
        board.clearContents(); board.writeObjects(urls as [NSURL])
        cutURLs = cut ? urls : []; cutChangeCount = cut ? board.changeCount : -1
        reserved = false; revision += 1
    }
    var contents: (urls: [URL], isCut: Bool) {
        let board = NSPasteboard.general
        let objects = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        let urls = objects.map { $0 as URL }
        return (urls, board.changeCount == cutChangeCount && !cutURLs.isEmpty && Set(urls) == Set(cutURLs))
    }
    func isCut(_ url: URL) -> Bool { NSPasteboard.general.changeCount == cutChangeCount && cutURLs.contains(url) }
    func reserveCut() -> CutTicket? {
        guard !reserved, contents.isCut else { return nil }
        reserved = true
        return CutTicket(generation: cutChangeCount, sources: cutURLs)
    }
    func finish(_ ticket: CutTicket, moved: [URL]) {
        guard ticket.generation == cutChangeCount, NSPasteboard.general.changeCount == ticket.generation else { refresh(); return }
        reserved = false
        let completed = Set(moved)
        let remaining = ticket.sources.filter { url in
            !completed.contains { root in
                url.standardizedFileURL.pathComponents.starts(with: root.standardizedFileURL.pathComponents)
            }
        }
        guard remaining.count != ticket.sources.count else { revision += 1; return }
        let board = NSPasteboard.general
        board.clearContents()
        if !remaining.isEmpty { board.writeObjects(remaining as [NSURL]) }
        cutURLs = remaining; cutChangeCount = remaining.isEmpty ? -1 : board.changeCount
        revision += 1
    }
    func refresh() {
        if NSPasteboard.general.changeCount != cutChangeCount && !cutURLs.isEmpty {
            cutURLs = []; cutChangeCount = -1; reserved = false; revision += 1
        }
    }
}
