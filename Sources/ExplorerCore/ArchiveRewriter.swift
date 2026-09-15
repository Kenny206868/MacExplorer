import Foundation
import CLibArchive
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Streaming reconstruction into a private, absent destination. No extraction,
/// in-place truncation, password downgrade, or unbounded member buffering.
enum ArchiveRewriter {
    static func rewrite(_ source: URL, to target: URL, mutation: ArchiveMutation,
                        control: OperationControl, options: ArchiveReadOptions = ArchiveReadOptions()) throws {
        let original = try FileFingerprint(source)
        let catalog = try ArchiveCatalog.read(source, options: options, control: control)
        let members = Dictionary(uniqueKeysWithValues: catalog.members.map { ($0.path, $0) })
        let plan = try ArchiveEditPlan(catalog: catalog, mutation: mutation, options: options, control: control)
        guard original.matches(source) else { throw ExplorerError.message("The archive changed while preparing its edit.") }
        let reader = try ArchiveReader(source: source, options: options)
        var entry = try reader.next(control: control)
        let format = archive_format(reader.handle) & ARCHIVE_FORMAT_BASE_MASK
        let filters = (0..<archive_filter_count(reader.handle)).map { archive_filter_code(reader.handle, $0) }.filter { $0 != ARCHIVE_FILTER_NONE }
        guard (format == ARCHIVE_FORMAT_ZIP && filters.isEmpty) || (format == ARCHIVE_FORMAT_TAR && filters.count <= 1 && filters.allSatisfy { [ARCHIVE_FILTER_GZIP, ARCHIVE_FILTER_BZIP2, ARCHIVE_FILTER_XZ].contains($0) }) else {
            throw ExplorerError.message("Editing supports unencrypted ZIP and TAR (plain, gzip, bzip2, or xz). This format remains read-only.")
        }
        guard let writer = archive_write_new() else { throw ExplorerError.message("Cannot allocate archive writer.") }
        defer { archive_write_free(writer) }
        func check(_ status: Int32) throws { guard status == ARCHIVE_OK else { throw ArchiveReader.error(writer) } }
        try check(format == ARCHIVE_FORMAT_ZIP ? archive_write_set_format_zip(writer) : archive_write_set_format_pax_restricted(writer))
        if let filter = filters.first {
            switch filter {
            case ARCHIVE_FILTER_GZIP: try check(archive_write_add_filter_gzip(writer))
            case ARCHIVE_FILTER_BZIP2: try check(archive_write_add_filter_bzip2(writer))
            default: try check(archive_write_add_filter_xz(writer))
            }
        }
        let fd = open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ExplorerError.message("Cannot create a private archive candidate: " + String(cString: strerror(errno))) }
        defer { close(fd) }
        try check(archive_write_open_fd(writer, fd))
        var buffer = [UInt8](repeating: 0, count: 65_536), total: Int64 = 0, seen = Set<String>()
        func write(_ bytes: UnsafeRawBufferPointer) throws {
            var offset = 0
            while offset < bytes.count {
                try control.checkpoint()
                let count = archive_write_data(writer, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0, count <= bytes.count - offset else { throw ArchiveReader.error(writer) }; offset += count
            }
        }
        func account(_ count: Int) throws {
            let (sum, overflow) = total.addingReportingOverflow(Int64(count))
            guard !overflow, sum <= options.maximumBytes else { throw ExplorerError.message("Expanded archive data exceeds the configured limit.") }; total = sum
        }
        while let value = entry {
            try control.checkpoint()
            let directory = archive_entry_filetype(value) == 0o040000
            if let path = try ArchivePath.parse(reader.name(value), directory: directory) {
                guard seen.insert(path).inserted, seen.count <= options.maximumEntries,
                      let member = members[path], member.isDirectory == directory,
                      archive_entry_is_encrypted(value) == 0, archive_entry_symlink(value) == nil, archive_entry_hardlink(value) == nil else { throw ExplorerError.message("The archive changed or contains unsupported entries.") }
                if !plan.removed.contains(path) {
                    guard let clone = archive_entry_clone(value) else { throw ExplorerError.message("Cannot allocate archive entry.") }
                    defer { archive_entry_free(clone) }
                    (plan.mapping[path] ?? path).withCString { archive_entry_set_pathname(clone, $0) }
                    try check(archive_write_header(writer, clone))
                    var bytes: Int64 = 0
                    while true {
                        try control.checkpoint()
                        let count = buffer.withUnsafeMutableBytes { archive_read_data(reader.handle, $0.baseAddress, $0.count) }
                        if count == 0 { break }
                        guard count > 0 else { throw ArchiveReader.error(reader.handle) }
                        try account(count); bytes += Int64(count)
                        guard bytes <= member.size else { throw ExplorerError.message("An archive entry expanded beyond its declared size.") }
                        try buffer.withUnsafeBytes { try write(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
                    }
                    guard directory || bytes == member.size else { throw ExplorerError.message("Truncated archive entry: " + path) }
                    try check(archive_write_finish_entry(writer))
                }
            }
            entry = try reader.next(control: control)
        }
        guard seen == Set(catalog.members.map(\.path)) else { throw ExplorerError.message("The archive member list changed while rewriting.") }
        for item in plan.imports.sorted(by: { $0.path < $1.path }) {
            try control.checkpoint()
            guard let value = archive_entry_new() else { throw ExplorerError.message("Cannot allocate archive entry.") }
            defer { archive_entry_free(value) }
            item.path.withCString { archive_entry_set_pathname(value, $0) }
            archive_entry_set_filetype(value, item.directory ? 0o040000 : 0o100000)
            archive_entry_set_perm(value, item.directory ? 0o755 : 0o644)
            archive_entry_set_size(value, item.size)
            let date = item.fingerprint?.modified ?? Date()
            archive_entry_set_mtime(value, time_t(date.timeIntervalSince1970), 0)
            if let url = item.source, let expected = item.fingerprint {
                guard expected.matches(url) else { throw ExplorerError.message("An imported item changed: " + url.lastPathComponent) }
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let mode = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0o644
                archive_entry_set_perm(value, mode_t(mode & 0o777))
            }
            try check(archive_write_header(writer, value))
            if !item.directory, let url = item.source, let expected = item.fingerprint {
                let input = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                guard input >= 0 else { throw ExplorerError.message("Cannot open imported file without following links.") }
                let file = FileHandle(fileDescriptor: input, closeOnDealloc: true)
                defer { try? file.close() }
                var stat = stat()
                guard fstat(input, &stat) == 0, UInt64(stat.st_ino) == expected.inode,
                      UInt64(stat.st_dev) == expected.device, stat.st_size == item.size else { throw ExplorerError.message("Imported file identity changed.") }
                var bytes: Int64 = 0
                while let data = try file.read(upToCount: 65_536), !data.isEmpty {
                    try control.checkpoint(); try account(data.count); bytes += Int64(data.count)
                    guard bytes <= item.size else { throw ExplorerError.message("An imported file grew during archiving.") }; try data.withUnsafeBytes(write)
                }
                guard bytes == item.size, expected.matches(url) else { throw ExplorerError.message("An imported file changed during archiving.") }
            }
            try check(archive_write_finish_entry(writer))
        }
        try check(archive_write_close(writer)); try control.checkpoint()
        guard original.matches(source), plan.imports.allSatisfy({ item in item.source.map { item.fingerprint?.matches($0) == true } ?? true }) else { throw ExplorerError.message("An archive source changed; the original archive was retained.") }
        let validated = try ArchiveCatalog.read(target, options: options, control: control)
        guard Set(validated.members.map(\.path)) == plan.expectedPaths else { throw ExplorerError.message("Rewritten archive validation failed.") }
    }
}
