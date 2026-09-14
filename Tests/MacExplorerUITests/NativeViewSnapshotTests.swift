import XCTest
import SwiftUI
import AppKit
import QuartzCore
import ExplorerCore
@testable import MacExplorer

/// Renders the production SwiftUI views, not the HTML design, without input
/// automation or screen-recording permission. Run serially on the macOS runner.
final class NativeViewSnapshotTests: XCTestCase {
    struct Capture: Codable {
        let name: String
        let width: Int
        let height: Int
        let pixelsWide: Int
        let pixelsHigh: Int
        let luminanceRange: Double
        let distinctSamples: Int
    }

    @MainActor func testNativeViewMatrix() async throws {
        guard let outputPath = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set MACEXPLORER_SNAPSHOT_DIR to capture native view fixtures.")
        }
        let output = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("MacExplorer-Visual-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        let defaultsKey = "MacExplorer.preferences.v1"
        let previousData = UserDefaults.standard.data(forKey: defaultsKey)
        let preferences = PreferenceStore.shared
        let originalPreferences = preferences.value
        let originalJobs = OperationCenter.shared.jobs
        defer {
            preferences.value = originalPreferences
            if let previousData { UserDefaults.standard.set(previousData, forKey: defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: defaultsKey) }
            OperationCenter.shared.jobs = originalJobs
            try? FileManager.default.removeItem(at: fixture)
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        var urls: [URL] = []
        for name in ["Brand assets", "Design system", "Projects", "Release notes.txt", "Roadmap.md", "Quarterly report.csv", "A very long document name to exercise truncation and selection.txt", "Zażółć gęślą jaźń.txt", "日本語のドキュメント.txt"] {
            let url = fixture.appendingPathComponent(name)
            if url.pathExtension.isEmpty { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) }
            else { try Data("MacExplorer visual fixture\n".utf8).write(to: url) }
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)], ofItemAtPath: url.path)
            urls.append(url)
        }
        var settings = Preferences()
        settings.pins = urls.prefix(3).map(Bookmark.init)
        settings.recent = []
        settings.tabs = [.folder(fixture)]
        settings.restoreTabs = false
        preferences.value = settings
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.folder(fixture)), options: FolderOptions(), query: "", allLocations: false, selection: []))
        let tab = workspace.current
        tab.stop()
        let entries = try urls.map { try FileEntry(url: $0) }
        tab.entries = entries
        tab.loading = false
        let updater = AppUpdater()
        var captures: [Capture] = []
        func shell() -> AnyView {
            AnyView(WorkspaceShell(workspace: workspace, tab: tab)
                .environmentObject(workspace).environmentObject(preferences).environmentObject(updater))
        }
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            preferences.value.theme = theme
            preferences.value.inspector = true
            preferences.value.previewPane = false
            for mode in ViewMode.allCases {
                tab.options.view = mode
                tab.selection = [urls[3]]
                captures.append(try await capture(shell(), named: "\(theme)-\(mode.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))", size: NSSize(width: 1260, height: 800), dark: dark, output: output))
            }
            tab.options.view = .large
            tab.options.group = .kind
            preferences.value.checkboxes = true
            tab.selection = Set(urls.prefix(4))
            captures.append(try await capture(shell(), named: "\(theme)-grouped-selection", size: NSSize(width: 1260, height: 800), dark: dark, output: output))
            tab.options.group = .none
            preferences.value.previewPane = true
            tab.selection = []
            for width in [800, 1024, 1600] {
                captures.append(try await capture(shell(), named: "\(theme)-panes-\(width)", size: NSSize(width: width, height: 700), dark: dark, output: output))
            }
            preferences.value.previewPane = false
            preferences.value.inspector = false
            tab.entries = []
            captures.append(try await capture(shell(), named: "\(theme)-empty", size: NSSize(width: 1024, height: 700), dark: dark, output: output))
            tab.error = "Access to this folder was denied. Choose a different location or review macOS privacy settings."
            captures.append(try await capture(shell(), named: "\(theme)-permission-denied", size: NSSize(width: 1024, height: 700), dark: dark, output: output))
            tab.error = nil
            tab.entries = entries
            tab.selection = [urls[3], urls[4]]
            for sheet in [ExplorerSheet.newFolder, .newFile, .rename, .tags, .connect] {
                let view = AnyView(ExplorerSheetView(sheet: sheet, workspace: workspace).environmentObject(preferences).environmentObject(updater))
                captures.append(try await capture(view, named: "\(theme)-dialog-\(sheet.rawValue)", size: NSSize(width: 700, height: 580), dark: dark, output: output))
            }
            let job = OperationRow(title: "Copy project assets")
            job.progress = FileProgress(completed: 3, total: 9, name: "Brand assets", bytes: 6_000_000, logicalBytes: 6_000_000, totalBytes: 20_000_000, phase: .copying, sequence: 1)
            job.status = "Copying"
            let now = ProcessInfo.processInfo.systemUptime
            for index in 0..<40 { job.statistics.record(bytes: Int64(index) * 150_000, at: now - 4 + Double(index) * 0.1) }
            OperationCenter.shared.jobs = [job]
            captures.append(try await capture(AnyView(OperationsView(workspace: workspace)), named: "\(theme)-transfers", size: NSSize(width: 760, height: 650), dark: dark, output: output))
            captures.append(try await capture(AnyView(PreferencesView().environmentObject(preferences).environmentObject(updater)), named: "\(theme)-preferences", size: NSSize(width: 700, height: 580), dark: dark, output: output))
        }
        workspace.tabs.forEach { $0.stop() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("captures.json"), options: .atomic)
        XCTAssertEqual(captures.count, 44)
    }

    @MainActor private func capture(_ content: AnyView, named name: String, size: NSSize, dark: Bool, output: URL) async throws -> Capture {
        let host = NSHostingView(rootView: content
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .transaction { $0.animation = nil })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = dark ? NSColor(calibratedWhite: 0.11, alpha: 1) : .windowBackgroundColor
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        // Give SwiftUI/AppKit layout, native tables, icons and async tasks a run-loop turn.
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
        XCTAssertEqual(host.bounds.width, size.width, accuracy: 1, "Horizontal overflow: \(name)")
        XCTAssertEqual(host.bounds.height, size.height, accuracy: 1, "Vertical overflow: \(name)")
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds), "No bitmap: \(name)")
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        var shades = Set<Int>(), low = 1.0, high = 0.0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                low = min(low, luminance); high = max(high, luminance)
                shades.insert(Int((luminance * 255).rounded()))
            }
        }
        XCTAssertGreaterThan(high - low, 0.15, "Blank/low-contrast render: \(name)")
        XCTAssertGreaterThan(shades.count, 12, "Missing native content: \(name)")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        return Capture(name: name, width: Int(size.width), height: Int(size.height), pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh, luminanceRange: high - low, distinctSamples: shades.count)
    }
}
