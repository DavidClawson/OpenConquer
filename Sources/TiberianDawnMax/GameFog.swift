import Foundation

// MARK: - Fog of War

enum FogLevel {
    case unexplored
    case explored
    case visible
}

// Sight ranges now come from type data tables via GameObject.sightRange

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

        let sight = max(1, obj.sightRange)
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
