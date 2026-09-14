import SwiftUI
import AppKit
import ExplorerCore

/// One status surface for both Explorer and Commander layouts. Activity is a
/// transient popover: observing a transfer never makes the browser modal.
struct ExplorerStatusBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var center = OperationCenter.shared
    var compact = false
    var active = true
    @State private var volume: StatusVolume?
    @State private var showActivity = false
    @State private var showVolume = false
    private var selection: [FileEntry] { workspace.selected }
    private var selectedBytes: Int64 {
        selection.lazy.filter { !$0.isDirectory }.reduce(0) { total, entry in
            let (sum, overflow) = total.addingReportingOverflow(max(0, entry.size)); return overflow ? .max : sum
        }
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 9) {
                if compact {
                    Circle().fill(active ? Color.accentColor : ExplorerDesign.muted.opacity(0.35))
                        .frame(width: 5, height: 5).accessibilityHidden(true)
                }
                if tab.loading { ProgressView().controlSize(.mini).accessibilityLabel("Loading files") }
                Text("\(tab.entries.count) " + (tab.query.isEmpty ? "items" : "matches")).monospacedDigit().fixedSize()
                if !selection.isEmpty {
                    Text("·").accessibilityHidden(true)
                    Text("\(selection.count) selected").monospacedDigit().lineLimit(1)
                    if geometry.size.width > 600 && selection.contains(where: { !$0.isDirectory }) {
                        Text(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file)).monospacedDigit().fixedSize()
                            .help("Combined size of selected files; folder contents are not included")
                    }
                }
                Spacer(minLength: 0)
                if !compact && geometry.size.width > 1000, let volume {
                    Button { showVolume.toggle() } label: {
                        Text(ByteCountFormatter.string(fromByteCount: volume.available, countStyle: .file) + " available").monospacedDigit().lineLimit(1)
                    }.help("Storage information for " + volume.name)
                        .popover(isPresented: $showVolume, arrowEdge: .bottom) { StatusVolumeView(volume: volume) }
                }
                if !compact {
                    Button { showActivity.toggle() } label: {
                        if let job = center.jobs.first(where: { !$0.finished }) { StatusOperationBadge(job: job) }
                        else {
                            Label(center.jobs.contains(where: { !$0.errors.isEmpty }) ? "Review operations" : "Activity",
                                  systemImage: center.jobs.contains(where: { !$0.errors.isEmpty }) ? "exclamationmark.circle" : "arrow.up.arrow.down.circle")
                        }
                    }.help("Show file activity without leaving this folder")
                        .popover(isPresented: $showActivity, arrowEdge: .bottom) { FileActivityPopover() }
                }
                Menu {
                    Picker("File view", selection: $tab.options.view) {
                        ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                } label: { Image(systemName: tab.options.view.symbol).frame(width: 28, height: 26) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("File view: " + tab.options.view.rawValue).help("Change file view")
            }.font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted).buttonStyle(.plain)
                .padding(.horizontal, 12).frame(height: 30).background(ExplorerDesign.chrome)
        }.frame(height: 30)
            .task(id: "\(workspace.destination?.path ?? "")|\(center.revision)") {
                volume = nil; guard let url = workspace.destination else { return }
                let value = await Task.detached(priority: .utility) { StatusVolume.read(url) }.value
                if !Task.isCancelled { volume = value }
            }
            .accessibilityIdentifier(compact ? "explorer.paneStatus" : "explorer.windowStatus")
    }
}
private struct StatusOperationBadge: View {
    @ObservedObject var job: OperationRow
    private var fraction: Double? {
        guard let total = job.progress.totalBytes, total > 0 else { return nil }
        return max(0, min(1, Double(job.progress.logicalBytes) / Double(total)))
    }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: job.paused ? "pause.circle" : "arrow.up.arrow.down.circle").foregroundStyle(Color.accentColor)
            Text(job.paused ? "Paused" : job.progress.phase.rawValue).lineLimit(1)
            if let fraction {
                ProgressView(value: fraction).progressViewStyle(.linear).frame(width: 36).accessibilityHidden(true)
                Text("\(Int(fraction * 100))%").monospacedDigit()
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(job.title + ": " + job.status)
    }
}

