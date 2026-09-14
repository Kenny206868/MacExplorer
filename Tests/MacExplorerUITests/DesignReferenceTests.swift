import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class DesignReferenceTests: XCTestCase {
    @MainActor private final class GeometryProbe { var regions: [String: CGRect] = [:] }
    @MainActor func testPopulatedReferenceViewsMatchDesignGeometryAndPalette() async throws {
        guard let path = ProcessInfo.processInfo.environment["MACEXPLORER_SNAPSHOT_DIR"] else { throw XCTSkip("Native capture job only") }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path), manager = FileManager.default
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let fixtureRoot = manager.temporaryDirectory.appendingPathComponent("MacExplorer-Reference-" + UUID().uuidString)
        let root = fixtureRoot.appendingPathComponent("This Mac"), documents = root.appendingPathComponent("Documents")
        let store = PreferenceStore.shared, previous = store.value
        let previousColumns = DetailsColumnStore.shared.value, previousJobs = OperationCenter.shared.jobs
        let preferencesKey = "MacExplorer.preferences.v1", saved = UserDefaults.standard.data(forKey: "MacExplorer.preferences.v1")
        defer {
            store.value = previous; DetailsColumnStore.shared.value = previousColumns; OperationCenter.shared.jobs = previousJobs
            if let saved { UserDefaults.standard.set(saved, forKey: preferencesKey) } else { UserDefaults.standard.removeObject(forKey: preferencesKey) }
            try? manager.removeItem(at: fixtureRoot)
        }
        try manager.createDirectory(at: documents, withIntermediateDirectories: true)
        let folders = ["Desktop", "Downloads", "Documents", "Pictures", "Projects", "Design assets"].map { root.appendingPathComponent($0) }
        for url in folders { try manager.createDirectory(at: url, withIntermediateDirectories: true) }
        let fileNames = ["Brand guidelines.md", "Budget 2026.csv", "Meeting notes.txt", "Project proposal.pdf", "Release checklist.md", "Research notes.txt", "Website roadmap.md"]
        for name in fileNames {
            let url = documents.appendingPathComponent(name)
            if url.pathExtension == "pdf" { try createPDF(at: url) }
            else { try Data(("# " + name + "\n\nMacExplorer design reference document.\n").utf8).write(to: url) }
            try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_789_099_200)], ofItemAtPath: url.path)
        }
        let entries = try fileNames.map { try FileEntry(url: documents.appendingPathComponent($0)) }
        var settings = Preferences(); settings.pins = folders.map(Bookmark.init); settings.restoreTabs = false; settings.inspector = true; settings.previewPane = false
        settings.recent = entries.map { Bookmark($0.url) }; settings.theme = "light"
        store.value = settings; DetailsColumnStore.shared.value = DetailsColumns(); OperationCenter.shared.jobs = []
        var captures: [NativeViewSnapshotTests.Capture] = [], evidence: [[String: String]] = []
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"; store.value.theme = theme
            for name in ["home", "details", "computer"] {
                let location: Location = name == "home" ? .home : name == "computer" ? .computer : .folder(documents)
                let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(location), options: FolderOptions(), query: "", allLocations: false, selection: []))
                let tab = workspace.current
                tab.stop(); tab.entries = name == "computer" ? [] : entries; tab.loading = false
                if name != "computer" { tab.selection = [entries[3].url] }
                let probe = GeometryProbe()
                let content = AnyView(WorkspaceShell(workspace: workspace, tab: tab).environmentObject(workspace).environmentObject(store).environmentObject(AppUpdater())
                    .onPreferenceChange(ExplorerLayoutRegions.self) { probe.regions = $0 })
                let captureName = theme + "-reference-" + name
                captures.append(try await NativeSnapshotCapture.render(content, named: captureName, size: NSSize(width: 1260, height: 800), dark: dark, output: output))
                let geometry = probe.regions
                XCTAssertEqual(try XCTUnwrap(geometry["sidebar"]).width, 211, accuracy: 0.5, captureName)
                let inspector = try XCTUnwrap(geometry["inspector"])
                XCTAssertEqual(inspector.width, 254, accuracy: 0.5, captureName)
                XCTAssertEqual(try XCTUnwrap(geometry["files"]).width, 793, accuracy: 0.5, captureName)
                for (region, height) in [("tabs", 42.0), ("address", 54), ("status", 30)] { XCTAssertEqual(try XCTUnwrap(geometry[region]).height, height, accuracy: 0.5, captureName + " " + region) }
                XCTAssertNil(geometry["commands"], "The real native toolbar replaces duplicate content commands")
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output.appendingPathComponent(captureName + ".png"))))
                try assertColor(bitmap, point: CGPoint(x: 880, y: 20), rgb: dark ? 0x292B33 : 0xF7F7F9, label: captureName + " tab chrome")
                try assertColor(bitmap, point: CGPoint(x: 6, y: 510), rgb: dark ? 0x25272F : 0xF3F4F7, label: captureName + " sidebar")
                try assertColor(bitmap, point: CGPoint(x: inspector.minX + 4, y: 735), rgb: dark ? 0x202228 : 0xFFFFFF, label: captureName + " inspector canvas")
                if name == "details" {
                    let frame = try XCTUnwrap(geometry["files"]), index = try XCTUnwrap(tab.displayEntries.firstIndex { $0.url == entries[3].url })
                    try assertColor(bitmap, point: CGPoint(x: frame.minX + 3, y: frame.minY + 34 + CGFloat(index) * 36 + 18), rgb: dark ? 0x153E6D : 0xE4F0FF, label: captureName + " selected row")
                    try assertColor(bitmap, point: CGPoint(x: frame.minX + 35, y: 720), rgb: dark ? 0x202228 : 0xFFFFFF, label: captureName + " no empty zebra rows")
                }
                evidence.append(["capture": captureName, "geometry": "211 sidebar / 793 files / 254 inspector; native toolbar outside content", "palette": "encoded sRGB surface and selection channels checked"])
                workspace.tabs.forEach { $0.stop() }
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(captures).write(to: output.appendingPathComponent("design-captures.json"), options: .atomic)
        try encoder.encode(evidence).write(to: output.appendingPathComponent("design-assertions.json"), options: .atomic)
        XCTAssertEqual(captures.count, 6)
    }
    @MainActor private func assertColor(_ bitmap: NSBitmapImageRep, point: CGPoint, rgb: Int, label: String) throws {
        XCTAssertEqual(bitmap.bitsPerSample, 8, label); XCTAssertFalse(bitmap.isPlanar, label)
        XCTAssertGreaterThanOrEqual(bitmap.samplesPerPixel, 3, label)
        let scale = CGFloat(bitmap.pixelsWide) / 1260
        let expected = [(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255]
        for offset in [-1, 0, 1] {
            var pixel = [Int](repeating: 0, count: bitmap.samplesPerPixel)
            bitmap.getPixel(&pixel, atX: Int(point.x * scale) + offset, y: Int(point.y * scale))
            for (actual, reference) in zip(pixel.prefix(3), expected) { XCTAssertEqual(Double(actual), Double(reference), accuracy: 6, label) }
        }
    }
    @MainActor private func createPDF(at url: URL) throws {
        var box = CGRect(x: 0, y: 0, width: 420, height: 560)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil); context.setFillColor(NSColor.white.cgColor); context.fill(box)
        context.setFillColor(NSColor(srgbRed: 0.06, green: 0.38, blue: 0.75, alpha: 1).cgColor); context.fill(CGRect(x: 0, y: 440, width: 420, height: 120))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("PROJECT PROPOSAL" as NSString).draw(at: CGPoint(x: 32, y: 484), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: NSColor.white])
        ("MacExplorer\n\nA familiar workspace. A native experience.\n\nDesign direction and implementation plan\nSeptember 2026" as NSString).draw(in: CGRect(x: 32, y: 120, width: 350, height: 265), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray])
        NSGraphicsContext.restoreGraphicsState(); context.endPDFPage(); context.closePDF()
    }
}
