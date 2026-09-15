import XCTest
import CLibArchive
@testable import ExplorerCore

final class ArchiveEditingTests: XCTestCase {
    func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveEdit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }; return url
    }
    func archive(_ root: URL, tar: Bool = false) throws -> URL {
        let url = root.appendingPathComponent(tar ? "sample.tar.gz" : "sample.zip")
        let writer = try XCTUnwrap(archive_write_new()); defer { archive_write_free(writer) }
        XCTAssertEqual(tar ? archive_write_set_format_pax_restricted(writer) : archive_write_set_format_zip(writer), ARCHIVE_OK)
        if tar { XCTAssertEqual(archive_write_add_filter_gzip(writer), ARCHIVE_OK) }
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o600); XCTAssertGreaterThanOrEqual(fd, 0); defer { close(fd) }
        XCTAssertEqual(archive_write_open_fd(writer, fd), ARCHIVE_OK)
        for (path, content) in [("docs/readme.txt", "original"), ("keep.txt", "untouched")] {
            let entry = try XCTUnwrap(archive_entry_new()); defer { archive_entry_free(entry) }
            path.withCString { archive_entry_set_pathname(entry, $0) }; archive_entry_set_filetype(entry, 0o100000)
            archive_entry_set_perm(entry, 0o640); archive_entry_set_size(entry, Int64(content.utf8.count)); archive_entry_set_mtime(entry, 1_700_000_000, 0)
            XCTAssertEqual(archive_write_header(writer, entry), ARCHIVE_OK)
            let data = Data(content.utf8); XCTAssertEqual(data.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, $0.count) }, data.count)
            XCTAssertEqual(archive_write_finish_entry(writer), ARCHIVE_OK)
        }
        XCTAssertEqual(archive_write_close(writer), ARCHIVE_OK); return url
    }
    func contents(_ url: URL) throws -> [String: Data] {
        let reader = try ArchiveReader(source: url, options: ArchiveReadOptions())
        var result: [String: Data] = [:], buffer = [UInt8](repeating: 0, count: 4096)
        while let entry = try reader.next(control: OperationControl()) {
            let path = try reader.name(entry); var data = Data()
            while true {
                let count = buffer.withUnsafeMutableBytes { archive_read_data(reader.handle, $0.baseAddress, $0.count) }
                if count == 0 { break }; guard count > 0 else { throw ArchiveReader.error(reader.handle) }; data.append(contentsOf: buffer.prefix(count))
            }
            result[path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))] = data
        }
        return result
    }
    func testStreamingRenameDeleteImportAndReplacePreserveUntouchedData() throws {
        for tar in [false, true] {
            let root = try root(), original = try archive(root, tar: tar), initial = try Data(contentsOf: original)
            let renamed = root.appendingPathComponent("renamed")
            try ArchiveRewriter.rewrite(original, to: renamed, mutation: .rename(path: "docs", to: "manual"), control: OperationControl())
            XCTAssertEqual(try contents(renamed), ["manual/readme.txt": Data("original".utf8), "keep.txt": Data("untouched".utf8)])
            let deleted = root.appendingPathComponent("deleted")
            try ArchiveRewriter.rewrite(renamed, to: deleted, mutation: .remove(paths: ["manual"]), control: OperationControl())
            XCTAssertEqual(try contents(deleted), ["keep.txt": Data("untouched".utf8)])
            let folder = root.appendingPathComponent("folder")
            try ArchiveRewriter.rewrite(deleted, to: folder, mutation: .createDirectory(path: "added"), control: OperationControl())
            let input = root.appendingPathComponent("new.txt"); try Data("new contents".utf8).write(to: input)
            let imported = root.appendingPathComponent("imported")
            try ArchiveRewriter.rewrite(folder, to: imported, mutation: .importItems(sources: [input], into: "added"), control: OperationControl())
            XCTAssertEqual(try contents(imported)["added/new.txt"], Data("new contents".utf8))
            let replaced = root.appendingPathComponent("replaced")
            try ArchiveRewriter.rewrite(imported, to: replaced, mutation: .replace(path: "keep.txt", source: input), control: OperationControl())
            XCTAssertEqual(try contents(replaced)["keep.txt"], Data("new contents".utf8)); XCTAssertEqual(try Data(contentsOf: original), initial)
        }
    }
    func testCollisionTraversalLinksAndLimitsNeverOverwriteOriginal() throws {
        let root = try root(), original = try archive(root), before = try Data(contentsOf: original)
        for mutation in [ArchiveMutation.rename(path: "docs", to: "keep.txt"), .rename(path: "docs", to: "../outside"), .createDirectory(path: "keep.txt/child"), .createDirectory(path: "DOCS"), .remove(paths: ["missing"])] {
            XCTAssertThrowsError(try ArchiveRewriter.rewrite(original, to: root.appendingPathComponent(UUID().uuidString), mutation: mutation, control: OperationControl()))
        }
        let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try ArchiveRewriter.rewrite(original, to: root.appendingPathComponent("link-import"), mutation: .importItems(sources: [link], into: ""), control: OperationControl()))
        XCTAssertThrowsError(try ArchiveCatalog.read(link))
        XCTAssertThrowsError(try ArchiveRewriter.rewrite(original, to: root.appendingPathComponent("limited"), mutation: .createDirectory(path: "new"), control: OperationControl(), options: ArchiveReadOptions(maximumBytes: 1)))
        XCTAssertEqual(try Data(contentsOf: original), before)
    }
    func testCancellationAndOccupiedCandidateAreSafe() throws {
        let root = try root(), original = try archive(root), control = OperationControl(); control.cancel()
        let candidate = root.appendingPathComponent("candidate")
        XCTAssertThrowsError(try ArchiveRewriter.rewrite(original, to: candidate, mutation: .remove(paths: ["docs"]), control: control)); XCTAssertFalse(FileNames.exists(candidate))
        try Data("external".utf8).write(to: candidate)
        XCTAssertThrowsError(try ArchiveRewriter.rewrite(original, to: candidate, mutation: .remove(paths: ["docs"]), control: OperationControl())); XCTAssertEqual(try String(contentsOf: candidate), "external")
    }
    func testJournaledArchiveEditUndoRedoAndStaleFingerprint() async throws {
        let root = try root(), source = try archive(root), before = try Data(contentsOf: source)
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts")), original = try FileFingerprint(source)
        let changed = await engine.editArchive(source, expected: original, mutation: .rename(path: "docs", to: "manual"), control: OperationControl())
        XCTAssertTrue(changed.errors.isEmpty, changed.errors.description); XCTAssertEqual(changed.receipt.steps.count, 2); XCTAssertNotNil(try contents(source)["manual/readme.txt"])
        let stale = await engine.editArchive(source, expected: original, mutation: .remove(paths: ["keep.txt"]), control: OperationControl())
        XCTAssertFalse(stale.errors.isEmpty); XCTAssertNotNil(try contents(source)["keep.txt"])
        let undone = await engine.undo(changed.receipt, control: OperationControl())
        XCTAssertTrue(undone.errors.isEmpty, undone.errors.description); XCTAssertEqual(try Data(contentsOf: source), before)
        let redone = await engine.undo(undone.receipt, control: OperationControl())
        XCTAssertTrue(redone.errors.isEmpty, redone.errors.description); XCTAssertNotNil(try contents(source)["manual/readme.txt"])
        let pending = try await engine.interruptedOperations(); XCTAssertTrue(pending.isEmpty)
    }
    func testEncryptedEditsCannotDowngradeProtection() async throws {
        let root = try root(), source = root.appendingPathComponent("encrypted.zip")
        let data = try XCTUnwrap(Data(base64Encoded: ArchiveCatalogTests.encrypted)); try data.write(to: source)
        let engine = FileOperationEngine(recoveryDirectory: root.appendingPathComponent("receipts"))
        let result = await engine.editArchive(source, expected: try FileFingerprint(source), mutation: .createDirectory(path: "new"), control: OperationControl())
        XCTAssertFalse(result.errors.isEmpty); XCTAssertEqual(try Data(contentsOf: source), data)
    }
}
