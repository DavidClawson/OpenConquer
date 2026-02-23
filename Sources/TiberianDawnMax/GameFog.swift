import Foundation

// MARK: - Fog of War

enum FogLevel {
    case unexplored
    case explored
    case visible
}

/// Sight range in cells per unit type
let sightRanges: [String: Int] = [
    // Vehicles
    "MTNK": 5,
    "LTNK": 5,
    "HTNK": 5,
    "FTNK": 4,
    "STNK": 4,
    "ARTY": 5,
    "MSAM": 5,
    "HMMV": 6,
    "BGGY": 6,
    "BIKE": 6,
    "APC":  5,
    "MHQ":  6,
    "HARV": 4,
    "MCV":  5,
    "LST":  5,

    // Infantry
    "E1":   3,
    "E2":   3,
    "E3":   4,
    "E4":   3,
    "E5":   3,
    "E6":   3,
    "E7":   3,
    "RMBO": 5,
    "C1":   2, "C2": 2, "C3": 2, "C4": 2, "C5": 2,
    "C6":   2, "C7": 2, "C8": 2, "C9": 2, "C10": 2,

    // Structures (use building size as base)
    "FACT": 4, "PROC": 4, "WEAP": 4, "PYLE": 3, "HAND": 3,
    "NUKE": 3, "HQ":   5, "EYE":  7, "GUN":  5, "GTWR": 5,
    "OBLI": 5, "ATWR": 5, "SAM":  5, "SILO": 3, "HPAD": 4,
    "TMPL": 4, "FIX":  4, "AFLD": 4, "BIO":  3,
]

/// Fog state for each of the 4096 cells
var fogState: [FogLevel] = Array(repeating: .unexplored, count: 4096)

/// Update fog of war based on current friendly unit positions
func updateFog() {
    guard let world = gameWorld else { return }

    // Demote all visible cells to explored
    for i in 0..<4096 {
        if fogState[i] == .visible {
            fogState[i] = .explored
        }
    }

    // For each friendly unit/structure, reveal cells within sight range
    for obj in world.objects {
        if obj.house != world.playerHouse { continue }
        if obj.strength <= 0 { continue }

        let sight = sightRanges[obj.typeName.uppercased()] ?? 3
        let cx = obj.cellX
        let cy = obj.cellY

        // Simple circle reveal
        for dy in -sight...sight {
            for dx in -sight...sight {
                let nx = cx + dx
                let ny = cy + dy
                if nx < 0 || nx >= 64 || ny < 0 || ny >= 64 { continue }
                // Circle check
                if dx * dx + dy * dy <= sight * sight {
                    fogState[ny * 64 + nx] = .visible
                }
            }
        }
    }
}

/// Check if a cell is currently visible
func isCellVisible(_ cell: Int) -> Bool {
    guard cell >= 0 && cell < 4096 else { return false }
    return fogState[cell] == .visible
}

/// Check if a cell has been explored
func isCellExplored(_ cell: Int) -> Bool {
    guard cell >= 0 && cell < 4096 else { return false }
    return fogState[cell] != .unexplored
}

/// Initialize fog — reveal areas around starting friendly units
func initFog() {
    fogState = Array(repeating: .unexplored, count: 4096)
    updateFog()
}
