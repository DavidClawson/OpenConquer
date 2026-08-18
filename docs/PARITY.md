# OpenConquer — Parity Checklist

What is **verified** against the original, what is **ported but untested**, what is
**approximated**, and what is **missing**. This is the honest map of how close the
simulation is to 1995 Tiberian Dawn — written so a contributor can pick a row and
know exactly what "fixing it" means.

The reference sources are EA's GPLv3 releases, kept alongside the repo and never
bundled (see [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- **`../CnC_Tiberian_Dawn/`** — the original Westwood C++. The authority.
- **`../Vanilla-Conquer/`** — the modern port; cleaner C++, good for constants.

## Legend

| | Status | Means |
|---|---|---|
| ✅ | **Verified** | Ported from the reference *and* pinned by a `--test-*` harness or the `--determinism` baselines. A regression fails a check. |
| 🟢 | **Ported** | Transcribed from the reference C++, believed faithful, but nothing asserts it. Trust it; don't bet on it. |
| 🟡 | **Approximated** | Plays close to right, but the mechanism is ours rather than the original's. Each row names the actual difference. |
| ⬜ | **Missing** | Not implemented. |
| ➖ | **Out of scope** | Deliberately not doing (see [`ROADMAP.md`](ROADMAP.md)). |

Everything below describes the canonical **`classic1995`** ruleset. The
**`enhanced`** preset intentionally deviates — that's its purpose — and those
deviations are listed in [Ruleset deviations](#ruleset-deviations) rather than
counted as parity gaps.

---

## Determinism & the simulation core

| Item | Status | Reference | Notes |
|---|---|---|---|
| Fixed 15 FPS sim tick, decoupled from render | ✅ | `GameLoop.swift` | Phase order is load-bearing (= RNG consumption order). |
| Seeded RNG for all sim randomness | ✅ | `GameRandom.swift` | `--determinism` runs 3 clean subprocess trials; three pinned baselines in [`CLAUDE.md`](../CLAUDE.md). |
| Session reset hygiene between missions | ✅ | `initGameWorld` | `--reset-check` asserts two in-process worlds match. |
| Same-seed reproducibility across processes | ✅ | — | `--test-synthetic` is the asset-free equivalent and runs in CI. |
| Original's exact RNG stream/algorithm | 🟡 | `RANDOM.CPP` | We are *self*-deterministic, not stream-compatible with the C++. Reproducing original replays is not a goal. |

## Data tables

| Item | Status | Reference | Notes |
|---|---|---|---|
| Unit stats (cost, HP, armor, speed, ROT, sight, flags) | 🟢 | `udata.cpp` | Transcribed constructor-by-constructor. |
| Building stats | 🟢 | `bdata.cpp` | |
| Infantry stats | 🟢 | `idata.cpp` | |
| Aircraft stats | 🟢 | `adata.cpp` | |
| Weapons (damage, ROF, range, bullet, warhead) | 🟢 | `const.cpp` `Weapons[]` | |
| Warhead-vs-armor modifier matrix | 🟢 | `const.cpp` `Warheads[]` | |
| House types | 🟢 | `hdata.cpp` | |
| Per-template land types (what's rock/water/road) | ✅ | `CDATA.CPP` + `CELL.CPP` Recalc_Attributes | Auto-generated table (`TemplateLandData.swift`); pathfinding depends on it. |
| Per-field C++ line citations in the tables | ⬜ | — | Headers cite the source file; individual values don't. Roadmap Phase 3. |

## Combat

| Item | Status | Reference | Notes |
|---|---|---|---|
| Warhead modifier applied vs. target armor | 🟢 | `COMBAT.CPP` Modify_Damage | `modifyDamage` in `WeaponData.swift`. |
| Minimum 1 damage floor | 🟢 | `COMBAT.CPP:69` | |
| **Splash falloff curve** | 🟡 | `COMBAT.CPP:87-91` | Original: `distance >>= SpreadFactor; damage >>= distance` (halving per step, capped at 16). Ours: linear falloff over `SpreadFactor * 24`. Different splash shape. **[good first issue]** |
| Rate of fire / range gating | 🟢 | `TECHNO.CPP` | Range in leptons from the weapon tables. |
| Retaliation / return fire | 🟢 | `TECHNO.CPP` | Snap to the attacker when idle. |
| Infantry fear & prone | 🟢 | `INFANTRY.CPP` fear model | Plus a first-contact reflex drop that the original doesn't have (avoids the stand-still-and-eat-a-burst window). |
| Crushing infantry with tracked units | ✅ | `UNIT.CPP` | `--test-crush`; crushers under an explicit move order drive through rather than stopping to shoot. |
| Building damage states / half-health frames | 🟢 | `BUILDING.CPP:560-634` | `pickStructureFrame`. |
| On-building fire animations are cosmetic | ✅ | — | They used to deal real damage and finish off crippled objects; fixed and pinned by the determinism baselines. |
| Per-instance invulnerability (mission flag) | ✅ | `ObjectTypeClass::IsImmune` | `--test-flags`. |
| **Stealth Tank cloaking** | ⬜ | `TECHNO.CPP` cloak state | `isCloakable` is parsed into the unit table but nothing in the sim or renderer uses it — STNK is permanently visible. **[good first issue]** |

## Movement & pathfinding

| Item | Status | Reference | Notes |
|---|---|---|---|
| Per-`SpeedType` passability (foot/track/wheel/float) | ✅ | `CELL.CPP` | `buildPassabilityMap`; cliffs/rock/water/boulders block correctly. |
| A* with octile heuristic, 8-directional | 🟡 | `FINDPATH.CPP` | The original uses its own crawler, not A*. Results are equivalent-looking; the search is ours. |
| Corner-cut rule, exempted on bridge/ford decks | ✅ | — | Pinned by the SCB01EA baseline. |
| **Per-terrain speed cost** (roads faster, rough slower) | ⬜ | `Ground[]` speed table | Passability is boolean; terrain doesn't modulate speed. Deferred as roadmap item A3 stage-2. |
| Units don't stack on a shared destination cell | ✅ | — | `--test-stacking`; occupancy stays live within a tick. |
| Human player pathfinds against explored terrain only | ✅ | — | `--test-fogpath`; ruleset-gated (`fogAwarePathfinding`), off for AI/headless so baselines stay omniscient. |
| Scatter / unstick behavior | 🟢 | `FOOT.CPP` | |

## Economy

| Item | Status | Reference | Notes |
|---|---|---|---|
| Tiberium growth & spread scan cycle | 🟢 | VC `MapClass::Logic()` | Block-scan + candidate reservoir, forward/reverse alternation. Deviation: we process up to 4 growth picks per cycle for a visible rate. |
| Harvesting, bail value, refinery docking | ✅ | `UNIT.CPP` harvest | Dock/siphon/undock animates the real PROC frames (12-29); harvester limboed on attach. |
| Silo capacity clamps deposits (overflow wasted) | ✅ | — | `--test-harvester-economy` also asserts capacity frees as credits are spent. |
| Silo fill-level frames | 🟢 | `pickStructureFrame` | SILO frames 0-4 / damaged 5-9. |
| Harvesters idle at the refinery when storage is full | 🟢 | — | Was: pointless shuttling. |
| Power production/drain and the low-power state | 🟢 | `HOUSE.CPP` power | Drives the sidebar meter and build rate. |
| Building sell refund | 🟡 | `BUILDING.CPP` sell | Flat 50% of cost. The original refunds based on the building's *current* health-scaled value. |
| Repair bay (FIX) heals a vehicle on the pad | ✅ | — | `--test-repair`. |
| Building repair (wrench) cost/rate | 🟢 | `BUILDING.CPP` repair | |

## Production & base building

| Item | Status | Reference | Notes |
|---|---|---|---|
| Prerequisites, build level, house ownability | 🟢 | `bdata/udata` tables | |
| Low power halves build rate | 🟡 | `FACTORY.CPP::AI` | Ours: skip every other tick. Original: staged rate table. |
| **Build time formula** | 🟡 | `FACTORY.CPP` | Ours: `max(30, cost/5)` ticks, flat. Original: a 54-step (`STEP_COUNT`) staged model with per-tick installment payments (`Cost_Per_Tick`). |
| **Multi-factory acceleration** | ⬜ | `FACTORY.CPP:245-263` | The original speeds a human player's production by the number of same-type factories owned. Not implemented. **[good first issue]** |
| **Installment payment** (charged per tick, refund on cancel = what you paid) | ⬜ | `FACTORY.CPP:696-707` | We charge the full cost up front and refund it on cancel. |
| MCV deploys into a Construction Yard | 🟢 | `UNIT.CPP` deploy | Footprint/blocking checks before deploying. |
| Build-area adjacency rules | 🟢 | `BUILDING.CPP` | |

## Fog, radar & vision

| Item | Status | Reference | Notes |
|---|---|---|---|
| Shroud reveal by sight range | 🟢 | `MAP.CPP` | |
| Out-of-bounds map area masked solid | ✅ | — | Was translucent, leaking unreachable fog. |
| Radar requires a Comm Center / power | 🟢 | `HOUSE.CPP` radar | |
| Fog-of-war regrow | ➖ | — | Tiberian Dawn has shroud, not regrowing fog. Correctly absent. |

## Triggers, teams & scenarios

This is the most heavily audited area — a full trigger/team/campaign fidelity audit
against the C++ was completed in July 2026 (see [`ROADMAP.md`](ROADMAP.md) Phase 2).

| Item | Status | Reference | Notes |
|---|---|---|---|
| INI scenario + map loading, round-trip safe | ✅ | `INI.CPP` | `--editor-roundtrip` asserts load→document→INI→reload is faithful and idempotent. |
| `IsAutocreate` parsing | ✅ | `TEAMTYPE.CPP` | Enemy attack waves were silently disabled before the fix. |
| AllowWin / Blockage win-gating | ✅ | `TRIGGER.CPP` | `--test-wingate`; four Nod missions (SCB04-07) used to win early. |
| Cap=Win / Des=Lose branching on the firing event | ✅ | `TRIGGER.CPP` | `--test-winlose`; firing event threaded through `fireTrigger`. |
| `Data=0` time triggers fire on the first check | ✅ | `TRIGGER.CPP:374-380` | Classic decrement-before-test. 13 campaign variants were broken by this, incl. two auto-losing missions. |
| Event-detection parity (Built It, NoFactories, destroyed scans) | ✅ | `HOUSE.CPP` scan masks | `--test-eventparity`; destroyed-scans exclude gunboat/transport/cargo/A-10. |
| Cell-trigger house matching + aircraft exclusion | ✅ | `CELL.CPP` | Fixed SCB04 / SCG09. |
| `BeginProduction` / `Autocreate` scoped to the trigger's own house | ✅ | `HOUSE.CPP` | Fixed SCB13 / SCB12. |
| Per-house superweapons: enemy charges and fires | ✅ | `HOUSE.CPP` AI, `SUPER.CPP` | `--test-enemy-superweapon`; Nuke/Ion arm the owning house, not the player. Fixed SCG15/SCB12/SCB13. |
| `InitNum`-at-start team spawning | ✅ | `TEAMTYPE.CPP` | Ruleset-gated: `classic1995` skips it (editor-only in classic TD); `enhanced` keeps it. `--test-initteams`. |
| Reinforcement delivery (`Edge=` entry, team mission lists, loaner rules, limbo) | ✅ | `REINF.CPP` (full port) | `--test-reinforcements`; team-less fixed-wing gets MISSION_HUNT (REINF.CPP:366-368); limboed cargo is untargetable in transit. |
| Civilian-evacuation win model | ✅ | `AIRCRAFT.CPP:836-855`, `HOUSE.CPP:1257` | `--test-civ-evac`; SCG11 (Delphi) and SCG12 (Mobius) are winnable. |
| Mission name parsing incl. "Area Guard" | ✅ | `MISSION.CPP:464` | The classic spelling used to silently downgrade to plain Guard. |
| Campaign branching + GDI SCG06 sabotage skip | ✅ | `MAPSEL.CPP` CountryArray | `--test-campaign-graph`. |
| All 28 missions / 47 variants play through | ✅ | — | July 2026 sweep; 8 defect classes found and fixed. |
| Mission authoring path (new scenarios) | ⬜ | — | Hand-authored INI works; the in-game editor is [`MISSION_EDITOR_PLAN.md`](MISSION_EDITOR_PLAN.md). |
| A mission declaring its own ruleset | ⬜ | — | Roadmap Phase 2. |

## AI

| Item | Status | Reference | Notes |
|---|---|---|---|
| Campaign AI is trigger/teamtype-driven only | ✅ | `HOUSE.CPP:1892` | `--test-ai-gating`; production starts *only* via the Production trigger under `classic1995`. |
| `Suggested_New_Team` former (RecruitPriority, MaxAllowed, owned-type check) | ✅ | `HOUSE.CPP` | `--test-team-former`; replaced a flat every-675-tick random pick. |
| `Suggest_New_Object` team-demand production, incl. build-nothing semantics | ✅ | `HOUSE.CPP:3166-3383` | `--test-prebuilt`; campaigns seed zero counters (HOUSE.CPP:3195-3204). |
| Harvester replacement priority | 🟢 | `HOUSE.CPP` | Priority 1 in `decideUnitBuild`; classic-faithful, ungated. |
| Guard / turret target acquisition, hunt | 🟢 | `TECHNO.CPP`, `MISSION.CPP` | Ungated — faithful paths. |
| Decision purity (decide/apply split) | ✅ | — | `--ai-parity` asserts `decide()` mutates nothing and consumes no RNG. |
| Goal-scoring "smarter AI" seam | ⬜ | — | `GameAIBrain.swift` is a reserved, unpopulated seam. Not a parity item — a future enhanced-only feature. |

## Superweapons & special

| Item | Status | Reference | Notes |
|---|---|---|---|
| Ion Cannon / Nuke charge, targeting, firing | ✅ | `SUPER.CPP`, `HOUSE.CPP` | Per-house `HouseState.superWeapons`; the AI targets the player's highest-value building. |
| Airstrike (A-10) delivery | ✅ | `REINF.CPP:366-368` | Team-less fixed-wing hunts. |
| **Crates** | 🟡 | `CRATE.CPP` | Our own 7-outcome table and probability split (money/heal/speed/firepower/reveal/free-unit/explosion). The original's crate mix, weights, and multiplayer-only gating are different. |
| Dinosaur / secret missions | ➖ | — | Out of scope. |

## Save/load & campaign state

| Item | Status | Reference | Notes |
|---|---|---|---|
| Full world serialization round-trip | 🟢 | — | `GameSaveLoad.swift`; objects, houses, triggers, teams, production. |
| Campaign progression, variants, sabotage record | ✅ | `MAPSEL.CPP` | `--test-campaign-graph`. |
| **Mission score screen formula** | 🟡 | `SCORE.CPP` | Ours approximates VC: `kills + buildings*2 + credits/100 - time penalty`. Not the original's leadership/economy/tech breakdown. |
| Original `.SAV` file compatibility | ➖ | — | Never a goal; our format is our own. |

## Presentation

Not parity-scoped — the project's stated principle is *faithful simulation, **modern**
presentation*. Listed for completeness.

| Item | Status | Notes |
|---|---|---|
| Classic SHP rendering | 🟢 | |
| Remastered HD sprite rendering | 🟢 | Extracted from the user's own Remastered install. |
| HD cursors | ✅ | 57 families / 456 frames, with hotspots; falls back to procedural shapes. |
| HD sidebar power/progress meters | ⬜ | Art extracted to `ui/sidebar/`, not yet wired. Roadmap Phase 4. |
| Arbitrary window size / zoom | 🟢 | Deliberate deviation from the fixed 640×400. |
| Audio (classic AUD + remastered masters) | 🟢 | |
| Smudges render under buildings/units | ✅ | |

## Ruleset deviations

The `enhanced` preset turns on behavior that is deliberately **not** 1995. These are
features, not gaps — `classic1995` is the parity target and stays pinned.

| Toggle | `classic1995` | `enhanced` |
|---|---|---|
| `veterancy` | off | on — kill-count promotions, elite damage reduction |
| `fogAwarePathfinding` | off | on — interactive play only either way |
| `enhancedEnemyAI` | off | on — rally raids, idle-army attack waves, 5-min escalation, tactics suite, damaged retreat, production auto-enable, personality-pool production, free-form base building |
| `InitNum` team spawning | off | on |

Per-toggle overrides on top of a preset are not implemented yet (preset-level only).

---

## Explicitly out of scope

Multiplayer / netcode · Red Alert and later titles · bundling any game asset ·
original save-file compatibility · replay compatibility with the C++ RNG stream.

## Contributing to this document

If you fix a 🟡 or ⬜ row, move it up **and add the evidence** — a `--test-*` harness
entry, or a determinism baseline it now pins. A row only reaches ✅ when something
fails if it regresses. If you find a gap that isn't listed, add the row before
fixing it; the honest map is the point.
