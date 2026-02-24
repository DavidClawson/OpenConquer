import Foundation

// MARK: - Menu / UI Types

enum Faction: String { case gdi = "GDI"; case nod = "NOD" }
enum Difficulty: String, CaseIterable { case easy = "Easy"; case normal = "Normal"; case hard = "Hard" }
enum MenuState { case main, chooseDifficulty, chooseFaction, launching(Faction, Difficulty), spriteViewer, soundTest, mapViewer, playing }

// MARK: - GameSession
// Consolidates all game-session state globals into a single object.
// This is a mechanical refactor — no behavior changes.

class GameSession {
    // MARK: - Menu / UI State
    var menuState: MenuState = .main
    var running: Bool = true
    var selectedDifficulty: Difficulty = .normal
    var selectedFaction: Faction = .gdi
    var scenarioList: [String] = []
    var scenarioIndex: Int = 0
    var soundTest = SoundTestState()
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

    // MARK: - Reinforcements
    var pendingReinforcements: [PendingReinforcement] = []

    // MARK: - House States
    var houseStates: [House: HouseState] = [:]

    // MARK: - Credits Ticker

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

// MARK: - Global Session Instance

var session = GameSession()
