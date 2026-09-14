import XCTest
import SwiftUI
import AppKit
import QuartzCore
@testable import MacExplorer

@MainActor enum NativeSnapshotCapture {
    static func render(_ content: AnyView, named name: String, size: NSSize, dark: Bool, output: URL,
                       chromeOwner: ExplorerWorkspace? = nil, verify: ((NSWindow) throws -> Void)? = nil) async throws -> NativeViewSnapshotTests.Capture {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .transaction { $0.animation = nil })
        let window = SnapshotWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: chromeOwner == nil ? [.borderless] : [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.backgroundColor = .windowBackgroundColor; window.contentView = host
        let chrome = NativeWindowChrome(); chrome.persistsConfiguration = false
        if let chromeOwner { chromeOwner.window = window; chrome.attach(to: window, owner: chromeOwner); window.setContentSize(size) }
        host.frame = NSRect(origin: .zero, size: size); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
        // Let actual lazy field-editor focus tasks settle, without changing
        // the first responder on the application's behalf.
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
        XCTAssertEqual(host.bounds.width, size.width, accuracy: 1, "Horizontal overflow: \(name)")
        XCTAssertEqual(host.bounds.height, size.height, accuracy: 1, "Vertical overflow: \(name)")
        let renderedView = chromeOwner == nil ? host : (host.superview ?? host)
        let raw = try XCTUnwrap(renderedView.bitmapImageRepForCachingDisplay(in: renderedView.bounds), "No bitmap: \(name)")
        renderedView.cacheDisplay(in: renderedView.bounds, to: raw)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: raw.pixelsWide, height: raw.pixelsHigh,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let rectangle = CGRect(x: 0, y: 0, width: raw.pixelsWide, height: raw.pixelsHigh)
        window.appearance?.performAsCurrentDrawingAppearance { context.setFillColor(window.backgroundColor.cgColor); context.fill(rectangle) }
        context.draw(try XCTUnwrap(raw.cgImage), in: rectangle)
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent(name + ".png"), options: .atomic)
        try verify?(window) // Preserve failed captures as evidence.
        var shades = Set<Int>(), low = 1.0, high = 0.0, minimumAlpha = 1.0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 7) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 7) {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                minimumAlpha = min(minimumAlpha, c.alphaComponent)
                let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                low = min(low, luminance); high = max(high, luminance); shades.insert(Int((luminance * 255).rounded()))
            }
        }
        XCTAssertGreaterThanOrEqual(minimumAlpha, 0.99, "Uncomposited render: \(name)")
        XCTAssertGreaterThan(high - low, 0.15, "Blank/low-contrast render: \(name)")
        XCTAssertGreaterThan(shades.count, 12, "Missing native content: \(name)")
        return NativeViewSnapshotTests.Capture(name: name, width: Int(renderedView.bounds.width), height: Int(renderedView.bounds.height), pixelsWide: bitmap.pixelsWide, pixelsHigh: bitmap.pixelsHigh, luminanceRange: high - low, distinctSamples: shades.count, minimumAlpha: minimumAlpha)
    }
}
@MainActor private final class SnapshotWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
