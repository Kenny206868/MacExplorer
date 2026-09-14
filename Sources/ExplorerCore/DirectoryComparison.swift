import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum ComparisonMode: String, CaseIterable, Sendable { case metadata = "Size & date", contents = "File data" }
public enum ComparisonNamePolicy: String, CaseIterable, Sendable { case exact = "Exact names", ignoreCase = "Ignore case" }
public enum ComparisonStatus: String, CaseIterable, Sendable {
    case leftOnly = "Only in first pane", rightOnly = "Only in second pane"
    case metadataMatch = "Matching metadata", matchingData = "Matching file data", different = "Different"
    case typeConflict = "Different types", ambiguous = "Ambiguous names", notCompared = "Not compared", unavailable = "Unavailable"
    public var isDifference: Bool { [.leftOnly, .rightOnly, .different, .typeConflict, .ambiguous].contains(self) }
    public var isUnverified: Bool { [.metadataMatch, .notCompared, .unavailable, .ambiguous].contains(self) }
}

/// Own stat snapshot, including nanosecond modification/change times. Access
/// time is intentionally excluded: a read may update it. Never follows links.
public struct ComparisonStamp: Equatable, Sendable {
    public enum Kind: String, Sendable { case file, folder, link, other }
    public let device: UInt64
    public let inode: UInt64
    public let size: Int64
    public let kind: Kind
    public let modified: Date
    public let dataless: Bool
    public let hidden: Bool
    private let mode: UInt32
    private let flags: UInt32
    private let modifiedSeconds: Int64, modifiedNanoseconds: Int64
    private let changedSeconds: Int64, changedNanoseconds: Int64
    init(_ value: stat) {
        device = UInt64(truncatingIfNeeded: value.st_dev); inode = UInt64(value.st_ino)
        size = max(0, Int64(value.st_size)); mode = UInt32(value.st_mode)
        switch value.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFREG): kind = .file
        case mode_t(S_IFDIR): kind = .folder
        case mode_t(S_IFLNK): kind = .link
        default: kind = .other
        }
        #if canImport(Darwin)
        modifiedSeconds = Int64(value.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(value.st_mtimespec.tv_nsec)
        changedSeconds = Int64(value.st_ctimespec.tv_sec); changedNanoseconds = Int64(value.st_ctimespec.tv_nsec)
        flags = value.st_flags; dataless = value.st_flags & UInt32(SF_DATALESS) != 0
        hidden = value.st_flags & UInt32(UF_HIDDEN) != 0
        #else
        modifiedSeconds = Int64(value.st_mtim.tv_sec); modifiedNanoseconds = Int64(value.st_mtim.tv_nsec)
        changedSeconds = Int64(value.st_ctim.tv_sec); changedNanoseconds = Int64(value.st_ctim.tv_nsec)
        flags = 0; dataless = false; hidden = false
        #endif
        modified = Date(timeIntervalSince1970: Double(modifiedSeconds) + Double(modifiedNanoseconds) / 1_000_000_000)
    }
    public static func read(_ url: URL) throws -> ComparisonStamp {
        guard url.isFileURL else { throw ExplorerError.message("Comparison requires filesystem folders.") }
        var value = stat()
        guard url.withUnsafeFileSystemRepresentation({ pointer -> Int32 in
            guard let pointer else { errno = EINVAL; return -1 }; return lstat(pointer, &value) }) == 0 else { throw comparisonError(url.lastPathComponent) }
        return ComparisonStamp(value)
    }
    func matchesMetadata(_ other: ComparisonStamp) -> Bool {
        size == other.size && modifiedSeconds == other.modifiedSeconds && modifiedNanoseconds == other.modifiedNanoseconds
    }
    func matchesIdentity(_ other: ComparisonStamp) -> Bool { device == other.device && inode == other.inode && kind == other.kind }
}
public struct ComparisonFile: Sendable {
    public let url: URL
    public let name: String
    public let stamp: ComparisonStamp?
    public let error: String?
}
public struct ComparisonRow: Identifiable, Sendable {
    public let id: String
    public let left: [ComparisonFile]
    public let right: [ComparisonFile]
    public let status: ComparisonStatus
    public let detail: String
    public var name: String { left.first?.name ?? right.first?.name ?? id }
}
public struct ComparisonRequest: Sendable {
    public let left: URL, right: URL
    public var mode: ComparisonMode = .metadata
    public var namePolicy: ComparisonNamePolicy = .exact
    public var includeHidden = false
    public var maximumEntriesPerFolder = 25_000
    /// Total data read across both sides, not a per-file allowance.
    public var maximumReadBytes: Int64 = 2 * 1024 * 1024 * 1024
    public init(left: URL, right: URL) { self.left = left; self.right = right }
}
public struct ComparisonProgress: Sendable {
    public let completed: Int, total: Int
    public let name: String
    public let bytesRead: Int64
}
public struct ComparisonReport: Sendable {
    public let request: ComparisonRequest
    public let leftStamp: ComparisonStamp, rightStamp: ComparisonStamp
    public let rows: [ComparisonRow]
    public let bytesRead: Int64
    public let date: Date
    /// Used immediately before selecting report items in the original panes.
    /// Opening descriptors again also rejects replaced or linked roots.
    public func validate(_ selected: [ComparisonRow]) throws {
        let left = try ComparisonDirectory(request.left), right = try ComparisonDirectory(request.right)
        guard left.stamp == leftStamp, right.stamp == rightStamp else { throw ExplorerError.message("A compared folder changed. Run the comparison again.") }
        for row in selected {
            for item in row.left { guard let stamp = item.stamp, try left.snapshot(item.name) == stamp else { throw ExplorerError.message("A compared file changed: \(item.name)") } }
            for item in row.right { guard let stamp = item.stamp, try right.snapshot(item.name) == stamp else { throw ExplorerError.message("A compared file changed: \(item.name)") } }
        }
        try left.validate(); try right.validate()
    }
}

