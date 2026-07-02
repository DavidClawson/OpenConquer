import Foundation

// MARK: - Team AI System
// Ported from Vanilla Conquer team.h/team.cpp, teamtype.h/teamtype.cpp

// MARK: - Team Mission Types (VC TeamMissionType)

enum TeamMission: Int, CaseIterable {
    case attackBase = 0       // Attack nearest enemy base
    case attackUnits = 1      // Attack all enemy units
    case attackCivilians = 2  // Attack all civilians
    case rampage = 3          // Attack & destroy anything not mine
    case defendBase = 4       // Protect my base
    case move = 5             // Move to waypoint
    case moveCell = 6         // Move to specific cell
    case retreat = 7          // Retreat (coordinated)
    case guard_ = 8           // Guard current position
    case loop = 9             // Loop back to start of mission list
    case attackTarcom = 10    // Attack specific target
    case unload = 11          // Unload at current location

    var displayName: String {
        switch self {
        case .attackBase:      return "Attack Base"
        case .attackUnits:     return "Attack Units"
        case .attackCivilians: return "Attack Civil."
        case .rampage:         return "Rampage"
        case .defendBase:      return "Defend Base"
        case .move:            return "Move"
        case .moveCell:        return "Move to Cell"
        case .retreat:         return "Retreat"
        case .guard_:          return "Guard"
        case .loop:            return "Loop"
        case .attackTarcom:    return "Attack Tarcom"
        case .unload:          return "Unload"
        }
    }

    static func from(_ name: String) -> TeamMission? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        for mission in TeamMission.allCases {
            if mission.displayName.lowercased() == lower { return mission }
        }
        // Fallback partial matches
        if lower.contains("attack") && lower.contains("base") { return .attackBase }
        if lower.contains("attack") && lower.contains("unit") { return .attackUnits }
        if lower.contains("attack") && lower.contains("civil") { return .attackCivilians }
        if lower.contains("rampage") { return .rampage }
        if lower.contains("defend") { return .defendBase }
        if lower.contains("move") && lower.contains("cell") { return .moveCell }
        if lower.contains("move") { return .move }
        if lower.contains("retreat") { return .retreat }
        if lower.contains("guard") { return .guard_ }
        if lower.contains("loop") { return .loop }
        if lower.contains("tarcom") { return .attackTarcom }
        if lower.contains("unload") { return .unload }
        return nil
    }
}

// MARK: - Team Mission Entry

struct TeamMissionEntry {
    let mission: TeamMission
    let argument: Int           // Waypoint index, cell number, or loop target
}

// MARK: - Team Member Slot

struct TeamClassSlot {
    let kind: ObjectKind        // .unit or .infantry
    let typeName: String        // INI name (e.g., "MTNK", "E1")
    let desiredCount: Int       // How many of this type to recruit
}

// MARK: - Team Type Definition (static template from scenario INI)

let maxTeamClassCount = 5
let maxTeamMissions = 20

class TeamType {
    let name: String
    let house: House

    // Flags
    var isRoundAbout: Bool = false    // Avoid threats during movement
    var isLearning: Bool = false      // Learn from mistakes
    var isSuicide: Bool = false       // Won't stop until dead or mission done
    var isAutocreate: Bool = false    // Can be auto-created by AI
    var isMercenary: Bool = false     // Changes sides if losing
    var isPrebuilt: Bool = true       // Build members regardless
    var isReinforcable: Bool = true   // Allow new member recruitment

    // Configuration
    var recruitPriority: Int = 7     // 0-15, higher can steal from lower
    var maxAllowed: Int = 0          // 0 = unlimited
    var initNum: Int = 0             // Number to create at scenario start
    var fear: Int = 0                // Fear level (0=fearless)

    // Composition
    var classSlots: [TeamClassSlot] = []

    // Mission list
    var missionList: [TeamMissionEntry] = []

    init(name: String, house: House) {
        self.name = name
        self.house = house
    }
}

// MARK: - Active Team Instance (runtime)

/// Maximum distance (in cells) units can stray from team center
let teamStrayDistance: Double = 2.0 * 24.0

