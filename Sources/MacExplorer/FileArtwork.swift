import SwiftUI
import AppKit
import ExplorerCore

struct FolderArtwork: View {
    var size: CGFloat = 38
    var body: some View {
        Image(systemName: "folder.fill").resizable().scaledToFit()
            .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.65), Color.accentColor], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size * 0.85).accessibilityHidden(true)
    }
}
private final class ArtworkRaster: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
private actor ArtworkCache {
    static let shared = ArtworkCache()
    private let cache = NSCache<NSString, ArtworkRaster>()
    init() { cache.totalCostLimit = 32 * 1024 * 1024; cache.countLimit = 128 }
    func render(_ entry: FileEntry, pixels: Int) throws -> ArtworkRaster {
        try Task.checkCancellation()
        guard entry.isDownloaded else { throw ExplorerError.message("The file has not been downloaded.") }
        let key = "\(entry.url.path)|\(entry.modified.timeIntervalSince1970)|\(entry.size)|\(pixels)" as NSString
        if let value = cache.object(forKey: key) { return value }
        let image = try FilePreviewRenderer.render(entry.url, maximumPixelSize: pixels)
        try Task.checkCancellation()
        let value = ArtworkRaster(image); cache.setObject(value, forKey: key, cost: image.bytesPerRow * image.height); return value
    }
}
private struct DecodedArtwork: View {
    let entry: FileEntry
    let size: CGFloat
    @Environment(\.displayScale) private var displayScale
    @State private var raster: ArtworkRaster?
    private var pixels: Int { min(2048, max(16, Int((size * displayScale).rounded(.up)))) }
    private var key: String { "\(entry.url.path)|\(entry.modified.timeIntervalSince1970)|\(entry.size)|\(pixels)" }
    var body: some View {
        Group {
            if let raster { Image(decorative: raster.image, scale: displayScale).resizable().interpolation(.high).scaledToFit() }
            else { FileThumbnail(entry: entry, size: size, iconOnly: true) }
        }.frame(width: size, height: size).task(id: key) {
            raster = nil
            do { let value = try await ArtworkCache.shared.render(entry, pixels: pixels); if !Task.isCancelled { raster = value } }
            catch { /* An unavailable preview keeps its asynchronous native icon. */ }
        }
    }
}
struct FileArtwork: View {
    let entry: FileEntry
    let size: CGFloat
    var body: some View {
        Group {
            if entry.canBrowse { FolderArtwork(size: size) }
            else if entry.isImage || entry.url.pathExtension.lowercased() == "pdf" { DecodedArtwork(entry: entry, size: size) }
            else {
                VStack(spacing: 7) {
                    FileThumbnail(entry: entry, size: size * 0.76, iconOnly: true)
                    if size >= 70, !entry.url.pathExtension.isEmpty { Text(entry.url.pathExtension.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(ExplorerDesign.muted) }
                }.frame(width: size, height: size)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
struct FolderShortcutCard: View {
    let url: URL
    @ObservedObject var workspace: ExplorerWorkspace
    private var pinned: Bool { workspace.preferences.value.pins.contains { $0.url.standardizedFileURL.path == url.standardizedFileURL.path } }
    var body: some View {
        Button { workspace.navigate(.folder(url)) } label: {
            HStack(spacing: 13) {
                FolderArtwork()
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(url.deletingLastPathComponent() == FileManager.default.homeDirectoryForCurrentUser ? "This Mac" : url.deletingLastPathComponent().lastPathComponent).font(.system(size: 10)).foregroundStyle(ExplorerDesign.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        }.buttonStyle(ExplorerCardStyle()).contextMenu {
            Button("Open in New Tab") { workspace.newTab(.folder(url)) }
            Button(pinned ? "Unpin from Quick Access" : "Pin to Quick Access") { if pinned { workspace.preferences.unpin(url) } else { workspace.preferences.pin(url) } }
        }.onDrop(of: ["public.file-url"], isTargeted: nil) { workspace.drop($0, to: url, move: NSEvent.modifierFlags.contains(.shift)) }
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
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(hovered ? Color.accentColor.opacity(0.4) : ExplorerDesign.separator, lineWidth: 1)).onHover { hovered = $0 }
        }
    }
}
