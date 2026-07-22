import Foundation

// MARK: - Game Object Types

enum ObjectKind {
    case unit
    case infantry
    case structure
}

/// AI tactical role assigned to a unit for coordinated behaviors
enum AITacticalRole {
    case none           // No special role
    case scout          // Scouting / recon
    case hitAndRun      // Hit-and-run attacker
    case harasser       // Harvester harasser
    case flank          // Flanking group member
}

enum Mission: String {
    // Core missions (VC mission.h)
    case sleep = "Sleep"
    case attack = "Attack"
    case move = "Move"
    case retreat = "Retreat"
    case guard_ = "Guard"
    case sticky = "Sticky"         // Guard without auto-target
    case enter = "Enter"
    case capture = "Capture"
    case harvest = "Harvest"
    case guardArea = "Guard Area"
    case return_ = "Return"
    case stop = "Stop"
    case ambush = "Ambush"
    case hunt = "Hunt"
    case timedHunt = "Timed Hunt"
    case unload = "Unload"
    case repair = "Repair"
    case missile = "Missile"
    case construction = "Construction"
    case deconstruction = "Deconstruction"
    case selling = "Selling"
    case sabotage = "Sabotage"
    case patrol = "Patrol"

    static func from(_ string: String) -> Mission {
        switch string.lowercased() {
        case "guard":          return .guard_
        case "move":           return .move
        case "stop":           return .stop
        case "sleep":          return .sleep
        case "attack":         return .attack
        case "harvest":        return .harvest
        case "hunt":           return .hunt
        case "ambush":         return .ambush
        case "retreat":        return .retreat
        case "enter":          return .enter
        case "capture":        return .capture
        // "Area Guard" is the classic INI spelling (MISSION.CPP:464);
        // "Guard Area" kept for editor/serialized round-trips.
        case "guard area":     return .guardArea
        case "area guard":     return .guardArea
        case "return":         return .return_
        case "unload":         return .unload
        case "repair":         return .repair
        case "sticky":         return .sticky
        case "timed hunt":     return .timedHunt
        case "sabotage":       return .sabotage
        case "patrol":         return .patrol
        default:               return .guard_
        }
    }
}

// MARK: - Game Object

/// Unified game object — represents units, infantry, and structures.
/// Type-specific data is resolved once at creation time via cached lookups.
class GameObject {
    let id: Int
    let typeName: String
    var house: House                // Mutable for capture
    let kind: ObjectKind

    // Position in double-pixel coordinates (sub-pixel smooth)
    var worldX: Double
    var worldY: Double
    var prevWorldX: Double          // Previous tick position (for render interpolation)
    var prevWorldY: Double
    var facing: Int                 // 0-255 C&C facing (0=N, 64=E, 128=S, 192=W)
    var turretFacing: Int = 0       // Turret facing for units with turrets
    var strength: Int               // Hit points

    // Mission state (VC MissionClass)
    var mission: Mission
    {
        didSet {
            #if DEBUG
            validateMission(mission, old: oldValue)
            #endif
        }
    }
    var missionQueue: Mission? = nil         // Queued next mission
    var suspendedMission: Mission? = nil     // Saved mission for resume
    var missionStatus: Int = 0               // Sub-state within current mission
    var isSelected: Bool = false

    // Movement (VC FootClass)
    var moveTargetX: Double? = nil
    var moveTargetY: Double? = nil
    var speed: Double               // Pixels per tick
    var movePath: [(cellX: Int, cellY: Int)] = []
    var navTargetId: Int? = nil     // Navigation target object ID
    var group: Int = -1             // Control group (0-9, -1 = none)
    var isAttackMoving: Bool = false // Attack-move: scan for enemies while moving
    var moveWaypoints: [(x: Double, y: Double)] = []  // Queued waypoints (shift+click)
    var groupMoveSpeed: Double? = nil  // Squad speed matching: move at slowest unit's speed

    // Patrol route
    var patrolWaypoints: [(x: Double, y: Double)] = []  // Ordered patrol waypoints
    var patrolIndex: Int = 0                              // Current waypoint in the loop

