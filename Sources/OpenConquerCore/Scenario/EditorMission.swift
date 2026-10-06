import Foundation
import OpenConquerAssets

// MARK: - The mission editor's model of a mission's rules
//
// Everything about a scenario that isn't an object on the map: who the player
// is, each house's money and reinforcement edge, the tech level and the
// mission's changes to it, the triggers and team types (which is where the
// win and lose conditions and the reinforcements live), and the Tier-1
// per-object flags. Kept as the strings the INI holds, so a section the
// editor didn't touch writes back exactly as it was read; the side panel
// turns them into plain words.

/// One [Triggers] line: `Name=Event,Action,Data,House,Team,Persistence`.
package struct EditorTrigger: Equatable {
    package var name: String
    package var event: String
    package var action: String
    package var data: Int
    package var house: String
    package var team: String
    package var persistence: Int

    package init(name: String, event: String, action: String, data: Int = 0,
                 house: String, team: String = "None", persistence: Int = 0) {
        self.name = name
        self.event = event
        self.action = action
        self.data = data
        self.house = house
        self.team = team
        self.persistence = persistence
    }

    package var eventType: TriggerEvent { TriggerEvent.from(event) }
    package var actionType: TriggerAction { TriggerAction.from(action) }
}

package struct EditorTeamMember: Equatable {
    package var type: String
    package var count: Int

    package init(type: String, count: Int) {
        self.type = type
        self.count = count
    }
}

package struct EditorTeamMission: Equatable {
    package var mission: String
    package var argument: Int

    package init(mission: String, argument: Int) {
        self.mission = mission
        self.argument = argument
    }
}

/// One [TeamTypes] line: House, nine flag/number fields (RoundAbout, Learning,
/// Suicide, Autocreate, Mercenary, RecruitPriority, MaxAllowed, InitNum,
/// Fear), the members, the missions, then IsReinforcable and IsPrebuilt.
package struct EditorTeam: Equatable {
    package var name: String
    package var house: String
    package var fields: [String]
    package var members: [EditorTeamMember]
    package var missions: [EditorTeamMission]
    package var trailing: [String]

    /// A reinforcement team as the campaign writes them (SCG01EA's GDIR1).
    package init(name: String, house: String, members: [EditorTeamMember], missions: [EditorTeamMission] = []) {
        self.name = name
        self.house = house
        fields = ["0", "0", "0", "0", "0", "7", "3", "0", "0"]
        self.members = members
        self.missions = missions
        trailing = ["1", "1"]
    }

    init(name: String, value: String) {
        let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        self.name = name
        house = parts.first ?? "None"
        var i = 1
        fields = []
        while i < 10 && i < parts.count { fields.append(parts[i]); i += 1 }
        members = []
        missions = []
        if i < parts.count {
            let n = Int(parts[i]) ?? 0
            i += 1
            for _ in 0..<n where i < parts.count {
                let mp = parts[i].components(separatedBy: ":")
                members.append(EditorTeamMember(type: mp[0], count: mp.count > 1 ? Int(mp[1]) ?? 1 : 1))
                i += 1
            }
        }
        if i < parts.count {
            let n = Int(parts[i]) ?? 0
            i += 1
            for _ in 0..<n where i < parts.count {
                let mp = parts[i].components(separatedBy: ":")
                missions.append(EditorTeamMission(mission: mp[0], argument: mp.count > 1 ? Int(mp[1]) ?? 0 : 0))
                i += 1
            }
        }
        trailing = i < parts.count ? Array(parts[i...]) : []
    }

    package var value: String {
        var parts = [house] + fields
        parts.append(String(members.count))
        parts += members.map { "\($0.type):\($0.count)" }
        parts.append(String(missions.count))
        parts += missions.map { "\($0.mission):\($0.argument)" }
        return (parts + trailing).joined(separator: ",")
    }
}

/// How a reinforcement arrives, which the game decides from the team's
/// members (REINF.CPP): a hovercraft lands on a beach, a Chinook or cargo
/// plane flies in, anything else drives in from the house's edge.
package enum ReinforcementTransport: String, CaseIterable {
    case none = ""
    case hovercraft = "LST"
    case chinook = "TRAN"
    case cargoPlane = "C17"

    package var label: String {
        switch self {
        case .none: return "Drive in"
        case .hovercraft: return "Hovercraft"
        case .chinook: return "Chinook"
        case .cargoPlane: return "Cargo plane"
        }
    }

    package static func of(_ team: EditorTeam) -> ReinforcementTransport {
        for t in allCases where t != .none {
            if team.members.contains(where: { $0.type.uppercased() == t.rawValue }) { return t }
        }
        return .none
    }
}

