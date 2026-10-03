import Foundation

// MARK: - Game Object Types

package enum ObjectKind {
    case unit
    case infantry
    case structure
}

/// AI tactical role assigned to a unit for coordinated behaviors
package enum AITacticalRole {
    case none           // No special role
    case scout          // Scouting / recon
    case hitAndRun      // Hit-and-run attacker
    case harasser       // Harvester harasser
    case flank          // Flanking group member
}

package enum Mission: String {
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

    package static func from(_ string: String) -> Mission {
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
package class GameObject {
    package let id: Int
    package let typeName: String
    package var house: House                // Mutable for capture
    package let kind: ObjectKind

    // Position in double-pixel coordinates (sub-pixel smooth)
    package var worldX: Double
    package var worldY: Double
    package var prevWorldX: Double          // Previous tick position (for render interpolation)
    package var prevWorldY: Double
    package var facing: Int                 // 0-255 C&C facing (0=N, 64=E, 128=S, 192=W)
    package var turretFacing: Int = 0       // Turret facing for units with turrets
    package var strength: Int               // Hit points

    // Mission state (VC MissionClass)
    package var mission: Mission
    {
        didSet {
            #if DEBUG
            validateMission(mission, old: oldValue)
            #endif
        }
    }
    package var missionQueue: Mission? = nil         // Queued next mission
    package var suspendedMission: Mission? = nil     // Saved mission for resume
    package var missionStatus: Int = 0               // Sub-state within current mission
    package var isSelected: Bool = false

    // Movement (VC FootClass)
    package var moveTargetX: Double? = nil
    package var moveTargetY: Double? = nil
    package var speed: Double               // Pixels per tick
    package var movePath: [(cellX: Int, cellY: Int)] = []
    package var navTargetId: Int? = nil     // Navigation target object ID
    package var group: Int = -1             // Control group (0-9, -1 = none)
    package var isAttackMoving: Bool = false // Attack-move: scan for enemies while moving
    package var moveWaypoints: [(x: Double, y: Double)] = []  // Queued waypoints (shift+click)
    package var groupMoveSpeed: Double? = nil  // Squad speed matching: move at slowest unit's speed

    // Patrol route
    package var patrolWaypoints: [(x: Double, y: Double)] = []  // Ordered patrol waypoints
    package var patrolIndex: Int = 0                              // Current waypoint in the loop

    // Combat (VC TechnoClass)
    package var attackTarget: Int? = nil    // Target object ID
    package var suspendedTarget: Int? = nil // Saved target (VC SuspendedTarCom)
    package var reloadTimer: Int = 0
    package var lastFireTick: Int = 0       // Tick when unit last fired (for muzzle flash)
    package var lastDamagedTick: Int = 0    // Tick when unit last took damage (for damage flash)
    package var ammo: Int = -1              // -1 = unlimited

    // Veterancy system
    package var killCount: Int = 0          // Total kills scored by this unit
    /// Veteran level: 0=Regular, 1=Veteran (3 kills), 2=Elite (7 kills).
    /// Returns 0 when the active ruleset disables veterancy (the classic game had
    /// no promotions), which removes every downstream bonus in one place. Kills
    /// still accrue in `killCount` so toggling the rule mid-session is lossless.
    package var veteranLevel: Int {
        guard session.rules.veterancyEnabled else { return 0 }
        if killCount >= 7 { return 2 }
        if killCount >= 3 { return 1 }
        return 0
    }

    // Harvesting (units only)
    package var tiberiumLoad: Int = 0
    package var dockTimer: Int = 0          // Transient counter driving the refinery dock slide-in/out animation
    package var preferredRefineryID: Int? = nil  // Player-directed dock target; harvester docks here instead of the nearest PROC
    package var harvesterForceDock: Bool = false // Player ordered "return to refinery" — go dock now even if not full

    // Repair facility (FIX) — vehicle the player sent to a repair bay to be healed
    package var repairBuildingID: Int? = nil

    // Transport boarding — infantry the player ordered into a transport
    // (walks over and loads as a passenger; drives the civ-evac flow)
    package var enterTransportID: Int? = nil

    // Animation state (infantry walk cycle, fire animation)
    package var animFrame: Int = 0          // Current animation frame offset (0 = stand, 1+ = walk cycle)
    package var animTickCounter: Int = 0    // Tick counter for animation timing
    package var isFiringAnim: Bool = false  // True when playing fire animation
    package var fireAnimTicks: Int = 0      // Countdown for fire animation duration

    // Infantry-specific (VC InfantryClass)
    package var subCell: Int
    package var fear: UInt8 = 0             // 0-255: 0=fearless, 200=panic
    package var isProne: Bool = false       // Crawling/prone

    // Building-specific (VC BuildingClass)
    package var isRepairing: Bool = false
    package var lastWhoHurtMe: House? = nil // For kill credit
    package var lastAttackerId: Int? = nil  // Specific attacker — drives retaliation/return-fire
    package var rallyPointX: Double? = nil  // Rally point world X for production buildings
    package var rallyPointY: Double? = nil  // Rally point world Y for production buildings
    package var powerOutput: Int = 0        // Power generated by this building
    package var powerDrain: Int = 0         // Power consumed by this building
    package var buildUpFrame: Int = -1      // -1 = no build anim, 0+ = current build-up frame
    package var buildUpTotalFrames: Int = 0 // Total frames in build-up sequence
    package var buildUpDelay: Int = 0       // Ticks until next build-up frame advance
    package var samDeployState: Int = 0     // 0 = retracted, 1-31 = deploying/deployed frame

    // Aircraft-specific (VC AircraftClass)
    package var isAircraft: Bool = false    // True if this is an aircraft object
    package var altitude: Int = 0           // 0=ground, 24=flight level
    package var isLanding: Bool = false     // In landing sequence
    package var isTakingOff: Bool = false   // In takeoff sequence
    package var landingPadId: Int? = nil    // Object ID of reserved helipad/airstrip

    // Cargo (VC CargoClass) — passengers carried by transports (APC, TRAN, C17)
    package var passengers: [Int] = []      // Object IDs of loaded passengers
    package var unloadTether: [Int] = []    // Hovercraft: just-unloaded units it waits on before leaving
    package var leftMap: Bool = false       // Removed by leaving the map (a classic delete, not a loss)
    package var baseAttackTimerEnd: Int = 0 // Tick until this attacker stops triggering rescues (BaseAttackTimer)
    package var isALoaner: Bool = false     // Transport is a loaner (auto-removed after delivery)

    // Flags (VC TechnoClass/ObjectClass)
    package var isInLimbo: Bool = false     // In transport or off-map
    package var isTethered: Bool = false    // Loosely attached to unit (docking)

    // Trigger
    package var triggerName: String? = nil  // Attached trigger ID

    // Per-instance mission flags (Tier-1 editor; [ObjectFlags] section).
    // Default off so classic scenarios stay byte-identical.
    package var isInvulnerable: Bool = false  // Immune to all damage (cannot be killed)
    package var mustSurvive: Bool = false     // If this object dies, the mission is lost

    // Crate buff (temporary speed/firepower bonus from crate pickup)
    package var crateBuff: CrateBuff = CrateBuff()

    // AI tactical flags
    package var aiHitAndRunTick: Int? = nil     // Tick when hit-and-run engagement started
    package var aiTacticalRole: AITacticalRole = .none  // Current tactical assignment

    // Computed cell position
    package var cellX: Int { Int(worldX) / 24 }
    package var cellY: Int { Int(worldY) / 24 }
    package var cell: Int { cellY * 64 + cellX }

    // MARK: - Cached Type Data

    // These are resolved once at creation time for performance
    package private(set) var cachedPrimaryWeapon: WeaponType? = nil
    package private(set) var cachedSecondaryWeapon: WeaponType? = nil
    package private(set) var cachedArmor: ArmorType = .none
    package private(set) var cachedSightRange: Int = 3
    package private(set) var cachedMaxStrength: Int = 100
    package private(set) var cachedCost: Int = 0
    package private(set) var cachedHasTurret: Bool = false
    package private(set) var cachedSpeedType: SpeedType = .foot
    package private(set) var cachedIsCrusher: Bool = false
    package private(set) var cachedIsCrushable: Bool = false
    // Identity flags resolved once at type-cache time so combat/AI/movement
    // code can ask `obj.isHarvester` instead of `obj.typeName.uppercased() == "HARV"`.
    package private(set) var cachedIsHarvester: Bool = false
    package private(set) var cachedIsMCV: Bool = false
    package private(set) var cachedIsGunboat: Bool = false
    package private(set) var cachedIsCommando: Bool = false
    package private(set) var cachedRisk: Int = 0
    package private(set) var cachedIsDefenseStructure: Bool = false
    package private(set) var cachedIsPowerPlant: Bool = false
    package private(set) var cachedIsRefinery: Bool = false
    package private(set) var cachedIsAircraftPad: Bool = false
    package private(set) var cachedIsWall: Bool = false
    package private(set) var cachedIsSAMSite: Bool = false

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
                cachedRisk = data.riskValue
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
                cachedRisk = data.riskValue
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

    package var primaryWeapon: WeaponType? { cachedPrimaryWeapon }
    package var secondaryWeapon: WeaponType? { cachedSecondaryWeapon }
    package var armorType: ArmorType { cachedArmor }
    package var sightRange: Int { effectiveSightRange }
    package var baseSightRange: Int { cachedSightRange }
    package var maxStrength: Int { cachedMaxStrength }
    package var cost: Int { cachedCost }
    package var hasTurret: Bool { cachedHasTurret }
    package var speedType: SpeedType { cachedSpeedType }
    package var isCrusher: Bool { cachedIsCrusher }
    package var isCrushable: Bool { cachedIsCrushable }
    package var isHarvester: Bool { cachedIsHarvester }
    package var isMCV: Bool { cachedIsMCV }
    package var isGunboat: Bool { cachedIsGunboat }
    package var isCommando: Bool { cachedIsCommando }
    /// TechnoTypeClass::Risk — how dangerous this type is, for rescue sizing.
    package var riskValue: Int { cachedRisk }
    package var isDefenseStructure: Bool { cachedIsDefenseStructure }
    package var isPowerPlant: Bool { cachedIsPowerPlant }
    package var isRefinery: Bool { cachedIsRefinery }
    package var isAircraftPad: Bool { cachedIsAircraftPad }
    package var isWall: Bool { cachedIsWall }
    package var isSAMSite: Bool { cachedIsSAMSite }

    /// Damage ratio as fraction (1.0 = full health, 0.0 = dead)
    package var healthFraction: Double {
        guard cachedMaxStrength > 0 else { return 0.0 }
        return Double(strength) / Double(cachedMaxStrength)
    }

    /// Effective movement speed including crate buff multiplier
    package var effectiveSpeed: Double { speed * crateBuff.speedMultiplier }

    /// True if this object is armed (has a weapon)
    package var isArmed: Bool { cachedPrimaryWeapon != nil }

    /// True if this object can move
    package var isMobile: Bool { kind != .structure }

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

    package init(id: Int, typeName: String, house: House, kind: ObjectKind,
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

package class GameWorld {
    package var objects: [GameObject] = []
    package var nextObjectId: Int = 0
    package var tickCount: Int = 0
    package var randomSeed: UInt64 = 0       // Seed used for the deterministic sim RNG (see GameRandom)
    package var theater: TheaterType = .temperate
    package var mapBounds: MapBounds?
    /// Cell -> object IDs currently in that cell. Multiple entries allowed
    /// because the original C&C lets up to 5 infantry share a cell with
    /// sub-cell positioning. Vehicles still claim the cell exclusively;
    /// `cellHasVehicle()` and `cellInfantryCount()` consult this map.
    package var occupancy: [Int: [Int]] = [:]
    package var occupiedPads: Set<Int> = []  // object IDs of helipads/airstrips currently occupied by a landing/landed aircraft
    package var playerHouse: House = .goodGuy
    package var map: GameMap = GameMap()
    package var crateState: CrateState = CrateState()

    // Control groups (0-9), each can hold multiple object IDs
    package var controlGroups: [[Int]] = Array(repeating: [], count: 10)
    /// Player orders waiting for the next tick, and every order applied so far
    /// (Game/PlayerCommands.swift).
    package var pendingCommands: [PlayerCommand] = []
    package var commandLog: [LoggedCommand] = []

    // O(1) object lookup by ID — maintained by addObject/removeDeadObjects
    private var objectIndex: [Int: GameObject] = [:]

    package func addObject(_ obj: GameObject) {
        objects.append(obj)
        objectIndex[obj.id] = obj
    }

    package func allocateId() -> Int {
        let id = nextObjectId
        nextObjectId += 1
        return id
    }

    package func selectedObjects() -> [GameObject] {
        objects.filter { $0.isSelected }
    }

    package func deselectAll() {
        for obj in objects {
            obj.isSelected = false
        }
    }

    /// Find an object by ID — O(1) dictionary lookup
    package func findObject(id: Int) -> GameObject? {
        objectIndex[id]
    }

    /// Remove dead objects (strength <= 0) and update the index.
    /// Returns the removed objects for caller inspection.
    @discardableResult
    package func removeDeadAndIndex() -> [GameObject] {
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
    package func rebuildObjectIndex() {
        objectIndex.removeAll(keepingCapacity: true)
        for obj in objects {
            objectIndex[obj.id] = obj
        }
    }

    /// Get all objects of a specific kind owned by a house
    package func objects(ofKind kind: ObjectKind, house: House) -> [GameObject] {
        objects.filter { $0.kind == kind && $0.house == house && $0.strength > 0 }
    }

    /// Count living objects by kind and house.
    /// (filter{}.count, not count(where:) — the latter is Swift 6 only and breaks
    /// the Swift 5.10 CI runner; see .github/workflows/ci.yml.)
    package func countObjects(ofKind kind: ObjectKind, house: House) -> Int {
        objects.filter { $0.kind == kind && $0.house == house && $0.strength > 0 }.count
    }

    /// Total power output for a house
    package func totalPower(for house: House) -> Int {
        objects.filter { $0.kind == .structure && $0.house == house && $0.strength > 0 }
            .reduce(0) { $0 + $1.powerOutput }
    }

    /// Total power drain for a house
    package func totalDrain(for house: House) -> Int {
        objects.filter { $0.kind == .structure && $0.house == house && $0.strength > 0 }
            .reduce(0) { $0 + $1.powerDrain }
    }

    /// Check if a house has a specific building type
    package func hasBuilding(type: String, house: House) -> Bool {
        objects.contains { $0.kind == .structure && $0.house == house &&
            $0.strength > 0 && $0.typeName.caseInsensitiveCompare(type) == .orderedSame }
    }

    package init() {}
}

