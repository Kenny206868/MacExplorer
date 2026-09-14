import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = directory.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func render(_ pixels: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let s = CGFloat(pixels) / 1024
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = AffineTransform(scale: s)
    (transform as NSAffineTransform).concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 210, yRadius: 210)
    NSGradient(starting: NSColor(calibratedRed: 0.38, green: 0.78, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.015, green: 0.32, blue: 0.88, alpha: 1))!.draw(in: background, angle: -90)
    let window = NSBezierPath(roundedRect: NSRect(x: 178, y: 249, width: 668, height: 542), xRadius: 53, yRadius: 53)
    NSColor.white.withAlphaComponent(0.95).setFill(); window.fill()
    let chrome = NSBezierPath(roundedRect: NSRect(x: 178, y: 686, width: 668, height: 105), xRadius: 53, yRadius: 53)
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); chrome.fill()
    NSColor(calibratedWhite: 0.95, alpha: 1).setFill(); NSRect(x: 178, y: 686, width: 668, height: 55).fill()
    for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() { color.setFill(); NSBezierPath(ovalIn: NSRect(x: 211 + index * 39, y: 725, width: 22, height: 22)).fill() }
    NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.98, alpha: 1).setFill(); NSRect(x: 178, y: 297, width: 154, height: 389).fill()
    let folder = NSBezierPath()
    folder.move(to: NSPoint(x: 395, y: 395)); folder.line(to: NSPoint(x: 760, y: 395)); folder.line(to: NSPoint(x: 760, y: 615)); folder.line(to: NSPoint(x: 568, y: 615)); folder.line(to: NSPoint(x: 539, y: 644)); folder.line(to: NSPoint(x: 395, y: 644)); folder.close()
    NSGradient(starting: NSColor.systemTeal, ending: NSColor.systemBlue)!.draw(in: folder, angle: -90)
    NSColor.systemBlue.withAlphaComponent(0.42).setFill()
    for i in 0..<5 { NSBezierPath(roundedRect: NSRect(x: 208, y: 601 - i * 56, width: 95, height: 12), xRadius: 6, yRadius: 6).fill() }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Icon", code: 1) }
    return data
}
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); process.arguments = ["-c", "icns", iconset.path, "-o", directory.appendingPathComponent("AppIcon.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { throw NSError(domain: "Iconutil", code: Int(process.terminationStatus)) }
try FileManager.default.removeItem(at: iconset)
