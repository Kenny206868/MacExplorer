import SwiftUI
import AppKit
import ExplorerCore

/// A stable footer: selection on the leading edge, real storage and activity
/// on the trailing edge. Expensive summaries are cached by the tab, not rebuilt
/// for hover/focus/progress publications. Compact panes use the same semantics.
struct ExplorerStatusBar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var center = OperationCenter.shared
    @ObservedObject private var settings = CommanderPreferences.shared
    @ObservedObject private var input = InputPreferences.shared
    var compact = false
    var active = true
    @State private var volume: StatusVolume?
    @State private var showSelection = false
    @State private var showVolume = false
    private var height: CGFloat { input.touchFriendly ? 44 : compact ? 32 : 36 }
    private var storageURL: URL? { tab.location.directory ?? tab.location.archiveSource?.deletingLastPathComponent() }
    private var selectedCount: Int { tab.location.isArchive ? tab.archiveSelectionCount : tab.selectionStatistics.count }
    private var totalCount: Int { tab.location.isArchive ? tab.archiveItemCount : tab.entries.count }
    private var summaryText: String {
        selectedCount > 0 ? "\(selectedCount) of \(totalCount) selected" : "\(totalCount) " + (tab.query.isEmpty ? "items" : "matches")
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 10) {
                if compact {
                    Capsule().fill(active ? Color.accentColor : ExplorerDesign.muted.opacity(0.4)).frame(width: 3, height: 12).accessibilityHidden(true)
                }
                if tab.loading || tab.selectionMatching { ProgressView().controlSize(.mini).accessibilityLabel(tab.selectionMatching ? "Matching selection" : "Loading files") }
                Button { showSelection.toggle() } label: {
                    HStack(spacing: 7) {
                        if !compact { Image(systemName: selectedCount > 0 ? "checkmark.circle.fill" : "folder").foregroundStyle(selectedCount > 0 ? Color.accentColor : ExplorerDesign.muted) }
                        Text(summaryText).monospacedDigit().lineLimit(1)
                        if selectedCount > 0 && !tab.location.isArchive && geometry.size.width > (compact ? 480 : 850) {
                            Text(byteText).monospacedDigit().foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                        }
                    }.frame(minHeight: height - 4).contentShape(Rectangle())
                }.popover(isPresented: $showSelection, arrowEdge: .bottom) { selectionDetails }
                    .help("Selection counts and logical file sizes; folder contents are not scanned")
                    .accessibilityIdentifier("explorer.selectionSummary")
                Spacer(minLength: 0)
                if let volume, (!compact || settings.paneStorage), geometry.size.width > (compact ? 460 : 1000) {
                    Button { showVolume.toggle() } label: {
                        HStack(spacing: 6) {
                            if geometry.size.width > (compact ? 660 : 1200) {
                                ProgressView(value: Double(max(0, volume.total - volume.available)), total: Double(max(1, volume.total)))
                                    .frame(width: 38).accessibilityHidden(true)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: volume.available, countStyle: .file) + " free").monospacedDigit().fixedSize()
                        }.frame(minHeight: height - 4)
                    }.help("Storage on " + volume.name).popover(isPresented: $showVolume, arrowEdge: .bottom) { StatusVolumeView(volume: volume) }
                }
                if !compact { FileActivityButton(); PowerToolsMenu(workspace: workspace) }
                Menu {
                    Picker("File view", selection: $tab.options.view) { ForEach(ViewMode.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) } }
                } label: { Image(systemName: tab.options.view.symbol).frame(width: 26, height: height - 4) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("File view: " + tab.options.view.rawValue).help("Change file view").disabled(tab.location.isArchive)
            }.font(.system(size: 11)).foregroundStyle(ExplorerDesign.text).buttonStyle(.plain)
                .padding(.horizontal, 12).frame(height: height).background(ExplorerDesign.chrome)
        }.frame(height: height)
            .task(id: "\(storageURL?.path ?? "")|\(center.revision)|\(tab.dataRevision)|\(!compact || settings.paneStorage)") {
                volume = nil
                guard !compact || settings.paneStorage, let url = storageURL else { return }
                do {
                    let value = try await StatusVolumeService.shared.read(url, revision: center.revision)
                    try Task.checkCancellation(); volume = value
                } catch { /* Obsolete/unavailable storage never replaces the new pane's status. */ }
            }
            .accessibilityIdentifier(compact ? "explorer.paneStatus" : "explorer.windowStatus")
    }
    private var byteText: String {
        let statistics = tab.selectionStatistics
        return (statistics.overflowed ? "≥ " : "") + ByteCountFormatter.string(fromByteCount: statistics.bytes, countStyle: .file)
    }
    private var selectionDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(summaryText, systemImage: "checkmark.circle").font(.system(size: 14, weight: .semibold))
            if !tab.location.isArchive {
                Text("\(tab.selectionStatistics.files) files · \(tab.selectionStatistics.folders) folders").font(.system(size: 12)).monospacedDigit()
                Text(byteText).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit()
                Text("Logical size of selected files only. Folder contents, resource forks and physical disk allocation are not included. No recursive scan runs while you select or scroll.")
                    .font(.caption).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
            } else { Text("Archive members are separate from filesystem files.").font(.caption).foregroundStyle(ExplorerDesign.muted) }
        }.padding(20).frame(width: 300).background(ExplorerDesign.canvas)
    }
}
struct FileActivityButton: View {
    @ObservedObject private var center = OperationCenter.shared
    @State private var presented = false
    var body: some View {
        Button { presented.toggle() } label: {
            if let job = center.jobs.first(where: { !$0.finished }) { StatusOperationBadge(job: job) }
            else { Label(center.jobs.contains(where: { !$0.errors.isEmpty }) ? "Review operations" : "Activity", systemImage: center.jobs.contains(where: { !$0.errors.isEmpty }) ? "exclamationmark.circle" : "arrow.up.arrow.down.circle") }
        }.buttonStyle(.plain).font(.system(size: 11)).help("View transfer progress without leaving this folder")
            .popover(isPresented: $presented, arrowEdge: .bottom) { FileActivityPopover() }
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
                Text("File activity").font(.system(size: 14, weight: .semibold)); Spacer()
                if !running.isEmpty { Text("\(running.count) active").font(.caption).foregroundStyle(ExplorerDesign.muted) }
                Button("Done") { dismiss() }.font(.caption).keyboardShortcut(.cancelAction)
            }.padding(16)
            ExplorerRule()
            if center.jobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray").font(.system(size: 28, weight: .light)).foregroundStyle(ExplorerDesign.muted)
                    Text("No file operations yet").font(.system(size: 12, weight: .medium))
                    Text("Copy and move progress appears here.\nYou can keep browsing while transfers run.").font(.caption).foregroundStyle(ExplorerDesign.muted).multilineTextAlignment(.center)
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
                    Text("Completed work is retained when you cancel.").font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted); Spacer()
                    Button("Clear completed") { center.jobs.removeAll { $0.finished } }.font(.system(size: 10)).disabled(recent.isEmpty)
                }.padding(14)
            }
        }.frame(width: 400).background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text).accessibilityIdentifier("explorer.fileActivity")
    }
}
private struct RecentActivityRow: View {
    @ObservedObject var job: OperationRow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: !job.errors.isEmpty ? "exclamationmark.triangle" : job.cancelled ? "xmark.circle" : "checkmark.circle").foregroundStyle(!job.errors.isEmpty ? Color.orange : ExplorerDesign.muted)
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(job.status).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if !job.errors.isEmpty {
                DisclosureGroup("\(job.errors.count) notice(s)") { Text(job.errors.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.caption).foregroundStyle(ExplorerDesign.muted)
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
        guard let values = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeLocalizedFormatDescriptionKey, .volumeIsReadOnlyKey]),
              let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init), let total = values.volumeTotalCapacity, total > 0 else { return nil }
        return StatusVolume(name: values.volumeName ?? url.lastPathComponent, available: max(0, available), total: Int64(total), format: values.volumeLocalizedFormatDescription ?? "Filesystem", readOnly: values.volumeIsReadOnly ?? false)
    }
}
struct StatusVolumeView: View {
    let volume: StatusVolume
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(volume.name, systemImage: "internaldrive").font(.system(size: 14, weight: .semibold))
            ProgressView(value: Double(max(0, volume.total - volume.available)), total: Double(max(1, volume.total)))
            Text(ByteCountFormatter.string(fromByteCount: volume.available, countStyle: .file) + " available of " + ByteCountFormatter.string(fromByteCount: volume.total, countStyle: .file)).font(.system(size: 12)).monospacedDigit()
            Text(volume.format + " · " + (volume.readOnly ? "Read only" : "Read and write")).font(.caption).foregroundStyle(ExplorerDesign.muted)
            Text("Available space is reported by macOS and may include reclaimable storage.").font(.caption2).foregroundStyle(ExplorerDesign.muted).fixedSize(horizontal: false, vertical: true)
        }.padding(20).frame(width: 310).background(ExplorerDesign.canvas).foregroundStyle(ExplorerDesign.text)
    }
}
