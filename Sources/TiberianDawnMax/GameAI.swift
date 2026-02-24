import Foundation

// MARK: - Enemy AI
// Enhanced AI with squad coordination, hunt behavior, and guard leash

var aiTickCounter: Int = 0

/// Maximum distance a guarding unit will chase before returning (in pixels)
let guardLeashRange: Double = 10.0 * 24.0  // 10 cells

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
            if obj.isArmed && obj.mission != .attack {
                if let enemy = findNearestEnemy(obj, range: aggroRange) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
            continue
        }

        // Skip harvesters and MCVs — they have their own behavior
        let upper = obj.typeName.uppercased()
        if upper == "HARV" {
            if obj.mission == .guard_ || obj.mission == .stop {
                obj.mission = .harvest
            }
            continue
        }
        if upper == "MCV" { continue }

        // Hunt mission — actively seek and destroy
        if obj.mission == .hunt {
            if obj.attackTarget == nil {
                // Find nearest enemy anywhere on map
                if let enemy = findNearestEnemy(obj, range: 64.0 * 24.0) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
            continue
        }

        // Idle enemy units (on guard/stop) — scan for nearby player units
        if obj.mission == .guard_ || obj.mission == .stop || obj.mission == .guardArea {
            if obj.isArmed {
                if let enemy = findNearestEnemy(obj, range: aggroRange) {
                    obj.attackTarget = enemy.id
                    obj.mission = .attack
                }
            }
        }
    }

    // Rally idle enemy units toward player base every ~20 seconds
    if aiTickCounter % 300 == 0 {
        rallyEnemyUnits(world: world)
    }

    // Periodically create autocreate teams (every ~45 seconds)
    if aiTickCounter % 675 == 0 && aiTickCounter > 300 {
        tryAutocreateTeam()
    }

    // Escalation: after 5 minutes, send all idle units to hunt
    if aiTickCounter == 15 * 60 * 5 {
        escalateAI(world: world)
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

/// Find the average position of enemy structures
func findEnemyBase(world: GameWorld) -> (x: Double, y: Double)? {
    var totalX = 0.0
    var totalY = 0.0
    var count = 0

    for obj in world.objects {
        if obj.kind == .structure && obj.house != world.playerHouse &&
           obj.house != .neutral && obj.strength > 0 {
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
        let upper = obj.typeName.uppercased()
        if upper == "HARV" || upper == "MCV" { continue }
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

/// Escalate AI: send all idle enemy units to hunt mode
func escalateAI(world: GameWorld) {
    for obj in world.objects {
        if obj.house == world.playerHouse || obj.house == .neutral { continue }
        if obj.kind == .structure { continue }
        if obj.strength <= 0 { continue }
        let upper = obj.typeName.uppercased()
        if upper == "HARV" || upper == "MCV" { continue }
        if obj.mission == .guard_ || obj.mission == .stop {
            obj.mission = .hunt
        }
    }
    print("AI: Escalation — all idle enemy units set to hunt")
}

/// Try to create an autocreate team from available team types
func tryAutocreateTeam() {
    let autocreateTypes = teamTypes.filter { $0.isAutocreate }
    guard !autocreateTypes.isEmpty else { return }

    // Pick a random autocreate team type
    let type = autocreateTypes[Int.random(in: 0..<autocreateTypes.count)]

    if let team = createAndRecruitTeam(type: type) {
        if team.memberCount > 0 {
            print("AI: Auto-created team '\(type.name)' with \(team.memberCount) members")
        } else {
            // No units to recruit — remove the empty team
            activeTeams.removeAll { $0 === team }
        }
    }
}
