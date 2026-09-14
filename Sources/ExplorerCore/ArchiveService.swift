import Foundation
import CLibArchive

public enum ArchiveService {
    /// ZIP creation uses ditto so macOS resource forks and extended attributes survive.
    /// A process is invoked directly with an argument vector: no shell or string interpolation execution.
    public static func compress(_ sources: [URL], to directory: URL, control: OperationControl) throws -> URL {
        guard !sources.isEmpty else { throw ExplorerError.message("Select files to compress.") }
        let manager = FileManager.default
        let temporary = manager.temporaryDirectory.appendingPathComponent("MacExplorer-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: temporary) }
        let input: URL
        if sources.count == 1 { input = sources[0] }
        else {
            input = temporary.appendingPathComponent("Archive", isDirectory: true)
            try manager.createDirectory(at: input, withIntermediateDirectories: false)
            for source in sources {
                try control.checkpoint()
                try manager.copyItem(at: source, to: FileNames.unique(input.appendingPathComponent(source.lastPathComponent)))
            }
        }
        let name = sources.count == 1 ? sources[0].lastPathComponent + ".zip" : "Archive.zip"
        let target = FileNames.unique(directory.appendingPathComponent(name))
        let stage = directory.appendingPathComponent(".MacExplorer-archive-" + UUID().uuidString)
        defer { if FileNames.exists(stage) { try? manager.removeItem(at: stage) } }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", input.path, stage.path]
        let log = temporary.appendingPathComponent("ditto.log")
        _ = manager.createFile(atPath: log.path, contents: nil)
        let errorFile = try FileHandle(forWritingTo: log); defer { try? errorFile.close() }
        process.standardError = errorFile
        try process.run()
        while process.isRunning {
            if control.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
            Thread.sleep(forTimeInterval: 0.08)
        }
        guard process.terminationStatus == 0 else { throw ExplorerError.message((try? String(contentsOf: log, encoding: .utf8)) ?? "ZIP creation failed.") }
        try control.checkpoint()
        try manager.moveItem(at: stage, to: target)
        return target
    }

    /// Archives are extracted into an isolated new directory. Absolute/traversing paths,
    /// links and special files are rejected, not normalized into apparently safe names.
    /// ZIP, tar, gzip, bzip2 and other formats depend on the macOS libarchive build.
    public static func extract(_ source: URL, to directory: URL, control: OperationControl, maximumBytes: Int64 = 20_000_000_000, maximumEntries: Int = 100_000) throws -> URL {
        let manager = FileManager.default
        let stage = directory.appendingPathComponent(".MacExplorer-extract-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var committed = false
        defer { if !committed { try? manager.removeItem(at: stage) } }
        guard let archive = archive_read_new() else { throw ExplorerError.message("Cannot allocate archive reader.") }
        defer { archive_read_free(archive) }
        archive_read_support_filter_all(archive); archive_read_support_format_all(archive)
        guard archive_read_open_filename(archive, source.path, 65_536) == ARCHIVE_OK else { throw archiveError(archive) }
        var entry: OpaquePointer?, total: Int64 = 0, count = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try control.checkpoint()
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status == ARCHIVE_OK, let entry, let namePointer = archive_entry_pathname(entry) else { throw archiveError(archive) }
            count += 1
            guard count <= maximumEntries else { throw ExplorerError.message("Archive exceeds the 100,000-entry safety limit.") }
            let name = String(cString: namePointer)
            let components = name.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard !name.hasPrefix("/"), !name.contains("\\"), !components.contains(".."), !components.contains(where: { $0.contains(":") }), !components.isEmpty else { throw ExplorerError.message("Unsafe archive path: \(name)") }
            guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil else { throw ExplorerError.message("Archive links are not extracted. Extract this trusted archive with a dedicated archive utility.") }
            let filetype = archive_entry_filetype(entry)
            // POSIX file types are stable across Darwin and libarchive.
            guard filetype == 0o040000 || filetype == 0o100000 else { throw ExplorerError.message("Archive contains a device, socket, or unsupported entry: \(name)") }
            let destination = components.reduce(stage) { $0.appendingPathComponent($1) }
            guard FileNames.isDescendant(destination, of: stage) else { throw ExplorerError.message("Archive entry escapes extraction directory.") }
            if filetype == 0o040000 {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                continue
            }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard !FileNames.exists(destination) else { throw ExplorerError.message("Duplicate archive entry: \(name)") }
            try Data().write(to: destination, options: .withoutOverwriting)
            let handle = try FileHandle(forWritingTo: destination)
            do {
                while true {
                    try control.checkpoint()
                    let read = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, $0.count) }
                    if read == 0 { break }
                    guard read > 0 else { throw archiveError(archive) }
                    total += Int64(read)
                    guard total <= maximumBytes else { throw ExplorerError.message("Archive exceeds the 20 GB expanded-size safety limit.") }
                    try handle.write(contentsOf: Data(buffer.prefix(Int(read))))
                }
                try handle.close()
            } catch { try? handle.close(); throw error }
            let mode = Int(archive_entry_perm(entry)) & 0o777
            try manager.setAttributes([.posixPermissions: mode == 0 ? 0o600 : mode & ~0o022], ofItemAtPath: destination.path)
        }
        let target = FileNames.unique(directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true))
        try manager.moveItem(at: stage, to: target); committed = true
        return target
    }
    private static func archiveError(_ archive: OpaquePointer) -> ExplorerError {
        .message(archive_error_string(archive).map { String(cString: $0) } ?? "Archive operation failed.")
    }
}
