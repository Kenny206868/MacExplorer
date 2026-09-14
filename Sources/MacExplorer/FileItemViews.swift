import SwiftUI
import AppKit
import ExplorerCore

func displayName(_ entry: FileEntry, extensions: Bool) -> String {
    extensions || entry.canBrowse || entry.url.pathExtension.isEmpty ? entry.name : entry.url.deletingPathExtension().lastPathComponent
}
struct FileTile: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var hovered = false
    @ObservedObject private var input = InputPreferences.shared
    private var selected: Bool { tab.selection.contains(entry.url) }
    private var horizontal: Bool { [.tiles, .small, .details].contains(tab.options.view) }
    private var menuURLs: [URL] { selected ? workspace.selectedURLs : [entry.url] }
    var body: some View {
        interactiveSurface.contextMenu { FileContextMenu(workspace: workspace, urls: menuURLs) }
            .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
            .accessibilityElement(children: .combine).accessibilityLabel(entry.name + ", " + entry.kind)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { workspace.tapFile(entry.url, modifiers: []) }
            .accessibilityAction(named: Text("Open")) { workspace.activateFile(entry, doubleClick: true) }.help(entry.url.path)
    }
    private var interactiveSurface: some View {
        tileContent
            .background(selected ? ExplorerDesign.selection : hovered ? ExplorerDesign.hover.opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor.opacity(0.32) : .clear, lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(tab.focusedURL == entry.url ? Color.accentColor.opacity(0.6) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).allowsHitTesting(false))
            .overlay(alignment: .topLeading) { checkbox }
            .contentShape(Rectangle()).onHover { hovered = $0 }
    }
    @ViewBuilder private var tileContent: some View {
        if horizontal {
            HStack(spacing: 12) {
                FileArtwork(entry: entry, size: tab.options.view == .small ? 20 : 44)
                labels(alignment: .leading); Spacer(minLength: 0)
            }.padding(.horizontal, 10).frame(height: input.gridCellHeight(tab.options.view))
        } else {
            VStack(spacing: 10) {
                FileArtwork(entry: entry, size: CGFloat(tab.options.view.iconSize))
                labels(alignment: .center)
            }.padding(12).frame(maxWidth: .infinity).frame(height: CGFloat(tab.options.view.iconSize) + 63)
        }
    }
    @ViewBuilder private var checkbox: some View {
        if preferences.value.checkboxes || workspace.touchSelecting {
            Toggle("Select " + entry.name, isOn: Binding(get: { selected }, set: { _ in workspace.select(entry.url, extend: true, range: false) }))
                .labelsHidden().toggleStyle(.checkbox).frame(minWidth: input.touchFriendly ? 36 : nil, minHeight: input.touchFriendly ? 36 : nil).padding(5)
        }
    }
    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(displayName(entry, extensions: preferences.value.showExtensions)).font(.system(size: 11)).lineLimit(horizontal ? 1 : 2)
                .multilineTextAlignment(horizontal ? .leading : .center).foregroundStyle(ExplorerDesign.text)
            if tab.options.view == .tiles {
                Text(entry.kind).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                Text(entry.sizeText).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted)
            }
        }
    }
}
struct FileWideRow: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    @State private var hovered = false
    @ObservedObject private var input = InputPreferences.shared
    private var selected: Bool { tab.selection.contains(entry.url) }
    private var detailed: Bool { tab.options.view == .content }
    private var menuURLs: [URL] { selected ? workspace.selectedURLs : [entry.url] }
    var body: some View {
        surface.contentShape(Rectangle()).onHover { hovered = $0 }
            .contextMenu { FileContextMenu(workspace: workspace, urls: menuURLs) }
            .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
            .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { workspace.tapFile(entry.url, modifiers: []) }
            .accessibilityAction(named: Text("Open")) { workspace.activateFile(entry, doubleClick: true) }
    }
    private var surface: some View {
        HStack(spacing: 12) {
            if preferences.value.checkboxes || workspace.touchSelecting { Toggle("Select " + entry.name, isOn: Binding(get: { selected }, set: { _ in workspace.select(entry.url, extend: true, range: false) })).labelsHidden().toggleStyle(.checkbox).frame(minWidth: input.touchFriendly ? 36 : nil, minHeight: input.touchFriendly ? 36 : nil) }
            FileArtwork(entry: entry, size: detailed ? 42 : 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName(entry, extensions: preferences.value.showExtensions)).font(.system(size: input.fileFontSize)).lineLimit(1).truncationMode(.middle).foregroundStyle(ExplorerDesign.text)
                if detailed { Text(entry.url.deletingLastPathComponent().path).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1).truncationMode(.middle) }
            }
            Spacer(minLength: 8)
            if detailed { Text(entry.modified.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1) }
            Text(entry.sizeText).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).frame(width: 65, alignment: .trailing).monospacedDigit().lineLimit(1)
        }.padding(.horizontal, 12).frame(height: detailed ? 70 : input.rowHeight(compact: preferences.value.compact))
            .background(selected ? ExplorerDesign.selection : hovered ? ExplorerDesign.hover.opacity(0.5) : ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottom) { Rectangle().fill(ExplorerDesign.separator.opacity(detailed ? 0.7 : 0.35)).frame(height: 0.5) }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tab.focusedURL == entry.url ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1).allowsHitTesting(false))
    }
}
