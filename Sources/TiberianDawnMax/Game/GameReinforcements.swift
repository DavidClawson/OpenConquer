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

        if typeName.uppercased() == "LST" {
            // Hovercraft beach landing: instead of materializing the unit on the
            // shoreline and standing it still, walk it a few cells inland (north,
            // away from the water the LST sailed in from — the same south-water
            // assumption the sail-back uses) so units visibly disembark onto the
            // shore rather than popping into existence on the beach.
            passenger.mission = .move
            passenger.moveTargetX = passenger.worldX
            passenger.moveTargetY = max(12.0, worldY - 3.0 * 24.0)
            passenger.movePath = []
        } else {
            // APC / destroyed-transport unload: disembark in place and hold.
            passenger.mission = .guardArea
            passenger.movePath = []
            passenger.moveTargetX = nil
            passenger.moveTargetY = nil
        }

        return passenger
    }
}

// MARK: - Reinforcement Delivery System

/// Create and place a reinforcement team — port of Do_Reinforcements
/// (REINF.CPP:63-430).
///
/// - A team with a mission list gets a force-active `ActiveTeam` that executes
///   those missions (REINF.CPP:75-80); members without one enter and hold.
/// - Delivery source: any aircraft → air; hovercraft → beach; gunboat →
///   shipping; otherwise the owning house's `Edge=` (REINF.CPP:111-128).
/// - Loaner rules (REINF.CPP:169-199): a transport is a loaner only when it is
///   carrying something AND is not a ground unit; a transport-only team (e.g.
///   SCG12's evac chopper) IS the reinforcement and keeps its transport.
///   Fixed-wing attack craft (A10) are always loaners.
func doReinforcements(teamName: String) {
    guard session.world != nil else { return }

    guard let teamType = session.teamTypes.first(where: { $0.name == teamName }) else {
        print("Reinforcements: Unknown team type '\(teamName)'")
        return
    }
    guard !teamType.classSlots.isEmpty else { return }

    // Team composition flags (REINF.CPP:89-105)
    var airTransport = false
    var waterTransport = false
    var onlyTransport = true

    for slot in teamType.classSlots {
        let upper = slot.typeName.uppercased()
        let isAircraftType = AircraftType.from(iniName: upper) != nil
        var isTransporterType = false
        if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
            isTransporterType = data.isTransporter
            if data.isTransporter && data.speed == .hover {
                waterTransport = true
            }
        }
        if isTransporterType || isAircraftType {
            if isAircraftType { airTransport = true }
        } else {
            onlyTransport = false
        }
    }

    // Gunboat special case: keys off the FIRST class slot (REINF.CPP:123)
    let isGunboat: Bool
    if let first = teamType.classSlots.first,
       let ut = UnitType.from(iniName: first.typeName.uppercased()), ut.isGunboat {
        isGunboat = true
    } else {
        isGunboat = false
    }

    // Controlling team: only created when there are missions to run
    // (REINF.CPP:70-80). The team handler assigns the members' missions.
    let team = createReinforcementTeam(type: teamType)

    if airTransport {
        doAirReinforcement(teamType: teamType, team: team, onlyTransport: onlyTransport)
    } else if waterTransport || isGunboat {
        doBeachReinforcement(teamType: teamType, team: team, isGunboat: isGunboat)
    } else {
        doGroundReinforcement(teamType: teamType, team: team,
                              edge: houseEdge(teamType.house))
    }
}

// MARK: - Edge Cell Selection (DisplayClass::Calculated_Cell)

/// Pick a clear cell along a map edge for a reinforcement to enter at — port of
/// Calculated_Cell's SOURCE_NORTH/EAST/SOUTH/WEST arms (DISPLAY.CPP:2413-2450):
/// random starting offset, then scan the whole edge for a cell where both the
/// edge cell and its inward neighbor are passable. Returns nil if the edge is
/// fully blocked. Uses the seeded RNG — this is simulation randomness.
func calculatedEdgeCell(edge: MapEdge, bounds: MapBounds) -> Int? {
    func clear(_ cell: Int) -> Bool {
        cell >= 0 && cell < 4096 && landPassability[cell]
    }

    switch edge {
    case .north, .south:
        let row = (edge == .north) ? bounds.y - 1 : bounds.y + bounds.height
        let inward = (edge == .north) ? 64 : -64
        let index = rndInt(1...bounds.width)
        for x in 0..<bounds.width {
            let cell = row * 64 + bounds.x + (x + index) % bounds.width
            if clear(cell) && clear(cell + inward) { return cell }
        }
    case .east, .west:
        let col = (edge == .east) ? bounds.x + bounds.width : bounds.x - 1
        let inward = (edge == .east) ? -1 : 1
        let index = rndInt(1...bounds.height)
        for y in 0..<bounds.height {
            let cell = (bounds.y + (y + index) % bounds.height) * 64 + col
            if clear(cell) && clear(cell + inward) { return cell }
        }
    }
    return nil
}

