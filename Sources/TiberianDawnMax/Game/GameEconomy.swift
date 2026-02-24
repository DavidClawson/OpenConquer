import Foundation

// MARK: - Tiberium System

// tiberiumCells is now in GameWorld.map (GameMap)

/// Maximum tiberium a harvester can carry
let maxTiberiumLoad: Int = 20

/// Credits per unit of tiberium
let tiberiumValue: Int = 25

/// Scan scenario overlays for tiberium
func initTiberiumCells() {
    guard let map = session.world?.map else { return }
    map.tiberiumCells.removeAll()
    map.tiberiumDensity.removeAll()
    guard let scenario = scenarioData else {
        print("GameEconomy: No scenarioData available for tiberium init")
        return
    }
    print("GameEconomy: Scanning \(scenario.overlays.count) overlays for tiberium")
    // Log first few overlays for debugging
    for (i, ov) in scenario.overlays.prefix(10).enumerated() {
        print("  overlay[\(i)]: cell=\(ov.cell) type='\(ov.typeName)'")
    }
    // First pass: register all tiberium cells
    for overlay in scenario.overlays {
        let upper = overlay.typeName.uppercased()
        if upper.hasPrefix("TI") {
            let numPart = upper.dropFirst(2)
            if let num = Int(numPart), num >= 1 && num <= 12 {
                map.tiberiumCells.insert(overlay.cell)
                // Use the overlay's TI number as initial density (TI1=sparse, TI12=full)
                map.tiberiumDensity[overlay.cell] = num
            }
        }
    }

    // Second pass: adjust density based on neighbor count (VC Tiberium_Adjust)
    // Cells surrounded by more tiberium should be denser
    let adjTable = [0, 1, 3, 4, 6, 7, 8, 10, 11]
    for cell in map.tiberiumCells {
        let cx = cell % 64
        let cy = cell / 64
        var adjCount = 0
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = cx + dx
                let ny = cy + dy
                if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 {
                    if map.tiberiumCells.contains(ny * 64 + nx) {
                        adjCount += 1
                    }
                }
            }
        }
        // Use max of original TI number and neighbor-based density
        let neighborDensity = adjTable[min(adjCount, adjTable.count - 1)] + 1
        let current = map.tiberiumDensity[cell] ?? 1
        map.tiberiumDensity[cell] = min(max(current, neighborDensity), 12)
    }
    print("GameEconomy: Found \(map.tiberiumCells.count) tiberium cells")
}

// MARK: - Harvester Extension

extension GameObject {

