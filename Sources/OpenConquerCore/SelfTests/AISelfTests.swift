import Foundation
import OpenConquerAssets

// MARK: - Enemy-AI self-tests
//
// Asset-free: each builds its world in code and never loads from a MIX, so
// they run under `swift test` (Tests/OpenConquerCoreTests) as well as through
// their `--test-*` flags in the app. Exit code 0 = pass.

/// `--test-team-former` — verify the AI team-creation scoring (Gap #6):
/// Suggested_New_Team picks by RecruitPriority, skips MaxAllowed==0 (never
/// suggested) and capped types, and only considers autocreate types while
/// alerted. Asset-free, pure decide function. Exit 0 = pass.
package func headlessTestTeamFormerCommand() -> Int32 {
    print("test-team-former: Suggested_New_Team priority/cap/alerted gating (Gap #6)")
    let world = GameWorld()
    world.playerHouse = .goodGuy      // so BadGuy is the AI house under test
    session.world = world

    func makeType(_ name: String, pri: Int, max: Int, auto: Bool) -> TeamType {
        let t = TeamType(name: name, house: .badGuy)
        t.recruitPriority = pri
        t.maxAllowed = max
        t.isAutocreate = auto
        t.classSlots = [TeamClassSlot(kind: .infantry, typeName: "E1", desiredCount: 1)]
        return t
    }
    // HI pri10/max1, LO pri5/max2, ZERO pri99/max0 (never), AUTO pri20/max1 autocreate.
    session.teamTypes = [makeType("HI", pri: 10, max: 1, auto: false),
                         makeType("LO", pri: 5,  max: 2, auto: false),
                         makeType("ZERO", pri: 99, max: 0, auto: false),
                         makeType("AUTO", pri: 20, max: 1, auto: true)]
    session.activeTeams.removeAll()

    // A BadGuy E1 in the field → hasNeeded true (full, not halved, priority).
    let e1 = GameObject(id: world.allocateId(), typeName: "E1", house: .badGuy, kind: .infantry,
                        worldX: 100, worldY: 100, facing: 0, strength: 50, mission: .guard_,
                        speed: resolveSpeed(typeName: "E1", kind: .infantry))
    world.addObject(e1)

    // 1. Not alerted: HI (pri10) wins; ZERO (max0) never suggested even at pri99;
    //    AUTO excluded because the house isn't alerted.
    guard decideSuggestedTeam(house: .badGuy, world: world, alerted: false)?.name == "HI" else {
        print("FAIL: expected HI (pri10) when not alerted"); return 1
    }
    // 2. Alerted: AUTO (pri20) now participates and outscores HI.
    guard decideSuggestedTeam(house: .badGuy, world: world, alerted: true)?.name == "AUTO" else {
        print("FAIL: expected AUTO (pri20) when alerted"); return 1
    }
    print("  score: HI wins unalerted (ZERO max0 excluded); AUTO wins alerted")

    // 3. Cap: once HI is at MaxAllowed(1), LO (pri5) becomes the pick.
    session.activeTeams.append(ActiveTeam(type: session.teamTypes[0]))   // one HI active
    guard decideSuggestedTeam(house: .badGuy, world: world, alerted: false)?.name == "LO" else {
        print("FAIL: expected LO after HI hit its MaxAllowed cap"); return 1
    }
    print("  cap: HI at MaxAllowed=1 → LO is next")

    print("PASS: Suggested_New_Team priority/cap/alerted gating (Gap #6) works")
    return 0
}

