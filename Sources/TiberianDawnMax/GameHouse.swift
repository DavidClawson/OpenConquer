import Foundation

// MARK: - House State
// Ported from Vanilla Conquer house.h/house.cpp
// Manages per-house economy, power, production, and tracking

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

    // AI state
    var isAlerted: Bool = false     // Under attack alert
    var alertTimer: Int = 0

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
        if bldData.isWall { return false }  // Walls not sidebar-buildable
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
}
