import Foundation

// MARK: - Player Commands
// Every order a player gives, as data. Input turns clicks and keys into a
// PlayerCommand and calls `issue`; the simulation applies queued commands at
// the start of the next tick. So every change to the world happens inside
// gameTick, where randomness is the seeded sim RNG: a seed plus the command
// log replays a game exactly, and AI, replays or network play can drive the
// sim through the same door as the mouse.
//
// Commands carry object ids, not references, and are re-validated when they
// apply: a unit may have died, or a factory finished, since the click. Each
// is queued with the house that gave it (EventClass::ID, EVENT.H) and only
// moves that house's objects — groundwork for more than one player
// (docs/MULTIPLAYER.md).

package struct MapPoint: Codable, Equatable {
    package var x: Double
    package var y: Double

    package init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

package enum PlayerCommand: Codable, Equatable {
    /// Move in formation. `queued` (shift) appends a waypoint to units already
    /// moving; `attackMove` engages enemies met on the way.
    case move(units: [Int], to: MapPoint, queued: Bool, attackMove: Bool)
    /// Attack, or for a commando sabotage / an engineer capture a building.
    case attack(units: [Int], target: Int)
    /// S: drop everything and stand.
    case stop(units: [Int])
    /// G: stand ground, engaging what comes into range.
    case guardPosition(units: [Int])
    /// X: each unit steps to a random free cell nearby.
    case scatter(units: [Int])
    case patrol(units: [Int], waypoints: [MapPoint])
    /// Infantry board a transport.
    case enter(units: [Int], transport: Int)
    /// Harvesters go unload at this refinery.
    case dock(harvesters: [Int], refinery: Int)
    /// Vehicles drive into this repair bay.
    case repairAt(units: [Int], bay: Int)
    case unload(transport: Int)
    case deploy(mcv: Int)
    case setRallyPoint(buildings: [Int], at: MapPoint)
    case toggleRepair(building: Int)
    case sell(building: Int)
    /// Start building; the full cost is paid up front.
    case startProduction(structure: Bool, type: String, cost: Int, buildTicks: Int)
    case holdProduction(structure: Bool)
    case resumeProduction(structure: Bool)
    /// Cancel and refund in full.
    case cancelProduction(structure: Bool)
    /// Put the finished structure down with its top-left at this cell.
    case placeStructure(type: String, cellX: Int, cellY: Int)
    case fireSuperWeapon(SpecialWeaponType, at: MapPoint)
}

extension SpecialWeaponType: Codable {}
extension House: Codable {}

/// A command and the house that gave it, waiting for the next tick.
package struct QueuedCommand: Equatable {
    package let house: House
    package let command: PlayerCommand

    package init(house: House, command: PlayerCommand) {
        self.house = house
        self.command = command
    }
}

/// A command, the house that gave it, and the tick it took effect on.
package struct LoggedCommand: Codable, Equatable {
    package let tick: Int
    package let house: House
    package let command: PlayerCommand

    package init(tick: Int, house: House, command: PlayerCommand) {
        self.tick = tick
        self.house = house
        self.command = command
    }
}

/// Queue a command for the next tick, from `house` — the player's by default.
package func issue(_ command: PlayerCommand, as house: House? = nil) {
    guard let world = session.world else { return }
    world.pendingCommands.append(QueuedCommand(house: house ?? world.playerHouse, command: command))
}

/// Apply everything queued since the last tick, in order, and log it with the
/// tick it took effect on. Called first thing in gameTick.
func applyPendingCommands(world: GameWorld) {
    guard !world.pendingCommands.isEmpty else { return }
    let commands = world.pendingCommands
    world.pendingCommands = []
    for queued in commands {
        world.commandLog.append(LoggedCommand(tick: world.tickCount, house: queued.house, command: queued.command))
        apply(queued.command, from: queued.house, world: world)
    }
}

private func apply(_ command: PlayerCommand, from house: House, world: GameWorld) {
    // Only the issuing house's own live objects take orders (EventClass::
    // Execute acts as Houses.Raw_Ptr(ID); its SELL checks the owner).
    func own(_ ids: [Int]) -> [GameObject] {
        ids.compactMap { world.findObject(id: $0) }
            .filter { $0.house == house && $0.strength > 0 }
    }
    func ownOne(_ id: Int) -> GameObject? { own([id]).first }
    // Production, placement and super weapons exist only for the player's
    // house so far (session's build queues and credits; docs/MULTIPLAYER.md
    // step 3), so another house's orders for them are dropped.
    let isPlayer = house == world.playerHouse

    switch command {
    case .move(let ids, let to, let queued, let attackMove):
        applyGroupMove(own(ids).filter { $0.kind != .structure }, to: to,
                       queued: queued, attackMove: attackMove)

    case .attack(let ids, let targetId):
        guard let enemy = world.findObject(id: targetId), enemy.strength > 0 else { return }
        for obj in own(ids) where obj.kind != .structure {
            obj.attackTarget = enemy.id
            obj.movePath = []
            obj.isAttackMoving = false
            obj.moveWaypoints = []
            obj.groupMoveSpeed = nil
            // Special missions when targeting a building
            if enemy.kind == .structure {
                if obj.isCommando {
                    // Commando targeting a building → sabotage mission (C4)
                    obj.mission = .sabotage
                } else if obj.kind == .infantry,
                          let data = getInfantryTypeDataByName(obj.typeName.uppercased()),
                          data.canCapture {
                    // Engineer targeting an enemy building → capture mission
                    obj.mission = .capture
                } else {
                    obj.mission = .attack
                }
            } else {
                obj.mission = .attack
            }
        }

    case .stop(let ids):
        for obj in own(ids) where obj.kind != .structure {
            obj.mission = .guard_
            obj.moveTargetX = nil
            obj.moveTargetY = nil
            obj.attackTarget = nil
            obj.movePath = []
            obj.isAttackMoving = false
            obj.moveWaypoints = []
        }

    case .guardPosition(let ids):
        for obj in own(ids) where obj.kind != .structure {
            obj.mission = .guard_
            obj.moveTargetX = nil
            obj.moveTargetY = nil
            obj.movePath = []
            obj.isAttackMoving = false
            obj.moveWaypoints = []
        }

    case .scatter(let ids):
        for obj in own(ids) where obj.kind != .structure {
            // Pick a random passable cell within 3 cells; up to 8 tries.
            let scatterDist = 3
            var found = false
            for _ in 0..<8 {
                let nx = max(0, min(63, obj.cellX + rndInt(-scatterDist...scatterDist)))
                let ny = max(0, min(63, obj.cellY + rndInt(-scatterDist...scatterDist)))
                if nx == obj.cellX && ny == obj.cellY { continue }
                if isCellPassable(cellX: nx, cellY: ny, ignoring: obj, speedType: obj.cachedSpeedType) {
                    obj.moveTargetX = Double(nx * 24) + 12.0
                    obj.moveTargetY = Double(ny * 24) + 12.0
                    obj.mission = .move
                    obj.movePath = []
                    obj.attackTarget = nil
                    obj.isAttackMoving = false
                    obj.moveWaypoints = []
                    found = true
                    break
                }
            }
            if !found { obj.mission = .guard_ }  // nowhere to go: stop in place
        }

    case .patrol(let ids, let waypoints):
        guard !waypoints.isEmpty else { return }
        for obj in own(ids) where obj.kind != .structure {
            obj.patrolWaypoints = waypoints.map { (x: $0.x, y: $0.y) }
            obj.patrolIndex = 0
            obj.mission = .patrol
            obj.moveTargetX = nil
            obj.moveTargetY = nil
            obj.movePath = []
            obj.attackTarget = nil
            obj.isAttackMoving = false
            obj.moveWaypoints = []
        }

    case .enter(let ids, let transportId):
        // Classic ACTION_ENTER. Boarding drives the civ-evac missions: a
        // civilian entering a transport aircraft flies it off the map
        // (AIRCRAFT.CPP:2530-2542).
        guard let transport = ownOne(transportId), transport.isTransporter else { return }
        var slots = transport.maxPassengers - transport.passengerCount
        for obj in own(ids) where obj.kind == .infantry {
            guard slots > 0 else { break }
            obj.enterTransportID = transport.id
            obj.mission = .enter
            obj.attackTarget = nil
            obj.isAttackMoving = false
            obj.moveWaypoints = []
            obj.movePath = []
            obj.moveTargetX = nil
            obj.moveTargetY = nil
            slots -= 1
        }

    case .dock(let ids, let refineryId):
        guard let refinery = ownOne(refineryId) else { return }
        for obj in own(ids) where obj.isHarvester {
            obj.preferredRefineryID = refinery.id
            obj.harvesterForceDock = true
            obj.mission = .harvest
            obj.missionStatus = dockApproaching
            obj.isTethered = false
            obj.dockTimer = 0
            obj.attackTarget = nil
            obj.isAttackMoving = false
            obj.moveWaypoints = []
            obj.movePath = []
            obj.moveTargetX = nil
            obj.moveTargetY = nil
        }

    case .repairAt(let ids, let bayId):
        guard let bay = ownOne(bayId) else { return }
        for obj in own(ids) where obj.kind == .unit && !obj.isAircraft {
            obj.repairBuildingID = bay.id
            obj.mission = .enter
            obj.attackTarget = nil
            obj.isAttackMoving = false
            obj.moveWaypoints = []
            obj.movePath = []
            obj.moveTargetX = nil
            obj.moveTargetY = nil
        }

    case .unload(let transportId):
        // Classic ACTION_SELF on a loaded transport. A Chinook lands first —
        // see the .unload aircraft case in gameTick.
        guard let transport = ownOne(transportId), transport.hasCargo,
              transport.mission != .unload else { return }
        transport.mission = .unload
        transport.moveTargetX = nil
        transport.moveTargetY = nil
        transport.movePath = []

    case .deploy(let mcvId):
        guard let mcv = ownOne(mcvId), mcv.isMCV, mcv.mission != .unload else { return }
        mcv.mission = .unload

    case .setRallyPoint(let ids, let at):
        for obj in own(ids) where obj.kind == .structure {
            obj.rallyPointX = at.x
            obj.rallyPointY = at.y
        }

    case .toggleRepair(let id):
        guard let obj = ownOne(id), obj.kind == .structure else { return }
        if obj.isRepairing {
            obj.isRepairing = false
            obj.mission = .guard_
        } else if obj.strength < obj.maxStrength {
            obj.isRepairing = true
            obj.mission = .repair
        }

    case .sell(let id):
        guard let obj = ownOne(id), obj.kind == .structure else { return }
        obj.mission = .selling

    case .startProduction(let structure, let type, let cost, let buildTicks):
        guard isPlayer else { return }
        let queue = structure ? session.structureBuildQueue : session.unitBuildQueue
        guard queue.item == nil, session.sidebarCredits >= cost else { return }
        queue.start(typeName: type, cost: cost, buildTime: buildTicks)
        session.sidebarCredits -= cost

    case .holdProduction(let structure):
        guard isPlayer else { return }
        let queue = structure ? session.structureBuildQueue : session.unitBuildQueue
        guard queue.item != nil, !queue.isComplete else { return }
        queue.isOnHold = true

    case .resumeProduction(let structure):
        guard isPlayer else { return }
        let queue = structure ? session.structureBuildQueue : session.unitBuildQueue
        queue.isOnHold = false

    case .cancelProduction(let structure):
        guard isPlayer else { return }
        let queue = structure ? session.structureBuildQueue : session.unitBuildQueue
        guard queue.item != nil else { return }
        session.sidebarCredits += queue.cancel()  // full cost was paid up front
        if structure {
            session.isPlacingStructure = false
            session.placementType = nil
        }

    case .placeStructure(let type, let cellX, let cellY):
        guard isPlayer else { return }
        placeStructure(type: type, cellX: cellX, cellY: cellY)

    case .fireSuperWeapon(let type, let at):
        guard isPlayer else { return }
        deploySuperWeapon(type, worldX: at.x, worldY: at.y)
    }
}

/// Move a group in formation: a grid of targets 1.5 cells apart around the
/// point, nudged onto passable ground, at the slowest member's speed.
private func applyGroupMove(_ movable: [GameObject], to point: MapPoint, queued: Bool, attackMove: Bool) {
    let count = movable.count
    guard count > 0 else { return }

    // Squad speed matching: compute minimum speed for mixed groups
    let groupSpeed: Double?
    if count >= 2 {
        let speeds = movable.map { $0.effectiveSpeed }
        let minSpeed = speeds.min() ?? 0
        let maxSpeed = speeds.max() ?? 0
        groupSpeed = (minSpeed < maxSpeed) ? minSpeed : nil
    } else {
        groupSpeed = nil
    }

    let cols = max(1, Int(ceil(sqrt(Double(count)))))
    let spacing = 36.0  // 1.5 cells apart to avoid stacking

    for (i, obj) in movable.enumerated() {
        let row = i / cols
        let col = i % cols
        let offsetX = (Double(col) - Double(cols - 1) / 2.0) * spacing
        let offsetY = (Double(row) - Double(max(0, (count - 1) / cols)) / 2.0) * spacing
        // Small jitter (±6px) so units don't converge to exact grid points
        let jitterX = rndDouble(-6.0...6.0)
        let jitterY = rndDouble(-6.0...6.0)

        var tgtX = max(12, min(64 * 24 - 12, point.x + offsetX + jitterX))
        var tgtY = max(12, min(64 * 24 - 12, point.y + offsetY + jitterY))

        // Validate target cell is passable for this unit's speed type
        let tgtCellX = Int(tgtX) / 24
        let tgtCellY = Int(tgtY) / 24
        if !isCellPassable(cellX: tgtCellX, cellY: tgtCellY, ignoring: obj, speedType: obj.cachedSpeedType) {
            // Find nearest passable cell
            var bestX = tgtCellX, bestY = tgtCellY
            var bestDist = Double.infinity
            let passMap = passabilityMap(for: obj.cachedSpeedType)
            for dy in -3...3 {
                for dx in -3...3 {
                    let nx = tgtCellX + dx
                    let ny = tgtCellY + dy
                    if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 && passMap[ny * 64 + nx] {
                        let dist = sqrt(Double(dx * dx + dy * dy))
                        if dist < bestDist {
                            bestDist = dist
                            bestX = nx
                            bestY = ny
                        }
                    }
                }
            }
            if bestDist == Double.infinity { continue }  // nowhere nearby, skip this unit
            tgtX = Double(bestX * 24) + 12.0
            tgtY = Double(bestY * 24) + 12.0
        }

        if queued && obj.mission == .move && obj.moveTargetX != nil {
            // Already moving — queue this as a waypoint
            obj.moveWaypoints.append((x: tgtX, y: tgtY))
        } else {
            obj.moveTargetX = tgtX
            obj.moveTargetY = tgtY
            obj.attackTarget = nil
            obj.isAttackMoving = attackMove
            obj.mission = .move
            obj.movePath = []
            if !queued { obj.moveWaypoints = [] }
        }
        obj.groupMoveSpeed = count == 1 ? nil : groupSpeed
    }
}
