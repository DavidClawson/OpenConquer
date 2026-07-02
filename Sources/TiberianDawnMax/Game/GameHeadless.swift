import Foundation

// MARK: - Headless simulation harness
//
// Runs the game simulation with no SDL window, rendering, or audio. This is the
// safety net for refactoring the AI and the pathfinding/land-type system: it
// lets us run N ticks of a scenario and compare a digest of the resulting world
// state, so a regression shows up as a changed digest instead of requiring a
// human to watch the game.
//
// Audio is safe to leave uninitialized — AudioManager.playSoundEffect() guards
// on `isInitialized`, so every sound call no-ops here. Rendering is simply never
// invoked.
//
// CLI entry points (dispatched from main.swift before SDL init):
//   --headless <SCEN> <ticks> [seed]   run and print a state digest
//   --determinism <SCEN> <ticks>       run twice, assert identical digests

/// Stable FNV-1a digest of the simulation state. Sorted by object id and house
/// name so the result is independent of collection iteration order. Includes the
/// RNG stream position so any divergence in random consumption is caught too.
func headlessWorldDigest() -> UInt64 {
    var h: UInt64 = 0xCBF29CE484222325
    func mix(_ v: UInt64) { h ^= v; h = h &* 0x100000001B3 }
    func mixInt(_ i: Int) { mix(UInt64(bitPattern: Int64(i))) }
    func mixStr(_ s: String) { for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001B3 } }

    guard let world = session.world else { return h }
    mixInt(world.tickCount)

    for obj in world.objects.sorted(by: { $0.id < $1.id }) {
        mixInt(obj.id)
        mixStr(obj.typeName)
        mixStr(String(describing: obj.house))
        mixStr(String(describing: obj.mission))
        mixInt(obj.strength)
        mix(obj.worldX.bitPattern)
        mix(obj.worldY.bitPattern)
        mixInt(obj.facing)
        mixInt(obj.tiberiumLoad)
    }

    for (house, state) in session.houseStates.sorted(by: { String(describing: $0.key) < String(describing: $1.key) }) {
        mixStr(String(describing: house))
        mixInt(state.credits)
        mixInt(state.tiberium)
    }

    mix(gameRng.state)
    return h
}

/// One-line human-readable summary of the current world.
func headlessWorldSummary() -> String {
    guard let world = session.world else { return "(no world)" }
    let byKind = Dictionary(grouping: world.objects, by: { $0.kind })
        .map { "\($0.key)=\($0.value.count)" }
        .sorted()
        .joined(separator: " ")
    let credits = session.houseStates
        .sorted(by: { String(describing: $0.key) < String(describing: $1.key) })
        .map { "\($0.key):\($0.value.credits)" }
        .joined(separator: " ")
    return "tick=\(world.tickCount) objects=\(world.objects.count) [\(byKind)] credits[\(credits)]"
}

/// Load a scenario and run `ticks` simulation steps. Returns the state digest,
/// or nil if the scenario could not be loaded.
@discardableResult
func runHeadless(scenario: String, ticks: Int, seed: UInt64?) -> UInt64? {
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }

    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("headless: could not load scenario '\(scenario)'")
        return nil
    }
    initGameWorld(scenario: data, scenarioName: scenario)

    for _ in 0..<ticks { gameTick() }
    return headlessWorldDigest()
}

/// `--headless <SCEN> <ticks> [seed]` — run once and print a digest + summary.
func headlessRunCommand(scenario: String, ticks: Int, seed: UInt64?) -> Int32 {
    print("headless: scenario=\(scenario) ticks=\(ticks) seed=\(seed.map(String.init) ?? "(scenario-derived)")")
    guard let digest = runHeadless(scenario: scenario, ticks: ticks, seed: seed) else {
        return 1
    }
    print(headlessWorldSummary())
    print(String(format: "digest=0x%016llX", digest))
    return 0
}

