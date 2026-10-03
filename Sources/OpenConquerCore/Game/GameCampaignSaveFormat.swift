import Foundation

// MARK: - Campaign Save Format
// Codable save-file structs, the save directory, and the kind/mission name mappings they use.

// MARK: - Save Game Data Structure

package struct SaveGameData: Codable {
    // Header
    package let version: Int
    package let description: String
    package let saveDate: Date
    package let scenarioName: String

    // World state
    package let tickCount: Int
    package var randomSeed: UInt64? = nil       // Deterministic RNG seed (optional: older saves lack it)
    package var rngState: UInt64? = nil         // Deterministic RNG stream position
    package let playerHouse: String
    package let theater: String
    package let mapBoundsX: Int
    package let mapBoundsY: Int
    package let mapBoundsW: Int
    package let mapBoundsH: Int

    // Credits
    package let credits: Int

    // Objects
    package let objects: [SavedObject]

    // Campaign
    package let campaignFaction: String
    package let campaignMission: Int
    package let campaignVariant: String
    package let campaignDifficulty: Int
    package let carryOverCredits: Int

    // Score
    package let scoreGDIKills: Int
    package let scoreNodKills: Int
    package let scoreCivKills: Int
    package let scoreGDIBuildings: Int
    package let scoreNodBuildings: Int
    package let scoreCivBuildings: Int
    package let scoreCreditsHarvested: Int
    package let scoreElapsedTicks: Int

    // Triggers
    package let triggers: [SavedTrigger]

    // Camera
    package let cameraX: Double
    package let cameraY: Double

    // --- V2 fields (optional for backward compat with V1 saves) ---

    // Control groups
    package var controlGroups: [[Int]]?

    // Map state: tiberium
    package var tiberiumCells: [Int]?
    package var tiberiumDensity: [SavedTiberiumEntry]?
    package var tiberiumScan: Int?
    package var isForwardScan: Bool?

    // Map state: smudges
    package var smudges: [SavedSmudge]?

    // Map state: fog
    package var fogState: [Int]?

    // Production queues
    package var unitBuildQueue: SavedProductionQueue?
    package var structureBuildQueue: SavedProductionQueue?

    // Super weapon charge state
    package var ionCannon: SavedSuperWeapon?
    package var airStrike: SavedSuperWeapon?
    package var nukeStrike: SavedSuperWeapon?

    // Active teams
    package var activeTeams: [SavedActiveTeam]?

    // Scripting state
    package var triggerWinState: String?
    package var allowWinFlag: Bool?
    package var aiTickCounter: Int?
    package var scenarioBuildLevel: Int?
}

package struct SavedObject: Codable {
    package let id: Int
    package let typeName: String
    package let house: String
    package let kind: String
    package let worldX: Double
    package let worldY: Double
    package let facing: Int
    package let strength: Int
    package let mission: String
    package let speed: Double
    package let isSelected: Bool
    package let triggerName: String?
    package let isAircraft: Bool
    package let altitude: Int
    package let ammo: Int
    package let subCell: Int

    // --- V2 fields (optional for backward compat) ---

    // Movement
    package var moveTargetX: Double?
    package var moveTargetY: Double?
    package var movePath: [SavedCell]?
    package var navTargetId: Int?
    package var group: Int?
    package var isAttackMoving: Bool?
    package var moveWaypoints: [SavedCell]?

    // Combat
    package var attackTarget: Int?
    package var suspendedTarget: Int?
    package var reloadTimer: Int?
    package var lastFireTick: Int?
    package var lastDamagedTick: Int?

    // Mission state
    package var turretFacing: Int?
    package var missionQueue: String?
    package var suspendedMission: String?
    package var missionStatus: Int?

    // Cargo / transport
    package var passengers: [Int]?
    package var isALoaner: Bool?

    // Harvesting
    package var tiberiumLoad: Int?

    // Infantry
    package var fear: UInt8?
    package var isProne: Bool?

    // Building
    package var isRepairing: Bool?
    package var buildUpFrame: Int?
    package var buildUpTotalFrames: Int?
    package var buildUpDelay: Int?
    package var samDeployState: Int?
    package var powerOutput: Int?
    package var powerDrain: Int?

    // Aircraft
    package var isLanding: Bool?
    package var isTakingOff: Bool?

    // Flags
    package var isInLimbo: Bool?
    package var isTethered: Bool?

    // Rally point (buildings)
    package var rallyPointX: Double?
    package var rallyPointY: Double?

    // Patrol route
    package var patrolWaypoints: [SavedCell]?
    package var patrolIndex: Int?
}

package struct SavedCell: Codable {
    package let x: Int
    package let y: Int
}

package struct SavedTrigger: Codable {
    package let name: String
    package let isActive: Bool
    package let data: Int
    package let attachCount: Int
}

package struct SavedTiberiumEntry: Codable {
    package let cell: Int
    package let density: Int
    /// Sprite variant 1..12 (which TI<N>.SHP to draw). Optional so older
    /// saves load fine — at restore we fall back to the cell's density.
    package var variant: Int?
}

package struct SavedSmudge: Codable {
    package let type: String
    package let cell: Int
}

package struct SavedProductionQueue: Codable {
    package var typeName: String?
    package var progress: Int?
    package var cost: Int?
    package var totalTicks: Int?
    package var isOnHold: Bool?
}

package struct SavedSuperWeapon: Codable {
    package var isPresent: Bool
    package var isReady: Bool
    package var isOneTime: Bool
    package var isSuspended: Bool
    package var chargeRemaining: Int
    package var suspendedTime: Int
}

package struct SavedActiveTeam: Codable {
    package let typeName: String
    package let members: [Int]
    package let isMoving: Bool
    package let isFullStrength: Bool
    package let isUnderStrength: Bool
    package let isHasBeen: Bool
    package let currentMission: Int
    package let isNextMission: Bool
    package let centerX: Double
    package let centerY: Double
    package let target: Int?
    package let targetCell: Int?
    package let missionTimeout: Int
    package let isSuspended: Bool
    package let suspendTimer: Int
}

// MARK: - Save Directory

package let saveDirectory: URL = {
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TiberianDawnMax")
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return appSupport
}()

// MARK: - Helper Functions

package func objectKindString(_ kind: ObjectKind) -> String {
    switch kind {
    case .unit: return "unit"
    case .infantry: return "infantry"
    case .structure: return "structure"
    }
}

package func objectKindFromString(_ str: String) -> ObjectKind {
    switch str.lowercased() {
    case "unit": return .unit
    case "infantry": return .infantry
    case "structure": return .structure
    default: return .unit
    }
}

// MARK: - Mission extensions

extension Mission {
    package var saveName: String {
        switch self {
        case .sleep: return "Sleep"
        case .attack: return "Attack"
        case .move: return "Move"
        case .guard_: return "Guard"
        case .guardArea: return "Area Guard"
        case .harvest: return "Harvest"
        case .return_: return "Return"
        case .stop: return "Stop"
        case .ambush: return "Ambush"
        case .hunt: return "Hunt"
        case .timedHunt: return "Timed Hunt"
        case .enter: return "Enter"
        case .capture: return "Capture"
        case .retreat: return "Retreat"
        case .unload: return "Unload"
        case .construction: return "Construction"
        case .deconstruction: return "Deconstruction"
        case .repair: return "Repair"
        case .selling: return "Selling"
        case .missile: return "Missile"
        case .sticky: return "Sticky"
        case .sabotage: return "Sabotage"
        case .patrol: return "Patrol"
        }
    }
}