/// Facing (0-255) pointing inward from a map edge.
func edgeInwardFacing(_ edge: MapEdge) -> Int {
    switch edge {
    case .north: return 128  // enter from north → face south
    case .east:  return 192  // face west
    case .south: return 0    // face north
    case .west:  return 64   // face east
    }
}

/// Cell delta stepping inward (onto the map) from a given edge.
func edgeInwardDelta(_ edge: MapEdge) -> Int {
    switch edge {
    case .north: return 64
    case .east:  return -1
    case .south: return -64
    case .west:  return 1
    }
}

// MARK: - Air Reinforcement (C17 / Transport Helicopter / Fixed-Wing)

/// Deliver reinforcements by air — port of the SOURCE_AIR arm of
/// Do_Reinforcements (REINF.CPP:340-394). Aircraft enter from the owning
/// house's `Edge=` (cargo planes align with the airstrip row, east edge).
/// Fidelity points:
/// - Transporters carrying cargo are loaners; a transport-only team keeps its
///   transport (that IS the reinforcement — SCG12's evac chopper).
/// - Team-less fixed-wing (A10 strike) gets MISSION_HUNT (REINF.CPP:366-368)
///   and is always a loaner (REINF.CPP:191-193).
/// - Teamed aircraft enter under team control and follow the mission list.
private func doAirReinforcement(teamType: TeamType, team: ActiveTeam?, onlyTransport: Bool) {
    guard let world = session.world else { return }
    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)
    let edge = houseEdge(teamType.house)

    // Split slots: air transports carry, everything else (incl. fixed-wing
    // attack craft and any ground cargo) is delivered (REINF.CPP:169-199).
    var transportSlots: [TeamClassSlot] = []
    var otherSlots: [TeamClassSlot] = []
    for slot in teamType.classSlots {
        let upper = slot.typeName.uppercased()
        if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at],
           data.isTransporter {
            transportSlots.append(slot)
        } else {
            otherSlots.append(slot)
        }
    }

    // Drop destination: Calculated_Cell(SOURCE_AIR) = waypoint 25, else map
    // center (DISPLAY.CPP:2452-2462); C17s align with the airstrip instead.
    let hasC17 = transportSlots.contains { $0.typeName.uppercased() == "C17" }
        || transportSlots.contains { AircraftType.from(iniName: $0.typeName.uppercased()) == .cargo }
    var dropCell = session.scenarioWaypoints[25]
        ?? ((bounds.y + bounds.height / 2) * 64 + bounds.x + bounds.width / 2)
    if hasC17, let airstrip = findAirstrip(house: teamType.house) {
        dropCell = airstrip.cell
    }
    let dropPos = cellToPixel(dropCell)
    let dropX = Double(dropPos.px) + 12.0
    let dropY = Double(dropPos.py) + 12.0

    // Entry point along the house's edge (REINF.CPP:349-357); C17s always
    // stream in from the east at the drop row (classic aligns with the
    // airstrip docking row, east edge).
    let entryPoint: (x: Double, y: Double)
    if hasC17 {
        entryPoint = (x: Double((bounds.x + bounds.width) * 24) + 48.0, y: dropY)
    } else if let cell = calculatedEdgeCell(edge: edge, bounds: bounds) {
        let pos = cellToPixel(cell)
        entryPoint = (x: Double(pos.px) + 12.0, y: Double(pos.py) + 12.0)
    } else {
        entryPoint = (x: Double((bounds.x + bounds.width) * 24) + 48.0, y: dropY)
    }
    let entryFacing = edgeInwardFacing(edge)

    // Cargo objects ride in limbo aboard the first transport
    var cargoIds: [Int] = []
    var fixedWingObjects: [GameObject] = []
    for slot in otherSlots {
        for _ in 0..<slot.desiredCount {
            let upper = slot.typeName.uppercased()
            if let at = AircraftType.from(iniName: upper),
               let data = aircraftTypeDataTable[at], data.isFixedWing {
                // Fixed-wing attack craft (A10): its own delivery, not cargo
                let plane = createAircraft(
                    world: world, type: at, house: teamType.house,
                    worldX: entryPoint.x, worldY: entryPoint.y,
                    facing: entryFacing,
                    mission: team != nil ? .guard_ : .hunt  // REINF.CPP:366-368
                )
                plane.isALoaner = true  // A10s always loaners (REINF.CPP:191-193)
                world.addObject(plane)
                fixedWingObjects.append(plane)
                team?.members.append(plane.id)
                continue
            }
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
            team?.members.append(cargo.id)
        }
    }

    // Suppress the arrival announcement for loaded cargo planes — it plays at
    // the unload instead (REINF.CPP:222-229 okvoice).
    var announceNow = true

    for slot in transportSlots {
        for _ in 0..<slot.desiredCount {
            let at = AircraftType.from(iniName: slot.typeName.uppercased()) ?? .cargo
            let transport = createAircraft(
                world: world, type: at, house: teamType.house,
                worldX: entryPoint.x, worldY: entryPoint.y,
                facing: entryFacing,
                mission: .guard_
            )
            world.addObject(transport)
            team?.members.append(transport.id)

            if !cargoIds.isEmpty && transport.passengers.isEmpty {
                // First transport carries everything (REINF.CPP:218-233)
                transport.passengers = cargoIds
                // A carrying transport is a loaner — delivery agent only
                // (REINF.CPP:176-178). A transport-only team is NOT.
                transport.isALoaner = !onlyTransport
            }

            if team == nil {
                if transport.hasCargo {
                    // Fly to the drop cell, unload, exit (classic
                    // MISSION_UNLOAD → Assign_Destination, REINF.CPP:369-374)
                    transport.mission = .unload
                    transport.moveTargetX = dropX
                    transport.moveTargetY = dropY
                    session.pendingReinforcements.append(PendingReinforcement(
                        transportId: transport.id, dropCell: dropCell, house: teamType.house))
                    if at == .cargo { announceNow = false }
                } else {
                    // Empty transport IS the reinforcement: fly to the drop
                    // cell and await orders (REINF.CPP:371-374)
                    transport.mission = .move
                    transport.moveTargetX = dropX
                    transport.moveTargetY = dropY
                }
            }
            // With a team: the force-active team's mission list drives it
            // (move/unload waypoints) — no scripted exit, no forced unload.

            print("Reinforcements: \(slot.typeName) entering from \(edge.rawValue) "
                  + "with \(transport.passengerCount) passengers"
                  + (team != nil ? " (teamed)" : ""))
        }
    }

    if announceNow && teamType.house == world.playerHouse {
        audioManager.speak(.reinforcements)
    }
}

