import Foundation

// MARK: - Facing & Remap Lookup Tables (from Vanilla Conquer tiberiandawn/const.cpp)

/// Maps 0-255 facing value to 32-direction index
let facing32: [Int] = [
    0,0,0,0,0,1,1,1,1,1,1,1,1,1,2,2,
    2,2,2,2,2,2,3,3,3,3,3,3,3,3,3,4,
    4,4,4,4,4,4,4,5,5,5,5,5,5,5,5,5,
    6,6,6,6,6,6,6,6,7,7,7,7,7,7,7,7,
    8,8,8,8,8,8,8,8,8,9,9,9,9,9,9,9,
    9,10,10,10,10,10,10,10,10,10,11,11,11,11,11,11,
    11,11,12,12,12,12,12,12,12,12,12,13,13,13,13,13,
    13,13,13,14,14,14,14,14,14,14,14,14,15,15,15,15,
    15,15,15,15,16,16,16,16,16,16,16,16,16,17,17,17,
    17,17,17,17,17,18,18,18,18,18,18,18,18,18,19,19,
    19,19,19,19,19,19,20,20,20,20,20,20,20,20,20,21,
    21,21,21,21,21,21,21,22,22,22,22,22,22,22,22,22,
    23,23,23,23,23,23,23,23,24,24,24,24,24,24,24,24,
    24,25,25,25,25,25,25,25,25,26,26,26,26,26,26,26,
    26,26,27,27,27,27,27,27,27,27,28,28,28,28,28,28,
    28,28,28,29,29,29,29,29,29,29,29,30,30,30,30,30
]

/// Maps 32-direction index to SHP frame index for vehicle body rotation
let bodyShape: [Int] = [
    0,31,30,29,28,27,26,25,24,23,22,21,20,19,18,17,
    16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1
]

/// Maps 32-direction index to 8-direction index for infantry
let humanShape: [Int] = [
    0,0,7,7,7,7,6,6,6,6,5,5,5,5,5,4,
    4,4,3,3,3,3,2,2,2,2,1,1,1,1,1,0
]

/// House color remap tables — each has 16 entries replacing palette indices 176-191
/// From Vanilla Conquer tiberiandawn/const.cpp
let remapRed: [UInt8] = [
    127,126,125,124,122,46,120,47,125,124,123,122,42,121,120,120
]
let remapBlue: [UInt8] = [
    2,119,118,135,136,138,112,12,118,135,136,137,138,139,114,112
]
let remapOrange: [UInt8] = [
    24,25,26,27,29,31,46,47,26,27,28,29,30,31,43,47
]
let remapGreen: [UInt8] = [
    5,165,166,167,159,142,140,199,166,167,157,3,159,143,142,141
]
let remapLtBlue: [UInt8] = [
    161,200,201,202,204,205,206,12,201,202,203,204,205,115,198,114
]

/// Returns the 16-entry remap table for a given house, or nil for identity (no remap)
func remapTable(for house: House) -> [UInt8]? {
    switch house {
    case .goodGuy:  return nil          // GDI uses default gold (identity)
    case .badGuy:   return remapRed     // Nod = red
    case .neutral:  return nil           // Neutral = identity
    case .special:  return nil           // Special = identity
    case .multi1:   return remapLtBlue  // Multi1 = light blue
    case .multi2:   return remapOrange  // Multi2 = orange
    case .multi3:   return remapGreen   // Multi3 = green
    case .multi4:   return nil          // Multi4 = gold (default)
    case .multi5:   return remapRed     // Multi5 = red (same as Nod)
    case .multi6:   return remapBlue    // Multi6 = blue
    }
}

/// Animation frame counter, incremented each render frame