    // Combat (VC TechnoClass)
    var attackTarget: Int? = nil    // Target object ID
    var suspendedTarget: Int? = nil // Saved target (VC SuspendedTarCom)
    var reloadTimer: Int = 0
    var lastFireTick: Int = 0       // Tick when unit last fired (for muzzle flash)
    var lastDamagedTick: Int = 0    // Tick when unit last took damage (for damage flash)
    var ammo: Int = -1              // -1 = unlimited

    // Veterancy system
    var killCount: Int = 0          // Total kills scored by this unit
    /// Veteran level: 0=Regular, 1=Veteran (3 kills), 2=Elite (7 kills).
    /// Returns 0 when the active ruleset disables veterancy (the classic game had
    /// no promotions), which removes every downstream bonus in one place. Kills
    /// still accrue in `killCount` so toggling the rule mid-session is lossless.
    var veteranLevel: Int {
        guard session.rules.veterancyEnabled else { return 0 }
        if killCount >= 7 { return 2 }
        if killCount >= 3 { return 1 }
        return 0
    }

    // Harvesting (units only)
    var tiberiumLoad: Int = 0
    var dockTimer: Int = 0          // Transient counter driving the refinery dock slide-in/out animation
    var preferredRefineryID: Int? = nil  // Player-directed dock target; harvester docks here instead of the nearest PROC
    var harvesterForceDock: Bool = false // Player ordered "return to refinery" — go dock now even if not full

    // Repair facility (FIX) — vehicle the player sent to a repair bay to be healed
    var repairBuildingID: Int? = nil

    // Transport boarding — infantry the player ordered into a transport
    // (walks over and loads as a passenger; drives the civ-evac flow)
    var enterTransportID: Int? = nil

    // Animation state (infantry walk cycle, fire animation)
    var animFrame: Int = 0          // Current animation frame offset (0 = stand, 1+ = walk cycle)
    var animTickCounter: Int = 0    // Tick counter for animation timing
    var isFiringAnim: Bool = false  // True when playing fire animation
    var fireAnimTicks: Int = 0      // Countdown for fire animation duration

    // Infantry-specific (VC InfantryClass)
    var subCell: Int
    var fear: UInt8 = 0             // 0-255: 0=fearless, 200=panic
    var isProne: Bool = false       // Crawling/prone

    // Building-specific (VC BuildingClass)
    var isRepairing: Bool = false
    var lastWhoHurtMe: House? = nil // For kill credit
    var lastAttackerId: Int? = nil  // Specific attacker — drives retaliation/return-fire
    var rallyPointX: Double? = nil  // Rally point world X for production buildings
    var rallyPointY: Double? = nil  // Rally point world Y for production buildings
    var powerOutput: Int = 0        // Power generated by this building
    var powerDrain: Int = 0         // Power consumed by this building
    var buildUpFrame: Int = -1      // -1 = no build anim, 0+ = current build-up frame
    var buildUpTotalFrames: Int = 0 // Total frames in build-up sequence
    var buildUpDelay: Int = 0       // Ticks until next build-up frame advance
    var samDeployState: Int = 0     // 0 = retracted, 1-31 = deploying/deployed frame

    // Aircraft-specific (VC AircraftClass)
    var isAircraft: Bool = false    // True if this is an aircraft object
    var altitude: Int = 0           // 0=ground, 24=flight level
    var isLanding: Bool = false     // In landing sequence
    var isTakingOff: Bool = false   // In takeoff sequence
    var landingPadId: Int? = nil    // Object ID of reserved helipad/airstrip

    // Cargo (VC CargoClass) — passengers carried by transports (APC, TRAN, C17)
    var passengers: [Int] = []      // Object IDs of loaded passengers
    var isALoaner: Bool = false     // Transport is a loaner (auto-removed after delivery)

    // Flags (VC TechnoClass/ObjectClass)
    var isInLimbo: Bool = false     // In transport or off-map
    var isTethered: Bool = false    // Loosely attached to unit (docking)

    // Trigger
    var triggerName: String? = nil  // Attached trigger ID

