import XCTest
@testable import ExplorerCore

final class ArchiveDirectoryIndexTests: XCTestCase {
    private func member(_ path: String, folder: Bool = false, encrypted: Bool = false) -> ArchiveMember {
        ArchiveMember(path: path, isDirectory: folder, size: folder ? 0 : 8,
            encrypted: encrypted, modified: nil, unsupportedReason: nil)
    }
    func testImplicitAncestorsEmptyFoldersAndExplicitMetadata() throws {
        let explicit = ArchiveMember(path: "docs", isDirectory: true, size: 0, encrypted: false,
            modified: Date(timeIntervalSince1970: 123), unsupportedReason: nil)
        let index = try ArchiveDirectoryIndex(members: [member("docs/nested/file10.txt"), explicit,
            member("docs/nested/file2.txt"), member("Empty", folder: true), member("root.txt", encrypted: true)])
        XCTAssertEqual(index.listing(in: "").entries.map(\.path), ["docs", "Empty", "root.txt"])
        XCTAssertEqual(index.listing(in: "docs/nested").entries.map(\.name), ["file2.txt", "file10.txt"])
        XCTAssertEqual(index.listing(in: "").entries.first?.modified, explicit.modified)
        XCTAssertTrue(index.containsFolder("Empty")); XCTAssertFalse(index.containsFolder("missing"))
        XCTAssertTrue(index.hasEncryption); XCTAssertFalse(index.hasUnsupportedMembers)
    }
    func testSparseSelectionAndFilteringOnlyAddressImmediateChildren() throws {
        let index = try ArchiveDirectoryIndex(members: (0..<1024).map { member("Files/file\($0).txt") } + [member("Other/file2.txt")])
        let listing = index.listing(in: "Files")
        for count in [0, 1, 2, 512, 1024] {
            let paths = Set(listing.entries.suffix(count).map(\.path)).union(["Other/file2.txt", "gone"])
            XCTAssertEqual(listing.selected(paths), listing.entries.filter { paths.contains($0.path) })
        }
        let filtered = try listing.filtered(by: "file2.")
        XCTAssertEqual(filtered.entries.map(\.path), ["Files/file2.txt"])
        XCTAssertFalse(filtered.contains("Files/file3.txt"))
        XCTAssertEqual(try listing.filtered(by: "").entries.count, 1024)
    }
    func testCancellationAndAmbiguousParentsAreRejected() {
        XCTAssertThrowsError(try ArchiveDirectoryIndex(members: [member("a"), member("a/b")]))
        XCTAssertThrowsError(try ArchiveDirectoryIndex(members: [member("a"), member("a")]))
        XCTAssertThrowsError(try ArchiveDirectoryIndex(members: [], checkingCancellation: { throw CancellationError() }))
    }
    func testRepeatedLargeArchiveNavigationDoesNotEnumerateMembersAgain() throws {
        let members = (0..<50_000).map { member("Folder\($0 / 100)/file\($0).txt") }
        var checkpoints = 0
        let index = try ArchiveDirectoryIndex(members: members, checkingCancellation: { checkpoints += 1 })
        let builds = checkpoints
        for repeatIndex in 0..<2000 {
            let folder = repeatIndex % 500
            let listing = index.listing(in: "Folder\(folder)")
            XCTAssertEqual(listing.entries.count, 100)
            XCTAssertEqual(listing.selected(["Folder\(folder)/file\(folder * 100).txt"]).count, 1)
        }
        XCTAssertEqual(checkpoints, builds, "Lookup and sparse selection must not rebuild the namespace")
        XCTAssertEqual(index.entryCount, 50_500)
    }
}
