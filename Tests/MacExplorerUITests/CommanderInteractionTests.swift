import XCTest
import AppKit
import ExplorerCore
@testable import MacExplorer

final class CommanderInteractionTests: XCTestCase {
    @MainActor func testPreferencesPersistIndependentlyAndDefaultsKeepNativeKeys() throws {
        let name = "CommanderTests." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = CommanderPreferences(defaults: defaults)
        XCTAssertFalse(settings.showCommandBar); XCTAssertFalse(settings.classicFunctionKeys)
        XCTAssertFalse(settings.compactTitlebar); XCTAssertTrue(settings.paneStorage)
        settings.showCommandBar = true; settings.paneTerminalButtons = true; settings.compactTitlebar = true
        let restored = CommanderPreferences(defaults: defaults)
        XCTAssertTrue(restored.showCommandBar); XCTAssertTrue(restored.paneTerminalButtons); XCTAssertTrue(restored.compactTitlebar)
        XCTAssertFalse(restored.classicFunctionKeys, "Showing buttons must not silently remap function keys")
    }
    @MainActor func testSelectionStatisticsAreCachedButInvalidateForEqualSizedSelectionsAndRefreshes() throws {
        let fixture = try CommanderFixture()
        defer { fixture.close() }
        let tab = fixture.owner.current, first = fixture.files[0], second = fixture.files[1]
        tab.selection = [first.url]
        XCTAssertEqual(tab.selectionStatistics.bytes, first.size)
        let builds = tab.selectionStatisticsBuilds, projections = tab.selectedProjectionBuilds
        for _ in 0..<1000 { XCTAssertEqual(tab.selectionStatistics.files, 1) }
        XCTAssertEqual(tab.selectionStatisticsBuilds, builds); XCTAssertEqual(tab.selectedProjectionBuilds, projections)
        tab.selection = [second.url]
        XCTAssertEqual(tab.selectionStatistics.bytes, second.size); XCTAssertEqual(tab.selectionStatisticsBuilds, builds + 1)
        try Data(repeating: 65, count: 101).write(to: second.url)
        tab.entries = try fixture.files.map { try FileEntry(url: $0.url) }
        XCTAssertEqual(tab.selectionStatistics.bytes, 101)
        tab.selection = []; XCTAssertEqual(tab.selectionStatistics.count, 0)
    }
    @MainActor func testMaskPreviewReplaceAddRemoveAndStaleListingGuard() async throws {
        let fixture = try CommanderFixture(); defer { fixture.close() }
        let tab = fixture.owner.current, model = SelectionMaskModel()
        model.pattern = "*.swift|*.g.swift"; model.update(tab: tab)
        try await until { !model.working }
        XCTAssertNil(model.error); XCTAssertEqual(model.names, ["App.swift"])
        XCTAssertTrue(model.apply(to: tab)); XCTAssertEqual(tab.selection, [fixture.root.appendingPathComponent("App.swift")])
        model.pattern = "*.txt"; model.mode = .add; model.update(tab: tab); try await until { !model.working }
        XCTAssertTrue(model.apply(to: tab)); XCTAssertEqual(tab.selection.count, 2)
        model.mode = .remove; XCTAssertTrue(model.apply(to: tab)); XCTAssertEqual(tab.selection.count, 1)
        let current = tab.entries; tab.entries = current
        XCTAssertFalse(model.apply(to: tab), "A preview must not apply to a refreshed listing")
        model.pattern = "old|invalid|mask"; model.update(tab: tab)
        model.pattern = "*.g.swift"; model.update(tab: tab); try await until { !model.working }
        XCTAssertNil(model.error); XCTAssertEqual(model.names, ["Bindings.g.swift"])
        XCTAssertTrue(model.apply(to: tab)); model.cancel()
    }
    @MainActor func testSameExtensionUsesExactSuffixAndRejectsLateSelectionChanges() async throws {
        let fixture = try CommanderFixture(); defer { fixture.close() }
        let tab = fixture.owner.current
        tab.selection = [fixture.files[0].url]; tab.selectSameExtension("SWIFT")
        try await until { !tab.selectionMatching }
        XCTAssertEqual(tab.selection, Set(fixture.files.prefix(2).map(\.url)))
        tab.selectSameExtension("txt"); tab.selection = []
        try await until { !tab.selectionMatching }
        XCTAssertTrue(tab.selection.isEmpty, "Background matching must not overwrite newer input")
    }
    @MainActor func testClassicKeysAreOptInScopedAndLeaveEditorsAndVoiceOverAlone() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture(), owner = fixture.owner
        let settings = CommanderPreferences.shared, saved = settings.classicFunctionKeys
        let window = CommanderTestWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; owner.window = window; window.makeKeyAndOrderFront(nil); AppRouter.shared.active = owner
        defer { settings.classicFunctionKeys = saved; fixture.close(); window.orderOut(nil); window.close(); AppRouter.shared.active = nil }
        func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], repeated: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 1,
                windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: repeated, keyCode: code))
        }
        settings.classicFunctionKeys = false; owner.fileSurfaceFocused = true
        XCTAssertNotNil(KeyboardRouter.handle(try key(98)), "F7 has no native profile binding")
        settings.classicFunctionKeys = true; owner.fileSurfaceFocused = true
        XCTAssertNil(KeyboardRouter.handle(try key(98))); XCTAssertEqual(owner.sheet, .newFolder)
        owner.sheet = nil
        XCTAssertNil(KeyboardRouter.handle(try key(98, repeated: true))); XCTAssertNil(owner.sheet)
        XCTAssertNotNil(KeyboardRouter.handle(try key(98, flags: [.control, .option]))); XCTAssertNil(owner.sheet)
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        window.contentView?.addSubview(editor); window.makeFirstResponder(editor)
        XCTAssertNotNil(KeyboardRouter.handle(try key(98))); XCTAssertNil(owner.sheet)
        window.makeFirstResponder(nil); owner.fileSurfaceFocused = true
        owner.dualPane = DualPaneController(primary: owner)
        owner.dualPane?.secondary.sheet = .newFolder
        XCTAssertNotNil(KeyboardRouter.handle(try key(98))); XCTAssertNil(owner.sheet)
        owner.dualPane?.secondary.sheet = nil
        owner.current.history = NavigationHistory(.archive(fixture.root.appendingPathComponent("test.zip"), folder: ""))
        XCTAssertNotNil(KeyboardRouter.handle(try key(98))); XCTAssertNil(owner.sheet)
        XCTAssertEqual([99, 118, 96, 97, 98, 100].compactMap { CommanderAction.functionKey(UInt16($0)) }, CommanderAction.functionActions)
    }
    @MainActor func testCompactTitlebarTogglesWithoutReplacingCustomizedToolbar() throws {
        _ = NSApplication.shared
        let fixture = try CommanderFixture(), settings = CommanderPreferences.shared, saved = settings.compactTitlebar
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; fixture.owner.window = window
        let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false
        defer { settings.compactTitlebar = saved; fixture.close(); window.close() }
        settings.compactTitlebar = false; chrome.attach(to: window, owner: fixture.owner)
        let toolbar = try XCTUnwrap(window.toolbar)
        toolbar.insertItem(withItemIdentifier: .init("operations"), at: 0)
        XCTAssertEqual(window.toolbarStyle, .unified)
        settings.compactTitlebar = true; chrome.refresh()
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact); XCTAssertTrue(window.toolbar === toolbar)
        XCTAssertEqual(toolbar.items.first?.itemIdentifier.rawValue, "operations")
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier.rawValue == "power" })
        XCTAssertTrue(toolbar.items.contains { $0.itemIdentifier.rawValue == "terminal" })
    }
    @MainActor private func until(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(4)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition(), "UI state did not settle")
    }
}
@MainActor final class CommanderFixture {
    private let container: URL
    let root: URL
    let files: [FileEntry]
    let owner: ExplorerWorkspace
    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("Commander-" + UUID().uuidString)
        root = container.appendingPathComponent("Workspace Source")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var entries: [FileEntry] = []
        for (index, name) in ["App.swift", "Bindings.g.swift", "Notes.txt"].enumerated() {
            let url = root.appendingPathComponent(name); try Data(repeating: 65, count: 7 + index * 9).write(to: url)
            entries.append(try FileEntry(url: url))
        }
        files = entries
        owner = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(root)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        owner.current.stop(); owner.current.entries = files; owner.current.loading = false
    }
    func close() {
        owner.dualPane?.cancelTransferPreparation(); owner.tabs.forEach { $0.stop() }; owner.dualPane?.secondary.tabs.forEach { $0.stop() }
        try? FileManager.default.removeItem(at: container)
    }
}
@MainActor private final class CommanderTestWindow: NSWindow { override var canBecomeKey: Bool { true } }
