import XCTest
@testable import OpenConquerCore

/// The score screen's arithmetic (SCORE.CPP:643-696) and the hall-of-fame
/// insertion (SCORE.CPP:900-913).
final class ScoreFormulaTests: XCTestCase {
    private func inputs(survivors: Int = 20, gdiLost: Int = 5, gdiBldgLost: Int = 0,
                        harvested: Int = 3000, initial: Int = 1000, credits: Int = 2000,
                        scenario: Int = 3, ticks: Int = 9000) -> ScoreInputs {
        ScoreInputs(isGDI: true, scenario: scenario, elapsedTicks: ticks, survivingObjects: survivors,
                    gdiUnitsLost: gdiLost, nodUnitsLost: 40, civUnitsLost: 3,
                    gdiBuildingsLost: gdiBldgLost, nodBuildingsLost: 7, civBuildingsLost: 1,
                    harvestedCredits: harvested, initialCredits: initial, credits: credits)
    }

    func testTypicalMission() {
        let r = ScoreResult(inputs())
        XCTAssertEqual(r.leadership, 80)   // 20 of 25: 204/256 -> 80%
        XCTAssertEqual(r.efficiency, 50)   // 2001 / 4001
        XCTAssertEqual(r.total, 340)       // (3200 + 4600 + 700) / 100 = 85, x (3 + 1)
        XCTAssertEqual(r.minutes, 11)      // 10 minutes played, printed + 1
    }

    func testClampsAndFloors() {
        // No survivors and no losses still rates 100%; finishing richer than
        // you started saturates efficiency at 100%.
        let r = ScoreResult(inputs(survivors: 0, gdiLost: 0, harvested: 0, initial: 5000,
                                   credits: 10000, scenario: 1, ticks: 0))
        XCTAssertEqual(r.leadership, 100)
        XCTAssertEqual(r.efficiency, 100)
        XCTAssertEqual(r.total, 200)
        XCTAssertEqual(r.minutes, 1)
        // Broke at the end: efficiency floors at 1 fixed-point step -> 0%.
        XCTAssertEqual(ScoreResult(inputs(credits: 0)).efficiency, 0)
    }

    func testHallOfFameInsertion() {
        var list: [FameEntry] = []
        XCTAssertEqual(HallOfFame.insert(total: 340, level: 3, into: &list), 0)
        XCTAssertEqual(list.count, HallOfFame.count)
        XCTAssertEqual(list[0], FameEntry(name: String(repeating: " ", count: 11), score: 340, level: 3))

        // Lands in the middle; everyone below moves down one.
        list = (0..<7).map { FameEntry(name: "P\($0)", score: 1000 - $0 * 100, level: 1) }
        XCTAssertEqual(HallOfFame.insert(total: 750, level: 5, into: &list), 3)
        XCTAssertEqual(list.map(\.score), [1000, 900, 800, 750, 700, 600, 500])
        XCTAssertEqual(list[4].name, "P3")

        // Too low for the table: it still replaces the bottom row.
        list = (0..<7).map { FameEntry(name: "P\($0)", score: 1000 - $0 * 100, level: 1) }
        XCTAssertEqual(HallOfFame.insert(total: 100, level: 2, into: &list), 6)
        XCTAssertEqual(list[6].score, 100)
    }
}
