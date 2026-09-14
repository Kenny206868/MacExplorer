import XCTest
@testable import ExplorerCore

final class DetailsColumnsTests: XCTestCase {
    func testFourDefaultColumnsFillWithoutClippingAtEveryUsableWidth() {
        let configuration = DetailsColumns()
        XCTAssertEqual(configuration.visible, [.name, .modified, .kind, .size])
        for width in stride(from: 430.0, through: 2400, by: 1) {
            let sizes = configuration.widths(available: width)
            XCTAssertEqual(sizes.reduce(0, +), width, accuracy: 0.001)
            for (column, size) in zip(configuration.visible, sizes) { XCTAssertGreaterThanOrEqual(size, column.minimum) }
        }
    }
    func testReferenceProportionsAndIntentionalNarrowScrolling() {
        let sizes = DetailsColumns().widths(available: 800)
        XCTAssertEqual(sizes, [384, 200, 136, 80])
        XCTAssertEqual(DetailsColumns().widths(available: 350), [160, 118, 88, 64])
    }
    func testVisibilityReorderingAndMalformedPersistenceRemainSafe() {
        var value = DetailsColumns(); value.order = [.size, .size]; value.hidden = [.name, .tags, .availability]
        XCTAssertEqual(value.visible, [.size, .name, .modified, .kind])
        value.move(.name, before: .size); XCTAssertEqual(value.visible.first, .name)
        value.overrides["name"] = .nan
        XCTAssertTrue(value.widths(available: .infinity).allSatisfy { $0.isFinite && $0 > 0 })
        value.setWidth(-20, for: .name); XCTAssertEqual(value.overrides["name"], 160)
        value.setWidth(.infinity, for: .name); XCTAssertEqual(value.overrides["name"], 160)
    }
    func testExplicitWidthsAreNotSilentlyOverwritten() throws {
        var value = DetailsColumns(); value.setWidth(600, for: .name)
        XCTAssertEqual(value.widths(available: 700).first, 600)
        XCTAssertGreaterThan(value.widths(available: 700).reduce(0, +), 700)
        let decoded = try JSONDecoder().decode(DetailsColumns.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded, value)
    }
}
