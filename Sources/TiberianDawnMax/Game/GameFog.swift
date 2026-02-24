import Foundation

// MARK: - Fog of War

enum FogLevel {
    case unexplored
    case explored
    case visible
}

// Sight ranges now come from type data tables via GameObject.sightRange

// fogState is now in GameWorld.map (GameMap)
// Backward-compatible computed property for code that still reads fogState directly
var fogState: [FogLevel] {
    get { session.world?.map.fogState ?? Array(repeating: .unexplored, count: 4096) }
    set { session.world?.map.fogState = newValue }
}

/// Update fog of war based on current friendly unit positions
func updateFog() {
    guard let world = session.world else { return }
    let map = world.map

    // Demote all visible cells to explored
    for i in 0..<4096 {
        if map.fogState[i] == .visible {
            map.fogState[i] = .explored
        }
    }

    // For each friendly unit/structure, reveal cells within sight range
    // Uses actual sight range from type data tables (matches original C&C behavior)
    for obj in world.objects {
        if obj.house != world.playerHouse { continue }
        if obj.strength <= 0 { continue }

        let sight = max(2, obj.sightRange)
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
                    map.fogState[ny * 64 + nx] = .visible
                }
            }
        }
    }
}

/// Check if a cell is currently visible
func isCellVisible(_ cell: Int) -> Bool {
    guard cell >= 0 && cell < 4096 else { return false }
    guard let map = session.world?.map else { return false }
    return map.fogState[cell] == .visible
}

/// Check if a cell has been explored
func isCellExplored(_ cell: Int) -> Bool {
    guard cell >= 0 && cell < 4096 else { return false }
    guard let map = session.world?.map else { return false }
    return map.fogState[cell] != .unexplored
}

/// Initialize fog — reveal areas around starting friendly units
func initFog() {
    guard let map = session.world?.map else { return }
    map.fogState = Array(repeating: .unexplored, count: 4096)
    updateFog()
}

/// Temporarily reveal fog around a world position (e.g., when an enemy fires at the player).
/// Reveals a small area (2-cell radius) so the player can see who's shooting them.
func revealFogAroundPosition(worldX: Double, worldY: Double, radius: Int = 2) {
    guard let map = session.world?.map else { return }
    let cx = Int(worldX) / 24
    let cy = Int(worldY) / 24

    for dy in -radius...radius {
        for dx in -radius...radius {
            let nx = cx + dx
            let ny = cy + dy
            if nx < 0 || nx >= 64 || ny < 0 || ny >= 64 { continue }
            if dx * dx + dy * dy <= radius * radius {
                let cell = ny * 64 + nx
                map.fogState[cell] = .visible
            }
        }
    }
}
