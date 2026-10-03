import Foundation

// MARK: - Aircraft Type Data
// Ported faithfully from Vanilla Conquer adata.cpp AircraftTypeClass constructors

package struct AircraftTypeData {
    package let type: AircraftType
    package let iniName: String
    package let fullName: String

    // Build info
    package let buildLevel: Int
    package let prerequisite: StructFlag
    package let cost: Int
    package let scenario: Int
    package let ownable: HouseFlag

    // Combat
    package let strength: Int           // Max HP
    package let armor: ArmorType
    package let primaryWeapon: WeaponType?
    package let secondaryWeapon: WeaponType?
    package let sightRange: Int         // Cells
    package let maxAmmo: Int            // -1 = unlimited, 0 = none

    // Movement
    package let maxSpeed: MPHType
    package let rot: Int                // Rate of turn (degrees per tick)

    // Flags
    package let isFixedWing: Bool       // Fixed-wing aircraft (flies in one direction)
    package let isLandable: Bool        // Can land on ground
    package let isRotorEquipped: Bool   // Has visible rotor
    package let isTransporter: Bool     // Can carry passengers
    package let isBuildable: Bool
    package let hasCrew: Bool

    // AI ratings
    package let riskValue: Int
    package let rewardValue: Int
}

package let aircraftTypeDataTable: [AircraftType: AircraftTypeData] = [
    // Transport Helicopter (Chinook)
    .transport: AircraftTypeData(
        type: .transport, iniName: "TRAN", fullName: "Transport Helicopter",
        buildLevel: 7, prerequisite: .helipad, cost: 1500, scenario: 5,
        ownable: .bothAll,
        strength: 90, armor: .aluminum,
        primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 4, maxAmmo: 0,
        maxSpeed: .mediumFast, rot: 5,
        isFixedWing: false, isLandable: true, isRotorEquipped: true,
        isTransporter: true, isBuildable: true, hasCrew: true,
        riskValue: 0, rewardValue: 15
    ),

    // A-10 Ground Attack Plane
    .a10: AircraftTypeData(
        type: .a10, iniName: "A10", fullName: "A-10 Thunderbolt",
        buildLevel: 99, prerequisite: .none, cost: 800, scenario: 99,
        ownable: .bothAll,
        strength: 60, armor: .aluminum,
        primaryWeapon: .napalm, secondaryWeapon: nil,
        sightRange: 4, maxAmmo: 3,
        maxSpeed: .fast, rot: 5,
        isFixedWing: true, isLandable: false, isRotorEquipped: false,
        isTransporter: false, isBuildable: false, hasCrew: true,
        riskValue: 0, rewardValue: 20
    ),

    // Apache Attack Helicopter (Nod)
    .helicopter: AircraftTypeData(
        type: .helicopter, iniName: "HELI", fullName: "Apache",
        buildLevel: 7, prerequisite: .helipad, cost: 1200, scenario: 6,
        ownable: .nodAll,
        strength: 125, armor: .steel,
        primaryWeapon: .chainGun, secondaryWeapon: nil,
        sightRange: 4, maxAmmo: 15,
        maxSpeed: .fast, rot: 4,
        isFixedWing: false, isLandable: false, isRotorEquipped: true,
        isTransporter: false, isBuildable: true, hasCrew: true,
        riskValue: 20, rewardValue: 25
    ),

    // C-17 Cargo Plane (reinforcement delivery)
    .cargo: AircraftTypeData(
        type: .cargo, iniName: "C17", fullName: "Cargo Plane",
        buildLevel: 99, prerequisite: .none, cost: 800, scenario: 99,
        ownable: .bothAll,
        strength: 25, armor: .aluminum,
        primaryWeapon: nil, secondaryWeapon: nil,
        sightRange: 4, maxAmmo: 0,
        maxSpeed: .fast, rot: 5,
        isFixedWing: true, isLandable: false, isRotorEquipped: false,
        isTransporter: true, isBuildable: false, hasCrew: false,
        riskValue: 0, rewardValue: 0
    ),

    // Orca Attack Helicopter (GDI)
    .orca: AircraftTypeData(
        type: .orca, iniName: "ORCA", fullName: "Orca",
        buildLevel: 7, prerequisite: .helipad, cost: 1200, scenario: 6,
        ownable: .gdiAll,
        strength: 125, armor: .steel,
        primaryWeapon: .dragon, secondaryWeapon: nil,
        sightRange: 4, maxAmmo: 6,
        maxSpeed: .fast, rot: 4,
        isFixedWing: false, isLandable: false, isRotorEquipped: false,
        isTransporter: false, isBuildable: true, hasCrew: true,
        riskValue: 20, rewardValue: 25
    ),
]
