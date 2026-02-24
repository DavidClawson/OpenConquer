import Foundation

// MARK: - Trigger System
// Ported from Vanilla Conquer trigger.h/trigger.cpp

// MARK: - Trigger Event Types

enum TriggerEvent: Int {
    case none = 0
    case playerEntered = 1
    case discovered = 2
    case attacked = 3
    case destroyed = 4
    case any = 5
    case houseDiscovered = 6
    case unitsDestroyed = 7
    case buildingsDestroyed = 8
    case allDestroyed = 9
    case credits = 10
    case time = 11
    case nBuildingsDestroyed = 12
    case nUnitsDestroyed = 13
    case noFactories = 14
    case civEvacuated = 15
    case builtIt = 16

    static func from(_ name: String) -> TriggerEvent {
        let eventNames: [(String, TriggerEvent)] = [
            ("None", .none),
            ("Player Enters", .playerEntered),
            ("Discovered", .discovered),
            ("Attacked", .attacked),
            ("Destroyed", .destroyed),
            ("Any", .any),
            ("House Discov.", .houseDiscovered),
            ("Units Destr.", .unitsDestroyed),
            ("Bldgs Destr.", .buildingsDestroyed),
            ("All Destr.", .allDestroyed),
            ("Credits", .credits),
            ("Time", .time),
            ("# Bldgs Dstr.", .nBuildingsDestroyed),
            ("# Units Dstr.", .nUnitsDestroyed),
            ("No Factories", .noFactories),
            ("Civ. Evac.", .civEvacuated),
            ("Built It", .builtIt),
        ]
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for (str, evt) in eventNames {
            if str.caseInsensitiveCompare(trimmed) == .orderedSame {
                return evt
            }
        }
        return .none
    }
}

// MARK: - Trigger Action Types

enum TriggerAction: Int {
    case none = -1
    case win = 0
    case lose = 1
    case beginProduction = 2
    case createTeam = 3
    case destroyTeam = 4
    case allHunt = 5
    case reinforcements = 6
    case dz = 7
    case airstrike = 8
    case nuke = 9
    case ionCannon = 10
    case destroyXXXX = 11
    case destroyYYYY = 12
    case destroyZZZZ = 13
    case autocreate = 14
    case winLose = 15
    case allowWin = 16

    static func from(_ name: String) -> TriggerAction {
        let actionNames: [(String, TriggerAction)] = [
            ("None", .none),
            ("Win", .win),
            ("Lose", .lose),
            ("Production", .beginProduction),
            ("Create Team", .createTeam),
            ("Dstry Teams", .destroyTeam),
            ("All to Hunt", .allHunt),
            ("Reinforce.", .reinforcements),
            ("DZ at 'Z'", .dz),
            ("Airstrike", .airstrike),
            ("Nuclear Missile", .nuke),
            ("Ion Cannon", .ionCannon),
            ("Dstry Trig 'XXXX'", .destroyXXXX),
            ("Dstry Trig 'YYYY'", .destroyYYYY),
            ("Dstry Trig 'ZZZZ'", .destroyZZZZ),
            ("Autocreate", .autocreate),
            ("Cap=Win/Des=Lose", .winLose),
            ("Allow Win", .allowWin),
        ]
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        for (str, act) in actionNames {
            if str.caseInsensitiveCompare(trimmed) == .orderedSame {
                return act
            }
        }
        return .none
    }
}

// MARK: - Trigger Persistence

enum TriggerPersistence: Int {
    case volatile = 0         // Fire once, then remove
    case semiPersistent = 1   // Fire when all attached objects trigger
    case persistent = 2       // Never auto-remove
}

// MARK: - Game Trigger

class GameTrigger {
    let name: String
    let event: TriggerEvent
    let action: TriggerAction
    let house: House
    let teamName: String?
    let persistence: TriggerPersistence
    var data: Int               // Event-specific: credits threshold, time (in ticks), count
    let dataCopy: Int           // Original data value for resetting
    var attachCount: Int = 0
    var isActive: Bool = true

    init(name: String, event: TriggerEvent, action: TriggerAction,
         house: House, teamName: String?, persistence: TriggerPersistence, data: Int) {
        self.name = name
        self.event = event
        self.action = action
        self.house = house
        self.teamName = teamName
        self.persistence = persistence
        // Time events store data in minutes; convert to ticks (15 ticks/sec * 60 sec)
        if event == .time {
            self.data = data * 15 * 60
        } else {
            self.data = data
        }
        self.dataCopy = self.data
    }
}

