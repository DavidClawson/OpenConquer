import Foundation

// MARK: - GameMap Class

class GameMap {
    /// The 64x64 grid of terrain template cells (loaded from .BIN file)
    var cells: [MapCell] = []

    /// Parsed scenario INI data (structures, units, infantry, overlays, etc.)
    var scenarioData: ScenarioData? = nil

    /// Land passability: true = passable for ground units, false = impassable
    var landPassability: [Bool] = Array(repeating: true, count: 4096)

    /// Water passability: true = passable for naval units, false = impassable
    var waterPassability: [Bool] = Array(repeating: true, count: 4096)

    /// Set of cell indices that contain tiberium overlays
    var tiberiumCells: Set<Int> = Set()

    /// Tiberium density per cell (1-12, matching TI1-TI12 overlay types)
    var tiberiumDensity: [Int: Int] = [:]

    /// Scan position for tiberium growth/spread (VC TiberiumScan)
    var tiberiumScan: Int = 0

    /// Alternating scan direction (VC IsForwardScan)
    var isForwardScan: Bool = true

    /// Accumulated growth candidates during current scan cycle (VC TiberiumGrowth[])
    var tiberiumGrowthCandidates: [Int] = []

    /// Accumulated spread candidates during current scan cycle (VC TiberiumSpread[])
    var tiberiumSpreadCandidates: [Int] = []

    /// Persistent ground smudges (craters, scorch marks)
    var smudges: [Smudge] = []

    /// Fog state for each of the 4096 cells
    var fogState: [FogLevel] = Array(repeating: .unexplored, count: 4096)
}

// MARK: - Backward-Compatible Passability Globals

/// Land passability — delegates to session.world.map; falls back to a default array
var landPassability: [Bool] {
    get { session.world?.map.landPassability ?? Array(repeating: true, count: 4096) }
    set { session.world?.map.landPassability = newValue }
}
/// Water passability — delegates to session.world.map; falls back to a default array
var waterPassability: [Bool] {
    get { session.world?.map.waterPassability ?? Array(repeating: true, count: 4096) }
    set { session.world?.map.waterPassability = newValue }
}
/// Legacy alias used by structure placement and MCV deploy
var staticPassability: [Bool] {
    get { landPassability }
    set { landPassability = newValue }
}

// Water template types (from templateTable in MapLoader.swift)
private let waterTemplateTypes: Set<Int> = [1, 2]  // W1, W2

/// Build the static passability map from terrain data.
/// Called once after loading a scenario into game mode.
func buildPassabilityMap() {
    // Start with all cells passable in both maps
    landPassability = Array(repeating: true, count: 4096)
    waterPassability = Array(repeating: true, count: 4096)

    // Mark structure footprints as impassable in BOTH maps
    if let scenario = scenarioData {
        for structure in scenario.structures {
            let size = buildingSize(structure.typeName)
            let baseXY = cellToXY(structure.cell)
            for dy in 0..<size.h {
                for dx in 0..<size.w {
                    let cx = baseXY.x + dx
                    let cy = baseXY.y + dy
                    if cx >= 0 && cx < 64 && cy >= 0 && cy < 64 {
                        landPassability[cy * 64 + cx] = false
                        waterPassability[cy * 64 + cx] = false
                    }
                }
            }
        }

        // Mark terrain objects as impassable in BOTH maps
        for terrainObj in scenario.terrain {
            let cell = terrainObj.cell
            if cell >= 0 && cell < 4096 {
                landPassability[cell] = false
                waterPassability[cell] = false
            }
        }
    }

    // Mark water/land tiles appropriately for each map.
    // Only pure water templates (W1, W2) are fully land-impassable.
    // Shore (SH*), river (RV*), falls, ford, and bridge templates are multi-cell
    // with a mix of land and water sub-tiles. Without per-icon land type data,
    // we keep them land-passable to avoid blocking large terrain areas.
    // Water passability: W1, W2, SH*, RV*, FALLS*, FORD* are water-passable for boats.
    for i in 0..<4096 {
        let templateType = Int(mapCells[i].templateType)
        if templateType != 0xFF && templateType < templateTable.count {
            let name = templateTable[templateType].icnName.uppercased()
            if name == "W1" || name == "W2" {
                // Pure open water: impassable for land, passable for water
                landPassability[i] = false
                // waterPassability[i] stays true
            } else if name.hasPrefix("SH") || name.hasPrefix("RV") ||
                      name.hasPrefix("FALLS") || name.hasPrefix("FORD") {
                // Shore/river/falls/ford: passable for BOTH land and water
                // These multi-cell templates have mixed terrain; keep land-passable
                // to avoid blocking banks/beaches. Boats can also traverse.
                // landPassability[i] stays true
                // waterPassability[i] stays true
            } else if name.hasPrefix("BRIDGE") {
                // Bridges: passable by land, not by water
                // landPassability[i] stays true
                waterPassability[i] = false
            } else {
                // Regular land: passable for land, impassable for water
                waterPassability[i] = false
            }
        } else {
            // Default land cell: impassable for water
            waterPassability[i] = false
        }
    }

    // Mark cells outside map bounds as impassable in BOTH maps
    if let bounds = scenarioData?.mapBounds {
        for y in 0..<64 {
            for x in 0..<64 {
                if x < bounds.x || x >= bounds.x + bounds.width ||
                   y < bounds.y || y >= bounds.y + bounds.height {
                    landPassability[y * 64 + x] = false
                    waterPassability[y * 64 + x] = false
                }
            }
        }
    }

    let landImpassable = landPassability.filter { !$0 }.count
    let waterImpassable = waterPassability.filter { !$0 }.count
    print("GameMap: Built passability map, \(landImpassable) land-impassable, \(waterImpassable) water-impassable cells")
}

