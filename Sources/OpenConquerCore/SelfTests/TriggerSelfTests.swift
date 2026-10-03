import Foundation
import OpenConquerAssets

// MARK: - Trigger self-tests
//
// Asset-free: each builds its world in code and never loads from a MIX, so
// they run under `swift test` (Tests/OpenConquerCoreTests) as well as through
// their `--test-*` flags in the app. Exit code 0 = pass.

/// `--test-triggers-ex` — verify Tier-1 T2 (multiple actions per trigger):
/// `[TriggersEx]` `Action2..N` parse into the trigger's action list and all
/// actions run in order when it fires; a trigger with no `[TriggersEx]` row
/// stays classic (one action). Exit 0 = pass.
package func headlessTestTriggersExCommand() -> Int32 {
    print("test-triggers-ex: multiple actions per trigger")
    let iniText = """
    [Triggers]
    TR1=Time,Allow Win,1,GoodGuy,None,2
    TR2=Time,Win,1,GoodGuy,None,2

    [TriggersEx]
    TR1=Action2=Win
    """
    parseTriggers(from: INIFile(string: iniText))
    guard session.gameTriggers.count == 2 else {
        print("FAIL: expected 2 triggers, got \(session.gameTriggers.count)"); return 1
    }
    let tr1 = session.gameTriggers[0]
    let tr2 = session.gameTriggers[1]

    // 1. Parse: TR1 gains a 2nd action; classic TR2 keeps exactly one.
    guard tr1.actions.count == 2 else {
        print("FAIL: TR1 should have 2 actions, got \(tr1.actions.count)"); return 1
    }
    guard tr2.actions.count == 1 else {
        print("FAIL: TR2 (no TriggersEx) should have 1 action, got \(tr2.actions.count)"); return 1
    }
    guard tr1.actions[0].action == .allowWin, tr1.actions[1].action == .win else {
        print("FAIL: TR1 action order wrong: \(tr1.actions.map { $0.action })"); return 1
    }
    print("  parse: TR1=[allowWin, win]; TR2 (classic)=1 action")

    // 2. Execution: firing TR1 must run BOTH actions, in order.
    session.allowWinFlag = false
    session.triggerWinState = .playing
    fireTrigger(tr1)
    guard session.allowWinFlag else { print("FAIL: action 1 (allowWin) did not run"); return 1 }
    guard session.triggerWinState == .won else {
        print("FAIL: action 2 (win) did not run, state=\(session.triggerWinState)"); return 1
    }
    print("  execute: firing TR1 set allowWinFlag AND won — both actions ran")

    print("PASS: multiple actions per trigger (T2) works")
    return 0
}

/// `--test-two-event` — verify Tier-1 T3 (two-event AND/OR combining):
/// `[TriggersEx]` `Event2`/`Control` parse, an AND trigger fires only after
/// BOTH events occur, and an OR trigger fires on either. Exit 0 = pass.
package func headlessTestTwoEventCommand() -> Int32 {
    print("test-two-event: AND/OR event combining")
    let ini = """
    [Triggers]
    TAND=Time,Win,1,GoodGuy,None,2
    TOR=Time,Win,1,GoodGuy,None,2

    [TriggersEx]
    TAND=Event2=Destroyed; Control=AND
    TOR=Event2=Destroyed; Control=OR
    """
    parseTriggers(from: INIFile(string: ini))
    guard let tAnd = session.gameTriggers.first(where: { $0.name == "TAND" }),
          let tOr  = session.gameTriggers.first(where: { $0.name == "TOR" }) else {
        print("FAIL: triggers not parsed"); return 1
    }

    // 1. Parse: event2 + control landed.
    guard tAnd.event2 == .destroyed, tAnd.eventControl == .and else {
        print("FAIL: TAND event2/control = \(tAnd.event2)/\(tAnd.eventControl)"); return 1
    }
    guard tOr.eventControl == .or else { print("FAIL: TOR control = \(tOr.eventControl)"); return 1 }
    print("  parse: TAND=[control=AND, event2=destroyed]; TOR=[control=OR]")

    // 2. AND: one event alone must NOT fire; both must.
    session.triggerWinState = .playing
    registerEventSatisfied(tAnd, isEvent2: false)
    if session.triggerWinState != .playing {
        print("FAIL: AND fired on event1 alone"); return 1
    }
    registerEventSatisfied(tAnd, isEvent2: true)
    if session.triggerWinState != .won {
        print("FAIL: AND did not fire after both events (state=\(session.triggerWinState))"); return 1
    }
    print("  AND: event1 alone did not fire; both events did")

    // 3. OR: a single event fires immediately.
    session.triggerWinState = .playing
    registerEventSatisfied(tOr, isEvent2: true)
    if session.triggerWinState != .won {
        print("FAIL: OR did not fire on a single event"); return 1
    }
    print("  OR: a single event fired the trigger")

    print("PASS: two-event AND/OR combining (T3) works")
    return 0
}

