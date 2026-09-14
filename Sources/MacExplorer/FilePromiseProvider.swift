import AppKit
import UniformTypeIdentifiers
import ExplorerCore

/// The pasteboard and delegate metadata stay on MainActor. Only immutable
/// filesystem requests reach the worker queue supplied to AppKit.
@MainActor final class ExplorerPromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    nonisolated let request: FilePromiseExport
    nonisolated private static let sharedQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MacExplorer.file-promise-export"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        return queue
    }()
    nonisolated let queue: OperationQueue

    init(source: URL) throws {
        request = try FilePromiseExport(source: source)
        queue = Self.sharedQueue
        super.init()
    }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        request.source.lastPathComponent
    }
    func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue { queue }
    nonisolated func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                                        completionHandler: @escaping @Sendable (Error?) -> Void) {
        fulfill(to: url, completion: completionHandler)
    }
    /// Shared by the AppKit delegate and native queue-contract tests. The
    /// provider itself never crosses an actor boundary in application code.
    nonisolated func fulfill(to url: URL, completion: @escaping @Sendable (Error?) -> Void) {
        do { try request.write(to: url); completion(nil) }
        catch { completion(error) }
    }
}

/// Export both representations in the same dragging item: existing-file URL for
/// file managers, and a lazy coordinated copy for promise-consuming apps.
@MainActor final class ExplorerFilePromiseProvider: NSFilePromiseProvider {
    static func make(for entry: FileEntry) throws -> ExplorerFilePromiseProvider {
        let delegate = try ExplorerPromiseDelegate(source: entry.url)
        let type = entry.isDirectory ? UTType.folder : UTType(filenameExtension: entry.url.pathExtension) ?? .data
        let provider = ExplorerFilePromiseProvider(fileType: type.identifier, delegate: delegate)
        // NSFilePromiseProvider's delegate is weak. A promised write may outlive
        // the visible drag, the source tile, or even its originating window.
        provider.userInfo = delegate
        return provider
    }
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let types = super.writableTypes(for: pasteboard)
        return types.contains(.fileURL) ? types : types + [.fileURL]
    }
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL { return (userInfo as? ExplorerPromiseDelegate)?.request.source.absoluteString }
        return super.pasteboardPropertyList(forType: type)
    }
    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }
}