    // Per-instance mission flags (Tier-1 editor; [ObjectFlags] section).
    // Default off so classic scenarios stay byte-identical.
    var isInvulnerable: Bool = false  // Immune to all damage (cannot be killed)
    var mustSurvive: Bool = false     // If this object dies, the mission is lost

    // Crate buff (temporary speed/firepower bonus from crate pickup)
    var crateBuff: CrateBuff = CrateBuff()

    // AI tactical flags
    var aiHitAndRunTick: Int? = nil     // Tick when hit-and-run engagement started
    var aiTacticalRole: AITacticalRole = .none  // Current tactical assignment

    // Computed cell position
    var cellX: Int { Int(worldX) / 24 }
    var cellY: Int { Int(worldY) / 24 }
    var cell: Int { cellY * 64 + cellX }

    // MARK: - Cached Type Data

    // These are resolved once at creation time for performance
    private(set) var cachedPrimaryWeapon: WeaponType? = nil
    private(set) var cachedSecondaryWeapon: WeaponType? = nil
    private(set) var cachedArmor: ArmorType = .none
    private(set) var cachedSightRange: Int = 3
    private(set) var cachedMaxStrength: Int = 100
    private(set) var cachedCost: Int = 0
    private(set) var cachedHasTurret: Bool = false
    private(set) var cachedSpeedType: SpeedType = .foot
    private(set) var cachedIsCrusher: Bool = false
    private(set) var cachedIsCrushable: Bool = false
    // Identity flags resolved once at type-cache time so combat/AI/movement
    // code can ask `obj.isHarvester` instead of `obj.typeName.uppercased() == "HARV"`.
    private(set) var cachedIsHarvester: Bool = false
    private(set) var cachedIsMCV: Bool = false
    private(set) var cachedIsGunboat: Bool = false
    private(set) var cachedIsCommando: Bool = false
    private(set) var cachedIsDefenseStructure: Bool = false
    private(set) var cachedIsPowerPlant: Bool = false
    private(set) var cachedIsRefinery: Bool = false
    private(set) var cachedIsAircraftPad: Bool = false
    private(set) var cachedIsWall: Bool = false
    private(set) var cachedIsSAMSite: Bool = false

