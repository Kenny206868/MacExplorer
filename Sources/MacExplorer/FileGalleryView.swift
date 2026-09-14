import SwiftUI
import AppKit
import ImageIO
import ExplorerCore

private final class GalleryRaster: @unchecked Sendable {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
private actor GalleryRasterCache {
    static let shared = GalleryRasterCache()
    private let cache = NSCache<NSString, GalleryRaster>()
    init() { cache.totalCostLimit = 48 * 1024 * 1024; cache.countLimit = 12 }
    func image(for entry: FileEntry) throws -> GalleryRaster {
        try Task.checkCancellation()
        let key = "\(entry.url.path)|\(entry.modified.timeIntervalSince1970)|\(entry.size)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard entry.isDownloaded, !entry.canBrowse,
              let source = CGImageSourceCreateWithURL(entry.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw ExplorerError.message("Use Quick Look to preview this image format.") }
        try Task.checkCancellation()
        let raster = GalleryRaster(image); cache.setObject(raster, forKey: key, cost: image.bytesPerRow * image.height)
        return raster
    }
}
struct FileGalleryView: View {
    @ObservedObject var workspace: ExplorerWorkspace
    @ObservedObject var tab: BrowserTab
    private var files: [FileEntry] { tab.displayEntries }
    private var active: FileEntry? {
        files.first { $0.url == tab.focusedURL && tab.selection.contains($0.url) }
            ?? files.first { tab.selection.contains($0.url) } ?? files.first
    }
    private var index: Int { active.flatMap { entry in files.firstIndex { $0.url == entry.url } } ?? 0 }
    var body: some View {
        VStack(spacing: 0) {
            if let entry = active {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(entry.kind + " · " + entry.sizeText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    CommandIcon("Previous item", "chevron.left", disabled: index == 0) { step(-1) }
                    Text("\(index + 1) / \(files.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    CommandIcon("Next item", "chevron.right", disabled: index + 1 >= files.count) { step(1) }
                    CommandIcon("Open in Quick Look", "arrow.up.left.and.arrow.down.right") { tab.previewURL = entry.url }
                }.padding(.horizontal, 18).frame(height: 60)
                ExplorerRule()
                Group {
                    if entry.canBrowse {
                        VStack(spacing: 20) {
                            FileThumbnail(entry: entry, size: 128); Text(entry.name).font(.title3).lineLimit(2)
                            Button("Open Folder") { workspace.open(entry) }.buttonStyle(ExplorerButtonStyle(primary: true))
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !entry.isDownloaded {
                        ContentUnavailableView("Available online", systemImage: "icloud.and.arrow.down", description: Text("Download this file before previewing it.")).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if entry.isImage { GalleryImageCanvas(entry: entry).id(entry.url) }
                    else { NativePreview(url: entry.url).padding(18).frame(maxWidth: .infinity, maxHeight: .infinity) }
                }.background(ExplorerDesign.surface.opacity(0.28))
                    .contextMenu { FileContextMenu(workspace: workspace, urls: tab.selection.contains(entry.url) ? workspace.selectedURLs : [entry.url]) }
                ExplorerRule(); filmstrip
            } else { ContentUnavailableView("No files to preview", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.onAppear { tab.gridColumns = 1 }.accessibilityIdentifier("explorer.gallery")
    }
    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(files) { entry in
                        VStack(spacing: 8) {
                            FileThumbnail(entry: entry, size: 62); Text(entry.name).font(.system(size: 10)).lineLimit(1)
                        }.frame(width: 92, height: 92).padding(6)
                            .background(tab.selection.contains(entry.url) ? ExplorerDesign.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(entry.url == active?.url ? Color.accentColor : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle()).id(entry.url)
                            .modifier(FileInteractionModifier(entry: entry, workspace: workspace, tab: tab))
                            .contextMenu { FileContextMenu(workspace: workspace, urls: tab.selection.contains(entry.url) ? workspace.selectedURLs : [entry.url]) }
                            .accessibilityElement(children: .ignore).accessibilityLabel(entry.name)
                            .accessibilityAddTraits(tab.selection.contains(entry.url) ? [.isButton, .isSelected] : .isButton)
                            .accessibilityAction { workspace.tapFile(entry.url, modifiers: []) }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 12)
            }.frame(height: 138)
                .onChange(of: active?.url) { _, url in if let url { proxy.scrollTo(url, anchor: .center) } }
                .onAppear { if let url = active?.url { proxy.scrollTo(url, anchor: .center) } }
        }
    }
    private func step(_ offset: Int) {
        let next = index + offset; guard files.indices.contains(next) else { return }
        workspace.activatePane(); workspace.select(files[next].url, extend: false, range: false)
    }
}
private struct GalleryImageCanvas: View {
    let entry: FileEntry
    @State private var raster: GalleryRaster?
    @State private var failed = false
    @State private var zoom = 1.0
    @State private var turns = 0
    @GestureState private var magnification = 1.0
    @ObservedObject private var input = InputPreferences.shared
    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                if let raster {
                    let rotated = turns % 2 != 0
                    let width = CGFloat(rotated ? raster.image.height : raster.image.width)
                    let height = CGFloat(rotated ? raster.image.width : raster.image.height)
                    let fit = min(max(1, proxy.size.width - 48) / width, max(1, proxy.size.height - 48) / height)
                    let scale = fit * min(8, max(1, zoom * magnification))
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: raster.image, scale: 1).resizable().interpolation(.high)
                            .frame(width: CGFloat(raster.image.width) * scale, height: CGFloat(raster.image.height) * scale)
                            .rotationEffect(.degrees(Double(turns * 90))).frame(width: width * scale, height: height * scale)
                            .padding(24).frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    }.simultaneousGesture(MagnifyGesture().updating($magnification) { value, state, _ in if input.gesturesEnabled { state = value.magnification } }
                        .onEnded { if input.gesturesEnabled { zoom = min(8, max(1, zoom * $0.magnification)) } })
                        .accessibilityLabel("Image preview: " + entry.name)
                } else if failed { NativePreview(url: entry.url).frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { ProgressView("Loading preview…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            HStack(spacing: 8) {
                Text("Preview only").font(.caption).foregroundStyle(.secondary); Spacer()
                CommandIcon("Zoom out", "minus.magnifyingglass", disabled: zoom <= 1 || raster == nil) { zoom = max(1, zoom / 1.5) }
                Button(zoom == 1 ? "Fit" : String(format: "%.0f%%", zoom * 100)) { zoom = 1 }.font(.caption).frame(width: 46, height: input.target).help("Fit image to view")
                CommandIcon("Zoom in", "plus.magnifyingglass", disabled: zoom >= 8 || raster == nil) { zoom = min(8, zoom * 1.5) }
                CommandIcon("Rotate preview clockwise", "rotate.right", disabled: raster == nil) { turns = (turns + 1) % 4 }
            }.padding(.horizontal, 16).frame(height: input.touchFriendly ? 52 : 40)
        }.task(id: entry.modified) {
            raster = nil; failed = false
            do { let image = try await GalleryRasterCache.shared.image(for: entry); if !Task.isCancelled { raster = image } }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}
