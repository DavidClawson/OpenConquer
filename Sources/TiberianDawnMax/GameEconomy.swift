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
    guard let scenario = scenarioData else { return }
    for overlay in scenario.overlays {
        let upper = overlay.typeName.uppercased()
        if upper.hasPrefix("TI") {
            // TI1 through TI12 are tiberium
            let numPart = upper.dropFirst(2)
            if let num = Int(numPart), num >= 1 && num <= 12 {
                map.tiberiumCells.insert(overlay.cell)
            }
        }
    }
    print("GameEconomy: Found \(map.tiberiumCells.count) tiberium cells")
}

// MARK: - Harvester State Machine

func tickHarvest(_ obj: GameObject) {
    guard let world = session.world else { return }
    let upper = obj.typeName.uppercased()
    if upper != "HARV" { return }

    // State machine based on current conditions
    if obj.tiberiumLoad >= maxTiberiumLoad {
        // Full — return to refinery
        if let refinery = findNearestRefinery(obj) {
            let dx = refinery.worldX - obj.worldX
            let dy = refinery.worldY - obj.worldY
            let dist = sqrt(dx * dx + dy * dy)

            if dist < 36.0 {
                // At refinery — deposit
                let creditsGained = obj.tiberiumLoad * tiberiumValue
                let houseState = getHouseState(obj.house)
                houseState.addCredits(creditsGained)
                // Keep sidebar credits in sync for the player
                if obj.house == session.world?.playerHouse {
                    session.sidebarCredits += creditsGained
                }
                obj.tiberiumLoad = 0
                // Clear movement to go find more tiberium
                obj.moveTargetX = nil
                obj.moveTargetY = nil
                obj.movePath = []
            } else {
                // Move toward refinery
                obj.moveTargetX = refinery.worldX
                obj.moveTargetY = refinery.worldY
                if obj.movePath.isEmpty {
                    obj.movePath = findPath(
                        fromX: obj.cellX, fromY: obj.cellY,
                        toX: refinery.cellX, toY: refinery.cellY,
                        ignoring: obj,
                        speedType: .harvester
                    )
                }
                let _ = obj.moveOneStep()
            }
        } else {
            // No refinery — just sit
            obj.moveTargetX = nil
            obj.moveTargetY = nil
        }
    } else if world.map.tiberiumCells.contains(obj.cell) {
        // On tiberium — harvest
        // Harvest one unit every few ticks
        if world.tickCount % 4 == 0 {
            obj.tiberiumLoad += 1
            // Deplete tiberium after multiple harvests
            if obj.tiberiumLoad % 5 == 0 {
                world.map.tiberiumCells.remove(obj.cell)
            }
        }
    } else {
        // Not on tiberium and not full — find nearest tiberium
        if let target = findNearestTiberium(obj) {
            let targetPx = Double(target.cellX * 24) + 12.0
            let targetPy = Double(target.cellY * 24) + 12.0

            // Check if we're already moving to tiberium
            if let mx = obj.moveTargetX, let my = obj.moveTargetY {
                let dx = mx - targetPx
                let dy = my - targetPy
                if sqrt(dx * dx + dy * dy) < 2.0 {
                    // Already heading there
                    let _ = obj.moveOneStep()
                    return
                }
            }

            obj.moveTargetX = targetPx
            obj.moveTargetY = targetPy
            obj.movePath = findPath(
                fromX: obj.cellX, fromY: obj.cellY,
                toX: target.cellX, toY: target.cellY,
                ignoring: obj,
                speedType: .harvester
            )
            let _ = obj.moveOneStep()
        } else {
            // No tiberium left — return to refinery if carrying anything
            if obj.tiberiumLoad > 0 {
                obj.tiberiumLoad = maxTiberiumLoad  // Force return
            }
        }
    }
}

/// Find nearest tiberium cell to a harvester
func findNearestTiberium(_ obj: GameObject) -> (cellX: Int, cellY: Int)? {
    guard let map = session.world?.map else { return nil }
    var bestCell: (cellX: Int, cellY: Int)? = nil
    var bestDist = Double.infinity

    for cell in map.tiberiumCells {
        let cx = cell % 64
        let cy = cell / 64
        let dx = Double(cx) - Double(obj.cellX)
        let dy = Double(cy) - Double(obj.cellY)
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            bestCell = (cellX: cx, cellY: cy)
        }
    }
    return bestCell
}

/// Find nearest refinery owned by this object's house
func findNearestRefinery(_ obj: GameObject) -> GameObject? {
    guard let world = session.world else { return nil }
    var nearest: GameObject? = nil
    var nearestDist = Double.infinity

    for other in world.objects {
        if other.kind != .structure { continue }
        if other.house != obj.house { continue }
        if other.strength <= 0 { continue }
        if other.typeName.uppercased() != "PROC" { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < nearestDist {
            nearest = other
            nearestDist = dist
        }
    }
    return nearest
}