    /// Resolve type data from tables and cache it
    private func cacheTypeData() {
        let upper = typeName.uppercased()
        switch kind {
        case .unit:
            // Check if this is an aircraft type
            if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
                cachedPrimaryWeapon = data.primaryWeapon
                cachedSecondaryWeapon = data.secondaryWeapon
                cachedArmor = data.armor
                cachedSightRange = data.sightRange
                cachedMaxStrength = data.strength
                cachedCost = data.cost
                cachedHasTurret = false
                cachedSpeedType = .winged
                ammo = data.maxAmmo
            } else if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
                cachedPrimaryWeapon = data.primaryWeapon
                cachedSecondaryWeapon = data.secondaryWeapon
                cachedArmor = data.armor
                cachedSightRange = data.sightRange
                cachedMaxStrength = data.strength
                cachedCost = data.cost
                cachedHasTurret = data.hasTurret
                cachedSpeedType = data.speed
                cachedIsCrusher = data.isCrusher
                cachedIsCrushable = data.isCrushable
                cachedIsHarvester = ut.isHarvester
                cachedIsMCV = ut.isMCV
                cachedIsGunboat = ut.isGunboat
                ammo = data.ammo
            }
        case .infantry:
            if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
                cachedPrimaryWeapon = data.primaryWeapon
                cachedSecondaryWeapon = data.secondaryWeapon
                cachedArmor = data.armor
                cachedSightRange = data.sightRange
                cachedMaxStrength = data.strength
                cachedCost = data.cost
                cachedSpeedType = .foot
                cachedIsCrushable = true  // All infantry are crushable
                cachedIsCommando = it.isCommando
            }
        case .structure:
            if let st = StructType.from(iniName: upper), let data = buildingTypeDataTable[st] {
                cachedPrimaryWeapon = data.primaryWeapon
                cachedSecondaryWeapon = data.secondaryWeapon
                cachedArmor = data.armor
                cachedSightRange = data.sightRange
                cachedMaxStrength = data.strength
                cachedCost = data.cost
                cachedHasTurret = data.hasTurret
                powerOutput = data.powerProduction
                powerDrain = data.powerDrain
                cachedIsDefenseStructure = st.isDefenseStructure
                cachedIsPowerPlant = st.isPowerPlant
                cachedIsRefinery = st.isRefinery
                cachedIsAircraftPad = st.isAircraftPad
                cachedIsWall = st.isWall
                cachedIsSAMSite = st.isSAMSite
            }
        }
    }

    // MARK: - Public Type Data Accessors (use cached values)

    var primaryWeapon: WeaponType? { cachedPrimaryWeapon }
    var secondaryWeapon: WeaponType? { cachedSecondaryWeapon }
    var armorType: ArmorType { cachedArmor }
    var sightRange: Int { effectiveSightRange }
    var baseSightRange: Int { cachedSightRange }
    var maxStrength: Int { cachedMaxStrength }
    var cost: Int { cachedCost }
    var hasTurret: Bool { cachedHasTurret }
    var speedType: SpeedType { cachedSpeedType }
    var isCrusher: Bool { cachedIsCrusher }
    var isCrushable: Bool { cachedIsCrushable }
    var isHarvester: Bool { cachedIsHarvester }
    var isMCV: Bool { cachedIsMCV }
    var isGunboat: Bool { cachedIsGunboat }
    var isCommando: Bool { cachedIsCommando }
    var isDefenseStructure: Bool { cachedIsDefenseStructure }
    var isPowerPlant: Bool { cachedIsPowerPlant }
    var isRefinery: Bool { cachedIsRefinery }
    var isAircraftPad: Bool { cachedIsAircraftPad }
    var isWall: Bool { cachedIsWall }
    var isSAMSite: Bool { cachedIsSAMSite }

    /// Damage ratio as fraction (1.0 = full health, 0.0 = dead)
    var healthFraction: Double {
        guard cachedMaxStrength > 0 else { return 0.0 }
        return Double(strength) / Double(cachedMaxStrength)
    }

    /// Effective movement speed including crate buff multiplier
    var effectiveSpeed: Double { speed * crateBuff.speedMultiplier }

    /// True if this object is armed (has a weapon)
    var isArmed: Bool { cachedPrimaryWeapon != nil }

    /// True if this object can move
    var isMobile: Bool { kind != .structure }

    // MARK: - Mission Validation (DEBUG only)

    /// Valid missions for each object kind. Missions not in this set trigger a debug warning.
    private static let structureMissions: Set<Mission> = [
        .guard_, .attack, .repair, .construction, .deconstruction, .selling, .stop, .sleep, .sticky, .missile
    ]
    private static let mobileMissions: Set<Mission> = [
        .guard_, .guardArea, .attack, .move, .harvest, .hunt, .timedHunt,
        .ambush, .retreat, .return_, .enter, .capture, .unload, .stop, .sleep, .sticky,
        .sabotage, .patrol
    ]

    #if DEBUG
    private func validateMission(_ newMission: Mission, old oldMission: Mission) {
        switch kind {
        case .structure:
            if !Self.structureMissions.contains(newMission) {
                print("WARNING: \(typeName)#\(id) (structure) assigned invalid mission .\(newMission.rawValue) (was .\(oldMission.rawValue))")
            }
        case .unit, .infantry:
            if !Self.mobileMissions.contains(newMission) {
                print("WARNING: \(typeName)#\(id) (\(kind)) assigned invalid mission .\(newMission.rawValue) (was .\(oldMission.rawValue))")
            }
        }
    }
    #endif

    init(id: Int, typeName: String, house: House, kind: ObjectKind,
         worldX: Double, worldY: Double, facing: Int, strength: Int,
         mission: Mission, speed: Double, subCell: Int = 0) {
        self.id = id
        self.typeName = typeName
        self.house = house
        self.kind = kind
        self.worldX = worldX
        self.worldY = worldY
        self.prevWorldX = worldX
        self.prevWorldY = worldY
        self.facing = facing
        self.turretFacing = facing
        self.strength = strength
        self.mission = mission
        self.speed = speed
        self.subCell = subCell
        // Cache type data after all properties are set
        cacheTypeData()
    }
}

