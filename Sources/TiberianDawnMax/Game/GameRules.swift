import Foundation

// MARK: - Ruleset
//
// The ruleset is the data-driven switchboard for tunable game behavior. It lets
// the game run either as the authentic 1995 title or with optional modern
// enhancements, and it's the foundation for future modding (see docs/VISION.md,
// docs/ROADMAP.md — Phase 1).
//
// Rules of the road:
//   • `Ruleset.classic1995` is the CANONICAL, determinism-tested baseline. The
//     headless harness runs against it, so its digests are the pinned regression
//     values in CLAUDE.md. Do not change classic1995's values casually.
//   • New tunables get added here as a field + a value in each preset, then the
//     relevant simulation code reads `session.rules.<field>` at the single point
//     where the behavior branches (e.g. veterancy reads it in one place).
//   • Presets are plain data; a future in-game Options screen / mod loader can
//     construct or override a `Ruleset` without touching engine code.

struct Ruleset {
    /// Human-readable preset name (shown in the UI).
    let name: String

    /// Whether units gain veteran/elite promotions from kills. Off in the classic
    /// game (veterancy did not exist in 1995); gated at `GameObject.veteranLevel`
    /// so disabling it removes every downstream bonus (damage resistance, faster
    /// fire, extended sight, elite self-heal, rank chevrons) in one place.
    var veterancyEnabled: Bool

    // Future tunables slot in here (crush behavior, build adjacency, economy
    // constants, …), each read at a single branch point in the simulation.

    /// The authentic 1995 experience. Canonical, determinism-pinned baseline.
    static let classic1995 = Ruleset(
        name: "Classic (1995)",
        veterancyEnabled: false
    )

    /// Classic plus modern gameplay enhancements.
    static let enhanced = Ruleset(
        name: "Enhanced",
        veterancyEnabled: true
    )

    /// All built-in presets, in display order.
    static let presets: [Ruleset] = [.classic1995, .enhanced]
}
