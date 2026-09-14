import XCTest
@testable import ExplorerCore

final class FilenameEditingTests: XCTestCase {
    func testExtensionSelectionUsesNativeUTF16Coordinates() {
        for (name, base) in [("Report.pdf", "Report"), ("Archive.tar.gz", "Archive.tar"), ("Zażółć 🧪.txt", "Zażółć 🧪"), (".gitignore", ".gitignore"), ("README", "README")] {
            let range = FilenameEditing.initialSelection(name, isDirectory: false)
            XCTAssertEqual((name as NSString).substring(with: range), base)
        }
        let folder = "A folder.with.dots"
        XCTAssertEqual(FilenameEditing.initialSelection(folder, isDirectory: true).length, folder.utf16.count)
    }
}
