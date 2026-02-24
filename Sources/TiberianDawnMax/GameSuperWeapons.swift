import Foundation

// MARK: - Special Weapons System
// Ported from Vanilla Conquer super.h/super.cpp, house.cpp

// MARK: - Special Weapon Types

enum SpecialWeaponType: Int, CaseIterable {
    case ionCannon = 0      // GDI — Advanced Comm Center (EYE)
    case airStrike = 1      // Both — A-10 bombing run
    case nuclearStrike = 2  // Nod — Temple of Nod
}

// MARK: - Charge Times (in game ticks at 15 FPS)

/// Ion Cannon: 10 minutes = 10 * 900 = 9000 ticks
let ionCannonChargeTime: Int = 9000

/// Airstrike: 8 minutes = 8 * 900 = 7200 ticks
let airStrikeChargeTime: Int = 7200

/// Nuclear Strike: 14 minutes = 14 * 900 = 12600 ticks
let nuclearStrikeChargeTime: Int = 12600

// MARK: - Super Weapon Instance

class SuperWeapon {
    let type: SpecialWeaponType
    let chargeTime: Int          // Total ticks to fully charge
    var isPresent: Bool = false  // Weapon is available
    var isReady: Bool = false    // Fully charged
    var isOneTime: Bool = false  // One-time use (from crate, etc.)
    var isSuspended: Bool = false // Charging paused (low power)
    var chargeRemaining: Int = 0 // Ticks remaining until charged
    var suspendedTime: Int = 0   // Time stored when suspended

    init(type: SpecialWeaponType, chargeTime: Int) {
        self.type = type
        self.chargeTime = chargeTime
    }

    /// Charge fraction (0.0 = empty, 1.0 = fully charged)
    var chargeFraction: Double {
        guard chargeTime > 0 else { return 1.0 }
        if isReady { return 1.0 }
        let elapsed = chargeTime - chargeRemaining
        return Double(elapsed) / Double(chargeTime)
    }

    /// Enable the weapon and start charging
    func enable(oneTime: Bool = false) {
        isPresent = true
        isOneTime = oneTime
        recharge()
    }

    /// Start/restart charging
    func recharge() {
        isReady = false
        isSuspended = false
        chargeRemaining = chargeTime
    }

    /// Suspend charging (low power)
    func suspend() {
        if !isSuspended && !isReady {
            isSuspended = true
            suspendedTime = chargeRemaining
        }
    }

    /// Resume charging
    func resume() {
        if isSuspended {
            isSuspended = false
            chargeRemaining = suspendedTime
        }
    }

    /// Mark as fired — recharge or remove
    func discharged() {
        isReady = false
        if isOneTime {
            remove()
        } else {
            recharge()
        }
    }

    /// Remove the weapon entirely
    func remove() {
        isPresent = false
        isReady = false
        isSuspended = false
        chargeRemaining = 0
    }

    /// Instantly charge the weapon
    func forceCharge() {
        chargeRemaining = 0
        isReady = true
        isSuspended = false
    }

    /// Tick the charge timer
    func tick() {
        guard isPresent && !isReady && !isSuspended else { return }
        if chargeRemaining > 0 {
            chargeRemaining -= 1
        }
        if chargeRemaining <= 0 {
            isReady = true
            print("SuperWeapon: \(type) fully charged!")
        }
    }
}

// MARK: - Per-House Super Weapons

/// Super weapons owned by the player house
// session.playerIonCannon, session.playerAirStrike, session.playerNukeStrike -- now in session

/// Get the super weapon instance by type for the player
func playerSuperWeapon(_ type: SpecialWeaponType) -> SuperWeapon {
    switch type {
    case .ionCannon:     return session.playerIonCannon
    case .airStrike:     return session.playerAirStrike
    case .nuclearStrike: return session.playerNukeStrike
    }
}

/// Reset all super weapons (for new game)
func resetSuperWeapons() {
    session.playerIonCannon = SuperWeapon(type: .ionCannon, chargeTime: ionCannonChargeTime)
    session.playerAirStrike = SuperWeapon(type: .airStrike, chargeTime: airStrikeChargeTime)
    session.playerNukeStrike = SuperWeapon(type: .nuclearStrike, chargeTime: nuclearStrikeChargeTime)
}

