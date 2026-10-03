import Foundation

// MARK: - Crate Pickup System
// Collectible crates that spawn on the map with random bonus effects.

// MARK: - Crate Type

enum CrateType: CaseIterable {
    case money      // +2000 credits
    case heal       // Fully heal the collecting unit
    case speed      // +50% speed for 60 seconds (900 ticks)
    case firepower  // +50% damage for 60 seconds (900 ticks)
    case revealMap  // Reveal entire map
    case freeUnit   // Spawn a random unit nearby
    case explosion  // Trap! Damages nearby units

    /// Weighted random selection matching original C&C distribution
    static func randomWeighted() -> CrateType {
        let roll = rndInt(0..<100)
        switch roll {
        case 0..<30:  return .money       // 30%
        case 30..<50: return .heal        // 20%
        case 50..<60: return .speed       // 10%
        case 60..<70: return .firepower   // 10%
        case 70..<80: return .revealMap   // 10%
        case 80..<90: return .freeUnit    // 10%
        default:      return .explosion   // 10%
        }
    }
}

// MARK: - Crate Instance

struct GameCrate {
    let id: Int
    var cell: Int           // Map cell index (0-4095)
    var worldX: Double      // World pixel position
    var worldY: Double
    var crateType: CrateType
    var isCollected: Bool = false
}

// MARK: - Crate State (stored on GameWorld)

class CrateState {
    var crates: [GameCrate] = []
    var nextCrateId: Int = 0
    var nextSpawnTick: Int = 0       // Tick when next crate spawn is attempted
    var spawnedCount: Int = 0

    /// Maximum simultaneous crates on the map
    let maxCrates = 3

    /// Spawn interval range in ticks (3-5 minutes at 15 TPS)
    let minSpawnInterval = 2700      // ~3 minutes
    let maxSpawnInterval = 4500      // ~5 minutes

    func allocateId() -> Int {
        let id = nextCrateId
        nextCrateId += 1
        return id
    }
}

// MARK: - Crate Buff on GameObject

/// Temporary buff applied by a crate pickup. Stored on the collecting unit.
struct CrateBuff {
    var speedMultiplier: Double = 1.0
    var firepowerMultiplier: Double = 1.0
    var expirationTick: Int = 0
}

// MARK: - Crate Spawning

/// Tick the crate system: spawn new crates and check pickups.
/// Called from gameTick() in GameLoop.swift.
func tickCrates() {
    guard let world = session.world else { return }
    let tick = world.tickCount

    // Initialize spawn timer on first tick
    if world.crateState.nextSpawnTick == 0 {
        world.crateState.nextSpawnTick = tick + rndInt(world.crateState.minSpawnInterval...world.crateState.maxSpawnInterval)
    }

    // Try to spawn a crate
    if tick >= world.crateState.nextSpawnTick {
        spawnCrateIfPossible()
        world.crateState.nextSpawnTick = tick + rndInt(world.crateState.minSpawnInterval...world.crateState.maxSpawnInterval)
    }

    // Check for unit pickups
    checkCratePickups()

    // Tick active buffs (expire them)
    tickCrateBuffs()
}

/// Attempt to spawn a crate on a random passable land cell
private func spawnCrateIfPossible() {
    guard let world = session.world else { return }
    let state = world.crateState

    // Don't exceed max crates
    let activeCrates = state.crates.filter { !$0.isCollected }
    if activeCrates.count >= state.maxCrates { return }

    // Get map bounds for valid placement
    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    // Try up to 20 random cells to find a valid placement
    for _ in 0..<20 {
        let cellX = rndInt(bounds.x..<(bounds.x + bounds.width))
        let cellY = rndInt(bounds.y..<(bounds.y + bounds.height))
        let cell = cellY * 64 + cellX

        // Must be passable land
        guard cell >= 0 && cell < 4096 else { continue }
        guard landPassability[cell] else { continue }

        // Must not be occupied by a building or unit
        if world.occupancy[cell]?.isEmpty == false { continue }

        // Must not have tiberium
        if world.map.tiberiumCells.contains(cell) { continue }

        // Must not already have a crate
        if state.crates.contains(where: { !$0.isCollected && $0.cell == cell }) { continue }

        // Place the crate
        let crateType = CrateType.randomWeighted()
        let wx = Double(cellX * 24) + 12.0
        let wy = Double(cellY * 24) + 12.0
        let crate = GameCrate(
            id: state.allocateId(),
            cell: cell,
            worldX: wx,
            worldY: wy,
            crateType: crateType
        )
        state.crates.append(crate)
        state.spawnedCount += 1
        print("Crate: Spawned \(crateType) crate at cell (\(cellX),\(cellY))")
        return
    }
}

// MARK: - Crate Pickup

