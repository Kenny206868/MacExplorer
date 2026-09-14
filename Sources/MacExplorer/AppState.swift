import SwiftUI
import Combine
import AppKit
import ExplorerCore

struct Preferences: Codable {
    var showHidden = false
    var showExtensions = true
    var checkboxes = false
    var compact = false
    var inspector = true
    var previewPane = false
    var singleClickOpen = false
    var restoreTabs = true
    var confirmTrash = false
    var theme = "system"
    var startLocation = "Home"
    var recursiveSearch = true
    var folders: [String: FolderOptions] = [:]
    var pins: [Bookmark] = ["Desktop", "Downloads", "Documents", "Pictures"].map { Bookmark(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0)) }
    var recent: [Bookmark] = []
    var savedSearches: [String] = []
    var tabs: [Location] = [.home]
}

@MainActor final class PreferenceStore: ObservableObject {
    static let shared = PreferenceStore()
    @Published var value: Preferences { didSet { save() } }
    private let key = "MacExplorer.preferences.v1"
    init() { value = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences() }
    private func save() { if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) } }
    func pin(_ url: URL) { if !value.pins.contains(where: { $0.url == url }) { value.pins.append(Bookmark(url)) } }
    func unpin(_ url: URL) { value.pins.removeAll { $0.url == url } }
    func visit(_ url: URL) { value.recent.removeAll { $0.url == url }; value.recent.insert(Bookmark(url), at: 0); value.recent = Array(value.recent.prefix(200)) }
    func folderOptions(_ location: Location) -> FolderOptions { value.folders[location.directory?.path ?? location.title] ?? FolderOptions() }
    func remember(_ location: Location, _ options: FolderOptions) { value.folders[location.directory?.path ?? location.title] = options }
    var colorScheme: ColorScheme? { value.theme == "dark" ? .dark : value.theme == "light" ? .light : nil }
}

@MainActor final class OperationRow: ObservableObject, Identifiable {
    let id: UUID
    let title: String
    let started = Date()
    let control = OperationControl()
    @Published var progress = FileProgress(completed: 0, total: 1, name: "Queued")
    @Published var status = "Queued"
    @Published var statistics = TransferStatistics()
    var cancellationAction: (() -> Void)?
    @Published var errors: [String] = []
    @Published var paused = false
    @Published var finished = false
    @Published var cancelled = false
    init(id: UUID = UUID(), title: String) { self.id = id; self.title = title }
    func cancel() { control.cancel(); statistics.suspend(); status = "Cancelling…"; cancellationAction?() }
    func acceptProgress(_ value: FileProgress) {
        guard !finished, value.sequence >= progress.sequence, value.timestamp >= progress.timestamp else { return }
        if value.phase != .copying || progress.phase != .copying { statistics.suspend() }
        progress = value
        statistics.record(bytes: value.bytes, at: value.timestamp, paused: paused || value.phase != .copying)
        if !paused && !control.isCancelled { status = value.phase.rawValue }
    }
    func togglePause() { paused.toggle(); statistics.suspend(); control.setPaused(paused); status = paused ? "Paused (at the next safe checkpoint)" : "Running" }
}
struct ConflictPrompt: Identifiable {
    let id = UUID()
    let collision: FileCollision
    let operationID: UUID
    let continuation: CheckedContinuation<CollisionAnswer, Never>
}
@MainActor final class OperationCenter: ObservableObject {
    static let shared = OperationCenter()
    @Published var jobs: [OperationRow] = []
    @Published var undoStack: [OperationReceipt] = []
    @Published var redoStack: [OperationReceipt] = []
    @Published var revision = 0
    @Published var historyBusy = false
    var runningCount: Int { jobs.filter { !$0.finished }.count }
    func submit(_ job: FileJob, owner: ExplorerWorkspace, cutTicket: FileClipboard.CutTicket? = nil, completion: ((FileJobResult) -> Void)? = nil) {
        let origin = owner.current, location = owner.current.location
        let row = OperationRow(id: job.id, title: job.title), control = OperationControl()
        // Keep the row's cooperative control as the sole operation control.
        _ = control
        jobs.insert(row, at: 0)
        let jobControl = row.control
        row.cancellationAction = { [weak owner] in if owner?.conflict?.operationID == job.id { owner?.answerCollision(.cancel) } }
        Task {
            let result = await FileOperationEngine.shared.run(job, control: jobControl, progress: { [weak row] progress in
                Task { @MainActor in guard let row, !row.finished else { return }; row.acceptProgress(progress) }
            }, resolve: { [weak owner] collision in
                guard let owner else { return CollisionAnswer(.cancel) }
                return await owner.resolve(collision, operationID: job.id, control: jobControl)
            })
            complete(row, result: result)
            if let cutTicket { FileClipboard.shared.finish(cutTicket, moved: result.completedSources) }
            completion?(result)
            if origin.location == location { if result.outputs.isEmpty { origin.refresh() } else { origin.refresh(selecting: result.outputs) } }
        }
    }
    func rename(_ mapping: [(URL, String)], owner: ExplorerWorkspace) {
        let origin = owner.current, location = owner.current.location
        let row = OperationRow(title: "Rename \(mapping.count) item(s)"); jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.rename(mapping, control: row.control)
            complete(row, result: result)
            if origin.location == location { if result.outputs.isEmpty { origin.refresh() } else { origin.refresh(selecting: result.outputs) } }
        }
    }
    private func complete(_ row: OperationRow, result: FileJobResult) {
        if let final = result.finalProgress { row.acceptProgress(final) }
        row.cancellationAction = nil; row.paused = false; row.control.setPaused(false)
        row.cancelled = result.cancelled || row.control.isCancelled; row.errors = result.errors; row.finished = true
        row.status = result.cancelled ? "Cancelled — completed items were retained" : result.errors.isEmpty ? "Completed" : "Completed with errors"
        if !result.skippedSources.isEmpty { row.status += " — \(result.skippedSources.count) skipped" }
        if !result.receipt.steps.isEmpty { undoStack.append(result.receipt); redoStack.removeAll() }
        revision += 1
        if jobs.count > 100 { jobs = Array(jobs.filter { !$0.finished } + jobs.filter(\.finished).prefix(100)) }
    }
    func undo(redo: Bool = false) {
        guard !historyBusy, runningCount == 0, let receipt = redo ? redoStack.popLast() : undoStack.popLast() else { return }
        historyBusy = true
        let row = OperationRow(title: (redo ? "Redo " : "Undo ") + receipt.title); jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.undo(receipt, control: row.control)
            row.cancelled = result.cancelled || row.control.isCancelled
            row.finished = true; row.errors = result.errors; row.status = result.errors.isEmpty ? "Completed" : "Stopped to protect changes"
            if !result.receipt.steps.isEmpty { if redo { undoStack.append(result.receipt) } else { redoStack.append(result.receipt) } }
            if !result.remaining.isEmpty {
                var remaining = OperationReceipt(title: receipt.title, steps: result.remaining); remaining.renameBatch = receipt.renameBatch
                if redo { redoStack.append(remaining) } else { undoStack.append(remaining) }
            }
            historyBusy = false; revision += 1
        }
    }
}
struct MessageBox: Identifiable { let id = UUID(); let title: String; let message: String }
enum ExplorerSheet: String, Identifiable { case newFolder, newFile, rename, properties, tags, connect, operations, recovery, archive, fileActions, keyboardHelp; var id: String { rawValue } }