// MARK: - Super Weapon Availability Check

/// Check if player has the required buildings for each super weapon
func updateSuperWeaponAvailability() {
    guard let world = session.world else { return }

    // Ion Cannon requires Advanced Comm Center (EYE)
    let hasEye = world.hasBuilding(type: "EYE", house: world.playerHouse)
    if hasEye && !session.playerIonCannon.isPresent {
        session.playerIonCannon.enable()
        print("SuperWeapon: Ion Cannon available — charging")
    } else if !hasEye && session.playerIonCannon.isPresent && !session.playerIonCannon.isOneTime {
        session.playerIonCannon.remove()
        print("SuperWeapon: Ion Cannon lost — building destroyed")
    }

    // Nuclear Strike requires Temple of Nod
    let hasTemple = world.hasBuilding(type: "TMPL", house: world.playerHouse)
    if hasTemple && !session.playerNukeStrike.isPresent {
        session.playerNukeStrike.enable()
        print("SuperWeapon: Nuclear Strike available — charging")
    } else if !hasTemple && session.playerNukeStrike.isPresent && !session.playerNukeStrike.isOneTime {
        session.playerNukeStrike.remove()
        print("SuperWeapon: Nuclear Strike lost — building destroyed")
    }

    // Airstrike: check if enabled by trigger (handled elsewhere)
    // Power suspension
    let houseState = getHouseState(world.playerHouse)
    if !houseState.hasPower {
        if session.playerIonCannon.isPresent && !session.playerIonCannon.isSuspended {
            session.playerIonCannon.suspend()
        }
        if session.playerNukeStrike.isPresent && !session.playerNukeStrike.isSuspended {
            session.playerNukeStrike.suspend()
        }
    } else {
        if session.playerIonCannon.isSuspended { session.playerIonCannon.resume() }
        if session.playerNukeStrike.isSuspended { session.playerNukeStrike.resume() }
    }
}

// MARK: - Super Weapon Tick

/// Tick all super weapons each game tick
func tickSuperWeapons() {
    guard let world = session.world else { return }

    // Check availability every 30 ticks
    if world.tickCount % 30 == 0 {
        updateSuperWeaponAvailability()
    }

    // Tick charge timers
    session.playerIonCannon.tick()
    session.playerAirStrike.tick()
    session.playerNukeStrike.tick()
}

// MARK: - Super Weapon Deployment

/// Current super weapon targeting mode
// session.superWeaponTargeting -- now in session

/// Start targeting mode for a super weapon
func startSuperWeaponTargeting(_ type: SpecialWeaponType) {
    let weapon = playerSuperWeapon(type)
    guard weapon.isPresent && weapon.isReady else {
        print("SuperWeapon: \(type) not ready")
        return
    }
    session.superWeaponTargeting = type
    print("SuperWeapon: Targeting mode for \(type)")
}

/// Deploy the super weapon at a world position
func deploySuperWeapon(_ type: SpecialWeaponType, worldX: Double, worldY: Double) {
    let weapon = playerSuperWeapon(type)
    guard weapon.isPresent && weapon.isReady else { return }

    switch type {
    case .ionCannon:
        deployIonCannon(worldX: worldX, worldY: worldY)
    case .airStrike:
        deployAirStrike(worldX: worldX, worldY: worldY)
    case .nuclearStrike:
        deployNuclearStrike(worldX: worldX, worldY: worldY)
    }

    weapon.discharged()
    session.superWeaponTargeting = nil
}

// MARK: - Ion Cannon

