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
./tools/make-app.sh         # package dist/OpenConquer.app (double-clickable)
```

- Requires SDL2: `brew install sdl2` (wired via the `CSDL2` system-library target).
- Target: macOS 13+. Toolchain: swift-tools 5.9.
- **Asset location** is `~/Library/Application Support/Vanilla-Conquer/vanillatd`.
  Two overrides, in precedence order (`main.swift`): `OPENCONQUER_DATA_DIR`, then the
  `TDMax.dataDir` user default (`defaults write org.openconquer.OpenConquer
  TDMax.dataDir <path>`). The user default exists because LaunchServices does not pass
  the environment to a Finder-launched app, so the env var alone is useless to the
  `.app`. The override is also how you exercise the no-assets path —
  `homeDirectoryForCurrentUser` reads the passwd database, so setting `HOME` does not
  move it: `OPENCONQUER_DATA_DIR=/tmp/empty swift run`.
- **`UI/SetupScreen.swift`** renders when `assetManager.mixManager.totalEntries == 0`
  (wired at the bottom of `main.swift`, just before the main loop). It must stay
  asset-free — SDL primitives and the built-in 5x7 font only — because it is what a
  first launch shows before anything is extracted, and a Finder-launched app has no
  stdout to print diagnostics to. Its RETRY re-runs discovery in place. Adding
  punctuation to `TextRenderer`'s glyph table was part of this: unknown characters
  render as a blank advance, so a path with `.` or `~` used to read as a hole.
- **`tools/make-app.sh`** vendors the SDL dylibs into `Contents/Frameworks`,
  rewrites their load paths to `@rpath`, ad-hoc signs (required on Apple Silicon
  after `install_name_tool` edits), and smoke-tests the bundle with
  `--test-synthetic`. Two traps it handles, both of which cost real time to
  diagnose: `brew install sdl2` now installs **sdl2-compat**, which `dlopen`s
  libSDL3 at runtime where `otool` cannot see it; and brew's lib dirs are symlink
  chains into `../Cellar`, so a link copied with `cp -a` dangles inside the bundle —
  sdl2-compat then fails to find SDL3 and raises a **modal NSAlert from a library
  initializer**, hanging the process forever with no output. Use `cp -L`.

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
./.build/debug/TiberianDawnMax --test-initteams                  # ASSET-FREE: InitNum-at-start ruleset-gated (Gap #7) — runs in CI
./.build/debug/TiberianDawnMax --test-enemy-superweapon          # ASSET-FREE: enemy trigger-granted Nuke/Ion fires at player (Gap #5) — runs in CI
./.build/debug/TiberianDawnMax --test-eventparity                # ASSET-FREE: Built It / NoFactories / destroyed-scan fidelity (Gap #9) — runs in CI
./.build/debug/TiberianDawnMax --test-team-former                # ASSET-FREE: AI Suggested_New_Team priority/cap/alerted scoring (Gap #6) — runs in CI
./.build/debug/TiberianDawnMax --test-prebuilt                   # ASSET-FREE: IsPrebuilt team-demand production gating (#6C) — runs in CI
./.build/debug/TiberianDawnMax --test-campaign-graph             # ASSET-FREE: CountryArray branching + GDI sabotage skip — runs in CI
./.build/debug/TiberianDawnMax --test-reinforcements             # ASSET-FREE: Edge= entry, team mission lists, loaner + limbo fidelity — runs in CI
./.build/debug/TiberianDawnMax --test-civ-evac                   # ASSET-FREE: civilian-evacuation win model (SCG11/SCG12) — runs in CI
./.build/debug/TiberianDawnMax --test-heli-transport             # ASSET-FREE: Chinook takeoff / single-speed flight / LZ slowdown / land / land-before-unload — runs in CI
./.build/debug/TiberianDawnMax --test-ai-gating                  # ASSET-FREE: enhanced enemy-AI layer OFF under classic1995 — runs in CI
./.build/debug/TiberianDawnMax --test-original-targeting         # ASSET-FREE: classic target acquisition, retaliation, base-attack rescue — runs in CI
./.build/debug/TiberianDawnMax --test-command-replay             # ASSET-FREE: orders queue, log, and replay exactly — runs in CI
./.build/debug/TiberianDawnMax --test-harvester-economy          # ASSET-FREE: silo capacity frees up as credits are spent — runs in CI
./.build/debug/TiberianDawnMax --test-triggers-ex                # ASSET-FREE: multiple actions per trigger ([TriggersEx]) — runs in CI
./.build/debug/TiberianDawnMax --ai-parity    <SCEN> <ticks>      # B3: assert the AI decide() phase is pure (no RNG/world mutation)
./.build/debug/TiberianDawnMax --ai-trace     <SCEN> <ticks>      # B3: print the per-house goal/decision stream each decide tick
./.build/debug/TiberianDawnMax --test-flags   <SCEN>             # Tier-1: per-instance invulnerable / must-survive flags
./.build/debug/TiberianDawnMax --test-repair  <SCEN>            # a player vehicle drives to a FIX and heals
./.build/debug/TiberianDawnMax --test-crush   <SCEN>            # a tank squishes enemy infantry at a chokepoint
./.build/debug/TiberianDawnMax --test-fogpath <SCEN>           # player plans through unexplored, reroutes on discovery
./.build/debug/TiberianDawnMax --test-stacking <SCEN>          # units ordered to one point don't stack on a cell
./.build/debug/TiberianDawnMax --editor-roundtrip <SCEN>         # E1: scenario load→document→INI→reload is faithful, idempotent, edit-safe
```