/// `--determinism <SCEN> <ticks>` — verify the simulation is reproducible.
///
/// Each trial runs in a *fresh subprocess* (re-exec of this binary with
/// --headless and a fixed seed). Subprocesses are used deliberately: a number of
/// globals (session sub-state, render/audio caches, the event bus) are not fully
/// reset by initGameWorld, so two runs in one process can contaminate each other
/// — that's a separate latent bug (it also affects campaign mission-to-mission
/// transitions; see docs/IMPROVEMENT_PLAN.md). A clean process per trial tests
/// the property we actually care about: same seed + same inputs -> same result.
///
/// Exit code 0 = deterministic, 1 = divergence/failure.
func headlessDeterminismCommand(scenario: String, ticks: Int) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    let trials = 3
    print("determinism: scenario=\(scenario) ticks=\(ticks) seed=0x\(String(seed, radix: 16)) trials=\(trials)")

    var digests: [String] = []
    for i in 0..<trials {
        guard let out = runHeadlessSubprocess(scenario: scenario, ticks: ticks, seed: seed) else {
            print("FAIL: trial \(i) subprocess failed to run")
            return 1
        }
        guard let digest = parseDigest(out) else {
            print("FAIL: trial \(i) produced no digest")
            return 1
        }
        print("  trial \(i): \(digest)")
        digests.append(digest)
    }

    if Set(digests).count == 1 {
        print("PASS: simulation is deterministic over \(ticks) ticks (\(trials) trials)")
        return 0
    } else {
        print("FAIL: digests diverged — simulation is NOT deterministic")
        return 1
    }
}

/// `--reset-check <SCEN> <ticks>` — run the same scenario+seed twice *in one
/// process* and verify identical digests. Unlike --determinism (separate
/// processes), this specifically guards "world reset hygiene": that
/// initGameWorld fully clears persistent session sub-state between worlds, so a
/// new mission doesn't inherit the previous one's projectiles/AI-phase/queues
/// (F1). Exit code 0 = clean reset, 1 = state leaked between worlds.
func headlessResetCheckCommand(scenario: String, ticks: Int) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("reset-check: scenario=\(scenario) ticks=\(ticks) (two in-process worlds)")
    guard let a = runHeadless(scenario: scenario, ticks: ticks, seed: seed) else { return 1 }
    guard let b = runHeadless(scenario: scenario, ticks: ticks, seed: seed) else { return 1 }
    print(String(format: "  world A digest=0x%016llX", a))
    print(String(format: "  world B digest=0x%016llX", b))
    if a == b {
        print("PASS: session state is fully reset between worlds")
        return 0
    } else {
        print("FAIL: in-process worlds diverged — session state leaked across initGameWorld")
        return 1
    }
}

/// A tiny, fully in-code scenario used by `--test-synthetic`. It references only
/// the hard-coded stat tables (MTNK/HARV/E1) and plain tiberium overlays, so it
/// loads and ticks with ZERO game assets — the whole point is a determinism net
/// that can run in CI. GDI and Nod units sit next to each other on Hunt so they
/// engage (movement + combat + RNG), and a harvester works a small tiberium
/// field (economy). No MIX/SHP lookups are reached by any of this.
private let syntheticScenarioINI = """
[Basic]
BuildLevel=1

[GoodGuy]
Credits=50

[BadGuy]
Credits=50

[MAP]
Theater=TEMPERATE
X=2
Y=2
Width=60
Height=60

[OVERLAY]
1946=TI1
1947=TI1
2010=TI1
2011=TI1

[UNITS]
0=GoodGuy,MTNK,256,2078,0,Hunt,None
1=BadGuy,MTNK,256,2084,128,Hunt,None
2=GoodGuy,HARV,256,1948,0,Harvest,None

[INFANTRY]
0=GoodGuy,E1,256,2079,0,Hunt,0,None
1=BadGuy,E1,256,2083,0,Hunt,0,None
"""

/// `--test-synthetic [ticks]` — full-tick determinism check with NO game assets.
///
/// Fabricates a small scenario in code (`syntheticScenarioINI`), then runs it
/// twice in one process with the same forced seed and asserts identical digests.
/// Because the scenario is built from an in-code INI string (not loaded from a
/// MIX), this is the one determinism test that runs in CI. As with `--reset-check`
/// this leans on `initGameWorld` fully resetting session sub-state between runs.
///
/// It deliberately asserts EQUALITY between the two in-process runs rather than
/// comparing to a pinned hex digest: the digest hashes `Double.bitPattern`s and
/// can legitimately differ across the Swift 5.10 / 6.x CI matrix, so a pinned
/// constant would be brittle. Exit code 0 = deterministic, 1 = diverged.
func headlessTestSyntheticCommand(ticks: Int) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("test-synthetic: in-code asset-free scenario, ticks=\(ticks) (two in-process runs)")

    func run() -> UInt64 {
        forcedGameSeed = seed
        defer { forcedGameSeed = nil }
        let data = parseScenarioData(INIFile(string: syntheticScenarioINI), name: "SYNTH")
        initGameWorld(scenario: data, scenarioName: "SYNTH")
        for _ in 0..<ticks { gameTick() }
        return headlessWorldDigest()
    }

    let a = run()
    let b = run()
    print(headlessWorldSummary())
    print(String(format: "  run A digest=0x%016llX", a))
    print(String(format: "  run B digest=0x%016llX", b))

    guard let world = session.world, !world.objects.isEmpty else {
        print("FAIL: synthetic world spawned no objects — scenario/stat tables broken")
        return 1
    }
    if a == b {
        print("PASS: synthetic scenario is deterministic (asset-free)")
        return 0
    } else {
        print("FAIL: synthetic runs diverged — nondeterminism in the sim")
        return 1
    }
}