/// Deploy ion cannon beam at target location
/// VC: 600 damage, WARHEAD_PB (particle beam), single cell
func deployIonCannon(worldX: Double, worldY: Double) {
    guard let world = session.world else { return }

    print("SuperWeapon: ION CANNON deployed at (\(Int(worldX)), \(Int(worldY)))")

    // Spawn ion cannon animation
    spawnAnimation(.ionCannon, worldX: worldX, worldY: worldY)

    // Apply 600 damage to all objects in the target cell
    let targetCellX = Int(worldX) / 24
    let targetCellY = Int(worldY) / 24

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        let objCellX = obj.cellX
        let objCellY = obj.cellY

        // Central cell: full damage
        if objCellX == targetCellX && objCellY == targetCellY {
            let died = obj.applyDamage(amount: 600, warhead: .pb)
            if died {
                obj.spawnDeathEffects()
            }
        }
        // Adjacent cells: half damage
        else if abs(objCellX - targetCellX) <= 1 && abs(objCellY - targetCellY) <= 1 {
            let died = obj.applyDamage(amount: 300, warhead: .pb)
            if died {
                obj.spawnDeathEffects()
            }
        }
    }
}

// MARK: - Nuclear Strike

/// Deploy nuclear strike at target location
/// VC Campaign: 1000 damage center, 4 cell radius, WARHEAD_FIRE
/// VC Multiplayer: 200 damage center, 3 cell radius
func deployNuclearStrike(worldX: Double, worldY: Double) {
    guard let world = session.world else { return }

    print("SuperWeapon: NUCLEAR STRIKE deployed at (\(Int(worldX)), \(Int(worldY)))")

    // Spawn nuclear explosion animation
    spawnAnimation(.atomBlast, worldX: worldX, worldY: worldY)

    // Also spawn secondary explosions
    for _ in 0..<4 {
        let ox = Double.random(in: -36...36)
        let oy = Double.random(in: -36...36)
        spawnAnimation(.fball1, worldX: worldX + ox, worldY: worldY + oy)
    }

    // Apply damage in radius (campaign values)
    let centerDamage = 1000
    let radius = 4  // cells
    let targetCellX = Int(worldX) / 24
    let targetCellY = Int(worldY) / 24

    for obj in world.objects {
        guard obj.strength > 0 else { continue }

        let dx = obj.cellX - targetCellX
        let dy = obj.cellY - targetCellY
        let cellDist = max(abs(dx), abs(dy))  // Chebyshev distance in cells

        if cellDist <= radius {
            // Damage falls off with distance
            let damage: Int
            if cellDist == 0 {
                damage = centerDamage
            } else {
                damage = centerDamage / (cellDist + 1)
            }

            let died = obj.applyDamage(amount: damage, warhead: .fire)
            if died {
                obj.spawnDeathEffects()
            }
        }
    }

    // Spawn scorch marks across the blast area
    for dy in -2...2 {
        for dx in -2...2 {
            let cx = targetCellX + dx
            let cy = targetCellY + dy
            if cx >= 0 && cx < 64 && cy >= 0 && cy < 64 {
                let scorch = SmudgeType.allCases.filter { $0.rawValue.hasPrefix("scorch") }
                if !scorch.isEmpty {
                    let chosen = scorch[Int.random(in: 0..<scorch.count)]
                    let smudgeCell = cy * 64 + cx
                    session.world?.map.smudges.append(Smudge(type: chosen, cell: smudgeCell))
                }
            }
        }
    }
}

// MARK: - Airstrike

/// Deploy airstrike at target location
/// VC: 1-3 A-10s fly to target and attack with napalm
func deployAirStrike(worldX: Double, worldY: Double) {
    guard let world = session.world else { return }

    print("SuperWeapon: AIRSTRIKE deployed at (\(Int(worldX)), \(Int(worldY)))")

    // Determine number of A-10s (1-3 based on scenario difficulty)
    let numPlanes = min(3, max(1, 2))  // Default 2 planes

    // Spawn A-10s from map edge
    let bounds = world.mapBounds
    let spawnY = bounds.map { Double($0.y * 24) } ?? 0.0

    for i in 0..<numPlanes {
        let offset = Double(i - numPlanes / 2) * 36.0
        let a10 = createAircraft(
            world: world,
            type: .a10,
            house: world.playerHouse,
            worldX: worldX + offset,
            worldY: spawnY,
            facing: 128,  // Face south toward target
            mission: .attack
        )
        a10.altitude = flightLevel

        // Set the target: find nearest enemy object to the clicked position
        var bestTarget: GameObject? = nil
        var bestDist = Double.infinity
        for obj in world.objects {
            guard obj.strength > 0 else { continue }
            guard obj.house != world.playerHouse && obj.house != .neutral else { continue }
            let dx = obj.worldX - worldX
            let dy = obj.worldY - worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestTarget = obj
            }
        }

        if let target = bestTarget {
            a10.attackTarget = target.id
            a10.moveTargetX = target.worldX
            a10.moveTargetY = target.worldY
        } else {
            // No enemy target — just fly to the point and bomb
            a10.moveTargetX = worldX + offset
            a10.moveTargetY = worldY
            a10.mission = .hunt
        }

        world.addObject(a10)
    }
}

