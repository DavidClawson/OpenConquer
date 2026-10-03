import Foundation
import OpenConquerAssets

// MARK: - Reinforcement, transport and economy self-tests
//
// Asset-free: each builds its world in code and never loads from a MIX, so
// they run under `swift test` (Tests/OpenConquerCoreTests) as well as through
// their `--test-*` flags in the app. Exit code 0 = pass.

/// `--test-reinforcements` — verify reinforcement fidelity (REINF.CPP port):
/// house `Edge=` parsing + edge entry, force-active teams executing their
/// TeamType mission list, the transport-only loaner exemption (SCG12's evac
/// chopper survives), team-less fixed-wing hunting (A10 strikes), and limboed
/// cargo being untargetable. Asset-free (in-code scenario). Exit 0 = pass.
package func headlessTestReinforcementsCommand() -> Int32 {
    print("test-reinforcements: Edge= entry, team mission lists, loaner + limbo fidelity")
    // [TeamTypes] token order: House,RoundAbout,Learning,Suicide,Autocreate,
    // Mercenary,RecruitPriority,MaxAllowed,InitNum,Fear,ClassCount,classes...,
    // MissionCount,missions...,IsReinforcable,IsPrebuilt
    let ini = """
    [Basic]
    BuildLevel=1
    [GoodGuy]
    Credits=50
    [BadGuy]
    Edge=West
    [MAP]
    Theater=TEMPERATE
    X=2
    Y=2
    Width=60
    Height=60
    [Waypoints]
    0=2080
    [UNITS]
    0=GoodGuy,MTNK,256,2078,0,Guard,None
    [TeamTypes]
    GRND=BadGuy,0,0,0,0,0,7,0,0,0,1,MTNK:2,1,Move:0,0,1
    EVAC=GoodGuy,0,0,0,0,0,7,0,0,0,1,TRAN:1,1,Move:0,0,1
    A10S=BadGuy,0,0,0,0,0,7,0,0,0,1,A10:1,0,0,1
    """
    let seed: UInt64 = 0xF00D_FACE_BEEF_CAFE
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    let saved = session.rules
    session.rules = .classic1995
    defer { session.rules = saved }

    let data = parseScenarioData(INIFile(string: ini), name: "SYNTHREINF")
    initGameWorld(scenario: data, scenarioName: "SYNTHREINF")
    guard let world = session.world else { print("FAIL: no world"); return 1 }
    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    // 1. Edge= parsing: BadGuy overridden to West, GoodGuy defaults to North
    guard houseEdge(.badGuy) == .west, houseEdge(.goodGuy) == .north else {
        print("FAIL: Edge= parse — badGuy=\(houseEdge(.badGuy)) goodGuy=\(houseEdge(.goodGuy))"); return 1
    }
    print("  edge: BadGuy Edge=West parsed; GoodGuy defaults to North")

    // 2. Ground team enters from the house's west edge under team control
    let before = Set(world.objects.map { $0.id })
    doReinforcements(teamName: "GRND")
    let grndObjs = world.objects.filter { !before.contains($0.id) }
    guard grndObjs.count == 2 else {
        print("FAIL: GRND spawned \(grndObjs.count) objects (expected 2)"); return 1
    }
    let westCol = bounds.x - 1
    guard grndObjs.allSatisfy({ $0.cellX == westCol }) else {
        print("FAIL: GRND entered at cols \(grndObjs.map { $0.cellX }) (expected \(westCol))"); return 1
    }
    guard session.activeTeams.count == 1, let grndTeam = session.activeTeams.first,
          grndTeam.members.count == 2 else {
        print("FAIL: GRND team not created/populated (teams=\(session.activeTeams.count))"); return 1
    }
    print("  ground: 2 MTNK entered at west edge col \(westCol), teamed")

    // 3. Force-active launch: the mission list runs without full-strength wait
    grndTeam.tick()
    let wpPos = cellToPixel(2080)
    let moving = grndObjs.filter { obj in
        obj.mission == .move && abs((obj.moveTargetX ?? 0) - (Double(wpPos.px) + 12.0)) < 60
    }
    guard !moving.isEmpty else {
        print("FAIL: team mission list did not send members to waypoint 0 "
              + "(missions=\(grndObjs.map { $0.mission }))"); return 1
    }
    print("  team: force-active launch — members moving to waypoint 0 (Move:0)")

    // 4. Transport-only team: the chopper IS the reinforcement — no loaner,
    //    no scripted fly-out, driven by its own mission list
    let pendingBefore = session.pendingReinforcements.count
    let beforeEvac = Set(world.objects.map { $0.id })
    doReinforcements(teamName: "EVAC")
    guard let tran = world.objects.first(where: { !beforeEvac.contains($0.id) }),
          tran.typeName == "TRAN" else {
        print("FAIL: EVAC did not spawn a TRAN"); return 1
    }
    guard !tran.isALoaner else {
        print("FAIL: transport-only TRAN marked loaner (would be culled — SCG12 evac bug)"); return 1
    }
    guard session.pendingReinforcements.count == pendingBefore else {
        print("FAIL: transport-only TRAN got a scripted unload/fly-out delivery"); return 1
    }
    guard let evacTeam = session.activeTeams.first(where: { $0.members.contains(tran.id) }) else {
        print("FAIL: TRAN not in its team"); return 1
    }
    evacTeam.tick()
    guard tran.mission == .move, tran.moveTargetX != nil else {
        print("FAIL: EVAC team did not send TRAN to its waypoint (mission=\(tran.mission))"); return 1
    }
    print("  evac: transport-only TRAN kept (not loaner), following its Move:0 mission")

    // 5. Team-less fixed-wing strike: A10 hunts (REINF.CPP:366-368) as a loaner
    let beforeA10 = Set(world.objects.map { $0.id })
    doReinforcements(teamName: "A10S")
    guard let a10 = world.objects.first(where: { !beforeA10.contains($0.id) }),
          a10.typeName == "A10" else {
        print("FAIL: A10S did not spawn an A10"); return 1
    }
    guard a10.mission == .hunt, a10.isALoaner else {
        print("FAIL: team-less A10 mission=\(a10.mission) loaner=\(a10.isALoaner) "
              + "(expected hunt + loaner)"); return 1
    }
    print("  a10: team-less fixed-wing enters hunting, always a loaner")

    // 6. Limboed cargo is untargetable and takes no splash
    guard let playerTank = world.objects.first(where: { $0.typeName == "MTNK" && $0.house == .goodGuy }) else {
        print("FAIL: no player MTNK"); return 1
    }
    let lurker = GameObject(
        id: world.allocateId(), typeName: "E1", house: .badGuy, kind: .infantry,
        worldX: playerTank.worldX + 24.0, worldY: playerTank.worldY,
        facing: 0, strength: 50, mission: .guard_, speed: 1.0)
    lurker.isInLimbo = true
    world.addObject(lurker)
    if let hit = findNearestEnemy(playerTank, range: 100, requireVisibility: false), hit.id == lurker.id {
        print("FAIL: limboed object acquired as a target"); return 1
    }
    let hpBefore = lurker.strength
    applySplashDamage(at: lurker.worldX, worldY: lurker.worldY, warhead: .he,
                      baseDamage: 100, attackerHouse: .goodGuy)
    guard lurker.strength == hpBefore else {
        print("FAIL: limboed object took splash damage"); return 1
    }
    lurker.isInLimbo = false
    guard findNearestEnemy(playerTank, range: 100, requireVisibility: false)?.id == lurker.id else {
        print("FAIL: unlimboed object not reacquired"); return 1
    }
    print("  limbo: in-transit cargo untargetable + splash-immune; targetable once unloaded")

    print("PASS: reinforcement fidelity (Edge=, team missions, loaners, limbo)")
    return 0
}

