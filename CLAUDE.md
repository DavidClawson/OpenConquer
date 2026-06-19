# TiberianDawnMax — Codebase Guide

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
./.build/debug/TiberianDawnMax --ai-parity    <SCEN> <ticks>      # B3: assert the AI decide() phase is pure (no RNG/world mutation)
./.build/debug/TiberianDawnMax --ai-trace     <SCEN> <ticks>      # B3: print the per-house goal/decision stream each decide tick
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

## Status & where to build next (2026-06)

See `docs/IMPROVEMENT_PLAN.md` for full history; `docs/B3_B4_PLAN.md` for the
AI/editor design.

- **Fixed:** harvester refinery docking animation, building damage-state frames,
  and terrain (cliff/tree/water) pathfinding via a per-cell LandType model.
- **AI decision layer (B3):** complete at parity. All AI decisions (production,
  attack/rally/escalation, tactics) are split into pure `decideX` + effectful
  `applyX` (`GameAI.swift`, `GameAITactics.swift`). The top-level `decide()` /
  `apply()` and goal vocabulary in `GameAIBrain.swift` are a **reserved seam**,
  not yet populated — that's where a goal-scoring "smarter AI" plugs in.
- **Next:** populate the goal-scoring seam (smarter AI), or B4 mission editor
  (`docs/B3_B4_PLAN.md`, E0+); A3 stage-2 speed-cost weighting in A* (F3) is
  deferred.
