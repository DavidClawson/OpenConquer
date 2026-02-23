import CSDL2
import Foundation

// MARK: - Game Tick Timing

let ticksPerSecond = 15
let tickDurationMs: UInt32 = 66  // ~15 FPS (1000/15)
var tickAccumulator: UInt32 = 0
var lastTickTime: UInt32 = 0

// MARK: - Game Update

func updateGame() {
    let now = SDL_GetTicks()
    if lastTickTime == 0 {
        lastTickTime = now
        return
    }

    let elapsed = now - lastTickTime
    lastTickTime = now
    tickAccumulator += elapsed

    // Run game ticks at fixed 15 FPS rate
    while tickAccumulator >= tickDurationMs {
        tickAccumulator -= tickDurationMs
        gameTick()
    }
}

// MARK: - Game Tick

func gameTick() {
    guard let world = gameWorld else { return }
    world.tickCount += 1

    // Update occupancy at start of tick
    updateOccupancy()

    // Update fog of war
    updateFog()

    // Tick production
    tickProduction()

    // Tick AI
    tickAI()

    // Update each object by mission
    for obj in world.objects {
        switch obj.mission {
        case .move:
            tickMove(obj)
        case .attack:
            tickAttack(obj)
        case .harvest:
            tickHarvest(obj)
        case .guard_:
            // Auto-target enemies for armed units/structures
            if weaponData[obj.typeName.uppercased()] != nil {
                tickGuardScan(obj)
            }
        case .stop, .sleep:
            break
        }
    }

    // Remove dead objects
    removeDeadObjects()
}

// MARK: - Movement Tick

func tickMove(_ obj: GameObject) {
    guard let targetX = obj.moveTargetX, let targetY = obj.moveTargetY else {
        obj.mission = .guard_
        return
    }

    // If we have no path, compute one via A*
    if obj.movePath.isEmpty {
        let fromCellX = obj.cellX
        let fromCellY = obj.cellY
        let toCellX = Int(targetX) / 24
        let toCellY = Int(targetY) / 24

        // Only pathfind if we're not already at the target cell
        if fromCellX != toCellX || fromCellY != toCellY {
            let path = findPath(
                fromX: fromCellX, fromY: fromCellY,
                toX: toCellX, toY: toCellY,
                ignoring: obj
            )
            if path.isEmpty {
                // No path found, stop
                obj.mission = .guard_
                obj.moveTargetX = nil
                obj.moveTargetY = nil
                return
            }
            obj.movePath = path
        }
    }

    // Determine the next waypoint to move toward
    let nextX: Double
    let nextY: Double

    if !obj.movePath.isEmpty {
        // Move toward the center of the next path cell
        let nextCell = obj.movePath[0]
        nextX = Double(nextCell.cellX * 24) + 12.0
        nextY = Double(nextCell.cellY * 24) + 12.0
    } else {
        // We're in the target cell, move to exact target position
        nextX = targetX
        nextY = targetY
    }

    let dx = nextX - obj.worldX
    let dy = nextY - obj.worldY
    let dist = sqrt(dx * dx + dy * dy)

    // Update facing to point toward movement direction
    if dist > 0.5 {
        obj.facing = directionToFacing(dx: dx, dy: dy)
    }

    if dist <= obj.speed {
        // Arrived at waypoint
        obj.worldX = nextX
        obj.worldY = nextY

        if !obj.movePath.isEmpty {
            obj.movePath.removeFirst()

            // If we've consumed all waypoints, check if we're at final target
            if obj.movePath.isEmpty {
                let finalDx = targetX - obj.worldX
                let finalDy = targetY - obj.worldY
                let finalDist = sqrt(finalDx * finalDx + finalDy * finalDy)
                if finalDist < 2.0 {
                    obj.mission = .guard_
                    obj.moveTargetX = nil
                    obj.moveTargetY = nil
                }
            }
        } else {
            // Arrived at final target
            obj.mission = .guard_
            obj.moveTargetX = nil
            obj.moveTargetY = nil
        }
    } else {
        // Move toward waypoint
        let moveX = (dx / dist) * obj.speed
        let moveY = (dy / dist) * obj.speed
        obj.worldX += moveX
        obj.worldY += moveY
    }
}

// MARK: - Facing Calculation

/// Convert movement direction to C&C 0-255 facing
/// C&C convention: 0=North, 64=East, 128=South, 192=West
func directionToFacing(dx: Double, dy: Double) -> Int {
    // atan2 gives angle from positive X axis, counterclockwise
    // We need: 0=N (up, -Y), 64=E (+X), 128=S (+Y), 192=W (-X)
    let angle = atan2(dx, -dy)  // Note: (dx, -dy) maps to N=0
    var facing = Int(angle / (2.0 * .pi) * 256.0)
    if facing < 0 { facing += 256 }
    return facing & 0xFF
}