/// `--test-regions` — verify Tier-1 T4 (region zones): a unit moving into a
/// `[Regions]` zone fires an Enter Region trigger, and moving out fires a Leave
/// Region trigger; a unit outside fires neither. Exit 0 = pass.
package func headlessTestRegionsCommand() -> Int32 {
    print("test-regions: enter/leave region events")
    let world = GameWorld()
    world.playerHouse = .goodGuy
    let mover = GameObject(id: world.allocateId(), typeName: "E1", house: .goodGuy,
                           kind: .infantry, worldX: 12, worldY: 12, facing: 0,
                           strength: 100, mission: .guard_, speed: 0)
    world.addObject(mover)
    session.world = world
    session.triggerWinState = .playing

    // A 2x2 rectangular region at cells (10,10)..(11,11).
    session.scenarioRegions = ["RGN": ScenarioRegion(name: "RGN", shape: .rect(x: 10, y: 10, w: 2, h: 2))]

    let tEnter = GameTrigger(name: "RENTER", event: .enteredRegion, action: .win,
                             house: .goodGuy, teamName: nil, persistence: .persistent, data: 0)
    tEnter.regionName = "RGN"
    let tLeave = GameTrigger(name: "RLEAVE", event: .leftRegion, action: .lose,
                             house: .goodGuy, teamName: nil, persistence: .persistent, data: 0)
    tLeave.regionName = "RGN"
    session.gameTriggers = [tEnter, tLeave]

    // 1. Outside the region: nothing fires.
    tickRegionTriggers()
    guard session.triggerWinState == .playing, !tEnter.regionOccupied else {
        print("FAIL: fired or primed-occupied while outside (state=\(session.triggerWinState))"); return 1
    }
    print("  outside: no fire")

    // 2. Move into the region: Enter fires (win).
    mover.worldX = Double(10 * 24) + 12; mover.worldY = Double(10 * 24) + 12
    tickRegionTriggers()
    guard session.triggerWinState == .won else {
        print("FAIL: enter did not fire (state=\(session.triggerWinState))"); return 1
    }
    print("  enter: moving in fired win")

    // 3. Move back out: Leave fires (lose).
    session.triggerWinState = .playing
    mover.worldX = 12; mover.worldY = 12
    tickRegionTriggers()
    guard session.triggerWinState == .lost else {
        print("FAIL: leave did not fire (state=\(session.triggerWinState))"); return 1
    }
    print("  leave: moving out fired lose")

    print("PASS: region enter/leave events (T4) work")
    return 0
}

