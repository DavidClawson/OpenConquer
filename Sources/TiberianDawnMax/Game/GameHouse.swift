import Foundation

// MARK: - House State
// Ported from Vanilla Conquer house.h/house.cpp
// Manages per-house economy, power, production, and tracking

// MARK: - Map Edge (reinforcement source)

/// The map edge a house's reinforcements arrive from — the INI `Edge=` key in
/// each house section (HOUSE.CPP:1672-1675, default SOURCE_NORTH). Only the four
/// edge sources are scenario-settable; shipping/beach/air are derived from team
/// composition (REINF.CPP:111-128).
enum MapEdge: String {
    case north = "North"
    case east = "East"
    case south = "South"
    case west = "West"

    static func from(_ string: String) -> MapEdge? {
        MapEdge(rawValue: string.trimmingCharacters(in: .whitespaces).capitalized)
    }
}

/// The edge a house's ground/air reinforcements enter from (`Edge=` in the
/// house's INI section; default north per HOUSE.CPP:351,1674).
func houseEdge(_ house: House) -> MapEdge {
    session.houseEdges[house] ?? .north
}

class HouseState {
    let type: House
    var credits: Int
    var tiberium: Int = 0           // Raw tiberium stored
    var capacity: Int = 0           // Total silo/refinery capacity
    var isHuman: Bool

    // Power system
    var powerOutput: Int = 0        // Total power generated
    var powerDrain: Int = 0         // Total power consumed

    // Tracking
    var unitsKilled: Int = 0
    var unitsLost: Int = 0
    var buildingsKilled: Int = 0
    var buildingsLost: Int = 0

    // Enemy-owned superweapons granted by a trigger (Nuke=BadGuy, Ion=GoodGuy).
    // The player's copies live on session.combat; this dict is only populated for
    // AI houses. Recreated per world by initHouseStates, so it resets with the
    // world — no save/load needed (a trigger grant is one-time and fires next tick).
    var superWeapons: [SpecialWeaponType: SuperWeapon] = [:]

    // Civ-evac win condition (HOUSE.H:128 IsCivEvacuated): set when a transport
    // aircraft owned by this house leaves the map carrying a civilian
    // (AIRCRAFT.CPP:836-842); polled by the Civ. Evac. trigger event
    // (HOUSE.CPP:1257). Never reset once set.
    var isCivEvacuated: Bool = false

    // AI state
    var isAlerted: Bool = false     // Under attack alert
    var alertTimer: Int = 0
    var productionEnabled: Bool = false  // Set by beginProduction trigger

    // AI production queues (separate from player's)
    var aiUnitQueue = ProductionQueue()
    var aiInfantryQueue = ProductionQueue()
    var aiStructureQueue = ProductionQueue()

    // AI base building state
    var aiBuildCycleCount: Int = 0       // Number of buildings placed (for defense scheduling)
    var aiLastAttackTick: Int = -9999    // Last tick an attack wave was sent
    var aiLastTeamFormTick: Int = 0      // Last tick the regular team-former ran (Gap #6)
    var aiLastBuildCheckTick: Int = 0    // Last tick building priorities were evaluated

    // AI tactical state — memory, scouting, harassment
    var aiKnownEnemyPositions: [(x: Double, y: Double, typeName: String, tick: Int)] = []
    var aiLastScoutTick: Int = 0         // When last scout was sent
    var aiScoutTargetCell: Int? = nil    // Current scout destination cell
    var aiScoutUnitId: Int? = nil        // Object ID of active scout unit
    var aiLastHitAndRunTick: Int = 0     // When last hit-and-run was initiated
    var aiLastHarassTick: Int = 0        // When last harvester harassment was sent
    var aiHarassUnitId: Int? = nil       // Object ID of active harass unit
    var aiFlankDelayTick: Int? = nil     // Tick when flank group should engage
    var aiFlankUnitIds: [Int] = []       // Object IDs in the flank group
    var aiFlankTargetX: Double? = nil    // Flank group's attack target X
    var aiFlankTargetY: Double? = nil    // Flank group's attack target Y
    var aiFlankAttackTargetId: Int? = nil // Flank group's attack target object ID

    // B3 decision layer (scaffolding; see Game/GameAIBrain.swift). Auto-reset
    // per world because initHouseStates() recreates fresh HouseStates.
    var aiBrain = AIBrain()

    init(type: House, credits: Int, isHuman: Bool) {
        self.type = type
        self.credits = credits
        self.isHuman = isHuman
    }

    /// Effective power ratio (1.0 = full power, <1.0 = low power)
    var powerFraction: Double {
        guard powerDrain > 0 else { return 1.0 }
        return min(1.0, Double(powerOutput) / Double(powerDrain))
    }

    /// True if power is sufficient (output >= drain)
    var hasPower: Bool { powerOutput >= powerDrain }

    /// True if power is critically low (<50%)
    var isLowPower: Bool { powerFraction < 0.5 }

    /// Spend credits, returns true if successful
    func spendCredits(_ amount: Int) -> Bool {
        if credits >= amount {
            credits -= amount
            // Reduce stored tiberium proportionally (spending draws from storage)
            tiberium = max(0, tiberium - amount)
            return true
        }
        return false
    }

    /// Add credits (from harvesting, selling, etc.)
    func addCredits(_ amount: Int) {
        credits += amount
    }

