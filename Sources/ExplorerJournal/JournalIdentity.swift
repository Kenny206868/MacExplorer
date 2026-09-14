import Foundation
import CJournal

public struct JournalIdentity: Codable, Equatable, Sendable {
    public let inode: UInt64
    public let device: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let mode: UInt32
    public let owner: UInt32
    public var isDirectory: Bool { mode & 0o170000 == 0o040000 }
    public var isRegularFile: Bool { mode & 0o170000 == 0o100000 }
    public var isLink: Bool { mode & 0o170000 == 0o120000 }
    public init(_ url: URL) throws {
        try JournalIdentity.validatePath(url)
        var value = me_file_identity()
        guard me_identity_path(url.path, &value) == 0 else { throw JournalError.io("Read identity of \(url.path)", errno) }
        self.init(value)
    }
    init(_ value: me_file_identity) {
        inode = value.inode; device = value.device; size = value.size
        modifiedSeconds = value.modified_seconds; modifiedNanoseconds = value.modified_nanoseconds
        mode = value.mode; owner = value.owner
    }
    public func isSameObject(as other: JournalIdentity) -> Bool {
        inode != 0 && inode == other.inode && device == other.device && mode & 0o170000 == other.mode & 0o170000
    }
    public func matches(_ url: URL, exact: Bool = true) -> Bool {
        guard let other = try? JournalIdentity(url), isSameObject(as: other) else { return false }
        return !exact || size == other.size && modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
    }
    static func validatePath(_ url: URL) throws {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0"), url.path.utf8.count <= 32_768 else { throw JournalError.unsafe("Invalid filesystem path.") }
    }
}
struct JournalMove: Codable, Sendable {
    let source: URL
    let destination: URL
    let identity: JournalIdentity
    let sourceParent: JournalIdentity
    let destinationParent: JournalIdentity
    let emptyDirectory: Bool
    init(source: URL, destination: URL, emptyDirectory: Bool = false) throws {
        try JournalIdentity.validatePath(source); try JournalIdentity.validatePath(destination)
        self.source = source.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(source.lastPathComponent)
        self.destination = destination.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(destination.lastPathComponent)
        guard self.source.path != self.destination.path, self.source.path != "/", self.destination.path != "/" else { throw JournalError.unsafe("A journaled rename requires distinct non-root paths.") }
        identity = try JournalIdentity(self.source)
        sourceParent = try JournalIdentity(self.source.deletingLastPathComponent())
        destinationParent = try JournalIdentity(self.destination.deletingLastPathComponent())
        guard sourceParent.isDirectory, destinationParent.isDirectory, sourceParent.device == destinationParent.device else {
            throw JournalError.unsafe("Journaled renames must stay on one volume; stage cross-volume copies separately.")
        }
        self.emptyDirectory = emptyDirectory
    }
    func matches(_ url: URL) -> Bool {
        if emptyDirectory {
            return identity.isDirectory && identity.matches(url, exact: false) && (try? FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty) == true
        }
        return identity.matches(url)
    }
}
public enum JournalDurability {
    /// Sync completed staging before installation, never following links.
    public static func synchronizeTree(_ url: URL, checkpoint: () throws -> Void = {}) throws {
        try checkpoint()
        let item = try JournalIdentity(url)
        if item.isLink { return }
        if item.isRegularFile {
            guard me_sync_path(url.path) >= 0 else { throw JournalError.io("Synchronize staged file", errno) }; return
        }
        guard item.isDirectory else { throw JournalError.unsafe("Cannot install a special filesystem object.") }
        var directories: [URL] = [url], enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { _, error in enumerationError = error; return false }) else { throw JournalError.unsafe("Cannot enumerate staging directory.") }
        for case let child as URL in enumerator {
            try checkpoint(); let childIdentity = try JournalIdentity(child)
            if childIdentity.isDirectory { directories.append(child) }
            else if childIdentity.isRegularFile {
                guard me_sync_path(child.path) >= 0 else { throw JournalError.io("Synchronize staged file", errno) }
            } else if !childIdentity.isLink { throw JournalError.unsafe("Staging contains a special filesystem object.") }
        }
        if let enumerationError { throw enumerationError }
        for directory in directories.reversed() {
            let fd = me_open_directory(directory.path); guard fd >= 0 else { throw JournalError.io("Open staging directory", errno) }
            let result = me_sync_directory(fd), code = errno; me_close(fd)
            guard result >= 0 else { throw JournalError.io("Synchronize staging directory", code) }
        }
    }
}
/// Open parent descriptors pin both endpoints. Exclusive rename makes the
/// no-clobber rule atomic, rather than exists() followed by a clobbering rename.
func journalRename(_ move: JournalMove, reverse: Bool) throws {
    let from = reverse ? move.destination : move.source, to = reverse ? move.source : move.destination
    let fromParent = reverse ? move.destinationParent : move.sourceParent
    let toParent = reverse ? move.sourceParent : move.destinationParent
    let sourceFD = me_open_directory(from.deletingLastPathComponent().path)
    guard sourceFD >= 0 else { throw JournalError.io("Open source parent", errno) }
    defer { me_close(sourceFD) }
    let destinationFD = me_open_directory(to.deletingLastPathComponent().path)
    guard destinationFD >= 0 else { throw JournalError.io("Open destination parent", errno) }
    defer { me_close(destinationFD) }
    var sourceDirectory = me_file_identity(), destinationDirectory = me_file_identity(), item = me_file_identity()
    guard me_identity_fd(sourceFD, &sourceDirectory) == 0, fromParent.isSameObject(as: JournalIdentity(sourceDirectory)),
          me_identity_fd(destinationFD, &destinationDirectory) == 0, toParent.isSameObject(as: JournalIdentity(destinationDirectory)),
          me_identity_at(sourceFD, from.lastPathComponent, &item) == 0, move.identity.isSameObject(as: JournalIdentity(item)),
          move.matches(from) else { throw JournalError.conflict("A parent or source changed. No rename was performed.") }
    guard me_rename_exclusive(sourceFD, from.lastPathComponent, destinationFD, to.lastPathComponent) == 0 else { throw JournalError.io("Rename without replacement", errno) }
    guard me_sync_directory(sourceFD) >= 0, me_sync_directory(destinationFD) >= 0 else { throw JournalError.io("Synchronize rename directories", errno) }
}
