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

    /// Tiberium density / growth stage per cell (1-12). Drives both harvest
    /// yield and the SHP frame drawn — frame = density - 1 (so density 12
    /// shows the mature bright-green frame 11).
    var tiberiumDensity: [Int: Int] = [:]

    /// Tiberium SHP variant per cell (1-12). C&C ships TI1.SHP through
    /// TI12.SHP — different sprite shapes, each with 12 maturity frames.
    /// The variant picks which shape to render; density picks which frame.
    /// Defaults to 1 if missing (legacy saves).
    var tiberiumVariant: [Int: Int] = [:]

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

    /// Fog state for each of the 4096 cells (player perspective: unexplored/explored/visible)
    var fogState: [FogLevel] = Array(repeating: .unexplored, count: 4096)

    /// Per-house live visibility. `true` at index `cell` means the house has
    /// at least one living unit/structure with line-of-sight to that cell.
    /// Used to gate AI target acquisition so units can't fire at enemies in
    /// their own fog of war. Recomputed each tick alongside fogState.
    var houseVisibility: [House: [Bool]] = [:]
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

/// Overlay-type metadata for passability. Mirrors Vanilla-Conquer odata.cpp:
/// walls (LAND_WALL: SBAG/CYCL/BRIK/BARB/WOOD) block movement; tiberium
/// (TI1-TI12), roads (ROAD/CONC), crates (WCRATE/SCRATE), and the flag spot
/// stay passable.
private let blockingOverlayTypes: Set<String> = [
    "SBAG",   // Sandbag wall
    "CYCL",   // Cyclone (chain-link) fence
    "BRIK",   // Brick/concrete wall
    "BARB",   // Barbed wire
    "WOOD",   // Wood fence
]

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
        // (trees T01-T18/TC01-TC14, civilian decor V01-V18, rocks SPLIT*/ROCK*)
        for terrainObj in scenario.terrain {
            let cell = terrainObj.cell
            if cell >= 0 && cell < 4096 {
                landPassability[cell] = false
                waterPassability[cell] = false
            }
        }

        // Mark wall-type overlays as impassable. Tiberium, roads, crates, and
        // flag spots are skipped — units must be able to walk over them.
        for overlay in scenario.overlays {
            guard blockingOverlayTypes.contains(overlay.typeName.uppercased()) else { continue }
            let cell = overlay.cell
            if cell >= 0 && cell < 4096 {
                landPassability[cell] = false
                waterPassability[cell] = false
            }
        }
    }

    // Classify each cell from its template's land type (ported from the
    // original CDATA.CPP TemplateTypeClass land data — see TemplateLandData.swift
    // and cellLandType below). This replaces the old name-prefix + pixel-analysis
    // heuristics, which left cliffs/slopes (LAND_ROCK) and boulders passable.
    //   - Ground units can't enter water, rock (cliffs/boulders), or wall cells.
    //   - Naval units can only traverse water.
    // Per-icon exceptions (e.g. the walkable ramp icon of a slope, the deck of a
    // bridge, the fordable icons of a river) are honored via altIcons.
    for i in 0..<4096 {
        let land = cellLandType(templateType: mapCells[i].templateType,
                                iconIndex: mapCells[i].iconIndex)
        if land == .water || land == .rock || land == .wall {
            landPassability[i] = false
        }
        if land != .water {
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

/// Land type of a cell, resolved from its template + icon index. Mirrors
/// CellClass::Recalc_Attributes (CELL.CPP:~500-520): default to the template's
/// land type, but use the alternate land type for icons listed in altIcons.
/// Returns .clear for empty/unknown templates (clear terrain).
func cellLandType(templateType: UInt8, iconIndex: UInt8) -> LandType {
    let tt = Int(templateType)
    if tt == 0xFF || tt >= templateTable.count { return .clear }
    let name = templateTable[tt].icnName.uppercased()
    guard let data = templateLandData[name] else { return .clear }
    if data.altIcons.contains(Int(iconIndex)) { return data.altLand }
    return data.land
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

/// Maximum infantry that can share a single cell.
/// Original C&C allows 5, with each occupant assigned a sub-cell offset
/// (NW/N/NE/W/Center/E/SW/S/SE). Until sub-cell offset rendering is in
/// place this is set to 1 so a cluster of soldiers doesn't visibly stack
/// at the same pixel — the multi-occupant scaffolding stays in place so
/// raising this back to 5 later only requires adding render offsets.
let maxInfantryPerCell = 1

/// Rebuild occupancy grid from current object positions
func updateOccupancy() {
    guard let world = session.world else { return }
    world.occupancy.removeAll(keepingCapacity: true)

    for obj in world.objects {
        if obj.kind == .structure { continue }  // Structures use static passability
        if obj.strength <= 0 { continue }
        let cell = obj.cell
        if cell >= 0 && cell < 4096 {
            world.occupancy[cell, default: []].append(obj.id)
        }
    }
}

/// Convenience: any vehicle/aircraft in this cell? (structures excluded —
/// they use static passability.)
func cellHasVehicle(_ cell: Int, world: GameWorld, ignoringId: Int? = nil) -> Bool {
    guard let ids = world.occupancy[cell] else { return false }
    for id in ids where id != ignoringId {
        if let obj = world.findObject(id: id), obj.kind == .unit { return true }
    }
    return false
}

/// Count infantry currently in this cell (for the 5-per-cell stacking rule).
func cellInfantryCount(_ cell: Int, world: GameWorld, ignoringId: Int? = nil) -> Int {
    guard let ids = world.occupancy[cell] else { return 0 }
    var count = 0
    for id in ids where id != ignoringId {
        if let obj = world.findObject(id: id), obj.kind == .infantry { count += 1 }
    }
    return count
}

/// Sweep the world for cells holding more than one unit and tell the extras
/// to scatter to the nearest free neighbor. Catches scenarios where two
/// units start the mission overlapping (or where a spawn slipped past the
/// destination check) — without this, idle stacked units never move and
/// stay glued together.
func resolveStackedUnits() {
    guard let world = session.world else { return }
    for (cell, ids) in world.occupancy where ids.count > 1 {
        // Prefer to scatter mobile/idle units; leave busy ones in place
        // unless every co-occupant is busy.
        var picked: GameObject? = nil
        for id in ids {
            guard let obj = world.findObject(id: id) else { continue }
            // Vehicles must scatter; infantry only if we exceed the cap.
            let exceedsCap = obj.kind == .infantry &&
                cellInfantryCount(cell, world: world) > maxInfantryPerCell
            guard obj.kind == .unit || exceedsCap else { continue }
            // Only nudge units that aren't already on a path; a unit mid-move
            // will resolve itself.
            guard obj.moveTargetX == nil else { continue }
            picked = obj
            break
        }
        guard let scatterer = picked else { continue }
        guard let target = findFreeSpawnCell(
            nearWorldX: scatterer.worldX,
            nearWorldY: scatterer.worldY,
            kind: scatterer.kind,
            speedType: scatterer.cachedSpeedType,
            radius: 4
        ) else { continue }
        scatterer.moveTargetX = Double(target.cellX * 24) + 12.0
        scatterer.moveTargetY = Double(target.cellY * 24) + 12.0
        scatterer.movePath = []
        if scatterer.mission == .guard_ || scatterer.mission == .stop {
            scatterer.mission = .move
        }
    }
}

/// Find a free cell near a desired spawn point. Used by production spawns
/// and the free-harvester drop on PROC build, so a new unit doesn't land
/// on top of an existing unit and immediately get stuck.
///
/// Searches outward in a square spiral up to `radius` cells; returns the
/// closest cell that is statically passable AND has no vehicle (and < max
/// infantry, for an infantry spawn). Returns nil if no slot is free.
func findFreeSpawnCell(nearWorldX: Double, nearWorldY: Double,
                       kind: ObjectKind, speedType: SpeedType = .track,
                       radius: Int = 6) -> (cellX: Int, cellY: Int)? {
    guard let world = session.world else { return nil }
    let baseX = max(0, min(63, Int(nearWorldX) / 24))
    let baseY = max(0, min(63, Int(nearWorldY) / 24))
    let passMap = passabilityMap(for: speedType)

    for r in 0...radius {
        var best: (cellX: Int, cellY: Int)? = nil
        var bestDist = Double.infinity
        for dy in -r...r {
            for dx in -r...r {
                // Outer ring only at this radius (skip cells already
                // checked at smaller r).
                if r > 0 && abs(dx) != r && abs(dy) != r { continue }
                let nx = baseX + dx
                let ny = baseY + dy
                guard nx >= 0 && nx < 64 && ny >= 0 && ny < 64 else { continue }
                let cellIdx = ny * 64 + nx
                if !passMap[cellIdx] { continue }
                if cellHasVehicle(cellIdx, world: world) { continue }
                if kind == .unit {
                    if cellInfantryCount(cellIdx, world: world) > 0 { continue }
                } else if kind == .infantry {
                    if cellInfantryCount(cellIdx, world: world) >= maxInfantryPerCell { continue }
                }
                let dist = Double(dx * dx + dy * dy)
                if dist < bestDist {
                    bestDist = dist
                    best = (cellX: nx, cellY: ny)
                }
            }
        }
        if let found = best { return found }
    }
    return nil
}

// MARK: - Passability Check

/// Can `mover` enter `cell` for transit?
/// Friendly units allow passthrough so squad movement stays smooth; enemies
/// block. Cell occupancy is checked separately at arrival via
/// `isCellEnterableAsDestination` so units don't permanently stack.
func isCellPassable(cellX: Int, cellY: Int, ignoring: GameObject? = nil, speedType: SpeedType = .foot) -> Bool {
    guard cellX >= 0 && cellX < 64 && cellY >= 0 && cellY < 64 else { return false }
    let cell = cellY * 64 + cellX

    // Static terrain passability (walls, water, structures, trees, etc.)
    let passMap = passabilityMap(for: speedType)
    if !passMap[cell] { return false }

    // Dynamic occupants. Allow self and friendlies; block enemies.
    guard let world = session.world, let ids = world.occupancy[cell] else { return true }
    for occupantId in ids {
        if occupantId == ignoring?.id { continue }
        guard let occupant = world.findObject(id: occupantId) else { continue }
        if let mover = ignoring, occupant.house == mover.house { continue }
        return false  // enemy in cell — blocked
    }
    return true
}

/// Can `mover` come to rest in `cell`? Stricter than `isCellPassable`:
/// vehicles need the cell free of any other unit; infantry need the cell free
/// of vehicles and with fewer than `maxInfantryPerCell` infantry already
/// present. This is what stops squads from collapsing onto a single cell.
func isCellEnterableAsDestination(cell: Int, mover: GameObject) -> Bool {
    guard cell >= 0 && cell < 4096 else { return false }
    guard let world = session.world else { return true }

    // Static passability still has to hold.
    let passMap = passabilityMap(for: mover.cachedSpeedType)
    if !passMap[cell] { return false }

    // Vehicles and aircraft are "vehicle-class" for occupancy purposes.
    let moverIsVehicle = mover.kind == .unit
    let moverId = mover.id

    if moverIsVehicle {
        // Vehicle destination: no other vehicle, no infantry occupying.
        if cellHasVehicle(cell, world: world, ignoringId: moverId) { return false }
        if cellInfantryCount(cell, world: world, ignoringId: moverId) > 0 { return false }
        return true
    } else {
        // Infantry destination: no vehicle, and infantry count < 5.
        if cellHasVehicle(cell, world: world, ignoringId: moverId) { return false }
        if cellInfantryCount(cell, world: world, ignoringId: moverId) >= maxInfantryPerCell { return false }
        return true
    }
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

    // Reroute the destination if the requested cell can't actually be the
    // unit's resting place — either the static terrain forbids it (water,
    // tree, building) OR another unit already occupies it under the
    // 1-vehicle / 5-infantry rules. The latter is what makes squads spread
    // out around a click point instead of collapsing onto one cell.
    let targetCell = toY * 64 + toX
    let targetEnterable: Bool = {
        if !passMap[targetCell] { return false }
        if let mover = ignoring {
            return isCellEnterableAsDestination(cell: targetCell, mover: mover)
        }
        return true
    }()
    if !targetEnterable {
        var bestX = toX, bestY = toY
        var bestDist = Double.infinity
        for dy in -5...5 {
            for dx in -5...5 {
                let nx = toX + dx
                let ny = toY + dy
                guard nx >= 0 && nx < 64 && ny >= 0 && ny < 64 else { continue }
                let cellIdx = ny * 64 + nx
                if !passMap[cellIdx] { continue }
                if let mover = ignoring,
                   !isCellEnterableAsDestination(cell: cellIdx, mover: mover) { continue }
                let dist = sqrt(Double(dx * dx + dy * dy))
                if dist < bestDist {
                    bestDist = dist
                    bestX = nx
                    bestY = ny
                }
            }
        }
        if bestDist == Double.infinity { return [] }
        if bestX == fromX && bestY == fromY { return [] }
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
            if let occ = occupancy, let occupants = occ[neighborCell] {
                let othersHere = occupants.contains { $0 != ignoringId }
                if othersHere {
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