e.g. `--headless SCG01EA 600` or `--determinism SCG01EA 2500`. The determinism
check is the regression net for AI/pathfinding work: a change that perturbs the
simulation shows up as a changed digest. (Other diagnostic flags: `--test-mix`,
`--dump-scenario <NAME>`, `--test-gfx` / `--dump-gfx NAME OUTDIR [PAL]` for the
CPS/WSA/PAL decoders — `Headless/GfxDiagnostics.swift`.) Implementation: `TiberianDawnMax/Headless/GameHeadless.swift`
(scenario-backed tools) and `OpenConquerCore/SelfTests/` (the ASSET-FREE self-tests).

**`swift test`** runs every ASSET-FREE self-test above (incl. `--test-synthetic 500`,
plus `--test-two-event` / `--test-regions`) as an XCTest case in
`Tests/OpenConquerCoreTests`; this is what CI runs. The `--test-*` flags call the same
Core functions. The tests share the `session` / `forcedGameSeed` / `gameRng` globals, so
don't run them with `--parallel`. A new asset-free self-test goes in
`OpenConquerCore/SelfTests/` as a `package func ... -> Int32` plus a test case; one that
loads a scenario from MIX stays in `GameHeadless.swift` behind a CLI flag.

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
  values (as of 2026-10-02, **default ruleset = `classic1995`, veterancy OFF,
  enhanced enemy AI OFF**):
  SCG01EA 2500t `0x9CC893509D34122A`, 4000t `0xFE87053AB1F51FFF`,
  SCB01EA 4000t `0x4BD118CA4072F594`.
  All three changed (from `0x6F23B2EEA84E59F6` / `0x61141BE711B8B2CD` /
  `0xE824320DE6F2C796`) when target acquisition was ported to the original
  (`Ruleset.originalTargeting`, ON in `classic1995`): the computer sees the
  player's units through shroud (Evaluate_Object), guard scans weapon range,
  area guard twice it from home with a 1-cell leash and no wandering, hunt the
  whole map, a hit computer unit hunts its attacker (FootClass::Take_Damage),
  unarmed buildings and harvesters call rescuers (Base_Is_Attacked), the
  player's commando holds fire in guard, the periodic aggro scans in `tickAI`
  no longer run, and BGGY/BIKE sight is 2. Covered by
  `--test-original-targeting`.
  Both SCG01EA digests changed (from `0x70572C2165FB3BBC` / `0xB3E6E8566D689265`)
  when the hovercraft (LST) beach landing was ported to classic fidelity:
  UDATA.CPP stats (MPH_MEDIUM_FAST, unarmed, 400 hp), the Calculated_Cell
  SOURCE_BEACH column pick with an off-map entry and a straight run in
  (`beachLandingCell`), all cargo unloading at once from the deck spots at
  half speed, a tether wait, and the exit off the south edge
  (`tickHovercraftUnload`). SCG01EA's opening reinforcement is a hovercraft,
  so its run diverges; SCB01EA has none in-window and didn't move.
  All three digests changed (from `0xD188B0F93C6A9815` / `0xCDD2FC25630E52F8` /
  `0xD0A4B022F77129B4`) when the enhanced (non-classic) enemy-AI layer became
  a ruleset toggle that is OFF in `classic1995` (`Ruleset.enhancedEnemyAI`):
  rally raids, idle-army attack waves, the 5-minute hunt escalation, the
  tactics suite, damaged-unit retreat, the 3-minute production auto-enable
  timeout, the personality-pool production fallback, and free-form base
  building no longer run — classic campaign AI is trigger/teamtype-driven
  only (HOUSE.CPP:1892). The faithful paths (guard/turret target acquisition,
  hunt, the Suggested_New_Team former, Suggest_New_Object demand production)
  are unchanged. Both baselines diverged because rally raids used to fire at
  tick 300 (and consume rally-jitter RNG). Covered by `--test-ai-gating`.
  Before that, all three changed (from `0xF13E3EEE6E4094CF` / `0xDC151F8FFFD544C2` /
  `0x0712535052A6CB00`) when reinforcement delivery was ported to REINF.CPP
  fidelity: reinforcement teams now enter from the owning house's `Edge=`
  (seeded random edge-cell pick, `calculatedEdgeCell`), get a force-active
  team that executes the TeamType mission list (previously: spawn east, walk
  to waypoint 25), transports are loaners only when carrying cargo
  (transport-only teams like SCG12's evac chopper survive), team-less
  fixed-wing (A10) hunts, and limboed cargo is untargetable. Both baseline
  missions fire `Reinforce.` triggers in-window (SCG01EA RNF1@3, SCB01EA
  rnf1@2), so their runs diverge. See `GameReinforcements.swift`.
  The SCG01EA digests earlier changed (from `0x368A0F41B0BFC746` / `0x2220AD679F47F1A9`)
  when cosmetic damage-state fire animations stopped dealing real damage —
  they were finishing off crippled vehicles/structures mid-battle (classic
  on-building flames are decoration; only gameplay fire like napalm burns).
  The same change plus a tiberium-tie-break fix (equidistant cells now resolve
  by lowest cell index, not Set hash order) made SCB08EA/EB and SCB11EA/EB
  pass `--determinism` for the first time.
  Before that, all three changed when the classic INI mission spelling "Area Guard"
  (MISSION.CPP:464) became parseable — scenario units with that initial
  mission previously downgraded silently to plain Guard and now get the
  pursue-and-return `guardArea` behavior.
  Before that, the SCG01EA digests changed from `0xF2FC92976A82C252` / `0xF8D1E05941A069C1`
  when Data=0 time triggers were fixed to fire on their first check (classic
  decrement-before-test, TRIGGER.CPP:374-380): SCG01EA's `ATK2` (Time,Create
  Team,0) now actually spawns its Nod attack team. 13 campaign variants were
  affected by that bug, incl. SCG07EA/SCG15EA auto-losing at tick ~151.
  SCG01EA 4000t changed from `0xC645B24188C4D2CC` when the AI team-creation model
  (Gap #6) replaced the old flat every-675-tick autocreate pick with the faithful
  Suggested_New_Team former: once the GDI-vs-Nod AI's production enables mid-mission
  it now forms a priority-scored team, which perturbs the run after ~2500t (the
  2500t digest is unchanged; SCB01EA didn't move — its AI forms nothing in-window).
  See `GameAITeamFormer.swift`.
  SCB01EA 4000t earlier changed from `0xD46F9A67468411FF` when the
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

- **Three modules** (see `Package.swift`), each depending only on those above:
  - `OpenConquerAssets` — archive and file formats (MIX, SHP, ICN, INI, AUD).
  - `OpenConquerCore` — the simulation: data tables, rules, scenarios. **Never
    imports SDL** and never touches rendering, audio or UI state; the compiler
    enforces it. It talks outward only through narrow seams: `audioManager`
    (the `SimAudio` protocol, silent by default), the `eventBus` (e.g.
    `.ionCannonStrike` for screen effects), and the `saveView` camera hooks.
  - `TiberianDawnMax` — the app: SDL, rendering, audio, UI, headless harness.
  Cross-module declarations use `package` access. New Core code that the app
  calls must be `package` (an implicit memberwise init stays internal: spell
  it out as a `package init` when the app constructs the type).
- **Simulation state:** a global `session: GameSession`
  (`OpenConquerCore/Game/GameSession.swift`) owns all mutable sim state:
  - `session.world` → `GameWorld` (objects, map, occupancy) — `Game/GameState.swift`
  - `session.production` → build queues / sidebar
  - `session.scripting` → triggers, AI, teams
  - `session.combat` → projectiles, animations, superweapons
  - `session.campaign` → mission progression
  App-only state (current screen, menus, frame clock) is `app: AppState`
  (`TiberianDawnMax/App/AppState.swift`); the sim never refers to it.
- **Player commands:** input never edits the world. Clicks and keys become a
  `PlayerCommand` (`OpenConquerCore/Game/PlayerCommands.swift`) passed to
  `issue(_:)`; `gameTick` applies the queue first thing and appends each to
  `world.commandLog` with its tick. Seed + log replays a game exactly
  (`--test-command-replay`). New orders get a case there, not direct mutation
  from UI code. UI-only state (selection, modes, placement cursor) stays in UI.
- **Game objects** are a single `GameObject` **class** (reference type) in
  `Game/GameState.swift`. Behavior is attached via `extension GameObject` blocks
  spread across many files (missions, combat, economy, movement, animation).
- **Fixed-tick loop:** the sim runs at a fixed **15 FPS** (`Game/GameLoop.swift`),
  decoupled from render FPS via an accumulator in `App/FrameClock.swift`, which
  also sets the presentation up whenever the sim builds a new world. Rendering
  interpolates between ticks. `gameTick()` is the one discrete update: occupancy
  rebuild → fog → per-object mission ticks → AI → triggers → tiberium growth →
  remove dead.
- **Deterministic:** all *simulation* randomness flows through the seeded
  `gameRng` (see Conventions); same seed + same inputs → identical run, across
  processes and across two `initGameWorld` calls in one process. The headless
  harness guards this.

## Folder map (`Sources/`)

| Folder | What's there |
|--------|--------------|
| `OpenConquerAssets/` | MIX/SHP/ICN/INI/AUD/CPS/WSA/PAL parsers (shared LCW + XOR-delta in `WestwoodCodec`), asset manager |
| `OpenConquerCore/Data/` | static type tables: units, buildings, infantry, aircraft, weapons, houses, sound IDs, facing tables |
| `OpenConquerCore/Game/` | all simulation: loop, state, missions, AI, combat, economy, map/pathfinding, triggers, teams, save/load, campaign |
| `OpenConquerCore/Scenario/` | INI scenario + map loaders |
| `TiberianDawnMax/App/` | app state, frame clock, input, event handling, perf, window, settings |
| `TiberianDawnMax/Rendering/` | `GameRenderer` (in-game), `MapRenderer` (scenario/map view), effects, cursor, text, remastered sprites |
| `TiberianDawnMax/UI/` | menus, sidebars (classic + modern), in-game input |
| `TiberianDawnMax/Audio/` | audio engine, sound library, unit voices |
| `OpenConquerCore/SelfTests/` | asset-free self-tests (run by `swift test` and the `--test-*` flags) |
| `TiberianDawnMax/Headless/` | headless harness and scenario-backed self-tests |

Key files to know: `Game/GameState.swift` (object model + Mission enum),
`Game/GameLoop.swift` (tick + `moveOneStep`), `Game/GameMap.swift` (pathfinding +
`buildPassabilityMap`), `Rendering/ObjectSpriteRenderer.swift` (`pickStructureFrame`),
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
  `Rendering/MapRenderer.swift`, `Game/GameSaveLoad.swift`, `Game/GameAI.swift`,
  `Game/GameMissions.swift`, `Game/GameReinforcements.swift`. `GameRenderer.swift`
  is mostly the one ordered `renderGame` pass list; split it by pass, not by line.)
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
