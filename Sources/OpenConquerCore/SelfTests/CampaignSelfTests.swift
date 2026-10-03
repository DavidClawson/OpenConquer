import Foundation
import OpenConquerAssets

// MARK: - Campaign self-tests
//
// Asset-free: each builds its world in code and never loads from a MIX, so
// they run under `swift test` (Tests/OpenConquerCoreTests) as well as through
// their `--test-*` flags in the app. Exit code 0 = pass.

/// `--test-campaign-graph` — verify campaign branching: CountryArray
/// transcription (MAPSEL.CPP:76-119), the Do_Win advance sequence incl. the
/// GDI airstrip-sabotage skip (SCENARIO.CPP:472-478), and scenario-name
/// composition (INI.CPP:84-186). Pure graph/state logic — asset-free.
package func headlessTestCampaignGraphCommand() -> Int32 {
    print("test-campaign-graph: CountryArray branching + sabotage skip")

    func freshState(faction: String, mission: Int, variant: String) -> CampaignState {
        let s = CampaignState()
        s.currentFaction = faction
        s.currentMission = mission
        s.currentVariant = variant
        s.isActive = true
        return s
    }

    // (a) GDI wins 1 (East): single choice → SCG02EA.
    var s = freshState(faction: "GDI", mission: 1, variant: "EA")
    var choices = s.completeMission()
    guard choices == [CampaignChoice(dir: "E", variant: "A")] else {
        print("FAIL: GDI 1 should offer exactly [EA]"); return 1
    }
    s.advance(choosing: choices[0])
    guard s.scenarioName == "SCG02EA" else {
        print("FAIL: expected SCG02EA, got \(s.scenarioName)"); return 1
    }
    print("  linear: GDI 1 → SCG02EA")

    // (b) GDI wins 3: the 3-way fork [WA, WB, EA]; choosing WB flips West.
    s = freshState(faction: "GDI", mission: 3, variant: "EA")
    choices = s.completeMission()
    guard choices.map({ $0.suffix }) == ["WA", "WB", "EA"] else {
        print("FAIL: GDI 3 fork should be [WA, WB, EA], got \(choices.map { $0.suffix })"); return 1
    }
    s.advance(choosing: choices[1])
    guard s.scenarioName == "SCG04WB", s.dir == "W" else {
        print("FAIL: expected SCG04WB on the West path"); return 1
    }
    print("  fork: GDI 3 → [WA, WB, EA]; WB → SCG04WB")

    // (c) West path: row 4 W column keeps West [WA, WB]; row 5 funnels back
    //     East [EA, EA] → SCG06EA.
    s = freshState(faction: "GDI", mission: 4, variant: "WB")
    choices = s.completeMission()
    guard choices.map({ $0.suffix }) == ["WA", "WB"] else {
        print("FAIL: GDI 4 (dir W) should offer [WA, WB], got \(choices.map { $0.suffix })"); return 1
    }
    s = freshState(faction: "GDI", mission: 5, variant: "WA")
    choices = s.completeMission()
    guard choices.map({ $0.suffix }) == ["EA", "EA"], s.currentMission == 6 else {
        print("FAIL: GDI 5 (dir W) should funnel back East [EA, EA]"); return 1
    }
    s.advance(choosing: choices[0])
    guard s.scenarioName == "SCG06EA" else {
        print("FAIL: expected SCG06EA after the West funnel"); return 1
    }
    print("  west path: GDI 4 W → [WA, WB]; GDI 5 W → SCG06EA")

    // (d) Sabotage skip: AFLD sabotaged in GDI 6 → mission 8 via row 7's
    //     choices [EA, EB]; a non-airstrip sabotage does NOT skip and
    //     survives for the mission-7 destroyed-at-start rule; nil → 7.
    s = freshState(faction: "GDI", mission: 6, variant: "EA")
    s.sabotagedBuildingType = "AFLD"
    choices = s.completeMission()
    guard s.currentMission == 8, choices.map({ $0.suffix }) == ["EA", "EB"],
          s.sabotagedBuildingType == nil else {
        print("FAIL: airstrip sabotage should skip to mission 8 with row-7 choices"); return 1
    }
    s = freshState(faction: "GDI", mission: 6, variant: "EA")
    s.sabotagedBuildingType = "HAND"
    _ = s.completeMission()
    guard s.currentMission == 7, s.sabotagedBuildingType == "HAND" else {
        print("FAIL: non-airstrip sabotage should reach mission 7 with the type intact"); return 1
    }
    s = freshState(faction: "GDI", mission: 6, variant: "EA")
    _ = s.completeMission()
    guard s.currentMission == 7 else {
        print("FAIL: no sabotage should reach mission 7"); return 1
    }
    print("  skip: AFLD → mission 8 [EA, EB]; HAND → 7 (kept); none → 7")

    // (e) Nod wins 5: 3-way [EA, EB, EC] → SCB06EC reachable.
    s = freshState(faction: "NOD", mission: 5, variant: "EA")
    choices = s.completeMission()
    guard choices.map({ $0.suffix }) == ["EA", "EB", "EC"] else {
        print("FAIL: Nod 5 should offer [EA, EB, EC]"); return 1
    }
    s.advance(choosing: choices[2])
    guard s.scenarioName == "SCB06EC" else {
        print("FAIL: expected SCB06EC, got \(s.scenarioName)"); return 1
    }
    print("  nod: 5 → [EA, EB, EC]; EC → SCB06EC")

    // (f) Completion: GDI wins 15 / Nod wins 13 end their campaigns.
    s = freshState(faction: "GDI", mission: 15, variant: "EA")
    guard s.completeMission().isEmpty, s.isComplete, !s.isActive else {
        print("FAIL: GDI campaign should complete after mission 15"); return 1
    }
    s = freshState(faction: "NOD", mission: 13, variant: "EA")
    guard s.completeMission().isEmpty, s.isComplete else {
        print("FAIL: Nod campaign should complete after mission 13"); return 1
    }
    print("  completion: GDI 15 / Nod 13 end")

    // (g) Default rule: rows without a graph node offer a single EA.
    guard CampaignGraph.choices(faction: "NOD", wonMission: 4, dir: "W") ==
          [CampaignChoice(dir: "E", variant: "A")] else {
        print("FAIL: missing graph column should default to [EA]"); return 1
    }
    print("  default: missing node/column → [EA]")

    print("PASS: campaign graph branching + sabotage skip work")
    return 0
}

