import Foundation

// MARK: - Enemy AI

var aiTickCounter: Int = 0

/// AI update — called every game tick but only acts periodically
func tickAI() {
    guard let world = gameWorld else { return }
    aiTickCounter += 1

    // AI acts every 30 ticks (~2 seconds)
    guard aiTickCounter % 30 == 0 else { return }

    let aggroRange: Double = 8.0 * 24.0  // 8 cells in pixels

    for obj in world.objects {
        // Only control enemy (non-player) units
        if obj.house == world.playerHouse { continue }
        if obj.house == .neutral { continue }
        if obj.strength <= 0 { continue }

        // Turrets / defense structures auto-target
        if obj.kind == .structure {
            if weaponData[obj.typeName.uppercased()] != nil && obj.mission != .attack {
                if let enemy = findNearestEnemy(obj, range: aggroRange) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
            continue
        }

        // Idle enemy units (on guard) — scan for nearby player units
        if obj.mission == .guard_ || obj.mission == .stop {
            if let enemy = findNearestEnemy(obj, range: aggroRange) {
                obj.attackTarget = enemy.id
                obj.mission = .attack
            }
        }

        // Enemy harvesters auto-harvest
        if obj.typeName.uppercased() == "HARV" && obj.mission == .guard_ {
            obj.mission = .harvest
        }
    }

    // Rally idle enemy units toward player base every ~20 seconds
    if aiTickCounter % 300 == 0 {
        rallyEnemyUnits(world: world)
    }
}

/// Find the average position of player structures
func findPlayerBase(world: GameWorld) -> (x: Double, y: Double)? {
    var totalX = 0.0
    var totalY = 0.0
    var count = 0

    for obj in world.objects {
        if obj.kind == .structure && obj.house == world.playerHouse && obj.strength > 0 {
            totalX += obj.worldX
            totalY += obj.worldY
            count += 1
        }
    }

    if count == 0 { return nil }
    return (x: totalX / Double(count), y: totalY / Double(count))
}

/// Rally idle enemy units toward the player's base
func rallyEnemyUnits(world: GameWorld) {
    guard let playerBase = findPlayerBase(world: world) else { return }

    // Gather idle enemy combat units
    var idleUnits: [GameObject] = []
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        if obj.typeName.uppercased() == "HARV" || obj.typeName.uppercased() == "MCV" { continue }
        if obj.mission == .guard_ || obj.mission == .stop {
            idleUnits.append(obj)
        }
    }

    // Send groups of 3-5 idle units toward the player base
    let squadSize = min(5, max(3, idleUnits.count))
    if idleUnits.count >= squadSize {
        let squad = Array(idleUnits.prefix(squadSize))
        for unit in squad {
            // Add some randomness to the target so they don't all stack
            let offsetX = Double.random(in: -48...48)
            let offsetY = Double.random(in: -48...48)
            unit.moveTargetX = max(12, min(64 * 24 - 12, playerBase.x + offsetX))
            unit.moveTargetY = max(12, min(64 * 24 - 12, playerBase.y + offsetY))
            unit.mission = .move
            unit.movePath = []
        }
    }
}
