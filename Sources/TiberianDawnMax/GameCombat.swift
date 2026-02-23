import Foundation

// MARK: - Weapon Data

struct WeaponInfo {
    let range: Double       // pixels
    let damage: Int
    let reloadTicks: Int
    let isAntiAir: Bool
}

let weaponData: [String: WeaponInfo] = [
    // Vehicles
    "MTNK": WeaponInfo(range: 144, damage: 30, reloadTicks: 20, isAntiAir: false),
    "LTNK": WeaponInfo(range: 120, damage: 20, reloadTicks: 15, isAntiAir: false),
    "HTNK": WeaponInfo(range: 168, damage: 40, reloadTicks: 25, isAntiAir: false),
    "FTNK": WeaponInfo(range: 96,  damage: 35, reloadTicks: 20, isAntiAir: false),
    "ARTY": WeaponInfo(range: 192, damage: 40, reloadTicks: 35, isAntiAir: false),
    "MSAM": WeaponInfo(range: 168, damage: 40, reloadTicks: 30, isAntiAir: true),
    "HMMV": WeaponInfo(range: 120, damage: 10, reloadTicks: 10, isAntiAir: false),
    "BGGY": WeaponInfo(range: 120, damage: 10, reloadTicks: 10, isAntiAir: false),
    "BIKE": WeaponInfo(range: 144, damage: 15, reloadTicks: 12, isAntiAir: false),
    "STNK": WeaponInfo(range: 120, damage: 25, reloadTicks: 18, isAntiAir: false),
    "APC":  WeaponInfo(range: 96,  damage: 10, reloadTicks: 10, isAntiAir: false),

    // Infantry
    "E1":   WeaponInfo(range: 96,  damage: 5,  reloadTicks: 8,  isAntiAir: false),
    "E2":   WeaponInfo(range: 96,  damage: 15, reloadTicks: 15, isAntiAir: false),
    "E3":   WeaponInfo(range: 168, damage: 25, reloadTicks: 30, isAntiAir: true),
    "E4":   WeaponInfo(range: 72,  damage: 20, reloadTicks: 12, isAntiAir: false),
    "E5":   WeaponInfo(range: 72,  damage: 20, reloadTicks: 12, isAntiAir: false),
    "RMBO": WeaponInfo(range: 120, damage: 50, reloadTicks: 10, isAntiAir: false),

    // Defense structures
    "GUN":  WeaponInfo(range: 144, damage: 30, reloadTicks: 15, isAntiAir: false),
    "GTWR": WeaponInfo(range: 144, damage: 30, reloadTicks: 15, isAntiAir: false),
    "OBLI": WeaponInfo(range: 168, damage: 100, reloadTicks: 40, isAntiAir: false),
    "ATWR": WeaponInfo(range: 120, damage: 20, reloadTicks: 12, isAntiAir: true),
    "SAM":  WeaponInfo(range: 168, damage: 30, reloadTicks: 25, isAntiAir: true),
]

// MARK: - Combat Functions

/// Check if two objects are enemies (different houses, neither neutral)
func isEnemy(_ a: GameObject, _ b: GameObject) -> Bool {
    if a.house == b.house { return false }
    if a.house == .neutral || b.house == .neutral { return false }
    return true
}

/// Find the nearest enemy within range of an object
func findNearestEnemy(_ obj: GameObject, range: Double) -> GameObject? {
    guard let world = gameWorld else { return nil }
    var nearest: GameObject? = nil
    var nearestDist = Double.infinity

    for other in world.objects {
        if other.id == obj.id { continue }
        if other.strength <= 0 { continue }
        if !isEnemy(obj, other) { continue }

        let dx = other.worldX - obj.worldX
        let dy = other.worldY - obj.worldY
        let dist = sqrt(dx * dx + dy * dy)
        if dist <= range && dist < nearestDist {
            nearest = other
            nearestDist = dist
        }
    }
    return nearest
}