package struct MissionState: Equatable {
    package var player: House
    /// Starting money per house, in credits (the INI stores hundreds).
    package var credits: [House: Int]
    package var buildLevel: Int
    package var edges: [House: MapEdge]
    package var allow: Set<String>
    package var deny: Set<String>
    package var triggers: [EditorTrigger]
    package var teams: [EditorTeam]
    /// [ObjectFlags]: cell -> "Invulnerable", "MustSurvive" (Tier-1).
    package var objectFlags: [Int: Set<String>]

    /// The houses whose settings the editor shows.
    package static let sides: [House] = [.goodGuy, .badGuy]

    init(ini: INIFile, name: String) {
        player = scenarioPlayerHouse(ini, name: name)
        credits = [:]
        edges = [:]
        for house in House.allCases where ini.hasSection(house.rawValue) {
            credits[house] = ini.int(house.rawValue, "Credits", default: 0) * 100
            if let edge = MapEdge.from(ini.string(house.rawValue, "Edge")) { edges[house] = edge }
        }
        buildLevel = ini.int("Basic", "BuildLevel", default: 1)
        (allow, deny) = parseBuildables(ini)
        triggers = ini.entries("Triggers").map { entry in
            let p = entry.value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            func at(_ i: Int, _ d: String) -> String { i < p.count ? p[i] : d }
            return EditorTrigger(name: entry.key, event: at(0, "None"), action: at(1, "None"),
                                 data: Int(at(2, "0")) ?? 0, house: at(3, "None"), team: at(4, "None"),
                                 persistence: Int(at(5, "0")) ?? 0)
        }
        teams = ini.entries("TeamTypes").map { EditorTeam(name: $0.key, value: $0.value) }
        objectFlags = [:]
        for entry in ini.entries("ObjectFlags") {
            guard let cell = Int(entry.key) else { continue }
            objectFlags[cell] = Set(entry.value.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        }
    }

    /// Writes the parts that differ from `old` into `ini`.
    func write(into ini: inout INIFile, changedFrom old: MissionState) {
        if player != old.player { ini.setValue("Basic", "Player", player.rawValue) }
        if buildLevel != old.buildLevel { ini.setValue("Basic", "BuildLevel", String(buildLevel)) }
        for house in House.allCases {
            if credits[house] != old.credits[house], let c = credits[house] {
                ini.setValue(house.rawValue, "Credits", String(c / 100))
            }
            if edges[house] != old.edges[house], let e = edges[house] {
                ini.setValue(house.rawValue, "Edge", e.rawValue)
            }
        }
        if allow != old.allow || deny != old.deny {
            var entries: [(key: String, value: String)] = []
            if !allow.isEmpty { entries.append(("Allow", allow.sorted().joined(separator: ","))) }
            if !deny.isEmpty { entries.append(("Deny", deny.sorted().joined(separator: ","))) }
            if entries.isEmpty { ini.removeSection("Buildables") } else { ini.setEntries("Buildables", entries) }
        }
        if triggers != old.triggers {
            ini.setEntries("Triggers", triggers.map {
                (key: $0.name, value: "\($0.event),\($0.action),\($0.data),\($0.house),\($0.team),\($0.persistence)")
            })
        }
        if teams != old.teams {
            ini.setEntries("TeamTypes", teams.map { (key: $0.name, value: $0.value) })
        }
        if objectFlags != old.objectFlags {
            let entries = objectFlags.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }
                .map { (key: String($0.key), value: $0.value.sorted().joined(separator: ",")) }
            if entries.isEmpty { ini.removeSection("ObjectFlags") } else { ini.setEntries("ObjectFlags", entries) }
        }
    }

    // MARK: Names

    /// A free trigger name: four characters, the original's limit (TRIGGER.H).
    package func newTriggerName(_ prefix: String) -> String {
        let p = String(prefix.uppercased().prefix(2))
        for i in 1..<100 {
            let name = p + String(format: "%02d", i)
            if !triggers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return name }
        }
        return p + "99"
    }

    /// A free team type name: eight characters at most (TYPE.H IniName).
    package func newTeamName(_ prefix: String) -> String {
        let p = String(prefix.uppercased().prefix(5))
        for i in 1..<1000 {
            let name = p + String(i)
            if !teams.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return name }
        }
        return p + "X"
    }

    package var enemy: House { player == .badGuy ? .goodGuy : .badGuy }

    // MARK: Goals

    /// Triggers that decide the mission: their action wins or loses it.
    package var goals: [EditorTrigger] {
        triggers.filter { [.win, .lose, .winLose].contains($0.actionType) }
    }

    package mutating func addTrigger(_ trigger: EditorTrigger) {
        triggers.append(trigger)
    }

    package mutating func removeTrigger(named name: String) {
        guard let t = triggers.first(where: { $0.name == name }) else { return }
        triggers.removeAll { $0.name == name }
        // A reinforcement's team goes with it unless another trigger uses it.
        if t.team != "None", !triggers.contains(where: { $0.team == t.team }) {
            teams.removeAll { $0.name == t.team }
        }
    }

    // MARK: Reinforcements

    /// Triggers that send a team in.
    package var reinforcements: [EditorTrigger] {
        triggers.filter { $0.actionType == .reinforcements }
    }

    package func team(named name: String) -> EditorTeam? {
        teams.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    package mutating func updateTeam(_ team: EditorTeam) {
        if let i = teams.firstIndex(where: { $0.name == team.name }) { teams[i] = team }
    }

    package mutating func updateTrigger(_ trigger: EditorTrigger) {
        if let i = triggers.firstIndex(where: { $0.name == trigger.name }) { triggers[i] = trigger }
    }

    /// A team sent in after `tenths` tenths of a minute (the Time event's
    /// unit). An enemy team hunts the player's units once it's in; the
    /// player's waits for orders, as the campaign's do.
    @discardableResult
    package mutating func addReinforcement(house: House, afterTenths tenths: Int,
                                           members: [EditorTeamMember], transport: ReinforcementTransport) -> EditorTrigger {
        let teamName = newTeamName(house == .badGuy ? "NODR" : "GDIR")
        var all = members
        if transport != .none { all.append(EditorTeamMember(type: transport.rawValue, count: 1)) }
        let missions = house == player ? [] : [EditorTeamMission(mission: "Attack Units", argument: 0)]
        teams.append(EditorTeam(name: teamName, house: house.rawValue, members: all, missions: missions))
        let trigger = EditorTrigger(name: newTriggerName("RF"), event: "Time", action: "Reinforce.",
                                    data: tenths, house: house.rawValue, team: teamName)
        triggers.append(trigger)
        return trigger
    }

    // MARK: Object flags

    package func flag(_ name: String, at cell: Int) -> Bool { objectFlags[cell]?.contains(name) ?? false }

    package mutating func setFlag(_ name: String, at cell: Int, _ on: Bool) {
        var set = objectFlags[cell] ?? []
        if on { set.insert(name) } else { set.remove(name) }
        objectFlags[cell] = set.isEmpty ? nil : set
    }

    /// Flags follow an object that moves (they're keyed by cell).
    package mutating func moveFlags(from: Int, to: Int) {
        guard from != to, let set = objectFlags.removeValue(forKey: from) else { return }
        objectFlags[to] = set
    }
}

