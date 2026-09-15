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
            else { ScrollView { LazyVStack(spacing: 12) { ForEach(center.jobs) { job in OperationCard(job: job) } }.padding(2) }.frame(height: 400) }
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
            if job.progress.totalBytes != nil || job.progress.bytes > 0 || job.progress.phase == .calculating || job.progress.phase == .copying { OperationTransferDetails(job: job) }
            else if !job.finished { ProgressView(value: Double(job.progress.completed), total: Double(max(1, job.progress.total))) }
            HStack { Text(job.status); Spacer(); if job.progress.total > 1 { Text("\(job.progress.completed) / \(job.progress.total) completed").monospacedDigit() } }.font(.caption).foregroundStyle(.secondary)
            if !job.finished { Text(job.progress.name).font(.caption).lineLimit(1).foregroundStyle(.secondary) }
            if !job.errors.isEmpty { DisclosureGroup("\(job.errors.count) error(s)") { ForEach(Array(job.errors.enumerated()), id: \.offset) { _, error in Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) } } }
        }.padding(15).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(ExplorerDesign.separator))
    }
}
