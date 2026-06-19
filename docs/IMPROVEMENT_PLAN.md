# TiberianDawnMax — Improvement Plan & Fix Designs

_Last updated: 2026-06-16. Based on a read-through of the codebase against the
original Westwood C++ source. All file:line references verified at time of writing
— re-check before editing, line numbers drift._

This doc has two parts:
- **Part A — Bug fixes** (the three known issues), with root cause + design.
- **Part B — Foundation & feature roadmap** (what to shore up to enable smarter
  AI and a mission planner).

A suggested ordering is at the end.

---

## Part A — Bug fixes

> **Status (2026-06-16):**
> - A1 (harvester docking) and A2 (building damage frames) implemented; build
>   clean; pending in-game visual confirmation.
> - B1 (seeded RNG) and B2 (headless harness) **done and verified**: the sim is
>   deterministic across separate processes (`--determinism SCG01EA 2500` passes
>   3/3 trials). See `Game/GameRandom.swift`, `Game/GameHeadless.swift`.
> - F1 (session state leak between worlds) **fixed and verified** — see below.
> - A3 (land-type/passability) **core done** — per-cell `LandType` ported from the
>   original `CDATA.CPP` (all 216 templates incl. per-icon exceptions) now drives
>   passability, so cliffs/slopes (`LAND_ROCK`), boulders, and water correctly
>   block ground units. Verified: determinism + reset-check still pass; 5
>   scenarios across all 3 theaters run healthily; AI harvester economy still
>   works (harvesters path to fields and dock). Remaining A3 stage 2 (speed-cost
>   weighting in A*) deferred — see follow-up F3.
> - B3/B4 design: a vetted, phased implementation plan was produced (multi-agent
>   design pass) and saved to **docs/B3_B4_PLAN.md** (Part C). B3 = scored-goal
>   single decider (pure decide / effectful apply, behind a flag, migrated with
>   parity gates); B4 = separate EditorScenario document.
> - **B3-P0 done + verified:** the per-AI-house loops that advance the sim now
>   iterate in sorted `House.rawValue` order (7 sites in GameAI/GameAITactics/
>   GameSuperWeapons), closing a latent multi-AI nondeterminism hazard. Behavior
>   identical for single-AI campaign missions; determinism + reset-check green.
> - **B3-P1 done + verified:** inert scaffolding landed — `Game/GameAIBrain.swift`
>   (AIGoal/ScoredGoal/AIDecision/AIBrain types, `aiUseGoalLayer=false` flag, pure
>   `decide`/effectful `apply` skeletons, `isAIHouse`, `deriveDecideSeed`),
>   `aiBrain` on HouseState, and harness flags `--ai-parity` (proves `decide()`
>   purity) + `--ai-trace` (decision stream). Digest byte-identical to B3-P0
>   (`0x76C4D7D28B207A08`); ai-parity PASS (20 probes), reset-check green. Nothing
>   wired into live `tickAI()` yet — that begins in B3-P2.
> - **B3-P2 done + verified:** production migrated to the decide/apply split.
>   Pure `decideUnitBuild`/`decideInfantryBuild` return an `AIBuildPlan`
>   (`.forced` = no draw / `.weighted` = one draw / `.none`); effectful
>   `applyBuildPlan` is now the single site of the production RNG draw;
>   `aiPickStructure` renamed `decideStructureBuild` (already pure, no RNG). The
>   live pickers are thin shims (`applyBuildPlan(decide…())`). Digest at 2500t
>   byte-identical to baseline (`0x76C4D7D28B207A08`) — proving the draw
>   relocation is faithful; determinism PASS at 4000t (production-exercising):
>   SCG01EA `0xAD2FA4BFC4723E0A`, SCB01EA `0xC6BACBDF0518D5B7`. (Open decision
>   #1: gates accepted as proof; no separate manual draw-count audit performed.)
> - **B3-P3 done + verified:** attack/rally/escalation migrated to the
>   decide/apply split (Seams 2 & 4). Pure `decideAttackWave` (interval gate +
>   idle-unit gather + target pick → `AttackWavePlan`), `decideRally`,
>   `decideEscalation`; effectful `applyAttackWave` (delegates to
>   applyFlankingTactics — the per-unit flank RNG), `applyRally` (±48px jitter),
>   `applyEscalation`. Live functions are shims. Coarse plan structs (units+
>   target) used instead of fine-grained AIDecision lists, because the per-unit
>   flank RNG order can't be reshaped without changing the digest — fine-grained
>   mapping deferred to the P5 flag-flip. Digests byte-identical: 2500t
>   `0x76C4D7D28B207A08`, 4000t SCG `0xAD2FA4BFC4723E0A`, SCB `0xC6BACBDF0518D5B7`.
> - **B3-P4 done + verified:** tactics (recon/hit-and-run/harass/flank-follow-up)
>   migrated to the decide/apply split. Pure deciders: `decideRecon` (→ReconAction),
>   `decideHitAndRun` (→HitRunDecision, gate + management-independent target pick),
>   `decideHarass` (→HarassAction), `decideFlankFollowUp` (Bool gate). Effectful
>   appliers hold all RNG (scout-target ±360, retreatToBase ±24, flank jitter ±36)
>   and mutation. Key faithfulness call: hit-and-run *attacker* selection stays in
>   apply because the management phase can release units to idle and thus change
>   the eligible set — only the (enemy) target pick is hoisted to decide. Digests
>   byte-identical: 2500t `0x76C4D7D28B207A08`, 4000t SCG `0xAD2FA4BFC4723E0A`,
>   SCB `0xC6BACBDF0518D5B7`; reset-check + ai-parity green.
> - **B3 complete at parity (P5 reframed):** the decide/apply split was done
>   *in place* (the procedural tick functions call the pure deciders / effectful
>   appliers directly), validated by byte-identical digests at every step —
>   rather than as a parallel goal loop behind a flag. So P5's literal "flip the
>   flag" was moot: the `aiUseGoalLayer` flag gated nothing and was removed, and
>   the top-level `decide()`/`apply()` + goal vocabulary (AIGoal/ScoredGoal/
>   AIDecision) are now documented as the **reserved seam** for the next stage
>   (goal-scoring AI + B4 planner preview), exercised by `--ai-trace`/`--ai-parity`.
>   No behavior change; digests unchanged. The decide/apply layer — B3's actual
>   goal — is live and clean.
> - Still to do: smarter AI (populate the goal-scoring seam — make `decide`
>   real), B4-E0..E7 (see docs/B3_B4_PLAN.md), A3 stage 2 (F3).

### A1. Harvester docking animation (missing)  — ✅ implemented

**Symptom.** A full harvester drives to the refinery and the credits appear
instantly; there is no animation of it pulling into the bay, unloading, or backing
out.

**Root cause.** `tickHarvest()` (`Game/GameEconomy.swift:133-189`) is a teleport
deposit: once the harvester is within `dist < 14.0` of the dock cell it sets
`tiberiumLoad = 0`, banks the credits, and clears its move target in the same tick
(`GameEconomy.swift:150-171`). There is no docking sub-state, no unload duration,
and no render treatment. The `isTethered` flag that exists for exactly this
(`Game/GameState.swift:177`) is **only ever touched by save/load** — every
reference is in `GameSaveLoad.swift` / `GameCampaign.swift`, never set during the
sim.

The original engine drives this through a radio handshake (`RADIO_DOCKING` →
`RADIO_BACKUP_NOW` → `RADIO_TETHER`, see `CnC_Tiberian_Dawn/TECHNO.CPP:650-667`,
`FOOT.CPP` `Mission_Enter`). **We do not need to port the radio protocol** — a
local state machine on the harvester is the pragmatic equivalent.

**Design.**

1. Add a docking phase to the harvester. Either a small enum stored on the object
   or reuse the existing `Mission` values:
   - `.harvest` (in field) → on full, set `.enter` and path to the dock cell.
   - On arrival (`dist < 14.0`): enter a **Docked** phase — set `isTethered = true`,
     stop movement, start an `unloadTimer` (e.g. unload `N` units of load per tick
     so a full 20-load harvester takes ~1–1.5s, matching the original's metered
     unload rather than an instant dump).
   - When `tiberiumLoad == 0`: **Backing out** phase — set `isTethered = false`,
     path one cell out (south of the bay), then return to `.harvest`.
2. Store unload progress so credits accrue over the unload, not in one lump
   (the current lump-sum logic at `GameEconomy.swift:152-168` becomes per-tick).
3. **Rendering** (`Rendering/GameRenderer.swift`, unit-draw path ~`:375-461`):
   when `isTethered` and docking at a PROC, apply a small fixed sprite offset so
   the harvester visually seats into the refinery bay (the original nudges it
   onto the bay door). Keep the offset data-driven (a per-building "dock offset").
4. Optional polish: PROC has an animated bay; check `Game/GameAnimation.swift` for
   an existing refinery-door animation hook to sync with the unload phase.

**Touch points.** `Game/GameEconomy.swift` (state machine + metered unload),
`Game/GameState.swift` (a small `dockPhase`/`unloadTimer` field if not reusing
existing ones), `Rendering/GameRenderer.swift` (offset), maybe
`Game/GameAnimation.swift` (bay door).

**Risk.** Low. Self-contained to the harvester. Watch the interaction with
`findNearestRefinery()` (`GameEconomy.swift:268`) and multiple harvesters queueing
for one PROC — initially fine to let them stack at the dock; a proper queue is a
later refinement.

---

### A2. Building damage-state frames (not rendering)  — ✅ implemented

> **Refined root cause found during implementation:** there's a *third*, larger
> cause beyond the two below. `getObjectTexture` (`MapRenderer.swift:302-308`)
> returns the **remastered HD PNG** sprite early and **never populates
> `objectSHPCache`**. So any building that has a remastered manifest had
> `frameCount == 0` *permanently* and never showed damage — while buildings
> without an HD manifest fell through to classic SHP and worked. That asymmetry
> is almost certainly the "*some* buildings are broken" the report describes.
> Fix shipped: a `remasteredFrameCount()` accessor (`Assets/RemasteredSprites.swift`)
> that reads the count from the preloaded manifest; `pickStructureFrame` now
> sources the count from the manifest first, then the classic cache; and the
> classic cache is warmed before selection for non-HD buildings.
> Still open: validate the `frameCount-2` / `+64` turret heuristics against real
> sprite frame counts (needs running with assets), and the `MapRenderer:635`
> preview hardcode is left as-is (scenario structures are placed at full health).


**Symptom.** Buildings don't switch to their damaged sprite (smoke/sparks/cracked
frames) at <50% health, or only do so inconsistently.