class ActiveTeam {
    let type: TeamType
    let house: House
    var members: [Int] = []         // Object IDs in this team
    var isMoving: Bool = false      // Executing main mission (vs regrouping)
    var isFullStrength: Bool = false
    var isUnderStrength: Bool = true
    var isHasBeen: Bool = false     // Has ever been full strength
    var currentMission: Int = -1    // Current mission index
    var isNextMission: Bool = true  // Ready to advance to next mission
    var centerX: Double = 0        // Average position of members
    var centerY: Double = 0
    var target: Int? = nil          // Current target object ID
    var targetCell: Int? = nil      // Target cell for move missions
    var missionTimeout: Int = 0     // Ticks until mission times out
    var isSuspended: Bool = false
    var suspendTimer: Int = 0

    init(type: TeamType) {
        self.type = type
        self.house = type.house
    }

    /// Total desired member count
    var desiredCount: Int {
        type.classSlots.reduce(0) { $0 + $1.desiredCount }
    }

    /// Current member count (living)
    var memberCount: Int {
        guard let world = session.world else { return 0 }
        return members.filter { id in
            world.objects.contains { $0.id == id && $0.strength > 0 }
        }.count
    }
}

// MARK: - ActiveTeam Extension

extension ActiveTeam {

    /// Process this team's AI for one tick
    func tick() {
        guard session.world != nil else { return }

        // Suspension check
        if isSuspended {
            if suspendTimer > 0 {
                suspendTimer -= 4
                return
            }
            isSuspended = false
        }

        // Recalculate center
        calcTeamCenter()

        // Strength calculation
        let current = memberCount
        let desired = desiredCount

        isFullStrength = (current >= desired)
        if type.isReinforcable {
            isUnderStrength = (current <= desired / 3) && current < desired
        } else {
            isUnderStrength = !isHasBeen && current < desired
        }

        // Delete empty human teams that were activated
        if current == 0 && isHasBeen {
            return  // Will be cleaned up by tickTeams
        }

        // Regroup if understrength while executing missions
        if isMoving && isUnderStrength {
            isMoving = false
            currentMission = -1

            // Move to nearest friendly building to regroup
            if let regroupPos = findRegroupPosition() {
                coordinateMove(targetX: regroupPos.x, targetY: regroupPos.y)
            }
            return
        }

        // Launch mission when full strength (or forced)
        if !isMoving && isFullStrength {
            isMoving = true
            isHasBeen = true
            isUnderStrength = false
            currentMission = -1
            isNextMission = true
        }

        // Recruit if not full strength
        if !isFullStrength && type.isReinforcable {
            recruitMembers()
        }

        // Advance to next mission
        if isMoving && isNextMission {
            isNextMission = false
            currentMission += 1

            if currentMission >= type.missionList.count {
                // Mission list exhausted — dissolve team
                dissolve()
                return
            }

            let missionEntry = type.missionList[currentMission]
            missionTimeout = missionEntry.argument * 90  // VC: arg * (TICKS_PER_MINUTE / 10)
            target = nil
            targetCell = nil

            // Set up mission target based on type
            switch missionEntry.mission {
            case .moveCell:
                targetCell = missionEntry.argument
            case .move, .unload:
                // Use waypoint from scenario
                if let cell = waypointCell(missionEntry.argument) {
                    targetCell = cell
                }
            default:
                break
            }
        }

        // Execute current mission
        guard isMoving && !isUnderStrength else { return }
        guard currentMission >= 0 && currentMission < type.missionList.count else { return }

        let missionEntry = type.missionList[currentMission]

        switch missionEntry.mission {
        case .attackBase:
            // Find nearest enemy building
            if target == nil {
                if let enemyBuilding = findNearestEnemyBuilding() {
                    target = enemyBuilding.id
                }
            }
            coordinateAttack()

        case .attackUnits:
            // Find nearest enemy unit
            if target == nil {
                if let enemyUnit = findNearestEnemyUnit() {
                    target = enemyUnit.id
                }
            }
            coordinateAttack()

        case .attackCivilians:
            if target == nil {
                if let civ = findNearestCivilian() {
                    target = civ.id
                }
            }
            coordinateAttack()

        case .rampage, .attackTarcom:
            if target == nil {
                if let enemy = findNearestEnemyAny() {
                    target = enemy.id
                }
            }
            coordinateAttack()

        case .defendBase:
            if let cell = targetCell {
                let pos = cellToPixel(cell)
                coordinateMove(targetX: Double(pos.px) + 12.0, targetY: Double(pos.py) + 12.0)
            } else {
                coordinateRegroup()
            }

        case .move, .moveCell, .retreat:
            if let cell = targetCell {
                let pos = cellToPixel(cell)
                coordinateMove(targetX: Double(pos.px) + 12.0, targetY: Double(pos.py) + 12.0)
            } else {
                isNextMission = true
            }

        case .guard_:
            coordinateRegroup()

        case .loop:
            // Loop back to mission index specified by argument
            currentMission = max(0, missionEntry.argument) - 1
            isNextMission = true

        case .unload:
            coordinateUnload()
        }

        // Mission timeout
        if missionTimeout > 0 {
            missionTimeout -= 4
            if missionTimeout <= 0 {
                switch missionEntry.mission {
                case .attackBase, .attackUnits, .attackCivilians, .rampage, .attackTarcom,
                     .defendBase, .unload, .retreat, .guard_:
                    isNextMission = true
                default:
                    break
                }
            }
        }
    }

