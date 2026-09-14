import SwiftUI
import AppKit
import ExplorerCore

/// A recognizable folder silhouette, shared by the design's quick-access cards.
struct FolderArtwork: View {
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: "folder.fill").resizable().scaledToFit()
            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.65), Color.accentColor], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size * 0.85).accessibilityHidden(true)
    }
}

/// Uses actual image/PDF thumbnails. Other documents use their native file icon
/// rather than a nearly blank microscopic text-page thumbnail.
struct FileArtwork: View {
    let entry: FileEntry
    let size: CGFloat
    var body: some View {
        Group {
            if entry.canBrowse { FolderArtwork(size: size) }
            else if entry.isImage || entry.url.pathExtension.lowercased() == "pdf" { FileThumbnail(entry: entry, size: size) }
            else {
                VStack(spacing: 7) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().scaledToFit().frame(width: size * 0.76, height: size * 0.76)
                    if size >= 70, !entry.url.pathExtension.isEmpty {
                        Text(entry.url.pathExtension.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(ExplorerDesign.muted)
                    }
                }.frame(width: size, height: size)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct FolderShortcutCard: View {
    let url: URL
    @ObservedObject var workspace: ExplorerWorkspace
    var body: some View {
        Button { workspace.navigate(.folder(url)) } label: {
            HStack(spacing: 13) {
                FolderArtwork()
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(url.deletingLastPathComponent() == FileManager.default.homeDirectoryForCurrentUser ? "This Mac" : url.deletingLastPathComponent().lastPathComponent)
                        .font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }.buttonStyle(ExplorerCardStyle())
            .contextMenu {
                Button("Open in New Tab") { workspace.newTab(.folder(url)) }
                Button("Unpin from Quick Access") { workspace.preferences.unpin(url) }
            }
            .onDrop(of: ["public.file-url"], isTargeted: nil) { workspace.drop($0, to: url, move: NSEvent.modifierFlags.contains(.shift)) }
    }
}
struct ExplorerCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Card(configuration: configuration) }
    private struct Card: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovered = false
        var body: some View {
            configuration.label.foregroundStyle(ExplorerDesign.text)
                .background(hovered || configuration.isPressed ? ExplorerDesign.hover.opacity(0.45) : ExplorerDesign.canvas, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(hovered ? Color.accentColor.opacity(0.4) : ExplorerDesign.separator, lineWidth: 1))
                .onHover { hovered = $0 }
        }
    }
}
