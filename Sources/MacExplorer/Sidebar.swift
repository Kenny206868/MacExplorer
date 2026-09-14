import SwiftUI
import AppKit
import ExplorerCore

struct ExplorerSidebar: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var cloudFolders: [URL] = []
    @State private var volumes: [URL] = []
    @State private var computerExpanded = false
    @State private var allTags = false
    private var tags: [String] {
        let present = Array(Set(tab.entries.flatMap(\.tags))).sorted()
        let defaults = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"]
        return allTags ? Array(Set(present + defaults)).sorted() : present.isEmpty ? ["Red", "Orange", "Green"] : Array(present.prefix(4))
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    location(.home); location(.gallery)
                    if !cloudFolders.isEmpty {
                        heading("Cloud storage")
                        ForEach(cloudFolders, id: \.self) { url in
                            location(.folder(url), title: url.lastPathComponent == "com~apple~CloudDocs" ? "iCloud Drive" : url.lastPathComponent, symbol: "icloud")
                        }
                    }
                    heading("Quick access")
                    ForEach(preferences.value.pins) { pin in TreeFolderRow(url: pin.url, workspace: workspace, tab: tab, depth: 0, pinned: true) }
                    heading("Locations")
                    HStack(spacing: 0) {
                        Button { computerExpanded.toggle() } label: { Image(systemName: computerExpanded ? "chevron.down" : "chevron.right").font(.system(size: 8)).frame(width: 12, height: 32) }
                            .buttonStyle(.plain).foregroundStyle(ExplorerDesign.muted).accessibilityLabel(computerExpanded ? "Collapse This Mac" : "Expand This Mac")
                        Button { workspace.navigate(.computer) } label: {
                            Label("This Mac", systemImage: "desktopcomputer").labelStyle(SidebarLabelStyle()).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).font(.system(size: 12))
                    }.padding(.trailing, 8).background(tab.location == .computer ? ExplorerDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 6))
                    if computerExpanded {
                        ForEach(volumes, id: \.self) { url in TreeFolderRow(url: url, workspace: workspace, tab: tab, depth: 1, pinned: false) }
                        location(.folder(FileManager.default.homeDirectoryForCurrentUser), title: NSUserName(), symbol: "person.crop.circle")
                    }
                    location(.network); location(.trash)
                    HStack { heading("Tags"); Spacer(); Button { allTags.toggle() } label: { Image(systemName: allTags ? "minus" : "ellipsis").font(.system(size: 10)) }.buttonStyle(.plain).padding(.top, 16).padding(.trailing, 10).help(allTags ? "Show fewer tags" : "Show all standard tags") }
                    ForEach(tags, id: \.self) { tag in
                        Button { workspace.navigate(.tag(tag)) } label: {
                            HStack(spacing: 12) { Circle().fill(ExplorerDesign.tagColor(tag)).frame(width: 6, height: 6).frame(width: 18); Text(tag).lineLimit(1); Spacer(minLength: 0) }
                        }.buttonStyle(SidebarButtonStyle(selected: tab.location == .tag(tag)))
                    }
                    if !preferences.value.savedSearches.isEmpty {
                        heading("Saved searches")
                        ForEach(preferences.value.savedSearches, id: \.self) { query in
                            Button { workspace.navigate(.home); tab.allLocations = true; tab.query = query } label: {
                                Label(query, systemImage: "magnifyingglass").labelStyle(SidebarLabelStyle()).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(SidebarButtonStyle(selected: false))
                                .contextMenu { Button("Remove Saved Search") { preferences.value.savedSearches.removeAll { $0 == query } } }
                        }
                    }
                }.padding(.horizontal, 10).padding(.top, 15).padding(.bottom, 16)
            }
            ExplorerRule().padding(.horizontal, 20)
            VolumeCapacity(url: URL(fileURLWithPath: "/"), compact: true).padding(.horizontal, 20).padding(.vertical, 14)
        }.background(ExplorerDesign.sidebar).foregroundStyle(ExplorerDesign.text)
            .task { reloadLocations() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in reloadLocations() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in reloadLocations() }
    }
    private func reloadLocations() { cloudFolders = NativeIntegration.cloudFolders(); volumes = NativeIntegration.volumes() }
    private func heading(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(ExplorerDesign.muted)
            .tracking(0.7).padding(.top, 18).padding(.bottom, 6).padding(.horizontal, 10)
    }
    private func location(_ value: Location, title: String? = nil, symbol: String? = nil) -> some View {
        Button { workspace.navigate(value) } label: {
            Label(title ?? value.title, systemImage: symbol ?? value.symbol).labelStyle(SidebarLabelStyle()).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(SidebarButtonStyle(selected: tab.location == value))
            .contextMenu { Button("Open in New Tab") { workspace.newTab(value) }; if let url = value.directory { Button("Pin to Quick Access") { preferences.pin(url) } } }
    }
}
struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 10) { configuration.icon.foregroundStyle(Color.accentColor).font(.system(size: 15)).frame(width: 18); configuration.title.lineLimit(1) } }
}
struct SidebarButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View { SidebarButtonBody(configuration: configuration, selected: selected) }
    private struct SidebarButtonBody: View {
        let configuration: ButtonStyle.Configuration
        let selected: Bool
        @State private var hovered = false
        var body: some View {
            configuration.label.font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 10).frame(height: 32)
                .foregroundStyle(selected ? Color.accentColor : ExplorerDesign.text)
                .background(selected ? ExplorerDesign.selection : hovered || configuration.isPressed ? ExplorerDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
        }
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
    @State private var hovered = false
    private var symbol: String {
        switch url.lastPathComponent {
        case "Desktop": return "desktopcomputer"
        case "Downloads": return "arrow.down.to.line"
        case "Documents": return "doc.text"
        case "Pictures": return "photo"
        case "Music": return "music.note"
        case "Movies": return "film"
        default: return url.path == "/" ? "internaldrive" : "folder"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 0) {
                Button { expanded.toggle() } label: { Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8)).foregroundStyle(ExplorerDesign.muted).frame(width: 12, height: 32) }.buttonStyle(.plain).accessibilityLabel(expanded ? "Collapse folder" : "Expand folder")
                Button { workspace.navigate(.folder(url)) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.accentColor).frame(width: 18)
                        Text(url.path == "/" ? "Macintosh HD" : url.lastPathComponent).lineLimit(1)
                        Spacer(minLength: 0)
                        if pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(ExplorerDesign.muted.opacity(0.75)) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).font(.system(size: 12))
            }.padding(.leading, CGFloat(depth * 10)).padding(.trailing, 10).frame(height: 32)
                .background(tab.location == .folder(url) ? ExplorerDesign.selection : hovered ? ExplorerDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 6))
                .onHover { hovered = $0 }
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
                if loading { ProgressView().controlSize(.small).padding(.leading, CGFloat(depth * 10 + 25)) }
                if let error { Text(error).font(.caption2).foregroundStyle(ExplorerDesign.muted).lineLimit(2).padding(.leading, 25) }
                ForEach(children) { child in AnyView(TreeFolderRow(url: child.url, workspace: workspace, tab: tab, depth: depth + 1, pinned: false)) }
            }
        }.task(id: "\(expanded)|\(preferences.value.showHidden)|\(operations.revision)") {
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
            Text(name.isEmpty ? (url.path == "/" ? "Macintosh HD" : url.lastPathComponent) : name).font(.system(size: compact ? 11 : 13, weight: .medium)).lineLimit(1)
            if total > 0 {
                GeometryReader { geometry in
                    Capsule().fill(ExplorerDesign.separator).overlay(alignment: .leading) {
                        Capsule().fill(Double(available) / Double(total) < 0.1 ? Color.orange : Color.accentColor)
                            .frame(width: geometry.size.width * max(0, min(1, Double(total - available) / Double(total))))
                    }
                }.frame(height: 4)
                Text("\(ByteCountFormatter.string(fromByteCount: available, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))").font(.system(size: compact ? 10 : 11)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).task(id: url) {
            let values = await Task.detached(priority: .utility) { () -> (Int64, Int64, String) in
                let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey, .volumeNameKey])
                return (Int64(v?.volumeAvailableCapacity ?? 0), Int64(v?.volumeTotalCapacity ?? 0), v?.volumeName ?? url.lastPathComponent)
            }.value
            guard !Task.isCancelled else { return }
            available = values.0; total = values.1; name = values.2
        }
    }
}
