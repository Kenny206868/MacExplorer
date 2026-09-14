import XCTest
import SwiftUI
import AppKit
import ExplorerCore
@testable import MacExplorer

final class FilePromiseHostingTests: XCTestCase {
    @MainActor private final class Probe { var scheme: ColorScheme? }
    private struct SchemeProbe: View {
        let probe: Probe
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            Text("Readable file label").foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .onAppear { probe.scheme = scheme }
                .onChange(of: scheme) { _, value in probe.scheme = value }
        }
    }
    @MainActor func testNestedFileHostReceivesSwiftUIAndAppKitAppearance() async throws {
        _ = NSApplication.shared
        let workspace = ExplorerWorkspace(session: BrowserSession(id: UUID(), history: NavigationHistory(.home), options: FolderOptions(), query: "", allLocations: false, selection: []))
        defer { workspace.tabs.forEach { $0.stop() } }
        for scheme in [ColorScheme.light, .dark] {
            let probe = Probe()
            let root = NSHostingView(rootView: FilePromiseDropHost(workspace: workspace) { SchemeProbe(probe: probe) }
                .environment(\.colorScheme, scheme).frame(width: 400, height: 300))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = root
            window.orderFrontRegardless()
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            try await Task.sleep(for: .milliseconds(100))
            root.layoutSubtreeIfNeeded()
            func find(_ view: NSView) -> PromiseDropHostingView? {
                if let value = view as? PromiseDropHostingView { return value }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            let nested = try XCTUnwrap(find(root))
            XCTAssertEqual(probe.scheme, scheme)
            XCTAssertEqual(nested.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), scheme == .dark ? .darkAqua : .aqua)
            var background: CGFloat = 0, foreground: CGFloat = 0
            nested.effectiveAppearance.performAsCurrentDrawingAppearance {
                background = NSColor.textBackgroundColor.usingColorSpace(.sRGB)?.redComponent ?? -1
                foreground = NSColor.labelColor.usingColorSpace(.sRGB)?.redComponent ?? -1
            }
            XCTAssertGreaterThan(abs(background - foreground), 0.5)
            if scheme == .dark { XCTAssertLessThan(background, 0.4); XCTAssertGreaterThan(foreground, 0.6) }
            else { XCTAssertGreaterThan(background, 0.6); XCTAssertLessThan(foreground, 0.4) }
        }
    }
}
