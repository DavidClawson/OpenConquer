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