/// `--ai-parity <SCEN> <ticks>` — prove the B3 `decide` phase is PURE.
///
/// Runs the scenario and, at every decide tick (`% 30`), snapshots the world
/// digest and the global RNG state, calls `decide(...)` for every AI house, then
/// asserts neither changed. `decide` must read-only-derive its output; if a
/// migrated seam accidentally mutates the world or advances `gameRng` inside
/// decide, this fails loudly at the first offending `(house, tick)`. As seams
/// migrate (B3-P2+), this also gains the procedural-vs-decide order-set compare.
/// Exit code 0 = pure, 1 = impurity detected.
func headlessAIParityCommand(scenario: String, ticks: Int) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("ai-parity: scenario=\(scenario) ticks=\(ticks) (decide() purity check)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("ai-parity: could not load scenario '\(scenario)'")
        return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }

    var checks = 0
    for t in 0..<ticks {
        gameTick()
        // Mirror tickAI's decide cadence so we probe when the layer would run.
        if (t + 1) % 30 != 0 { continue }
        let houses = session.houseStates.keys.sorted { $0.rawValue < $1.rawValue }
        for house in houses where isAIHouse(house, world) {
            let state = session.houseStates[house]!
            let beforeRng = gameRng.state
            let beforeDigest = headlessWorldDigest()
            let seed = deriveDecideSeed(world.randomSeed, house, world.tickCount)
            _ = decide(world: world, house: house, state: state,
                       brain: state.aiBrain, seed: seed, tick: world.tickCount)
            checks += 1
            if gameRng.state != beforeRng {
                print("FAIL: decide() advanced gameRng at tick=\(world.tickCount) house=\(house)")
                return 1
            }
            if headlessWorldDigest() != beforeDigest {
                print("FAIL: decide() mutated world state at tick=\(world.tickCount) house=\(house)")
                return 1
            }
        }
    }
    print("PASS: decide() is pure over \(checks) (house,tick) probes")
    return 0
}

/// `--ai-trace <SCEN> <ticks>` — print the goal-layer decision stream.
///
/// At every decide tick, prints one line per AI house:
///   `tick | house | goals=N | top=<goal>:<score> | decisions=M`
/// Deterministic; localizes divergence far better than an end-state digest and
/// is the data the B4 "why" panel will consume. Until the goal-scoring layer is
/// populated, the brain has no goals and `decide` returns nothing, so lines read
/// `goals=0 ... decisions=0` — this exercises the reserved seam. Always exits 0.
func headlessAITraceCommand(scenario: String, ticks: Int) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("ai-trace: scenario=\(scenario) ticks=\(ticks)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("ai-trace: could not load scenario '\(scenario)'")
        return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }

    print("tick | house | goals | top | decisions")
    for t in 0..<ticks {
        gameTick()
        if (t + 1) % 30 != 0 { continue }
        let houses = session.houseStates.keys.sorted { $0.rawValue < $1.rawValue }
        for house in houses where isAIHouse(house, world) {
            let state = session.houseStates[house]!
            let s = deriveDecideSeed(world.randomSeed, house, world.tickCount)
            let decisions = decide(world: world, house: house, state: state,
                                   brain: state.aiBrain, seed: s, tick: world.tickCount)
            let top = state.aiBrain.goals.max(by: { $0.score < $1.score })
            let topDesc = top.map { "\($0.goal):\(String(format: "%.2f", $0.score))" } ?? "-"
            print("\(world.tickCount) | \(house) | \(state.aiBrain.goals.count) | \(topDesc) | \(decisions.count)")
        }
    }
    return 0
}