// MARK: - Game World

class GameWorld {
    var objects: [GameObject] = []
    var nextObjectId: Int = 0
    var tickCount: Int = 0
    var randomSeed: UInt64 = 0       // Seed used for the deterministic sim RNG (see GameRandom)
    var theater: TheaterType = .temperate
    var mapBounds: MapBounds?
    /// Cell -> object IDs currently in that cell. Multiple entries allowed
    /// because the original C&C lets up to 5 infantry share a cell with
    /// sub-cell positioning. Vehicles still claim the cell exclusively;
    /// `cellHasVehicle()` and `cellInfantryCount()` consult this map.
    var occupancy: [Int: [Int]] = [:]
    var occupiedPads: Set<Int> = []  // object IDs of helipads/airstrips currently occupied by a landing/landed aircraft
    var playerHouse: House = .goodGuy
    var map: GameMap = GameMap()
    var crateState: CrateState = CrateState()

    // Control groups (0-9), each can hold multiple object IDs
    var controlGroups: [[Int]] = Array(repeating: [], count: 10)

    // O(1) object lookup by ID — maintained by addObject/removeDeadObjects
    private var objectIndex: [Int: GameObject] = [:]

    func addObject(_ obj: GameObject) {
        objects.append(obj)
        objectIndex[obj.id] = obj
    }

    func allocateId() -> Int {
        let id = nextObjectId
        nextObjectId += 1
        return id
    }

    func selectedObjects() -> [GameObject] {
        objects.filter { $0.isSelected }
    }

    func deselectAll() {
        for obj in objects {
            obj.isSelected = false
        }
    }

    /// Find an object by ID — O(1) dictionary lookup
    func findObject(id: Int) -> GameObject? {
        objectIndex[id]
    }

    /// Remove dead objects (strength <= 0) and update the index.
    /// Returns the removed objects for caller inspection.
    @discardableResult
    func removeDeadAndIndex() -> [GameObject] {
        let dead = objects.filter { $0.strength <= 0 }
        if dead.isEmpty { return [] }
        for obj in dead {
            objectIndex.removeValue(forKey: obj.id)
        }
        objects.removeAll { $0.strength <= 0 }
        return dead
    }

    /// Rebuild the entire object index from the objects array.
    /// Call after bulk-loading objects (e.g., scenario init).
    func rebuildObjectIndex() {
        objectIndex.removeAll(keepingCapacity: true)
        for obj in objects {
            objectIndex[obj.id] = obj
        }
    }

    /// Get all objects of a specific kind owned by a house
    func objects(ofKind kind: ObjectKind, house: House) -> [GameObject] {
        objects.filter { $0.kind == kind && $0.house == house && $0.strength > 0 }
    }

    /// Count living objects by kind and house.
    /// (filter{}.count, not count(where:) — the latter is Swift 6 only and breaks
    /// the Swift 5.10 CI runner; see .github/workflows/ci.yml.)
    func countObjects(ofKind kind: ObjectKind, house: House) -> Int {
        objects.filter { $0.kind == kind && $0.house == house && $0.strength > 0 }.count
    }

    /// Total power output for a house
    func totalPower(for house: House) -> Int {
        objects.filter { $0.kind == .structure && $0.house == house && $0.strength > 0 }
            .reduce(0) { $0 + $1.powerOutput }
    }

    /// Total power drain for a house
    func totalDrain(for house: House) -> Int {
        objects.filter { $0.kind == .structure && $0.house == house && $0.strength > 0 }
            .reduce(0) { $0 + $1.powerDrain }
    }

    /// Check if a house has a specific building type
    func hasBuilding(type: String, house: House) -> Bool {
        objects.contains { $0.kind == .structure && $0.house == house &&
            $0.strength > 0 && $0.typeName.caseInsensitiveCompare(type) == .orderedSame }
    }
}

