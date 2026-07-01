import Foundation

// MARK: - Menu / UI Types

enum Faction: String { case gdi = "GDI"; case nod = "NOD" }
enum Difficulty: String, CaseIterable { case easy = "Easy"; case normal = "Normal"; case hard = "Hard" }
// MARK: - Sub-Containers

/// Sidebar, credits, build queues, placement/repair/sell mode.
class ProductionState {
    var sidebarCredits: Int = 5000
    var displayedCredits: Int = 0
    var unitBuildQueue = ProductionQueue()
    var structureBuildQueue = ProductionQueue()
    var isPlacingStructure: Bool = false
    var placementType: String? = nil
    var sidebarScrollOffset: Int = 0
    var sidebarTab: Int = 0
    var isRepairMode: Bool = false
    var isSellMode: Bool = false
    var isAttackMoveMode: Bool = false
    var isPatrolMode: Bool = false
    var patrolModeWaypoints: [(x: Double, y: Double)] = []  // Waypoints being built in patrol mode

    /// Animate displayedCredits toward sidebarCredits each game tick.
    /// Ported from Vanilla Conquer credits.cpp CreditClass::AI.
    /// The adder is |delta| >> 5, clamped to [1, 143], matching the original.
    func tickCreditsDisplay() {
        if displayedCredits == sidebarCredits { return }

        let delta = sidebarCredits - displayedCredits
        var adder = abs(delta) >> 5
        adder = max(1, min(adder, 143))
        if delta < 0 { adder = -adder }
        displayedCredits += adder

        // Snap if we overshot
        if (adder > 0 && displayedCredits > sidebarCredits) ||
           (adder < 0 && displayedCredits < sidebarCredits) {
            displayedCredits = sidebarCredits
        }
    }
}

/// Triggers, win/lose state, reinforcements, teams, waypoints, AI.
class ScriptingState {
    var gameTriggers: [GameTrigger] = []
    var triggerWinState: TriggerWinState = .playing
    var allowWinFlag: Bool = false
    var teamTypes: [TeamType] = []
    var activeTeams: [ActiveTeam] = []
    var scenarioWaypoints: [Int: Int] = [:]
    var aiTickCounter: Int = 0
    var pendingReinforcements: [PendingReinforcement] = []
    /// Tier-1 T4: named region zones, keyed by uppercased name.
    var scenarioRegions: [String: ScenarioRegion] = [:]
}

/// Super weapons, projectiles, animations.
class CombatState {
    var playerIonCannon = SuperWeapon(type: .ionCannon, chargeTime: ionCannonChargeTime)
    var playerAirStrike = SuperWeapon(type: .airStrike, chargeTime: airStrikeChargeTime)
    var playerNukeStrike = SuperWeapon(type: .nuclearStrike, chargeTime: nuclearStrikeChargeTime)
    var superWeaponTargeting: SpecialWeaponType? = nil
    var activeProjectiles: [Projectile] = []
    var nextProjectileId: Int = 1
    var activeAnimations: [GameAnimation] = []

    // EVA speech rate limiting — tracks last tick each VoxType was spoken
    var lastEVATick: [VoxType: Int] = [:]

    // Track previous low-power state for edge-triggered EVA announcement
    var wasLowPower: Bool = false

    // Track previous sidebar build options for "new options" detection
    var previousBuildOptionCount: Int = 0
}

// MARK: - GameSession

class GameSession {
    // MARK: - Menu / UI State
    var currentScreen: MenuScreen = MainMenuScreen()
    var running: Bool = true
    var isPlaying: Bool { currentScreen is PlayingScreen }
    var selectedDifficulty: Difficulty = .normal
    var selectedFaction: Faction = .gdi
    var scenarioList: [String] = []
    var scenarioIndex: Int = 0
    var soundTest = SoundTestState()
    var spritePlayground = SpritePlaygroundState()

    // MARK: - Game World
    var world: GameWorld? = nil
    var scenarioBuildLevel: Int = 99  // Tech level cap (from scenario INI)

    // When true, the HUMAN player's move pathfinding only trusts explored
    // terrain: unexplored cells are assumed passable, so a unit ordered into the
    // dark heads straight there and only reroutes once it discovers a real
    // obstacle. Off by default (and never set in headless) so the AI stays
    // omniscient and the determinism baselines are unaffected.
    var fogAwarePathfinding: Bool = false

    // Active ruleset — the data-driven switchboard for tunable behavior (see
    // Game/GameRules.swift). Defaults to the canonical, determinism-pinned
    // Classic (1995) preset; interactive play / a future Options screen can swap
    // it (e.g. to .enhanced for veterancy). The headless harness uses this
    // default, so classic1995's digests are the pinned baselines in CLAUDE.md.
    var rules: Ruleset = .classic1995

    // MARK: - Game Tick Timing
    var tickAccumulator: UInt32 = 0
    var lastTickTime: UInt32 = 0
    var renderInterpolation: Double = 0.0

    // MARK: - Sub-Containers
    var production = ProductionState()
    var scripting = ScriptingState()
    var combat = CombatState()

    // MARK: - Campaign
    var campaign = CampaignManager()

    // Forwarding properties (campaign)
    var campaignState: CampaignState { campaign.state }
    var missionScore: MissionScore { campaign.score }
    var currentScenarioName: String? {
        get { campaign.currentScenarioName }
        set { campaign.currentScenarioName = newValue }
    }