**Root cause (two confirmed issues).**

1. **SHP cache is cold when the frame is chosen.** `pickStructureFrame()`
   (`Rendering/GameRenderer.swift:32`) decides the damaged/rubble frame from
   `frameCount = renderState.objectSHPCache[upper]?.frames.count ?? 0`
   (`:41`). But the cache is only pre-warmed for buildings that are *animating
   their build-up* (`buildUpFrame >= 0`, `GameRenderer.swift:320-339`). For a
   normal, already-built structure the cache is empty at `:342`, so `frameCount`
   is `0`, every damage branch fails (`frameCount >= 2` at `:65`, the turret
   `frameCount >= base + 64 + 1` at `:52`), and it returns the healthy frame. The
   cache is only filled afterward by `getObjectTexture()` at `:344` — too late for
   this frame.
2. **Map/scenario renderer bypasses the logic entirely.** `MapRenderer.swift:635`
   hardcodes `frame: 0` for structures, so the scenario/editor view never shows
   damage.

**Lower-confidence, verify with assets.** The turret-damage branch
(`GameRenderer.swift:43-55`) assumes the SHP holds 128 frames (64 healthy + 64
damaged) and the simple branch assumes the damaged frame is `frameCount - 2`. If
the extracted GUN/SAM/other sprites don't actually have that layout, damage frames
won't appear even with a warm cache. Confirm real frame counts (dump
`objectSHPCache[name].frames.count` for each building) once issue #1 is fixed.