// MARK: - Beach Reinforcement (Hovercraft / LST)

/// Deliver reinforcements via beach landing (hovercraft/LST) or shipping lane (gunboat).
/// Ported from VC reinf.cpp SOURCE_BEACH / SOURCE_SHIPPING logic.
/// The hover lander itself never joins the team (REINF.CPP:160); its cargo does.
///
/// Hovercraft: Spawns at southern water edge, sails north to beach, unloads cargo.
/// Gunboat: Spawns at eastern water edge, sails west across map.
private func doBeachReinforcement(teamType: TeamType, team: ActiveTeam?, isGunboat: Bool) {
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
                    // Cargo joins the controlling team; the lander never does
                    // (REINF.CPP:160)
                    team?.members.append(obj.id)
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

/// Deliver reinforcements by ground from the owning house's map edge — port of
/// the SOURCE_NORTH/EAST/SOUTH/WEST arm of Do_Reinforcements
/// (REINF.CPP:257-335). Teamed members enter with MISSION_GUARD and the team
/// handler drives them; team-less members move one cell inward and hold.
private func doGroundReinforcement(teamType: TeamType, team: ActiveTeam?, edge: MapEdge) {
    guard let world = session.world else { return }
    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    // Entry point along the house's edge; fall back to the edge midpoint if the
    // whole edge is blocked (classic aborts — we degrade gracefully instead).
    let entryCell: Int
    if let cell = calculatedEdgeCell(edge: edge, bounds: bounds) {
        entryCell = cell
    } else {
        switch edge {
        case .north: entryCell = (bounds.y - 1) * 64 + bounds.x + bounds.width / 2
        case .south: entryCell = (bounds.y + bounds.height) * 64 + bounds.x + bounds.width / 2
        case .east:  entryCell = (bounds.y + bounds.height / 2) * 64 + bounds.x + bounds.width
        case .west:  entryCell = (bounds.y + bounds.height / 2) * 64 + bounds.x - 1
        }
    }
    let facing = edgeInwardFacing(edge)

    // Create the members, splitting ground transports (APC) from the rest.
    // Ground transports are never loaners (REINF.CPP:176): the crate arrives
    // with the goods and both are keepers.
    var transportObj: GameObject? = nil
    var cargoObjects: [GameObject] = []

    for slot in teamType.classSlots {
        for _ in 0..<slot.desiredCount {
            let kind = slot.kind
            let speed = resolveSpeed(typeName: slot.typeName, kind: kind)
            let hp = resolveStrength(typeName: slot.typeName, kind: kind, scenarioStrength: 256)

            let upper = slot.typeName.uppercased()
            var isTransport = false
            if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
                isTransport = data.isTransporter
            }

            let pos = cellToPixel(entryCell)
            let obj = GameObject(
                id: world.allocateId(),
                typeName: slot.typeName,
                house: teamType.house,
                kind: kind,
                worldX: Double(pos.px) + 12.0, worldY: Double(pos.py) + 12.0,
                facing: facing,
                strength: hp,
                mission: .guard_,
                speed: speed
            )

            if isTransport && transportObj == nil {
                transportObj = obj
            } else {
                cargoObjects.append(obj)
            }
            world.addObject(obj)
        }
    }

    // If a transport came along, everything else rides inside it
    // (REINF.CPP:218-233: Attach + place only the transport).
    var placedObjects: [GameObject]
    if let transport = transportObj, !cargoObjects.isEmpty {
        for cargo in cargoObjects {
            transport.loadPassenger(cargo)
        }
        placedObjects = [transport]
    } else {
        placedObjects = cargoObjects
        if let transport = transportObj { placedObjects.append(transport) }
    }

    // Stagger on-map entry cells: first object on the entry cell, the rest on
    // nearby free cells along the edge (approximates the classic adjacent-cell
    // unlimbo scatter, REINF.CPP:296-312).
    var usedCells = Set<Int>()
    for obj in placedObjects {
        var cell = entryCell
        if usedCells.contains(cell) {
            let lateral = (edge == .north || edge == .south) ? 1 : 64
            for step in 1...8 {
                let candidates = [entryCell + step * lateral, entryCell - step * lateral]
                if let free = candidates.first(where: {
                    !usedCells.contains($0) && $0 >= 0 && $0 < 4096 && landPassability[$0]
                }) {
                    cell = free
                    break
                }
            }
        }
        usedCells.insert(cell)
        let pos = cellToPixel(cell)
        obj.worldX = Double(pos.px) + 12.0
        obj.worldY = Double(pos.py) + 12.0
        obj.prevWorldX = obj.worldX
        obj.prevWorldY = obj.worldY

        if let team = team {
            // Team handler assigns the real missions (REINF.CPP:287-289)
            obj.mission = .guard_
            team.members.append(obj.id)
        } else {
            // No mission list: step onto the map and hold (REINF.CPP:290-292)
            let inwardCell = cell + edgeInwardDelta(edge)
            let dest = cellToPixel(inwardCell)
            obj.mission = .move
            obj.moveTargetX = Double(dest.px) + 12.0
            obj.moveTargetY = Double(dest.py) + 12.0
        }
    }
    // Limboed passengers follow their transport's team membership implicitly —
    // classic adds them to the team too; ours recruit into it on unload if the
    // team still exists. Keep them listed so team strength counts the cargo.
    if let team = team, let transport = transportObj, !cargoObjects.isEmpty {
        for cargo in cargoObjects where cargo.id != transport.id {
            team.members.append(cargo.id)
        }
    }

    print("Reinforcements: ground team '\(teamType.name)' entering from \(edge.rawValue) at cell \(entryCell)"
          + (team != nil ? " (teamed, \(teamType.missionList.count) missions)" : ""))

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
            // Drop all cargo at the current position. The arrival announcement
            // for loaded cargo planes plays here, not at map entry
            // (REINF.CPP:222-229 okvoice → announced on unload).
            if pending.house == world.playerHouse {
                audioManager.speak(.reinforcements)
            }
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