/// `--test-flags <SCEN>` — verify the Tier-1 per-instance object flags work:
/// an invulnerable object takes no damage, and killing a must-survive object
/// loses the mission. Exit 0 = pass, 1 = fail.
func headlessTestFlagsCommand(scenario: String) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("test-flags: scenario=\(scenario)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("test-flags: could not load scenario '\(scenario)'"); return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }

    // 1. Invulnerability: an invulnerable object takes no damage.
    guard let victim = world.objects.first(where: { $0.strength > 0 }) else {
        print("FAIL: no live object to test"); return 1
    }
    victim.isInvulnerable = true
    let before = victim.strength
    let killed = victim.applyDamage(amount: 99999)
    if killed || victim.strength != before {
        print("FAIL: invulnerable \(victim.typeName) took damage (\(before)->\(victim.strength), killed=\(killed))")
        return 1
    }
    print("  invulnerable: \(victim.typeName) unchanged at \(before) hp under 99999 damage")

    // 2. Must-survive: killing a must-survive object loses the mission.
    guard let vip = world.objects.first(where: { $0.strength > 0 && $0.id != victim.id }) else {
        print("FAIL: no second live object for must-survive test"); return 1
    }
    vip.mustSurvive = true
    vip.strength = 0          // simulate death
    gameTick()               // removal loop runs the must-survive check
    if session.triggerWinState != .lost {
        print("FAIL: must-survive \(vip.typeName) died but win state = \(session.triggerWinState)")
        return 1
    }
    print("  must-survive: killing \(vip.typeName) set win state to .lost")

    print("PASS: per-instance flags (invulnerable, must-survive) work")
    return 0
}

/// `--editor-roundtrip <SCEN>` — verify the editor's load → document → INI →
/// re-parse cycle is faithful: the re-parsed typed model must equal the
/// original, and serializing twice must be byte-identical (idempotent). This is
/// the E1 foundation gate — it proves the section writers are exact inverses of
/// the loader and that pass-through sections survive untouched. Exit 0 = pass.
func headlessEditorRoundtripCommand(scenario: String) -> Int32 {
    print("editor-roundtrip: scenario=\(scenario)")
    guard let data1 = loadScenario("\(scenario).INI", from: mixManager) else {
        print("editor-roundtrip: could not load scenario '\(scenario)'"); return 1
    }

    let editor1 = EditorScenario(name: scenario, data: data1)
    let text1 = editor1.serialize()
    let data2 = parseScenarioData(INIFile(string: text1), name: scenario)

    // 1. Semantic round-trip: every typed entity list must match.
    var failures: [String] = []
    func check<T: Equatable>(_ label: String, _ a: [T], _ b: [T]) {
        if a.count != b.count {
            failures.append("\(label): count \(a.count) != \(b.count)")
        } else if a != b {
            let idx = (0..<a.count).first(where: { a[$0] != b[$0] }).map(String.init) ?? "?"
            failures.append("\(label): differs at index \(idx)")
        }
    }
    check("structures", data1.structures, data2.structures)
    check("units",      data1.units,      data2.units)
    check("infantry",   data1.infantry,   data2.infantry)
    check("overlays",   data1.overlays,   data2.overlays)
    check("terrain",    data1.terrain,    data2.terrain)
    check("waypoints",  data1.waypoints,  data2.waypoints)
    check("cellTriggers", data1.cellTriggers, data2.cellTriggers)
    check("baseBuildings", data1.baseBuildings, data2.baseBuildings)
    if data1.theater != data2.theater { failures.append("theater: \(data1.theater) != \(data2.theater)") }
    if data1.mapBounds != data2.mapBounds { failures.append("mapBounds differs") }
    if data1.credits != data2.credits { failures.append("credits: \(data1.credits) != \(data2.credits)") }
    if data1.buildLevel != data2.buildLevel { failures.append("buildLevel: \(data1.buildLevel) != \(data2.buildLevel)") }

    // 2. Idempotence: serializing the re-parsed document must reproduce text1.
    let text2 = EditorScenario(name: scenario, data: data2).serialize()
    if text1 != text2 { failures.append("not idempotent: serialize() changed on second pass") }

    print("  structures=\(data1.structures.count) units=\(data1.units.count) infantry=\(data1.infantry.count) overlays=\(data1.overlays.count) terrain=\(data1.terrain.count) waypoints=\(data1.waypoints.count) cellTriggers=\(data1.cellTriggers.count) base=\(data1.baseBuildings.count)")

    // 3. Edit → save → reload: a programmatic edit must survive the cycle, and
    //    only the edited entity must change. Move the first unit (or infantry)
    //    to a new cell and confirm it round-trips.
    if let u0 = data1.units.first {
        let editor = EditorScenario(name: scenario, data: data1)
        let newCell = u0.cell + 1
        editor.data.units[0] = ScenarioUnit(
            house: u0.house, typeName: u0.typeName, strength: u0.strength,
            cell: newCell, facing: u0.facing, mission: u0.mission, trigger: u0.trigger)
        let edited = parseScenarioData(INIFile(string: editor.serialize()), name: scenario)
        if edited.units.count != data1.units.count {
            failures.append("edit: unit count changed (\(data1.units.count) -> \(edited.units.count))")
        } else if edited.units[0].cell != newCell {
            failures.append("edit: moved unit cell not persisted (want \(newCell), got \(edited.units[0].cell))")
        } else if edited.structures != data1.structures || edited.infantry != data1.infantry {
            failures.append("edit: a non-edited section changed")
        } else {
            print("  edit: moved unit[0] \(u0.typeName) cell \(u0.cell)->\(newCell), persisted; other sections intact")
        }
    }

    if failures.isEmpty {
        print("PASS: editor round-trip is faithful, idempotent, and edit-safe")
        return 0
    }
    for f in failures { print("FAIL: \(f)") }
    return 1
}

