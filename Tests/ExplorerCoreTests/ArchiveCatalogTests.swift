import XCTest
@testable import ExplorerCore

final class ArchiveCatalogTests: XCTestCase {
    private func fixture(_ data: String) throws -> (root: URL, archive: URL, output: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ArchiveTests-" + UUID().uuidString)
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("example.zip")
        try XCTUnwrap(Data(base64Encoded: data)).write(to: archive)
        return (root, archive, output)
    }
    func testCatalogIncludesImplicitDirectoriesAndDates() throws {
        let f = try fixture(Self.plain)
        let catalog = try ArchiveCatalog.read(f.archive)
        XCTAssertEqual(catalog.logicalBytes, 26)
        XCTAssertEqual(catalog.members.count, 2)
        XCTAssertEqual(catalog.children().map(\.name), ["nested", "other.txt"])
        XCTAssertEqual(catalog.children(of: "nested").map(\.name), ["hello.txt"])
        XCTAssertNotNil(catalog.members.first?.modified)
    }
    func testSelectedDirectoryExtractionKeepsUnselectedMembersOut() throws {
        let f = try fixture(Self.plain)
        let output = try ArchiveService.extract(f.archive, to: f.output, control: OperationControl(), options: ArchiveReadOptions(selectedPaths: ["nested"]))
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("nested/hello.txt")), "Hello archive")
        XCTAssertFalse(FileNames.exists(output.appendingPathComponent("other.txt")))
    }
    func testEncryptedZipAcceptsPasswordWithoutPersistingIt() throws {
        let f = try fixture(Self.encrypted)
        let catalog = try ArchiveCatalog.read(f.archive)
        XCTAssertTrue(catalog.containsEncryption)
        let output = try ArchiveService.extract(f.archive, to: f.output, control: OperationControl(), options: ArchiveReadOptions(passphrase: "fixture-password"))
        XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("secret.txt")), "Encrypted fixture content\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.output.path).count, 1)
    }
    func testWrongOrMissingPasswordLeavesNoInstalledOrStagedFiles() throws {
        let f = try fixture(Self.encrypted)
        for password in [nil, "wrong-password"] as [String?] {
            XCTAssertThrowsError(try ArchiveService.extract(f.archive, to: f.output, control: OperationControl(), options: ArchiveReadOptions(passphrase: password)))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
        }
        XCTAssertTrue(FileNames.exists(f.archive))
    }
    func testTraversalAndExpansionLimitsRetainOriginalArchive() throws {
        let malicious = try fixture(Self.traversal)
        XCTAssertThrowsError(try ArchiveCatalog.read(malicious.archive))
        XCTAssertThrowsError(try ArchiveService.extract(malicious.archive, to: malicious.output, control: OperationControl()))
        XCTAssertFalse(FileNames.exists(malicious.root.appendingPathComponent("outside.txt")))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: malicious.output.path).isEmpty)
        let ordinary = try fixture(Self.plain)
        XCTAssertThrowsError(try ArchiveCatalog.read(ordinary.archive, options: ArchiveReadOptions(maximumBytes: 5)))
        XCTAssertThrowsError(try ArchiveService.extract(ordinary.archive, to: ordinary.output, control: OperationControl(), maximumEntries: 1))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: ordinary.output.path).isEmpty)
    }
    func testConventionalTarRootAndInvalidPaths() throws {
        XCTAssertNil(try ArchivePath.parse("./", directory: true))
        XCTAssertEqual(try ArchivePath.parse("./folder/file", directory: false), "folder/file")
        for path in ["/absolute", "../up", "a/../b", "a/./b", "C:/drive", "a\\b", "", "a\0b"] {
            XCTAssertThrowsError(try ArchivePath.parse(path, directory: false), path)
        }
        XCTAssertThrowsError(try ArchivePath.parse(Array(repeating: "a", count: 129).joined(separator: "/"), directory: false))
    }
    func testCancelledAndInvalidPasswordReadersCleanUpExactlyOnce() throws {
        let f = try fixture(Self.plain), control = OperationControl()
        control.cancel()
        XCTAssertThrowsError(try ArchiveCatalog.read(f.archive, control: control))
        XCTAssertThrowsError(try ArchiveService.extract(f.archive, to: f.output, control: control))
        for _ in 0..<10 {
            XCTAssertThrowsError(try ArchiveCatalog.read(f.archive, options: ArchiveReadOptions(passphrase: "bad\0password")))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
    }
    // Synthetic fixtures contain only the strings asserted above. The password
    // is fixture data, not a credential; no user password enters command arguments.
    static let plain = "UEsDBBQAAAAIAKqxblecUSL7DwAAAA0AAAAQAAAAbmVzdGVkL2hlbGxvLnR4dPNIzcnJV0gsSs7ILEsFAFBLAwQUAAAACACqsW5XDGaWKw8AAAANAAAACQAAAG90aGVyLnR4dPMvyUgtUkjOzytJzSsBAFBLAQIUAxQAAAAIAKqxblecUSL7DwAAAA0AAAAQAAAAAAAAAAAAAACggQAAAABuZXN0ZWQvaGVsbG8udHh0UEsBAhQDFAAAAAgAqrFuVwxmlisPAAAADQAAAAkAAAAAAAAAAAAAAKCBPQAAAG90aGVyLnR4dFBLBQYAAAAAAgACAHUAAABzAAAAAAA="
    static let encrypted = "UEsDBAoACQAAAGZrLl3EPaRQJgAAABoAAAAKABwAc2VjcmV0LnR4dFVUCQADMPanajD2p2p1eAsAAQQAAAAABAAAAAAtfrRF9uBluagTypjMtnrYEoFu1mHC7tnb3RdLV20cAune8UjtVlBLBwjEPaRQJgAAABoAAABQSwECHgMKAAkAAABmay5dxD2kUCYAAAAaAAAACgAYAAAAAAABAAAApIEAAAAAc2VjcmV0LnR4dFVUBQADMPananV4CwABBAAAAAAEAAAAAFBLBQYAAAAAAQABAFAAAAB6AAAAAAA="
    static let traversal = "UEsDBBQAAAAIAKqxbldbZFjlDgAAAAwAAAAOAAAALi4vb3V0c2lkZS50eHRLyVfIyy9RKC/KLEkFAFBLAQIUAxQAAAAIAKqxbldbZFjlDgAAAAwAAAAOAAAAAAAAAAAAAACggQAAAAAuLi9vdXRzaWRlLnR4dFBLBQYAAAAAAQABADwAAAA6AAAAAAA="
}
