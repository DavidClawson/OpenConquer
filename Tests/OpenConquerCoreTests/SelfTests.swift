import XCTest
import OpenConquerCore

// The asset-free self-tests (Sources/OpenConquerCore/SelfTests), one test each.
// Every self-test returns 0 on pass, the same exit code its `--test-*` flag
// uses. They mutate process globals (`session`, `forcedGameSeed`, `gameRng`),
// so they must run serially: XCTest does by default, so never run this target
// with `--parallel`. XCTest rather than swift-testing because the CI matrix's
// macos-14 leg (Swift 5.10 / Xcode 15) has no `Testing` module.
final class SelfTests: XCTestCase {
    // Triggers
    func testTriggersEx() { XCTAssertEqual(headlessTestTriggersExCommand(), 0) }
    func testTwoEvent() { XCTAssertEqual(headlessTestTwoEventCommand(), 0) }
    func testRegions() { XCTAssertEqual(headlessTestRegionsCommand(), 0) }
    func testWinGate() { XCTAssertEqual(headlessTestWinGateCommand(), 0) }
    func testWinLose() { XCTAssertEqual(headlessTestWinLoseCommand(), 0) }
    func testEventParity() { XCTAssertEqual(headlessTestEventParityCommand(), 0) }
    func testInitTeams() { XCTAssertEqual(headlessTestInitTeamsCommand(), 0) }

    // Enemy AI
    func testTeamFormer() { XCTAssertEqual(headlessTestTeamFormerCommand(), 0) }
    func testPrebuilt() { XCTAssertEqual(headlessTestPrebuiltCommand(), 0) }
    func testAIGating() { XCTAssertEqual(headlessTestAIGatingCommand(), 0) }
    func testEnemySuperWeapon() { XCTAssertEqual(headlessTestEnemySuperWeaponCommand(), 0) }
    func testOriginalTargeting() { XCTAssertEqual(headlessTestOriginalTargetingCommand(), 0) }

    // Campaign
    func testCampaignGraph() { XCTAssertEqual(headlessTestCampaignGraphCommand(), 0) }
    func testCivEvac() { XCTAssertEqual(headlessTestCivEvacCommand(), 0) }

    // Units and economy
    func testReinforcements() { XCTAssertEqual(headlessTestReinforcementsCommand(), 0) }
    func testHeliTransport() { XCTAssertEqual(headlessTestHeliTransportCommand(), 0) }
    func testHarvesterEconomy() { XCTAssertEqual(headlessTestHarvesterEconomyCommand(), 0) }

    // Player commands
    func testCommandReplay() { XCTAssertEqual(headlessTestCommandReplayCommand(), 0) }
    func testCommandOwnership() { XCTAssertEqual(headlessTestCommandOwnershipCommand(), 0) }

    // Determinism net (the tick count CI used for `--test-synthetic 500`)
    func testSynthetic() { XCTAssertEqual(headlessTestSyntheticCommand(ticks: 500), 0) }
}