    /// Tick harvester state machine
    func tickHarvest() {
        guard let world = session.world else { return }
        let upper = typeName.uppercased()
        if upper != "HARV" { return }

        // Harvester threat avoidance: check for nearby enemy combat units every 15 ticks
        if world.tickCount % 15 == 0 {
            let fleeRange = 5.0 * 24.0  // 5 cells in pixels
            var nearestEnemy: GameObject? = nil
            var nearestEnemyDist = Double.infinity

            for other in world.objects {
                guard other.strength > 0 else { continue }
                guard other.house != house else { continue }
                guard other.house != .neutral else { continue }
                guard !other.isAircraft else { continue }
                // Only flee from armed ground units (not other harvesters, not unarmed)
                guard other.isArmed else { continue }
                guard other.kind == .unit || other.kind == .infantry else { continue }

                let dx = other.worldX - worldX
                let dy = other.worldY - worldY
                let dist = sqrt(dx * dx + dy * dy)
                if dist < fleeRange && dist < nearestEnemyDist {
                    nearestEnemy = other
                    nearestEnemyDist = dist
                }
            }

            if let enemy = nearestEnemy {
                if tiberiumLoad > 0 {
                    // Carrying tiberium: force return to refinery immediately
                    tiberiumLoad = maxTiberiumLoad
                    moveTargetX = nil
                    moveTargetY = nil
                    movePath = []
                    // Fall through to the normal "full" return-to-refinery logic below
                } else {
                    // Empty: flee in opposite direction from enemy
                    let dx = worldX - enemy.worldX
                    let dy = worldY - enemy.worldY
                    let dist = max(1.0, sqrt(dx * dx + dy * dy))
                    let fleeX = max(12, min(64 * 24 - 12, worldX + dx / dist * 120))
                    let fleeY = max(12, min(64 * 24 - 12, worldY + dy / dist * 120))
                    moveTargetX = fleeX
                    moveTargetY = fleeY
                    movePath = []
                    moveOneStep()
                    return
                }
            }
        }

        // State machine based on current conditions
        if tiberiumLoad >= maxTiberiumLoad {
            // Full — return to refinery
            if let refinery = findNearestRefinery() {
                let dx = refinery.worldX - worldX
                let dy = refinery.worldY - worldY
                let dist = sqrt(dx * dx + dy * dy)

                if dist < 36.0 {
                    // At refinery — deposit
                    var creditsGained = tiberiumLoad * tiberiumValue
                    let houseState = getHouseState(house)
                    // Enforce silo capacity: only store up to capacity limit
                    if houseState.capacity > 0 {
                        let currentStored = houseState.tiberium
                        let spaceLeft = max(0, houseState.capacity - currentStored)
                        let creditsToStore = min(creditsGained, spaceLeft)
                        houseState.tiberium += creditsToStore
                        creditsGained = creditsToStore
                    }
                    houseState.addCredits(creditsGained)
                    // Keep sidebar credits in sync for the player
                    if house == session.world?.playerHouse {
                        session.sidebarCredits += creditsGained
                    }
                    tiberiumLoad = 0
                    // Clear movement to go find more tiberium
                    moveTargetX = nil
                    moveTargetY = nil
                    movePath = []
                } else {
                    // Move toward refinery
                    moveTargetX = refinery.worldX
                    moveTargetY = refinery.worldY
                    if movePath.isEmpty {
                        movePath = findPath(
                            fromX: cellX, fromY: cellY,
                            toX: refinery.cellX, toY: refinery.cellY,
                            ignoring: self,
                            speedType: .harvester
                        )
                    }
                    let _ = moveOneStep()
                }
            } else {
                // No refinery — just sit
                moveTargetX = nil
                moveTargetY = nil
            }
        } else if world.map.tiberiumCells.contains(cell) {
            // On tiberium — harvest
            // Harvest one unit every few ticks
            if world.tickCount % 4 == 0 {
                tiberiumLoad += 1
                // Reduce density; remove cell when depleted
                if tiberiumLoad % 5 == 0 {
                    let density = world.map.tiberiumDensity[cell] ?? 1
                    if density <= 1 {
                        world.map.tiberiumCells.remove(cell)
                        world.map.tiberiumDensity.removeValue(forKey: cell)
                    } else {
                        world.map.tiberiumDensity[cell] = density - 1
                    }
                }
            }
        } else {
            // Not on tiberium and not full — find nearest tiberium
            if let target = findNearestTiberium() {
                let targetPx = Double(target.cellX * 24) + 12.0
                let targetPy = Double(target.cellY * 24) + 12.0

                // Check if we're already moving to tiberium
                if let mx = moveTargetX, let my = moveTargetY {
                    let dx = mx - targetPx
                    let dy = my - targetPy
                    if sqrt(dx * dx + dy * dy) < 2.0 {
                        // Already heading there
                        let _ = moveOneStep()
                        return
                    }
                }

                moveTargetX = targetPx
                moveTargetY = targetPy
                movePath = findPath(
                    fromX: cellX, fromY: cellY,
                    toX: target.cellX, toY: target.cellY,
                    ignoring: self,
                    speedType: .harvester
                )
                let _ = moveOneStep()
            } else {
                // No tiberium left — return to refinery if carrying anything
                if tiberiumLoad > 0 {
                    tiberiumLoad = maxTiberiumLoad  // Force return
                }
            }
        }
    }

    /// Find nearest tiberium cell to this harvester
    func findNearestTiberium() -> (cellX: Int, cellY: Int)? {
        guard let map = session.world?.map else { return nil }
        var bestCell: (cellX: Int, cellY: Int)? = nil
        var bestDist = Double.infinity

        for cell in map.tiberiumCells {
            let cx = cell % 64
            let cy = cell / 64
            let dx = Double(cx) - Double(cellX)
            let dy = Double(cy) - Double(cellY)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestCell = (cellX: cx, cellY: cy)
            }
        }
        return bestCell
    }

    /// Find nearest refinery owned by this object's house
    func findNearestRefinery() -> GameObject? {
        guard let world = session.world else { return nil }
        var nearest: GameObject? = nil
        var nearestDist = Double.infinity

        for other in world.objects {
            if other.kind != .structure { continue }
            if other.house != house { continue }
            if other.strength <= 0 { continue }
            if other.typeName.uppercased() != "PROC" { continue }

            let dx = other.worldX - worldX
            let dy = other.worldY - worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < nearestDist {
                nearest = other
                nearestDist = dist
            }
        }
        return nearest
    }
}

// MARK: - Tiberium Growth & Spread

extension GameMap {

