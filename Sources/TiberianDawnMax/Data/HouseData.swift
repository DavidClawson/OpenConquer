import Foundation

// MARK: - House Type Data
// Ported from Vanilla Conquer hdata.cpp HouseTypeClass definitions

struct HouseTypeData {
    let type: HousesType
    let iniName: String
    let fullName: String
    let suffix: String          // 3-4 char suffix (GDI, NOD, CIV, etc.)
    let voicePrefix: Character

    // Colors (palette indices)
    let color: UInt8            // Dark radar color
    let brightColor: UInt8      // Bright radar color

    // Display colors (RGB for rendering)
    let displayColorR: UInt8
    let displayColorG: UInt8
    let displayColorB: UInt8

    // AI bias multipliers (default 1.0)
    let firepowerBias: Double
    let groundspeedBias: Double
    let airspeedBias: Double
    let armorBias: Double
    let rofBias: Double
    let costBias: Double
    let buildSpeedBias: Double
}

let houseTypeDataTable: [HousesType: HouseTypeData] = [
    .good: HouseTypeData(
        type: .good, iniName: "GoodGuy", fullName: "GDI", suffix: "GDI", voicePrefix: "G",
        color: 180, brightColor: 176,
        displayColorR: 218, displayColorG: 165, displayColorB: 32,  // Gold
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .bad: HouseTypeData(
        type: .bad, iniName: "BadGuy", fullName: "Nod", suffix: "NOD", voicePrefix: "B",
        color: 123, brightColor: 127,
        displayColorR: 200, displayColorG: 40, displayColorB: 40,   // Red
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .neutral: HouseTypeData(
        type: .neutral, iniName: "Neutral", fullName: "Civilian", suffix: "CIV", voicePrefix: "C",
        color: 205, brightColor: 202,
        displayColorR: 200, displayColorG: 200, displayColorB: 200, // White/grey
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .jp: HouseTypeData(
        type: .jp, iniName: "Special", fullName: "Special", suffix: "JP", voicePrefix: "J",
        color: 123, brightColor: 127,
        displayColorR: 200, displayColorG: 40, displayColorB: 40,
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .multi1: HouseTypeData(
        type: .multi1, iniName: "Multi1", fullName: "Multi1", suffix: "MP1", voicePrefix: "M",
        color: 205, brightColor: 202,
        displayColorR: 160, displayColorG: 200, displayColorB: 255, // Light blue
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .multi2: HouseTypeData(
        type: .multi2, iniName: "Multi2", fullName: "Multi2", suffix: "MP2", voicePrefix: "M",
        color: 205, brightColor: 202,
        displayColorR: 255, displayColorG: 165, displayColorB: 0,   // Orange
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .multi3: HouseTypeData(
        type: .multi3, iniName: "Multi3", fullName: "Multi3", suffix: "MP3", voicePrefix: "M",
        color: 205, brightColor: 202,
        displayColorR: 0, displayColorG: 180, displayColorB: 0,     // Green
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .multi4: HouseTypeData(
        type: .multi4, iniName: "Multi4", fullName: "Multi4", suffix: "MP4", voicePrefix: "M",
        color: 205, brightColor: 202,
        displayColorR: 0, displayColorG: 0, displayColorB: 200,     // Blue
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .multi5: HouseTypeData(
        type: .multi5, iniName: "Multi5", fullName: "Multi5", suffix: "MP5", voicePrefix: "M",
        color: 205, brightColor: 202,
        displayColorR: 218, displayColorG: 165, displayColorB: 32,  // Gold
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
    .multi6: HouseTypeData(
        type: .multi6, iniName: "Multi6", fullName: "Multi6", suffix: "MP6", voicePrefix: "M",
        color: 205, brightColor: 202,
        displayColorR: 180, displayColorG: 0, displayColorB: 0,     // Dark red
        firepowerBias: 1.0, groundspeedBias: 1.0, airspeedBias: 1.0,
        armorBias: 1.0, rofBias: 1.0, costBias: 1.0, buildSpeedBias: 1.0
    ),
]

// MARK: - Lookup Helpers

func getHouseTypeData(_ type: HousesType) -> HouseTypeData? {
    return houseTypeDataTable[type]
}

func getHouseTypeDataByName(_ iniName: String) -> HouseTypeData? {
    return houseTypeDataTable.values.first { $0.iniName.caseInsensitiveCompare(iniName) == .orderedSame }
}

// MARK: - House ↔ Legacy House Conversion

/// Convert the new HousesType to the existing House enum used in GameState
func housesTypeToHouse(_ ht: HousesType) -> House {
    switch ht {
    case .good:    return .goodGuy
    case .bad:     return .badGuy
    case .neutral: return .neutral
    case .jp:      return .special
    case .multi1:  return .multi1
    case .multi2:  return .multi2
    case .multi3:  return .multi3
    case .multi4:  return .multi4
    case .multi5:  return .multi5
    case .multi6:  return .multi6
    }
}

/// Convert the existing House enum to the new HousesType
func houseToHousesType(_ h: House) -> HousesType {
    switch h {
    case .goodGuy: return .good
    case .badGuy:  return .bad
    case .neutral: return .neutral
    case .special: return .jp
    case .multi1:  return .multi1
    case .multi2:  return .multi2
    case .multi3:  return .multi3
    case .multi4:  return .multi4
    case .multi5:  return .multi5
    case .multi6:  return .multi6
    }
}

/// Check if a house can own a given object based on HouseFlag
func canHouseOwn(_ house: House, flags: HouseFlag) -> Bool {
    let ht = houseToHousesType(house)
    switch ht {
    case .good:    return flags.contains(.good)
    case .bad:     return flags.contains(.bad)
    case .neutral: return flags.contains(.neutral)
    case .jp:      return flags.contains(.jp)
    case .multi1:  return flags.contains(.multi1)
    case .multi2:  return flags.contains(.multi2)
    case .multi3:  return flags.contains(.multi3)
    case .multi4:  return flags.contains(.multi4)
    case .multi5:  return flags.contains(.multi5)
    case .multi6:  return flags.contains(.multi6)
    }
}