/// ASSET-FREE: Chinook move/land/unload fidelity (AIRCRAFT.CPP Mission_Move,
/// Process_Fly_To, Mission_Unload). A parked Chinook ordered to move lifts off,
/// flies at no more than its max speed (aircraft used to step twice a tick),
/// eases into the LZ, and lands there; a loaded one ordered to unload while
/// airborne sets down before anyone gets out.
package func headlessTestHeliTransportCommand() -> Int32 {
    print("test-heli-transport: Chinook takeoff / fly / land / unload")
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
    [INFANTRY]
    0=GoodGuy,E1,256,1300,0,Guard,0,None
    """
    forcedGameSeed = 0x4E11_C0B7_E2A1_5EED
    defer { forcedGameSeed = nil }
    let saved = session.rules
    session.rules = .classic1995
    defer { session.rules = saved }

    let data = parseScenarioData(INIFile(string: ini), name: "SYNTHHELI")
    initGameWorld(scenario: data, scenarioName: "SYNTHHELI")
    guard let world = session.world else { print("FAIL: no world"); return 1 }

    // 1. Parked Chinook ordered 10 cells east
    let heli = createAircraft(world: world, type: .transport, house: .goodGuy,
                              worldX: 20 * 24 + 12, worldY: 20 * 24 + 12, facing: 64)
    heli.altitude = 0
    world.addObject(heli)
    let targetX = heli.worldX + 240, targetY = heli.worldY
    heli.moveTargetX = targetX
    heli.moveTargetY = targetY
    heli.mission = .move

    var reachedFlightLevel = false
    var maxStep = 0.0, lastStep = 0.0
    var ticks = 0
    while ticks < 400 {
        let (px, py) = (heli.worldX, heli.worldY)
        gameTick()
        ticks += 1
        let step = hypot(heli.worldX - px, heli.worldY - py)
        if step > 0 { maxStep = max(maxStep, step); lastStep = step }
        if heli.altitude == flightLevel { reachedFlightLevel = true }
        if heli.mission == .guard_ && heli.altitude == 0 && reachedFlightLevel { break }
    }
    guard reachedFlightLevel else { print("FAIL: parked Chinook never took off"); return 1 }
    guard maxStep <= heli.speed + 0.001 else {
        print("FAIL: flew \(maxStep)px in one tick (max speed \(heli.speed)) — double-stepping"); return 1
    }
    guard lastStep < heli.speed * 0.5 else {
        print("FAIL: no slowdown into the LZ (last step \(lastStep)px)"); return 1
    }
    guard abs(heli.worldX - targetX) < 0.01, abs(heli.worldY - targetY) < 0.01 else {
        print("FAIL: ended at (\(heli.worldX), \(heli.worldY)), not the LZ"); return 1
    }
    guard heli.altitude == 0, heli.mission == .guard_ else {
        print("FAIL: didn't land (altitude \(heli.altitude), mission \(heli.mission))"); return 1
    }
    print("  move: took off, max \(String(format: "%.2f", maxStep))px/tick, eased in, landed at the LZ (\(ticks) ticks)")

    // 2. Airborne + loaded, ordered to unload → lands first, then unloads
    guard let grunt = world.objects.first(where: { $0.typeName == "E1" }) else {
        print("FAIL: E1 not placed"); return 1
    }
    let carrier = createAircraft(world: world, type: .transport, house: .goodGuy,
                                 worldX: grunt.worldX, worldY: grunt.worldY, facing: 0)
    world.addObject(carrier)
    carrier.loadPassenger(grunt)
    carrier.mission = .unload
    var unloadedAtAltitude: Int? = nil
    for _ in 0..<200 {
        gameTick()
        if !grunt.isInLimbo && unloadedAtAltitude == nil { unloadedAtAltitude = carrier.altitude }
        if !carrier.hasCargo { break }
    }
    guard let alt = unloadedAtAltitude else { print("FAIL: passenger never unloaded"); return 1 }
    guard alt == 0 else { print("FAIL: unloaded at altitude \(alt) — must land first"); return 1 }
    print("  unload: landed, then the passenger got out")

    print("PASS: Chinook takes off, flies at max speed, eases in, lands, and unloads on the ground")
    return 0
}

/// `--test-harvester-economy` — verify the player's stored tiberium frees up as
/// they spend, so harvesting resumes after silos fill (the "silos full forever"
/// regression). Exit 0 = pass.
package func headlessTestHarvesterEconomyCommand() -> Int32 {
    print("test-harvester-economy: spending frees silo capacity")
    let world = GameWorld()
    world.playerHouse = .goodGuy
    session.world = world

    // One refinery's worth of capacity (1000), storage full.
    let hs = HouseState(type: .goodGuy, credits: 1000, isHuman: true)
    hs.capacity = 1000
    hs.tiberium = 1000           // silos full
    session.houseStates[.goodGuy] = hs
    session.sidebarCredits = 1000

    let harv = GameObject(id: world.allocateId(), typeName: "HARV", house: .goodGuy,
                          kind: .unit, worldX: 12, worldY: 12, facing: 0,
                          strength: 200, mission: .harvest, speed: 0)
    world.addObject(harv)

    // 1. Full storage: a deposit is wasted (no credit gain).
    let c0 = session.sidebarCredits
    harv.depositTiberium(load: 1)
    if session.sidebarCredits != c0 {
        print("FAIL: deposit credited while silos full (\(c0) -> \(session.sidebarCredits))"); return 1
    }
    print("  full: deposit wasted, credits stay \(c0)")

    // 2. Player spends via the sidebar (does NOT touch tiberium directly).
    session.sidebarCredits = 400
    // 3. The per-tick sync must clamp stored tiberium down to actual credits.
    syncPlayerCredits()
    if hs.tiberium != 400 {
        print("FAIL: tiberium not freed after spend (tib=\(hs.tiberium), credits=\(hs.credits))"); return 1
    }
    print("  spend: credits 1000->400, stored tiberium clamped 1000->\(hs.tiberium)")

    // 4. Harvesting now credits again (capacity freed).
    let c1 = session.sidebarCredits
    harv.depositTiberium(load: 1)
    if session.sidebarCredits <= c1 {
        print("FAIL: harvest still wasted after spending down (\(c1) -> \(session.sidebarCredits))"); return 1
    }
    print("  replenish: deposit credited \(c1) -> \(session.sidebarCredits)")

    print("PASS: harvester economy recovers after spending (silos no longer stuck)")
    return 0
}
