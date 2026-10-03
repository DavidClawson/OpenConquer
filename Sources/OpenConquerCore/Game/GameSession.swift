import Foundation

// MARK: - Menu / UI Types

package enum Faction: String { case gdi = "GDI"; case nod = "NOD" }
package enum Difficulty: String, CaseIterable { case easy = "Easy"; case normal = "Normal"; case hard = "Hard" }
// MARK: - Sub-Containers

/// Sidebar, credits, build queues, placement/repair/sell mode.
package class ProductionState {
    package var sidebarCredits: Int = 5000
    package var displayedCredits: Int = 0
    package var unitBuildQueue = ProductionQueue()
    package var structureBuildQueue = ProductionQueue()
    package var isPlacingStructure: Bool = false
    package var placementType: String? = nil
    package var sidebarScrollOffset: Int = 0
    package var sidebarTab: Int = 0
    package var isRepairMode: Bool = false
    package var isSellMode: Bool = false
    package var isAttackMoveMode: Bool = false
    package var isPatrolMode: Bool = false
    package var patrolModeWaypoints: [(x: Double, y: Double)] = []  // Waypoints being built in patrol mode

    /// Animate displayedCredits toward sidebarCredits each game tick.
    /// Ported from Vanilla Conquer credits.cpp CreditClass::AI.
    /// The adder is |delta| >> 5, clamped to [1, 143], matching the original.
    package func tickCreditsDisplay() {
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
package class ScriptingState {
    package var gameTriggers: [GameTrigger] = []
    package var triggerWinState: TriggerWinState = .playing
    package var allowWinFlag: Bool = false
    /// Win-gating (mirrors HouseClass Blockage/IsToWin, TRIGGER.CPP:1078,313 +
    /// HOUSE.CPP:794): `winBlockage` = number of unfired AllowWin triggers for the
    /// player; a flagged win only completes once it reaches 0. `flaggedToWin`
    /// mirrors IsToWin — a Win action sets it, but the mission only ends when the
    /// blockage is drained.
    package var winBlockage: Int = 0
    package var flaggedToWin: Bool = false
    package var teamTypes: [TeamType] = []
    package var activeTeams: [ActiveTeam] = []
    package var scenarioWaypoints: [Int: Int] = [:]
    /// Per-house reinforcement entry edge (`Edge=` in house INI sections).
    package var houseEdges: [House: MapEdge] = [:]
    package var aiTickCounter: Int = 0
    package var pendingReinforcements: [PendingReinforcement] = []
    /// Tier-1 T4: named region zones, keyed by uppercased name.
    package var scenarioRegions: [String: ScenarioRegion] = [:]
}

/// Super weapons, projectiles, animations.
package class CombatState {
    package var playerIonCannon = SuperWeapon(type: .ionCannon, chargeTime: ionCannonChargeTime)
    package var playerAirStrike = SuperWeapon(type: .airStrike, chargeTime: airStrikeChargeTime)
    package var playerNukeStrike = SuperWeapon(type: .nuclearStrike, chargeTime: nuclearStrikeChargeTime)
    package var superWeaponTargeting: SpecialWeaponType? = nil
    package var activeProjectiles: [Projectile] = []
    package var nextProjectileId: Int = 1
    package var activeAnimations: [GameAnimation] = []

    // EVA speech rate limiting — tracks last tick each VoxType was spoken
    package var lastEVATick: [VoxType: Int] = [:]

    // Track previous low-power state for edge-triggered EVA announcement
    package var wasLowPower: Bool = false

    // Track previous sidebar build options for "new options" detection
    package var previousBuildOptionCount: Int = 0
}

// MARK: - Selection

/// The local player's selection and control groups. UI state, not simulation
/// state: orders reach the world only as PlayerCommands, so in a networked
/// game each machine keeps just its own player's selection, like the
/// original (IsSelected never travels in an EventClass). Reset with every
/// new GameWorld; saves still record it (GameSaveLoad / GameCampaignSave).
package final class SelectionState {
    package var ids: Set<Int> = []
    package var controlGroups: [[Int]] = Array(repeating: [], count: 10)

    package init() {}
}

// MARK: - GameSession

package class GameSession {
    // MARK: - Game World
    package var world: GameWorld? = nil
    package var scenarioBuildLevel: Int = 99  // Tech level cap (from scenario INI)

    // Human-player fog-aware pathfinding is now a ruleset toggle
    // (`session.rules.fogAwarePathfinding`, off in Classic) — see GameRules.swift.

    // Active ruleset — the data-driven switchboard for tunable behavior (see
    // Game/GameRules.swift). Defaults to the canonical, determinism-pinned
    // Classic (1995) preset; interactive play / a future Options screen can swap
    // it (e.g. to .enhanced for veterancy). The headless harness uses this
    // default, so classic1995's digests are the pinned baselines in CLAUDE.md.
    package var rules: Ruleset = .classic1995

    // MARK: - Sub-Containers
    package var production = ProductionState()
    package var scripting = ScriptingState()
    package var combat = CombatState()
    package var selection = SelectionState()

    // MARK: - Campaign
    package var campaign = CampaignManager()

    // Forwarding properties (campaign)
    package var campaignState: CampaignState { campaign.state }
    package var missionScore: MissionScore { campaign.score }
    package var currentScenarioName: String? {
        get { campaign.currentScenarioName }
        set { campaign.currentScenarioName = newValue }
    }

    // MARK: - House States
    package var houseStates: [House: HouseState] = [:]

    // MARK: - Forwarding Properties (production)
    package var sidebarCredits: Int {
        get { production.sidebarCredits }
        set { production.sidebarCredits = newValue }
    }
    package var displayedCredits: Int {
        get { production.displayedCredits }
        set { production.displayedCredits = newValue }
    }
    package var unitBuildQueue: ProductionQueue { production.unitBuildQueue }
    package var structureBuildQueue: ProductionQueue { production.structureBuildQueue }
    package var isPlacingStructure: Bool {
        get { production.isPlacingStructure }
        set { production.isPlacingStructure = newValue }
    }
    package var placementType: String? {
        get { production.placementType }
        set { production.placementType = newValue }
    }
    package var sidebarScrollOffset: Int {
        get { production.sidebarScrollOffset }
        set { production.sidebarScrollOffset = newValue }
    }
    package var sidebarTab: Int {
        get { production.sidebarTab }
        set { production.sidebarTab = newValue }
    }
    package var isRepairMode: Bool {
        get { production.isRepairMode }
        set { production.isRepairMode = newValue }
    }
    package var isSellMode: Bool {
        get { production.isSellMode }
        set { production.isSellMode = newValue }
    }
    package var isAttackMoveMode: Bool {
        get { production.isAttackMoveMode }
        set { production.isAttackMoveMode = newValue }
    }
    package var isPatrolMode: Bool {
        get { production.isPatrolMode }
        set { production.isPatrolMode = newValue }
    }
    package var patrolModeWaypoints: [(x: Double, y: Double)] {
        get { production.patrolModeWaypoints }
        set { production.patrolModeWaypoints = newValue }
    }
    package func tickCreditsDisplay() { production.tickCreditsDisplay() }

    // MARK: - Forwarding Properties (scripting)
    package var gameTriggers: [GameTrigger] {
        get { scripting.gameTriggers }
        set { scripting.gameTriggers = newValue }
    }
    package var triggerWinState: TriggerWinState {
        get { scripting.triggerWinState }
        set { scripting.triggerWinState = newValue }
    }
    package var allowWinFlag: Bool {
        get { scripting.allowWinFlag }
        set { scripting.allowWinFlag = newValue }
    }
    package var winBlockage: Int {
        get { scripting.winBlockage }
        set { scripting.winBlockage = newValue }
    }
    package var flaggedToWin: Bool {
        get { scripting.flaggedToWin }
        set { scripting.flaggedToWin = newValue }
    }
    package var teamTypes: [TeamType] {
        get { scripting.teamTypes }
        set { scripting.teamTypes = newValue }
    }
    package var activeTeams: [ActiveTeam] {
        get { scripting.activeTeams }
        set { scripting.activeTeams = newValue }
    }
    package var scenarioWaypoints: [Int: Int] {
        get { scripting.scenarioWaypoints }
        set { scripting.scenarioWaypoints = newValue }
    }
    package var houseEdges: [House: MapEdge] {
        get { scripting.houseEdges }
        set { scripting.houseEdges = newValue }
    }
    package var scenarioRegions: [String: ScenarioRegion] {
        get { scripting.scenarioRegions }
        set { scripting.scenarioRegions = newValue }
    }
    package var aiTickCounter: Int {
        get { scripting.aiTickCounter }
        set { scripting.aiTickCounter = newValue }
    }
    package var pendingReinforcements: [PendingReinforcement] {
        get { scripting.pendingReinforcements }
        set { scripting.pendingReinforcements = newValue }
    }

    // MARK: - Forwarding Properties (combat)
    package var playerIonCannon: SuperWeapon {
        get { combat.playerIonCannon }
        set { combat.playerIonCannon = newValue }
    }
    package var playerAirStrike: SuperWeapon {
        get { combat.playerAirStrike }
        set { combat.playerAirStrike = newValue }
    }
    package var playerNukeStrike: SuperWeapon {
        get { combat.playerNukeStrike }
        set { combat.playerNukeStrike = newValue }
    }
    package var superWeaponTargeting: SpecialWeaponType? {
        get { combat.superWeaponTargeting }
        set { combat.superWeaponTargeting = newValue }
    }
    package var activeProjectiles: [Projectile] {
        get { combat.activeProjectiles }
        set { combat.activeProjectiles = newValue }
    }
    package var nextProjectileId: Int {
        get { combat.nextProjectileId }
        set { combat.nextProjectileId = newValue }
    }
    package var activeAnimations: [GameAnimation] {
        get { combat.activeAnimations }
        set { combat.activeAnimations = newValue }
    }
    package var lastEVATick: [VoxType: Int] {
        get { combat.lastEVATick }
        set { combat.lastEVATick = newValue }
    }
    package var wasLowPower: Bool {
        get { combat.wasLowPower }
        set { combat.wasLowPower = newValue }
    }
    package var previousBuildOptionCount: Int {
        get { combat.previousBuildOptionCount }
        set { combat.previousBuildOptionCount = newValue }
    }

    /// Speak an EVA line with rate limiting. `cooldownTicks` is the minimum gap
    /// between repeats of the same VoxType (default 90 ticks = ~6 seconds).
    package func speakEVA(_ vox: VoxType, cooldownTicks: Int = 90) {
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

package var session = GameSession()