// MARK: - AI Super Weapon Usage

/// AI fires super weapons when ready (called from tickAI)
func tickAISuperWeapons() {
    guard let world = session.world else { return }

    // Process for each AI house
    for (house, state) in session.houseStates {
        guard !state.isHuman else { continue }

        // AI Ion Cannon
        let hasEye = world.hasBuilding(type: "EYE", house: house)
        if hasEye {
            // Simple AI: fire at player base when ready
            // (Using a simplified timer approach for AI)
            if world.tickCount % ionCannonChargeTime == 0 && world.tickCount > 0 {
                if let target = findBestAITarget(house: house) {
                    deployAIIonCannon(worldX: target.worldX, worldY: target.worldY, house: house)
                }
            }
        }

        // AI Nuclear Strike
        let hasTemple = world.hasBuilding(type: "TMPL", house: house)
        if hasTemple {
            if world.tickCount % nuclearStrikeChargeTime == 0 && world.tickCount > 0 {
                if let target = findBestAITarget(house: house) {
                    deployAINukeStrike(worldX: target.worldX, worldY: target.worldY, house: house)
                }
            }
        }
    }
}

/// Find best target for AI super weapons (highest value enemy structure)
func findBestAITarget(house: House) -> GameObject? {
    guard let world = session.world else { return nil }
    var bestTarget: GameObject? = nil
    var bestValue = 0

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard obj.house != house && obj.house != .neutral else { continue }

        let value: Int
        if obj.kind == .structure {
            value = obj.cost + 500  // Structures are high priority
        } else {
            value = obj.cost
        }

        if value > bestValue {
            bestValue = value
            bestTarget = obj
        }
    }
    return bestTarget
}

/// AI deploys ion cannon (same damage, different house)
func deployAIIonCannon(worldX: Double, worldY: Double, house: House) {
    guard let world = session.world else { return }
    print("AI SuperWeapon: Ion Cannon fired by \(house.rawValue) at (\(Int(worldX)), \(Int(worldY)))")

    spawnAnimation(.ionCannon, worldX: worldX, worldY: worldY)

    let targetCellX = Int(worldX) / 24
    let targetCellY = Int(worldY) / 24

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        let dx = abs(obj.cellX - targetCellX)
        let dy = abs(obj.cellY - targetCellY)

        if dx == 0 && dy == 0 {
            let died = obj.applyDamage(amount: 600, warhead: .pb)
            if died { obj.spawnDeathEffects() }
        } else if dx <= 1 && dy <= 1 {
            let died = obj.applyDamage(amount: 300, warhead: .pb)
            if died { obj.spawnDeathEffects() }
        }
    }
}

/// AI deploys nuclear strike
func deployAINukeStrike(worldX: Double, worldY: Double, house: House) {
    guard let world = session.world else { return }
    print("AI SuperWeapon: Nuclear Strike fired by \(house.rawValue) at (\(Int(worldX)), \(Int(worldY)))")

    spawnAnimation(.atomBlast, worldX: worldX, worldY: worldY)

    let centerDamage = 1000
    let radius = 4
    let targetCellX = Int(worldX) / 24
    let targetCellY = Int(worldY) / 24

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        let dx = abs(obj.cellX - targetCellX)
        let dy = abs(obj.cellY - targetCellY)
        let cellDist = max(dx, dy)

        if cellDist <= radius {
            let damage = cellDist == 0 ? centerDamage : centerDamage / (cellDist + 1)
            let died = obj.applyDamage(amount: damage, warhead: .fire)
            if died { obj.spawnDeathEffects() }
        }
    }
}