    // MARK: - House States
    var houseStates: [House: HouseState] = [:]

    // MARK: - Forwarding Properties (production)
    var sidebarCredits: Int {
        get { production.sidebarCredits }
        set { production.sidebarCredits = newValue }
    }
    var displayedCredits: Int {
        get { production.displayedCredits }
        set { production.displayedCredits = newValue }
    }
    var unitBuildQueue: ProductionQueue { production.unitBuildQueue }
    var structureBuildQueue: ProductionQueue { production.structureBuildQueue }
    var isPlacingStructure: Bool {
        get { production.isPlacingStructure }
        set { production.isPlacingStructure = newValue }
    }
    var placementType: String? {
        get { production.placementType }
        set { production.placementType = newValue }
    }
    var sidebarScrollOffset: Int {
        get { production.sidebarScrollOffset }
        set { production.sidebarScrollOffset = newValue }
    }
    var sidebarTab: Int {
        get { production.sidebarTab }
        set { production.sidebarTab = newValue }
    }
    var isRepairMode: Bool {
        get { production.isRepairMode }
        set { production.isRepairMode = newValue }
    }
    var isSellMode: Bool {
        get { production.isSellMode }
        set { production.isSellMode = newValue }
    }
    var isAttackMoveMode: Bool {
        get { production.isAttackMoveMode }
        set { production.isAttackMoveMode = newValue }
    }
    var isPatrolMode: Bool {
        get { production.isPatrolMode }
        set { production.isPatrolMode = newValue }
    }
    var patrolModeWaypoints: [(x: Double, y: Double)] {
        get { production.patrolModeWaypoints }
        set { production.patrolModeWaypoints = newValue }
    }
    func tickCreditsDisplay() { production.tickCreditsDisplay() }

    // MARK: - Forwarding Properties (scripting)
    var gameTriggers: [GameTrigger] {
        get { scripting.gameTriggers }
        set { scripting.gameTriggers = newValue }
    }
    var triggerWinState: TriggerWinState {
        get { scripting.triggerWinState }
        set { scripting.triggerWinState = newValue }
    }
    var allowWinFlag: Bool {
        get { scripting.allowWinFlag }
        set { scripting.allowWinFlag = newValue }
    }
    var teamTypes: [TeamType] {
        get { scripting.teamTypes }
        set { scripting.teamTypes = newValue }
    }
    var activeTeams: [ActiveTeam] {
        get { scripting.activeTeams }
        set { scripting.activeTeams = newValue }
    }
    var scenarioWaypoints: [Int: Int] {
        get { scripting.scenarioWaypoints }
        set { scripting.scenarioWaypoints = newValue }
    }
    var scenarioRegions: [String: ScenarioRegion] {
        get { scripting.scenarioRegions }
        set { scripting.scenarioRegions = newValue }
    }
    var aiTickCounter: Int {
        get { scripting.aiTickCounter }
        set { scripting.aiTickCounter = newValue }
    }
    var pendingReinforcements: [PendingReinforcement] {
        get { scripting.pendingReinforcements }
        set { scripting.pendingReinforcements = newValue }
    }

    // MARK: - Forwarding Properties (combat)
    var playerIonCannon: SuperWeapon {
        get { combat.playerIonCannon }
        set { combat.playerIonCannon = newValue }
    }
    var playerAirStrike: SuperWeapon {
        get { combat.playerAirStrike }
        set { combat.playerAirStrike = newValue }
    }
    var playerNukeStrike: SuperWeapon {
        get { combat.playerNukeStrike }
        set { combat.playerNukeStrike = newValue }
    }
    var superWeaponTargeting: SpecialWeaponType? {
        get { combat.superWeaponTargeting }
        set { combat.superWeaponTargeting = newValue }
    }
    var activeProjectiles: [Projectile] {
        get { combat.activeProjectiles }
        set { combat.activeProjectiles = newValue }
    }
    var nextProjectileId: Int {
        get { combat.nextProjectileId }
        set { combat.nextProjectileId = newValue }
    }
    var activeAnimations: [GameAnimation] {
        get { combat.activeAnimations }
        set { combat.activeAnimations = newValue }
    }
    var lastEVATick: [VoxType: Int] {
        get { combat.lastEVATick }
        set { combat.lastEVATick = newValue }
    }
    var wasLowPower: Bool {
        get { combat.wasLowPower }
        set { combat.wasLowPower = newValue }
    }
    var previousBuildOptionCount: Int {
        get { combat.previousBuildOptionCount }
        set { combat.previousBuildOptionCount = newValue }
    }

    /// Speak an EVA line with rate limiting. `cooldownTicks` is the minimum gap
    /// between repeats of the same VoxType (default 90 ticks = ~6 seconds).
    func speakEVA(_ vox: VoxType, cooldownTicks: Int = 90) {
        guard let world = world else {
            audioManager.speak(vox)
            return
        }
        let tick = world.tickCount
        if let last = lastEVATick[vox], tick - last < cooldownTicks {
            return  // Rate limited
        }
        lastEVATick[vox] = tick
        audioManager.speak(vox)
    }
}

// MARK: - Global Session Instance

var session = GameSession()
