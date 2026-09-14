import XCTest
@testable import ExplorerCore

final class SelectionTests: XCTestCase {
    let order = Array(0..<8)
    func testShiftRangeShrinksWithoutRetainingOldItems() {
        var s = ExplorerSelection<Int>()
        s.click(2, in: order); s.click(6, in: order, range: true)
        XCTAssertEqual(s.selected, Set(2...6))
        s.click(4, in: order, range: true)
        XCTAssertEqual(s.selected, Set(2...4)); XCTAssertEqual(s.anchor, 2)
    }
    func testControlShiftAddsRange() {
        var s = ExplorerSelection<Int>()
        s.click(0, in: order); s.click(4, in: order, toggle: true)
        s.click(6, in: order, toggle: true, range: true)
        XCTAssertEqual(s.selected, [0, 4, 5, 6])
    }
    func testKeyboardExtendsFromFocusNotFirstSelection() {
        var s = ExplorerSelection<Int>()
        s.click(1, in: order); s.move(by: 1, in: order, extend: true)
        s.move(by: 1, in: order, extend: true)
        XCTAssertEqual(s.selected, [1, 2, 3]); XCTAssertEqual(s.focus, 3)
        s.move(by: -1, in: order, extend: true)
        XCTAssertEqual(s.selected, [1, 2])
    }
    func testControlArrowOnlyMovesFocus() {
        var s = ExplorerSelection<Int>(); s.click(1, in: order)
        s.move(by: 2, in: order, focusOnly: true)
        XCTAssertEqual(s.selected, [1]); XCTAssertEqual(s.focus, 3)
    }
    func testHomeEndAndReconcile() {
        var s = ExplorerSelection<Int>(); s.click(3, in: order)
        s.boundary(last: true, in: order, extend: true)
        XCTAssertEqual(s.selected, Set(3...7))
        s.reconcile(with: [0, 3, 4]); XCTAssertEqual(s.selected, [3, 4])
        XCTAssertEqual(s.focus, 3)
    }
    func testEmptyOrderAndStaleAnchorAreSafe() {
        var s = ExplorerSelection<Int>(selected: [99], anchor: 99, focus: 99)
        s.move(by: 1, in: []); s.click(2, in: order, range: true)
        XCTAssertEqual(s.selected, [2]); XCTAssertEqual(s.anchor, 2)
    }
    func testTypeAheadCyclesThenRefines() {
        var t = TypeAheadSearch(); let names = ["Alpha", "Beta", "Bravo", "Charlie"]
        XCTAssertEqual(t.match("b", names: names, focusedIndex: 0, time: 1), 1)
        XCTAssertEqual(t.match("b", names: names, focusedIndex: 1, time: 1.1), 2)
        XCTAssertEqual(t.match("r", names: names, focusedIndex: 2, time: 1.2), 2)
        XCTAssertEqual(t.prefix, "br")
    }
    func testTypeAheadTimeoutAndUnicode() {
        var t = TypeAheadSearch(); let names = ["Éclair", "Notes", "工程"]
        XCTAssertEqual(t.match("e", names: names, focusedIndex: 1, time: 1), 0)
        XCTAssertEqual(t.match("工", names: names, focusedIndex: 0, time: 3), 2)
        XCTAssertNil(t.match("\n", names: names, focusedIndex: 2, time: 3.1))
    }
}
