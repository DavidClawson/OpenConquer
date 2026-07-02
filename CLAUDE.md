# TiberianDawnMax — Codebase Guide

> **Public name: OpenConquer.** `TiberianDawnMax` is the internal codename / SwiftPM
> target. The published project is branded **OpenConquer** to avoid the EA
> trademarks (see `README.md`, `docs/VISION.md`). License: **GPLv3** (`LICENSE`).
> Never commit game assets. Roadmap: `docs/ROADMAP.md`.

A Swift + SDL2 reimplementation of **Command & Conquer: Tiberian Dawn** for macOS.
The original Westwood C++ source and the open-source Vanilla-Conquer port live
alongside this repo as reference (see "Reference sources" below).

## Build & run

```bash
swift build            # or:  swift run
./TiberianDawnMax.command   # wrapper that runs `swift run`
```

- Requires SDL2: `brew install sdl2` (wired via the `CSDL2` system-library target).
- Target: macOS 13+. Toolchain: swift-tools 5.9.

### Headless harness (no window/render/audio)

The simulation can run without SDL — useful for verifying logic changes without
watching the game. Run the built binary directly:

```bash
./.build/debug/TiberianDawnMax --headless <SCEN> <ticks> [seed]   # run + print state digest
./.build/debug/TiberianDawnMax --determinism <SCEN> <ticks>       # 3 clean subprocess trials, assert identical
./.build/debug/TiberianDawnMax --reset-check  <SCEN> <ticks>      # two in-process worlds, assert session state fully reset
./.build/debug/TiberianDawnMax --test-synthetic [ticks]          # ASSET-FREE determinism net (in-code scenario) — runs in CI
./.build/debug/TiberianDawnMax --test-wingate                    # ASSET-FREE: AllowWin/Blockage win-gating (Gap #3) — runs in CI
./.build/debug/TiberianDawnMax --test-winlose                    # ASSET-FREE: Cap=Win/Des=Lose event branching (Gap #2) — runs in CI
./.build/debug/TiberianDawnMax --ai-parity    <SCEN> <ticks>      # B3: assert the AI decide() phase is pure (no RNG/world mutation)
./.build/debug/TiberianDawnMax --ai-trace     <SCEN> <ticks>      # B3: print the per-house goal/decision stream each decide tick
./.build/debug/TiberianDawnMax --test-flags   <SCEN>             # Tier-1: per-instance invulnerable / must-survive flags
./.build/debug/TiberianDawnMax --test-harvester-economy         # silo capacity frees up as credits are spent
./.build/debug/TiberianDawnMax --test-repair  <SCEN>            # a player vehicle drives to a FIX and heals
./.build/debug/TiberianDawnMax --test-crush   <SCEN>            # a tank squishes enemy infantry at a chokepoint
./.build/debug/TiberianDawnMax --test-fogpath <SCEN>           # player plans through unexplored, reroutes on discovery
./.build/debug/TiberianDawnMax --test-stacking <SCEN>          # units ordered to one point don't stack on a cell
./.build/debug/TiberianDawnMax --editor-roundtrip <SCEN>         # E1: scenario load→document→INI→reload is faithful, idempotent, edit-safe
```

e.g. `--headless SCG01EA 600` or `--determinism SCG01EA 2500`. The determinism
check is the regression net for AI/pathfinding work: a change that perturbs the
simulation shows up as a changed digest. (Other diagnostic flags: `--test-mix`,
`--dump-scenario <NAME>`.) Implementation: `Game/GameHeadless.swift`.

- Note: the simulation is deterministic given a seed, both across separate
  processes and across two `initGameWorld` calls in one process (`initGameWorld`
  resets the persistent `session` sub-containers — see the F1 fix). `--reset-check`
  guards that reset hygiene; `--determinism` uses subprocesses for an independent
  check.
- **Seed gotcha:** `--determinism` runs with a *forced* fixed seed; `--headless`
  (no seed arg) uses `stableSeed(scenarioName)`. They are different seeds, so
  their digests are **not comparable** — `--headless SCG01EA 4000` and
  `--determinism SCG01EA 4000` print different digests for the same code. Compare
  like-for-like. The documented regression baselines are the `--determinism`
  values (as of 2026-07-01, **default ruleset = `classic1995`, veterancy OFF**):
  SCG01EA 2500t `0xF2FC92976A82C252`, 4000t `0xC645B24188C4D2CC`,
  SCB01EA 4000t `0xA3C944E7664939D2` (changed from `0xD46F9A67468411FF` when the
  A* corner-cut rule was exempted for bridge/ford decks — units/AI now cross the
  diagonal bridge deck in that Nod mission; see `findPath` + `deckCells`).
  The SCG01EA digests changed from
  `0xD1596F2E7234204A` / `0x9D62132321684A74` when veterancy became a ruleset
  toggle that is off in the canonical `classic1995` preset (see `GameRules.swift`
  and `GameObject.veteranLevel`); SCB01EA is unchanged because no unit scores
  3+ kills in that Nod mission within 4000 ticks, so veterancy never fired there.
  (Earlier, SCB01EA changed from `0xC6BACBDF0518D5B7` when crushers stopped
  retaliating against crushable infantry under an explicit move order.)
  **Baselines are per-ruleset:** these are the `classic1995` values; a different
  active ruleset (e.g. `.enhanced`) produces different, separately-pinned digests.

