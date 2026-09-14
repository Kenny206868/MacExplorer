import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

/// Uses NSWindow event delivery and real SwiftUI sheet presentation. No global
/// input synthesis, screen recording permission, or application mouse control.
final class CommandPaletteLifecycleTests: XCTestCase {
    @MainActor private func makeOwner() -> ExplorerWorkspace {
        _ = NSApplication.shared
        let owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(FileManager.default.temporaryDirectory)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); return owner
    }
    @MainActor private func eventually(_ description: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail(description)
        throw ExplorerError.message(description)
    }
    @MainActor private func event(_ window: NSWindow, code: UInt16, text: String,
                                 flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: repeatKey, keyCode: code))
    }
    @MainActor func testNativeSearchFieldRoutesArrowsAndRepeatedKeys() async throws {
        let owner = makeOwner(), model = CommandPaletteModel()
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 680, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: CommandPaletteView(workspace: owner, model: model))
        owner.window = window; window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { DeferredSheetAction.shared.cancel(for: owner); owner.current.stop(); window.orderOut(nil); window.contentView = nil; window.close() }
        try await eventually("The command search field never acquired native focus") { window.firstResponder is NSTextView }
        XCTAssertEqual(model.selection, .goToFolder)
        window.sendEvent(try event(window, code: 125, text: "\u{F701}"))
        try await eventually("Down Arrow did not move command selection") { model.selection == .newTab }
        window.sendEvent(try event(window, code: 125, text: "\u{F701}", repeatKey: true))
        try await eventually("Repeated Down Arrow did not move command selection") { model.selection == .dualPanes }
        window.sendEvent(try event(window, code: 126, text: "\u{F700}"))
        try await eventually("Up Arrow did not move command selection") { model.selection == .newTab }
        XCTAssertEqual((window.firstResponder as? NSTextView)?.string, "")
        XCTAssertEqual(model.query, "")
    }
    @MainActor func testRealDismissalPresentsRequestedSheetWithoutDelayGuessing() async throws {
        let owner = makeOwner()
        let window = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 1000, height: 760), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window
        let host = NSHostingView(rootView: Color.clear.frame(width: 1000, height: 760)
            .modifier(WorkspaceDialogs(workspace: owner)))
        window.contentView = host; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer {
            DeferredSheetAction.shared.cancel(for: owner); owner.sheet = nil; owner.current.stop()
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
            window.orderOut(nil); window.contentView = nil; window.close()
        }
        try await Task.sleep(for: .milliseconds(60))
        owner.sheet = .commandPalette
        try await eventually("The production sheet host did not present the palette") {
            window.attachedSheet?.firstResponder is NSTextView
        }
        let invocation = try CommandInvocation(.newFolder, workspace: owner)
        invocation.enqueue()
        try await eventually("The dismissal callback did not route the requested New Folder sheet") {
            owner.sheet == .newFolder && window.attachedSheet != nil
        }
        try await eventually("The new sheet did not acquire its native filename editor") {
            (window.attachedSheet?.firstResponder as? NSTextView)?.string == "New folder"
        }
        XCTAssertNil(owner.message)
        owner.sheet = nil
        try await eventually("The New Folder sheet did not dismiss") { window.attachedSheet == nil }
        XCTAssertFalse(DeferredSheetAction.shared.didDismiss(owner), "The action must have been consumed once")
    }
}