/// Get the appropriate passability map for a given speed type
func passabilityMap(for speed: SpeedType) -> [Bool] {
    switch speed {
    case .float_: return waterPassability
    case .hover:
        // Hovercraft can traverse both land and water (amphibious)
        var combined = Array(repeating: false, count: 4096)
        for i in 0..<4096 {
            combined[i] = landPassability[i] || waterPassability[i]
        }
        return combined
    default: return landPassability
    }
}

// MARK: - Dynamic Occupancy

/// Rebuild occupancy grid from current object positions
func updateOccupancy() {
    guard let world = session.world else { return }
    world.occupancy.removeAll(keepingCapacity: true)

    for obj in world.objects {
        if obj.kind == .structure { continue }  // Structures use static passability
        let cell = obj.cell
        if cell >= 0 && cell < 4096 {
            world.occupancy[cell] = obj.id
        }
    }
}

// MARK: - Passability Check

func isCellPassable(cellX: Int, cellY: Int, ignoring: GameObject? = nil, speedType: SpeedType = .foot) -> Bool {
    guard cellX >= 0 && cellX < 64 && cellY >= 0 && cellY < 64 else { return false }
    let cell = cellY * 64 + cellX

    // Check passability for this speed type
    let passMap = passabilityMap(for: speedType)
    if !passMap[cell] { return false }

    // Check dynamic occupancy — friendly units can pass through each other
    if let world = session.world, let occupantId = world.occupancy[cell] {
        if let ignoring = ignoring, occupantId == ignoring.id {
            return true
        }
        // Allow passing through friendly units
        if let ignoring = ignoring,
           let occupant = world.findObject(id: occupantId),
           occupant.house == ignoring.house {
            return true
        }
        return false
    }

    return true
}

// MARK: - A* Pathfinding (Binary Heap)

/// Min-heap priority queue for A* open set. O(log n) insert/extract-min
/// instead of O(n) linear scan, allowing much larger search spaces.
private struct PathHeap {
    private var nodes: [(cell: Int, f: Double)] = []

    var isEmpty: Bool { nodes.isEmpty }

    mutating func insert(cell: Int, f: Double) {
        nodes.append((cell, f))
        siftUp(nodes.count - 1)
    }

    mutating func extractMin() -> Int {
        let min = nodes[0].cell
        let last = nodes.count - 1
        nodes[0] = nodes[last]
        nodes.removeLast()
        if !nodes.isEmpty { siftDown(0) }
        return min
    }

    private mutating func siftUp(_ i: Int) {
        var idx = i
        while idx > 0 {
            let parent = (idx - 1) / 2
            if nodes[idx].f < nodes[parent].f {
                nodes.swapAt(idx, parent)
                idx = parent
            } else { break }
        }
    }

    private mutating func siftDown(_ i: Int) {
        var idx = i
        let count = nodes.count
        while true {
            let left = 2 * idx + 1
            let right = 2 * idx + 2
            var smallest = idx
            if left < count && nodes[left].f < nodes[smallest].f { smallest = left }
            if right < count && nodes[right].f < nodes[smallest].f { smallest = right }
            if smallest == idx { break }
            nodes.swapAt(idx, smallest)
            idx = smallest
        }
    }
}

