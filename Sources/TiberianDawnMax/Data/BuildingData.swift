import Foundation

// MARK: - Building Type Data
// Ported faithfully from Vanilla Conquer bdata.cpp BuildingTypeClass constructors

struct BuildingTypeData {
    let type: StructType
    let iniName: String
    let fullName: String

    // Build info
    let buildLevel: Int
    let prerequisite: StructFlag
    let cost: Int
    let scenario: Int           // First available scenario
    let ownable: HouseFlag

    // Combat
    let strength: Int           // Max HP
    let armor: ArmorType
    let primaryWeapon: WeaponType?
    let secondaryWeapon: WeaponType?
    let sightRange: Int         // Cells

    // Power
    let powerProduction: Int    // Power generated
    let powerDrain: Int         // Power consumed

    // Economy
    let tiberiumCapacity: Int   // Tiberium storage capacity

    // Physical
    let sizeW: Int              // Width in cells
    let sizeH: Int              // Height in cells

    // Flags
    let isBuildable: Bool
    let hasTurret: Bool
    let isCapturable: Bool
    let isWall: Bool
    let isCivilian: Bool

    // AI ratings
    let riskValue: Int
    let rewardValue: Int
}

// MARK: - Building Type Data Table

var buildingTypeDataTable: [StructType: BuildingTypeData] = [

    // MARK: Weapons Factory
    .weap: BuildingTypeData(
        type: .weap, iniName: "WEAP", fullName: "Weapons Factory",
        buildLevel: 2, prerequisite: .refinery, cost: 2000, scenario: 5, ownable: .gdiAll,
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 30, tiberiumCapacity: 0,
        sizeW: 3, sizeH: 3,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 86
    ),

    // MARK: Guard Tower
    .gtower: BuildingTypeData(
        type: .gtower, iniName: "GTWR", fullName: "Guard Tower",
        buildLevel: 2, prerequisite: .barracks, cost: 500, scenario: 7, ownable: .gdiAll,
        strength: 200, armor: .wood, primaryWeapon: .chainGun, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 10, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 25
    ),

    // MARK: Advanced Guard Tower
    .atower: BuildingTypeData(
        type: .atower, iniName: "ATWR", fullName: "Advanced Guard Tower",
        buildLevel: 4, prerequisite: .radar, cost: 1000, scenario: 13, ownable: .gdiAll,
        strength: 300, armor: .aluminum, primaryWeapon: .towTwo, secondaryWeapon: nil,
        sightRange: 4, powerProduction: 0, powerDrain: 20, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 30
    ),

    // MARK: Obelisk of Light
    .obelisk: BuildingTypeData(
        type: .obelisk, iniName: "OBLI", fullName: "Obelisk of Light",
        buildLevel: 4, prerequisite: .radar, cost: 1500, scenario: 11, ownable: .nodAll,
        strength: 200, armor: .aluminum, primaryWeapon: .obeliskLaser, secondaryWeapon: nil,
        sightRange: 5, powerProduction: 0, powerDrain: 150, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 35
    ),

    // MARK: Communications Center
    .radar: BuildingTypeData(
        type: .radar, iniName: "HQ", fullName: "Communications Center",
        buildLevel: 2, prerequisite: .refinery, cost: 1000, scenario: 3, ownable: .bothAll,
        strength: 500, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 10, powerProduction: 0, powerDrain: 40, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 20
    ),

    // MARK: Gun Turret
    .turret: BuildingTypeData(
        type: .turret, iniName: "GUN", fullName: "Gun Turret",
        buildLevel: 2, prerequisite: .barracks, cost: 600, scenario: 8, ownable: .nodAll,
        strength: 200, armor: .steel, primaryWeapon: .turretGun, secondaryWeapon: nil,
        sightRange: 5, powerProduction: 0, powerDrain: 20, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: true, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 26
    ),

    // MARK: Construction Yard
    .const_: BuildingTypeData(
        type: .const_, iniName: "FACT", fullName: "Construction Yard",
        buildLevel: 99, prerequisite: .none, cost: 5000, scenario: 1, ownable: .bothAll,
        strength: 400, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 30, powerDrain: 15, tiberiumCapacity: 0,
        sizeW: 3, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 70
    ),

    // MARK: Tiberium Refinery
    .refinery: BuildingTypeData(
        type: .refinery, iniName: "PROC", fullName: "Tiberium Refinery",
        buildLevel: 1, prerequisite: .power, cost: 2000, scenario: 2, ownable: .bothAll,
        strength: 450, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 4, powerProduction: 10, powerDrain: 40, tiberiumCapacity: 1000,
        sizeW: 3, sizeH: 3,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 55
    ),

    // MARK: Tiberium Silo
    .storage: BuildingTypeData(
        type: .storage, iniName: "SILO", fullName: "Tiberium Silo",
        buildLevel: 1, prerequisite: .refinery, cost: 150, scenario: 2, ownable: .bothAll,
        strength: 150, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 0, powerDrain: 10, tiberiumCapacity: 1500,
        sizeW: 2, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 16
    ),

    // MARK: Helipad
    .helipad: BuildingTypeData(
        type: .helipad, iniName: "HPAD", fullName: "Helipad",
        buildLevel: 6, prerequisite: .barracks, cost: 1500, scenario: 10, ownable: .bothAll,
        strength: 400, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 10, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 65
    ),

    // MARK: SAM Site
    .sam: BuildingTypeData(
        type: .sam, iniName: "SAM", fullName: "SAM Site",
        buildLevel: 6, prerequisite: .barracks, cost: 750, scenario: 5, ownable: .nodAll,
        strength: 200, armor: .steel, primaryWeapon: .nike, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 20, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: true, hasTurret: true, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 40
    ),

    // MARK: Airstrip
    .airstrip: BuildingTypeData(
        type: .airstrip, iniName: "AFLD", fullName: "Airstrip",
        buildLevel: 2, prerequisite: .refinery, cost: 2000, scenario: 5, ownable: .nodAll,
        strength: 500, armor: .steel, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 5, powerProduction: 0, powerDrain: 30, tiberiumCapacity: 0,
        sizeW: 4, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 86
    ),

    // MARK: Power Plant
    .power: BuildingTypeData(
        type: .power, iniName: "NUKE", fullName: "Power Plant",
        buildLevel: 0, prerequisite: .none, cost: 300, scenario: 1, ownable: .bothAll,
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 100, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 50
    ),

    // MARK: Advanced Power Plant
    .advancedPower: BuildingTypeData(
        type: .advancedPower, iniName: "NUK2", fullName: "Advanced Power Plant",
        buildLevel: 5, prerequisite: .power, cost: 700, scenario: 13, ownable: .bothAll,
        strength: 300, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 200, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 75
    ),

    // MARK: Hospital
    .hospital: BuildingTypeData(
        type: .hospital, iniName: "HOSP", fullName: "Hospital",
        buildLevel: 99, prerequisite: .barracks, cost: 500, scenario: 99, ownable: .bothAll,
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 0, powerDrain: 20, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 20
    ),

    // MARK: Barracks (GDI)
    .barracks: BuildingTypeData(
        type: .barracks, iniName: "PYLE", fullName: "Barracks",
        buildLevel: 0, prerequisite: .power, cost: 300, scenario: 1, ownable: .gdiAll,
        strength: 400, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 20, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 60
    ),

    // MARK: Tanker
    .tanker: BuildingTypeData(
        type: .tanker, iniName: "ARCO", fullName: "Tanker",
        buildLevel: 99, prerequisite: .power, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 100, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 80, rewardValue: 1
    ),

    // MARK: Repair Facility
    .repair: BuildingTypeData(
        type: .repair, iniName: "FIX", fullName: "Repair Facility",
        buildLevel: 5, prerequisite: .power, cost: 1200, scenario: 8, ownable: .bothAll,
        strength: 400, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 30, tiberiumCapacity: 0,
        sizeW: 3, sizeH: 3,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 46
    ),

    // MARK: Bio Lab
    .bioLab: BuildingTypeData(
        type: .bioLab, iniName: "BIO", fullName: "Bio Lab",
        buildLevel: 99, prerequisite: .hospital, cost: 500, scenario: 99, ownable: .nodAll,
        strength: 300, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 0, powerDrain: 40, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 1
    ),

    // MARK: Hand of Nod
    .hand: BuildingTypeData(
        type: .hand, iniName: "HAND", fullName: "Hand of Nod",
        buildLevel: 0, prerequisite: .power, cost: 300, scenario: 2, ownable: .nodAll,
        strength: 400, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 3, powerProduction: 0, powerDrain: 20, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 3,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 61
    ),

    // MARK: Temple of Nod
    .temple: BuildingTypeData(
        type: .temple, iniName: "TMPL", fullName: "Temple of Nod",
        buildLevel: 7, prerequisite: .radar, cost: 3000, scenario: 13, ownable: .nodAll,
        strength: 1000, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 4, powerProduction: 0, powerDrain: 150, tiberiumCapacity: 0,
        sizeW: 3, sizeH: 3,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 20
    ),

    // MARK: Advanced Communications Center
    .eye: BuildingTypeData(
        type: .eye, iniName: "EYE", fullName: "Advanced Communications Center",
        buildLevel: 7, prerequisite: .radar, cost: 2800, scenario: 13, ownable: .gdiAll,
        strength: 500, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 10, powerProduction: 0, powerDrain: 200, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: true, hasTurret: false, isCapturable: true, isWall: false, isCivilian: false,
        riskValue: 80, rewardValue: 100
    ),

    // MARK: Mission Building
    .mission: BuildingTypeData(
        type: .mission, iniName: "MISS", fullName: "Mission",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 99, ownable: .bothAll,
        strength: 800, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 4, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 3, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 80, rewardValue: 1
    ),

    // MARK: - Civilian Structures (V01-V37)
    // Placeholder entries with data from bdata.cpp — sizes match VC BSIZE values

    .v01: BuildingTypeData(
        type: .v01, iniName: "V01", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v02: BuildingTypeData(
        type: .v02, iniName: "V02", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v03: BuildingTypeData(
        type: .v03, iniName: "V03", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v04: BuildingTypeData(
        type: .v04, iniName: "V04", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v05: BuildingTypeData(
        type: .v05, iniName: "V05", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v06: BuildingTypeData(
        type: .v06, iniName: "V06", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v07: BuildingTypeData(
        type: .v07, iniName: "V07", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v08: BuildingTypeData(
        type: .v08, iniName: "V08", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v09: BuildingTypeData(
        type: .v09, iniName: "V09", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v10: BuildingTypeData(
        type: .v10, iniName: "V10", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v11: BuildingTypeData(
        type: .v11, iniName: "V11", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v12: BuildingTypeData(
        type: .v12, iniName: "V12", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v13: BuildingTypeData(
        type: .v13, iniName: "V13", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v14: BuildingTypeData(
        type: .v14, iniName: "V14", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v15: BuildingTypeData(
        type: .v15, iniName: "V15", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v16: BuildingTypeData(
        type: .v16, iniName: "V16", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v17: BuildingTypeData(
        type: .v17, iniName: "V17", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v18: BuildingTypeData(
        type: .v18, iniName: "V18", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v19: BuildingTypeData(
        type: .v19, iniName: "V19", fullName: "Pump Station",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v20: BuildingTypeData(
        type: .v20, iniName: "V20", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v21: BuildingTypeData(
        type: .v21, iniName: "V21", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v22: BuildingTypeData(
        type: .v22, iniName: "V22", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v23: BuildingTypeData(
        type: .v23, iniName: "V23", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v24: BuildingTypeData(
        type: .v24, iniName: "V24", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v25: BuildingTypeData(
        type: .v25, iniName: "V25", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v26: BuildingTypeData(
        type: .v26, iniName: "V26", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v27: BuildingTypeData(
        type: .v27, iniName: "V27", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v28: BuildingTypeData(
        type: .v28, iniName: "V28", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v29: BuildingTypeData(
        type: .v29, iniName: "V29", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v30: BuildingTypeData(
        type: .v30, iniName: "V30", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v31: BuildingTypeData(
        type: .v31, iniName: "V31", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v32: BuildingTypeData(
        type: .v32, iniName: "V32", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v33: BuildingTypeData(
        type: .v33, iniName: "V33", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 2, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v34: BuildingTypeData(
        type: .v34, iniName: "V34", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v35: BuildingTypeData(
        type: .v35, iniName: "V35", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v36: BuildingTypeData(
        type: .v36, iniName: "V36", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0, ownable: [.neutral, .allMulti, .jp],
        strength: 200, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 1, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    .v37: BuildingTypeData(
        type: .v37, iniName: "V37", fullName: "Civilian Structure",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 0,
        ownable: [.neutral, .allMulti, .jp, .good],
        strength: 300, armor: .wood, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 4, sizeH: 2,
        isBuildable: false, hasTurret: false, isCapturable: false, isWall: false, isCivilian: true,
        riskValue: 0, rewardValue: 2
    ),

    // MARK: - Walls
    // From bdata.cpp wall entries — strength=1 (auto-replaced by wall HP system), armor=aluminum

    .sandbagWall: BuildingTypeData(
        type: .sandbagWall, iniName: "SBAG", fullName: "Sandbag Wall",
        buildLevel: 2, prerequisite: .none, cost: 50, scenario: 5, ownable: .bothAll,
        strength: 1, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: false, isWall: true, isCivilian: false,
        riskValue: 0, rewardValue: 0
    ),

    .cycloneWall: BuildingTypeData(
        type: .cycloneWall, iniName: "CYCL", fullName: "Cyclone Fence",
        buildLevel: 5, prerequisite: .none, cost: 75, scenario: 9, ownable: .bothAll,
        strength: 1, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: false, isWall: true, isCivilian: false,
        riskValue: 0, rewardValue: 0
    ),

    .brickWall: BuildingTypeData(
        type: .brickWall, iniName: "BRIK", fullName: "Concrete Wall",
        buildLevel: 7, prerequisite: .none, cost: 100, scenario: 13, ownable: .bothAll,
        strength: 1, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: false, isWall: true, isCivilian: false,
        riskValue: 0, rewardValue: 0
    ),

    .barbwireWall: BuildingTypeData(
        type: .barbwireWall, iniName: "BARB", fullName: "Barbwire Fence",
        buildLevel: 98, prerequisite: .none, cost: 25, scenario: 98, ownable: .civAll,
        strength: 1, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: false, isWall: true, isCivilian: false,
        riskValue: 0, rewardValue: 0
    ),

    .woodWall: BuildingTypeData(
        type: .woodWall, iniName: "WOOD", fullName: "Wood Fence",
        buildLevel: 99, prerequisite: .none, cost: 25, scenario: 98,
        ownable: [.neutral, .allMulti, .jp, .good],
        strength: 1, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0, powerProduction: 0, powerDrain: 0, tiberiumCapacity: 0,
        sizeW: 1, sizeH: 1,
        isBuildable: true, hasTurret: false, isCapturable: false, isWall: true, isCivilian: false,
        riskValue: 0, rewardValue: 0
    ),
]

// MARK: - Lookup Helpers

func getBuildingTypeData(_ type: StructType) -> BuildingTypeData? {
    return buildingTypeDataTable[type]
}

func getBuildingTypeDataByName(_ iniName: String) -> BuildingTypeData? {
    guard let type = StructType.from(iniName: iniName) else { return nil }
    return buildingTypeDataTable[type]
}

/// Returns the footprint size (width x height in cells) for the given building type.
func buildingSizeFromType(_ type: StructType) -> (w: Int, h: Int) {
    guard let data = buildingTypeDataTable[type] else {
        return (w: 1, h: 1)
    }
    return (w: data.sizeW, h: data.sizeH)
}