**Design.**

1. **Resolve frame count before selecting.** Refactor so `pickStructureFrame` is
   guaranteed a populated cache: either pre-warm the SHP for every rendered
   structure (not just build-up ones) by hoisting the load at
   `GameRenderer.swift:320-339` out of the `buildUpFrame >= 0` guard, or have
   `pickStructureFrame` load-on-demand and re-query. Prefer a single
   `ensureStructureSHPLoaded(name)` helper called before both the frame pick and
   the draw.
2. **Route MapRenderer through the same logic.** Replace the hardcoded `frame: 0`
   at `MapRenderer.swift:635` with the shared frame-selection (factor the health →
   frame mapping into a function both renderers call; the scenario view passes
   full health so it just shows the healthy frame, but damaged placements render
   correctly).
3. **Validate the frame-layout heuristics** against actual sprite data; encode the
   real per-building damaged/rubble frame indices in `Data/BuildingData.swift` if
   the uniform `frameCount-2` rule doesn't hold (the original keys this off
   `BData` / `Shape_Number`).
4. Cross-check building-attached smoke/fire animations in
   `Game/GameAnimation.swift` — those are separate from frame selection and should
   spawn when health crosses the damage threshold.

**Touch points.** `Rendering/GameRenderer.swift` (cache ordering + extract shared
selector), `Rendering/MapRenderer.swift:635`, possibly `Data/BuildingData.swift`
(real damage frame indices), `Game/GameAnimation.swift` (smoke/fire).

