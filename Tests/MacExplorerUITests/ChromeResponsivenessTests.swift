import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class ChromeResponsivenessTests: XCTestCase {
    @MainActor func testRepeatedSelectionDoesNotReapplyWindowAppearanceAndLayout() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Chrome-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try ["a.txt", "b.txt"].map { name -> FileEntry in
            let url = root.appendingPathComponent(name); try Data().write(to: url); return try FileEntry(url: url)
        }
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.current.entries = files
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window; window.makeKeyAndOrderFront(nil)
        defer { owner.current.stop(); window.orderOut(nil); window.close() }
        let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false; chrome.attach(to: window, owner: owner)
        owner.current.selection = [files[0].url]; chrome.refresh()
        let changes = chrome.chromeMutationCount, passes = chrome.validationPasses, publications = chrome.workspaceModel.publications
        for index in 0..<1000 {
            owner.current.selection = [files[index % 2].url]; owner.current.focusedURL = files[index % 2].url; chrome.refresh()
        }
        XCTAssertEqual(chrome.workspaceModel.publications, publications, "File selection must not republish the titlebar workspace")
        XCTAssertEqual(chrome.chromeMutationCount, changes, "Selection must not reapply the whole window's appearance/titlebar")
        XCTAssertEqual(chrome.validationPasses, passes, "Unchanged availability must not revalidate every native item")
        owner.current.selection = []; chrome.refresh(); XCTAssertEqual(chrome.validationPasses, passes + 1)
    }
}
