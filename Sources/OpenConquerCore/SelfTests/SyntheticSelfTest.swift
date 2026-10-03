import Foundation
import OpenConquerAssets

// MARK: - Asset-free determinism net (--test-synthetic)
//
// Asset-free: each builds its world in code and never loads from a MIX, so
// they run under `swift test` (Tests/OpenConquerCoreTests) as well as through
// their `--test-*` flags in the app. Exit code 0 = pass.

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
package func headlessTestSyntheticCommand(ticks: Int) -> Int32 {
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