/// `--test-civ-evac` — verify the civilian-evacuation win model: a civilian
/// boarding a transport aircraft sends it off the map (AIRCRAFT.CPP:2530-2542),
/// the off-map exit sets the house `isCivEvacuated` flag without springing the
/// evacuee's Destroyed trigger (classic delete, AIRCRAFT.CPP:836-855), and the
/// Civ. Evac. trigger event wins the mission (HOUSE.CPP:1257). Also checks the
/// negative: a non-civilian boarding does NOT trigger the evacuation flight.
/// Asset-free (in-code scenario). Exit 0 = pass.
package func headlessTestCivEvacCommand() -> Int32 {
    print("test-civ-evac: civilian evacuation win model (SCG11/SCG12)")
    let ini = """
    [Basic]
    BuildLevel=1
    [GoodGuy]
    Credits=50
    [MAP]
    Theater=TEMPERATE
    X=2
    Y=2
    Width=60
    Height=60
    [Triggers]
    win=Civ. Evac.,Win,0,GoodGuy,None,0
    los1=Destroyed,Lose,0,None,None,0
    [INFANTRY]
    0=GoodGuy,MOEBIUS,256,2078,0,Guard,0,los1
    1=GoodGuy,E1,256,2079,0,Guard,0,None
    """
    let seed: UInt64 = 0xC1BE_BAC0_0DAD_FACE
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    let saved = session.rules
    session.rules = .classic1995
    defer { session.rules = saved }

    let data = parseScenarioData(INIFile(string: ini), name: "SYNTHEVAC")
    initGameWorld(scenario: data, scenarioName: "SYNTHEVAC")
    guard let world = session.world else { print("FAIL: no world"); return 1 }

    guard let moebius = world.objects.first(where: { $0.typeName == "MOEBIUS" }),
          let grunt = world.objects.first(where: { $0.typeName == "E1" }) else {
        print("FAIL: infantry not placed"); return 1
    }

    // 1. Negative first: a non-civilian boarding does NOT start the evac flight
    // Both Chinooks are parked beside the infantry: boarding only happens on
    // the ground (an airborne one is called down first).
    let apcHeli = createAircraft(world: world, type: .transport, house: .goodGuy,
                                 worldX: grunt.worldX + 18.0, worldY: grunt.worldY,
                                 facing: 0, mission: .guard_)
    apcHeli.altitude = 0
    world.addObject(apcHeli)
    grunt.enterTransportID = apcHeli.id
    grunt.mission = .enter
    grunt.tickEnterTransport()
    guard grunt.isInLimbo, apcHeli.passengers.contains(grunt.id) else {
        print("FAIL: E1 did not board the transport"); return 1
    }
    guard apcHeli.mission != .retreat else {
        print("FAIL: non-civilian boarding started an evacuation flight"); return 1
    }
    print("  board: E1 loads as a passenger; no evacuation flight for soldiers")

    // 2. The civilian boards → the transport immediately flies off the map
    let evacHeli = createAircraft(world: world, type: .transport, house: .goodGuy,
                                  worldX: moebius.worldX + 18.0, worldY: moebius.worldY,
                                  facing: 0, mission: .guard_)
    evacHeli.altitude = 0
    world.addObject(evacHeli)
    moebius.enterTransportID = evacHeli.id
    moebius.mission = .enter
    moebius.tickEnterTransport()
    guard moebius.isInLimbo, evacHeli.passengers.contains(moebius.id) else {
        print("FAIL: MOEBIUS did not board the transport"); return 1
    }
    guard evacHeli.mission == .retreat else {
        print("FAIL: civilian boarding did not start the evacuation flight "
              + "(mission=\(evacHeli.mission))"); return 1
    }
    print("  civ: MOEBIUS boards → transport assigned retreat (evacuation flight)")

    // 3. Fly out: off-map exit sets the flag, deletes without a 'kill'
    var ticks = 0
    while evacHeli.strength > 0 && ticks < 3000 {
        evacHeli.tickAircraft()  // takeoff climb, as gameTick() runs it
        evacHeli.tickAircraftRetreat()
        ticks += 1
    }
    guard evacHeli.strength <= 0 else {
        print("FAIL: transport never left the map (\(ticks) ticks)"); return 1
    }
    guard getHouseState(.goodGuy).isCivEvacuated else {
        print("FAIL: isCivEvacuated not set after off-map exit"); return 1
    }
    guard moebius.strength <= 0, moebius.triggerName == nil else {
        print("FAIL: evacuee not cleanly removed (hp=\(moebius.strength), trig=\(String(describing: moebius.triggerName)))"); return 1
    }
    print("  exit: off-map after \(ticks) ticks → isCivEvacuated set, evacuee removed as a delete")

    // 4. Trigger poll: Civ. Evac. wins — and the evacuee's Destroyed-Lose
    //    trigger must NOT have fired
    tickTriggers()
    guard session.triggerWinState == .won else {
        print("FAIL: Civ. Evac. trigger did not win (state=\(session.triggerWinState))"); return 1
    }
    print("  win: Civ. Evac. trigger fired → MISSION WON (lose trigger untouched)")

    print("PASS: civilian evacuation win model (SCG11/SCG12) works")
    return 0
}
