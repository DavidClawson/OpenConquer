import Foundation

// MARK: - Reinforcements & Cargo Transport System
// Ported from Vanilla Conquer reinf.cpp, cargo.cpp, cargo.h

// MARK: - Pending Reinforcement (C17 fly-in delivery)

/// Tracks a cargo plane flying across the map to deliver units.
/// The C17 spawns at the right map edge, flies left to the drop zone,
/// unloads its cargo, then continues off the left edge and is removed.
class PendingReinforcement {
    let transportId: Int            // Object ID of the C17 aircraft
    let dropCell: Int               // Cell where cargo is delivered
    let house: House
    var state: ReinforcementState = .flyingIn

    enum ReinforcementState {
        case flyingIn       // Flying toward drop zone
        case unloading      // At drop zone, deploying cargo
        case flyingOut      // Cargo delivered, exiting map
    }

    init(transportId: Int, dropCell: Int, house: House) {
        self.transportId = transportId
        self.dropCell = dropCell
        self.house = house
    }
}

// MARK: - Cargo Extension Methods on GameObject

extension GameObject {

    /// Whether this object type can carry passengers (APC, TRAN, C17, HOVER)
    var isTransporter: Bool {
        let upper = typeName.uppercased()
        // Check unit type data
        if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
            return data.isTransporter
        }
        // Check aircraft type data
        if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
            return data.isTransporter
        }
        return false
    }

    /// Maximum passenger capacity for this transport
    var maxPassengers: Int {
        let upper = typeName.uppercased()
        switch upper {
        case "APC":  return 5
        case "TRAN": return 5   // Chinook
        case "C17":  return 5   // Cargo plane
        case "LST": return 5    // Hovercraft (Landing Ship Tank)
        default:     return 0
        }
    }

    /// True if this transport has passengers
    var hasCargo: Bool {
        !passengers.isEmpty
    }

    /// Number of passengers currently loaded
    var passengerCount: Int {
        passengers.count
    }

    /// Load a passenger into this transport.
    /// The passenger enters limbo (disappears from map).
    func loadPassenger(_ infantry: GameObject) {
        guard isTransporter else { return }
        guard passengers.count < maxPassengers else { return }
        guard infantry.kind == .infantry || infantry.kind == .unit else { return }

        passengers.append(infantry.id)
        infantry.isInLimbo = true
    }

    /// Unload all passengers around this transport's current position.
    /// Passengers reappear on the map near the transport.
    func unloadPassengers() {
        guard let world = session.world else { return }
        guard !passengers.isEmpty else { return }

        var unloadIndex = 0
        for passengerId in passengers {
            guard let passenger = world.findObject(id: passengerId) else { continue }
            guard passenger.strength > 0 else { continue }

            // Place passenger near the transport, offset by sub-cell positions
            let offset = subCellOffset(unloadIndex % 5)
            passenger.worldX = worldX + Double(offset.dx)
            passenger.worldY = worldY + Double(offset.dy) + 12.0
            passenger.prevWorldX = passenger.worldX
            passenger.prevWorldY = passenger.worldY
            passenger.isInLimbo = false
            passenger.subCell = unloadIndex % 5

            // Assign appropriate mission
            passenger.mission = .guardArea
            passenger.movePath = []
            passenger.moveTargetX = nil
            passenger.moveTargetY = nil

            unloadIndex += 1
        }
        passengers.removeAll()

        print("Unloaded \(unloadIndex) passengers from \(typeName) at (\(Int(worldX)), \(Int(worldY)))")
    }

    /// Unload a single passenger (LIFO order like VC CargoClass::Detach_Object)
    func unloadOnePassenger() -> GameObject? {
        guard let world = session.world else { return nil }
        guard !passengers.isEmpty else { return nil }

        let passengerId = passengers.removeLast()
        guard let passenger = world.findObject(id: passengerId) else { return nil }
        guard passenger.strength > 0 else { return nil }

        let offset = subCellOffset(passengers.count % 5)
        passenger.worldX = worldX + Double(offset.dx)
        passenger.worldY = worldY + Double(offset.dy) + 12.0
        passenger.prevWorldX = passenger.worldX
        passenger.prevWorldY = passenger.worldY
        passenger.isInLimbo = false
        passenger.mission = .guardArea
        passenger.movePath = []
        passenger.moveTargetX = nil
        passenger.moveTargetY = nil

        return passenger
    }
}

