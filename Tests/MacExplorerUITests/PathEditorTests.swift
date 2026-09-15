import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class PathEditorTests: XCTestCase {
    @MainActor func testLateCompletionsAndNavigationCannotEscapeCancelledSession() async throws {
        let base = URL(fileURLWithPath: "/tmp"), finished = expectation(description: "late resolver returned")
        let model = PathEditorModel(resolve: { _, _, _ in
            try? await Task.sleep(for: .milliseconds(120)); finished.fulfill(); return .folder(base)
        }, complete: { value, _, _, _ in
            try? await Task.sleep(for: .milliseconds(value == "old" ? 200 : 10))
            return PathSuggestions(items: [PathSuggestion(url: base.appendingPathComponent(value))])
        })
        model.begin(text: base.path, base: base, showHidden: false)
        model.change("old"); try await Task.sleep(for: .milliseconds(130))
        model.change("new"); try await waitUntil { !model.completing }
        XCTAssertEqual(model.suggestions.map(\.title), ["new"])
        var navigations = 0; model.committed = { _, _ in navigations += 1 }
        model.submit(); model.cancel(); await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(navigations, 0); XCTAssertFalse(model.editing); XCTAssertTrue(model.suggestions.isEmpty)
    }
    @MainActor func testInvalidPathKeepsDraftAndEmptyCompletionDoesNotLoop() async throws {
        actor Counter { var value = 0; func hit() { value += 1 } }
        let calls = Counter(), base = URL(fileURLWithPath: "/tmp")
        let model = PathEditorModel(resolve: { _, _, _ in throw LocationAddressError.invalid("Folder unavailable") }, complete: { _, _, _, _ in await calls.hit(); return PathSuggestions() })
        model.begin(text: "missing", base: base, showHidden: false)
        model.acceptCompletion(); try await waitUntil { !model.completing }
        let count = await calls.value; XCTAssertEqual(count, 1)
        model.submit(); try await waitUntil { !model.resolving }
        XCTAssertTrue(model.editing); XCTAssertEqual(model.text, "missing"); XCTAssertEqual(model.error, "Folder unavailable"); model.cancel()
    }
    @MainActor func testNativeFieldSelectsFullUnicodePathAndCompletesWithoutChangingTabFocus() async throws {
        _ = NSApplication.shared
        let base = URL(fileURLWithPath: "/tmp"), name = "Zażółć gęślą 日本語"
        let model = PathEditorModel(complete: { _, _, _, _ in PathSuggestions(items: [PathSuggestion(url: base.appendingPathComponent(name))]) })
        model.begin(text: base.appendingPathComponent(name).path, base: base, showHidden: false)
        let host = NSHostingView(rootView: NativePathField(model: model, label: "Path test").frame(width: 600, height: 32))
        let window = PathTestWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { model.cancel(); window.orderOut(nil); window.contentView = nil; window.close() }
        try await waitUntil { self.findField(host)?.currentEditor() is NSTextView }; host.layoutSubtreeIfNeeded()
        let field = try XCTUnwrap(findField(host)), editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        try await waitUntil { editor.selectedRange() == NSRange(location: 0, length: (model.text as NSString).length) }
        model.change("Z"); try await waitUntil { !model.completing }; XCTAssertTrue(model.acceptCompletion())
        try await waitUntil { field.stringValue == base.appendingPathComponent(name).path + "/" && editor.selectedRange() == NSRange(location: (model.text as NSString).length, length: 0) }
        XCTAssertTrue(window.firstResponder === editor)
        model.requestFocus(selectAll: true)
        try await waitUntil { editor.selectedRange().length == (model.text as NSString).length }
    }
    @MainActor private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "Asynchronous UI state did not settle before the deadline")
    }
    @MainActor private func findField(_ root: NSView) -> PathTextField? {
        if let field = root as? PathTextField { return field }; return root.subviews.lazy.compactMap { self.findField($0) }.first
    }
}
@MainActor private final class PathTestWindow: NSWindow { override var canBecomeKey: Bool { true } }