**Risk.** Low–medium. Confined to rendering; main risk is the frame-layout
assumption, which is why asset validation is part of the task.

---

### A3. Pathfinding over cliffs / slopes / boulders (no land-type model)

**Symptom.** Units path and move over impassable terrain — cliffs, slopes, rocks,
some water edges — that should block them.

**Root cause.** The original engine models terrain as: every cell has a
**`LandType`** (CLEAR/ROAD/WATER/ROCK/WALL/TIBERIUM/BEACH), every unit has a
**`SpeedType`**, and `Ground[LandType][SpeedType]` gives a movement cost where
`0 == impassable` (`CnC_Tiberian_Dawn/CONST.CPP:261-276`). LandType is computed
per cell from the template + icon index (with **per-icon exceptions** — e.g. a
slope template's cliff icons are ROCK while its path icons are CLEAR), with
overlays taking precedence.

The Swift port never built this layer:
- `buildPassabilityMap()` (`Game/GameMap.swift:92-205`) produces a boolean
  passability array by **hardcoding template *names*** — it blocks structure
  footprints, scenario `TERRAIN` objects, wall overlays, and water/shore/bridge by
  name prefix (`W1`/`W2`, `SH*`/`RV*`/`FALLS`/`FORD`, `BRIDGE*`). **Everything
  else falls through to passable** — including cliff/slope templates (`S*`),
  boulders (`B*`), and any rock baked into a template rather than placed as a
  TERRAIN object.
- A `groundData` speed table already exists in `Data/WeaponData.swift:243-251`
  but is **never consulted** by the pathfinder or movement.
- A* (`GameMap.swift:~508-652`) and the per-step move check only test the boolean
  array (`:621`), so anything mis-marked as passable is freely traversed.

**Correction to note:** trees placed as scenario `TERRAIN` objects **are** blocked
(`GameMap.swift:~113-120`); it's not "all trees." The real gap is template-baked
terrain and confirming the terrain-object list is complete.

**Design (incremental — can ship in stages).**

1. **Add `LandType` per cell.** Extend the template metadata (`Scenario/MapLoader.swift`
   `TemplateInfo`, currently just `icnName/width/height`) with `landType`,
   `altLandType`, and `altIcons` (the per-icon exception set), mirroring the C++
   `TemplateTypeClass`. Build a `cellLandType(cell) -> LandType` in `GameMap.swift`
   that resolves overlay → template+icon → default CLEAR.
2. **Drive passability from `Ground[land][speed]`.** Replace the name-based
   `buildPassabilityMap` with a derivation from `cellLandType` + the (now-used)
   `groundData` cost table. A cell is impassable for a unit when the cost is 0.
3. **Use real movement costs in A\*.** Feed `Ground[land][speed]` cost into the
   edge weight so units prefer roads, avoid slow terrain, and never enter cost-0
   cells. Update both the planner (`findPath`) and the per-step re-check.
4. **Stage it:** even just step 1+2 for the cliff/slope/boulder templates
   (the templates currently falling through) fixes the visible bug; full
   per-speedtype cost tuning can follow.

**Touch points.** `Scenario/MapLoader.swift` (template metadata + land-type
table), `Game/GameMap.swift` (`cellLandType`, rewrite `buildPassabilityMap`, A*
edge cost), `Data/WeaponData.swift` (wire up `groundData`),
`Data/GameTypes.swift` (`LandType`/`SpeedType` if not already complete).

**Risk.** Medium–high — it touches the most-exercised system. Strongly benefits
from the headless test harness (B2) existing first, so regressions are caught.
This work also directly improves AI movement and is a prerequisite for sane
AI positioning.

---

## Part B — Foundation & feature roadmap

These are ordered by how much they unblock your stated goals (smarter AI, mission
planner).

### B1. Seeded deterministic RNG  *(highest-leverage foundation)*

~60 raw `Int.random` / `Double.random` / `Bool.random` calls (`GameAI`,
`GameMissions`, `GameAITactics`, `GameCrate`, `GameLoop`, …) make the sim
non-deterministic. That blocks: replays, AI lookahead/planning, and a mission
planner that previews AI behavior.

- Add `GameSession.rng` (a small seedable PRNG — an LCG or xoshiro is fine) seeded
  from the scenario/save.
- Replace raw `.random` calls with `rng.next(...)`. Persist the seed + stream
  position in save/load.
- Verify with a replay test (B2): same seed + same input → identical tick stream.

### B2. Headless test harness  *(do before A3 and any AI refactor)*

No tests exist today. Add:
- A `--headless <scenario> <ticks>` CLI mode (or an XCTest target) that runs
  `gameTick()` N times with no SDL window and dumps object positions / credits /
  outcomes.
- 2–3 tiny scenarios (16×16) for fast assertions: a pathfinding-around-a-cliff
  case, an AI-produces-a-unit case, a determinism replay case.
This is the safety net for the pathfinding rewrite and AI work.

### B3. AI decision layer  *(enables "smarter AI")*

`tickAI()` (`Game/GameAI.swift`) is a procedural script and team behavior is a
fixed enum (`Game/GameTeam.swift`). To grow it without it becoming unmanageable:
- Extract a pure `decide(world, house) -> [AIDecision]` layer (no side effects),
  separate from the apply step. This makes AI testable (B2) and lets a planner
  *preview* decisions.
- Introduce a light goal abstraction (`enum AIGoal { defendBase, attackAt,
  expandHarvest, … }`) that decomposes into existing missions/teams, instead of
  adding more branches to `tickAI`.
- A simple threat/influence map (per-cell danger from known enemy positions +
  weapon ranges) drives positioning; reuse the cell grid already in `GameMap`.
Depends on B1 (determinism) + B2 (tests) to be safe.

### B4. Mission planner / editor  *(your other goal)*

Today scenarios load from INI into immutable structs (`Scenario/ScenarioLoader.swift`
→ `ScenarioData`) and `buildPassabilityMap` runs once. There's no reversible
authoring flow. To build a planner:
- Introduce an `EditorState` distinct from the live `GameWorld`: a mutable list of
  placements + an undo stack.
- Reversible ops: `place(type, cell) -> Result<…, PlacementError>`,
  `remove`, `move` — reusing passability/footprint validation but not mutating the
  running sim until "play."
- A versioned save format (`ScenarioData` v2 with metadata) and a round-trip
  back to INI so authored maps load through the existing pipeline.
- The land-type work (A3) makes placement validation correct (can't place on
  cliffs/water), so A3 is a soft prerequisite.

### B5. Ongoing cleanup (opportunistic, not blocking)

- Eliminate force-unwrap crash risks: `queue.item!` (`GameAI.swift:307,527`,
  `GameProduction.swift:209`), `wps.last!` / `selectSHP!` (`GameRenderer.swift`),
  `randomElement()!` (`GameCrate.swift`). Replace with guards.
- Split the largest files as they're touched (`GameCampaign` 1181, `GameRenderer`
  1344, `GameSaveLoad` 1091, `GameAI` 1066, `GameMissions` 991) — don't do a big
  refactor pass for its own sake; split along the seams you're already editing.