// MARK: - Reinforcement Delivery System

/// Enhanced reinforcement spawning with C17 cargo plane fly-in delivery.
/// Replaces the simple `spawnReinforcements` stub in GameTrigger.swift.
///
/// Logic ported from VC Do_Reinforcements (reinf.cpp):
/// - If the team contains an aircraft (TRAN/C17), use air delivery
/// - Otherwise, spawn ground units at map edge and move them in
func doReinforcements(teamName: String) {
    guard session.world != nil else { return }

    guard let teamType = session.teamTypes.first(where: { $0.name == teamName }) else {
        print("Reinforcements: Unknown team type '\(teamName)'")
        return
    }

    // Determine delivery method by examining team composition (VC reinf.cpp logic)
    var hasAirTransport = false
    var hasWaterTransport = false
    var hasGunboat = false

    for slot in teamType.classSlots {
        let upper = slot.typeName.uppercased()
        if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
            if data.isTransporter || data.isFixedWing {
                hasAirTransport = true
            }
        }
        if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
            if data.isTransporter && data.speed == .hover {
                hasWaterTransport = true  // Hovercraft/LST
            }
            if ut.isGunboat {
                hasGunboat = true  // Gunboat arrives via SOURCE_SHIPPING
            }
        }
    }

    if hasAirTransport {
        doAirReinforcement(teamType: teamType)
    } else if hasWaterTransport || hasGunboat {
        doBeachReinforcement(teamType: teamType, isGunboat: hasGunboat)
    } else {
        doGroundReinforcement(teamType: teamType)
    }
}

// MARK: - Air Reinforcement (C17 / Transport Helicopter)

/// Deliver reinforcements by C17 cargo plane or transport helicopter.
/// The transport flies in from the right edge, drops units at the airstrip
/// (for C17) or a waypoint, then flies off.
private func doAirReinforcement(teamType: TeamType) {
    guard let world = session.world else { return }

    // Separate transport slots from cargo slots
    var transportSlots: [TeamClassSlot] = []
    var cargoSlots: [TeamClassSlot] = []

    for slot in teamType.classSlots {
        let upper = slot.typeName.uppercased()
        if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
            if data.isTransporter || data.isFixedWing {
                transportSlots.append(slot)
            } else {
                cargoSlots.append(slot)
            }
        } else {
            cargoSlots.append(slot)
        }
    }

    // If no explicit transport, use C17 as default for air delivery
    if transportSlots.isEmpty {
        transportSlots.append(TeamClassSlot(kind: .unit, typeName: "C17", desiredCount: 1))
    }

    // Find drop zone: airstrip for C17, or waypoint 25 (WAYPT_REINF), or map center
    let dropCell: Int
    let transportType = transportSlots[0].typeName.uppercased()

    if transportType == "C17" {
        // Look for an airstrip belonging to this house
        if let airstrip = findAirstrip(house: teamType.house) {
            dropCell = airstrip.cell
        } else if let reinfCell = session.scenarioWaypoints[25] {
            dropCell = reinfCell
        } else if let bounds = world.mapBounds {
            dropCell = (bounds.y + bounds.height / 2) * 64 + (bounds.x + bounds.width / 2)
        } else {
            dropCell = 32 * 64 + 32
        }
    } else {
        // Transport helicopter: use waypoint 25 or map center
        if let reinfCell = session.scenarioWaypoints[25] {
            dropCell = reinfCell
        } else if let bounds = world.mapBounds {
            dropCell = (bounds.y + bounds.height / 2) * 64 + (bounds.x + bounds.width / 2)
        } else {
            dropCell = 32 * 64 + 32
        }
    }

    let dropPos = cellToPixel(dropCell)
    let dropX = Double(dropPos.px) + 12.0
    let dropY = Double(dropPos.py) + 12.0

    // Create cargo objects (in limbo)
    var cargoIds: [Int] = []
    for slot in cargoSlots {
        for _ in 0..<slot.desiredCount {
            let kind = slot.kind
            let speed = resolveSpeed(typeName: slot.typeName, kind: kind)
            let hp = resolveStrength(typeName: slot.typeName, kind: kind, scenarioStrength: 256)

            let cargo = GameObject(
                id: world.allocateId(),
                typeName: slot.typeName,
                house: teamType.house,
                kind: kind,
                worldX: dropX, worldY: dropY,
                facing: 128,
                strength: hp,
                mission: .guard_,
                speed: speed
            )
            cargo.isInLimbo = true
            world.addObject(cargo)
            cargoIds.append(cargo.id)
        }
    }

    // Create transport aircraft
    for slot in transportSlots {
        for _ in 0..<slot.desiredCount {
            // Spawn at right edge of map, aligned with drop zone Y
            let spawnX: Double
            if let bounds = world.mapBounds {
                spawnX = Double((bounds.x + bounds.width) * 24) + 48.0
            } else {
                spawnX = 64.0 * 24.0 + 48.0
            }

            let transport: GameObject
            if let at = AircraftType.from(iniName: slot.typeName.uppercased()) {
                transport = createAircraft(
                    world: world,
                    type: at,
                    house: teamType.house,
                    worldX: spawnX,
                    worldY: dropY,
                    facing: 192,  // Face west
                    mission: .unload
                )
            } else {
                // Fallback: create C17
                transport = createAircraft(
                    world: world,
                    type: .cargo,
                    house: teamType.house,
                    worldX: spawnX,
                    worldY: dropY,
                    facing: 192,
                    mission: .unload
                )
            }

            transport.isALoaner = true
            transport.passengers = cargoIds
            transport.moveTargetX = dropX
            transport.moveTargetY = dropY

            world.addObject(transport)

            // Track the reinforcement delivery
            let pending = PendingReinforcement(
                transportId: transport.id,
                dropCell: dropCell,
                house: teamType.house
            )
            session.pendingReinforcements.append(pending)

            print("Reinforcements: C17/transport spawned at (\(Int(spawnX)), \(Int(dropY))), "
                  + "delivering \(cargoIds.count) units to cell \(dropCell)")
        }
    }

    // Announce reinforcements if this is the player's house
    if teamType.house == world.playerHouse {
        audioManager.speak(.reinforcements)
    }
}

