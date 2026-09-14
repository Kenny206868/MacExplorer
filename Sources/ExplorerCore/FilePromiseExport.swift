import Foundation

/// A promise captures the identity at drag time, but performs no copy until the
/// receiver supplies a destination. It never grants permission to move a source.
public struct FilePromiseExport: Sendable {
    public let source: URL
    public let expected: FileFingerprint

    public init(source: URL) throws {
        guard source.isFileURL else { throw ExplorerError.message("A file promise requires a local filesystem URL.") }
        try FileNames.validate(source.lastPathComponent)
        self.source = source
        expected = try FileFingerprint(source)
    }

    public func write(to destination: URL, control: OperationControl = OperationControl()) throws {
        guard destination.isFileURL else { throw ExplorerError.message("The receiver did not supply a filesystem destination.") }
        try FileNames.validate(destination.lastPathComponent)
        guard !FileNames.isDescendant(destination, of: source) else {
            throw ExplorerError.message("A promised folder cannot be copied into itself.")
        }
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var result: Result<Void, Error>?
        coordinator.coordinate(readingItemAt: source, options: [], writingItemAt: destination,
                               options: .forReplacing, error: &coordinationError) { readURL, writeURL in
            result = Result {
                try control.checkpoint()
                guard expected.matches(readURL) else { throw ExplorerError.message("The dragged item changed before its file promise was fulfilled.") }
                guard !FileNames.exists(writeURL) else { throw ExplorerError.message("The receiver's destination is occupied. No file was overwritten.") }
                let manager = FileManager.default
                let parent = writeURL.deletingLastPathComponent()
                let parentIdentity = try FileFingerprint(parent)
                let staging = parent.appendingPathComponent(".MacExplorer-promise-" + UUID().uuidString, isDirectory: true)
                try manager.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let payload = staging.appendingPathComponent("payload")
                defer { try? manager.removeItem(at: staging) }
                try NativeFileCopy.copy(from: readURL, to: payload, control: control)
                try control.checkpoint()
                guard expected.matches(readURL), parentIdentity.matchesIdentity(parent) else {
                    throw ExplorerError.message("The source or receiving folder changed during the promised copy.")
                }
                guard !FileNames.exists(writeURL) else { throw ExplorerError.message("Another item arrived at the receiver's destination. It was not replaced.") }
                // Installation is the commit point. Never cancel by deleting a
                // completed result or by interpreting a drag's Move operation.
                try manager.moveItem(at: payload, to: writeURL)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw ExplorerError.message("The file provider did not grant coordinated access.") }
        try result.get()
    }
}