    // MARK: - Recruitment

    /// Recruit members for this team from available units
    func recruitMembers() {
        guard let world = session.world else { return }

        for (slotIndex, slot) in type.classSlots.enumerated() {
            let currentCount = countMembersOfSlot(slotIndex: slotIndex)
            let needed = slot.desiredCount - currentCount
            guard needed > 0 else { continue }

            var recruited = 0
            for obj in world.objects {
                guard obj.house == house else { continue }
                guard obj.strength > 0 else { continue }
                guard !obj.isInLimbo else { continue }
                guard obj.typeName.uppercased() == slot.typeName.uppercased() else { continue }

                // Don't recruit from higher-priority teams
                if isInTeam(obj.id) {
                    if let existingTeam = teamForObject(obj.id) {
                        if existingTeam.type.recruitPriority >= type.recruitPriority {
                            continue
                        }
                        // Remove from lower priority team
                        existingTeam.removeMember(objectId: obj.id)
                    }
                }

                // Don't recruit units with sticky missions
                switch obj.mission {
                case .sticky, .sleep, .harvest:
                    continue
                default:
                    break
                }

                // Skip harvesters and MCVs
                if obj.isHarvester || obj.isMCV { continue }

                members.append(obj.id)
                recruited += 1
                if recruited >= needed { break }
            }
        }

        // Calculate center
        calcTeamCenter()
    }

    /// Count current members matching a particular class slot
    func countMembersOfSlot(slotIndex: Int) -> Int {
        guard slotIndex < type.classSlots.count else { return 0 }
        let slot = type.classSlots[slotIndex]
        guard let world = session.world else { return 0 }

        return members.filter { id in
            if let obj = world.findObject(id: id) {
                return obj.strength > 0 && obj.typeName.uppercased() == slot.typeName.uppercased()
            }
            return false
        }.count
    }

    /// Remove an object from this team
    func removeMember(objectId: Int) {
        members.removeAll { $0 == objectId }
    }

    // MARK: - Team Center Calculation

    /// Calculate the average position of team members
    func calcTeamCenter() {
        guard let world = session.world else { return }
        var x = 0.0, y = 0.0, count = 0

        for id in members {
            if let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo {
                x += obj.worldX
                y += obj.worldY
                count += 1
            }
        }

        if count > 0 {
            centerX = x / Double(count)
            centerY = y / Double(count)
        }
    }

    // MARK: - Team Coordination Functions

    /// Coordinate attack: all team members attack the same target
    func coordinateAttack() {
        guard let world = session.world else { return }
        guard let targetId = target else {
            isNextMission = true
            return
        }

        // Verify target is still alive
        guard world.objects.contains(where: { $0.id == targetId && $0.strength > 0 }) else {
            target = nil
            isNextMission = true
            return
        }

        for id in members {
            guard let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo else { continue }

            if obj.mission != .attack || obj.attackTarget != targetId {
                obj.attackTarget = targetId
                obj.mission = .attack
                obj.movePath = []
            }
        }
    }