    /// Number of cells scanned per tick (VC scans MAP_CELL_TOTAL over ~136 ticks)
    private static let scanBlockSize = 4096 / 136  // ~30 cells per tick

    /// Maximum entries in growth/spread candidate lists (VC uses MAP_CELL_W/2 = 32)
    private static let maxCandidates = 32

    /// 8-directional adjacency offsets (dx, dy)
    private static let adjacentOffsets: [(dx: Int, dy: Int)] = [
        (0, -1), (1, -1), (1, 0), (1, 1),
        (0, 1), (-1, 1), (-1, 0), (-1, -1)
    ]

    /// Tick tiberium growth and spread.
    /// Faithfully ports VC MapClass::Logic() — scans a block of cells each tick,
    /// accumulates growth/spread candidates across multiple ticks, then processes
    /// them all when a full scan cycle completes.
    func tickTiberiumGrowth() {
        // Scan a block of cells this tick, accumulating candidates
        var remaining = GameMap.scanBlockSize
        var index = tiberiumScan

        while index < 4096 && remaining > 0 {
            let cell = isForwardScan ? index : (4095 - index)

            if tiberiumCells.contains(cell) {
                let density = tiberiumDensity[cell] ?? 1

                // Growth: cells with density < 12 can grow
                if density < 12 {
                    if tiberiumGrowthCandidates.count < GameMap.maxCandidates {
                        tiberiumGrowthCandidates.append(cell)
                    } else {
                        // Reservoir sampling — replace a random existing entry
                        tiberiumGrowthCandidates[Int.random(in: 0..<tiberiumGrowthCandidates.count)] = cell
                    }
                }

                // Spread: cells with density > 6 can spread (VC: OverlayData > 6)
                if density > 6 {
                    if tiberiumSpreadCandidates.count < GameMap.maxCandidates {
                        tiberiumSpreadCandidates.append(cell)
                    } else {
                        tiberiumSpreadCandidates[Int.random(in: 0..<tiberiumSpreadCandidates.count)] = cell
                    }
                }
            }

            index += 1
            remaining -= 1
        }

        tiberiumScan = index

        // Only process candidates when a full scan cycle completes
        guard tiberiumScan >= 4096 else { return }

        // Reset scan for next cycle
        tiberiumScan = 0
        isForwardScan.toggle()

        // Growth: pick random candidates and increase their density
        // Process up to 4 growth candidates per cycle for visible growth rate
        let growthPicks = min(4, tiberiumGrowthCandidates.count)
        for _ in 0..<growthPicks {
            let pick = Int.random(in: 0..<tiberiumGrowthCandidates.count)
            let cell = tiberiumGrowthCandidates[pick]
            if tiberiumCells.contains(cell) {
                let current = tiberiumDensity[cell] ?? 1
                if current < 12 {
                    tiberiumDensity[cell] = current + 1
                }
            }
        }

        // Spread: pick random candidates and try to spread to adjacent empty cells
        // Process up to 2 spread candidates per cycle
        let spreadPicks = min(2, tiberiumSpreadCandidates.count)
        for _ in 0..<spreadPicks {
            let pick = Int.random(in: 0..<tiberiumSpreadCandidates.count)
            let cell = tiberiumSpreadCandidates[pick]
            let cx = cell % 64
            let cy = cell / 64

            // Start from a random direction and try all 8 adjacent cells
            let startDir = Int.random(in: 0..<8)
            for i in 0..<8 {
                let dir = (startDir + i) % 8
                let offset = GameMap.adjacentOffsets[dir]
                let nx = cx + offset.dx
                let ny = cy + offset.dy

                guard nx >= 0 && nx < 64 && ny >= 0 && ny < 64 else { continue }
                let adjCell = ny * 64 + nx

                // Only spread to passable land cells without existing tiberium
                guard !tiberiumCells.contains(adjCell) else { continue }
                guard adjCell < landPassability.count && landPassability[adjCell] else { continue }

                // Don't spread onto water
                guard adjCell < waterPassability.count && !waterPassability[adjCell] else { continue }

                // Don't spread onto cells occupied by structures
                if let world = session.world {
                    let occupied = world.objects.contains { obj in
                        obj.kind == .structure && obj.strength > 0 && obj.cell == adjCell
                    }
                    if occupied { continue }
                }

                // Spread tiberium to this cell
                tiberiumCells.insert(adjCell)
                tiberiumDensity[adjCell] = 1
                break
            }
        }

        // Clear candidate lists for next scan cycle
        tiberiumGrowthCandidates.removeAll(keepingCapacity: true)
        tiberiumSpreadCandidates.removeAll(keepingCapacity: true)
    }
}