/// `--test-prebuilt` — verify #6C IsPrebuilt production gating: the AI's build
/// deciders follow team-template demand (Suggest_New_Object, HOUSE.CPP:3166-
/// 3383) ahead of the personality pool. Asset-free; all assertions on the PURE
/// functions (no RNG draw), plus the satisfaction/exclusion/clamp rules.
package func headlessTestPrebuiltCommand() -> Int32 {
    print("test-prebuilt: IsPrebuilt team-demand production gating (#6C)")
    // Enhanced rules: this test exercises the demand-vs-personality-pool
    // interplay, and the pool fallback is enhanced-only (classic1995 has
    // faithful build-nothing semantics — see decideUnitBuild Priority 3 and
    // --test-ai-gating). Demand steps 1-2/4-5 behave identically either way.
    let savedRules = session.rules
    session.rules = .enhanced
    defer { session.rules = savedRules }
    let world = GameWorld()
    world.playerHouse = .goodGuy      // BadGuy is the AI house under test
    session.world = world
    session.activeTeams.removeAll()

    let state = getHouseState(.badGuy)
    state.credits = 5000

    // Factories so canBuild prerequisites pass and decideUnitBuild's WEAP gate holds.
    for (t, cell) in [("WEAP", 200), ("HAND", 202), ("PROC", 204)] {
        let o = GameObject(id: world.allocateId(), typeName: t, house: .badGuy, kind: .structure,
                           worldX: Double((cell % 64) * 24 + 12), worldY: Double((cell / 64) * 24 + 12),
                           facing: 0, strength: 400, mission: .guard_, speed: 0)
        world.addObject(o)
    }
    // A harvester so decideUnitBuild's harvester priority doesn't preempt demand.
    let harv = GameObject(id: world.allocateId(), typeName: "HARV", house: .badGuy, kind: .unit,
                          worldX: 300, worldY: 300, facing: 0, strength: 600,
                          mission: .harvest, speed: 1)
    world.addObject(harv)   // typeName HARV → isHarvester (cached)

    // Prebuilt (non-autocreate) template: 2x LTNK + 1x E3.
    let pre = TeamType(name: "PRE", house: .badGuy)
    pre.isPrebuilt = true
    pre.isAutocreate = false
    pre.classSlots = [TeamClassSlot(kind: .unit, typeName: "LTNK", desiredCount: 2),
                      TeamClassSlot(kind: .infantry, typeName: "E3", desiredCount: 1)]
    session.teamTypes = [pre]

    let owned = state.ownedBuildingTypes()

    func unitCandidates() -> [String] {
        if case .weighted(let cs) = decideUnitBuild(house: .badGuy, houseState: state,
                                                    owned: owned, costMultiplier: 1.0) {
            return cs.map { $0.name }
        }
        return []
    }
    func infantryCandidates() -> [String] {
        if case .weighted(let cs) = decideInfantryBuild(house: .badGuy, houseState: state,
                                                        owned: owned, costMultiplier: 1.0) {
            return cs.map { $0.name }
        }
        return []
    }

    // 1. Demand: the template drives the choice — exactly LTNK / exactly E3
    //    (the faction pools would offer several types).
    guard computeTeamBuildDemand(house: .badGuy, kind: .unit, world: world, alerted: false)["LTNK"] == 2 else {
        print("FAIL: expected unit demand LTNK=2 from the prebuilt template"); return 1
    }
    guard unitCandidates() == ["LTNK"] else {
        print("FAIL: expected decideUnitBuild to offer exactly [LTNK], got \(unitCandidates())"); return 1
    }
    guard infantryCandidates() == ["E3"] else {
        print("FAIL: expected decideInfantryBuild to offer exactly [E3], got \(infantryCandidates())"); return 1
    }
    print("  demand: prebuilt LTNKx2/E3 template → build LTNK / E3")

    // 2. Satisfaction: two free guard-mission LTNKs zero the demand → the AI
    //    builds NOTHING (classic Suggest_New_Object returns NULL when demand
    //    exists but nets to zero; the pool only stands in when the scenario
    //    defines no team demand at all). A .hunt LTNK doesn't count (3250).
    var ltnks: [GameObject] = []
    for i in 0..<2 {
        let u = GameObject(id: world.allocateId(), typeName: "LTNK", house: .badGuy, kind: .unit,
                           worldX: Double(400 + i * 30), worldY: 400, facing: 0, strength: 300,
                           mission: .guard_, speed: 1)
        world.addObject(u); ltnks.append(u)
    }
    guard unitCandidates().isEmpty else {
        print("FAIL: satisfied demand should build nothing (classic NULL), got \(unitCandidates())"); return 1
    }
    ltnks[0].mission = .hunt      // busy → no longer satisfies demand
    guard unitCandidates() == ["LTNK"] else {
        print("FAIL: a hunting LTNK must not satisfy demand (HOUSE.CPP:3250)"); return 1
    }
    print("  satisfaction: free LTNKs satisfy (build nothing); hunting LTNK excluded")
    ltnks[0].mission = .guard_

    // 3. Autocreate gate: an autocreate template contributes demand only when
    //    the house is alerted (HOUSE.CPP:3233). With the template gated out the
    //    demand map is EMPTY → pool fallback (multiple candidates).
    pre.isAutocreate = true
    guard unitCandidates().count > 1 else {
        print("FAIL: unalerted autocreate template should leave the pool in charge"); return 1
    }
    ltnks[0].mission = .hunt                    // make demand unsatisfied again
    state.isAlerted = true
    guard unitCandidates() == ["LTNK"] else {
        print("FAIL: alerted house should demand from autocreate template"); return 1
    }
    state.isAlerted = false
    pre.isAutocreate = false
    ltnks[0].mission = .guard_
    print("  autocreate: unalerted → pool; alerted → template demand")

    // 4. Infantry clamp: desired 9 clamps to 5 (HOUSE.CPP:3334).
    pre.classSlots = [TeamClassSlot(kind: .infantry, typeName: "E1", desiredCount: 9)]
    guard computeTeamBuildDemand(house: .badGuy, kind: .infantry, world: world, alerted: false)["E1"] == 5 else {
        print("FAIL: infantry demand should clamp at 5"); return 1
    }
    print("  clamp: E1 desired 9 → demand 5")

    // 5. End-to-end: the production path actually starts an LTNK build.
    pre.classSlots = [TeamClassSlot(kind: .unit, typeName: "LTNK", desiredCount: 2)]
    ltnks.forEach { $0.strength = 0 }           // back to unsatisfied
    if let choice = applyBuildPlan(decideUnitBuild(house: .badGuy, houseState: state,
                                                   owned: owned, costMultiplier: 1.0)) {
        guard choice.typeName == "LTNK" else {
            print("FAIL: end-to-end build pick was \(choice.typeName), expected LTNK"); return 1
        }
    } else {
        print("FAIL: end-to-end build pick returned nothing"); return 1
    }
    print("  end-to-end: applyBuildPlan starts LTNK")

    print("PASS: IsPrebuilt production gating (#6C) works")
    return 0
}

