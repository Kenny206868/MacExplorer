import XCTest
import CoreGraphics
import ImageIO
@testable import ExplorerCore

final class FilePreviewRendererTests: XCTestCase {
    func testPDFPreviewRendersActualContentWithinPixelBudget() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        var page = CGRect(x: 0, y: 0, width: 210, height: 297)
        let consumer = try XCTUnwrap(CGDataConsumer(url: url as CFURL))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &page, nil))
        context.beginPDFPage(nil); context.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.8, alpha: 1)); context.fill(page)
        context.endPDFPage(); context.closePDF()
        let before = try Data(contentsOf: url)
        let image = try FilePreviewRenderer.render(url, maximumPixelSize: 160)
        XCTAssertEqual(image.height, 160); XCTAssertLessThanOrEqual(image.width, 160); XCTAssertGreaterThan(image.width, 100)
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testInvalidSourceAndOutOfRangeBudgetAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("not an image".utf8); try original.write(to: url)
        XCTAssertThrowsError(try FilePreviewRenderer.render(url, maximumPixelSize: 120))
        XCTAssertThrowsError(try FilePreviewRenderer.render(url, maximumPixelSize: 1_000_000))
        XCTAssertThrowsError(try FilePreviewRenderer.render(URL(string: "https://example.invalid/file.png")!, maximumPixelSize: 120))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}