// MARK: - Beach Reinforcement (Hovercraft / LST)

/// Deliver reinforcements via beach landing (hovercraft/LST) or shipping lane (gunboat).
/// Ported from VC reinf.cpp SOURCE_BEACH / SOURCE_SHIPPING logic.
///
/// Hovercraft: Spawns at southern water edge, sails north to beach, unloads cargo.
/// Gunboat: Spawns at eastern water edge, sails west across map.
private func doBeachReinforcement(teamType: TeamType, isGunboat: Bool) {
    guard let world = session.world else { return }
    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    if isGunboat {
        // SOURCE_SHIPPING: Gunboat arrives from east edge, sails west
        // Find a water row for the gunboat (scan from top of map for water rows)
        var shippingRow = bounds.y + bounds.height / 2
        for y in bounds.y..<(bounds.y + bounds.height) {
            let rightEdgeCell = y * 64 + bounds.x + bounds.width - 1
            if rightEdgeCell < 4096 && waterPassability[rightEdgeCell] {
                shippingRow = y
                break
            }
        }

        let spawnX = Double((bounds.x + bounds.width) * 24) + 24.0
        let spawnY = Double(shippingRow * 24) + 12.0

        for slot in teamType.classSlots {
            for _ in 0..<slot.desiredCount {
                let speed = resolveSpeed(typeName: slot.typeName, kind: .unit)
                let hp = resolveStrength(typeName: slot.typeName, kind: .unit, scenarioStrength: 256)
                let obj = GameObject(
                    id: world.allocateId(),
                    typeName: slot.typeName,
                    house: teamType.house,
                    kind: .unit,
                    worldX: spawnX, worldY: spawnY,
                    facing: 192,  // DIR_W
                    strength: hp,
                    mission: .hunt,
                    speed: speed
                )
                obj.isALoaner = true
                // Destination: west edge of map along same row (stay within bounds)
                obj.moveTargetX = Double(bounds.x * 24) + 12.0
                obj.moveTargetY = spawnY
                world.addObject(obj)
            }
        }

        print("Reinforcements: Gunboat arriving via shipping from east edge at row \(shippingRow)")
    } else {
        // SOURCE_BEACH: Hovercraft arrives from south, lands on beach.
        // Scan columns from CENTER outward to find a beach (water→land transition),
        // preferring columns near the middle of the map for natural-looking approach.
        var beachCell: Int? = nil
        let centerX = bounds.x + bounds.width / 2
        for offset in 0..<bounds.width {
            // Alternate left and right from center
            let candidates = offset == 0 ? [centerX] : [centerX + offset, centerX - offset]
            for x in candidates {
                if x < bounds.x || x >= bounds.x + bounds.width { continue }

                // Scan upward from bottom to find where water meets land
                var foundWater = false
                for y in stride(from: bounds.y + bounds.height - 1, through: bounds.y, by: -1) {
                    let cell = y * 64 + x
                    guard cell >= 0 && cell < 4096 else { continue }
                    if waterPassability[cell] {
                        foundWater = true
                    } else if foundWater && landPassability[cell] {
                        // Found land cell above water — this is a beach
                        beachCell = cell
                        break
                    }
                }
                if beachCell != nil { break }
            }
            if beachCell != nil { break }
        }

        // Fallback: if no beach found, use waypoint 25 or center of map
        let landingCell = beachCell ?? session.scenarioWaypoints[25]
            ?? ((bounds.y + bounds.height / 2) * 64 + bounds.x + bounds.width / 2)

        let landingPos = cellToPixel(landingCell)
        let destX = Double(landingPos.px) + 12.0
        let destY = Double(landingPos.py) + 12.0

        // Spawn hovercraft at the southernmost water cell in the landing column
        // (NOT outside map bounds, which would be impassable for hover units)
        let landingCellX = landingCell % 64
        var spawnCellY = bounds.y + bounds.height - 1
        for y in stride(from: bounds.y + bounds.height - 1, through: bounds.y, by: -1) {
            let cell = y * 64 + landingCellX
            if cell >= 0 && cell < 4096 && waterPassability[cell] {
                spawnCellY = y
                break
            }
        }
        // If no water found in this column, try adjacent columns
        if !waterPassability[spawnCellY * 64 + landingCellX] {
            for dx in 1...5 {
                for tryX in [landingCellX - dx, landingCellX + dx] {
                    guard tryX >= bounds.x && tryX < bounds.x + bounds.width else { continue }
                    for y in stride(from: bounds.y + bounds.height - 1, through: bounds.y, by: -1) {
                        let cell = y * 64 + tryX
                        if cell >= 0 && cell < 4096 && waterPassability[cell] {
                            spawnCellY = y
                            break
                        }
                    }
                    if waterPassability[spawnCellY * 64 + min(63, max(0, tryX))] { break }
                }
                if spawnCellY != bounds.y + bounds.height - 1 { break }
            }
        }
        let spawnY = Double(spawnCellY * 24) + 12.0
        let spawnX = Double(landingCellX * 24) + 12.0

        // Separate transport from cargo
        var transportObj: GameObject? = nil
        var cargoObjects: [GameObject] = []

        for slot in teamType.classSlots {
            for i in 0..<slot.desiredCount {
                let kind = slot.kind
                let speed = resolveSpeed(typeName: slot.typeName, kind: kind)
                let hp = resolveStrength(typeName: slot.typeName, kind: kind, scenarioStrength: 256)

                let upper = slot.typeName.uppercased()
                let isTransport: Bool
                if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
                    isTransport = data.isTransporter
                } else {
                    isTransport = false
                }

                let obj = GameObject(
                    id: world.allocateId(),
                    typeName: slot.typeName,
                    house: teamType.house,
                    kind: kind,
                    worldX: spawnX + Double(i) * 12.0, worldY: spawnY,
                    facing: 0,  // DIR_N — facing north (toward beach)
                    strength: hp,
                    mission: .move,
                    speed: speed
                )

                if isTransport {
                    transportObj = obj
                    obj.isALoaner = true
                } else {
                    cargoObjects.append(obj)
                }

                world.addObject(obj)
            }
        }

        // Load cargo into hovercraft and send it to the beach
        if let transport = transportObj {
            for cargo in cargoObjects {
                transport.loadPassenger(cargo)
            }
            transport.moveTargetX = destX
            transport.moveTargetY = destY
            transport.mission = .unload
        }

        print("Reinforcements: Hovercraft approaching beach from south at (\(Int(spawnX)), \(Int(spawnY))) -> cell \(landingCell)")
    }

    if teamType.house == world.playerHouse {
        audioManager.speak(.reinforcements)
    }
}

