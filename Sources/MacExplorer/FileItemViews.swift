import SwiftUI
import AppKit
import ExplorerCore

func displayName(_ entry: FileEntry, extensions: Bool) -> String { extensions || entry.canBrowse || entry.url.pathExtension.isEmpty ? entry.name : entry.url.deletingPathExtension().lastPathComponent }

struct FileTile: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    private var selected: Bool { tab.selection.contains(entry.url) }
    private var horizontal: Bool { [.tiles, .small, .details].contains(tab.options.view) }
    var body: some View {
        tileContent
            .contextMenu { FileContextMenu(workspace: workspace, urls: selected ? workspace.selectedURLs : [entry.url]) }
            .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(entry.name + ", " + entry.kind)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { workspace.open(entry) }
            .help(entry.url.path)
    }
    private var tileContent: some View {
        Group {
            if horizontal {
                HStack(spacing: 12) { FileThumbnail(entry: entry, size: tab.options.view == .small ? 20 : 44); labels(alignment: .leading); Spacer(minLength: 0) }.padding(10).frame(height: tab.options.view == .small ? 36 : 80)
            } else {
                VStack(spacing: 12) { FileThumbnail(entry: entry, size: CGFloat(tab.options.view.iconSize)); labels(alignment: .center) }.padding(12).frame(maxWidth: .infinity).frame(height: CGFloat(tab.options.view.iconSize) + 63)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selected ? Color.accentColor.opacity(0.3) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(tab.focusedURL == entry.url ? Color.accentColor.opacity(0.65) : .clear, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).allowsHitTesting(false))
        .overlay(alignment: .topLeading) {
            if preferences.value.checkboxes {
                Toggle("Select " + entry.name, isOn: Binding(get: { selected }, set: { _ in workspace.select(entry.url, extend: true, range: false) }))
                    .labelsHidden().toggleStyle(.checkbox).padding(5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.open(entry) }
        .onTapGesture {
            workspace.select(entry.url, extend: NSEvent.modifierFlags.intersection([.command, .control]).isEmpty == false, range: NSEvent.modifierFlags.contains(.shift))
            if preferences.value.singleClickOpen { workspace.open(entry) }
        }
    }
    private func labels(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(displayName(entry, extensions: preferences.value.showExtensions)).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(horizontal ? .leading : .center)
            if tab.options.view == .tiles { Text(entry.kind).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1); Text(entry.sizeText).font(.system(size: 10)).foregroundStyle(.tertiary) }
        }
    }
}

struct FileWideRow: View {
    let entry: FileEntry
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var preferences: PreferenceStore
    var body: some View {
        HStack(spacing: 11) {
            FileThumbnail(entry: entry, size: tab.options.view == .content ? 42 : 23)
            VStack(alignment: .leading, spacing: 4) { Text(displayName(entry, extensions: preferences.value.showExtensions)).font(.system(size: 12)).lineLimit(1); if tab.options.view == .content { Text(entry.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1) } }
            Spacer(minLength: 10)
            Text(entry.modified.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            Text(entry.sizeText).font(.caption).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
        }.padding(.horizontal, 9).padding(.vertical, preferences.value.compact ? 4 : 8)
            .background(tab.selection.contains(entry.url) ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
            .onTapGesture(count: 2) { workspace.open(entry) }
            .onTapGesture { workspace.select(entry.url, extend: !NSEvent.modifierFlags.intersection([.command, .control]).isEmpty, range: NSEvent.modifierFlags.contains(.shift)); if preferences.value.singleClickOpen { workspace.open(entry) } }
            .contextMenu { FileContextMenu(workspace: workspace, urls: tab.selection.contains(entry.url) ? workspace.selectedURLs : [entry.url]) }
            .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
    }
}
