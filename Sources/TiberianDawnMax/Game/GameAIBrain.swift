import Foundation

// MARK: - B3: AI decision layer (scored-goal single decider)
//
// This file is the *inert scaffolding* for the AI decision layer (B3-P1). It
// introduces the vocabulary the layer will speak in — scored goals and an
// Equatable list of decisions — plus a per-house `AIBrain` and the pure
// `decide` / effectful `apply` split described in docs/B3_B4_PLAN.md §1.
//
// Nothing here is wired into the live `tickAI()` path yet: `aiUseGoalLayer` is
// `false`, so the existing procedural AI runs unchanged and the world digest is
// byte-identical to before this file existed. Subsequent phases (B3-P2..P5)
// migrate one procedural seam at a time into `decide`/`apply`, each gated by
// `--ai-parity` and `--determinism`.
//
// Determinism contract (the linchpin — see plan §1.5):
//   1. `decide` is PURE: it reads world/house/brain, returns `[AIDecision]`,
//      mutates nothing, and never advances the global `gameRng`. Tie-breaks draw
//      from a LOCAL `GameRandom` seeded by `deriveDecideSeed`.
//   2. `apply` is the ONLY place the global `gameRng` advances, in the same
//      count and order as the procedural code it replaces.
//   3. Per-house iteration is sorted by `House.rawValue` wherever a per-house
//      decision draws RNG (the B3-P0 fix, already landed in GameAI.swift).

/// Master switch for the goal-based decision layer. Stays `false` until each
/// migrated seam is proven at parity with the procedural AI; flipping it on is
/// B3-P5, accompanied by a deliberate digest re-baseline.
var aiUseGoalLayer = false

// MARK: Goals

/// A thing the AI wants to accomplish. Goals decompose into the missions/teams
/// the simulation already supports — they do not introduce new unit behaviors.
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

/// A goal with its current desirability. `score` is also the data the B4 "why"
/// panel will surface to explain a decision.
struct ScoredGoal: Equatable {
    var goal: AIGoal
    var score: Double          // [0,1]; drives selection AND the B4 explanation UI
    var createdTick: Int
    var expiresTick: Int       // 0 = standing goal
}

// MARK: Decisions

/// A candidate for a weighted production draw. Production decisions return a
/// candidate *set* (not a pre-chosen type) so the single weighted `rndInt` draw
/// stays inside `apply`, preserving the digest (plan §1.2/§1.5).
struct BuildCandidate: Equatable { let name: String; let weight: Int; let cost: Int; let buildTime: Int }

/// The pure result of a production decision (B3-P2). Distinguishes the two RNG
/// behaviors the procedural AI has:
///   - `.forced`   — a priority pick (e.g. first harvester) that consumes NO RNG.
///   - `.weighted` — a candidate pool that consumes EXACTLY ONE `rndInt` draw,
///                   even when only one candidate survives filtering.
/// `applyBuildPlan` turns a plan into the chosen build, doing the draw only for
/// `.weighted`. Keeping the draw out of the plan is what keeps `decide` pure.
enum AIBuildPlan: Equatable {
    case none
    case forced(BuildCandidate)
    case weighted([BuildCandidate])
}

/// The pure output of `decide`. Each case is something `apply` turns into the
/// exact mutation the procedural AI does today. Equatable so `--ai-trace` and
/// the parity harness can diff decision lists for free.
enum AIDecision: Equatable {
    // Production — candidate set, not a chosen type (see BuildCandidate).
    case enqueueUnit(candidates: [BuildCandidate])
    case enqueueInfantry(candidates: [BuildCandidate])
    case enqueueStructure(typeName: String, cost: Int, buildTime: Int) // deterministic ladder, no draw
    // Movement / combat — addressed by object id, never object references.
    case orderAttack(unitId: Int, targetId: Int)
    case orderMoveTo(unitId: Int, x: Double, y: Double, then: Mission)
    case orderMission(unitId: Int, mission: Mission)
    case assignRole(unitId: Int, role: AITacticalRole, engageTick: Int?)
    // House-memory writes apply performs on the brain's behalf.
    case recordEnemySighting(x: Double, y: Double, typeName: String)
}

// MARK: Brain (per-house, value type, rides HouseState)

/// Per-house decision state. Stored on `HouseState`; auto-reset per world via
/// `initHouseStates()` recreating fresh `HouseState`s (no GameInit line needed).
/// The decide-phase RNG sub-stream is *derived* each tick (see
/// `deriveDecideSeed`), NOT stored here, so there is nothing extra to persist.
struct AIBrain: Equatable {
    var goals: [ScoredGoal] = []
    var lastDecideTick: Int = 0
}

// MARK: - decide / apply (skeletons)

/// True if `house` is an AI-controlled combatant (not the player, not neutral).
func isAIHouse(_ house: House, _ world: GameWorld) -> Bool {
    guard house != .neutral, house != world.playerHouse else { return false }
    return !getHouseState(house).isHuman
}

/// Derive a per-(house, tick) seed for decide-phase tie-breaks. Pure function of
/// persisted inputs, so it is reproducible without being stored in the brain.
func deriveDecideSeed(_ worldSeed: UInt64, _ house: House, _ tick: Int) -> UInt64 {
    var h: UInt64 = worldSeed ^ 0x9E3779B97F4A7C15
    h = (h ^ UInt64(house.rawValue.utf8.reduce(0xCBF2) { ($0 &* 31) &+ UInt64($1) })) &* 0x100000001B3
    h = (h ^ UInt64(bitPattern: Int64(tick))) &* 0x100000001B3
    return h
}

/// PURE: read world/house/brain, emit decisions. Mutates nothing; never touches
/// the global `gameRng`. Tie-breaks must use a LOCAL `GameRandom(seed:)`.
///
/// B3-P1 stub: returns no decisions, so the goal layer is a no-op even if the
/// flag were flipped. Subsequent phases populate this seam by seam.
func decide(world: GameWorld, house: House, state: HouseState,
            brain: AIBrain, seed: UInt64, tick: Int) -> [AIDecision] {
    _ = (world, house, state, brain, seed, tick)
    return []
}

/// EFFECTFUL: the ONLY site that mutates objects/queues/roles and advances the
/// global `gameRng`. Applies each decision as the exact mutation the procedural
/// AI performs today.
///
/// B3-P1 stub: nothing to apply yet.
func apply(_ decisions: [AIDecision], world: GameWorld, house: House,
           state: HouseState, tick: Int) {
    _ = (decisions, world, house, state, tick)
}
