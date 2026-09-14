import SwiftUI
import AppKit
import ExplorerCore

struct FileCollection: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    var body: some View {
        if tab.options.view == .gallery { FileGalleryView(workspace: workspace, tab: tab) }
        else if tab.options.view == .details && tab.options.group == .none { FileDetailsTable(workspace: workspace, tab: tab) }
        else if [.content, .list, .details].contains(tab.options.view) {
            ScrollViewReader { proxy in
                List(selection: $tab.selection) {
                    ForEach(Array(tab.groups.enumerated()), id: \.offset) { _, group in
                        Section { ForEach(group.1) { entry in FileWideRow(entry: entry, workspace: workspace, tab: tab).tag(entry.url).id(entry.url) } } header: { if !group.0.isEmpty { Text(group.0) } }
                    }
                }.listStyle(.inset)
                    .onChange(of: tab.focusedURL) { _, url in if let url { proxy.scrollTo(url) } }
            }
        } else { FileGridView(workspace: workspace, tab: tab) }
    }
}

struct FileDetailsTable: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var lastSelection: Set<URL> = []
    @State private var sortOrder = [KeyPathComparator(\FileEntry.name)]
    @SceneStorage("MacExplorer.DetailColumns") private var customization: TableColumnCustomization<FileEntry>
    var body: some View {
        Table(tab.visibleEntries, selection: $tab.selection, sortOrder: $sortOrder, columnCustomization: $customization) {
            TableColumn("Name", value: \.name) { entry in
                HStack(spacing: 8) {
                    if preferences.value.checkboxes { Toggle("Select \(entry.name)", isOn: Binding(get: { tab.selection.contains(entry.url) }, set: { if $0 { tab.selection.insert(entry.url) } else { tab.selection.remove(entry.url) } })).labelsHidden().toggleStyle(.checkbox) }
                    FileThumbnail(entry: entry, size: 20)
                    Text(displayName(entry, extensions: preferences.value.showExtensions)).lineLimit(1)
                    if entry.isLocked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary) }
                }.frame(minHeight: preferences.value.compact ? 22 : 29)
                    .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
            }.width(min: 180, ideal: 310).customizationID("name")
            TableColumn("Date modified", value: \.modified) { entry in Text(entry.modified.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }.width(min: 130, ideal: 150).customizationID("modified")
            TableColumn("Kind", value: \.kind) { entry in Text(entry.kind).foregroundStyle(.secondary) }.width(min: 100, ideal: 140).customizationID("kind")
            TableColumn("Size", value: \.size) { entry in Text(entry.sizeText).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing) }.width(min: 65, ideal: 80).customizationID("size")
            TableColumn("Tags") { entry in Text(entry.tags.joined(separator: ", ")).foregroundStyle(.secondary) }.width(min: 90, ideal: 130).customizationID("tags")
            TableColumn("Availability") { entry in
                if entry.isCloud { Label(entry.isDownloaded ? "Downloaded" : "Online only", systemImage: entry.isDownloaded ? "checkmark.icloud" : "icloud.and.arrow.down").foregroundStyle(.secondary) }
                else { Text("Local").foregroundStyle(.tertiary) }
            }.width(min: 90, ideal: 125).customizationID("availability")
        }
        .font(.system(size: 12))
        .contextMenu(forSelectionType: URL.self) { urls in FileContextMenu(workspace: workspace, urls: Array(urls)) } primaryAction: { urls in tab.selection = urls; workspace.openSelection() }
        .onChange(of: tab.selection) { _, selection in
            if let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(event.type) {
                tab.focusedURL = tab.visibleEntries.first(where: { selection.contains($0.url) && !lastSelection.contains($0.url) })?.url ?? tab.focusedURL
                if !event.modifierFlags.contains(.shift) { tab.selectionAnchor = tab.focusedURL }
            }
            lastSelection = selection
        }
        .onChange(of: sortOrder) { _, order in
            guard let first = order.first else { return }
            if first.keyPath == \FileEntry.name { tab.options.sort = .name }
            else if first.keyPath == \FileEntry.modified { tab.options.sort = .modified }
            else if first.keyPath == \FileEntry.kind { tab.options.sort = .kind }
            else if first.keyPath == \FileEntry.size { tab.options.sort = .size }
            tab.options.descending = first.order == .reverse
        }
    }
}