/// `--test-wingate` — verify AllowWin/Blockage win-gating (Gap #3): a Win action
/// only ends the mission once every AllowWin trigger for the player has fired.
/// Mirrors the load-time `Blockage++` (TRIGGER.CPP:1078), the per-fire decrement
/// (TRIGGER.CPP:313), and the `Blockage <= 0` win gate (HOUSE.CPP:794). Exit 0 = pass.
package func headlessTestWinGateCommand() -> Int32 {
    print("test-wingate: AllowWin/Blockage gates the Win action")

    // A minimal world so parseTriggers can prime blockage against the player house.
    let world = GameWorld()
    world.playerHouse = .goodGuy
    session.world = world

    // Two separate player-house triggers: one Win, one AllowWin. One AllowWin
    // trigger ⇒ blockage should prime to 1.
    let ini = """
    [Triggers]
    TWIN=Time,Win,1,GoodGuy,None,2
    TAW=Time,Allow Win,1,GoodGuy,None,2
    """
    parseTriggers(from: INIFile(string: ini))

    guard session.winBlockage == 1 else {
        print("FAIL: expected blockage primed to 1, got \(session.winBlockage)"); return 1
    }
    guard let tWin = session.gameTriggers.first(where: { $0.name == "TWIN" }),
          let tAllow = session.gameTriggers.first(where: { $0.name == "TAW" }) else {
        print("FAIL: triggers not parsed"); return 1
    }
    print("  parse: blockage primed to 1 (one AllowWin trigger)")

    // Fire Win while still blocked — must NOT complete the mission.
    fireTrigger(tWin)
    guard session.triggerWinState == .playing else {
        print("FAIL: Win completed while blockage>0 (state=\(session.triggerWinState))"); return 1
    }
    guard session.flaggedToWin else {
        print("FAIL: Win did not flag the pending win"); return 1
    }
    print("  gate: Win fired but mission stays .playing (flagged, blockage=\(session.winBlockage))")

    // Fire AllowWin — drains the blockage, so the pending win now completes.
    fireTrigger(tAllow)
    guard session.winBlockage == 0 else {
        print("FAIL: AllowWin did not drain blockage (=\(session.winBlockage))"); return 1
    }
    guard session.triggerWinState == .won else {
        print("FAIL: win did not complete after blockage drained (state=\(session.triggerWinState))"); return 1
    }
    print("  release: AllowWin drained blockage → mission WON")

    print("PASS: AllowWin/Blockage win-gating (Gap #3) works")
    return 0
}

/// `--test-winlose` — verify the Cap=Win/Des=Lose action branches on the firing
/// event (Gap #2): a DESTROYED spring loses, a PLAYER_ENTERED (capture) spring
/// wins. Mirrors TRIGGER.CPP:427-443. Exit 0 = pass.
package func headlessTestWinLoseCommand() -> Int32 {
    print("test-winlose: Cap=Win/Des=Lose branches on the firing event")
    let ini = """
    [Triggers]
    TWL=Any,Cap=Win/Des=Lose,0,GoodGuy,None,0
    """

    // Sub-test 1: capture (PLAYER_ENTERED) → win.
    parseTriggers(from: INIFile(string: ini))
    springTrigger(named: "TWL", event: .playerEntered)
    guard session.triggerWinState == .won else {
        print("FAIL: capture (PLAYER_ENTERED) did not win (state=\(session.triggerWinState))"); return 1
    }
    print("  capture: PLAYER_ENTERED spring → MISSION WON")

    // Sub-test 2: destruction (DESTROYED) → lose. Re-parse to reset win state.
    parseTriggers(from: INIFile(string: ini))
    springTrigger(named: "TWL", event: .destroyed)
    guard session.triggerWinState == .lost else {
        print("FAIL: destruction (DESTROYED) did not lose (state=\(session.triggerWinState))"); return 1
    }
    print("  destroy: DESTROYED spring → MISSION LOST")

    print("PASS: Cap=Win/Des=Lose event branching (Gap #2) works")
    return 0
}

