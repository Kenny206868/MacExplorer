import XCTest
@testable import ExplorerCore

final class IndexedSelectionTests: XCTestCase {
    func testIndexedSelectionMatchesReferenceAcrossInputSequences() {
        let ids = Array(0..<257), indexed = IndexedSelectionOrder(Array(0..<257))
        var reference = ExplorerSelection<Int>(), actual = reference
        var random: UInt64 = 0x9abc
        func next() -> Int { random = random &* 6364136223846793005 &+ 1; return Int((random >> 32) & 0x7fff) }
        for _ in 0..<10_000 {
            let action = next() % 4, item = next() % 300, flag = next() % 2 == 0, second = next() % 2 == 0
            switch action {
            case 0:
                reference.click(item, in: ids, toggle: flag, range: second)
                actual.click(item, in: indexed, toggle: flag, range: second)
            case 1:
                let delta = item % 23 - 11
                reference.move(by: delta, in: ids, extend: flag, focusOnly: second)
                actual.move(by: delta, in: indexed, extend: flag, focusOnly: second)
            case 2:
                reference.boundary(last: flag, in: ids, extend: second)
                actual.boundary(last: flag, in: indexed, extend: second)
            default:
                reference.focus = nil; actual.focus = nil
            }
            XCTAssertEqual(actual.selected, reference.selected); XCTAssertEqual(actual.focus, reference.focus); XCTAssertEqual(actual.anchor, reference.anchor)
        }
    }
    func testSparseSelectionFocusAndExtremeOffsets() {
        let order = IndexedSelectionOrder(Array(0..<100_000))
        XCTAssertEqual(order.firstSelectedIndex(in: [70_000, 5]), 5)
        var model = ExplorerSelection(selected: [50_000], focus: 50_000)
        model.move(by: .max, in: order); XCTAssertEqual(model.focus, 99_999)
        model.move(by: .min, in: order); XCTAssertEqual(model.focus, 0)
        model.move(by: 1, in: order, focusOnly: true)
        XCTAssertEqual(model.selected, [0]); XCTAssertEqual(model.focus, 1)
    }
    func testEmptyMissingAndDuplicateIDsAreSafe() {
        let order = IndexedSelectionOrder([2, 1, 2]); XCTAssertEqual(order.index(of: 2), 0)
        var selection = ExplorerSelection<Int>(); selection.click(3, in: order)
        XCTAssertTrue(selection.selected.isEmpty)
        selection.move(by: 1, in: IndexedSelectionOrder([])); XCTAssertNil(selection.focus)
    }
}
