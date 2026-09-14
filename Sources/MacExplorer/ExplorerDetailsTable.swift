import SwiftUI
import AppKit
import ExplorerCore

struct FileDetailsTable: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @ObservedObject private var columns = DetailsColumnStore.shared
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var collapsed = Set<String>()
    @State private var scrollbarGutter: CGFloat = 0
    @ObservedObject private var input = InputPreferences.shared
    var embedded = false
    var body: some View {
        GeometryReader { geometry in
            let visible = columns.value.visible
            let available = max(0, geometry.size.width - scrollbarGutter)
            let widths = columns.value.widths(available: available)
            let total = max(available, widths.reduce(0, +))
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(Array(tab.groups.enumerated()), id: \.offset) { _, group in
                                if !group.0.isEmpty { groupHeader(group.0, count: group.1.count) }
                                if !collapsed.contains(group.0) {
                                    ForEach(group.1) { entry in
                                        DetailsFileRow(entry: entry, workspace: workspace, tab: tab, columns: visible, widths: widths).id(entry.url)
                                    }
                                }
                            }
                        } header: {
                            HStack(spacing: 0) {
                                ForEach(Array(visible.enumerated()), id: \.element) { index, column in
                                    DetailsColumnHeader(column: column, width: widths[index], tab: tab, store: columns)
                                }
                            }.frame(width: total, height: input.headerHeight).background(ExplorerDesign.canvas)
                                .overlay(alignment: .bottom) { ExplorerRule() }.explorerRegion("details.header")
                        }
                    }.frame(width: total).frame(minHeight: geometry.size.height, alignment: .top)
                        .background(ExplorerDesign.canvas).contentShape(Rectangle())
                        .background(ScrollViewportMetrics { scrollbarGutter = $0 })
                        .contextMenu { FileContextMenu(workspace: workspace, urls: []) }
                }.onChange(of: tab.focusedURL) { _, url in if let url { proxy.scrollTo(url) } }
                    .onChange(of: tab.options.group) { _, _ in collapsed = [] }
            }
        }.accessibilityIdentifier("explorer.detailsTable")
    }
    private func groupHeader(_ title: String, count: Int) -> some View {
        Button { if collapsed.contains(title) { collapsed.remove(title) } else { collapsed.insert(title) } } label: {
            HStack(spacing: 8) {
                Image(systemName: collapsed.contains(title) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold))
                Text(title).fontWeight(.semibold); Text("\(count)").foregroundStyle(ExplorerDesign.muted); Spacer()
            }.font(.system(size: 11)).padding(.horizontal, 14).frame(height: input.headerHeight).background(ExplorerDesign.chrome)
        }.buttonStyle(.plain).accessibilityLabel(title + ", \(count) items")
    }
}
private struct DetailsFileRow: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    let columns: [DetailsColumn]
    let widths: [Double]
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var hovered = false
    @ObservedObject private var input = InputPreferences.shared
    private var selected: Bool { tab.selection.contains(entry.url) }
    private var menuURLs: [URL] { selected ? workspace.selectedURLs : [entry.url] }
    private var rowColor: Color { selected ? ExplorerDesign.selection : hovered ? ExplorerDesign.hover.opacity(0.65) : ExplorerDesign.canvas }
    var body: some View {
        interaction.accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.name + ", " + entry.kind + ", " + entry.sizeText)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { workspace.tapFile(entry.url, modifiers: []) }
            .accessibilityAction(named: Text("Open")) { workspace.activateFile(entry, doubleClick: true) }
            .accessibilityAction(named: Text("More actions")) { workspace.showFileActions(for: entry) }.help(entry.url.path)
    }
    private var interaction: some View {
        surface.contentShape(Rectangle()).onHover { hovered = $0 }
            .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
            .contextMenu { FileContextMenu(workspace: workspace, urls: menuURLs) }
    }
    private var surface: some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.element) { index, column in
                cell(column).padding(.horizontal, 12).frame(width: widths[index], alignment: column == .size ? .trailing : .leading)
            }
        }.font(.system(size: input.fileFontSize)).frame(height: input.rowHeight(compact: preferences.value.compact))
            .background(rowColor)
            .overlay(alignment: .bottom) { Rectangle().fill(ExplorerDesign.separator.opacity(0.42)).frame(height: 0.5) }
            .overlay { if tab.focusedURL == entry.url { Rectangle().stroke(Color.accentColor.opacity(0.6), lineWidth: 1).padding(1).allowsHitTesting(false) } }
    }
    @ViewBuilder private func cell(_ column: DetailsColumn) -> some View {
        switch column {
        case .name:
            HStack(spacing: 10) {
                if preferences.value.checkboxes || workspace.touchSelecting {
                    Toggle("Select " + entry.name, isOn: Binding(get: { selected }, set: { _ in workspace.select(entry.url, extend: true, range: false) }))
                        .labelsHidden().toggleStyle(.checkbox).frame(minWidth: input.touchFriendly ? 36 : nil, minHeight: input.touchFriendly ? 40 : nil)
                }
                FileThumbnail(entry: entry, size: 20)
                Text(displayName(entry, extensions: preferences.value.showExtensions)).lineLimit(1).truncationMode(.middle).foregroundStyle(ExplorerDesign.text)
                if entry.isLocked { Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(ExplorerDesign.muted) }
            }
        case .modified:
            ViewThatFits(in: .horizontal) {
                Text(entry.modified.formatted(date: .abbreviated, time: .shortened)).fixedSize()
                Text(entry.modified.formatted(date: .abbreviated, time: .omitted)).fixedSize()
                Text(entry.modified.formatted(date: .numeric, time: .omitted)).fixedSize()
            }.foregroundStyle(ExplorerDesign.muted).help(entry.modified.formatted(date: .complete, time: .standard))
        case .kind: Text(entry.kind).lineLimit(1).foregroundStyle(ExplorerDesign.muted).help(entry.kind)
        case .size: Text(entry.sizeText).monospacedDigit().lineLimit(1).foregroundStyle(ExplorerDesign.muted)
        case .tags: Text(entry.tags.joined(separator: ", ")).lineLimit(1).foregroundStyle(ExplorerDesign.muted)
        case .availability:
            Label(entry.isCloud ? (entry.isDownloaded ? "Downloaded" : "Online only") : "Local", systemImage: entry.isCloud ? (entry.isDownloaded ? "checkmark.icloud" : "icloud") : "checkmark")
                .font(.system(size: 11)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
        }
    }
}
private struct DetailsColumnHeader: View {
    let column: DetailsColumn
    let width: Double
    @ObservedObject var tab: BrowserTab
    @ObservedObject var store: DetailsColumnStore
    @State private var initial: Double?
    @State private var targeted = false
    @ObservedObject private var input = InputPreferences.shared
    var body: some View {
        Button(action: sort) {
            HStack(spacing: 5) {
                Text(column.title).lineLimit(1)
                if column.sort == tab.options.sort { Image(systemName: tab.options.descending ? "arrow.down" : "arrow.up").font(.system(size: 8)) }
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).padding(.horizontal, 12).frame(height: input.headerHeight)
                .background(targeted ? ExplorerDesign.selection : ExplorerDesign.canvas)
        }.buttonStyle(.plain).frame(width: width)
            .onDrag { store.begin(column) }
            .onDrop(of: [DetailsColumnStore.dragType], isTargeted: $targeted) { store.accept($0, before: column) }
            .overlay(alignment: .trailing) { resizeHandle }.contextMenu { columnMenu }
            .accessibilityLabel(column.title + (column.sort == tab.options.sort ? (tab.options.descending ? ", sorted descending" : ", sorted ascending") : ""))
    }
    private var resizeHandle: some View {
        Rectangle().fill(Color.clear).frame(width: 7, height: 26).contentShape(Rectangle())
            .overlay { Rectangle().fill(ExplorerDesign.separator).frame(width: 1, height: 14) }
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { gesture in if initial == nil { initial = width }; store.value.setWidth((initial ?? width) + gesture.translation.width, for: column) }
                .onEnded { _ in initial = nil; store.save() })
            .onTapGesture(count: 2, perform: sizeToFit).accessibilityLabel("Resize " + column.title)
            .accessibilityAdjustableAction { direction in store.value.setWidth(width + (direction == .increment ? 20 : -20), for: column); store.save() }
    }
    private var columnMenu: some View {
        Group {
            ForEach(DetailsColumn.allCases) { item in
                Toggle(item.title, isOn: Binding(get: { store.value.visible.contains(item) }, set: { _ in store.toggle(item) })).disabled(item == .name)
            }
            Divider(); Button("Size Column to Fit", action: sizeToFit)
            Button("Automatic Column Widths") { store.value.overrides = [:]; store.save() }
            Button("Reset Columns") { store.reset() }
        }
    }
    private func sort() {
        guard let field = column.sort else { return }
        if tab.options.sort == field { tab.options.descending.toggle() } else { tab.options.sort = field; tab.options.descending = false }
    }
    private func sizeToFit() {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
        let samples = tab.visibleEntries.prefix(500).map { entry -> String in
            switch column {
            case .name: return entry.name
            case .modified: return entry.modified.formatted(date: .abbreviated, time: .shortened)
            case .kind: return entry.kind
            case .size: return entry.sizeText
            case .tags: return entry.tags.joined(separator: ", ")
            case .availability: return entry.isCloud ? "Downloaded" : "Local"
            }
        }
        let measured = (samples + [column.title]).map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
        store.value.setWidth(min(720, measured + (column == .name ? 66 : 30)), for: column); store.save()
    }
}
