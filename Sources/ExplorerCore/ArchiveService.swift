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

    /// Staging is private and installation is all-or-nothing. Passwords are passed
    /// directly to libarchive, never to a subprocess or persistent model.
    public static func extract(_ source: URL, to directory: URL, control: OperationControl,
                               maximumBytes: Int64 = 20_000_000_000, maximumEntries: Int = 100_000,
                               options: ArchiveReadOptions? = nil) throws -> URL {
        let options = options ?? ArchiveReadOptions(maximumBytes: maximumBytes, maximumEntries: maximumEntries)
        let manager = FileManager.default
        let sourceIdentity = try FileFingerprint(source)
        let parentIdentity = try FileFingerprint(directory)
        let quarantine = try (source as NSURL).resourceValues(forKeys: [.quarantinePropertiesKey])[.quarantinePropertiesKey]
        let stage = directory.appendingPathComponent(".MacExplorer-extract-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var committed = false
        defer { if !committed { try? manager.removeItem(at: stage) } }
        let reader = try ArchiveReader(source: source, options: options)
        var total: Int64 = 0, declaredTotal: Int64 = 0, count = 0, seen = Set<String>()
        var directories: [(URL, Date?)] = []
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while let entry = try reader.next(control: control) {
            count += 1
            guard count <= options.maximumEntries else { throw ExplorerError.message("Archive exceeds the configured entry limit.") }
            let type = archive_entry_filetype(entry)
            guard let name = try ArchivePath.parse(reader.name(entry), directory: type == 0o040000) else { continue }
            guard seen.insert(name).inserted else { throw ExplorerError.message("Duplicate archive entry: \(name)") }
            guard archive_entry_symlink(entry) == nil, archive_entry_hardlink(entry) == nil,
                  type == 0o040000 || type == 0o100000 else {
                throw ExplorerError.message("Archive contains a link or unsupported special object: \(name)")
            }
            let declared = archive_entry_size_is_set(entry) != 0 ? max(0, archive_entry_size(entry)) : 0
            let (nextDeclared, overflow) = declaredTotal.addingReportingOverflow(declared)
            guard !overflow, nextDeclared <= options.maximumBytes else { throw ExplorerError.message("Archive exceeds the configured expanded-size limit.") }
            declaredTotal = nextDeclared
            guard options.includes(name) else { continue }
            let destination = name.split(separator: "/").reduce(stage) { $0.appendingPathComponent(String($1)) }
            guard FileNames.isDescendant(destination, of: stage) else { throw ExplorerError.message("Archive entry escapes extraction directory.") }
            if type == 0o040000 {
                try manager.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                directories.append((destination, ArchiveReader.modificationDate(entry)))
                continue
            }
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard !FileNames.exists(destination) else { throw ExplorerError.message("Duplicate archive entry: \(name)") }
            try Data().write(to: destination, options: .withoutOverwriting)
            let output = try FileHandle(forWritingTo: destination)
            do {
                while true {
                    try control.checkpoint()
                    let read = buffer.withUnsafeMutableBytes { archive_read_data(reader.handle, $0.baseAddress, $0.count) }
                    if read == 0 { break }
                    guard read > 0 else { throw ArchiveReader.error(reader.handle) }
                    let (next, overflow) = total.addingReportingOverflow(Int64(read))
                    guard !overflow, next <= options.maximumBytes else { throw ExplorerError.message("Archive exceeds the configured expanded-size limit.") }
                    total = next
                    try output.write(contentsOf: Data(buffer.prefix(Int(read))))
                }
                try output.close()
            } catch { try? output.close(); throw error }
            let mode = Int(archive_entry_perm(entry)) & 0o777
            // Keep the owner able to manage the new working copy, remove set-id
            // and group/world write bits; never recreate archived ownership.
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: (mode & ~0o022) | 0o600]
            if let date = ArchiveReader.modificationDate(entry) { attributes[.modificationDate] = date }
            try manager.setAttributes(attributes, ofItemAtPath: destination.path)
        }
        for (url, date) in directories.reversed() {
            if let date { try manager.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        }
        if let quarantine {
            try (stage as NSURL).setResourceValue(quarantine, forKey: .quarantinePropertiesKey)
            if let enumerator = manager.enumerator(at: stage, includingPropertiesForKeys: nil) {
                for case let url as URL in enumerator {
                    try control.checkpoint()
                    try (url as NSURL).setResourceValue(quarantine, forKey: .quarantinePropertiesKey)
                }
            }
        }
        try control.checkpoint()
        guard sourceIdentity.matches(source), parentIdentity.matchesIdentity(directory) else {
            throw ExplorerError.message("The archive or destination folder changed during extraction. Nothing was installed.")
        }
        let target = FileNames.unique(directory.appendingPathComponent(source.deletingPathExtension().lastPathComponent, isDirectory: true))
        try manager.moveItem(at: stage, to: target); committed = true
        return target
    }
}
