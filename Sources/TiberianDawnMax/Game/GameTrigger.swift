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
    var data: Int               // Event-specific: credits threshold, time (in game ticks), count
    let dataCopy: Int           // Original data value for resetting
    var attachCount: Int = 0
    var isActive: Bool = true
    /// Tracks which houses have already fired this trigger (for semi-persistent per-side)
    var firedForHouses: Set<House> = []

    init(name: String, event: TriggerEvent, action: TriggerAction,
         house: House, teamName: String?, persistence: TriggerPersistence, data: Int) {
        self.name = name
        self.event = event
        self.action = action
        self.house = house
        self.teamName = teamName
        self.persistence = persistence
        // Time events store data in 1/10th minute intervals (6 sec each); convert to ticks
        if event == .time {
            self.data = data * 15 * 6
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

// MARK: - Waypoint Helpers

/// Convert a waypoint index to world coordinates (center of the cell).
/// Returns nil if the waypoint is not defined in the scenario.
func waypointWorldPos(_ wp: Int) -> (x: Double, y: Double)? {
    guard let cell = session.scenarioWaypoints[wp] else { return nil }
    let pos = cellToPixel(cell)
    return (x: Double(pos.px) + 12.0, y: Double(pos.py) + 12.0)
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
            // Don't fire until the house has actually existed (grace period for reinforcements)
            let house = trigger.house
            let hasAnything = world.objects.contains { $0.house == house && $0.strength > 0 }
            if !hasAnything && world.tickCount > 30 {
                // Verify the house ever had objects (check if any dead objects belonged to this house)
                let everExisted = world.tickCount > 150  // ~10 seconds grace period
                if everExisted {
                    fireTrigger(trigger)
                }
            }

        case .unitsDestroyed:
            // All units of the specified house destroyed
            // Don't fire in the first 10 seconds to allow reinforcements to arrive
            let house = trigger.house
            let hasUnits = world.objects.contains { $0.house == house && $0.strength > 0 &&
                ($0.kind == .unit || $0.kind == .infantry) }
            if !hasUnits && world.tickCount > 150 {
                fireTrigger(trigger)
            }

        case .buildingsDestroyed:
            // All buildings of the specified house destroyed
            let house = trigger.house
            let hasBuildings = world.objects.contains { $0.house == house && $0.strength > 0 && $0.kind == .structure }
            if !hasBuildings && world.tickCount > 30 {
                fireTrigger(trigger)
            }

        case .noFactories:
            // No factories left for house (WEAP, FACT/Construction Yard, AFLD, HAND, PYLE)
            let house = trigger.house
            let hasFactory = world.objects.contains { $0.house == house && $0.strength > 0 &&
                $0.kind == .structure && ["WEAP", "FACT", "AFLD", "HAND", "PYLE"].contains($0.typeName.uppercased()) }
            if !hasFactory && world.tickCount > 30 {
                fireTrigger(trigger)
            }

        case .credits:
            // Credits threshold reached for the trigger's house
            let creditsToCheck: Int
            if trigger.house == world.playerHouse {
                creditsToCheck = session.sidebarCredits
            } else {
                creditsToCheck = getHouseState(trigger.house).credits
            }
            if creditsToCheck >= trigger.data {
                fireTrigger(trigger)
            }

        case .nBuildingsDestroyed:
            // N buildings of the specified house have been destroyed
            // data field holds the count threshold; we decrement it each time a building dies
            // (decrement is done in springTrigger when .destroyed fires for buildings)
            // Alternatively, check the house state's buildingsLost counter
            let houseState = getHouseState(trigger.house)
            if houseState.buildingsLost >= trigger.data && trigger.data > 0 {
                fireTrigger(trigger)
            }

        case .nUnitsDestroyed:
            // N units of the specified house have been destroyed
            let houseState = getHouseState(trigger.house)
            if houseState.unitsLost >= trigger.data && trigger.data > 0 {
                fireTrigger(trigger)
            }

        case .houseDiscovered:
            // Fire when any object of the trigger's house is discovered by the player
            // (visible in the fog of war). Check every ~1 second for performance.
            if world.tickCount % 15 == 0 {
                let house = trigger.house
                let playerDiscovered = world.objects.contains { obj in
                    obj.house == house && obj.strength > 0 && !obj.isInLimbo &&
                    isCellVisible(obj.cell)
                }
                if playerDiscovered {
                    fireTrigger(trigger)
                }
            }

        case .civEvacuated:
            // Civilians evacuated: check if any civilian (neutral house) infantry
            // has reached waypoint 25 (WAYPT_REINF, the standard evac waypoint).
            // In original C&C, this fires when the civilian enters the evacuation point.
            if world.tickCount % 8 == 0 {
                if let evacPos = waypointWorldPos(25) {
                    let evacuated = world.objects.contains { obj in
                        obj.house == .neutral && obj.kind == .infantry &&
                        obj.strength > 0 && !obj.isInLimbo &&
                        abs(obj.worldX - evacPos.x) < 24.0 && abs(obj.worldY - evacPos.y) < 24.0
                    }
                    if evacuated {
                        fireTrigger(trigger)
                    }
                }
            }

        case .builtIt:
            // Handled externally by springTriggerBuiltIt() when a structure is placed
            break

        case .discovered:
            // Object-level discovered: handled by springTrigger from fog checks
            // (when an attached object becomes visible to the player)
            break

        case .playerEntered, .attacked, .destroyed, .any:
            // These are object/cell events handled by springTrigger calls
            break

        case .none:
            break
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

/// Spring a cell trigger when a unit enters a cell.
/// Player units fire .playerEntered; any unit fires triggers with .any event.
func checkCellTriggers(cell: Int, enteringObject: GameObject) {
    guard let scenario = scenarioData else { return }
    let isPlayer = enteringObject.house == session.world?.playerHouse

    for ct in scenario.cellTriggers {
        if ct.cell == cell {
            if isPlayer {
                springTrigger(named: ct.triggerName, event: .playerEntered)
            }
            // Also check for triggers that respond to any unit entering
            for trigger in session.gameTriggers {
                guard trigger.isActive else { continue }
                guard trigger.name.caseInsensitiveCompare(ct.triggerName) == .orderedSame else { continue }
                guard trigger.event == .any else { continue }

                if trigger.persistence == .semiPersistent {
                    trigger.attachCount -= 1
                    if trigger.attachCount <= 0 {
                        fireTrigger(trigger)
                    }
                } else if !isPlayer {
                    // Only fire for non-player if we didn't already fire via springTrigger above
                    fireTrigger(trigger)
                }
            }
        }
    }
}

/// Check if any attached object just became visible to the player (discovered trigger).
/// Called from the game loop after fog updates.
func checkDiscoveredTriggers() {
    guard let world = session.world else { return }
    guard session.triggerWinState == .playing else { return }

    for obj in world.objects {
        guard obj.strength > 0 && !obj.isInLimbo else { continue }
        guard let trigName = obj.triggerName else { continue }
        guard obj.house != world.playerHouse else { continue }
        // Fire discovered trigger if the object's cell is now visible
        if isCellVisible(obj.cell) {
            springTrigger(named: trigName, event: .discovered)
        }
    }
}

/// Called when the player builds/places a structure type.
/// Fires any "Built It" triggers attached to that structure type.
func springTriggerBuiltIt(structureType: String) {
    guard session.triggerWinState == .playing else { return }

    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }
        guard trigger.event == .builtIt else { continue }
        // In original C&C, "Built It" fires for the player's house when any structure is built.
        // The trigger is not attached to a specific type; it fires whenever any structure is placed.
        if let world = session.world, trigger.house == world.playerHouse {
            fireTrigger(trigger)
        }
    }
}

// MARK: - Trigger Actions

func fireTrigger(_ trigger: GameTrigger) {
    guard trigger.isActive else { return }

    print("Trigger '\(trigger.name)' fired: action=\(trigger.action)")

    // Handle persistence modes
    switch trigger.persistence {
    case .volatile:
        // Fire once, then deactivate
        trigger.isActive = false
    case .semiPersistent:
        // Already handled by attachCount decrement in springTrigger;
        // deactivate after firing
        trigger.isActive = false
    case .persistent:
        // Never auto-remove; stays active for re-firing
        break
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
        // Enable AI production for all non-player, non-neutral houses
        if let world = session.world {
            for (house, state) in session.houseStates {
                if house != world.playerHouse && house != .neutral {
                    state.productionEnabled = true
                    print("Trigger: AI production enabled for \(house.rawValue)")
                }
            }
        }

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
        // Enable autocreate AI mode: the AI will periodically create teams
        // from TeamTypes that have isAutocreate = true
        if let world = session.world {
            for (house, state) in session.houseStates {
                if house != world.playerHouse && house != .neutral {
                    state.productionEnabled = true
                }
            }
        }
        // Immediately try to create an autocreate team
        tryAutocreateTeam()
        print("Trigger: Autocreate enabled — AI will auto-create teams")

    case .winLose:
        // Cap=Win/Des=Lose — handled via object events (capture = win, destroy = lose)
        // This is set up by the trigger being attached to a building;
        // when captured, the player wins; when destroyed, the player loses.
        print("Trigger: Win/Lose condition set")

    case .allowWin:
        session.allowWinFlag = true
        print("Trigger: Allow win flag set")

    case .dz:
        // Drop zone at waypoint 'Z' (waypoint 25) — reveal fog around the drop zone
        // In original C&C, this places a smoke flare at waypoint 25
        if let dzPos = waypointWorldPos(25) {
            revealFogAroundPosition(worldX: dzPos.x, worldY: dzPos.y, radius: 4)
            print("Trigger: Drop zone flare at waypoint 25 (\(Int(dzPos.x)), \(Int(dzPos.y)))")
        } else {
            print("Trigger: Drop zone flare — waypoint 25 not defined")
        }

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

/// Force-activate a trigger by name (used by "Force Trigger" actions in some scenarios)
func forceTriggerNamed(_ name: String) {
    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }
        if trigger.name.caseInsensitiveCompare(name) == .orderedSame {
            fireTrigger(trigger)
        }
    }
}

// MARK: - Reinforcements

/// Spawn reinforcements for a team type — delegates to the full reinforcement system.
/// Supports C17 cargo plane fly-in delivery, APC transport, or direct ground spawning.
func spawnReinforcements(teamName: String) {
    doReinforcements(teamName: teamName)
}
