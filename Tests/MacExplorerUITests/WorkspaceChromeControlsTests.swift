import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class WorkspaceChromeControlsTests: XCTestCase {
    @MainActor func testLayoutActionsTargetTheOwningWindowAndRespectEitherPaneModal() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture(), owner = fixture.owner
        defer { fixture.close(); AppRouter.shared.active = nil }
        WorkspaceLayoutAction.split.perform(owner)
        let panes = try XCTUnwrap(owner.dualPane); panes.secondary.current.stop()
        XCTAssertEqual(panes.geometry.orientation, .sideBySide)
        WorkspaceLayoutAction.stacked.perform(owner)
        XCTAssertTrue(owner.dualPane === panes); XCTAssertEqual(panes.geometry.orientation, .stacked)
        WorkspaceLayoutAction.secondary.perform(owner)
        XCTAssertTrue(panes.active === panes.secondary)
        WorkspaceLayoutAction.primary.perform(owner)
        XCTAssertTrue(panes.active === owner)
        panes.geometry.ratio = 0.7; WorkspaceLayoutAction.equalize.perform(owner)
        XCTAssertEqual(panes.geometry.ratio, 0.5)
        panes.secondary.sheet = .commanderSettings
        XCTAssertFalse(WorkspaceLayoutAction.single.enabled(owner))
        WorkspaceLayoutAction.single.perform(owner); XCTAssertTrue(owner.dualPane === panes)
        WorkspaceLayoutAction.commands.perform(owner); XCTAssertNil(owner.sheet)
        panes.secondary.sheet = nil
        WorkspaceLayoutAction.commands.perform(owner); XCTAssertEqual(owner.sheet, .commandPalette)
        owner.sheet = nil
        WorkspaceLayoutAction.single.perform(owner); XCTAssertNil(owner.dualPane)
    }
    @MainActor func testTitlebarModelTracksBothIdentitiesButNotSelection() throws {
        let fixture = try CommanderFixture(), owner = fixture.owner
        defer { fixture.close(); AppRouter.shared.active = nil }
        owner.dualPane = DualPaneController(primary: owner)
        let panes = try XCTUnwrap(owner.dualPane); panes.secondary.current.stop()
        let model = WorkspaceChromeModel(); model.update(owner: owner, width: 1440)
        let publications = model.publications
        for index in 0..<1000 {
            owner.current.selection = [fixture.files[index % fixture.files.count].url]
            model.update(owner: owner, width: 1440)
        }
        XCTAssertEqual(model.publications, publications)
        panes.secondary.current.history = NavigationHistory(.folder(fixture.root.appendingPathComponent("Target")))
        panes.focus(.secondary); model.update(owner: owner, width: 1440)
        XCTAssertEqual(model.state.secondaryTitle, "Target"); XCTAssertEqual(model.state.focused, .secondary)
        XCTAssertEqual(model.publications, publications + 1)
    }
    @MainActor func testNativeHostResizesWithoutReplacingToolbarOrCustomItems() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 720), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; fixture.owner.window = window
        let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false
        defer { fixture.close(); window.close() }
        chrome.attach(to: window, owner: fixture.owner)
        let toolbar = try XCTUnwrap(window.toolbar)
        let host = try XCTUnwrap(toolbar.items.first { $0.itemIdentifier.rawValue == "workspace" }?.view)
        XCTAssertEqual(host.accessibilityIdentifier(), "explorer.titlebarWorkspaceHost")
        toolbar.insertItem(withItemIdentifier: .init("operations"), at: 0)
        for width in [800.0, 1260, 1760, 1024] {
            window.setContentSize(NSSize(width: width, height: 720)); chrome.refresh()
            let constraint = try XCTUnwrap(host.constraints.first { $0.firstAttribute == .width && $0.relation == .equal })
            XCTAssertEqual(constraint.constant, WorkspaceChromeLayout(width: window.frame.width).titlebarWidth)
            XCTAssertTrue(window.toolbar === toolbar)
            XCTAssertTrue(toolbar.items.first { $0.itemIdentifier.rawValue == "workspace" }?.view === host)
            XCTAssertEqual(toolbar.items.first?.itemIdentifier.rawValue, "operations")
        }
    }
    @MainActor func testOnlyTheUncustomizedLegacyToolbarMigrates() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false
        defer { fixture.close(); window.close() }
        chrome.attach(to: window, owner: fixture.owner)
        let toolbar = try XCTUnwrap(window.toolbar)
        while !toolbar.items.isEmpty { toolbar.removeItem(at: 0) }
        for identifier in NativeWindowChrome.legacyDefaultItems { toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count) }
        chrome.migrateLegacyDefault(toolbar)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier), chrome.toolbarDefaultItemIdentifiers(toolbar))
        toolbar.removeItem(at: try XCTUnwrap(toolbar.items.firstIndex { $0.itemIdentifier.rawValue == "workspace" }))
        toolbar.insertItem(withItemIdentifier: .init("operations"), at: 0)
        let custom = toolbar.items.map(\.itemIdentifier)
        chrome.migrateLegacyDefault(toolbar)
        XCTAssertEqual(toolbar.items.map(\.itemIdentifier), custom, "Do not overwrite an owner's toolbar arrangement")
    }
}
