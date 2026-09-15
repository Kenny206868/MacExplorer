import AppKit
import Combine
import ExplorerCore

/// Clipboard IPC is sampled once per cut generation, never once per drawn row.
/// Commands still revalidate the exact generation before moving source files.
@MainActor final class FileClipboard: ObservableObject {
    static let shared = FileClipboard()
    struct CutTicket { let generation: Int; let sources: [URL] }
    @Published private(set) var revision = 0
    private let board: NSPasteboard
    private var cutURLs: [URL] = []
    private var cutPaths = Set<String>()
    private var cutChangeCount = -1
    private var reserved = false
    private var timer: Timer?
    private(set) var generationReads = 0
    init(pasteboard: NSPasteboard = .general) { board = pasteboard }
    func write(_ urls: [URL], cut: Bool) {
        board.clearContents(); let written = board.writeObjects(urls as [NSURL])
        cutURLs = cut && written ? urls : []; rebuildMembership()
        cutChangeCount = cutURLs.isEmpty ? -1 : readGeneration()
        reserved = false; revision += 1; updateObservation()
    }
    var contents: (urls: [URL], isCut: Bool) {
        refresh()
        let objects = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [NSURL] ?? []
        let urls = objects.map { $0 as URL }
        return (urls, readGeneration() == cutChangeCount && !cutURLs.isEmpty && Set(urls.map { $0.standardizedFileURL.path }) == cutPaths)
    }
    /// Pure O(1) membership; visual expiry is sampled at 250 ms while a cut is
    /// active. Paste/move commands perform immediate generation validation.
    func isCut(_ url: URL) -> Bool { cutPaths.contains(url.standardizedFileURL.path) }
    func reserveCut() -> CutTicket? {
        guard !reserved, contents.isCut else { return nil }; reserved = true
        return CutTicket(generation: cutChangeCount, sources: cutURLs)
    }
    func finish(_ ticket: CutTicket, moved: [URL]) {
        guard ticket.generation == cutChangeCount, readGeneration() == ticket.generation else { refresh(); return }
        reserved = false
        let roots = moved.map { $0.standardizedFileURL.pathComponents }
        let remaining = ticket.sources.filter { url in !roots.contains { url.standardizedFileURL.pathComponents.starts(with: $0) } }
        guard remaining.count != ticket.sources.count else { revision += 1; return }
        board.clearContents()
        let written = remaining.isEmpty || board.writeObjects(remaining as [NSURL])
        cutURLs = written ? remaining : []; rebuildMembership(); cutChangeCount = cutURLs.isEmpty ? -1 : readGeneration()
        revision += 1; updateObservation()
    }
    func refresh() {
        guard !cutURLs.isEmpty else { return }
        if readGeneration() != cutChangeCount {
            cutURLs = []; cutPaths = []; cutChangeCount = -1; reserved = false; revision += 1; updateObservation()
        }
    }
    private func readGeneration() -> Int { generationReads += 1; return board.changeCount }
    private func rebuildMembership() { cutPaths = Set(cutURLs.map { $0.standardizedFileURL.path }) }
    private func updateObservation() {
        if cutURLs.isEmpty { timer?.invalidate(); timer = nil; return }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    deinit { timer?.invalidate() }
}
