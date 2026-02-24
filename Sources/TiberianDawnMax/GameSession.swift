import Foundation

// MARK: - GameSession
// Consolidates all game-session state globals into a single object.
// This is a mechanical refactor — no behavior changes.

class GameSession {
    // MARK: - Game World
    var world: GameWorld? = nil

    // MARK: - Game Tick Timing
    var tickAccumulator: UInt32 = 0
    var lastTickTime: UInt32 = 0
    var renderInterpolation: Double = 0.0

    // MARK: - Projectiles
    var activeProjectiles: [Projectile] = []
    var nextProjectileId: Int = 1

    // MARK: - Animations
    var activeAnimations: [GameAnimation] = []

    // MARK: - Sidebar / Production
    var sidebarCredits: Int = 5000
    var displayedCredits: Int = 0
    var unitBuildQueue: (typeName: String, progress: Int, cost: Int, totalTicks: Int)? = nil
    var structureBuildQueue: (typeName: String, progress: Int, cost: Int, totalTicks: Int)? = nil
    var isPlacingStructure: Bool = false
    var placementType: String? = nil
    var sidebarScrollOffset: Int = 0
    var sidebarTab: Int = 0
    var isRepairMode: Bool = false
    var isSellMode: Bool = false

    // MARK: - Triggers
    var gameTriggers: [GameTrigger] = []
    var triggerWinState: TriggerWinState = .playing
    var allowWinFlag: Bool = false

    // MARK: - Campaign
    var campaignState = CampaignState()
    var missionScore = MissionScore()
    var currentScenarioName: String? = nil

    // MARK: - Super Weapons
    var playerIonCannon = SuperWeapon(type: .ionCannon, chargeTime: ionCannonChargeTime)
    var playerAirStrike = SuperWeapon(type: .airStrike, chargeTime: airStrikeChargeTime)
    var playerNukeStrike = SuperWeapon(type: .nuclearStrike, chargeTime: nuclearStrikeChargeTime)
    var superWeaponTargeting: SpecialWeaponType? = nil

    // MARK: - Teams & Waypoints
    var teamTypes: [TeamType] = []
    var activeTeams: [ActiveTeam] = []
    var scenarioWaypoints: [Int: Int] = [:]

    // MARK: - AI
    var aiTickCounter: Int = 0

    // MARK: - House States
    var houseStates: [House: HouseState] = [:]
}

// MARK: - Global Session Instance

var session = GameSession()