// MARK: - Ground Reinforcement

/// Deliver reinforcements by ground — spawn at map edge and move in.
private func doGroundReinforcement(teamType: TeamType) {
    guard let world = session.world else { return }

    // Find spawn location: map edge
    let spawnX: Double
    let spawnY: Double

    if let bounds = world.mapBounds {
        // Spawn at right edge (VC uses house edge, we simplify to right)
        spawnX = Double((bounds.x + bounds.width) * 24) + 12.0
        spawnY = Double(bounds.y * 24 + bounds.height * 12)
    } else {
        spawnX = 64.0 * 24.0 - 12.0
        spawnY = 32.0 * 24.0
    }

    // Destination: waypoint 25 or map center
    let destX: Double
    let destY: Double

    if let reinfCell = session.scenarioWaypoints[25] {
        let pos = cellToPixel(reinfCell)
        destX = Double(pos.px) + 12.0
        destY = Double(pos.py) + 12.0
    } else if let bounds = world.mapBounds {
        destX = Double(bounds.x * 24 + bounds.width * 12)
        destY = Double(bounds.y * 24 + bounds.height * 12)
    } else {
        destX = 32.0 * 24.0
        destY = 32.0 * 24.0
    }

    print("Reinforcements: Spawning ground team '\(teamType.name)' at (\(Int(spawnX)), \(Int(spawnY)))")

    var transportObj: GameObject? = nil
    var cargoObjects: [GameObject] = []

    for slot in teamType.classSlots {
        for i in 0..<slot.desiredCount {
            let kind = slot.kind
            let speed = resolveSpeed(typeName: slot.typeName, kind: kind)
            let hp = resolveStrength(typeName: slot.typeName, kind: kind, scenarioStrength: 256)
            let offset = Double(i) * 12.0

            let upper = slot.typeName.uppercased()
            let isTransport: Bool
            if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
                isTransport = data.isTransporter
            } else {
                isTransport = false
            }

            let obj = GameObject(
                id: world.allocateId(),
                typeName: slot.typeName,
                house: teamType.house,
                kind: kind,
                worldX: spawnX + offset, worldY: spawnY,
                facing: 192,  // Face west (into map)
                strength: hp,
                mission: .move,
                speed: speed
            )

            if isTransport {
                transportObj = obj
            } else {
                cargoObjects.append(obj)
            }

            world.addObject(obj)
        }
    }

    // If there's a transport (APC), load cargo into it
    if let transport = transportObj, !cargoObjects.isEmpty {
        for cargo in cargoObjects {
            transport.loadPassenger(cargo)
        }
        transport.moveTargetX = destX
        transport.moveTargetY = destY
        transport.mission = .move
    } else {
        // No transport: all objects move independently to destination
        for obj in world.objects.suffix(teamType.classSlots.reduce(0) { $0 + $1.desiredCount }) {
            if obj.house == teamType.house && obj.mission == .move && obj.moveTargetX == nil {
                obj.moveTargetX = destX
                obj.moveTargetY = destY
            }
        }
        // Set move targets for all spawned objects
        let totalSpawned = cargoObjects.count + (transportObj != nil ? 1 : 0)
        let allObjects = world.objects
        let startIdx = max(0, allObjects.count - totalSpawned)
        for idx in startIdx..<allObjects.count {
            let obj = allObjects[idx]
            if obj.moveTargetX == nil {
                obj.moveTargetX = destX
                obj.moveTargetY = destY
            }
        }
    }

    if teamType.house == world.playerHouse {
        audioManager.speak(.reinforcements)
    }
}

