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

    // Reset per-house visibility — we rebuild it from scratch each tick.
    // Houses with no surviving objects naturally drop out of the dict.
    map.houseVisibility.removeAll(keepingCapacity: true)

    // For each unit/structure, reveal cells within sight range — for the
    // player's fogState (only player house) and for each house's
    // visibility map (every house, used to gate AI target acquisition).
    for obj in world.objects {
        if obj.strength <= 0 { continue }
        if obj.house == .neutral { continue }

        let sight = max(2, obj.sightRange)
        let cx = obj.cellX
        let cy = obj.cellY
        let isPlayer = obj.house == world.playerHouse

        // Lazily allocate the per-house bool grid on first sighting.
        if map.houseVisibility[obj.house] == nil {
            map.houseVisibility[obj.house] = Array(repeating: false, count: 4096)
        }

        for dy in -sight...sight {
            for dx in -sight...sight {
                let nx = cx + dx
                let ny = cy + dy
                if nx < 0 || nx >= 64 || ny < 0 || ny >= 64 { continue }
                if dx * dx + dy * dy > sight * sight { continue }
                let cell = ny * 64 + nx
                map.houseVisibility[obj.house]?[cell] = true
                if isPlayer {
                    map.fogState[cell] = .visible
                }
            }
        }
    }
}

/// True if the given house has line-of-sight to the cell. Neutral house
/// is always considered seeing (civilian/world targets are universally visible).
/// A house with no surviving objects sees nothing.
func canHouseSee(cell: Int, house: House) -> Bool {
    if house == .neutral { return true }
    guard cell >= 0 && cell < 4096 else { return false }
    guard let map = session.world?.map else { return false }
    return map.houseVisibility[house]?[cell] ?? false
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