struct FileActivityPopover: View {
    @ObservedObject private var center = OperationCenter.shared
    @Environment(\.dismiss) private var dismiss
    private var running: [OperationRow] { center.jobs.filter { !$0.finished } }
    private var recent: [OperationRow] { Array(center.jobs.filter(\.finished).prefix(3)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("File activity").font(.system(size: 14, weight: .semibold))
                Spacer()
                if !running.isEmpty { Text("\(running.count) active").font(.caption).foregroundStyle(ExplorerDesign.muted) }
                Button("Done") { dismiss() }.font(.caption).keyboardShortcut(.cancelAction)
            }.padding(16)
            ExplorerRule()
            if center.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 28, weight: .light)).foregroundStyle(ExplorerDesign.muted)
                    Text("No file operations yet").font(.system(size: 12, weight: .medium))
                    Text("Copy and move progress appears here.\nYou can keep browsing while transfers run.")
                        .font(.caption).foregroundStyle(ExplorerDesign.muted).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(running) { job in OperationCard(job: job) }
                        if !recent.isEmpty {
                            Text("RECENT").font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(ExplorerDesign.muted).padding(.top, 4)
                            ForEach(recent) { job in RecentActivityRow(job: job) }
                        }
                    }.padding(14)
                }.frame(maxHeight: 410)
                ExplorerRule()
                HStack {
                    Text("Completed work is retained when you cancel.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
                    Spacer()
                    Button("Clear completed") { center.jobs.removeAll { $0.finished } }.font(.system(size: 10)).disabled(recent.isEmpty)
                }.padding(14)
            }
        }.frame(width: 400).background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text)
            .accessibilityIdentifier("explorer.fileActivity")
    }
}
private struct RecentActivityRow: View {
    @ObservedObject var job: OperationRow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: !job.errors.isEmpty ? "exclamationmark.triangle" : job.cancelled ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(!job.errors.isEmpty ? Color.orange : ExplorerDesign.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(job.status).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !job.errors.isEmpty {
                DisclosureGroup("\(job.errors.count) notice(s)") {
                    Text(job.errors.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.font(.caption).foregroundStyle(ExplorerDesign.muted)
            }
        }.padding(10).background(ExplorerDesign.chrome, in: RoundedRectangle(cornerRadius: 8))
    }
}
struct StatusVolume: Sendable {
    let name: String
    let available: Int64
    let total: Int64
    let format: String
    let readOnly: Bool
    static func read(_ url: URL) -> StatusVolume? {
        guard let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedFormatDescriptionKey, .volumeIsReadOnlyKey]),
              let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return StatusVolume(name: values.volumeName ?? url.lastPathComponent, available: max(0, available),
            total: Int64(total), format: values.volumeLocalizedFormatDescription ?? "Filesystem", readOnly: values.volumeIsReadOnly ?? false)
    }
}
struct StatusVolumeView: View {
    let volume: StatusVolume
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(volume.name, systemImage: "internaldrive").font(.system(size: 14, weight: .semibold))
            ProgressView(value: Double(max(0, volume.total - volume.available)), total: Double(max(1, volume.total)))
            Text(ByteCountFormatter.string(fromByteCount: volume.available, countStyle: .file) + " available of " + ByteCountFormatter.string(fromByteCount: volume.total, countStyle: .file))
                .font(.system(size: 12)).monospacedDigit()
            Text(volume.format + " · " + (volume.readOnly ? "Read only" : "Read and write"))
                .font(.caption).foregroundStyle(ExplorerDesign.muted)
            Text("Available space is reported by macOS and may include reclaimable storage.")
                .font(.caption2).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 310).background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text)
    }
}
