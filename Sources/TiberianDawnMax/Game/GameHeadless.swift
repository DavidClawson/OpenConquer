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