// MARK: - Words for the side panel

extension EditorTrigger {
    /// "2:30" for a Time trigger's data (tenths of a minute).
    package static func clock(tenths: Int) -> String {
        let seconds = tenths * 6
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    package var houseName: String { Self.sideName(House.from(house)) }

    package static func sideName(_ house: House) -> String {
        switch house {
        case .goodGuy: return "GDI"
        case .badGuy: return "Nod"
        case .neutral: return "Civilians"
        default: return house.rawValue
        }
    }

    /// When it happens, in words.
    package var when: String {
        switch eventType {
        case .time: return "after \(Self.clock(tenths: data))"
        case .allDestroyed: return "all \(houseName) is destroyed"
        case .unitsDestroyed: return "all \(houseName) units are destroyed"
        case .buildingsDestroyed: return "all \(houseName) buildings are destroyed"
        case .destroyed:
            // Semi-persistent waits for every object carrying it (TRIGGER.CPP).
            return persistence == 1 ? "all marked targets are destroyed" : "a marked object is destroyed"
        case .playerEntered: return "\(houseName) reaches the spot"
        case .discovered: return "it is found"
        case .attacked: return "it is attacked"
        case .houseDiscovered: return "\(houseName) is found"
        case .credits: return "\(houseName) has \(data * 100) credits"
        case .nBuildingsDestroyed: return "\(data) \(houseName) buildings are lost"
        case .nUnitsDestroyed: return "\(data) \(houseName) units are lost"
        case .noFactories: return "\(houseName) has no factories"
        case .civEvacuated: return "the civilians are evacuated"
        case .builtIt: return "\(houseName) builds it"
        case .enteredRegion: return "\(houseName) enters the region"
        case .leftRegion: return "\(houseName) leaves the region"
        case .any: return "anything happens to it"
        case .none: return "never"
        }
    }
}
