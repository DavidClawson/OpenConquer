import Foundation

// MARK: - Static Passability

/// 4096-entry grid: true = passable, false = impassable
var staticPassability: [Bool] = Array(repeating: true, count: 4096)

// Water template types (from templateTable in MapLoader.swift)
private let waterTemplateTypes: Set<Int> = [1, 2]  // W1, W2

/// Build the static passability map from terrain data.
/// Called once after loading a scenario into game mode.
func buildPassabilityMap() {
    // Start with all cells passable
    staticPassability = Array(repeating: true, count: 4096)

    // Mark structure footprints as impassable
    if let scenario = scenarioData {
        for structure in scenario.structures {
            let size = buildingSize(structure.typeName)
            let baseXY = cellToXY(structure.cell)
            for dy in 0..<size.h {
                for dx in 0..<size.w {
                    let cx = baseXY.x + dx
                    let cy = baseXY.y + dy
                    if cx >= 0 && cx < 64 && cy >= 0 && cy < 64 {
                        staticPassability[cy * 64 + cx] = false
                    }
                }
            }
        }

        // Mark terrain objects as impassable
        for terrainObj in scenario.terrain {
            let cell = terrainObj.cell
            if cell >= 0 && cell < 4096 {
                staticPassability[cell] = false
            }
        }
    }

    // Mark water tiles as impassable
    for i in 0..<4096 {
        let templateType = Int(mapCells[i].templateType)
        if templateType != 0xFF && templateType < templateTable.count {
            let name = templateTable[templateType].icnName.uppercased()
            // Water templates
            if name == "W1" || name == "W2" {
                staticPassability[i] = false
            }
        }
    }

    // Mark cells outside map bounds as impassable
    if let bounds = scenarioData?.mapBounds {
        for y in 0..<64 {
            for x in 0..<64 {
                if x < bounds.x || x >= bounds.x + bounds.width ||
                   y < bounds.y || y >= bounds.y + bounds.height {
                    staticPassability[y * 64 + x] = false
                }
            }
        }
    }

    let impassableCount = staticPassability.filter { !$0 }.count
    print("GameMap: Built passability map, \(impassableCount) impassable cells")
}

// MARK: - Dynamic Occupancy

/// Rebuild occupancy grid from current object positions
func updateOccupancy() {
    guard let world = gameWorld else { return }
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

func isCellPassable(cellX: Int, cellY: Int, ignoring: GameObject? = nil) -> Bool {
    guard cellX >= 0 && cellX < 64 && cellY >= 0 && cellY < 64 else { return false }
    let cell = cellY * 64 + cellX

    // Check static passability
    if !staticPassability[cell] { return false }

    // Check dynamic occupancy
    if let world = gameWorld, let occupantId = world.occupancy[cell] {
        if let ignoring = ignoring, occupantId == ignoring.id {
            return true
        }
        return false
    }

    return true
}

// MARK: - A* Pathfinding

private struct PathNode: Comparable {
    let x: Int
    let y: Int
    let g: Double    // Cost from start
    let f: Double    // g + heuristic

    static func < (lhs: PathNode, rhs: PathNode) -> Bool {
        lhs.f < rhs.f
    }
}

/// Find a path from (fromX, fromY) to (toX, toY) using A* on the 64x64 grid.
/// Returns array of (cellX, cellY) waypoints, or empty if no path found.
func findPath(fromX: Int, fromY: Int, toX: Int, toY: Int,
              ignoring: GameObject? = nil, maxSteps: Int = 400) -> [(cellX: Int, cellY: Int)] {

    // Quick bounds check
    guard fromX >= 0 && fromX < 64 && fromY >= 0 && fromY < 64 &&
          toX >= 0 && toX < 64 && toY >= 0 && toY < 64 else {
        return []
    }

    // If target is impassable (and it's not our own cell), find nearest passable cell
    let targetCell = toY * 64 + toX
    if !staticPassability[targetCell] {
        // Try to find nearest passable cell to target
        var bestX = toX, bestY = toY
        var bestDist = Double.infinity
        for dy in -3...3 {
            for dx in -3...3 {
                let nx = toX + dx
                let ny = toY + dy
                if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 &&
                   staticPassability[ny * 64 + nx] {
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
        return findPath(fromX: fromX, fromY: fromY, toX: bestX, toY: bestY, ignoring: ignoring, maxSteps: maxSteps)
    }

    // Already at target
    if fromX == toX && fromY == toY { return [] }

    // 8-directional movement
    let dirs: [(dx: Int, dy: Int, cost: Double)] = [
        (0, -1, 1.0), (1, 0, 1.0), (0, 1, 1.0), (-1, 0, 1.0),      // Cardinal
        (1, -1, 1.414), (1, 1, 1.414), (-1, 1, 1.414), (-1, -1, 1.414)  // Diagonal
    ]

    // Heuristic: Chebyshev distance (since we allow diagonal movement)
    func heuristic(_ x: Int, _ y: Int) -> Double {
        let dx = abs(x - toX)
        let dy = abs(y - toY)
        return Double(max(dx, dy)) + 0.414 * Double(min(dx, dy))
    }

    // Open set as a sorted array (simple priority queue)
    var openSet: [PathNode] = [PathNode(x: fromX, y: fromY, g: 0, f: heuristic(fromX, fromY))]
    var cameFrom: [Int: Int] = [:]  // cell -> parent cell
    var gScore: [Int: Double] = [fromY * 64 + fromX: 0]
    var closedSet = Set<Int>()

    var steps = 0
    while !openSet.isEmpty && steps < maxSteps {
        steps += 1

        // Find node with lowest f score
        var bestIdx = 0
        for i in 1..<openSet.count {
            if openSet[i].f < openSet[bestIdx].f {
                bestIdx = i
            }
        }
        let current = openSet.remove(at: bestIdx)
        let currentCell = current.y * 64 + current.x

        if current.x == toX && current.y == toY {
            // Reconstruct path
            var path: [(cellX: Int, cellY: Int)] = []
            var cell = currentCell
            while cell != fromY * 64 + fromX {
                path.append((cellX: cell % 64, cellY: cell / 64))
                guard let parent = cameFrom[cell] else { break }
                cell = parent
            }
            path.reverse()
            return path
        }

        closedSet.insert(currentCell)

        for dir in dirs {
            let nx = current.x + dir.dx
            let ny = current.y + dir.dy

            guard nx >= 0 && nx < 64 && ny >= 0 && ny < 64 else { continue }

            let neighborCell = ny * 64 + nx
            if closedSet.contains(neighborCell) { continue }

            // Check passability (ignore occupancy for pathfinding to allow units to flow)
            if !staticPassability[neighborCell] { continue }

            // For diagonal moves, ensure both adjacent cardinal cells are passable
            if dir.dx != 0 && dir.dy != 0 {
                let adjCell1 = current.y * 64 + nx
                let adjCell2 = ny * 64 + current.x
                if !staticPassability[adjCell1] || !staticPassability[adjCell2] { continue }
            }

            let tentativeG = current.g + dir.cost
            let existingG = gScore[neighborCell] ?? Double.infinity

            if tentativeG < existingG {
                gScore[neighborCell] = tentativeG
                cameFrom[neighborCell] = currentCell
                let f = tentativeG + heuristic(nx, ny)
                openSet.append(PathNode(x: nx, y: ny, g: tentativeG, f: f))
            }
        }
    }

    // No path found
    return []
}
