import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerSidebar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                location(.home); location(.gallery)
                heading("Cloud storage")
                ForEach(NativeIntegration.cloudFolders(), id: \.self) { url in
                    location(.folder(url), title: url.lastPathComponent == "com~apple~CloudDocs" ? "iCloud Drive" : url.lastPathComponent, symbol: "icloud")
                }
                heading("Quick access")
                ForEach(preferences.value.pins) { pin in
                    TreeFolderRow(url: pin.url, workspace: workspace, tab: tab, depth: 0, pinned: true)
                }
                heading("Locations")
                location(.computer)
                ForEach(NativeIntegration.volumes(), id: \.self) { url in
                    TreeFolderRow(url: url, workspace: workspace, tab: tab, depth: 0, pinned: false)
                }
                location(.folder(FileManager.default.homeDirectoryForCurrentUser), title: NSUserName(), symbol: "person.crop.circle")
                location(.network); location(.trash)
                heading("Tags")
                ForEach(["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray", "Work", "Personal"], id: \.self) { tag in location(.tag(tag), symbol: "tag") }
                if !preferences.value.savedSearches.isEmpty {
                    heading("Saved searches")
                    ForEach(preferences.value.savedSearches, id: \.self) { query in
                        Button { workspace.navigate(.home); tab.allLocations = true; tab.query = query } label: { Label(query, systemImage: "magnifyingglass").lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(SidebarButtonStyle(selected: false))
                            .contextMenu { Button("Remove Saved Search") { preferences.value.savedSearches.removeAll { $0 == query } } }
                    }
                }
                Divider().padding(.top, 18)
                VolumeCapacity(url: URL(fileURLWithPath: "/"), compact: true).padding(10)
            }.padding(.horizontal, 9).padding(.vertical, 14)
        }.background(.regularMaterial)
    }
    private func heading(_ title: String) -> some View { Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).tracking(0.7).padding(.top, 18).padding(.bottom, 5).padding(.horizontal, 10) }
    private func location(_ value: Location, title: String? = nil, symbol: String? = nil) -> some View {
        Button { workspace.navigate(value) } label: {
            Label(title ?? value.title, systemImage: symbol ?? value.symbol).labelStyle(SidebarLabelStyle()).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(SidebarButtonStyle(selected: tab.location == value))
            .contextMenu { Button("Open in New Tab") { workspace.newTab(value) }; if let url = value.directory { Button("Pin to Quick Access") { preferences.pin(url) } } }
    }
}

struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 10) { configuration.icon.foregroundStyle(.tint).frame(width: 18); configuration.title.lineLimit(1) } }
}
struct SidebarButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 10).frame(height: 32)
            .background(selected ? Color.accentColor.opacity(0.13) : configuration.isPressed ? Color.primary.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
    }
}

struct TreeFolderRow: View {
    let url: URL
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    let depth: Int
    let pinned: Bool
    @EnvironmentObject private var preferences: PreferenceStore
    @ObservedObject private var operations = OperationCenter.shared
    @State private var expanded = false
    @State private var children: [FileEntry] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).frame(width: 17, height: 30) }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse folder" : "Expand folder")
                Button { workspace.navigate(.folder(url)) } label: {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 17, height: 17)
                        Text(url.path == "/" ? "Macintosh HD" : url.lastPathComponent).lineLimit(1)
                        Spacer(minLength: 0)
                        if pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.tertiary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).font(.system(size: 12))
            }.padding(.leading, CGFloat(depth * 9)).padding(.trailing, 8).frame(height: 32)
                .background(tab.location == .folder(url) ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contextMenu {
                    Button("Open in New Tab") { workspace.newTab(.folder(url)) }
                    Button(pinned ? "Unpin from Quick Access" : "Pin to Quick Access") { if pinned { preferences.unpin(url) } else { preferences.pin(url) } }
                    Button("Open in Terminal") { NativeIntegration.terminal(url, owner: workspace) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    if NativeIntegration.volumes().contains(url), url.path != "/" { Divider(); Button("Eject") { NativeIntegration.eject(url, owner: workspace) } }
                }
                .onDrag { NSItemProvider(object: url as NSURL) }
                .onDrop(of: ["public.file-url"], isTargeted: nil) { workspace.drop($0, to: url, move: NSEvent.modifierFlags.contains(.shift)) }
            if expanded {
                if loading { ProgressView().controlSize(.small).padding(.leading, CGFloat(depth * 9 + 25)) }
                if let error { Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2).padding(.leading, 25) }
                ForEach(children) { child in
                    // Type erasure bounds the recursive SwiftUI view type; data loading remains lazy.
                    AnyView(TreeFolderRow(url: child.url, workspace: workspace, tab: tab, depth: depth + 1, pinned: false))
                }
            }
        }
        .task(id: "\(expanded)|\(preferences.value.showHidden)|\(operations.revision)") {
            guard expanded, depth < 48 else { return }
            loading = true; error = nil
            do {
                let snapshot = try await FileService().list(url, showHidden: preferences.value.showHidden)
                guard !Task.isCancelled else { return }
                children = snapshot.entries.filter { $0.canBrowse && !$0.isSymbolicLink }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}

struct VolumeCapacity: View {
    let url: URL
    var compact = false
    @State private var available: Int64 = 0
    @State private var total: Int64 = 0
    @State private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            Text(name.isEmpty ? url.lastPathComponent : name).font(.system(size: compact ? 11 : 13, weight: .medium))
            if total > 0 {
                ProgressView(value: Double(total - available), total: Double(total)).tint(Double(available) / Double(total) < 0.1 ? .orange : .accentColor)
                Text("\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))").font(.system(size: compact ? 10 : 11)).foregroundStyle(.secondary)
            }
        }.task(id: url) {
            let values = await Task.detached(priority: .utility) { try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeNameKey]) }.value
            available = Int64(values?.volumeAvailableCapacity ?? 0); total = Int64(values?.volumeTotalCapacity ?? 0); name = values?.volumeName ?? url.lastPathComponent
        }
    }
}