// MARK: - Trigger Manager

// session.gameTriggers, session.triggerWinState, session.allowWinFlag -- now in session

enum TriggerWinState {
    case playing
    case won
    case lost
}

/// Parse triggers from scenario INI data
func parseTriggers(from ini: INIFile) {
    session.gameTriggers.removeAll()
    session.triggerWinState = .playing
    session.allowWinFlag = false

    // [Triggers] section: TriggerName = EventName,ActionName,Data,HouseName,TeamName,IsPersistent
    for entry in ini.entries("Triggers") {
        let name = entry.key.trimmingCharacters(in: .whitespaces)
        let parts = entry.value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { continue }

        let event = TriggerEvent.from(parts[0])
        let action = TriggerAction.from(parts[1])
        let data = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
        let houseName = parts.count > 3 ? parts[3] : "None"
        let teamName = parts.count > 4 && parts[4] != "None" ? parts[4] : nil
        let persistVal = parts.count > 5 ? Int(parts[5]) ?? 0 : 0
        let persistence = TriggerPersistence(rawValue: persistVal) ?? .volatile

        let house = House.from(houseName)

        let trigger = GameTrigger(
            name: name, event: event, action: action,
            house: house, teamName: teamName,
            persistence: persistence, data: data
        )
        session.gameTriggers.append(trigger)
    }

    // Count attachments for each trigger (objects + cells referencing it)
    if let scenario = scenarioData {
        for trigger in session.gameTriggers {
            var count = 0
            for s in scenario.structures {
                if s.trigger.caseInsensitiveCompare(trigger.name) == .orderedSame && s.trigger != "None" { count += 1 }
            }
            for u in scenario.units {
                if u.trigger.caseInsensitiveCompare(trigger.name) == .orderedSame && u.trigger != "None" { count += 1 }
            }
            for inf in scenario.infantry {
                if inf.trigger.caseInsensitiveCompare(trigger.name) == .orderedSame && inf.trigger != "None" { count += 1 }
            }
            for ct in scenario.cellTriggers {
                if ct.triggerName.caseInsensitiveCompare(trigger.name) == .orderedSame { count += 1 }
            }
            trigger.attachCount = count
        }
    }

    print("GameTrigger: Loaded \(session.gameTriggers.count) triggers")
}

// MARK: - Trigger Evaluation

/// Tick all house-based triggers each game tick
func tickTriggers() {
    guard let world = session.world else { return }
    guard session.triggerWinState == .playing else { return }

    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }

        switch trigger.event {
        case .time:
            // Countdown timer
            if trigger.data > 0 {
                trigger.data -= 1
                if trigger.data <= 0 {
                    fireTrigger(trigger)
                    // Reset for persistent triggers
                    if trigger.persistence == .persistent {
                        trigger.data = trigger.dataCopy
                    }
                }
            }

        case .allDestroyed:
            // All units and buildings of the specified house destroyed
            let house = trigger.house
            let hasUnits = world.objects.contains { $0.house == house && $0.strength > 0 && $0.kind != .structure }
            let hasBuildings = world.objects.contains { $0.house == house && $0.strength > 0 && $0.kind == .structure }
            if !hasUnits && !hasBuildings {
                fireTrigger(trigger)
            }

        case .unitsDestroyed:
            // All units of the specified house destroyed
            let house = trigger.house
            let hasUnits = world.objects.contains { $0.house == house && $0.strength > 0 &&
                ($0.kind == .unit || $0.kind == .infantry) }
            if !hasUnits {
                fireTrigger(trigger)
            }

        case .buildingsDestroyed:
            // All buildings of the specified house destroyed
            let house = trigger.house
            let hasBuildings = world.objects.contains { $0.house == house && $0.strength > 0 && $0.kind == .structure }
            if !hasBuildings {
                fireTrigger(trigger)
            }

        case .noFactories:
            // No factories left for house
            let house = trigger.house
            let hasFactory = world.objects.contains { $0.house == house && $0.strength > 0 &&
                $0.kind == .structure && ["WEAP", "FACT", "AFLD", "HAND", "PYLE"].contains($0.typeName.uppercased()) }
            if !hasFactory {
                fireTrigger(trigger)
            }

        case .credits:
            // Credits threshold reached
            if session.sidebarCredits >= trigger.data {
                fireTrigger(trigger)
            }

        default:
            break  // Object/cell events are handled by springTrigger calls
        }
    }
}

