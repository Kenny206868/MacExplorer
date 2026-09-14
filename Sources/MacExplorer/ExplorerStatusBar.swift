import SwiftUI
import AppKit
import ExplorerCore

/// A common status model for one or two panes. Folder metadata size is never
/// presented as the size of its descendants, and missing volume data is not
/// replaced with invented capacity or a green success indicator.
struct ExplorerStatusBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var center = OperationCenter.shared
    var compact = false
    var active = true
    @State private var capacity: Int64?
    private var selectedFiles: [FileEntry] { workspace.selected.filter { !$0.isDirectory } }
    private var selectedBytes: Int64 {
        selectedFiles.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(max(0, entry.size)); return overflow ? .max : sum
        }
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 10) {
                if compact { Circle().fill(active ? Color.accentColor : ExplorerDesign.muted.opacity(0.35)).frame(width: 5, height: 5).accessibilityHidden(true) }
                if tab.loading { ProgressView().controlSize(.mini) }
                Text("\(tab.entries.count) items").monospacedDigit().fixedSize()
                if !workspace.selected.isEmpty {
                    Text("\(workspace.selected.count) selected").monospacedDigit().lineLimit(1)
                    if geometry.size.width > 600 && !selectedFiles.isEmpty {
                        Text(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)).monospacedDigit().fixedSize()
                            .help("Combined size of selected files; folder contents are not included")
                    }
                }
                Spacer(minLength: 0)
                if !compact && geometry.size.width > 1000, let capacity {
                    Text(ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file) + " available").monospacedDigit().lineLimit(1)
                }
                if !compact { operations }
                Menu {
                    Picker("File view", selection: $tab.options.view) {
                        ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Image(systemName: tab.options.view.symbol).frame(width: 28, height: 26)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("File view: " + tab.options.view.rawValue).help("Change file view")
            }.font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted).buttonStyle(.plain)
                .padding(.horizontal, 12).frame(height: 30).background(ExplorerDesign.chrome)
        }.frame(height: 30)
            .task(id: "\(workspace.destination?.path ?? "")|\(center.revision)") {
                capacity = nil; guard let url = workspace.destination else { return }
                let value = await Task.detached(priority: .utility) { () -> Int64? in
                    let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                    return values?.volumeAvailableCapacityForImportantUsage ?? values?.volumeAvailableCapacity.map(Int64.init)
                }.value
                if !Task.isCancelled { capacity = value.map { max(0, $0) } }
            }
            .accessibilityIdentifier(compact ? "explorer.paneStatus" : "explorer.windowStatus")
    }
    @ViewBuilder private var operations: some View {
        if let job = center.jobs.first(where: { !$0.finished }) {
            StatusOperationBadge(job: job, workspace: workspace)
        } else {
            Button { workspace.sheet = .operations } label: {
                Label(center.jobs.contains(where: { !$0.errors.isEmpty }) ? "Review operations" : "Operations", systemImage: center.jobs.contains(where: { !$0.errors.isEmpty }) ? "exclamationmark.circle" : "arrow.up.arrow.down.circle")
            }.help("View file transfers and operation history")
        }
    }
}
private struct StatusOperationBadge: View {
    @ObservedObject var job: OperationRow
    @ObservedObject var workspace: ExplorerWorkspace
    private var fraction: Double? {
        guard let total = job.progress.totalBytes, total > 0 else { return nil }
        return max(0, min(1, Double(job.progress.logicalBytes) / Double(total)))
    }
    var body: some View {
        Button { workspace.sheet = .operations } label: {
            HStack(spacing: 6) {
                Image(systemName: job.paused ? "pause.circle" : "arrow.up.arrow.down.circle").foregroundStyle(Color.accentColor)
                Text(job.paused ? "Paused" : job.progress.phase.rawValue).lineLimit(1)
                if let fraction { Text("\(Int(fraction * 100))%").monospacedDigit() }
            }
        }.help(job.title + " · " + job.progress.name).accessibilityLabel(job.title + ": " + job.status)
    }
}
