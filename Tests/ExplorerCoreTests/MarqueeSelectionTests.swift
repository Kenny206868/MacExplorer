import XCTest
@testable import ExplorerCore

final class MarqueeSelectionTests: XCTestCase {
    func testIncrementalProjectionMatchesReferenceForEverySelectionMode() {
        let order = Array(0..<150), baseline: Set<Int> = [0, 7, 12, 95, 149]
        for mode in [MarqueeSelectionMode.replace, .add, .toggle] {
            var projection = MarqueeSelection(order: order, baseline: baseline, mode: mode)
            var published = baseline, random: UInt64 = 0x93AB672F
            for _ in 0..<1500 {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                let first = Int(random >> 32) % 180
                random = random &* 6364136223846793005 &+ 1442695040888963407
                let last = Int(random >> 32) % 180
                let hits = IndexSet(integersIn: min(first, last)..<max(first, last))
                let identifiers = Set(hits.filter { order.indices.contains($0) }.map { order[$0] })
                let expected = mode == .replace ? identifiers : mode == .add ? baseline.union(identifiers) : baseline.symmetricDifference(identifiers)
                if let result = projection.update(hits: hits) { published = result }
                XCTAssertEqual(published, expected)
                XCTAssertNil(projection.update(hits: hits), "An identical hit set must not reproject")
            }
        }
    }
    func testLeavingToggleRangeRestoresOriginalBaseline() {
        var projection = MarqueeSelection(order: Array(0..<10), baseline: [3, 8], mode: .toggle)
        XCTAssertEqual(projection.update(hits: [3, 5]), [5, 8])
        XCTAssertEqual(projection.update(hits: [5]), [3, 5, 8])
        XCTAssertEqual(projection.update(hits: []), [3, 8])
        XCTAssertNil(projection.update(hits: [1000]), "Invalid indices are excluded before comparing")
    }
    func testEmptyReplaceClearsBaselineOnlyOnce() {
        var projection = MarqueeSelection(order: [0, 1, 2], baseline: [1, 2], mode: .replace)
        XCTAssertEqual(projection.update(hits: []), [])
        XCTAssertNil(projection.update(hits: []))
        XCTAssertEqual(projection.projectionUpdates, 1)
    }
    func testTenThousandStableFramesDoNotReprojectEightyNineThousandFiles() {
        var projection = MarqueeSelection(order: Array(0..<100_000), baseline: [], mode: .replace)
        let hits = IndexSet(integersIn: 1_000..<90_000)
        XCTAssertEqual(projection.update(hits: hits)?.count, 89_000)
        for _ in 0..<10_000 { XCTAssertNil(projection.update(hits: hits)) }
        XCTAssertEqual(projection.projectionUpdates, 1)
    }
}
