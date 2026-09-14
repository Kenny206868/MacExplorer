import SwiftUI
import AppKit
import ExplorerCore

struct OperationsView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var center = OperationCenter.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: "File operations", subtitle: "Operations are serialized across every window. Copies pause at native data checkpoints. Atomic renames and system calls finish at safe boundaries; completed items are retained.")
            if center.jobs.isEmpty { ContentUnavailableView("No operations yet", systemImage: "checkmark.circle", description: Text("Copies, moves, renames, archives, and recovery actions appear here.")) }
            else {
                ScrollView { LazyVStack(spacing: 12) { ForEach(center.jobs) { job in OperationCard(job: job) } }.padding(2) }.frame(height: 400)
            }
            HStack {
                Button("Clear Completed") { center.jobs.removeAll { $0.finished } }.disabled(center.jobs.allSatisfy { !$0.finished })
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(25).frame(width: 650)
    }
}
struct OperationCard: View {
    @ObservedObject var job: OperationRow
    private var symbol: String {
        if !job.finished { return "doc.on.doc" }
        if job.cancelled { return "xmark.circle" }
        return job.errors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).foregroundStyle(job.cancelled ? Color(nsColor: .secondaryLabelColor) : job.errors.isEmpty ? Color.accentColor : Color.orange)
                Text(job.title).fontWeight(.semibold); Spacer()
                if !job.finished {
                    Button { job.togglePause() } label: { Image(systemName: job.paused ? "play.fill" : "pause.fill") }.help(job.paused ? "Resume" : "Pause at the next safe checkpoint").disabled(job.control.isCancelled)
                    Button { job.cancel() } label: { Image(systemName: "xmark") }.help("Cancel remaining work").disabled(job.control.isCancelled)
                }
            }
            if job.progress.totalBytes != nil || job.progress.bytes > 0 || job.progress.phase == .calculating || job.progress.phase == .copying {
                OperationTransferDetails(job: job)
            } else if !job.finished { ProgressView(value: Double(job.progress.completed), total: Double(max(1, job.progress.total))) }
            HStack { Text(job.status); Spacer(); if job.progress.total > 1 { Text("\(job.progress.completed) / \(job.progress.total) completed").monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
            if !job.finished { Text(job.progress.name).font(.caption).lineLimit(1).foregroundStyle(.secondary) }
            if !job.errors.isEmpty { DisclosureGroup("\(job.errors.count) error(s)") { ForEach(Array(job.errors.enumerated()), id: \.offset) { _, error in Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) } } }
        }.padding(15).background(.quaternary.opacity(0.15), in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }
}

struct RecoveryView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject private var center = OperationCenter.shared
    @Environment(\.dismiss) private var dismiss
    @State private var receipts: [OperationReceipt] = []
    @State private var selected: OperationReceipt.ID?
    @State private var status: String?
    @State private var busy = false
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeading(title: "Recovery history", subtitle: "Completed reversible steps are saved on disk. Restore refuses changed files and occupied destinations. A receipt is a recovery record, not a backup of file contents.")
            List(receipts, selection: $selected) { receipt in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(receipt.title).fontWeight(.medium); Spacer(); Text(receipt.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
                    Text("\(receipt.steps.count) reversible step(s)").font(.caption).foregroundStyle(.secondary)
                    if let first = receipt.steps.first { Text(first.source.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }.padding(.vertical, 4).tag(receipt.id)
            }.frame(height: 330)
            if let status { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Button("Open Recovery Folder") { NSWorkspace.shared.open(FileOperationEngine.journalDirectory) }
                Spacer()
                Button("Restore Selected…") { confirm = true }.disabled(selected == nil || busy || center.runningCount > 0 || center.historyBusy)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).disabled(busy)
            }
        }.padding(25).frame(width: 690).task { receipts = await FileOperationEngine.shared.history() }
            .confirmationDialog("Reverse the selected file operation?", isPresented: $confirm, titleVisibility: .visible) { Button("Restore") { restore() }; Button("Cancel", role: .cancel) {} } message: { Text("MacExplorer verifies the recorded file identity first. If a file changed or a destination is occupied, recovery stops without overwriting it.") }
            .interactiveDismissDisabled(busy)
    }
    private func restore() {
        guard let receipt = receipts.first(where: { $0.id == selected }) else { return }
        busy = true; center.historyBusy = true
        let row = OperationRow(title: "Recover " + receipt.title); center.jobs.insert(row, at: 0)
        Task {
            let result = await FileOperationEngine.shared.undo(receipt, control: row.control)
            row.cancelled = result.cancelled || row.control.isCancelled
            row.finished = true; row.errors = result.errors; row.status = result.errors.isEmpty ? "Recovered" : "Recovery stopped"
            if !result.receipt.steps.isEmpty { center.undoStack.append(result.receipt) }
            status = result.errors.isEmpty ? "Recovery completed. Its inverse is available through Undo." : result.errors.joined(separator: "\n")
            center.revision += 1; center.historyBusy = false; busy = false
            receipts = await FileOperationEngine.shared.history(); workspace.current.refresh()
        }
    }
}