/// Check if any mobile unit is on a cell with a crate
private func checkCratePickups() {
    guard let world = session.world else { return }
    let state = world.crateState

    for i in state.crates.indices {
        guard !state.crates[i].isCollected else { continue }
        let crateCell = state.crates[i].cell

        // Find a unit on this cell
        for obj in world.objects {
            guard obj.strength > 0 else { continue }
            guard obj.kind == .unit || obj.kind == .infantry else { continue }
            guard obj.cell == crateCell else { continue }

            // Pickup!
            state.crates[i].isCollected = true
            applyCrateEffect(state.crates[i], collector: obj)
            break
        }
    }

    // Clean up collected crates
    state.crates.removeAll { $0.isCollected }
}

/// Apply the crate's bonus effect
private func applyCrateEffect(_ crate: GameCrate, collector: GameObject) {
    guard let world = session.world else { return }
    let isPlayer = collector.house == world.playerHouse

    switch crate.crateType {
    case .money:
        let bonus = 2000
        if isPlayer {
            session.sidebarCredits += bonus
        } else {
            let hs = getHouseState(collector.house)
            hs.credits += bonus
        }
        audioManager.play(.button, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) picked up money crate (+$\(bonus))")

    case .heal:
        collector.strength = collector.maxStrength
        audioManager.play(.button, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) picked up heal crate")

    case .speed:
        collector.crateBuff.speedMultiplier = 1.5
        collector.crateBuff.expirationTick = max(collector.crateBuff.expirationTick, world.tickCount + 900)
        audioManager.play(.button, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) picked up speed crate")

    case .firepower:
        collector.crateBuff.firepowerMultiplier = 1.5
        collector.crateBuff.expirationTick = max(collector.crateBuff.expirationTick, world.tickCount + 900)
        audioManager.play(.button, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) picked up firepower crate")

    case .revealMap:
        // Lifts the shroud. With fog regrowth the revealed ground is fogged
        // until seen; without it (classic) revealed means visible.
        let revealed: FogLevel = session.rules.fogRegrowth ? .explored : .visible
        for i in 0..<4096 {
            if world.map.fogState[i] == .unexplored {
                world.map.fogState[i] = revealed
            }
        }
        if isPlayer {
            session.speakEVA(.reinforcements)
        }
        audioManager.play(.radarOn, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) picked up reveal map crate")

    case .freeUnit:
        spawnFreeUnit(near: crate, for: collector)
        if isPlayer {
            session.speakEVA(.unitReady)
        }
        audioManager.play(.button, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) picked up free unit crate")

    case .explosion:
        // Damage all units within 2-cell radius (48 pixels)
        let damageRadius = 48.0
        let damage = 200
        for obj in world.objects {
            guard obj.strength > 0 else { continue }
            let dx = obj.worldX - crate.worldX
            let dy = obj.worldY - crate.worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist <= damageRadius {
                obj.applyDamage(amount: damage, warhead: .he)
            }
        }
        spawnAnimation(.fball1, worldX: crate.worldX, worldY: crate.worldY)
        audioManager.play(.xplobig4, worldX: crate.worldX, worldY: crate.worldY)
        print("Crate: \(collector.typeName) triggered explosion crate!")
    }
}

/// Spawn a random free unit near the crate location
private func spawnFreeUnit(near crate: GameCrate, for collector: GameObject) {
    guard let world = session.world else { return }

    // Possible free unit types
    let unitTypes = ["E1", "E3", "JEEP", "MTNK", "APC"]
    let typeName = unitTypes.rndElement()!

    // Find a passable cell adjacent to the crate
    let crateX = crate.cell % 64
    let crateY = crate.cell / 64
    let offsets = [(0, -1), (1, 0), (0, 1), (-1, 0), (1, -1), (1, 1), (-1, 1), (-1, -1)]

    var spawnCellX = crateX
    var spawnCellY = crateY
    for (dx, dy) in offsets {
        let nx = crateX + dx
        let ny = crateY + dy
        if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 && landPassability[ny * 64 + nx] {
            spawnCellX = nx
            spawnCellY = ny
            break
        }
    }

    let wx = Double(spawnCellX * 24) + 12.0
    let wy = Double(spawnCellY * 24) + 12.0

    let kind: ObjectKind = (typeName == "E1" || typeName == "E3") ? .infantry : .unit
    let speed: Double = kind == .infantry ? 1.0 : 2.0

    let obj = GameObject(
        id: world.allocateId(),
        typeName: typeName,
        house: collector.house,
        kind: kind,
        worldX: wx,
        worldY: wy,
        facing: 0,
        strength: 100,  // Will be overridden by cacheTypeData maxStrength
        mission: .guard_,
        speed: speed
    )
    // Set strength to max after type data is cached
    obj.strength = obj.maxStrength
    world.addObject(obj)
}

// MARK: - Crate Buff Tick

/// Expire crate buffs that have timed out
private func tickCrateBuffs() {
    guard let world = session.world else { return }
    let tick = world.tickCount

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        if obj.crateBuff.expirationTick > 0 && tick >= obj.crateBuff.expirationTick {
            obj.crateBuff.speedMultiplier = 1.0
            obj.crateBuff.firepowerMultiplier = 1.0
            obj.crateBuff.expirationTick = 0
        }
    }
}