    /// Recalculate power from all owned buildings
    func recalculatePower() {
        guard let world = session.world else { return }
        powerOutput = 0
        powerDrain = 0
        capacity = 0

        for obj in world.objects {
            guard obj.house == type && obj.kind == .structure && obj.strength > 0 else { continue }
            powerOutput += obj.powerOutput
            powerDrain += obj.powerDrain

            // Tiberium capacity from refineries and silos
            let upper = obj.typeName.uppercased()
            if let st = StructType.from(iniName: upper), let data = buildingTypeDataTable[st] {
                capacity += data.tiberiumCapacity
            }
        }
    }

    /// Check if this house has all prerequisite buildings for a given struct flag
    func hasPrerequisites(_ prereq: StructFlag) -> Bool {
        guard let world = session.world else { return false }
        if prereq == .none { return true }

        // Check each prerequisite building type
        for (structType, data) in buildingTypeDataTable {
            // Map struct type to its flag
            let flag = structTypeToFlag(structType)
            if prereq.contains(flag) {
                // Check if we have this building
                let hasIt = world.objects.contains {
                    $0.house == type && $0.kind == .structure && $0.strength > 0 &&
                    $0.typeName.uppercased() == data.iniName.uppercased()
                }
                if !hasIt { return false }
            }
        }
        return true
    }

    /// Get set of building type names this house owns
    func ownedBuildingTypes() -> Set<String> {
        guard let world = session.world else { return [] }
        var result = Set<String>()
        for obj in world.objects {
            if obj.house == type && obj.kind == .structure && obj.strength > 0 {
                result.insert(obj.typeName.uppercased())
            }
        }
        return result
    }

    /// Check if this house can build a given unit type
    func canBuildUnit(_ unitData: UnitTypeData) -> Bool {
        let houseType = houseToHousesType(type)
        // Check ownership
        switch houseType {
        case .good:  if !unitData.ownable.contains(.good) { return false }
        case .bad:   if !unitData.ownable.contains(.bad) { return false }
        default: break
        }
        guard unitData.isBuildable else { return false }
        return hasPrerequisites(unitData.prerequisite)
    }

    /// Check if this house can build a given infantry type
    func canBuildInfantry(_ infData: InfantryTypeData) -> Bool {
        let houseType = houseToHousesType(type)
        switch houseType {
        case .good:  if !infData.ownable.contains(.good) { return false }
        case .bad:   if !infData.ownable.contains(.bad) { return false }
        default: break
        }
        guard infData.isBuildable else { return false }
        return hasPrerequisites(infData.prerequisite)
    }

    /// Check if this house can build a given building type
    func canBuildStructure(_ bldData: BuildingTypeData) -> Bool {
        let houseType = houseToHousesType(type)
        switch houseType {
        case .good:  if !bldData.ownable.contains(.good) { return false }
        case .bad:   if !bldData.ownable.contains(.bad) { return false }
        default: break
        }
        guard bldData.isBuildable else { return false }
        return hasPrerequisites(bldData.prerequisite)
    }
}

// MARK: - StructType to StructFlag Mapping

/// Map a StructType enum case to its corresponding prerequisite flag
func structTypeToFlag(_ st: StructType) -> StructFlag {
    switch st {
    case .weap:          return .weap
    case .gtower:        return .gtower
    case .atower:        return .atower
    case .obelisk:       return .obelisk
    case .radar:         return .radar
    case .turret:        return .turret
    case .const_:        return .const_
    case .refinery:      return .refinery
    case .storage:       return .storage
    case .helipad:       return .helipad
    case .sam:           return .sam
    case .airstrip:      return .airstrip
    case .power:         return .power
    case .advancedPower: return .advancedPower
    case .hospital:      return .hospital
    case .barracks:      return .barracks
    case .hand:          return .hand
    case .temple:        return .temple
    case .eye:           return .eye
    case .repair:        return .repair
    case .bioLab:        return .bioLab
    default:             return .none
    }
}

// MARK: - House Manager

/// Active house states for the current game

/// Get or create house state for a given house
func getHouseState(_ house: House) -> HouseState {
    if let state = session.houseStates[house] {
        return state
    }
    let state = HouseState(type: house, credits: 0, isHuman: false)
    session.houseStates[house] = state
    return state
}

/// Initialize house states from the current game world
func initHouseStates() {
    session.houseStates.removeAll()
    guard let world = session.world else { return }

    // Create house states for all houses present in the scenario
    var housesPresent = Set<House>()
    for obj in world.objects {
        housesPresent.insert(obj.house)
    }

    for house in housesPresent {
        let isHuman = (house == world.playerHouse)
        let credits = isHuman ? session.sidebarCredits : 5000  // AI gets default credits
        let state = HouseState(type: house, credits: credits, isHuman: isHuman)
        state.recalculatePower()
        session.houseStates[house] = state
    }

    print("GameHouse: Initialized \(session.houseStates.count) house states")
    for (house, state) in session.houseStates {
        print("  \(house.rawValue): credits=\(state.credits) power=\(state.powerOutput)/\(state.powerDrain)")
    }
}

/// Recalculate all house power (call after buildings change)
func recalculateAllHousePower() {
    for (_, state) in session.houseStates {
        state.recalculatePower()
    }

    // EVA low-power announcement (edge-triggered: only when transitioning to low power)
    if let world = session.world {
        let playerState = getHouseState(world.playerHouse)
        let isLow = !playerState.hasPower && playerState.powerDrain > 0
        if isLow && !session.wasLowPower {
            session.speakEVA(.lowPower, cooldownTicks: 150)
        }
        session.wasLowPower = isLow
    }
}