/// Read-only, one-directory-level comparison. Run off MainActor. Directory FDs
/// anchor reads; openat/fstatat do not follow child links. No writes, recursion,
/// sync, timestamp changes, metadata updates or explicit cloud downloads.
public enum DirectoryComparison {
    public static func compare(_ request: ComparisonRequest,
                               checkpoint: () throws -> Void = { try Task.checkCancellation() },
                               progress: (ComparisonProgress) -> Void = { _ in }) throws -> ComparisonReport {
        guard (1...100_000).contains(request.maximumEntriesPerFolder), request.maximumReadBytes >= 0 else {
            throw ExplorerError.message("Invalid comparison resource limits.")
        }
        try checkpoint()
        let left = try ComparisonDirectory(request.left), right = try ComparisonDirectory(request.right)
        let lhs = try left.list(request: request, checkpoint: checkpoint), rhs = try right.list(request: request, checkpoint: checkpoint)
        let a = Dictionary(grouping: lhs) { key($0.name, request.namePolicy) }, b = Dictionary(grouping: rhs) { key($0.name, request.namePolicy) }
        let keys = Set(a.keys).union(b.keys).sorted()
        var rows: [ComparisonRow] = [], bytes: Int64 = 0
        let bufferSize = 128 * 1024
        let firstBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        let secondBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        defer { firstBuffer.deallocate(); secondBuffer.deallocate() }
        for name in keys {
            try checkpoint()
            let first = (a[name] ?? []).sorted { $0.name < $1.name }, second = (b[name] ?? []).sorted { $0.name < $1.name }
            progress(ComparisonProgress(completed: rows.count, total: keys.count, name: first.first?.name ?? second.first?.name ?? name, bytesRead: bytes))
            try checkpoint()
            var status: ComparisonStatus = .notCompared, detail = ""
            if first.count > 1 || second.count > 1 { status = .ambiguous; detail = "Multiple names match under this name policy. No pairing was assumed." }
            else if first.isEmpty { status = .rightOnly; detail = "No corresponding name in the first folder." }
            else if second.isEmpty { status = .leftOnly; detail = "No corresponding name in the second folder." }
            else if let x = first[0].stamp, let y = second[0].stamp {
                if x.kind != y.kind { status = .typeConflict; detail = "\(x.kind.rawValue.capitalized) versus \(y.kind.rawValue)." }
                else if x.kind != .file { detail = "Folders, packages, links and special files are not traversed or compared." }
                else if request.mode == .metadata {
                    status = x.matchesMetadata(y) ? .metadataMatch : .different
                    detail = "Size and modification time only; file data was not read."
                } else if x.size != y.size { status = .different; detail = "File sizes differ." }
                else if x.dataless || y.dataless { status = .unavailable; detail = "Online-only file. Download it explicitly before comparing data." }
                else if x.size > (request.maximumReadBytes - bytes) / 2 { detail = "This file exceeds the remaining data-read budget." }
                else {
                    do {
                        let result = try dataMatches(first[0], second[0], left: left, right: right,
                            first: firstBuffer, second: secondBuffer, bufferSize: bufferSize, checkpoint: checkpoint) { count in bytes += count }
                        status = result ? .matchingData : .different
                        detail = result ? "Main file data matches byte for byte. Extended attributes, permissions and resource forks were not compared." : "Main file data differs."
                    } catch is CancellationError { throw CancellationError() }
                    catch { status = .unavailable; detail = error.localizedDescription }
                }
            } else { status = .unavailable; detail = first[0].error ?? second[0].error ?? "Metadata unavailable." }
            // Re-check every named object, including one-sided/metadata-only rows.
            do {
                for item in first { guard let stamp = item.stamp, try left.snapshot(item.name) == stamp else { throw ExplorerError.message("File changed during comparison: \(item.name)") } }
                for item in second { guard let stamp = item.stamp, try right.snapshot(item.name) == stamp else { throw ExplorerError.message("File changed during comparison: \(item.name)") } }
            } catch { status = .unavailable; detail = error.localizedDescription }
            rows.append(ComparisonRow(id: name, left: first, right: second, status: status, detail: detail))
        }
        try checkpoint(); try left.validate(); try right.validate()
        progress(ComparisonProgress(completed: rows.count, total: keys.count, name: "Finished", bytesRead: bytes))
        try checkpoint()
        return ComparisonReport(request: request, leftStamp: left.stamp, rightStamp: right.stamp, rows: rows, bytesRead: bytes, date: Date())
    }
    private static func key(_ name: String, _ policy: ComparisonNamePolicy) -> String {
        // Swift strings compare canonical-equivalent spellings equally. Multiple
        // such names form an ambiguous group rather than overwriting one row.
        policy == .exact ? name : name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    private static func dataMatches(_ a: ComparisonFile, _ b: ComparisonFile, left: ComparisonDirectory, right: ComparisonDirectory,
                                    first: UnsafeMutableRawPointer, second: UnsafeMutableRawPointer, bufferSize: Int,
                                    checkpoint: () throws -> Void, readBytes: (Int64) -> Void) throws -> Bool {
        let fdA = try left.openFile(a); defer { close(fdA) }
        let fdB = try right.openFile(b); defer { close(fdB) }
        let size = a.stamp?.size ?? 0
        var offset: Int64 = 0, matches = true
        while offset < size {
            try checkpoint()
            let count = Int(min(Int64(bufferSize), size - offset))
            try readChunk(fdA, first, count, checkpoint: checkpoint, readBytes: readBytes)
            try readChunk(fdB, second, count, checkpoint: checkpoint, readBytes: readBytes)
            if memcmp(first, second, count) != 0 { matches = false; break }
            offset += Int64(count)
        }
        var currentA = stat(), currentB = stat()
        guard fstat(fdA, &currentA) == 0, fstat(fdB, &currentB) == 0,
              ComparisonStamp(currentA) == a.stamp, ComparisonStamp(currentB) == b.stamp else {
            throw ExplorerError.message("A file changed while its data was being read.")
        }
        try checkpoint(); return matches
    }
    private static func readChunk(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int,
                                  checkpoint: () throws -> Void, readBytes: (Int64) -> Void) throws {
        var offset = 0
        while offset < count {
            try checkpoint()
            let result = read(fd, buffer.advanced(by: offset), count - offset)
            if result < 0 { if errno == EINTR { continue }; throw comparisonError("File data") }
            guard result > 0 else { throw ExplorerError.message("A file was truncated during comparison.") }
            offset += result; readBytes(Int64(result))
        }
    }
}

private final class ComparisonDirectory {
    let url: URL, descriptor: Int32, stamp: ComparisonStamp
    init(_ url: URL) throws {
        guard url.isFileURL else { throw ExplorerError.message("Choose filesystem folders in both panes.") }
        self.url = url.standardizedFileURL
        let before = try ComparisonStamp.read(self.url)
        guard before.kind == .folder, !before.dataless else { throw ExplorerError.message("Choose an available folder, not a link or online-only placeholder.") }
        descriptor = self.url.withUnsafeFileSystemRepresentation { pointer -> Int32 in
            guard let pointer else { errno = EINVAL; return -1 }; return open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard descriptor >= 0 else { throw comparisonError(url.lastPathComponent) }
        var value = stat()
        guard fstat(descriptor, &value) == 0, ComparisonStamp(value) == before else {
            close(descriptor); throw ExplorerError.message("The folder changed while comparison was starting.")
        }
        stamp = before
    }
    deinit { close(descriptor) }
    func validate() throws {
        var value = stat()
        guard fstat(descriptor, &value) == 0, ComparisonStamp(value) == stamp, try ComparisonStamp.read(url) == stamp else {
            throw ExplorerError.message("A folder changed during comparison. Run it again for a complete result.")
        }
    }
    func snapshot(_ name: String) throws -> ComparisonStamp {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else { throw ExplorerError.message("Invalid comparison filename.") }
        var value = stat()
        guard name.withCString({ fstatat(descriptor, $0, &value, AT_SYMLINK_NOFOLLOW) }) == 0 else { throw comparisonError(name) }
        return ComparisonStamp(value)
    }
    func list(request: ComparisonRequest, checkpoint: () throws -> Void) throws -> [ComparisonFile] {
        let copy = dup(descriptor)
        guard copy >= 0 else { throw comparisonError(url.lastPathComponent) }
        guard let directory = fdopendir(copy) else { close(copy); throw comparisonError(url.lastPathComponent) }
        defer { closedir(directory) }
        var result: [ComparisonFile] = [], count = 0
        while true {
            try checkpoint(); errno = 0
            guard let entry = readdir(directory) else { if errno != 0 { throw comparisonError(url.lastPathComponent) }; break }
            guard let name = withUnsafeBytes(of: entry.pointee.d_name, { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }) else { throw ExplorerError.message("A filename is not valid Unicode; comparison was stopped rather than omitting it.") }
            if name == "." || name == ".." { continue }
            count += 1
            guard count <= request.maximumEntriesPerFolder else { throw ExplorerError.message("This folder exceeds the \(request.maximumEntriesPerFolder)-entry comparison limit. No partial comparison was presented.") }
            if !request.includeHidden && name.hasPrefix(".") { continue }
            do {
                let stamp = try snapshot(name)
                if !request.includeHidden && stamp.hidden { continue }
                result.append(ComparisonFile(url: url.appendingPathComponent(name), name: name, stamp: stamp, error: nil))
            } catch { result.append(ComparisonFile(url: url.appendingPathComponent(name), name: name, stamp: nil, error: error.localizedDescription)) }
        }
        try validate(); return result
    }
    func openFile(_ file: ComparisonFile) throws -> Int32 {
        guard let expected = file.stamp, expected.kind == .file, !expected.dataless, try snapshot(file.name) == expected else {
            throw ExplorerError.message("File is unavailable or changed before reading: \(file.name)")
        }
        let fd = file.name.withCString { openat(descriptor, $0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) }
        guard fd >= 0 else { throw comparisonError(file.name) }
        var value = stat()
        guard fstat(fd, &value) == 0, ComparisonStamp(value) == expected else { close(fd); throw ExplorerError.message("File changed while opening: \(file.name)") }
        return fd
    }
}
private func comparisonError(_ name: String) -> Error {
    let code = errno
    return NSError(domain: NSPOSIXErrorDomain, code: Int(code == 0 ? EIO : code), userInfo: [NSLocalizedDescriptionKey: "\(name): \(String(cString: strerror(code == 0 ? EIO : code)))"])
}