/// `--test-triggers-ex` — verify Tier-1 T2 (multiple actions per trigger):
/// `[TriggersEx]` `Action2..N` parse into the trigger's action list and all
/// actions run in order when it fires; a trigger with no `[TriggersEx]` row
/// stays classic (one action). Exit 0 = pass.
func headlessTestTriggersExCommand() -> Int32 {
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

/// `--test-wingate` — verify AllowWin/Blockage win-gating (Gap #3): a Win action
/// only ends the mission once every AllowWin trigger for the player has fired.
/// Mirrors the load-time `Blockage++` (TRIGGER.CPP:1078), the per-fire decrement
/// (TRIGGER.CPP:313), and the `Blockage <= 0` win gate (HOUSE.CPP:794). Exit 0 = pass.
func headlessTestWinGateCommand() -> Int32 {
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

/// `--test-team-former` — verify the AI team-creation scoring (Gap #6):
/// Suggested_New_Team picks by RecruitPriority, skips MaxAllowed==0 (never
/// suggested) and capped types, and only considers autocreate types while
/// alerted. Asset-free, pure decide function. Exit 0 = pass.
func headlessTestTeamFormerCommand() -> Int32 {
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
func headlessTestPrebuiltCommand() -> Int32 {
    print("test-prebuilt: IsPrebuilt team-demand production gating (#6C)")
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

/// `--test-campaign-graph` — verify campaign branching: CountryArray
/// transcription (MAPSEL.CPP:76-119), the Do_Win advance sequence incl. the
/// GDI airstrip-sabotage skip (SCENARIO.CPP:472-478), and scenario-name
/// composition (INI.CPP:84-186). Pure graph/state logic — asset-free.
func headlessTestCampaignGraphCommand() -> Int32 {
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

/// `--test-eventparity` — verify Gap #9 trigger event-detection fidelity:
/// (1) Built It fires only for the SPECIFIC target structure, (2) NoFactories
/// ignores the Construction Yard, (3) the all/units-destroyed scan excludes
/// gunboat/transport/cargo/A-10. Asset-free. Exit 0 = pass.
func headlessTestEventParityCommand() -> Int32 {
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

/// `--test-enemy-superweapon` — verify the enemy half of Gap #5: a trigger that
/// grants a superweapon to the ENEMY house charges and fires it at the player's
/// base (highest-value building), then the one-time weapon removes itself.
/// Asset-free. Exit 0 = pass.
func headlessTestEnemySuperWeaponCommand() -> Int32 {
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

/// `--test-initteams` — verify that InitNum-at-start team spawning is
/// ruleset-gated (Gap #7): the faithful `.classic1995` preset spawns zero teams
/// at scenario start (InitNum is editor-only in classic TD), while `.enhanced`
/// spawns Σ InitNum. Asset-free (in-code scenario). Exit 0 = pass.
func headlessTestInitTeamsCommand() -> Int32 {
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

/// `--test-winlose` — verify the Cap=Win/Des=Lose action branches on the firing
/// event (Gap #2): a DESTROYED spring loses, a PLAYER_ENTERED (capture) spring
/// wins. Mirrors TRIGGER.CPP:427-443. Exit 0 = pass.
func headlessTestWinLoseCommand() -> Int32 {
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

/// `--test-two-event` — verify Tier-1 T3 (two-event AND/OR combining):
/// `[TriggersEx]` `Event2`/`Control` parse, an AND trigger fires only after
/// BOTH events occur, and an OR trigger fires on either. Exit 0 = pass.
func headlessTestTwoEventCommand() -> Int32 {
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
func headlessTestRegionsCommand() -> Int32 {
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

/// `--test-harvester-economy` — verify the player's stored tiberium frees up as
/// they spend, so harvesting resumes after silos fill (the "silos full forever"
/// regression). Exit 0 = pass.
func headlessTestHarvesterEconomyCommand() -> Int32 {
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

/// `--test-repair <SCEN>` — verify a player-ordered vehicle actually drives to a
/// repair bay (FIX) and heals. Reproduces the "tank never went onto the pad"
/// report. Exit 0 = pass.
func headlessTestRepairCommand(scenario: String) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("test-repair: scenario=\(scenario)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("test-repair: could not load scenario '\(scenario)'"); return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }

    // Find an open spot: a 3x3 FIX footprint centered at (cx,cy), a passable
    // dock cell 2 south, and a tank spawn 4 south — all land-passable.
    func open(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && x < 64 && y >= 0 && y < 64 && landPassability[y * 64 + x]
    }
    var site: (cx: Int, cy: Int)? = nil
    searchLoop: for cy in 1..<60 {
        for cx in 1..<62 {
            var ok = true
            for dy in -1...1 { for dx in -1...1 where !open(cx + dx, cy + dy) { ok = false } }
            if ok && open(cx, cy + 2) && open(cx, cy + 4) { site = (cx, cy); break searchLoop }
        }
    }
    guard let s = site else { print("FAIL: no open site for FIX"); return 1 }

    // Mark the FIX footprint impassable (as a real placed building would).
    for dy in -1...1 { for dx in -1...1 { landPassability[(s.cy + dy) * 64 + (s.cx + dx)] = false } }

    let fix = GameObject(id: world.allocateId(), typeName: "FIX", house: world.playerHouse,
                         kind: .structure, worldX: Double(s.cx * 24 + 12), worldY: Double(s.cy * 24 + 12),
                         facing: 0, strength: 400, mission: .guard_, speed: 0)
    world.addObject(fix)

    let tank = GameObject(id: world.allocateId(), typeName: "MTNK", house: world.playerHouse,
                          kind: .unit, worldX: Double(s.cx * 24 + 12), worldY: Double((s.cy + 4) * 24 + 12),
                          facing: 0, strength: 100, mission: .guard_,
                          speed: resolveSpeed(typeName: "MTNK", kind: .unit))
    world.addObject(tank)
    // Isolate the repair mechanic: this scenario has live Nod units that would
    // otherwise shoot the tank while it sits at the bay. We only care that it
    // drives in and heals.
    tank.isInvulnerable = true
    let maxStr = tank.maxStrength
    tank.strength = min(100, maxStr / 2)

    // Give the house plenty of credits so repair is affordable.
    let hs = getHouseState(world.playerHouse)
    hs.credits = 5000
    session.sidebarCredits = 5000

    // Issue the repair order (mirrors GameInput's FIX branch).
    tank.repairBuildingID = fix.id
    tank.mission = .enter
    tank.moveTargetX = nil; tank.moveTargetY = nil; tank.movePath = []

    let startY = tank.worldY
    let startStr = tank.strength
    var minDistToFix = Double.infinity
    for t in 0..<300 {
        gameTick()
        let d = abs(fix.worldY - tank.worldY) + abs(fix.worldX - tank.worldX)
        minDistToFix = min(minDistToFix, d)
        if t == 60 || t == 150 || t == 299 {
            print("  t=\(t): tank cell=(\(tank.cellX),\(tank.cellY)) str=\(tank.strength)/\(maxStr) mission=\(tank.mission) distToFix=\(String(format: "%.0f", d))")
        }
    }

    let moved = tank.worldY < startY - 12   // moved north toward the FIX
    let healed = tank.strength > startStr
    if !moved { print("FAIL: tank did not move toward the FIX (startY=\(startY), endY=\(tank.worldY), minDist=\(minDistToFix))"); return 1 }
    if !healed { print("FAIL: tank never healed (str stayed \(startStr))"); return 1 }
    print("PASS: tank drove to the repair bay and healed \(startStr) -> \(tank.strength)")
    return 0
}

/// `--test-crush <SCEN>` — verify a tracked crusher (tank) will path through and
/// squish an enemy infantryman blocking a 1-wide chokepoint (the "tank refused
/// to cross the bridge" report). Exit 0 = pass.
func headlessTestCrushCommand(scenario: String) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("test-crush: scenario=\(scenario)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("test-crush: could not load scenario '\(scenario)'"); return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }

    // Carve a 1-wide E-W corridor (a stand-in for a bridge deck): a 5-cell run
    // is passable, everything immediately above/below it is walled off, so the
    // ONLY route from the west end to the east end is straight through the
    // middle cell — where we park an enemy infantryman.
    let cy = 30, x0 = 20
    for x in 0..<64 { for dy in -1...1 { landPassability[(cy + dy) * 64 + x] = false } }
    for x in x0...(x0 + 4) { landPassability[cy * 64 + x] = true }

    let tank = GameObject(id: world.allocateId(), typeName: "MTNK", house: world.playerHouse,
                          kind: .unit, worldX: Double(x0 * 24 + 12), worldY: Double(cy * 24 + 12),
                          facing: 64, strength: 400, mission: .guard_,
                          speed: resolveSpeed(typeName: "MTNK", kind: .unit))
    world.addObject(tank)

    let enemyHouse: House = world.playerHouse == .goodGuy ? .badGuy : .goodGuy
    let inf = GameObject(id: world.allocateId(), typeName: "E1", house: enemyHouse,
                         kind: .infantry, worldX: Double((x0 + 2) * 24 + 12), worldY: Double(cy * 24 + 12),
                         facing: 0, strength: 50, mission: .guard_,
                         speed: resolveSpeed(typeName: "E1", kind: .infantry))
    world.addObject(inf)
    let infId = inf.id

    // Order the tank to the east end (one cell past the infantry).
    tank.moveTargetX = Double((x0 + 4) * 24 + 12)
    tank.moveTargetY = Double(cy * 24 + 12)
    tank.mission = .move
    tank.movePath = []

    var crushed = false
    for _ in 0..<120 {
        gameTick()
        if world.findObject(id: infId) == nil || world.findObject(id: infId)!.strength <= 0 { crushed = true }
        if crushed && tank.cellX >= x0 + 4 { break }
    }

    if !crushed { print("FAIL: enemy infantry was NOT crushed — tank treated the chokepoint as blocked"); return 1 }
    if tank.cellX < x0 + 3 { print("FAIL: tank crushed but did not cross the chokepoint (cellX=\(tank.cellX))"); return 1 }
    print("PASS: tank crushed the enemy infantry and crossed the chokepoint")
    return 0
}

/// `--test-fogpath <SCEN>` — verify the human player's fog-aware pathfinding:
/// a unit plans straight through an UNEXPLORED obstacle (assumed passable) but
/// routes AROUND the same obstacle once it's explored. Exit 0 = pass.
func headlessTestFogPathCommand(scenario: String) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("test-fogpath: scenario=\(scenario)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("test-fogpath: could not load scenario '\(scenario)'"); return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }
    session.rules = .enhanced  // enable fog-aware ("advanced") wayfinding for this test

    // A vertical wall at column wx (rows cy-3..cy+3), inside the scenario map
    // bounds, so routing AROUND it is much longer than straight through.
    let cy = 48, wx = 48, fromX = 45, toX = 51
    for i in 0..<4096 { landPassability[i] = true }          // clear the board
    for dy in -3...3 { landPassability[(cy + dy) * 64 + wx] = false }

    let mover = GameObject(id: world.allocateId(), typeName: "MTNK", house: world.playerHouse,
                           kind: .unit, worldX: Double(fromX * 24 + 12), worldY: Double(cy * 24 + 12),
                           facing: 0, strength: 400, mission: .guard_,
                           speed: resolveSpeed(typeName: "MTNK", kind: .unit))
    world.addObject(mover)

    // 1. Wall UNEXPLORED → fog-aware path assumes it passable → straight across.
    fogState = Array(repeating: .unexplored, count: 4096)
    let hidden = findPath(fromX: fromX, fromY: cy, toX: toX, toY: cy, ignoring: mover, speedType: .track)
    let hiddenCrossesWall = hidden.contains { $0.cellX == wx && abs($0.cellY - cy) <= 3 }
    print("  unexplored wall: path len=\(hidden.count), crosses wall cell=\(hiddenCrossesWall)")

    // 2. Wall EXPLORED → real passability → must detour around it.
    fogState = Array(repeating: .explored, count: 4096)
    let known = findPath(fromX: fromX, fromY: cy, toX: toX, toY: cy, ignoring: mover, speedType: .track)
    let knownCrossesWall = known.contains { $0.cellX == wx && abs($0.cellY - cy) <= 3 }
    print("  explored wall:   path len=\(known.count), crosses wall cell=\(knownCrossesWall)")

    if hidden.isEmpty { print("FAIL: no path found through unexplored wall"); return 1 }
    if !hiddenCrossesWall { print("FAIL: fog path detoured around an UNEXPLORED wall (should assume passable)"); return 1 }
    if known.isEmpty { print("FAIL: no path found around explored wall"); return 1 }
    if knownCrossesWall { print("FAIL: path crossed a KNOWN impassable wall"); return 1 }
    if known.count <= hidden.count { print("FAIL: detour (\(known.count)) not longer than straight path (\(hidden.count))"); return 1 }
    print("PASS: player plans through unexplored terrain and reroutes once it's discovered")
    return 0
}

/// `--test-stacking <SCEN>` — verify two vehicles ordered to the SAME cell do
/// not end up stacked on one tile (the "humvees occupy the same tile" report).
/// Exit 0 = pass.
func headlessTestStackingCommand(scenario: String) -> Int32 {
    let seed: UInt64 = 0xD1CE_D1CE_D1CE_D1CE
    print("test-stacking: scenario=\(scenario)")
    forcedGameSeed = seed
    defer { forcedGameSeed = nil }
    guard let data = loadScenario("\(scenario).INI", from: mixManager) else {
        print("test-stacking: could not load scenario '\(scenario)'"); return 1
    }
    initGameWorld(scenario: data, scenarioName: scenario)
    guard let world = session.world else { return 1 }

    // Find an open 6x6 patch inside bounds.
    func open(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < 64 && y >= 0 && y < 64 && landPassability[y * 64 + x] }
    var base: (x: Int, y: Int)? = nil
    outer: for cy in 2..<58 { for cx in 2..<58 {
        var ok = true
        for dy in 0..<6 { for dx in 0..<6 where !open(cx + dx, cy + dy) { ok = false } }
        if ok { base = (cx, cy); break outer }
    } }
    guard let b = base else { print("FAIL: no open patch"); return 1 }

    // Three jeeps, spread out, all ordered to the SAME single cell.
    let sp = resolveSpeed(typeName: "JEEP", kind: .unit)
    var jeeps: [GameObject] = []
    let starts = [(b.x, b.y), (b.x + 5, b.y), (b.x, b.y + 5)]
    for (i, s) in starts.enumerated() {
        let j = GameObject(id: world.allocateId(), typeName: "JEEP", house: world.playerHouse,
                           kind: .unit, worldX: Double(s.0 * 24 + 12), worldY: Double(s.1 * 24 + 12),
                           facing: 0, strength: 100, mission: .move, speed: sp)
        _ = i
        world.addObject(j); jeeps.append(j)
    }
    let tx = b.x + 3, ty = b.y + 3
    for j in jeeps {
        j.moveTargetX = Double(tx * 24 + 12); j.moveTargetY = Double(ty * 24 + 12); j.movePath = []
    }

    for _ in 0..<200 { gameTick() }

    // Report resting cells; a cell shared by 2+ jeeps is a stack.
    var cellCount: [Int: Int] = [:]
    for j in jeeps { cellCount[j.cell, default: 0] += 1 }
    for j in jeeps { print("  jeep id=\(j.id) cell=(\(j.cellX),\(j.cellY))") }
    let stacked = cellCount.values.contains { $0 > 1 }
    if stacked { print("FAIL: two jeeps ended on the same cell"); return 1 }
    print("PASS: jeeps ordered to one point settled on distinct cells")
    return 0
}

/// Re-exec this binary as `--headless <scenario> <ticks> <seed>` and return its
/// stdout. Returns nil on launch failure.
private func runHeadlessSubprocess(scenario: String, ticks: Int, seed: UInt64) -> String? {
    let exePath = CommandLine.arguments[0]
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: exePath)
    proc.arguments = ["--headless", scenario, String(ticks), String(seed)]
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8)
    } catch {
        print("subprocess error: \(error)")
        return nil
    }
}

/// Extract the `digest=0x....` token from headless output.
private func parseDigest(_ output: String) -> String? {
    for line in output.split(separator: "\n") where line.hasPrefix("digest=") {
        return String(line)
    }
    return nil
}
