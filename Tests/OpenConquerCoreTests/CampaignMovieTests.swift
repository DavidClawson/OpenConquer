import XCTest
import OpenConquerAssets
@testable import OpenConquerCore

/// Which movies play around a campaign mission: the [Basic] keys
/// (INI.CPP:296-300) and Start_Scenario's sequencing (SCENARIO.CPP:94-104).
final class CampaignMovieTests: XCTestCase {
    private let ini = INIFile(string: """
        [Basic]
        Intro=gdi2
        Brief=GDI2B
        Action=x
        Win=GDIWIN
        Lose=
        """)

    func testBasicSectionParsing() {
        let m = ScenarioMovies(ini: ini)
        XCTAssertEqual(m.intro, "GDI2")       // uppercased
        XCTAssertEqual(m.brief, "GDI2B")
        XCTAssertNil(m.action)                // "x" means none
        XCTAssertEqual(m.win, "GDIWIN")
        XCTAssertNil(m.lose)                  // empty means none
        XCTAssertEqual(ScenarioMovies(ini: INIFile(string: "")), ScenarioMovies())
    }

    func testPreMissionSequence() {
        let m = ScenarioMovies(intro: "I", brief: "B", action: "A")
        // GDI mission 1: intro and action, no briefing.
        XCTAssertEqual(m.preMission(mission: 1, isGDI: true, briefing: true), ["I", "A"])
        // Nod mission 1: the choose-sides screen replaces the intro.
        XCTAssertEqual(m.preMission(mission: 1, isGDI: false, briefing: true), ["B", "A"])
        // Later missions: all three, in order.
        XCTAssertEqual(m.preMission(mission: 5, isGDI: true, briefing: true), ["I", "B", "A"])
        // A restart skips the briefing.
        XCTAssertEqual(m.preMission(mission: 5, isGDI: false, briefing: false), ["I", "A"])
    }
}