## Reference sources (read-only, not part of the build)

- `../CnC_Tiberian_Dawn/` — the original Westwood C++ source (UNIT.CPP, BUILDING.CPP,
  CELL.CPP, MAP.CPP, CONST.CPP, etc.). The authoritative behavior reference.
- `../Vanilla-Conquer/` — modern open-source port; cleaner C++ and good for
  cross-checking constants and frame layouts.

When reimplementing a behavior, grep the C++ for the relevant `Mission_*`,
`LAND_*`, `BSTATE_*`, or data table before guessing.

## Architecture (the mental model)

- **Single source of truth:** a global `session: GameSession` (`main.swift`) owns
  all mutable state through nested containers:
  - `session.world` → `GameWorld` (objects, map, occupancy) — `Game/GameState.swift`
  - `session.production` → build queues / sidebar
  - `session.scripting` → triggers, AI, teams
  - `session.combat` → projectiles, animations, superweapons
  - `session.campaign` → mission progression
- **Game objects** are a single `GameObject` **class** (reference type) in
  `Game/GameState.swift`. Behavior is attached via `extension GameObject` blocks
  spread across many files (missions, combat, economy, movement, animation).
- **Fixed-tick loop:** the sim runs at a fixed **15 FPS** (`Game/GameLoop.swift`),
  decoupled from render FPS via an accumulator in `main.swift`. Rendering
  interpolates between ticks. `gameTick()` is the one discrete update: occupancy
  rebuild → fog → per-object mission ticks → AI → triggers → tiberium growth →
  remove dead.
- **Deterministic:** all *simulation* randomness flows through the seeded
  `gameRng` (see Conventions); same seed + same inputs → identical run, across
  processes and across two `initGameWorld` calls in one process. The headless
  harness guards this.

## Folder map (`Sources/TiberianDawnMax/`)

| Folder | What's there |
|--------|--------------|
| `App/` | session container, input, event handling, perf, window |
| `Game/` | all simulation: loop, state, missions, AI, combat, economy, map/pathfinding, triggers, teams, save/load, campaign |
| `Rendering/` | `GameRenderer` (in-game), `MapRenderer` (scenario/map view), cursor, text |
| `Data/` | static type tables: units, buildings, infantry, aircraft, weapons, houses |
| `Assets/` | MIX/SHP/ICN/INI parsers, asset manager, remastered-sprite handling |
| `Scenario/` | INI scenario + map loaders |
| `Audio/`, `UI/` | sound + menus |

Key files to know: `Game/GameState.swift` (object model + Mission enum),
`Game/GameLoop.swift` (tick + `moveOneStep`), `Game/GameMap.swift` (pathfinding +
`buildPassabilityMap`), `Rendering/GameRenderer.swift` (`pickStructureFrame`),
`Game/GameEconomy.swift` (harvesting).

## Conventions

- Match the C++ behavior; cite the reference file/line in comments where a choice
  mirrors the original (existing code already does this, e.g. "mirrors
  building.cpp:560-634").
- New behavior on objects goes in an `extension GameObject` in the topically
  appropriate `Game/` file.
- **Randomness:** simulation code (anything that mutates world/object/house/AI
  state during `gameTick`) MUST use the seeded helpers `rndInt/rndDouble/rndBool/
  .rndElement()` from `Game/GameRandom.swift`, never `Int.random(...)` etc.,
  or you break determinism. Purely cosmetic randomness (screen shake, debris and
  explosion offsets, sprite flicker, audio, menus) deliberately stays on the
  system RNG and must NOT use the seeded helpers.
- Prefer guards over force-unwraps; several `queue.item!` / `.last!` sites exist
  and are crash risks (see plan).
- **Split files when touched, not in a pass.** The codebase is well-organized by
  folder/concern; don't do dedicated "reorganize everything" passes (they risk
  the determinism contract for little gain). Instead, when you're already editing
  a file that has crossed ~800 lines *or* visibly mixes two separable concerns,
  split it along its natural seam as part of that work. Keep new behavior in the
  topically-appropriate file rather than growing a catch-all. (Current largest
  files worth splitting on contact: `UI/MenuScreen.swift`,
  `Rendering/GameRenderer.swift`, `Rendering/MapRenderer.swift`,
  `Game/GameCampaign.swift`, `Game/GameSaveLoad.swift`, `Game/GameAI.swift`.)
  Note `gameTick()` in `GameLoop.swift` is the one exception where source order
  is load-bearing (= RNG-consumption order) — extract phases there carefully and
  re-verify `--determinism` after each step; never reorder or fuse the per-object
  passes.

