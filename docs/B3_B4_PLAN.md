# Part C — B3 (AI Decision Layer) and B4 (Mission Editor): Implementation Plan

This section supersedes the one-paragraph sketches in B3/B4 above with a concrete, phased plan. It chooses one architecture per goal, grounded in the verified constraints of this codebase, and specifies the exact types, files, integration seams, and harness verification for every phase. **Every phase keeps the build green and `--determinism` / `--reset-check` passing.**

## Decisions up front (and why)

- **B3 = "scored-goal single decider" (Design A spine, with B's `--ai-trace` and utility scoring borrowed).** Design A maps onto the four existing seams (`aiPickVehicle/Infantry/Structure` already *return* rather than mutate; attack waves gather-then-act), is a 3-file addition rather than a ~19-file rewrite, and — decisively — keeps the `gameRng` draw inside the *apply* phase. Design B's `AIOrder.buildUnit(type: String)` bakes the chosen unit type into the order, which forces the weighted `rndInt` draw (`GameAI.swift:393`) into the supposedly-pure `plan()` and scatters RNG advancement across 12 contributor-authored files in Dictionary-iteration order. That is the single biggest determinism hazard and B's own examples violate its own purity rule. We adopt A, and fold B's per-behavior *utility scoring* into A's `refreshGoals` (one decider, scored goals) so we still get the B4 "explain the AI" surface, plus B's `--ai-trace` flag.

- **B4 = "separate EditorScenario document" (Design A spine), with one mandatory refactor.** Verified this session: structure passability is rebuilt from the **immutable global `scenarioData`** (`GameMap.swift:98-112`), `updateOccupancy()` **excludes structures** (`GameMap.swift:216-217`), and `cellHasVehicle` matches only `.unit` (`GameMap.swift:231`). Design B's headline claim — "edit the live world, validate against live occupancy, it's the real runtime check" — is therefore **factually false**: structures are never in the occupancy grid, and the real structure-passability authority (`scenarioData` + `landPassability`) is exactly what B leaves stale while editing live objects. To be correct, B must maintain a parallel `scenarioData`-shaped model anyway — which *is* Approach A. B also requires a `gameTick()` guard and a `GameObject.editorId` intrusion that threaten the determinism foundation for no real payoff. We adopt A. We borrow B's render-parity idea (read-only) and its "test from here" UX, but implement the playtest A's way (`compile → initGameWorld`, full seed+reset), never B's half-init.

## Cross-cutting prerequisite (Phase 0 for B3) — fix the latent Dictionary-iteration hazard

`--determinism` passes today only because single-player TD missions are one player + one AI house, so `for (house, state) in session.houseStates` has N=1 and iteration order is moot. The moment a 2-AI scenario (`multi*`/skirmish) exists, the six RNG-drawing loops at `GameAI.swift:250,515,541,913,1038` and `GameAITactics.swift:40` diverge across the 3 subprocesses `--determinism` runs. `House` is `enum House: String, CaseIterable` (`ScenarioLoader.swift:47`) — trivially sortable. This must be fixed **before** any per-house decision layer lands, as the very first increment.

---

## 1. B3 — Chosen architecture: scored-goal single decider with pure decide / effectful apply

### 1.1 Core shape

`tickAI()` is split, per AI house, into a **pure `decide`** (reads world/house/brain, emits `[AIDecision]`, advances *no* global `gameRng`, mutates *nothing*) and an **effectful `apply`** (the only site that mutates objects/queues/roles and advances `gameRng`, in the same count and order as today). A per-house `AIBrain` holds *scored goals*; goals decompose into the missions/teams the sim already supports.

### 1.2 Concrete Swift types

New file `Game/GameAIBrain.swift`:

```swift
enum AIGoal: Equatable {
    case defendBase
    case attackAt(cell: Int)
    case expandHarvest
    case scout(targetCell: Int)
    case harass(targetUnitId: Int)
    case buildUp(focus: BuildFocus)
    case rally
    case hunt
}
enum BuildFocus: Equatable { case economy, military, defense, tech }

struct ScoredGoal: Equatable {
    var goal: AIGoal
    var score: Double          // [0,1]; used for selection AND the B4 "why" panel
    var createdTick: Int
    var expiresTick: Int       // 0 = standing
}

/// Pure output of decide. Apply turns each into the exact mutation done today.
/// Equatable so --ai-trace and the parity harness can diff decision lists.
enum AIDecision: Equatable {
    // Production — note: candidate set, NOT a pre-chosen type, so the weighted
    // rndInt draw stays in apply (digest-preserving; see 1.5).
    case enqueueUnit(candidates: [BuildCandidate])
    case enqueueInfantry(candidates: [BuildCandidate])
    case enqueueStructure(typeName: String, cost: Int, buildTime: Int) // structure pick is deterministic ladder, no weighted draw
    // Movement / combat (by object id, never object refs)
    case orderAttack(unitId: Int, targetId: Int)
    case orderMoveTo(unitId: Int, x: Double, y: Double, then: Mission)
    case orderMission(unitId: Int, mission: Mission)
    case assignRole(unitId: Int, role: AITacticalRole, engageTick: Int?)
    // House-memory writes apply performs on the brain's behalf
    case recordEnemySighting(x: Double, y: Double, typeName: String)
}

struct BuildCandidate: Equatable { let name: String; let weight: Int; let cost: Int; let buildTime: Int }

struct AIBrain: Equatable {
    var goals: [ScoredGoal] = []
    var lastDecideTick: Int = 0
    // Derived each decide tick from (world.randomSeed, house, tick window); NOT persisted.
    // Used only for decide-phase tie-breaks via a LOCAL GameRandom; never the global gameRng.
}
```

> **Resolution of a contradiction in the upstream Design A:** the decide RNG sub-stream is *derived* every decide tick from persisted inputs, so it is **not** stored in `AIBrain` and **not** threaded through save/load. (Design A both reseeded it each tick and persisted it — incoherent. We derive, don't persist.)

### 1.3 State ownership & F1 reset

Add to `HouseState` (`Game/GameHouse.swift`):

```swift
var aiBrain = AIBrain()
```

This is auto-reset per world: `initHouseStates()` (`GameHouse.swift:223`) does `removeAll()` then recreates fresh `HouseState`s, so a default-initialized stored property is reset with no new `GameInit.swift` line — the same mechanism that already makes `aiKnownEnemyPositions`, `aiUnitQueue`, etc. safe. **No session-level AI state is added**, so there is no F1 footgun. Per-unit transient state stays on `GameObject` (`aiTacticalRole`, `aiHitAndRunTick`). Save/load is mechanical (value types ride existing `HouseState` serialization); since `decideRngState` is derived not stored, there is nothing extra to persist.

### 1.4 Exact `tickAI()` integration seams

Target end state (behind `aiUseGoalLayer`, default off until parity proven):

```swift
func tickAI() {
    guard let world = session.world else { return }
    session.aiTickCounter += 1
    let tick = session.aiTickCounter

    tickAIProduction()            // per-tick queue advance — unchanged (mechanism, not decision)
    tickAIStructureProduction()

    guard aiUseGoalLayer, tick % 30 == 0 else { /* old procedural body when flag off */ return }

    // DETERMINISTIC house order — the Phase-0 fix. Never raw Dictionary order.
    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue })
        where isAIHouse(house, world) {
        let state = session.houseStates[house]!
        let seed = deriveDecideSeed(world.randomSeed, house, tick)   // pure
        let decisions = decide(world: world, house: house, state: state,
                               brain: state.aiBrain, seed: seed, tick: tick)  // PURE
        apply(decisions, world: world, house: house, state: state, tick: tick) // mutates + advances gameRng
    }
}
```

Seam mapping (each is an incremental migration target, §3):

| Today | Becomes |
|---|---|
| `aiPickVehicle/Infantry` (`GameAI.swift:326,410`, draw at `:393`) | `decideUnitBuild/decideInfantryBuild` return `[BuildCandidate]`; **apply** does the single `rndInt(0..<totalWeight)` draw and enqueues |
| `aiPickStructure` (`:578`, deterministic ladder) | `decideStructureBuild` returns the chosen type (no RNG); apply enqueues |
| `tickAIAttackWaves` (`:913`) | goal `attackAt`; `decideAttackWave` returns `orderAttack/orderMoveTo/assignRole`; apply mutates `mission/attackTarget/moveTargetX,Y` and sets `aiLastAttackTick` |
| `tickAITactics` (`GameAITactics.swift:37`) | goals `scout/harass`; `decideTactics` returns `assignRole+orderMoveTo`; the 90/60/15-tick gates become pure predicates over `state.aiLast*Tick` vs `tick` |
| `rallyEnemyUnits`/`escalateAI` (`GameAI.swift`) | goals `rally`/`hunt`; pure predicates `shouldRally/shouldEscalate` |

`tickTeams()` (`GameTeam.swift`, called from `GameLoop.swift:87`) is **untouched** — squads stay parallel.

### 1.5 Determinism rules (the linchpin)

1. **decide never touches the global `gameRng`.** Tie-breaks draw from a *local* `GameRandom` seeded from the derived `seed`. This keeps decide pure even when the B4 planner previews it.
2. **apply is the only place the global `gameRng` advances, in the same count and order as today.** The picker-returns-candidates / apply-does-the-draw split (1.2/1.4) is what preserves the digest: today `aiPickVehicle` does one `rndInt(0..<totalWeight)` at `:393`; the migrated apply does exactly one, over the same candidate set. Moving, duplicating, or reordering a draw changes the digest.
3. **House iteration is sorted by `rawValue`** everywhere a per-house decision draws RNG (Phase 0).

### 1.6 Harness verification for B3

- **Inert-scaffolding gate:** after adding `AIBrain` (flag off), `--determinism SCG01EA 2500` and `--reset-check SCG01EA 600` digests must be **byte-identical** to pre-change.
- **`--ai-parity <SCEN> <ticks>`** (new in `GameHeadless.swift`): each decide tick, run both the procedural decision and `decide(...)` over the same snapshot and assert the order sets are `==` (free via `Equatable`). Fails loudly on first divergent `(house, tick)`.
- **`--ai-trace <SCEN> <ticks>`** (borrowed from Design B): prints `tick | house | goal | score | decisionCount`; deterministic, localizes divergence better than an end-state digest, and is the data the B4 "why" panel consumes.
- **Re-baseline gate:** when flipping `aiUseGoalLayer` on, run `--determinism` (3 subprocesses must agree → the goal layer is itself deterministic), then deliberately record the new digest as the post-B3 baseline.
- **Save→reload→continue digest** mode added to the harness to prove `HouseState.aiBrain` serializes (run T, save, reload, run T, compare to uninterrupted 2T).

---

## 2. B4 — Chosen architecture: separate `EditorScenario` document

### 2.1 Core principle

The editor never mutates a `GameWorld` and never enters `gameTick()`. It owns a mutable `EditorScenario` (a 1:1 superset of immutable `ScenarioData`). Play-test/preview produce a frozen `ScenarioData` via `compile()` and hand it to the existing `initGameWorld(scenario:scenarioName:)` (`GameInit.swift`), which reseeds `gameRng` and runs the full F1 reset (`:98-117`). This carries **zero** determinism/reset risk because the editor is outside the tick loop and `gameTick()` is never guarded or branched.

### 2.2 Concrete types (new `Scenario/EditorScenario.swift`, `Scenario/EditorCommand.swift`, `Scenario/INIWriter.swift`)

```swift
enum EditorObjectKind { case structure, unit, infantry, terrain, overlay }

final class EditorObject {          // reference type → stable identity for selection/undo
    let id: Int                     // editor-local, from EditorScenario.nextId — STABLE across undo
    var kind: EditorObjectKind
    var typeName: String
    var house: House
    var cell: Int                   // top-left footprint cell
    var facing: Int
    var strength: Int               // 0..256 C&C scale (matches ScenarioData)
    var subLocation: Int            // infantry
    var mission: String
    var triggerName: String?        // nil == "None"
}

struct EditorScenario {
    var theater: TheaterType
    var mapBounds: MapBounds?
    var credits: Int
    var buildLevel: Int
    var objects: [EditorObject] = []          // structures/units/infantry/terrain/overlay folded → uniform ops
    var waypoints: [Int: Int] = [:]
    var cellTriggers: [Int: String] = [:]
    var baseBuildings: [ScenarioBaseBuilding] = []
    var cells: [MapCell]                       // 4096, mirrors .BIN; edited in place → byte-identical round-trip when untouched
    var sourceINI: INIFile                     // passthrough for unmodeled sections ([Triggers],[TeamTypes],[Briefing])
    var nextId: Int = 1
    var formatVersion: Int = 1
}
```

Command stack (closure-pair do/undo, captures prior values for exact revert; compound ops = one `EditorCommand`):

```swift
struct EditorCommand { let label: String
    let apply: (inout EditorScenario) -> Void
    let revert: (inout EditorScenario) -> Void }
final class EditorHistory {
    private(set) var undoStack: [EditorCommand] = []
    private(set) var redoStack: [EditorCommand] = []
    var dirty: Bool { !undoStack.isEmpty }
    func run(_ c: EditorCommand, on doc: inout EditorScenario) { c.apply(&doc); undoStack.append(c); redoStack.removeAll() }
    func undo(on doc: inout EditorScenario) { guard let c = undoStack.popLast() else { return }; c.revert(&doc); redoStack.append(c) }
    func redo(on doc: inout EditorScenario) { guard let c = redoStack.popLast() else { return }; c.apply(&doc); undoStack.append(c) }
}
```

Session sub-container (add to `GameSession`, `App/GameSession.swift`):

```swift
final class EditorState {
    var doc: EditorScenario?
    var history = EditorHistory()
    var selection: Set<Int> = []
    var brush: EditorBrush = .select
    var clipboard: [EditorObject] = []
    var sourceName = ""
    var camera = EditorCamera()
}
let editor = EditorState()
```

**F1 reset inversion (document explicitly):** `session.editor` is reset on *editor entry* via `enterEditor(scenarioName:)`, and is **deliberately NOT** reset in `initGameWorld` — because a play-test (which calls `initGameWorld`) must leave the document intact so the user returns to it. This is the one place the F1 pattern is intentionally not applied; `--reset-check` is unaffected (it never enters the editor, and no editor state is in the world digest).

### 2.3 Mandatory refactor: pure passability (closes the validation-drift gap)

The editor must **not** re-implement passability. In Phase E0, refactor `buildPassabilityMap()` (`GameMap.swift:92-166`) into a pure function and have the existing global path call it:

```swift
func computePassability(structures: [ScenarioStructure], terrain: [ScenarioTerrain],
                        overlays: [ScenarioOverlay], cells: [MapCell],
                        bounds: MapBounds?, theater: TheaterType) -> (land: [Bool], water: [Bool])
// buildPassabilityMap() becomes: (landPassability, waterPassability) = computePassability(scenarioData...)
```

The editor's `validatePlacement(_:in:)` calls the **identical** function on the document's `structures/terrain/overlays/cells`, so a placement the editor calls valid is exactly what the sim's passability produces — no lookalike. Footprint size comes from the existing `buildingSize(typeName)`; buildability from `groundData[land].isBuildable`. Occupancy among editor objects is a static scan of `doc.objects` footprints (correct for authoring; the per-tick occupancy grid is not reused because it is dynamic and structure-excluding). Gate the refactor with `--determinism SCG01EA 2500` (digest byte-identical) before any editor code lands.

### 2.4 Serialize-back (verified correct)

- **INI:** `INIFile` is strictly read-only (`Assets/INIFile.swift:8-9`, private storage; only `entries/string/int/sectionNames`). Add standalone `INIWriter` that regenerates the owned sections (`[Basic] [MAP] [TERRAIN] [OVERLAY] [STRUCTURES] [UNITS] [INFANTRY] [WAYPOINTS] [CELLTRIGGERS] [BASE]`) and **passes through** all other sections from `doc.sourceINI` via the public `sectionNames`/`entries` API (order-preserving). No change to `INIFile`. Cross-check the `[Basic] Credits` /100 encoding against `ScenarioLoader`'s read before claiming fidelity.
- **.BIN:** exact inverse of `MapLoader.swift:38-42` — write `templateType` then `iconIndex` × 4096 = 8192 bytes. Because `doc.cells` is edited in place from the loaded array, untouched maps round-trip byte-identical.

### 2.5 UI insertion (matches the verified screen model)

`UI/EditorScreen.swift : MenuScreen` (protocol at `UI/MenuScreen.swift:6-9`). Entry: a "MAP EDITOR" button on `MainMenuScreen`, plus `E` from `MapViewerScreen` to import the currently-browsed scenario. Render composes: shared `renderScenarioLayers(...)` (extract the 4-pass body of `renderMapViewer` in `MapRenderer.swift` so viewer + editor share it), then selection outlines, then a green/red ghost preview (extract the existing highlight code at `GameSidebar.swift:865-901` into `renderPlacementPreview`), then a palette strip (reuse the sidebar button-grid + `getObjectTexture`), then toolbar. Input mirrors `PlayingScreen.handleMouseDown`'s region split (palette vs. canvas) and `MapViewerScreen` pan/zoom. Bindings: LMB select/place/paint, drag box-select/move, RMB delete, `R` rotate, `Del` delete, `Ctrl+Z/Y`, `Ctrl+C/V`, `G` grid, `Ctrl+S` save, `F5` play-test.

### 2.6 Play-test & AI preview

`F5`: `compile(doc) → initGameWorld(scenario:scenarioName:) → session.currentScreen = PlayingScreen()`. Full seed+reset, identical determinism to a normal load; `doc` survives because `initGameWorld` doesn't touch `session.editor`. AI preview (B3 dependency) reuses the headless tick loop on the compiled world and reads back per-house outcomes / the `--ai-trace` decision stream — never B's half-init.

---

## 3. Phased build order (every phase builds and keeps `--determinism` + `--reset-check` green)

**B3 first** (B4's AI preview depends on it; B3 also de-risks the Dictionary hazard early).

- **B3-P0 — Deterministic house iteration.** Replace the six `for (house, state) in session.houseStates` loops (`GameAI.swift:250,515,541,913,1038`; `GameAITactics.swift:40`) with `for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue })`. Add a 2-AI test scenario to the harness set. **Gate:** `--determinism SCG01EA 2500` unchanged; new 2-AI scenario now passes `--determinism`.
- **B3-P1 — Inert scaffolding.** Add `Game/GameAIBrain.swift` types, `var aiBrain = AIBrain()` on `HouseState`, `decide/apply` skeletons, `var aiUseGoalLayer = false`, and `--ai-trace`/`--ai-parity` harness flags. Flag off → old body runs. **Gate:** digests byte-identical; `--reset-check` clean.
- **B3-P2 — Migrate production (Seam 1).** `decideUnitBuild/decideInfantryBuild` return `[BuildCandidate]`; `decideStructureBuild` returns the ladder pick; apply does the single weighted draw. Migrate one picker at a time, each gated by `--ai-parity`. **Note:** moving the `:393` draw from picker to apply is a *real* relocation of where `gameRng` advances — gate with `--determinism` (expect identical if faithful), not an "identical function" claim.
- **B3-P3 — Attack/rally/escalation (Seams 2 & 4)** behind parity, keeping the `% 30` cadence and RNG order (rally ±48px jitter draw stays in apply).
- **B3-P4 — Tactics (Seam 3):** scout/hit-and-run/harass/flank as scored goals; 90/60/15 gates become pure predicates.
- **B3-P5 — Flip `aiUseGoalLayer = true`, re-baseline the determinism digest, delete dead procedural branches** after a release of flag-on-green.
- **B4-E0 — Pure passability refactor** (§2.3). **Gate:** `--determinism SCG01EA 2500` byte-identical.
- **B4-E1 — Model + round-trip, headless, no UI.** `EditorScenario`, `compile()`, `INIWriter`, `serializeBIN`, and `--edit-roundtrip <NAME>` (load → compile → serialize → reload → compile → assert equal; assert untouched `.BIN` byte-identical). Verify `[Basic] Credits` /100.
- **B4-E2 — Commands + validation** (`EditorHistory`, place/move/remove/rotate, `validatePlacement` via `computePassability`). Headless test: apply N ops, full-undo, assert document equality.
- **B4-E3 — EditorScreen read-only** (extract `renderScenarioLayers`, render `doc`). Verify viewer unregressed.
- **B4-E4 — Palette + placement** (reuse sidebar grid + `renderPlacementPreview`, commit through E2 commands).
- **B4-E5 — Full editing UX** (selection, drag-move, multi-delete, copy/paste, terrain paint, waypoint/cell-trigger tools, undo/redo, save + `dirty` prompt).
- **B4-E6 — Play-test handoff** (`F5 → compile → initGameWorld`; Esc back to intact editor).
- **B4-E7 — AI preview** (depends on B3): headless run on compiled world + decision-timeline overlay from `--ai-trace`.

## 4. The single smallest first increment (B3-P0), spelled out

**File:** `Sources/TiberianDawnMax/Game/GameAI.swift` (and one line in `Game/GameAITactics.swift`).
**What:** at the six sites listed, replace
`for (house, state) in session.houseStates {`
with
`for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {`
` guard let state = session.houseStates[house] else { continue }`
(keep the existing loop body verbatim — `house` and `state` are still in scope). `House` is `enum House: String, CaseIterable` (`ScenarioLoader.swift:47`), so `$0.rawValue < $1.rawValue` is a stable, process-independent ordering.
**Where it hooks in:** these are the only per-house loops that advance the global `gameRng` (weighted unit pick `:393`, attack-wave targeting `:913`, rally, tactics). Sorting them removes the latent cross-process nondeterminism that is currently masked only because campaign missions have one AI house.
**Default behavior preserved:** with one AI house (every shipping campaign scenario), the sorted order is identical to today's iteration, so the current AI behaves bit-for-bit the same.
**Test command to confirm:**
```
swift build && \
./.build/debug/TiberianDawnMax --determinism SCG01EA 2500 && \
./.build/debug/TiberianDawnMax --reset-check SCG01EA 600
```
Both must report identical digests / a clean reset, byte-identical to the pre-change run. (Then add a 2-AI scenario and confirm `--determinism` passes on it — proving the hazard is closed, not just masked.)

## 5. Open risks & decisions for the human

1. **RNG-draw relocation in B3-P2 is a genuine behavior-neutral-but-not-identical-code change.** Moving the weighted draw from inside `aiPickVehicle` (`:393`) to `apply` must produce the same draw count/order. Decision: accept the `--ai-parity` + `--determinism` gates as sufficient proof, or require a manual draw-count audit at that step?
2. **2-AI test scenario.** B3-P0's regression guard needs a `multi*`/skirmish scenario in the harness set. Does one exist/load cleanly headlessly today, or must one be authored first (chicken-and-egg with B4)?
3. **`[Basic] Credits` /100 convention** is unverified for the write path. Confirm against `ScenarioLoader`'s read before B4-E1 ships, else round-trip credits drift.
4. **Save/load of `HouseState.aiBrain`.** Goals carry no object refs (cells/ids only), so serialization is mechanical — but confirm the project wants mid-mission AI-goal state to survive save/reload (it should, for resume fidelity). Worth a save→reload→continue digest test in B3.
5. **Scope of B3 "smarter."** This plan delivers the *layer* and reproduces current behavior at parity; making the AI actually smarter (better `refreshGoals` scoring) is deliberately deferred behind the flag, post-parity, and re-baselined intentionally. Confirm that staging is acceptable vs. wanting visible behavior gains within B3 itself.
6. **`MapRenderer` frame bugs (CLAUDE.md issue #2 / F2).** B4's borrowed render-parity and the editor's structure-frame display inherit the existing `pickStructureFrame` bugs. Decision: fix F2 before B4-E3, or accept cosmetic inaccuracy in the editor until then?
7. **Unbounded `aiKnownEnemyPositions`** (expired only every 90 ticks). B3 goal scoring will read it more often; consider capping it as a small separate cleanup so the brain reads bounded memory.

Relevant files (absolute): `/Users/david/Projects/PERSONAL/Westwood/TiberianDawnMax/Sources/TiberianDawnMax/Game/GameAI.swift`, `.../Game/GameAITactics.swift`, `.../Game/GameHouse.swift`, `.../Game/GameInit.swift`, `.../Game/GameMap.swift`, `.../Game/GameState.swift`, `.../Game/GameHeadless.swift`, `.../Game/GameSidebar.swift`, `.../Rendering/MapRenderer.swift`, `.../Scenario/ScenarioLoader.swift`, `.../Scenario/MapLoader.swift`, `.../Assets/INIFile.swift`, `.../App/GameSession.swift`, `.../UI/MenuScreen.swift`, `.../docs/IMPROVEMENT_PLAN.md`.