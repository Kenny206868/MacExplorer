import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class CommanderSafetyTests: XCTestCase {
    @MainActor func testCommanderTrashAlwaysRequiresConfirmationWithoutChangingGlobalPreferences() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture(), owner = fixture.owner
        let preferences = owner.preferences, saved = preferences.value.confirmTrash
        defer { preferences.value.confirmTrash = saved; owner.pendingDeletion = []; fixture.close() }
        preferences.value.confirmTrash = false; owner.current.selection = [fixture.files[0].url]
        let jobs = owner.operations.jobs.count
        CommanderAction.trash.perform(in: owner)
        XCTAssertEqual(owner.pendingDeletion, [fixture.files[0].url])
        XCTAssertFalse(owner.permanentDeletion); XCTAssertFalse(preferences.value.confirmTrash)
        XCTAssertEqual(owner.operations.jobs.count, jobs, "An unconfirmed F8 must not enqueue a mutation")
        XCTAssertTrue(FileNames.exists(fixture.files[0].url))
    }
    @MainActor func testConfirmedMoveWaitsForNativeDialogDismissalBeforeRevalidation() async throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture(), owner = fixture.owner
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let dialog = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; dialog.isReleasedWhenClosed = false
        owner.window = window; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); AppRouter.shared.active = owner
        owner.dualPane = DualPaneController(primary: owner)
        let dual = try XCTUnwrap(owner.dualPane)
        dual.secondary.current.stop(); owner.current.selection = [fixture.files[0].url]
        defer {
            DeferredSheetAction.shared.cancel(for: owner)
            if window.attachedSheet != nil { window.endSheet(dialog) }
            owner.message = nil; fixture.close(); dialog.orderOut(nil); dialog.close(); window.orderOut(nil); window.close(); AppRouter.shared.active = nil
        }
        owner.pendingPaneTransfer = try await PaneTransferRequest.prepare(source: owner, destination: fixture.root, move: true)
        // A changed fingerprint will stop the move after dismissal, without
        // enqueueing any write in this lifecycle test.
        try Data("changed while confirmation was visible".utf8).write(to: fixture.files[0].url)
        // Match a real user confirmation: do not invoke it until AppKit has
        // actually attached the originating sheet and transferred its focus.
        window.beginSheet(dialog, completionHandler: nil)
        try await until { window.attachedSheet === dialog && dialog.isVisible }
        owner.confirmPaneTransfer()
        XCTAssertNil(owner.pendingPaneTransfer)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(dual.preparingTransfer, "Do not start validation under the original modal boundary")
        XCTAssertNil(owner.message)
        window.endSheet(dialog); dialog.orderOut(nil); window.makeKeyAndOrderFront(nil)
        try await until { window.attachedSheet == nil }
        try await until { owner.message != nil }
        XCTAssertEqual(owner.message?.title, "Transfer stopped")
        XCTAssertTrue(FileNames.exists(fixture.files[0].url))
    }
    @MainActor private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Transfer preparation did not settle")
    }
}