/// Spring a trigger by name (for object/cell events)
func springTrigger(named triggerName: String, event: TriggerEvent) {
    guard session.triggerWinState == .playing else { return }

    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }
        guard trigger.name.caseInsensitiveCompare(triggerName) == .orderedSame else { continue }
        guard trigger.event == event || trigger.event == .any else { continue }

        if trigger.persistence == .semiPersistent {
            trigger.attachCount -= 1
            if trigger.attachCount <= 0 {
                fireTrigger(trigger)
            }
        } else {
            fireTrigger(trigger)
        }
    }
}

/// Spring a cell trigger when a player unit enters a cell
func checkCellTriggers(cell: Int, enteringObject: GameObject) {
    guard let scenario = scenarioData else { return }
    guard enteringObject.house == session.world?.playerHouse else { return }

    for ct in scenario.cellTriggers {
        if ct.cell == cell {
            springTrigger(named: ct.triggerName, event: .playerEntered)
        }
    }
}

// MARK: - Trigger Actions

func fireTrigger(_ trigger: GameTrigger) {
    guard trigger.isActive else { return }

    print("Trigger '\(trigger.name)' fired: action=\(trigger.action)")

    // Deactivate volatile triggers
    if trigger.persistence == .volatile {
        trigger.isActive = false
    }

    switch trigger.action {
    case .win:
        print(">>> MISSION WON <<<")
        session.triggerWinState = .won

    case .lose:
        print(">>> MISSION LOST <<<")
        session.triggerWinState = .lost

    case .allHunt:
        // Send all enemy units to hunt mode
        guard let world = session.world else { return }
        for obj in world.objects {
            if obj.house != world.playerHouse && obj.house != .neutral && obj.strength > 0 {
                if obj.kind != .structure {
                    obj.mission = .hunt
                }
            }
        }

    case .beginProduction:
        // Signal AI to start production (stub for future M7)
        print("Trigger: AI begin production")

    case .createTeam:
        if let teamName = trigger.teamName {
            triggerCreateTeam(named: teamName)
        }

    case .destroyTeam:
        if let teamName = trigger.teamName {
            triggerDestroyTeam(named: teamName)
        }

    case .reinforcements:
        if let teamName = trigger.teamName {
            spawnReinforcements(teamName: teamName)
        }

    case .airstrike:
        session.playerAirStrike.enable()
        session.playerAirStrike.forceCharge()
        print("Trigger: Airstrike enabled and ready")

    case .nuke:
        session.playerNukeStrike.enable()
        session.playerNukeStrike.forceCharge()
        print("Trigger: Nuclear strike enabled and ready")

    case .ionCannon:
        session.playerIonCannon.enable()
        session.playerIonCannon.forceCharge()
        print("Trigger: Ion cannon enabled and ready")

    case .destroyXXXX:
        destroyTriggerNamed("XXXX")

    case .destroyYYYY:
        destroyTriggerNamed("YYYY")

    case .destroyZZZZ:
        destroyTriggerNamed("ZZZZ")

    case .autocreate:
        print("Trigger: Autocreate enabled")

    case .winLose:
        // Cap=Win/Des=Lose — handled via object events
        print("Trigger: Win/Lose condition set")

    case .allowWin:
        session.allowWinFlag = true
        print("Trigger: Allow win flag set")

    case .dz:
        print("Trigger: Drop zone flare")

    case .none:
        break
    }
}

/// Deactivate a trigger by name
func destroyTriggerNamed(_ name: String) {
    for trigger in session.gameTriggers {
        if trigger.name.caseInsensitiveCompare(name) == .orderedSame {
            trigger.isActive = false
            print("Trigger '\(name)' destroyed by another trigger")
        }
    }
}

// MARK: - Reinforcements

/// Spawn reinforcements for a team type — delegates to the full reinforcement system.
/// Supports C17 cargo plane fly-in delivery, APC transport, or direct ground spawning.
func spawnReinforcements(teamName: String) {
    doReinforcements(teamName: teamName)
}