- Consider consolidating the two save systems (campaign vs mid-mission) behind one
  versioned format over time.

---

## Suggested ordering

1. **A1 Harvester docking** — visible win, low risk, self-contained.
2. **A2 Building damage frames** — small, render-layer only.
3. **B1 Seeded RNG + B2 headless harness** — the foundation everything else rests on.
4. **A3 Land-type / passability rewrite** — bigger; safer once B2 exists; also feeds AI.
5. **B3 AI decision layer**, then **B4 mission planner**.
6. **B5 cleanup** — continuous, alongside the above.

Rationale: ship two quick visible wins first, then lay the deterministic/tested
foundation, then take on the high-leverage-but-riskier pathfinding rewrite with a
net underneath it, and only then the large features — which both depend on the
foundation being in place.

---

## Open follow-ups (discovered during implementation)

### F1. Global state not reset between `initGameWorld` calls — ✅ FIXED
`initGameWorld` built a fresh `GameWorld` and reseeded the RNG, but the
long-lived `session` sub-containers were not cleared, so a new mission inherited
the previous one's state. Root causes found: `scripting.aiTickCounter` (drives
the AI's `%30`/`%60` scheduling — a stale value shifts the AI's entire tick
phase), `scripting.pendingReinforcements`, `combat.activeProjectiles` /
`activeAnimations` / `nextProjectileId`, and the player build queues + credits.
Fix: a reset block at the top of `initGameWorld` (`Game/GameInit.swift`) clears
all of these and defaults `sidebarCredits` from the scenario. Verified by the new
`--reset-check` command (in-process double-world) passing at 6000 ticks on both a
GDI and a Nod mission, with `--determinism` still green. This was a real campaign
bug (mission 2 inheriting mission 1's AI phase / in-flight projectiles), not just
a test artifact. Guarded against regression by `--reset-check`.

### F2. Building damage frame-layout heuristics unverified
A2 fixed *whether* damage frames are selected; it didn't verify the `frameCount-2`
/ turret `+64` indices against real sprite frame counts. Validate in-game (or dump
frame counts) and, if wrong for some buildings, encode explicit damage/rubble
indices in `Data/BuildingData.swift`.

### F3. A3 stage 2 — movement speed costs (deferred)
A3 stage 1 made terrain pass/block correct via per-cell `LandType`. The original
also varies *movement cost* by `Ground[land][speed]` (roads faster, etc.), and
the `groundData` table in `Data/WeaponData.swift` already encodes these costs but
is still unused by A* (`GameMap.findPath`) and per-step movement. Wiring those
costs into the A* edge weights would make units prefer roads and traverse rough
terrain slower — polish, not a correctness bug. Do after B-series if desired.
