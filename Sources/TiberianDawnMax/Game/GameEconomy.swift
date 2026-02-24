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
    guard let scenario = scenarioData else { return }
    for overlay in scenario.overlays {
        let upper = overlay.typeName.uppercased()
        if upper.hasPrefix("TI") {
            // TI1 through TI12 are tiberium
            let numPart = upper.dropFirst(2)
            if let num = Int(numPart), num >= 1 && num <= 12 {
                map.tiberiumCells.insert(overlay.cell)
                // Count adjacent tiberium cells to set initial density (VC Tiberium_Adjust)
                let adjTable = [0, 1, 3, 4, 6, 7, 8, 10, 11]
                var adjCount = 0
                let cx = overlay.cell % 64
                let cy = overlay.cell / 64
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nx = cx + dx
                        let ny = cy + dy
                        if nx < 0 || nx >= 64 || ny < 0 || ny >= 64 { continue }
                        let adjCell = ny * 64 + nx
                        // Check if any other overlay is tiberium at this cell
                        for other in scenario.overlays {
                            if other.cell == adjCell {
                                let ou = other.typeName.uppercased()
                                if ou.hasPrefix("TI"), let on = Int(ou.dropFirst(2)), on >= 1 && on <= 12 {
                                    adjCount += 1
                                    break
                                }
                            }
                        }
                    }
                }
                let density = adjTable[min(adjCount, adjTable.count - 1)] + 1
                map.tiberiumDensity[overlay.cell] = min(density, 12)
            }
        }
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

        // State machine based on current conditions
        if tiberiumLoad >= maxTiberiumLoad {
            // Full — return to refinery
            if let refinery = findNearestRefinery() {
                let dx = refinery.worldX - worldX
                let dy = refinery.worldY - worldY
                let dist = sqrt(dx * dx + dy * dy)

                if dist < 36.0 {
                    // At refinery — deposit
                    let creditsGained = tiberiumLoad * tiberiumValue
                    let houseState = getHouseState(house)
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

        // Growth: pick a random candidate and increase its density
        if !tiberiumGrowthCandidates.isEmpty {
            let pick = Int.random(in: 0..<tiberiumGrowthCandidates.count)
            let cell = tiberiumGrowthCandidates[pick]
            if tiberiumCells.contains(cell) {
                let current = tiberiumDensity[cell] ?? 1
                if current < 12 {
                    tiberiumDensity[cell] = current + 1
                }
            }
        }

        // Spread: pick a random candidate and try to spread to an adjacent empty cell
        if !tiberiumSpreadCandidates.isEmpty {
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