/// `--test-ai-gating` — verify the enhanced enemy-AI layer is ruleset-gated:
/// under classic1995 the AI is trigger/teamtype-driven only (no production
/// timeout, no rally raids, no escalation — HOUSE.CPP:1892 production starts
/// only via the Production trigger), while the enhanced preset keeps the
/// modern layer. Asset-free (in-code world). Exit 0 = pass.
package func headlessTestAIGatingCommand() -> Int32 {
    print("test-ai-gating: enhanced enemy-AI layer is ruleset-gated")
    let savedRules = session.rules
    defer { session.rules = savedRules }

    struct PhaseResult {
        var productionEnabled: Bool
        var produced: Int        // units built beyond the starting army
        var idleTanks: Int       // original BadGuy LTNKs still sitting on guard
    }

    // One phase = a fresh in-code world driven purely through tickAI(): a
    // GoodGuy base structure far from a BadGuy weapons factory + 4 idle LTNKs
    // (out of aggro range, below the attack-wave threshold of 6), no team
    // templates and no Production trigger. 4600 ticks covers the rally
    // interval (300), the production timeout (2700), and escalation (4500).
    func runPhase(_ rules: Ruleset) -> PhaseResult {
        session.rules = rules
        seedGameRandom(0xA1_6A71_A6_0000_0001)
        session.aiTickCounter = 0
        session.houseStates.removeAll()
        session.activeTeams.removeAll()
        session.teamTypes = []

        let world = GameWorld()
        world.playerHouse = .goodGuy
        session.world = world

        let fact = GameObject(id: world.allocateId(), typeName: "FACT", house: .goodGuy,
                              kind: .structure, worldX: 96, worldY: 96, facing: 0,
                              strength: 400, mission: .guard_, speed: 0)
        world.addObject(fact)
        let weap = GameObject(id: world.allocateId(), typeName: "WEAP", house: .badGuy,
                              kind: .structure, worldX: 1200, worldY: 1176, facing: 0,
                              strength: 400, mission: .guard_, speed: 0)
        world.addObject(weap)
        getHouseState(.badGuy).credits = 5000
        var armyIDs: Set<Int> = []
        for i in 0..<4 {
            let tank = GameObject(id: world.allocateId(), typeName: "LTNK", house: .badGuy,
                                  kind: .unit, worldX: Double(1250 + i * 30), worldY: 1250,
                                  facing: 0, strength: 300, mission: .guard_,
                                  speed: resolveSpeed(typeName: "LTNK", kind: .unit))
            world.addObject(tank)
            armyIDs.insert(tank.id)
        }

        for _ in 0..<4600 { tickAI() }

        let state = getHouseState(.badGuy)
        // Only the original army — enhanced production spawns fresh (idle) tanks.
        let idle = world.objects.filter {
            armyIDs.contains($0.id) && $0.mission == .guard_ && $0.moveTargetX == nil
        }.count
        let produced = world.objects.filter {
            $0.house == .badGuy && $0.kind == .unit && !armyIDs.contains($0.id)
        }.count
        return PhaseResult(productionEnabled: state.productionEnabled,
                           produced: produced,
                           idleTanks: idle)
    }

    // 1. classic1995: nothing moves — no Production trigger means no production
    //    (no timeout), and rally/waves/escalation never touch the idle army.
    let classic = runPhase(.classic1995)
    guard !classic.productionEnabled, classic.produced == 0 else {
        print("FAIL: classic1995 production ran without a Production trigger "
              + "(enabled=\(classic.productionEnabled) produced=\(classic.produced))"); return 1
    }
    guard classic.idleTanks == 4 else {
        print("FAIL: classic1995 moved idle units (\(4 - classic.idleTanks) of 4) "
              + "— rally/escalation not gated"); return 1
    }
    print("  classic1995: production stayed off past the timeout; 4/4 units never moved (4600 ticks)")

    // 2. enhanced: the timeout enables production (queue starts) and the rally
    //    raid pulls the idle army toward the player base.
    let enhanced = runPhase(.enhanced)
    guard enhanced.productionEnabled, enhanced.produced > 0 else {
        print("FAIL: enhanced production timeout did not build anything "
              + "(enabled=\(enhanced.productionEnabled) produced=\(enhanced.produced))"); return 1
    }
    guard enhanced.idleTanks == 0 else {
        print("FAIL: enhanced rally left \(enhanced.idleTanks) units idle"); return 1
    }
    print("  enhanced: timeout auto-enabled production (built \(enhanced.produced)); rally moved all 4 units")

    print("PASS: enhanced enemy-AI layer is ruleset-gated (classic1995 = scripted-only)")
    return 0
}

