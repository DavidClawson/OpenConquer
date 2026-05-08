import Foundation

// MARK: - Infantry Type Data
// Ported faithfully from Vanilla Conquer idata.cpp InfantryTypeClass constructors

struct InfantryTypeData {
    let type: InfantryType
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

    // Movement
    let maxSpeed: MPHType

    // Flags
    let isBuildable: Bool
    let isLeader: Bool
    let isCivilian: Bool
    let isFraidycat: Bool
    let canCapture: Bool
    let hasCrawl: Bool          // Can go prone
    let isFemale: Bool

    // AI ratings
    let riskValue: Int
    let rewardValue: Int
}

// MARK: - Infantry Type Data Table

var infantryTypeDataTable: [InfantryType: InfantryTypeData] = [

    .e1: InfantryTypeData(
        type: .e1, iniName: "E1", fullName: "Minigunner",
        buildLevel: 1, prerequisite: .none, cost: 100, scenario: 1, ownable: .bothAll,
        strength: 50, armor: .none, primaryWeapon: .m16, secondaryWeapon: nil,
        sightRange: 1,
        maxSpeed: .slow,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: false, hasCrawl: true, isFemale: false,
        riskValue: 10, rewardValue: 10
    ),

    .e2: InfantryTypeData(
        type: .e2, iniName: "E2", fullName: "Grenadier",
        buildLevel: 1, prerequisite: .none, cost: 160, scenario: 3, ownable: .gdiAll,
        strength: 50, armor: .none, primaryWeapon: .grenade, secondaryWeapon: nil,
        sightRange: 1,
        maxSpeed: .slowIsh,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: false, hasCrawl: true, isFemale: false,
        riskValue: 10, rewardValue: 10
    ),

    .e3: InfantryTypeData(
        type: .e3, iniName: "E3", fullName: "Rocket Soldier",
        buildLevel: 2, prerequisite: .none, cost: 300, scenario: 3, ownable: .bothAll,
        strength: 25, armor: .none, primaryWeapon: .dragon, secondaryWeapon: nil,
        sightRange: 2,
        maxSpeed: .kindaSlow,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: false, hasCrawl: true, isFemale: false,
        riskValue: 10, rewardValue: 10
    ),

    .e4: InfantryTypeData(
        type: .e4, iniName: "E4", fullName: "Flamethrower",
        buildLevel: 1, prerequisite: .none, cost: 200, scenario: 5, ownable: .nodAll,
        strength: 70, armor: .none, primaryWeapon: .flamethrower, secondaryWeapon: nil,
        sightRange: 1,
        maxSpeed: .slowIsh,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: false, hasCrawl: true, isFemale: false,
        riskValue: 10, rewardValue: 10
    ),

    .e5: InfantryTypeData(
        type: .e5, iniName: "E5", fullName: "Chem Warrior",
        buildLevel: 7, prerequisite: .eye, cost: 300, scenario: 98, ownable: .nodAll,
        strength: 70, armor: .none, primaryWeapon: .chemspray, secondaryWeapon: nil,
        sightRange: 1,
        maxSpeed: .slow,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: false, hasCrawl: true, isFemale: false,
        riskValue: 10, rewardValue: 10
    ),

    .e7: InfantryTypeData(
        type: .e7, iniName: "E6", fullName: "Engineer",
        buildLevel: 3, prerequisite: .none, cost: 500, scenario: 2, ownable: .bothAll,
        strength: 25, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 2,
        maxSpeed: .slow,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: true, hasCrawl: false, isFemale: false,
        riskValue: 10, rewardValue: 75
    ),

    .rambo: InfantryTypeData(
        type: .rambo, iniName: "RMBO", fullName: "Commando",
        buildLevel: 7, prerequisite: .eye, cost: 1000, scenario: 98, ownable: .bothAll,
        strength: 80, armor: .none, primaryWeapon: .rifle, secondaryWeapon: nil,
        sightRange: 5,
        maxSpeed: .slowIsh,
        isBuildable: true, isLeader: true, isCivilian: false, isFraidycat: false,
        canCapture: false, hasCrawl: true, isFemale: false,
        riskValue: 10, rewardValue: 75
    ),

    // MARK: - Civilians

    .c1: InfantryTypeData(
        type: .c1, iniName: "C1", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 25, armor: .none, primaryWeapon: .pistol, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: true, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    .c2: InfantryTypeData(
        type: .c2, iniName: "C2", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: true,
        riskValue: 0, rewardValue: 1
    ),

    .c3: InfantryTypeData(
        type: .c3, iniName: "C3", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: true,
        riskValue: 0, rewardValue: 1
    ),

    .c4: InfantryTypeData(
        type: .c4, iniName: "C4", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: true,
        riskValue: 0, rewardValue: 1
    ),

    .c5: InfantryTypeData(
        type: .c5, iniName: "C5", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    .c6: InfantryTypeData(
        type: .c6, iniName: "C6", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    .c7: InfantryTypeData(
        type: .c7, iniName: "C7", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: .pistol, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: true, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    .c8: InfantryTypeData(
        type: .c8, iniName: "C8", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    .c9: InfantryTypeData(
        type: .c9, iniName: "C9", fullName: "Civilian",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 5, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    // MARK: - Named Civilians

    .c10: InfantryTypeData(
        type: .c10, iniName: "C10", fullName: "Nikoomba",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 50, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 1
    ),

    .moebius: InfantryTypeData(
        type: .moebius, iniName: "MOEBIUS", fullName: "Dr. Moebius",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 50, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 10
    ),

    .delphi: InfantryTypeData(
        type: .delphi, iniName: "DELPHI", fullName: "Agent Delphi",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 25, armor: .none, primaryWeapon: .pistol, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: true, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 10
    ),

    .chan: InfantryTypeData(
        type: .chan, iniName: "CHAN", fullName: "Dr. Chan",
        buildLevel: 99, prerequisite: .none, cost: 10, scenario: 99, ownable: .civAll,
        strength: 25, armor: .none, primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 0,
        maxSpeed: .slowIsh,
        isBuildable: false, isLeader: false, isCivilian: true, isFraidycat: true,
        canCapture: false, hasCrawl: false, isFemale: false,
        riskValue: 0, rewardValue: 10
    ),
]

// MARK: - Lookup Helpers

func getInfantryTypeData(_ type: InfantryType) -> InfantryTypeData? {
    return infantryTypeDataTable[type]
}

func getInfantryTypeDataByName(_ iniName: String) -> InfantryTypeData? {
    guard let type = InfantryType.from(iniName: iniName) else { return nil }
    return infantryTypeDataTable[type]
}
