import SwiftUI
import AppKit
import ExplorerCore

@MainActor final class RecoveryModel: ObservableObject {
    @Published var interrupted: [InterruptedFileOperation] = []
    @Published var receipts: [OperationReceipt] = []
    @Published var notice: String?
    @Published var artifacts: [URL] = []
    @Published var busy = false
    let engine: FileOperationEngine
    init(engine: FileOperationEngine = .shared) { self.engine = engine }
    func load() async {
        do { interrupted = try await engine.interruptedOperations(); receipts = await engine.history() }
        catch { notice = error.localizedDescription }
    }
}

/// Interrupted transactions and completed Undo receipts are separate. Recovery
/// does not silently accept ambiguous OS outcomes or delete retained staging.
@MainActor struct RecoveryView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var center = OperationCenter.shared
    @StateObject private var model: RecoveryModel
    @Environment(\.dismiss) private var dismiss
    @State private var pending: RecoveryAction?
    init(workspace: ExplorerWorkspace, model: RecoveryModel? = nil) {
        self.workspace = workspace; _model = StateObject(wrappedValue: model ?? RecoveryModel())
    }
    private var locked: Bool { model.busy || center.runningCount > 0 || center.historyBusy }
    private var confirmation: Binding<Bool> { Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ExplorerRule()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !model.interrupted.isEmpty { interruptedSection }
                    historySection
                    if !model.artifacts.isEmpty { retainedSection }
                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(22)
            }.frame(height: 420)
            ExplorerRule()
            HStack {
                Button("Show Recovery Store") { NSWorkspace.shared.open(FileOperationEngine.journalDirectory) }
                Spacer()
                Button("Refresh") { Task { await model.load() } }.disabled(locked)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
            }.buttonStyle(ExplorerButtonStyle()).padding(16)
        }.frame(width: 740).background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text)
            .task { await model.load() }
            .confirmationDialog(pending?.title ?? "Review recovery", isPresented: confirmation, titleVisibility: .visible) {
                if let action = pending { Button(action.button) { execute(action); pending = nil } }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: { Text(pending?.message ?? "") }
            .interactiveDismissDisabled(model.busy).accessibilityIdentifier("explorer.recovery")
    }
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: model.interrupted.isEmpty ? "clock.arrow.circlepath" : "exclamationmark.shield")
                .font(.system(size: 25, weight: .light)).foregroundStyle(model.interrupted.isEmpty ? Color.accentColor : .orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Recovery & history").font(.system(size: 20, weight: .semibold))
                Text("Durable checkpoints preserve completed work. Interrupted changes are reviewed separately from Undo history.")
                    .font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(); if model.busy { ProgressView().controlSize(.small) }
        }.padding(22)
    }
    private var interruptedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEEDS REVIEW").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.orange)
            Text("New mutations are paused until these transactions are recovered or explicitly acknowledged.").font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted)
            ForEach(model.interrupted) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(entry.title).font(.system(size: 13, weight: .semibold)); Spacer()
                        Text(entry.started.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(ExplorerDesign.muted)
                    }
                    Text("\(entry.pendingMutations) uncheckpointed record(s) · " + entry.state).font(.caption).foregroundStyle(ExplorerDesign.muted)
                    if let warning = entry.warning, !warning.isEmpty { Text(warning).font(.caption).textSelection(.enabled) }
                    HStack {
                        Button("Recover Safely…") { pending = .recover(entry.id) }.buttonStyle(ExplorerButtonStyle(primary: true))
                        Button("Keep Current Files…") { pending = .acknowledge(entry.id) }.buttonStyle(ExplorerButtonStyle())
                    }.disabled(locked)
                }.padding(15).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.orange.opacity(0.35), lineWidth: 1))
            }
        }
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COMPLETED CHECKPOINTS").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(ExplorerDesign.muted)
            if model.receipts.isEmpty {
                Label("No reversible operations recorded yet", systemImage: "tray").font(.system(size: 12)).foregroundStyle(ExplorerDesign.muted).padding(.vertical, 18)
            } else {
                ForEach(model.receipts) { receipt in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(receipt.title).font(.system(size: 12, weight: .medium))
                                Text("\(receipt.steps.count) reversible step(s) · " + receipt.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(ExplorerDesign.muted)
                            }
                            Spacer()
                            Button("Reverse…") { pending = .reverse(receipt) }.buttonStyle(ExplorerButtonStyle()).disabled(locked || !model.interrupted.isEmpty)
                        }
                        if let first = receipt.steps.first {
                            Text(first.source.path).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                        }
                    }.padding(13).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    private var retainedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("RETAINED FOR INSPECTION").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(ExplorerDesign.muted)
            ForEach(model.artifacts, id: \.self) { url in
                HStack {
                    Text(url.path).font(.system(size: 11)).textSelection(.enabled).lineLimit(3).truncationMode(.middle); Spacer()
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(ExplorerButtonStyle())
                }
            }
        }
    }
    private func execute(_ action: RecoveryAction) {
        guard !locked else { return }
        model.busy = true; center.historyBusy = true
        let row = OperationRow(title: action.title)
        if case .reverse = action { center.jobs.insert(row, at: 0) }
        Task { @MainActor in
            defer {
                model.busy = false; center.historyBusy = false; center.revision += 1; row.finished = true
                if !center.jobs.contains(where: { $0.id == row.id }) { center.jobs.insert(row, at: 0) }
            }
            do {
                switch action {
                case .recover(let id):
                    let report = try await model.engine.recoverInterrupted(id)
                    model.artifacts = report.retainedArtifacts
                    model.notice = (report.resolved ? "Recovery completed. Checkpointed work was retained." : "Recovery stopped to protect changed files.") + "\n" + report.notices.joined(separator: "\n")
                    row.status = report.resolved ? "Recovered" : "Review required"
                    if !report.resolved { row.errors = report.notices }
                case .acknowledge(let id):
                    try await model.engine.acknowledgeInterrupted(id)
                    model.notice = "Current files retained. The journal records your acknowledgement; no filesystem changes were made."
                    row.status = "Acknowledged"
                case .reverse(let receipt):
                    let result = await model.engine.undo(receipt, control: row.control)
                    row.errors = result.errors; row.cancelled = result.cancelled || row.control.isCancelled
                    row.status = result.errors.isEmpty ? "Reversed" : "Recovery stopped"
                    center.undoStack.removeAll { $0.id == receipt.id }; center.redoStack.removeAll { $0.id == receipt.id }
                    if !result.receipt.steps.isEmpty { center.undoStack.append(result.receipt) }
                    if !result.remaining.isEmpty { var rest = receipt; rest.steps = result.remaining; center.undoStack.append(rest) }
                    model.notice = result.errors.isEmpty ? "The completed inverse is recorded in history." : result.errors.joined(separator: "\n")
                }
            } catch { row.errors = [error.localizedDescription]; row.status = "Review required"; model.notice = error.localizedDescription }
            await model.load(); workspace.current.refresh()
        }
    }
}
private enum RecoveryAction {
    case recover(UUID), acknowledge(UUID), reverse(OperationReceipt)
    var title: String { switch self { case .recover: return "Recover interrupted work?"; case .acknowledge: return "Keep the current filesystem?"; case .reverse: return "Reverse this operation?" } }
    var button: String { switch self { case .recover: return "Recover Safely"; case .acknowledge: return "Keep Current Files"; case .reverse: return "Reverse Operation" } }
    var message: String {
        switch self {
        case .recover: return "Only changes after the last durable checkpoint are compensated. Changed objects and occupied paths stop recovery. Unknown native Trash or deletion outcomes require inspection."
        case .acknowledge: return "Confirm only after reviewing all affected files. This accepts the current state without compensating changes or deleting staging. The journal and audit record are retained."
        case .reverse: return "File identities and destination vacancies are checked before each reversible step. Newer files will not be overwritten."
        }
    }
}