/// Find a game object by ID
func findObjectById(_ id: Int) -> GameObject? {
    guard let world = gameWorld else { return nil }
    return world.objects.first { $0.id == id }
}

/// Apply damage to a target. Returns true if target dies.
@discardableResult
func applyDamage(_ target: GameObject, amount: Int) -> Bool {
    // Scale damage: strength is 0-256, damage values are tuned for this range
    target.strength -= amount
    if target.strength <= 0 {
        target.strength = 0
        return true
    }
    return false
}

/// Tick the attack mission for an object
func tickAttack(_ obj: GameObject) {
    guard gameWorld != nil else { return }

    // Decrement reload timer
    if obj.reloadTimer > 0 {
        obj.reloadTimer -= 1
    }

    // Find our target
    guard let targetId = obj.attackTarget,
          let target = findObjectById(targetId),
          target.strength > 0 else {
        // Target gone or dead — go back to guard
        obj.attackTarget = nil
        obj.mission = .guard_
        obj.moveTargetX = nil
        obj.moveTargetY = nil
        return
    }

    let weapon = weaponData[obj.typeName.uppercased()]
    let range = weapon?.range ?? 96.0

    let dx = target.worldX - obj.worldX
    let dy = target.worldY - obj.worldY
    let dist = sqrt(dx * dx + dy * dy)

    // Face the target
    if dist > 0.5 {
        obj.facing = directionToFacing(dx: dx, dy: dy)
    }

    if dist <= range {
        // In range — stop moving and fire if reloaded
        obj.moveTargetX = nil
        obj.moveTargetY = nil
        obj.movePath = []

        if obj.reloadTimer <= 0, let weapon = weapon {
            obj.reloadTimer = weapon.reloadTicks
            let died = applyDamage(target, amount: weapon.damage)
            if died {
                obj.attackTarget = nil
                obj.mission = .guard_
            }
        }
    } else {
        // Out of range — move closer
        if obj.kind != .structure {
            obj.moveTargetX = target.worldX
            obj.moveTargetY = target.worldY
            if obj.movePath.isEmpty {
                let path = findPath(
                    fromX: obj.cellX, fromY: obj.cellY,
                    toX: target.cellX, toY: target.cellY,
                    ignoring: obj
                )
                obj.movePath = path
            }
            tickMove(obj)
        }
    }
}

/// Auto-target enemies that enter guard range
func tickGuardScan(_ obj: GameObject) {
    let weapon = weaponData[obj.typeName.uppercased()]
    // Guard range is slightly larger than weapon range
    let guardRange = (weapon?.range ?? 96.0) * 1.5

    if let enemy = findNearestEnemy(obj, range: guardRange) {
        obj.attackTarget = enemy.id
        obj.mission = .attack
    }
}

/// Remove dead objects from the world
func removeDeadObjects() {
    guard let world = gameWorld else { return }
    world.objects.removeAll { $0.strength <= 0 }
}

/// Check if an object at a screen position is an enemy of the current player
func findEnemyAtWorldPos(worldX: Double, worldY: Double) -> GameObject? {
    guard let world = gameWorld else { return nil }
    let hitRadius = 14.0

    for obj in world.objects {
        if obj.strength <= 0 { continue }
        if obj.house == world.playerHouse { continue }
        if obj.house == .neutral { continue }

        let dx = obj.worldX - worldX
        let dy = obj.worldY - worldY
        let dist = sqrt(dx * dx + dy * dy)

        // For structures, use a larger hit area
        if obj.kind == .structure {
            let size = buildingSize(obj.typeName)
            let halfW = Double(size.w * 24) / 2.0
            let halfH = Double(size.h * 24) / 2.0
            if abs(dx) <= halfW && abs(dy) <= halfH {
                return obj
            }
        } else if dist < hitRadius {
            return obj
        }
    }
    return nil
}
