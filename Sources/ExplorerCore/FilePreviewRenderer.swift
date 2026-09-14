import Foundation
import CoreGraphics
import ImageIO

/// Bounded native image/PDF rasterization. UI callers run this off MainActor;
/// no NSImage, NSView or mutable document crosses the rendering boundary.
public enum FilePreviewRenderer {
    public static func render(_ url: URL, maximumPixelSize: Int) throws -> CGImage {
        guard url.isFileURL, (16...2048).contains(maximumPixelSize) else { throw ExplorerError.message("Invalid preview request.") }
        if url.pathExtension.lowercased() == "pdf" { return try pdf(url, maximumPixelSize: maximumPixelSize) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
              ] as CFDictionary) else { throw ExplorerError.message("No image preview is available for this file.") }
        return image
    }
    private static func pdf(_ url: URL, maximumPixelSize: Int) throws -> CGImage {
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted || document.isUnlocked,
              let page = document.page(at: 1) else { throw ExplorerError.message("This PDF cannot be previewed without opening or unlocking it.") }
        let box = page.getBoxRect(.cropBox)
        guard box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0,
              box.width < 100_000, box.height < 100_000 else { throw ExplorerError.message("The PDF page has invalid dimensions.") }
        let rotated = (page.rotationAngle / 90) % 2 != 0
        let pageWidth = rotated ? box.height : box.width, pageHeight = rotated ? box.width : box.height
        let scale = CGFloat(maximumPixelSize) / max(pageWidth, pageHeight)
        let width = max(1, min(maximumPixelSize, Int((pageWidth * scale).rounded(.up))))
        let height = max(1, min(maximumPixelSize, Int((pageHeight * scale).rounded(.up))))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ExplorerError.message("Could not allocate the PDF preview.") }
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(frame)
        context.concatenate(page.getDrawingTransform(.cropBox, rect: frame, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw ExplorerError.message("Could not render the PDF preview.") }
        return image
    }
}