/// Find a path from (fromX, fromY) to (toX, toY) using A* on the 64x64 grid.
/// Uses a binary heap for O(log n) priority queue operations.
/// Returns array of (cellX, cellY) waypoints, or empty if no path found.
func findPath(fromX: Int, fromY: Int, toX: Int, toY: Int,
              ignoring: GameObject? = nil, maxSteps: Int = 1200,
              speedType: SpeedType = .foot) -> [(cellX: Int, cellY: Int)] {

    // Quick bounds check
    guard fromX >= 0 && fromX < 64 && fromY >= 0 && fromY < 64 &&
          toX >= 0 && toX < 64 && toY >= 0 && toY < 64 else {
        return []
    }

    let passMap = passabilityMap(for: speedType)

    // If target is impassable, find nearest passable cell within 5-cell radius
    let targetCell = toY * 64 + toX
    if !passMap[targetCell] {
        var bestX = toX, bestY = toY
        var bestDist = Double.infinity
        for dy in -5...5 {
            for dx in -5...5 {
                let nx = toX + dx
                let ny = toY + dy
                if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 &&
                   passMap[ny * 64 + nx] {
                    let dist = sqrt(Double(dx * dx + dy * dy))
                    if dist < bestDist {
                        bestDist = dist
                        bestX = nx
                        bestY = ny
                    }
                }
            }
        }
        if bestDist == Double.infinity { return [] }
        return findPath(fromX: fromX, fromY: fromY, toX: bestX, toY: bestY,
                       ignoring: ignoring, maxSteps: maxSteps, speedType: speedType)
    }

    // Already at target
    if fromX == toX && fromY == toY { return [] }

    // 8-directional movement
    let dirs: [(dx: Int, dy: Int, cost: Double)] = [
        (0, -1, 1.0), (1, 0, 1.0), (0, 1, 1.0), (-1, 0, 1.0),      // Cardinal
        (1, -1, 1.414), (1, 1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)  // Diagonal
    ]

    // Heuristic: octile distance (optimal for 8-directional movement)
    func heuristic(_ x: Int, _ y: Int) -> Double {
        let dx = abs(x - toX)
        let dy = abs(y - toY)
        return Double(max(dx, dy)) + 0.414 * Double(min(dx, dy))
    }

    // Occupancy cost: cells with units get a soft penalty to route around them
    let occupancy = session.world?.occupancy
    let ignoringId = ignoring?.id

    let startCell = fromY * 64 + fromX
    var openSet = PathHeap()
    openSet.insert(cell: startCell, f: heuristic(fromX, fromY))
    var cameFrom = [Int: Int]()          // cell -> parent cell
    var gScore = [Int: Double]()         // cell -> best known g cost
    gScore[startCell] = 0

    var steps = 0
    while !openSet.isEmpty && steps < maxSteps {
        steps += 1

        let currentCell = openSet.extractMin()

        // Skip if we already found a better path to this cell
        guard let currentG = gScore[currentCell] else { continue }

        let cx = currentCell % 64
        let cy = currentCell / 64

        if cx == toX && cy == toY {
            // Reconstruct path
            var path: [(cellX: Int, cellY: Int)] = []
            var cell = currentCell
            while cell != startCell {
                path.append((cellX: cell % 64, cellY: cell / 64))
                guard let parent = cameFrom[cell] else { break }
                cell = parent
            }
            path.reverse()
            return path
        }

        for dir in dirs {
            let nx = cx + dir.dx
            let ny = cy + dir.dy

            guard nx >= 0 && nx < 64 && ny >= 0 && ny < 64 else { continue }

            let neighborCell = ny * 64 + nx

            // Check passability
            if !passMap[neighborCell] { continue }

            // For diagonal moves, ensure both adjacent cardinal cells are passable
            // (prevents cutting through wall corners)
            if dir.dx != 0 && dir.dy != 0 {
                if !passMap[cy * 64 + nx] || !passMap[ny * 64 + cx] { continue }
            }

            // Base movement cost + soft penalty for occupied cells
            var moveCost = dir.cost
            if let occ = occupancy, let occupantId = occ[neighborCell] {
                if occupantId != ignoringId {
                    moveCost += 3.0  // Soft penalty: prefer unoccupied cells
                }
            }

            let tentativeG = currentG + moveCost
            let existingG = gScore[neighborCell] ?? Double.infinity

            if tentativeG < existingG {
                gScore[neighborCell] = tentativeG
                cameFrom[neighborCell] = currentCell
                let f = tentativeG + heuristic(nx, ny)
                openSet.insert(cell: neighborCell, f: f)
            }
        }
    }

    // No path found
    return []
}
