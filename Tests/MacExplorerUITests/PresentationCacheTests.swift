import XCTest
import ExplorerCore
@testable import MacExplorer

final class PresentationCacheTests: XCTestCase {
    @MainActor func testSelectionAndViewChangesDoNotRebuildTheListing() async {
        let store = PreferenceStore.shared, original = PreferenceStore.shared.value
        defer { store.value = original }
        let tab = BrowserTab(.home)
        _ = tab.visibleEntries; _ = tab.groups; _ = tab.displayEntries; _ = tab.selectedEntries
        XCTAssertEqual(tab.presentationBuilds, 1)
        tab.selection = []; tab.focusedURL = nil; tab.options.view = .gallery
        _ = tab.displayEntries; _ = tab.selectedEntries
        XCTAssertEqual(tab.presentationBuilds, 1)
        tab.options.descending.toggle(); _ = tab.visibleEntries
        XCTAssertEqual(tab.presentationBuilds, 2)
        tab.entries = []; _ = tab.groups
        XCTAssertEqual(tab.presentationBuilds, 3)
        tab.stop()
    }
}