/// `--test-eventparity` — verify Gap #9 trigger event-detection fidelity:
/// (1) Built It fires only for the SPECIFIC target structure, (2) NoFactories
/// ignores the Construction Yard, (3) the all/units-destroyed scan excludes
/// gunboat/transport/cargo/A-10. Asset-free. Exit 0 = pass.
package func headlessTestEventParityCommand() -> Int32 {
    print("test-eventparity: Built It / NoFactories / destroyed-scan fidelity (Gap #9)")
    let world = GameWorld()
    world.playerHouse = .goodGuy
    world.tickCount = 200          // past the reinforcement-grace thresholds
    session.world = world

    func makeStruct(_ type: String, _ house: House, cell: Int) -> GameObject {
        let o = GameObject(id: world.allocateId(), typeName: type, house: house, kind: .structure,
                           worldX: Double((cell % 64) * 24 + 12), worldY: Double((cell / 64) * 24 + 12),
                           facing: 0, strength: 200, mission: .guard_, speed: 0)
        world.addObject(o); return o
    }

    // (1) Built It specific-structure. Target = barracks (PYLE); building a
    // Weapons Factory (different ordinal) must NOT fire it.
    let pyleOrd = StructType.from(iniName: "PYLE")!.rawValue
    let ini = """
    [Triggers]
    TB=Built It,Win,\(pyleOrd),GoodGuy,None,0
    """
    parseTriggers(from: INIFile(string: ini))
    springTriggerBuiltIt(structureType: "WEAP")   // wrong type
    guard session.triggerWinState == .playing else {
        print("FAIL: Built It fired on the wrong structure (WEAP)"); return 1
    }
    springTriggerBuiltIt(structureType: "PYLE")   // target type
    guard session.triggerWinState == .won else {
        print("FAIL: Built It did not fire on the target structure (PYLE)"); return 1
    }
    print("  builtit: WEAP no-op; PYLE (target) → won")

    // (2) NoFactories ignores the Construction Yard (FACT).
    let onlyConYard = makeStruct("FACT", .badGuy, cell: 100)
    guard polledEventReady(.noFactories, threshold: 0, house: .badGuy, world: world) else {
        print("FAIL: NoFactories should fire with only a con yard (FACT) present"); return 1
    }
    let weap = makeStruct("WEAP", .badGuy, cell: 102)
    guard !polledEventReady(.noFactories, threshold: 0, house: .badGuy, world: world) else {
        print("FAIL: NoFactories fired despite a real factory (WEAP)"); return 1
    }
    print("  nofactories: FACT-only fires; WEAP present does not")
    onlyConYard.strength = 0; weap.strength = 0     // clear for the next sub-test

    // (3) Destroyed-scan excludes the gunboat. A lone BOAT counts as destroyed.
    let boat = GameObject(id: world.allocateId(), typeName: "BOAT", house: .badGuy, kind: .unit,
                          worldX: 2000, worldY: 2000, facing: 0, strength: 100,
                          mission: .guard_, speed: 0)
    world.addObject(boat)
    guard polledEventReady(.unitsDestroyed, threshold: 0, house: .badGuy, world: world),
          polledEventReady(.allDestroyed, threshold: 0, house: .badGuy, world: world) else {
        print("FAIL: a lone gunboat should count as units/all destroyed (excluded)"); return 1
    }
    let mtnk = GameObject(id: world.allocateId(), typeName: "MTNK", house: .badGuy, kind: .unit,
                          worldX: 2100, worldY: 2000, facing: 0, strength: 400,
                          mission: .guard_, speed: 0)
    world.addObject(mtnk)
    guard !polledEventReady(.unitsDestroyed, threshold: 0, house: .badGuy, world: world) else {
        print("FAIL: a real unit (MTNK) should block units-destroyed"); return 1
    }
    print("  destroyed-scan: lone BOAT counts as destroyed; MTNK blocks it")

    print("PASS: trigger event-detection fidelity (Gap #9) works")
    return 0
}

/// `--test-initteams` — verify that InitNum-at-start team spawning is
/// ruleset-gated (Gap #7): the faithful `.classic1995` preset spawns zero teams
/// at scenario start (InitNum is editor-only in classic TD), while `.enhanced`
/// spawns Σ InitNum. Asset-free (in-code scenario). Exit 0 = pass.
package func headlessTestInitTeamsCommand() -> Int32 {
    print("test-initteams: InitNum-at-start spawning is ruleset-gated (Gap #7)")
    // [TeamTypes] token order (parseTeamTypes / TEAMTYPE.CPP:301-336):
    // House,RoundAbout,Learning,Suicide,Autocreate,Mercenary,RecruitPriority,
    // MaxAllowed,InitNum(=2),Fear,ClassCount(=1),MTNK:1
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
    [UNITS]
    0=GoodGuy,MTNK,256,2078,0,Guard,None
    [TeamTypes]
    ATTACK=GoodGuy,0,0,0,0,0,7,0,2,0,1,MTNK:1
    """
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }

    func initCount(_ rules: Ruleset) -> Int {
        let saved = session.rules
        session.rules = rules
        defer { session.rules = saved }
        let data = parseScenarioData(INIFile(string: ini), name: "SYNTHTEAM")
        initGameWorld(scenario: data, scenarioName: "SYNTHTEAM")
        return session.activeTeams.count
    }

    let classic = initCount(.classic1995)
    let enhanced = initCount(.enhanced)
    print("  classic1995 activeTeams=\(classic) (expect 0)")
    print("  enhanced    activeTeams=\(enhanced) (expect 2)")
    guard classic == 0 else {
        print("FAIL: classic1995 spawned \(classic) init teams (should be 0)"); return 1
    }
    guard enhanced == 2 else {
        print("FAIL: enhanced spawned \(enhanced) init teams (expected 2)"); return 1
    }
    print("PASS: InitNum-at-start spawning is ruleset-gated (Gap #7)")
    return 0
}