/// `--test-enemy-superweapon` — verify the enemy half of Gap #5: a trigger that
/// grants a superweapon to the ENEMY house charges and fires it at the player's
/// base (highest-value building), then the one-time weapon removes itself.
/// Asset-free. Exit 0 = pass.
package func headlessTestEnemySuperWeaponCommand() -> Int32 {
    print("test-enemy-superweapon: enemy Nuke fires at the player (Gap #5)")
    let world = GameWorld()
    world.playerHouse = .goodGuy
    session.world = world
    session.houseStates[.goodGuy] = HouseState(type: .goodGuy, credits: 0, isHuman: true)
    session.houseStates[.badGuy]  = HouseState(type: .badGuy, credits: 0, isHuman: false)

    // A player building for the enemy nuke to target.
    let hq = GameObject(id: world.allocateId(), typeName: "FACT", house: .goodGuy,
                        kind: .structure, worldX: Double(30 * 24 + 12), worldY: Double(30 * 24 + 12),
                        facing: 0, strength: 400, mission: .guard_, speed: 0)
    world.addObject(hq)
    let startHP = hq.strength

    // Grant the enemy (Nod) a nuke via the trigger action. ownerHouse is fixed to
    // .badGuy in the .nuke case, so the enemy branch of armSuperWeapon runs.
    executeTriggerAction(TriggerActionSpec(action: .nuke, teamName: nil),
                         trigger: GameTrigger(name: "T", event: .destroyed, action: .nuke,
                                              house: .badGuy, teamName: nil,
                                              persistence: .volatile, data: 0))
    let sw = getHouseState(.badGuy).superWeapons[.nuclearStrike]
    guard sw?.isPresent == true, sw?.isReady == true else {
        print("FAIL: enemy nuke not present+ready after grant"); return 1
    }
    print("  grant: enemy Nod holds a ready one-time nuke")

    // Fire it (a few ticks; fires the first tick a target exists).
    for _ in 0..<3 { tickAISuperWeapons() }
    guard hq.strength < startHP else {
        print("FAIL: enemy nuke did not damage the player building (\(hq.strength)/\(startHP))"); return 1
    }
    guard getHouseState(.badGuy).superWeapons[.nuclearStrike] == nil else {
        print("FAIL: one-time weapon was not removed after firing"); return 1
    }
    print("  fire: FACT \(startHP)→\(hq.strength); one-time weapon removed")
    print("PASS: enemy trigger-granted superweapon fires at the player (Gap #5)")
    return 0
}