## Status & where to build next (2026-06)

See `docs/IMPROVEMENT_PLAN.md` for full history; `docs/B3_B4_PLAN.md` for the
AI/editor design.

- **Fixed:** harvester refinery docking animation, building damage-state frames,
  and terrain (cliff/tree/water) pathfinding via a per-cell LandType model.
- **Fixed (2026-06):** harvester docking now hides the unit and animates the
  PROC.SHP dock/siphon/undock frames (12-29) like the original (the harvester is
  limboed on attach); silos show their fill level (SILO frames 0-4/damaged 5-9,
  from house tiberium/capacity — `pickStructureFrame`); harvesters idle at the
  refinery instead of shuttling when storage is full; the repair-bay (FIX) order
  reliably drives a vehicle onto the pad and heals it; and the **human player**
  pathfinds against explored terrain only (unexplored = assumed passable, reroute
  on discovery — gated by `session.fogAwarePathfinding`, set only in interactive
  play so headless/AI stay omniscient and the determinism baselines are intact).
- **Fixed (2026-06, cont.):** music aliasing/crackle (audio device now 44100 Hz to
  match the remastered masters + fractional resample phase carried across ticks +
  louder default music); out-of-bounds map area now masked SOLID black and small
  maps are centred (was translucent, showing unreachable fog); scorch/crater
  smudges render UNDER buildings/units (`renderSmudges`, its own early pass);
  vehicles ordered to one point no longer stack (occupancy kept live within a
  tick — `executeMovementStep` defer); tracked crushers under an explicit move
  order drive through & squish crushable infantry instead of stopping to shoot
  (`evaluateRetaliation`); GDI mission-select titles corrected to the real
  briefing names (SCG08EA = "Repair GDI Equipment", not "Remove SAM Sites").
- **Remastered HD UI art (2026-07):** `tools/extract_remastered_sprites.py --category ui`
  decodes the remastered in-game UI from `TEXTURES_SRGB.MEG` (uncompressed 32-bit
  `ICON_*.DDS` / `UI_*.DDS`) + cursor hotspots from `CONFIG.MEG` MOUSEPOINTERS.XML,
  writing PNGs to `<extracted>/sprites_remastered/ui/`: `cursors/<FAMILY>/…png`
  (57 families, 456 frames, 1× + `_X2` hi-DPI) with a `cursors.json` manifest
  (POINTER_* → family + hotX/hotY), and `sidebar/…png` (power-meter segments,
  in-progress/train/resource fill bars). The `read_dds()` helper handles only
  uncompressed 32-bit surfaces (BGRA/RGBA by mask). NOT extractable (absent in the
  remaster as bitmaps): the sidebar chrome/frame (vector/HTML), the build cameos
  (never remastered — still classic SHPs), and the radial build-progress clock
  (procedural shader). The **HD cursors are wired in** (`Rendering/GameCursorHD.swift`):
  `drawProceduralCursor` calls `drawHDCursor` first (maps each `CursorDef` →
  texture family + hotspot, blits the animated frame scaled to ~28px, lazily
  loads the manifest, caches textures) and only falls back to the procedural
  shapes if the `ui/cursors/` art isn't installed. The sidebar power/progress
  meter art is extracted but not yet wired (separate follow-up).
- **AI decision layer (B3):** complete at parity. All AI decisions (production,
  attack/rally/escalation, tactics) are split into pure `decideX` + effectful
  `applyX` (`GameAI.swift`, `GameAITactics.swift`). The top-level `decide()` /
  `apply()` and goal vocabulary in `GameAIBrain.swift` are a **reserved seam**,
  not yet populated — that's where a goal-scoring "smarter AI" plugs in.
- **Next:** populate the goal-scoring seam (smarter AI), or B4 mission editor
  (`docs/B3_B4_PLAN.md`, E0+); A3 stage-2 speed-cost weighting in A* (F3) is
  deferred.