    /// Coordinate move: all team members move to same destination
    func coordinateMove(targetX: Double, targetY: Double) {
        guard let world = session.world else { return }
        var allArrived = true

        for id in members {
            guard let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo else { continue }

            let dx = obj.worldX - targetX
            let dy = obj.worldY - targetY
            let dist = sqrt(dx * dx + dy * dy)

            if dist > teamStrayDistance {
                allArrived = false
                if obj.mission != .move || obj.moveTargetX == nil {
                    obj.moveTargetX = targetX + rndDouble(-24...24)
                    obj.moveTargetY = targetY + rndDouble(-24...24)
                    obj.mission = .move
                    obj.movePath = []
                }
            }
        }

        if allArrived && isMoving {
            isNextMission = true
        }
    }

    /// Coordinate regroup: gather all units to team center
    func coordinateRegroup() {
        guard let world = session.world else { return }

        for id in members {
            guard let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo else { continue }

            let dx = obj.worldX - centerX
            let dy = obj.worldY - centerY
            let dist = sqrt(dx * dx + dy * dy)

            if dist > teamStrayDistance {
                if obj.mission != .move || obj.moveTargetX == nil {
                    obj.moveTargetX = centerX + rndDouble(-12...12)
                    obj.moveTargetY = centerY + rndDouble(-12...12)
                    obj.mission = .move
                    obj.movePath = []
                }
            } else {
                if obj.mission == .move {
                    obj.mission = .guard_
                    obj.moveTargetX = nil
                    obj.moveTargetY = nil
                }
            }
        }
    }

    /// Coordinate unload: all transport members unload passengers
    func coordinateUnload() {
        guard let world = session.world else {
            isNextMission = true
            return
        }

        var anyUnloading = false
        for id in members {
            guard let obj = world.findObject(id: id), obj.strength > 0 else { continue }
            if obj.isTransporter && obj.hasCargo {
                obj.mission = .unload
                anyUnloading = true
            }
        }

        if !anyUnloading {
            isNextMission = true
        }
    }

    // MARK: - Team Target Finding

    /// Find nearest enemy building for team to attack
    func findNearestEnemyBuilding() -> GameObject? {
        guard let world = session.world else { return nil }
        var best: GameObject? = nil
        var bestDist = Double.infinity

        for obj in world.objects {
            guard obj.kind == .structure && obj.strength > 0 else { continue }
            guard obj.house != house && obj.house != .neutral else { continue }

            let dx = obj.worldX - centerX
            let dy = obj.worldY - centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                best = obj
            }
        }
        return best
    }

    /// Find nearest enemy unit
    func findNearestEnemyUnit() -> GameObject? {
        guard let world = session.world else { return nil }
        var best: GameObject? = nil
        var bestDist = Double.infinity

        for obj in world.objects {
            guard (obj.kind == .unit || obj.kind == .infantry) && obj.strength > 0 else { continue }
            guard obj.house != house && obj.house != .neutral else { continue }

            let dx = obj.worldX - centerX
            let dy = obj.worldY - centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                best = obj
            }
        }
        return best
    }

    /// Find nearest civilian
    func findNearestCivilian() -> GameObject? {
        guard let world = session.world else { return nil }
        var best: GameObject? = nil
        var bestDist = Double.infinity

        for obj in world.objects {
            guard obj.strength > 0 else { continue }
            guard obj.house == .neutral else { continue }

            let dx = obj.worldX - centerX
            let dy = obj.worldY - centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                best = obj
            }
        }
        return best
    }

    /// Find nearest enemy of any type
    func findNearestEnemyAny() -> GameObject? {
        guard let world = session.world else { return nil }
        var best: GameObject? = nil
        var bestDist = Double.infinity

        for obj in world.objects {
            guard obj.strength > 0 else { continue }
            guard obj.house != house && obj.house != .neutral else { continue }

            let dx = obj.worldX - centerX
            let dy = obj.worldY - centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                best = obj
            }
        }
        return best
    }

    /// Find regroup position (nearest friendly building)
    func findRegroupPosition() -> (x: Double, y: Double)? {
        guard let world = session.world else { return nil }
        var bestDist = Double.infinity
        var bestPos: (x: Double, y: Double)? = nil

        for obj in world.objects {
            guard obj.kind == .structure && obj.house == house && obj.strength > 0 else { continue }

            let dx = obj.worldX - centerX
            let dy = obj.worldY - centerY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestPos = (x: obj.worldX, y: obj.worldY)
            }
        }
        return bestPos
    }

    /// Dissolve team: release all members back to individual control
    func dissolve() {
        guard let world = session.world else { return }

        for id in members {
            if let obj = world.findObject(id: id), obj.strength > 0 {
                // Set to guard if idle
                if obj.mission == .move {
                    obj.mission = .guard_
                    obj.moveTargetX = nil
                    obj.moveTargetY = nil
                }
            }
        }
        members.removeAll()
    }
}

