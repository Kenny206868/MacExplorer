import Foundation
import CLibArchive
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Passwords stay in memory, never in preferences, receipts or arguments.
public struct ArchiveReadOptions: Sendable {
    public let passphrase: String?
    public let selectedPaths: Set<String>?
    public let maximumBytes: Int64
    public let maximumEntries: Int
    public init(passphrase: String? = nil, selectedPaths: Set<String>? = nil,
                maximumBytes: Int64 = 20_000_000_000, maximumEntries: Int = 100_000) {
        self.passphrase = passphrase?.isEmpty == false ? passphrase : nil
        self.selectedPaths = selectedPaths
        self.maximumBytes = max(0, maximumBytes); self.maximumEntries = max(0, maximumEntries)
    }
    func includes(_ path: String) -> Bool {
        guard let selectedPaths else { return true }
        return selectedPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
public struct ArchiveMember: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let encrypted: Bool
    public let modified: Date?
    public let unsupportedReason: String?
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}
public struct ArchiveCatalog: Sendable {
    public let members: [ArchiveMember]
    public let format: String
    public let logicalBytes: Int64
    public var containsEncryption: Bool { members.contains(where: \.encrypted) }
    public func children(of folder: String = "") -> [ArchiveMember] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        var children: [String: ArchiveMember] = [:]
        for member in members where member.path.hasPrefix(prefix) {
            let remainder = String(member.path.dropFirst(prefix.count))
            guard !remainder.isEmpty else { continue }
            if let separator = remainder.firstIndex(of: "/") {
                let path = prefix + remainder[..<separator]
                if children[path] == nil { children[path] = ArchiveMember(path: path, isDirectory: true, size: 0, encrypted: false, modified: nil, unsupportedReason: nil) }
            } else { children[member.path] = member }
        }
        return children.values.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    public static func read(_ source: URL, options: ArchiveReadOptions = ArchiveReadOptions(),
                            control: OperationControl = OperationControl()) throws -> ArchiveCatalog {
        let reader = try ArchiveReader(source: source, options: options)
        var members: [ArchiveMember] = [], total: Int64 = 0, seen = Set<String>(), headers = 0
        while let entry = try reader.next(control: control) {
            headers += 1
            guard headers <= options.maximumEntries else { throw ExplorerError.message("Archive exceeds the configured entry limit.") }
            guard let path = try ArchivePath.parse(reader.name(entry), directory: archive_entry_filetype(entry) == 0o040000) else { continue }
            guard seen.insert(path).inserted else { throw ExplorerError.message("Duplicate archive entry: \(path)") }
            let size = archive_entry_size_is_set(entry) != 0 ? max(0, archive_entry_size(entry)) : 0
            let (next, overflow) = total.addingReportingOverflow(size)
            guard !overflow, next <= options.maximumBytes else { throw ExplorerError.message("Archive exceeds the configured expanded-size limit.") }
            total = next
            let type = archive_entry_filetype(entry)
            let unsupported = archive_entry_symlink(entry) != nil || archive_entry_hardlink(entry) != nil
                ? "Archive links are not extracted" : type == 0o040000 || type == 0o100000 ? nil : "Unsupported special filesystem object"
            members.append(ArchiveMember(path: path, isDirectory: type == 0o040000, size: size,
                encrypted: archive_entry_is_encrypted(entry) != 0, modified: ArchiveReader.modificationDate(entry), unsupportedReason: unsupported))
        }
        return ArchiveCatalog(members: members, format: archive_format_name(reader.handle).map { String(cString: $0) } ?? "Archive", logicalBytes: total)
    }
}
public enum ArchivePath {
    public static func parse(_ name: String, directory: Bool) throws -> String? {
        guard !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"), !name.contains("\0"), name.utf8.count <= 8192 else { throw ExplorerError.message("Unsafe archive path: \(name)") }
        var components = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        while components.first == "." { components.removeFirst() }
        if components.isEmpty, directory { return nil }
        guard !components.isEmpty, components.count <= 128 else { throw ExplorerError.message("Invalid or excessively deep archive path.") }
        for component in components { try FileNames.validate(component) }
        return components.joined(separator: "/")
    }
}
final class ArchiveReader {
    let handle: OpaquePointer
    private let descriptor: Int32
    init(source: URL, options: ArchiveReadOptions) throws { (handle, descriptor) = try Self.open(source: source, options: options) }
    private static func open(source: URL, options: ArchiveReadOptions) throws -> (OpaquePointer, Int32) {
        guard source.isFileURL else { throw ExplorerError.message("Select a local archive file.") }
        guard let handle = archive_read_new() else { throw ExplorerError.message("Cannot allocate an archive reader.") }
        archive_read_support_filter_all(handle); archive_read_support_format_all(handle)
        if let passphrase = options.passphrase {
            guard passphrase.utf8.count <= 4096, !passphrase.contains("\0"),
                  passphrase.withCString({ archive_read_add_passphrase(handle, $0) }) == ARCHIVE_OK else {
                archive_read_free(handle); throw ExplorerError.message("The archive password is empty, invalid, or too long.")
            }
        }
        let fd = source.withUnsafeFileSystemRepresentation { path in
            #if canImport(Darwin)
            Darwin.open(path!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            #else
            Glibc.open(path!, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            #endif
        }
        guard fd >= 0 else { archive_read_free(handle); throw ExplorerError.message("Cannot open archive without following symbolic links.") }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & 0o170000 == 0o100000 else { close(fd); archive_read_free(handle); throw ExplorerError.message("Select an ordinary archive file.") }
        guard archive_read_open_fd(handle, fd, 65_536) == ARCHIVE_OK else {
            let error = Self.error(handle); archive_read_free(handle); close(fd); throw error
        }
        return (handle, fd)
    }
    deinit { archive_read_free(handle); close(descriptor) }
    func next(control: OperationControl) throws -> OpaquePointer? {
        try control.checkpoint()
        var entry: OpaquePointer?
        let status = archive_read_next_header(handle, &entry)
        if status == ARCHIVE_EOF { return nil }
        guard status == ARCHIVE_OK, let entry else { throw Self.error(handle) }; return entry
    }
    func name(_ entry: OpaquePointer) throws -> String {
        guard let value = archive_entry_pathname(entry) else { throw ExplorerError.message("Archive entry has no name.") }; return String(cString: value)
    }
    static func modificationDate(_ entry: OpaquePointer) -> Date? {
        guard archive_entry_mtime_is_set(entry) != 0 else { return nil }
        let value = Double(archive_entry_mtime(entry)) + Double(archive_entry_mtime_nsec(entry)) / 1_000_000_000
        guard value.isFinite, (-62_135_596_800...253_402_300_799).contains(value) else { return nil }; return Date(timeIntervalSince1970: value)
    }
    static func error(_ handle: OpaquePointer) -> ExplorerError { .message(archive_error_string(handle).map { String(cString: $0) } ?? "Archive operation failed.") }
}