// MARK: - Reinforcement Tick

/// Tick all pending reinforcement deliveries (C17 fly-in).
/// Called every game tick from the main game loop.
func tickReinforcements() {
    guard let world = session.world else { return }

    var completedIndices: [Int] = []

    for (index, pending) in session.pendingReinforcements.enumerated() {
        guard let transport = world.findObject(id: pending.transportId) else {
            completedIndices.append(index)
            continue
        }
        guard transport.strength > 0 else {
            // Transport destroyed — unload cargo where it died
            transport.unloadPassengers()
            completedIndices.append(index)
            continue
        }

        switch pending.state {
        case .flyingIn:
            // Fly toward drop zone
            let stillFlying = transport.flyToward()
            if !stillFlying {
                // Arrived at drop zone
                pending.state = .unloading
            }

        case .unloading:
            // Drop all cargo at the current position
            transport.unloadPassengers()
            pending.state = .flyingOut

            // Set exit target: fly off left edge of map
            let exitX: Double
            if let bounds = world.mapBounds {
                exitX = Double(bounds.x * 24) - 96.0
            } else {
                exitX = -96.0
            }
            transport.moveTargetX = exitX
            transport.moveTargetY = transport.worldY
            transport.facing = 192  // Face west

        case .flyingOut:
            // Fly off map
            let stillFlying = transport.flyToward()
            if !stillFlying {
                // Off map — remove transport
                transport.strength = 0
                completedIndices.append(index)
            }

            // Also remove if well past map edge
            if let bounds = world.mapBounds {
                if transport.worldX < Double(bounds.x * 24) - 48.0 {
                    transport.strength = 0
                    if !completedIndices.contains(index) {
                        completedIndices.append(index)
                    }
                }
            }
        }
    }

    // Remove completed reinforcements (in reverse order to preserve indices)
    for index in completedIndices.sorted().reversed() {
        if index < session.pendingReinforcements.count {
            session.pendingReinforcements.remove(at: index)
        }
    }
}