// MARK: - Team Manager

// MARK: - Parse Team Types from Scenario INI

func parseTeamTypes(from ini: INIFile) {
    session.teamTypes.removeAll()

    // [TeamTypes] section: key=name, value=full definition string
    for entry in ini.entries("TEAMTYPES") {
        let name = entry.key
        let parts = entry.value.components(separatedBy: ",")
        guard parts.count >= 4 else { continue }

        let house = House.from(parts[0].trimmingCharacters(in: .whitespaces))
        let teamType = TeamType(name: name, house: house)

        // Parse flags: RoundAbout, Learning, Suicide, Autocreate, Mercenary.
        // Token order mirrors TeamTypeClass::Read_INI (TEAMTYPE.CPP:301-321):
        // House,RoundAbout,Learning,Suicide,Autocreate,Mercenary,RecruitPriority,...
        if parts.count > 1 { teamType.isRoundAbout = parts[1].trimmingCharacters(in: .whitespaces) == "1" }
        if parts.count > 2 { teamType.isLearning = parts[2].trimmingCharacters(in: .whitespaces) == "1" }
        if parts.count > 3 { teamType.isSuicide = parts[3].trimmingCharacters(in: .whitespaces) == "1" }
        // parts[4] = IsAutocreate (TEAMTYPE.CPP:316) — was previously dropped as
        // "Spy (unused)", which left AI autocreate attack waves unable to form.
        if parts.count > 4 { teamType.isAutocreate = parts[4].trimmingCharacters(in: .whitespaces) == "1" }
        if parts.count > 5 { teamType.isMercenary = parts[5].trimmingCharacters(in: .whitespaces) == "1" }

        // RecruitPriority, MaxAllowed, InitNum, Fear
        if parts.count > 6 { teamType.recruitPriority = Int(parts[6].trimmingCharacters(in: .whitespaces)) ?? 7 }
        if parts.count > 7 { teamType.maxAllowed = Int(parts[7].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if parts.count > 8 { teamType.initNum = Int(parts[8].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if parts.count > 9 { teamType.fear = Int(parts[9].trimmingCharacters(in: .whitespaces)) ?? 0 }

        // ClassCount followed by Class:Num pairs
        var idx = 10
        if parts.count > idx {
            let classCount = Int(parts[idx].trimmingCharacters(in: .whitespaces)) ?? 0
            idx += 1

            for _ in 0..<classCount {
                guard idx < parts.count else { break }
                let classEntry = parts[idx].trimmingCharacters(in: .whitespaces)
                let classParts = classEntry.components(separatedBy: ":")
                if classParts.count >= 2 {
                    let typeName = classParts[0].trimmingCharacters(in: .whitespaces)
                    let count = Int(classParts[1].trimmingCharacters(in: .whitespaces)) ?? 1
                    let kind: ObjectKind
                    if InfantryType.from(iniName: typeName.uppercased()) != nil {
                        kind = .infantry
                    } else {
                        kind = .unit
                    }
                    teamType.classSlots.append(TeamClassSlot(kind: kind, typeName: typeName, desiredCount: count))
                }
                idx += 1
            }
        }

        // MissionCount followed by Mission:Arg pairs
        if idx < parts.count {
            let missionCount = Int(parts[idx].trimmingCharacters(in: .whitespaces)) ?? 0
            idx += 1

            for _ in 0..<missionCount {
                guard idx < parts.count else { break }
                let missionEntry = parts[idx].trimmingCharacters(in: .whitespaces)
                let missionParts = missionEntry.components(separatedBy: ":")
                if missionParts.count >= 2 {
                    let missionName = missionParts[0].trimmingCharacters(in: .whitespaces)
                    let arg = Int(missionParts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                    if let tm = TeamMission.from(missionName) {
                        teamType.missionList.append(TeamMissionEntry(mission: tm, argument: arg))
                    }
                }
                idx += 1
            }
        }

        // IsReinforcable, IsPrebuilt (optional trailing fields)
        if idx < parts.count {
            teamType.isReinforcable = parts[idx].trimmingCharacters(in: .whitespaces) == "1"
            idx += 1
        }
        if idx < parts.count {
            teamType.isPrebuilt = parts[idx].trimmingCharacters(in: .whitespaces) == "1"
        }

        session.teamTypes.append(teamType)
    }

    print("TeamTypes: Parsed \(session.teamTypes.count) team types")
    for tt in session.teamTypes {
        print("  \(tt.name): \(tt.house.rawValue), \(tt.classSlots.count) classes, \(tt.missionList.count) missions")
    }
}

// MARK: - Create Team Instance

/// Create an active team from a team type definition. `bypassCap` skips the
/// MaxAllowed check (the C++ `ScenarioInit++` path used by the alerted burst).
func createTeam(type: TeamType, bypassCap: Bool = false) -> ActiveTeam? {
    // Check max allowed (0 = unlimited here — note this differs from
    // decideSuggestedTeam, where MaxAllowed==0 means "never suggested").
    if !bypassCap && type.maxAllowed > 0 {
        let currentCount = session.activeTeams.filter { $0.type.name == type.name }.count
        if currentCount >= type.maxAllowed { return nil }
    }

    let team = ActiveTeam(type: type)
    session.activeTeams.append(team)
    return team
}

/// Create a team and recruit members
func createAndRecruitTeam(type: TeamType) -> ActiveTeam? {
    guard let team = createTeam(type: type) else { return nil }
    team.recruitMembers()
    return team
}

/// Like `createAndRecruitTeam` but ignores the MaxAllowed cap (alerted burst).
func forceCreateAndRecruitTeam(type: TeamType) -> ActiveTeam? {
    guard let team = createTeam(type: type, bypassCap: true) else { return nil }
    team.recruitMembers()
    return team
}

// MARK: - Team Membership Helpers

/// Check if an object is in any team
func isInTeam(_ objectId: Int) -> Bool {
    return session.activeTeams.contains { $0.members.contains(objectId) }
}

/// Get the team an object belongs to
func teamForObject(_ objectId: Int) -> ActiveTeam? {
    return session.activeTeams.first { $0.members.contains(objectId) }
}

// MARK: - Team AI Tick

/// Main team AI processing — called every game tick
func tickTeams() {
    guard let world = session.world else { return }

    // Only process teams every 4 ticks for performance
    guard world.tickCount % 4 == 0 else { return }

    // Remove dead members from all teams
    for team in session.activeTeams {
        team.members.removeAll { id in
            !world.objects.contains { $0.id == id && $0.strength > 0 }
        }
    }

    for team in session.activeTeams {
        team.tick()
    }

    // Remove empty teams that have been activated
    session.activeTeams.removeAll { $0.members.isEmpty && $0.isHasBeen }
}

// MARK: - Waypoint Lookup

/// Get cell number for a waypoint index
func waypointCell(_ index: Int) -> Int? {
    return session.scenarioWaypoints[index]
}

/// Global waypoint storage (populated during scenario load)

// MARK: - Trigger Integration

/// Create a team from trigger action (CREATE_TEAM)
func triggerCreateTeam(named name: String) {
    guard let type = session.teamTypes.first(where: { $0.name == name }) else {
        print("TeamAI: Cannot create team '\(name)' — type not found")
        return
    }

    if let team = createAndRecruitTeam(type: type) {
        print("TeamAI: Created team '\(name)' with \(team.memberCount) members")
    }
}

/// Destroy all instances of a team type
func triggerDestroyTeam(named name: String) {
    for team in session.activeTeams where team.type.name == name {
        team.dissolve()
    }
    session.activeTeams.removeAll { $0.type.name == name }
    print("TeamAI: Destroyed all teams named '\(name)'")
}
