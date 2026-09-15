import SwiftUI
import AppKit
import QuickLookThumbnailing
import ExplorerCore

/// No path probing in a row's body. Quick Look supplies asynchronous native
/// icons/thumbnails with single-flight deduplication and bounded concurrency.
@MainActor final class ThumbnailCache {
    static let shared = ThumbnailCache()
    struct Raster: @unchecked Sendable { let image: CGImage }
    typealias Completion = @Sendable (Raster?) -> Void
    typealias Start = @MainActor (QLThumbnailGenerator.Request, @escaping Completion) -> Void
    typealias Cancel = @MainActor (QLThumbnailGenerator.Request) -> Void
    @MainActor private final class Flight {
        let id = UUID()
        let request: QLThumbnailGenerator.Request
        let size: CGFloat
        let cost: Int
        var started = false
        var clients: [UUID: CheckedContinuation<NSImage?, Error>] = [:]
        init(request: QLThumbnailGenerator.Request, size: CGFloat, cost: Int) { self.request = request; self.size = size; self.cost = cost }
    }
    private let cache = NSCache<NSString, NSImage>()
    private let start: Start
    private let cancel: Cancel
    private let limit: Int
    private var flights: [String: Flight] = [:]
    private var queue: [(String, UUID)] = []
    private var queueHead = 0
    private var failures: [String: TimeInterval] = [:]
    private(set) var activeCount = 0
    private(set) var requestStarts = 0
    var pendingCount: Int { flights.count }
    init(limit: Int = 4, start: Start? = nil, cancel: Cancel? = nil) {
        self.limit = max(1, min(limit, 8))
        self.start = start ?? { request, completion in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                completion(representation.map { Raster(image: $0.cgImage) })
            }
        }
        self.cancel = cancel ?? { QLThumbnailGenerator.shared.cancel($0) }
        cache.totalCostLimit = 48 * 1024 * 1024; cache.countLimit = 600
    }
    func image(for entry: FileEntry, size: CGFloat, scale: CGFloat = 2, iconOnly: Bool = false) async throws -> NSImage? {
        try Task.checkCancellation()
        guard entry.isDownloaded, size.isFinite, scale.isFinite, size > 0, scale > 0 else { return nil }
        let side = min(512, max(16, size)), factor = min(3, max(1, scale))
        let icon = iconOnly || side <= 24 || entry.canBrowse
        let key = "\(entry.url.path)|\(entry.modified.timeIntervalSince1970)|\(entry.size)|\(side)|\(factor)|\(icon)"
        if let image = cache.object(forKey: key as NSString) { return image }
        if let failed = failures[key], ProcessInfo.processInfo.systemUptime - failed < 15 { return nil }
        let client = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let flight: Flight
                if let existing = flights[key] { flight = existing }
                else {
                    let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: CGSize(width: side, height: side), scale: factor, representationTypes: icon ? .icon : .all)
                    flight = Flight(request: request, size: side, cost: Int(side * factor * side * factor * 4))
                    flights[key] = flight; queue.append((key, flight.id))
                }
                flight.clients[client] = continuation; pump()
            }
        } onCancel: { Task { @MainActor [weak self] in self?.removeClient(client, key: key) } }
    }
    private func pump() {
        while activeCount < limit, queueHead < queue.count {
            let (key, expectedID) = queue[queueHead]; queueHead += 1
            guard let flight = flights[key], flight.id == expectedID, !flight.started, !flight.clients.isEmpty else { continue }
            flight.started = true; activeCount += 1; requestStarts += 1
            let id = flight.id
            start(flight.request) { [weak self] raster in Task { @MainActor in self?.finish(key: key, id: id, raster: raster) } }
        }
        if queueHead == queue.count { queue.removeAll(keepingCapacity: true); queueHead = 0 }
        else if queueHead > 512 && queueHead > queue.count / 2 { queue.removeFirst(queueHead); queueHead = 0 }
    }
    private func finish(key: String, id: UUID, raster: Raster?) {
        guard let flight = flights[key], flight.id == id else { return }
        flights.removeValue(forKey: key); activeCount -= 1
        let image = raster.map { value in
            let scale = flight.size / CGFloat(max(1, max(value.image.width, value.image.height)))
            return NSImage(cgImage: value.image, size: NSSize(width: CGFloat(value.image.width) * scale, height: CGFloat(value.image.height) * scale))
        }
        if let image { cache.setObject(image, forKey: key as NSString, cost: flight.cost) }
        else {
            if failures.count >= 600 { failures.removeAll(keepingCapacity: true) }
            failures[key] = ProcessInfo.processInfo.systemUptime
        }
        for continuation in flight.clients.values { continuation.resume(returning: image) }; pump()
    }
    private func removeClient(_ client: UUID, key: String) {
        guard let flight = flights[key], let continuation = flight.clients.removeValue(forKey: client) else { return }
        continuation.resume(throwing: CancellationError())
        guard flight.clients.isEmpty else { return }
        flights.removeValue(forKey: key)
        if flight.started { activeCount -= 1; cancel(flight.request) }; pump()
    }
}
struct FileThumbnail: View {
    let entry: FileEntry
    var size: CGFloat = 20
    var iconOnly = false
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?
    private var requestID: String { "\(entry.url.path)|\(entry.modified.timeIntervalSince1970)|\(entry.size)|\(size)|\(scale)|\(iconOnly)" }
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: entry.canBrowse ? "folder.fill" : "doc").resizable().scaledToFit().foregroundStyle(entry.canBrowse ? Color.accentColor : ExplorerDesign.muted) }
        }.frame(width: size, height: size)
            .overlay(alignment: .bottomLeading) {
                if entry.isSymbolicLink { Image(systemName: "arrow.turn.up.right").font(.system(size: max(8, size / 5))).padding(2).background(.regularMaterial, in: Circle()) }
            }
            .task(id: requestID) {
                image = nil
                do {
                    let value = try await ThumbnailCache.shared.image(for: entry, size: size, scale: scale, iconOnly: iconOnly)
                    if !Task.isCancelled { image = value }
                } catch { /* Off-screen consumers never install stale images. */ }
            }.accessibilityHidden(true)
    }
}