// MARK: - APC / Transport Unload Mission

extension GameObject {

    /// Tick the APC unload mission: eject passengers one at a time
    func tickAPCUnload() {
        guard isTransporter else {
            mission = .guard_
            return
        }

        guard !passengers.isEmpty else {
            mission = .guard_
            return
        }

        guard let world = session.world else { return }

        // Unload one passenger every 8 ticks
        if world.tickCount % 8 == 0 {
            if let _ = unloadOnePassenger() {
                // Keep unloading until empty
                if passengers.isEmpty {
                    // If this is a loaner transport, it should leave
                    if isALoaner {
                        if isAircraft {
                            // Fly off map
                            let exitX: Double
                            if let bounds = world.mapBounds {
                                exitX = Double(bounds.x * 24) - 96.0
                            } else {
                                exitX = -96.0
                            }
                            moveTargetX = exitX
                            moveTargetY = worldY
                            mission = .move
                        } else if cachedSpeedType == .hover || cachedSpeedType == .float_ {
                            // Water transport (hovercraft): sail to southernmost water cell then get cleaned up
                            if let bounds = world.mapBounds {
                                // Find southernmost water cell in current column within bounds
                                let col = cellX
                                var exitY = cellY
                                for y in stride(from: bounds.y + bounds.height - 1, through: cellY, by: -1) {
                                    let cell = y * 64 + col
                                    if cell >= 0 && cell < 4096 && waterPassability[cell] {
                                        exitY = y
                                        break
                                    }
                                }
                                moveTargetX = worldX
                                moveTargetY = Double(exitY * 24) + 12.0
                            } else {
                                moveTargetY = worldY + 96.0
                                moveTargetX = worldX
                            }
                            facing = 128  // DIR_S
                            mission = .move
                        } else {
                            // Ground transport: drive off map
                            mission = .retreat
                        }
                    } else {
                        mission = .guard_
                    }
                }
            }
        }
    }
}

// MARK: - Helper: Find Airstrip

/// Find the nearest airstrip belonging to a given house.
func findAirstrip(house: House) -> GameObject? {
    guard let world = session.world else { return nil }

    return world.objects.first {
        $0.kind == .structure &&
        $0.house == house &&
        $0.strength > 0 &&
        $0.typeName.uppercased() == "AFLD"
    }
}
