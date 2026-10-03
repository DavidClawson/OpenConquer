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

package struct Ruleset {
    /// Human-readable preset name (shown in the UI).
    package let name: String

    /// One-line description shown under the preset on the Options screen.
    package let summary: String

    /// Whether units gain veteran/elite promotions from kills. Off in the classic
    /// game (veterancy did not exist in 1995); gated at `GameObject.veteranLevel`
    /// so disabling it removes every downstream bonus (damage resistance, faster
    /// fire, extended sight, elite self-heal, rank chevrons) in one place.
    package var veterancyEnabled: Bool

    /// Wayfinding mode for the human player:
    ///   • false = "classic" — plan against true terrain everywhere (robust; the
    ///     unit routes correctly around real obstacles even in unexplored areas).
    ///   • true  = "advanced" — fog-of-war-aware: unexplored in-bounds cells are
    ///     assumed passable, so a unit ordered into the dark heads straight there
    ///     and reroutes on discovery. More immersive, at the cost of detours.
    /// Read at the single branch point `usesFogPathfinding(_:)` in GameMap.swift.
    /// Never enabled for the AI or headless runs, so determinism is unaffected.
    package var fogAwarePathfinding: Bool

    /// Whether the enhanced (non-classic) enemy-AI layer runs. The classic 1995
    /// campaign AI is entirely trigger/teamtype-driven: production starts only
    /// via the Production trigger (HOUSE.CPP:1892), attack pressure comes from
    /// Autocreate/Suggested_New_Team teams executing their mission lists, and
    /// units otherwise hold their scripted missions. FALSE (faithful) disables
    /// the modern layer on top of that: rally raids, idle-army attack waves,
    /// the 5-minute hunt escalation, the tactics suite (recon/hit-and-run/
    /// flanking/harassment), damaged-unit retreat, the 3-minute production
    /// auto-enable timeout, the personality-pool free production fallback, and
    /// free-form base building. The classic-faithful AI paths are NOT gated:
    /// turret/guard target acquisition, hunt, the Suggested_New_Team former,
    /// Suggest_New_Object team-demand production (incl. harvester replacement),
    /// and harvesters resuming work. Branch points read this in GameAI.swift
    /// (tickAI, tickAIProduction, decideUnitBuild/decideInfantryBuild).
    package var enhancedEnemyAI: Bool

    /// Whether TeamTypes with a non-zero `InitNum` spawn that many teams at
    /// scenario start. FALSE is faithful to 1995: classic TD parses InitNum but
    /// never consumes it at runtime (it appears only in TEAMTYPE.CPP parse/write,
    /// never in a spawn path — runtime teams come from AI autocreate,
    /// HOUSE.CPP:846/868 → Create_One_Of, and CREATE_TEAM triggers). Read at the
    /// single branch point: the InitNum loop in `initGameWorld` (GameInit.swift).
    package var spawnsInitialTeams: Bool

    /// Whether explored ground fogs over again once no unit sees it (enemies
    /// there hidden). FALSE is faithful to 1995: TD has only the shroud — a
    /// cell revealed by Map.Sight_From stays revealed for the rest of the
    /// mission, units in it included; re-growing fog came with Red Alert.
    /// Read at the single branch point: the demote step in `updateFog`.
    package var fogRegrowth: Bool

    /// How units find targets. TRUE is faithful to 1995 (TechnoClass::
    /// Evaluate_Object / Threat_Range / FootClass::Take_Damage):
    /// - the player's units are always visible to the computer, even under
    ///   shroud; other targets need only have been discovered by the player;
    /// - guard scans weapon range, area guard twice it (max 10 cells) around
    ///   its home cell, hunt the whole map;
    /// - a hit computer unit hunts its attacker; a hit unarmed building or
    ///   harvester calls up to six rescuers (Base_Is_Attacked);
    /// - a player's commando never auto-fires from guard.
    /// FALSE keeps the enhanced model: targets gated by the house's own sight,
    /// wider scans, and short-range return fire. Read through
    /// `usesOriginalTargeting` (GameCombat.swift).
    package var originalTargeting: Bool

    // Future tunables slot in here (crush behavior, build adjacency, economy
    // constants, …), each read at a single branch point in the simulation.

    /// The authentic 1995 experience. Canonical, determinism-pinned baseline.
    package static let classic1995 = Ruleset(
        name: "Classic (1995)",
        summary: "No veterancy - classic wayfinding - scripted AI - shroud only",
        veterancyEnabled: false,
        fogAwarePathfinding: false,
        enhancedEnemyAI: false,
        spawnsInitialTeams: false,
        fogRegrowth: false,
        originalTargeting: true
    )

    /// Classic plus modern gameplay enhancements.
    package static let enhanced = Ruleset(
        name: "Enhanced",
        summary: "Veterancy - fog-aware wayfinding - aggressive AI - fog of war",
        veterancyEnabled: true,
        fogAwarePathfinding: true,
        enhancedEnemyAI: true,
        spawnsInitialTeams: true,
        fogRegrowth: true,
        originalTargeting: false
    )

    /// All built-in presets, in display order.
    package static let presets: [Ruleset] = [.classic1995, .enhanced]
}
