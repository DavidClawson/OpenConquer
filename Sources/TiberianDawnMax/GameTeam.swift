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

        // Parse flags: RoundAbout, Learning, Suicide, Spy(unused), Mercenary
        if parts.count > 1 { teamType.isRoundAbout = parts[1].trimmingCharacters(in: .whitespaces) == "1" }
        if parts.count > 2 { teamType.isLearning = parts[2].trimmingCharacters(in: .whitespaces) == "1" }
        if parts.count > 3 { teamType.isSuicide = parts[3].trimmingCharacters(in: .whitespaces) == "1" }
        // parts[4] = Spy (unused in TD)
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

/// Create an active team from a team type definition
func createTeam(type: TeamType) -> ActiveTeam? {
    // Check max allowed
    if type.maxAllowed > 0 {
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
    recruitMembers(team)
    return team
}

// MARK: - Recruitment

/// Recruit members for a team from available units
func recruitMembers(_ team: ActiveTeam) {
    guard let world = session.world else { return }

    for (slotIndex, slot) in team.type.classSlots.enumerated() {
        let currentCount = countMembersOfSlot(team, slotIndex: slotIndex)
        let needed = slot.desiredCount - currentCount
        guard needed > 0 else { continue }

        var recruited = 0
        for obj in world.objects {
            guard obj.house == team.house else { continue }
            guard obj.strength > 0 else { continue }
            guard !obj.isInLimbo else { continue }
            guard obj.typeName.uppercased() == slot.typeName.uppercased() else { continue }

            // Don't recruit from higher-priority teams
            if isInTeam(obj.id) {
                if let existingTeam = teamForObject(obj.id) {
                    if existingTeam.type.recruitPriority >= team.type.recruitPriority {
                        continue
                    }
                    // Remove from lower priority team
                    removeFromTeam(obj.id, team: existingTeam)
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
            let upper = obj.typeName.uppercased()
            if upper == "HARV" || upper == "MCV" { continue }

            team.members.append(obj.id)
            recruited += 1
            if recruited >= needed { break }
        }
    }

    // Calculate center
    calcTeamCenter(team)
}

/// Count current members matching a particular class slot
func countMembersOfSlot(_ team: ActiveTeam, slotIndex: Int) -> Int {
    guard slotIndex < team.type.classSlots.count else { return 0 }
    let slot = team.type.classSlots[slotIndex]
    guard let world = session.world else { return 0 }

    return team.members.filter { id in
        if let obj = world.findObject(id: id) {
            return obj.strength > 0 && obj.typeName.uppercased() == slot.typeName.uppercased()
        }
        return false
    }.count
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

/// Remove an object from a team
func removeFromTeam(_ objectId: Int, team: ActiveTeam) {
    team.members.removeAll { $0 == objectId }
}

// MARK: - Team Center Calculation

/// Calculate the average position of team members
func calcTeamCenter(_ team: ActiveTeam) {
    guard let world = session.world else { return }
    var x = 0.0, y = 0.0, count = 0

    for id in team.members {
        if let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo {
            x += obj.worldX
            y += obj.worldY
            count += 1
        }
    }

    if count > 0 {
        team.centerX = x / Double(count)
        team.centerY = y / Double(count)
    }
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
        tickTeam(team)
    }

    // Remove empty teams that have been activated
    session.activeTeams.removeAll { $0.members.isEmpty && $0.isHasBeen }
}

/// Process a single team's AI
func tickTeam(_ team: ActiveTeam) {
    guard session.world != nil else { return }

    // Suspension check
    if team.isSuspended {
        if team.suspendTimer > 0 {
            team.suspendTimer -= 4
            return
        }
        team.isSuspended = false
    }

    // Recalculate center
    calcTeamCenter(team)

    // Strength calculation
    let current = team.memberCount
    let desired = team.desiredCount

    team.isFullStrength = (current >= desired)
    if team.type.isReinforcable {
        team.isUnderStrength = (current <= desired / 3) && current < desired
    } else {
        team.isUnderStrength = !team.isHasBeen && current < desired
    }

    // Delete empty human teams that were activated
    if current == 0 && team.isHasBeen {
        return  // Will be cleaned up by tickTeams
    }

    // Regroup if understrength while executing missions
    if team.isMoving && team.isUnderStrength {
        team.isMoving = false
        team.currentMission = -1

        // Move to nearest friendly building to regroup
        if let regroupPos = findRegroupPosition(team) {
            coordinateMove(team, targetX: regroupPos.x, targetY: regroupPos.y)
        }
        return
    }

    // Launch mission when full strength (or forced)
    if !team.isMoving && team.isFullStrength {
        team.isMoving = true
        team.isHasBeen = true
        team.isUnderStrength = false
        team.currentMission = -1
        team.isNextMission = true
    }

    // Recruit if not full strength
    if !team.isFullStrength && team.type.isReinforcable {
        recruitMembers(team)
    }

    // Advance to next mission
    if team.isMoving && team.isNextMission {
        team.isNextMission = false
        team.currentMission += 1

        if team.currentMission >= team.type.missionList.count {
            // Mission list exhausted — dissolve team
            dissolveTeam(team)
            return
        }

        let missionEntry = team.type.missionList[team.currentMission]
        team.missionTimeout = missionEntry.argument * 90  // VC: arg * (TICKS_PER_MINUTE / 10)
        team.target = nil
        team.targetCell = nil

        // Set up mission target based on type
        switch missionEntry.mission {
        case .moveCell:
            team.targetCell = missionEntry.argument
        case .move, .unload:
            // Use waypoint from scenario
            if let cell = waypointCell(missionEntry.argument) {
                team.targetCell = cell
            }
        default:
            break
        }
    }

    // Execute current mission
    guard team.isMoving && !team.isUnderStrength else { return }
    guard team.currentMission >= 0 && team.currentMission < team.type.missionList.count else { return }

    let missionEntry = team.type.missionList[team.currentMission]

    switch missionEntry.mission {
    case .attackBase:
        // Find nearest enemy building
        if team.target == nil {
            if let enemyBuilding = findNearestEnemyBuilding(team) {
                team.target = enemyBuilding.id
            }
        }
        coordinateAttack(team)

    case .attackUnits:
        // Find nearest enemy unit
        if team.target == nil {
            if let enemyUnit = findNearestEnemyUnit(team) {
                team.target = enemyUnit.id
            }
        }
        coordinateAttack(team)

    case .attackCivilians:
        if team.target == nil {
            if let civ = findNearestCivilian(team) {
                team.target = civ.id
            }
        }
        coordinateAttack(team)

    case .rampage, .attackTarcom:
        if team.target == nil {
            if let enemy = findNearestEnemyAny(team) {
                team.target = enemy.id
            }
        }
        coordinateAttack(team)

    case .defendBase:
        if let cell = team.targetCell {
            let pos = cellToPixel(cell)
            coordinateMove(team, targetX: Double(pos.px) + 12.0, targetY: Double(pos.py) + 12.0)
        } else {
            coordinateRegroup(team)
        }

    case .move, .moveCell, .retreat:
        if let cell = team.targetCell {
            let pos = cellToPixel(cell)
            coordinateMove(team, targetX: Double(pos.px) + 12.0, targetY: Double(pos.py) + 12.0)
        } else {
            team.isNextMission = true
        }

    case .guard_:
        coordinateRegroup(team)

    case .loop:
        // Loop back to mission index specified by argument
        team.currentMission = max(0, missionEntry.argument) - 1
        team.isNextMission = true

    case .unload:
        coordinateUnload(team)
    }

    // Mission timeout
    if team.missionTimeout > 0 {
        team.missionTimeout -= 4
        if team.missionTimeout <= 0 {
            switch missionEntry.mission {
            case .attackBase, .attackUnits, .attackCivilians, .rampage, .attackTarcom,
                 .defendBase, .unload, .retreat, .guard_:
                team.isNextMission = true
            default:
                break
            }
        }
    }
}

// MARK: - Team Coordination Functions

/// Coordinate attack: all team members attack the same target
func coordinateAttack(_ team: ActiveTeam) {
    guard let world = session.world else { return }
    guard let targetId = team.target else {
        team.isNextMission = true
        return
    }

    // Verify target is still alive
    guard world.objects.contains(where: { $0.id == targetId && $0.strength > 0 }) else {
        team.target = nil
        team.isNextMission = true
        return
    }

    for id in team.members {
        guard let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo else { continue }

        if obj.mission != .attack || obj.attackTarget != targetId {
            obj.attackTarget = targetId
            obj.mission = .attack
            obj.movePath = []
        }
    }
}

/// Coordinate move: all team members move to same destination
func coordinateMove(_ team: ActiveTeam, targetX: Double, targetY: Double) {
    guard let world = session.world else { return }
    var allArrived = true

    for id in team.members {
        guard let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo else { continue }

        let dx = obj.worldX - targetX
        let dy = obj.worldY - targetY
        let dist = sqrt(dx * dx + dy * dy)

        if dist > teamStrayDistance {
            allArrived = false
            if obj.mission != .move || obj.moveTargetX == nil {
                obj.moveTargetX = targetX + Double.random(in: -24...24)
                obj.moveTargetY = targetY + Double.random(in: -24...24)
                obj.mission = .move
                obj.movePath = []
            }
        }
    }

    if allArrived && team.isMoving {
        team.isNextMission = true
    }
}

/// Coordinate regroup: gather all units to team center
func coordinateRegroup(_ team: ActiveTeam) {
    guard let world = session.world else { return }

    for id in team.members {
        guard let obj = world.findObject(id: id), obj.strength > 0, !obj.isInLimbo else { continue }

        let dx = obj.worldX - team.centerX
        let dy = obj.worldY - team.centerY
        let dist = sqrt(dx * dx + dy * dy)

        if dist > teamStrayDistance {
            if obj.mission != .move || obj.moveTargetX == nil {
                obj.moveTargetX = team.centerX + Double.random(in: -12...12)
                obj.moveTargetY = team.centerY + Double.random(in: -12...12)
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
func coordinateUnload(_ team: ActiveTeam) {
    // Simplified: just advance to next mission since transport cargo not fully implemented
    team.isNextMission = true
}

// MARK: - Team Target Finding

/// Find nearest enemy building for team to attack
func findNearestEnemyBuilding(_ team: ActiveTeam) -> GameObject? {
    guard let world = session.world else { return nil }
    var best: GameObject? = nil
    var bestDist = Double.infinity

    for obj in world.objects {
        guard obj.kind == .structure && obj.strength > 0 else { continue }
        guard obj.house != team.house && obj.house != .neutral else { continue }

        let dx = obj.worldX - team.centerX
        let dy = obj.worldY - team.centerY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            best = obj
        }
    }
    return best
}

/// Find nearest enemy unit
func findNearestEnemyUnit(_ team: ActiveTeam) -> GameObject? {
    guard let world = session.world else { return nil }
    var best: GameObject? = nil
    var bestDist = Double.infinity

    for obj in world.objects {
        guard (obj.kind == .unit || obj.kind == .infantry) && obj.strength > 0 else { continue }
        guard obj.house != team.house && obj.house != .neutral else { continue }

        let dx = obj.worldX - team.centerX
        let dy = obj.worldY - team.centerY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            best = obj
        }
    }
    return best
}

/// Find nearest civilian
func findNearestCivilian(_ team: ActiveTeam) -> GameObject? {
    guard let world = session.world else { return nil }
    var best: GameObject? = nil
    var bestDist = Double.infinity

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard obj.house == .neutral else { continue }

        let dx = obj.worldX - team.centerX
        let dy = obj.worldY - team.centerY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            best = obj
        }
    }
    return best
}

/// Find nearest enemy of any type
func findNearestEnemyAny(_ team: ActiveTeam) -> GameObject? {
    guard let world = session.world else { return nil }
    var best: GameObject? = nil
    var bestDist = Double.infinity

    for obj in world.objects {
        guard obj.strength > 0 else { continue }
        guard obj.house != team.house && obj.house != .neutral else { continue }

        let dx = obj.worldX - team.centerX
        let dy = obj.worldY - team.centerY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            best = obj
        }
    }
    return best
}

/// Find regroup position (nearest friendly building)
func findRegroupPosition(_ team: ActiveTeam) -> (x: Double, y: Double)? {
    guard let world = session.world else { return nil }
    var bestDist = Double.infinity
    var bestPos: (x: Double, y: Double)? = nil

    for obj in world.objects {
        guard obj.kind == .structure && obj.house == team.house && obj.strength > 0 else { continue }

        let dx = obj.worldX - team.centerX
        let dy = obj.worldY - team.centerY
        let dist = sqrt(dx * dx + dy * dy)
        if dist < bestDist {
            bestDist = dist
            bestPos = (x: obj.worldX, y: obj.worldY)
        }
    }
    return bestPos
}

/// Dissolve team: release all members back to individual control
func dissolveTeam(_ team: ActiveTeam) {
    guard let world = session.world else { return }

    for id in team.members {
        if let obj = world.findObject(id: id), obj.strength > 0 {
            // Set to guard if idle
            if obj.mission == .move {
                obj.mission = .guard_
                obj.moveTargetX = nil
                obj.moveTargetY = nil
            }
        }
    }
    team.members.removeAll()
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
        dissolveTeam(team)
    }
    session.activeTeams.removeAll { $0.type.name == name }
    print("TeamAI: Destroyed all teams named '\(name)'")
}
