import Foundation

// MARK: - Unit Type Data
// Ported faithfully from Vanilla Conquer udata.cpp UnitTypeClass constructors

struct UnitTypeData {
    let type: UnitType
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
    let ammo: Int               // -1 = unlimited

    // Movement
    let speed: SpeedType
    let maxSpeed: MPHType
    let rot: Int                // Rate of turn (degrees per tick)

    // Flags
    let isBuildable: Bool
    let isLeader: Bool
    let hasTurret: Bool
    let isTwoShooter: Bool      // Fires multiple shots
    let isTransporter: Bool
    let isCrushable: Bool
    let isCrusher: Bool
    let isHarvester: Bool
    let isCloakable: Bool
    let isRepairable: Bool
    let hasCrew: Bool
    let isGigundo: Bool         // Extra large sprite
    let isStealthy: Bool        // Invisible to radar
    let isAnimating: Bool       // Constant animation
    let isLockTurret: Bool      // Turret locked while moving

    // AI ratings
    let riskValue: Int
    let rewardValue: Int

    // Death animation
    let explosion: AnimType

    // Default mission
    let defaultMission: MissionType
}

// MARK: - Unit Type Data Table

var unitTypeDataTable: [UnitType: UnitTypeData] = [

    .htank: UnitTypeData(
        type: .htank, iniName: "HTNK", fullName: "Mammoth Tank",
        buildLevel: 5, prerequisite: .repair, cost: 1500, scenario: 13, ownable: .gdiAll,
        strength: 600, armor: .steel, primaryWeapon: .w120mm, secondaryWeapon: .mammothTusk,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .mediumSlow, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: true,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: true,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 80, explosion: .artExp1, defaultMission: .hunt
    ),

    .mtank: UnitTypeData(
        type: .mtank, iniName: "MTNK", fullName: "Medium Tank",
        buildLevel: 3, prerequisite: .none, cost: 800, scenario: 7, ownable: .gdiAll,
        strength: 400, armor: .steel, primaryWeapon: .w105mm, secondaryWeapon: nil,
        sightRange: 3, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: true,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 62, explosion: .frag2, defaultMission: .hunt
    ),

    .ltank: UnitTypeData(
        type: .ltank, iniName: "LTNK", fullName: "Light Tank",
        buildLevel: 3, prerequisite: .none, cost: 600, scenario: 5, ownable: .nodAll,
        strength: 300, armor: .steel, primaryWeapon: .w75mm, secondaryWeapon: nil,
        sightRange: 3, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 56, explosion: .frag1, defaultMission: .hunt
    ),

    .stank: UnitTypeData(
        type: .stank, iniName: "STNK", fullName: "Stealth Tank",
        buildLevel: 5, prerequisite: .radar, cost: 900, scenario: 12, ownable: .nodAll,
        strength: 110, armor: .aluminum, primaryWeapon: .dragon, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .mediumFast, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: false, isTwoShooter: true,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: true, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: true, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 81, explosion: .frag2, defaultMission: .hunt
    ),

    .ftank: UnitTypeData(
        type: .ftank, iniName: "FTNK", fullName: "Flame Tank",
        buildLevel: 4, prerequisite: .radar, cost: 800, scenario: 9, ownable: .nodAll,
        strength: 300, armor: .steel, primaryWeapon: .flameTongue, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: false, isTwoShooter: true,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 66, explosion: .napalm3, defaultMission: .hunt
    ),

    .vice: UnitTypeData(
        type: .vice, iniName: "VICE", fullName: "Visceroid",
        buildLevel: 99, prerequisite: .none, cost: 800, scenario: 1, ownable: .civAll,
        strength: 150, armor: .wood, primaryWeapon: .chemspray, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: false, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: false, hasCrew: false, isGigundo: false,
        isStealthy: true, isAnimating: true, isLockTurret: false,
        riskValue: 80, rewardValue: 20, explosion: .napalm2, defaultMission: .hunt
    ),

    .apc: UnitTypeData(
        type: .apc, iniName: "APC", fullName: "APC",
        buildLevel: 4, prerequisite: .barracks, cost: 700, scenario: 5, ownable: .bothAll,
        strength: 200, armor: .steel, primaryWeapon: .m60mg, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .mediumFaster, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: true, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: false, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 15, explosion: .frag2, defaultMission: .hunt
    ),

    .mlrs: UnitTypeData(
        type: .mlrs, iniName: "MLRS", fullName: "Mobile Rocket Launch System",
        buildLevel: 7, prerequisite: .eye, cost: 800, scenario: 11, ownable: .bothAll,
        strength: 100, armor: .aluminum, primaryWeapon: .mlrs, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: true,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: true,
        riskValue: 80, rewardValue: 72, explosion: .artExp1, defaultMission: .guard_
    ),

    .jeep: UnitTypeData(
        type: .jeep, iniName: "JEEP", fullName: "Humm-Vee",
        buildLevel: 2, prerequisite: .none, cost: 400, scenario: 3, ownable: .gdiAll,
        strength: 150, armor: .aluminum, primaryWeapon: .m60mg, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .wheel, maxSpeed: .mediumFast, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 25, explosion: .frag1, defaultMission: .hunt
    ),

    .buggy: UnitTypeData(
        type: .buggy, iniName: "BGGY", fullName: "Nod Buggy",
        buildLevel: 2, prerequisite: .none, cost: 300, scenario: 1, ownable: .nodAll,
        strength: 140, armor: .aluminum, primaryWeapon: .m60mg, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .wheel, maxSpeed: .mediumFast, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 20, explosion: .frag1, defaultMission: .hunt
    ),

    .harvester: UnitTypeData(
        type: .harvester, iniName: "HARV", fullName: "Harvester",
        buildLevel: 2, prerequisite: .refinery, cost: 1400, scenario: 7, ownable: .bothAll,
        strength: 600, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2, ammo: -1,
        speed: .wheel, maxSpeed: .mediumSlow, rot: 5,
        isBuildable: true, isLeader: false, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: true,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: true,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 85, explosion: .fball1, defaultMission: .harvest
    ),

    .arty: UnitTypeData(
        type: .arty, iniName: "ARTY", fullName: "Artillery",
        buildLevel: 6, prerequisite: .radar, cost: 450, scenario: 8, ownable: .nodAll,
        strength: 75, armor: .aluminum, primaryWeapon: .w155mm, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .mediumSlow, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 72, explosion: .artExp1, defaultMission: .guard_
    ),

    .msam: UnitTypeData(
        type: .msam, iniName: "MSAM", fullName: "Rocket Launcher",
        buildLevel: 7, prerequisite: .eye, cost: 800, scenario: 11, ownable: .bothAll,
        strength: 100, armor: .aluminum, primaryWeapon: .mlrs, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: true, isTwoShooter: true,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: true,
        riskValue: 80, rewardValue: 72, explosion: .artExp1, defaultMission: .guard_
    ),

    .hover: UnitTypeData(
        type: .hover, iniName: "LST", fullName: "Hovercraft",
        buildLevel: 99, prerequisite: .none, cost: 1000, scenario: 99, ownable: .bothAll,
        strength: 200, armor: .aluminum, primaryWeapon: .m60mg, secondaryWeapon: nil,
        sightRange: 5, ammo: -1,
        speed: .hover, maxSpeed: .medium, rot: 5,
        isBuildable: false, isLeader: false, hasTurret: true, isTwoShooter: false,
        isTransporter: true, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: true,
        isStealthy: false, isAnimating: true, isLockTurret: false,
        riskValue: 80, rewardValue: 35, explosion: .fball1, defaultMission: .hunt
    ),

    .mhq: UnitTypeData(
        type: .mhq, iniName: "MHQ", fullName: "Mobile HQ",
        buildLevel: 99, prerequisite: .none, cost: 600, scenario: 99, ownable: .bothAll,
        strength: 110, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 7, ammo: -1,
        speed: .wheel, maxSpeed: .mediumFast, rot: 5,
        isBuildable: false, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 50, explosion: .frag2, defaultMission: .guard_
    ),

    .gunboat: UnitTypeData(
        type: .gunboat, iniName: "BOAT", fullName: "Gunboat",
        buildLevel: 99, prerequisite: .none, cost: 300, scenario: 99, ownable: .bothAll,
        strength: 700, armor: .steel, primaryWeapon: .tomahawk, secondaryWeapon: nil,
        sightRange: 5, ammo: -1,
        speed: .float_, maxSpeed: .slow, rot: 1,
        isBuildable: false, isLeader: true, hasTurret: true, isTwoShooter: true,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: false, hasCrew: true, isGigundo: true,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 40, explosion: .fball1, defaultMission: .guard_
    ),

    .mcv: UnitTypeData(
        type: .mcv, iniName: "MCV", fullName: "Mobile Construction Vehicle",
        buildLevel: 99, prerequisite: .none, cost: 5000, scenario: 99, ownable: .bothAll,
        strength: 600, armor: .aluminum, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .wheel, maxSpeed: .mediumSlow, rot: 5,
        isBuildable: false, isLeader: false, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: true,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 70, explosion: .fball1, defaultMission: .guard_
    ),

    .bike: UnitTypeData(
        type: .bike, iniName: "BIKE", fullName: "Recon Bike",
        buildLevel: 2, prerequisite: .none, cost: 500, scenario: 1, ownable: .nodAll,
        strength: 160, armor: .none, primaryWeapon: .dragon, secondaryWeapon: nil,
        sightRange: 4, ammo: -1,
        speed: .wheel, maxSpeed: .fast, rot: 5,
        isBuildable: true, isLeader: true, hasTurret: false, isTwoShooter: true,
        isTransporter: false, isCrushable: true, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: true, hasCrew: true, isGigundo: false,
        isStealthy: false, isAnimating: false, isLockTurret: false,
        riskValue: 80, rewardValue: 25, explosion: .frag1, defaultMission: .hunt
    ),

    // Dinosaurs
    .tric: UnitTypeData(
        type: .tric, iniName: "TRIC", fullName: "Triceratops",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 99, ownable: [.jp],
        strength: 700, armor: .steel, primaryWeapon: .steg, secondaryWeapon: nil,
        sightRange: 5, ammo: -1,
        speed: .track, maxSpeed: .slow, rot: 5,
        isBuildable: false, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: false, hasCrew: false, isGigundo: true,
        isStealthy: true, isAnimating: false, isLockTurret: false,
        riskValue: 50, rewardValue: 50, explosion: .tricDie, defaultMission: .guard_
    ),

    .trex: UnitTypeData(
        type: .trex, iniName: "TREX", fullName: "Tyrannosaurus Rex",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 99, ownable: [.jp],
        strength: 750, armor: .steel, primaryWeapon: .trex, secondaryWeapon: nil,
        sightRange: 5, ammo: -1,
        speed: .track, maxSpeed: .medium, rot: 5,
        isBuildable: false, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: false, hasCrew: false, isGigundo: true,
        isStealthy: true, isAnimating: false, isLockTurret: false,
        riskValue: 50, rewardValue: 50, explosion: .trexDie, defaultMission: .guard_
    ),

    .rapt: UnitTypeData(
        type: .rapt, iniName: "RAPT", fullName: "Velociraptor",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 99, ownable: [.jp],
        strength: 180, armor: .steel, primaryWeapon: .trex, secondaryWeapon: nil,
        sightRange: 5, ammo: -1,
        speed: .track, maxSpeed: .fast, rot: 5,
        isBuildable: false, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: false, isHarvester: false,
        isCloakable: false, isRepairable: false, hasCrew: false, isGigundo: true,
        isStealthy: true, isAnimating: false, isLockTurret: false,
        riskValue: 50, rewardValue: 50, explosion: .raptDie, defaultMission: .guard_
    ),

    .steg: UnitTypeData(
        type: .steg, iniName: "STEG", fullName: "Stegosaurus",
        buildLevel: 99, prerequisite: .none, cost: 0, scenario: 99, ownable: [.jp],
        strength: 600, armor: .steel, primaryWeapon: .steg, secondaryWeapon: nil,
        sightRange: 5, ammo: -1,
        speed: .track, maxSpeed: .slow, rot: 5,
        isBuildable: false, isLeader: true, hasTurret: false, isTwoShooter: false,
        isTransporter: false, isCrushable: false, isCrusher: true, isHarvester: false,
        isCloakable: false, isRepairable: false, hasCrew: false, isGigundo: true,
        isStealthy: true, isAnimating: false, isLockTurret: false,
        riskValue: 50, rewardValue: 50, explosion: .stegDie, defaultMission: .guard_
    ),
]

// MARK: - Lookup Helpers

func getUnitTypeData(_ type: UnitType) -> UnitTypeData? {
    return unitTypeDataTable[type]
}

func getUnitTypeDataByName(_ iniName: String) -> UnitTypeData? {
    guard let type = UnitType.from(iniName: iniName) else { return nil }
    return unitTypeDataTable[type]
}