/// ASSET-FREE: classic1995 target acquisition (TECHNO.CPP Evaluate_Object /
/// Threat_Range / Base_Is_Attacked, FOOT.CPP Take_Damage, INFANTRY.CPP
/// Greatest_Threat). The computer sees the player's units through shroud, a
/// hit computer unit hunts its attacker from any distance, an unarmed base
/// building calls rescuers, and a player's commando doesn't auto-fire.
package func headlessTestOriginalTargetingCommand() -> Int32 {
    print("test-original-targeting: classic target acquisition and reactions")
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
    """
    forcedGameSeed = 0x7A26_E7AC_0B5E_55ED
    defer { forcedGameSeed = nil }
    let saved = session.rules
    session.rules = .classic1995
    defer { session.rules = saved }

    let data = parseScenarioData(INIFile(string: ini), name: "SYNTHTARGET")
    initGameWorld(scenario: data, scenarioName: "SYNTHTARGET")
    guard let world = session.world else { print("FAIL: no world"); return 1 }
    world.map.fogState = Array(repeating: .unexplored, count: 4096)

    func place(_ type: String, _ kind: ObjectKind, _ house: House, _ x: Double, _ y: Double,
               _ mission: Mission = .guard_) -> GameObject {
        let o = GameObject(id: world.allocateId(), typeName: type, house: house, kind: kind,
                           worldX: x * 24 + 12, worldY: y * 24 + 12, facing: 0,
                           strength: resolveStrength(typeName: type, kind: kind, scenarioStrength: 256),
                           mission: mission, speed: resolveSpeed(typeName: type, kind: kind))
        world.addObject(o); return o
    }

    // 1. A turret fires at a shrouded player tank 5.5 cells out: past its
    //    5-cell sight, inside its 6-cell gun.
    let gun = place("GUN", .structure, .badGuy, 30, 30)
    let tank = place("MTNK", .unit, .goodGuy, 35.5, 30)
    gun.tickGuardScan()
    guard gun.attackTarget == tank.id else { print("FAIL: turret ignored a player tank in gun range"); return 1 }
    session.rules = .enhanced
    updateFog()
    gun.attackTarget = nil; gun.mission = .guard_
    gun.tickGuardScan()
    session.rules = .classic1995
    guard gun.attackTarget == nil else { print("FAIL: enhanced turret saw past its own sight"); return 1 }
    print("  turret: engages a shrouded player unit in weapon range (enhanced: sight-gated)")

    // 2. A hunter finds a player unit across the map (corner to corner).
    tank.strength = 0
    let hunter = place("E1", .infantry, .badGuy, 5, 5, .hunt)
    let far = place("E1", .infantry, .goodGuy, 55, 55)
    hunter.tickHunt()
    guard hunter.attackTarget == far.id else { print("FAIL: hunter didn't find the far player unit"); return 1 }
    print("  hunt: finds a player unit anywhere on the map")

    // 3. A guarding tank shot from 14 cells hunts the attacker.
    let ltnk = place("LTNK", .unit, .badGuy, 10, 45)
    let sniper = place("RMBO", .infantry, .goodGuy, 24, 45)
    ltnk.applyDamage(amount: 10, warhead: .sa, attackerHouse: .goodGuy, attackerId: sniper.id)
    guard ltnk.attackTarget == sniper.id, ltnk.mission == .attack, ltnk.suspendedMission == .hunt else {
        print("FAIL: hit tank didn't hunt its attacker (mission \(ltnk.mission))"); return 1
    }
    print("  damage: a hit computer unit hunts its attacker from any distance")

    // 4. Shooting an unarmed power plant sends rescuers: enough E1s
    //    (risk 10 each) to exceed twice the attacker's risk.
    let plant = place("NUKE", .structure, .badGuy, 45, 10)
    var guards: [GameObject] = []
    for i in 0..<5 { guards.append(place("E1", .infantry, .badGuy, 40 + Double(i), 14)) }
    let raider = place("E1", .infantry, .goodGuy, 47, 13)
    plant.applyDamage(amount: 10, warhead: .sa, attackerHouse: .goodGuy, attackerId: raider.id)
    let rescuers = guards.filter { $0.attackTarget == raider.id }.count
    guard rescuers == 3 else { print("FAIL: \(rescuers) rescuers answered, expected 3"); return 1 }
    guard raider.baseAttackTimerEnd > world.tickCount else { print("FAIL: base-attack timer not set"); return 1 }
    print("  base attacked: \(rescuers) rescuers sent, attacker timed out")

    // 5. The player's commando doesn't auto-fire from guard; Nod's does,
    //    but only at infantry and buildings.
    let havoc = place("RMBO", .infantry, .goodGuy, 20, 20)
    _ = place("E1", .infantry, .badGuy, 22, 20)
    havoc.tickGuardScan()
    guard havoc.attackTarget == nil else { print("FAIL: player commando auto-fired from guard"); return 1 }
    let nodCommando = place("RMBO", .infantry, .badGuy, 20, 55)
    _ = place("JEEP", .unit, .goodGuy, 22, 55)
    nodCommando.tickGuardScan()
    guard nodCommando.attackTarget == nil else { print("FAIL: commando auto-targeted a vehicle"); return 1 }
    print("  commando: player's holds fire in guard; rifle ignores vehicles")

    print("PASS: classic target acquisition matches the original")
    return 0
}
