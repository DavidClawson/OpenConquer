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
    // Tier-1 T4: region (area) events. Not in the classic engine — used by
    // triggers that carry a Region= reference in [TriggersEx].
    case enteredRegion = 17
    case leftRegion = 18

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
            ("Enter Region", .enteredRegion),
            ("Leave Region", .leftRegion),
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

// MARK: - Two-event combining (Tier-1 T3)

/// How a trigger's two events combine, mirroring RA1's event-control modes.
/// `only` is the classic single-event behavior (event2 ignored).
enum EventControl {
    case only     // fire on event1 only (classic)
    case or       // fire when EITHER event occurs
    case and      // fire only after BOTH events have occurred
    case linked   // treated like AND for Tier-1 (per-object linkage not modeled)

    static func from(_ name: String) -> EventControl {
        switch name.trimmingCharacters(in: .whitespaces).uppercased() {
        case "OR":     return .or
        case "AND":    return .and
        case "LINKED": return .linked
        default:        return .only
        }
    }
}

// MARK: - Region Zones (Tier-1 T4)

/// A named area on the map. Triggers with an `Enter Region` / `Leave Region`
/// event fire when a unit of the trigger's house enters or leaves this zone —
/// the area-based generalization of a single-cell `[CellTriggers]` enter.
/// Parsed from the `[Regions]` section (a classic engine ignores it).
struct ScenarioRegion {
    enum Shape {
        case rect(x: Int, y: Int, w: Int, h: Int)      // top-left cell + size in cells
        case waypointRadius(waypoint: Int, radius: Int) // cell radius around a waypoint
    }
    let name: String
    let shape: Shape

    /// Whether a cell lies inside this region.
    func contains(cellX: Int, cellY: Int) -> Bool {
        switch shape {
        case let .rect(x, y, w, h):
            return cellX >= x && cellX < x + w && cellY >= y && cellY < y + h
        case let .waypointRadius(wp, radius):
            guard let cell = session.scenarioWaypoints[wp] else { return false }
            let wx = cell % 64, wy = cell / 64
            let dx = cellX - wx, dy = cellY - wy
            // Chebyshev radius (square) — cheap and matches a "within N cells" feel.
            return abs(dx) <= radius && abs(dy) <= radius
        }
    }

    /// Parse a `[Regions]` value: `rect,x,y,w,h` or `wp,waypoint,radius`.
    static func parse(name: String, value: String) -> ScenarioRegion? {
        let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let kind = parts.first?.lowercased() else { return nil }
        switch kind {
        case "rect":
            guard parts.count >= 5,
                  let x = Int(parts[1]), let y = Int(parts[2]),
                  let w = Int(parts[3]), let h = Int(parts[4]) else { return nil }
            return ScenarioRegion(name: name, shape: .rect(x: x, y: y, w: w, h: h))
        case "wp":
            guard parts.count >= 3, let wp = Int(parts[1]), let r = Int(parts[2]) else { return nil }
            return ScenarioRegion(name: name, shape: .waypointRadius(waypoint: wp, radius: r))
        default:
            return nil
        }
    }
}

// MARK: - Trigger Action Spec (Tier-1 T2: multiple actions per trigger)

/// One action a trigger performs when it fires, with its optional team/argument.
/// The classic model is one action per trigger; Tier-1 lets a trigger carry
/// several (the first comes from the `[Triggers]` line, the rest from
/// `[TriggersEx]` `Action2..N`). Team-based actions (Create Team / Reinforce. /
/// Dstry Teams) use this spec's `teamName`, falling back to the trigger's.
struct TriggerActionSpec {
    let action: TriggerAction
    let teamName: String?
}

// MARK: - Game Trigger

class GameTrigger {
    let name: String
    let event: TriggerEvent
    let house: House
    let teamName: String?
    let persistence: TriggerPersistence
    var data: Int               // Event-specific: credits threshold, time (in game ticks), count
    let dataCopy: Int           // Original data value for resetting
    var attachCount: Int = 0
    var isActive: Bool = true
    /// Tracks which houses have already fired this trigger (for semi-persistent per-side)
    var firedForHouses: Set<House> = []

    /// The actions this trigger performs, in order. Classic triggers have
    /// exactly one (index 0, from the `[Triggers]` line); Tier-1 `[TriggersEx]`
    /// appends `Action2..N`.
    var actions: [TriggerActionSpec]

    /// The primary action (classic single-action accessor).
    var action: TriggerAction { actions.first?.action ?? .none }

    // Tier-1 T3: optional second event + combine mode (from [TriggersEx]).
    var event2: TriggerEvent = .none
    var data2: Int = 0          // event2 threshold / time (in game ticks)
    var data2Copy: Int = 0
    var eventControl: EventControl = .only
    // Latches for AND/LINKED: whether each event has been satisfied at least once.
    var e1Satisfied: Bool = false
    var e2Satisfied: Bool = false

    // Tier-1 T4: region this trigger watches (for Enter/Leave Region events),
    // from [TriggersEx] Region=. `regionOccupied` tracks last-seen occupancy so
    // enter/leave fire on the transition, not every tick.
    var regionName: String? = nil
    var regionOccupied: Bool = false

    init(name: String, event: TriggerEvent, action: TriggerAction,
         house: House, teamName: String?, persistence: TriggerPersistence, data: Int) {
        self.name = name
        self.event = event
        self.house = house
        self.teamName = teamName
        self.persistence = persistence
        self.actions = [TriggerActionSpec(action: action, teamName: teamName)]
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
    session.winBlockage = 0
    session.flaggedToWin = false

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

    // Tier-1 [TriggersEx]: extra actions + optional second event + region ref
    // per trigger. Classic scenarios have no such section, so this is inert.
    parseTriggersEx(from: ini)

    // Prime the win Blockage: one per AllowWin action belonging to the player's
    // house, so a Win action can't complete until every AllowWin has fired
    // (mirrors the load-time `Blockage++` in TRIGGER.CPP:1078; the win gate is
    // HOUSE.CPP:794). Count across all action slots so a TriggersEx-added
    // AllowWin is included. Must run after parseTriggersEx.
    let playerHouse = session.world?.playerHouse
    for trigger in session.gameTriggers where trigger.house == playerHouse {
        session.winBlockage += trigger.actions.filter { $0.action == .allowWin }.count
    }

    // Tier-1 [Regions]: named zones for Enter/Leave Region events.
    parseRegions(from: ini)

    print("GameTrigger: Loaded \(session.gameTriggers.count) triggers")

}

/// Parse the Tier-1 `[Regions]` section into `session.scenarioRegions` and prime
/// each region-watching trigger's occupancy to the current state, so a unit that
/// merely *starts* inside a region doesn't spuriously fire an Enter on tick 0.
func parseRegions(from ini: INIFile) {
    session.scenarioRegions.removeAll()
    for entry in ini.entries("Regions") {
        let name = entry.key.trimmingCharacters(in: .whitespaces)
        if let region = ScenarioRegion.parse(name: name, value: entry.value) {
            session.scenarioRegions[name.uppercased()] = region
        }
    }
    if session.scenarioRegions.isEmpty { return }
    print("GameTrigger: Loaded \(session.scenarioRegions.count) region(s)")

    // Prime occupancy without firing.
    guard let world = session.world else { return }
    for trigger in session.gameTriggers {
        guard let region = regionFor(trigger) else { continue }
        trigger.regionOccupied = regionIsOccupied(region, by: trigger.house, world: world)
    }
}

/// The region a trigger watches, if it has a region event + a valid Region= ref.
private func regionFor(_ trigger: GameTrigger) -> ScenarioRegion? {
    let watches = trigger.event == .enteredRegion || trigger.event == .leftRegion ||
        (trigger.eventControl != .only &&
         (trigger.event2 == .enteredRegion || trigger.event2 == .leftRegion))
    guard watches, let name = trigger.regionName else { return nil }
    return session.scenarioRegions[name.uppercased()]
}

/// Whether any live unit/infantry of `house` is currently inside `region`.
private func regionIsOccupied(_ region: ScenarioRegion, by house: House, world: GameWorld) -> Bool {
    world.objects.contains { obj in
        obj.house == house && obj.strength > 0 && !obj.isInLimbo &&
        (obj.kind == .unit || obj.kind == .infantry) &&
        region.contains(cellX: obj.cellX, cellY: obj.cellY)
    }
}

/// Per-tick region check: fire Enter/Leave Region events on the occupancy
/// transition. Inert when the scenario has no regions, so classic missions are
/// unaffected.
func tickRegionTriggers() {
    guard let world = session.world else { return }
    guard session.triggerWinState == .playing else { return }
    guard !session.scenarioRegions.isEmpty else { return }

    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }
        guard let region = regionFor(trigger) else { continue }

        let wantsEnter = trigger.event == .enteredRegion ||
            (trigger.eventControl != .only && trigger.event2 == .enteredRegion)
        let wantsLeave = trigger.event == .leftRegion ||
            (trigger.eventControl != .only && trigger.event2 == .leftRegion)

        let inside = regionIsOccupied(region, by: trigger.house, world: world)
        let was = trigger.regionOccupied
        if inside && !was && wantsEnter {
            registerEventSatisfied(trigger, isEvent2: trigger.event != .enteredRegion)
        } else if !inside && was && wantsLeave {
            registerEventSatisfied(trigger, isEvent2: trigger.event != .leftRegion)
        }
        trigger.regionOccupied = inside
    }
}

/// Parse the Tier-1 `[TriggersEx]` section, which extends named triggers with
/// extra actions and an optional second event. A row is
/// `TriggerName = key=val; key=val; ...` with keys:
///   - `Action2`,`Action3`,… `= ActionName[:TeamArg]` (T2) — extra actions,
///     same display names as `[Triggers]`.
///   - `Event2 = EventName[:Data]` (T3) — a second event (display names as in
///     `[Triggers]`; time Data is in 1/10-minute units like event1).
///   - `Control = AND|OR|ONLY|LINKED` (T3) — how the two events combine.
///   - `Region = name` (T4) — the `[Regions]` zone an Enter/Leave Region event
///     watches.
/// A trigger with no `[TriggersEx]` row stays exactly classic (one event, one
/// action, `Control=ONLY`).
func parseTriggersEx(from ini: INIFile) {
    for entry in ini.entries("TriggersEx") {
        let triggerName = entry.key.trimmingCharacters(in: .whitespaces)
        guard let trigger = session.gameTriggers.first(where: {
            $0.name.caseInsensitiveCompare(triggerName) == .orderedSame
        }) else { continue }

        // Collect Action<N> tokens, then append them in ascending N order so the
        // execution order is deterministic regardless of how they're written.
        var extras: [(index: Int, spec: TriggerActionSpec)] = []
        for token in entry.value.components(separatedBy: ";") {
            let t = token.trimmingCharacters(in: .whitespaces)
            guard let eq = t.firstIndex(of: "=") else { continue }
            let key = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
            let val = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            let keyLower = key.lowercased()

            // Control=AND|OR|ONLY|LINKED (T3).
            if keyLower == "control" {
                trigger.eventControl = EventControl.from(val)
                continue
            }
            // Region=name (T4) — the zone an Enter/Leave Region event watches.
            if keyLower == "region" {
                trigger.regionName = val
                continue
            }
            // Event2=EventName[:Data] (T3). Event display names never contain ':'.
            if keyLower == "event2" {
                let ep = val.components(separatedBy: ":")
                let evName = ep[0].trimmingCharacters(in: .whitespaces)
                let rawData = ep.count > 1 ? (Int(ep[1].trimmingCharacters(in: .whitespaces)) ?? 0) : 0
                let ev = TriggerEvent.from(evName)
                trigger.event2 = ev
                // Match GameTrigger.init: time data is in 1/10-minute units → ticks.
                trigger.data2 = (ev == .time) ? rawData * 15 * 6 : rawData
                trigger.data2Copy = trigger.data2
                continue
            }
            // Action<N>=ActionName[:TeamArg] (T2). Action names never contain ':'.
            if keyLower.hasPrefix("action"),
               let n = Int(keyLower.dropFirst("action".count)), n >= 2 {
                let colonParts = val.components(separatedBy: ":")
                let actionName = colonParts[0].trimmingCharacters(in: .whitespaces)
                let team = colonParts.count > 1 ? colonParts[1].trimmingCharacters(in: .whitespaces) : nil
                let action = TriggerAction.from(actionName)
                extras.append((index: n, spec: TriggerActionSpec(action: action, teamName: team)))
            }
        }
        extras.sort { $0.index < $1.index }
        for e in extras { trigger.actions.append(e.spec) }
        if !extras.isEmpty || trigger.event2 != .none {
            print("GameTrigger: '\(trigger.name)' extended: +\(extras.count) action(s), event2=\(trigger.event2), control=\(trigger.eventControl)")
        }
    }
}

// MARK: - Trigger Evaluation

/// Apply a satisfied event to a trigger's combine logic, firing when the
/// control condition is met.
/// - `.only`  : classic — only event1 fires; event2 is ignored.
/// - `.or`    : fire whenever either event is satisfied.
/// - `.and`/`.linked`: latch each event; fire once both have been satisfied.
/// For `.only` single-event triggers this is exactly `fireTrigger(trigger)`,
/// preserving classic behavior bit-for-bit.
func registerEventSatisfied(_ trigger: GameTrigger, isEvent2: Bool) {
    switch trigger.eventControl {
    case .only:
        if !isEvent2 { fireTrigger(trigger) }
    case .or:
        fireTrigger(trigger)
    case .and, .linked:
        if isEvent2 { trigger.e2Satisfied = true } else { trigger.e1Satisfied = true }
        if trigger.e1Satisfied && trigger.e2Satisfied {
            fireTrigger(trigger)
        }
    }
}

/// Whether a *polled* event's condition is currently met. Excludes `.time`
/// (a stateful countdown, handled inline in `evaluateTriggerEvent`) and the
/// sprung events (they arrive via `springTrigger`, so they return false here).
/// `threshold` is the event's data value (`trigger.data` or `trigger.data2`).
func polledEventReady(_ event: TriggerEvent, threshold: Int, house: House, world: GameWorld) -> Bool {
    switch event {
    case .allDestroyed:
        // Don't fire until the house has had time to exist (reinforcement grace).
        let hasAnything = world.objects.contains { $0.house == house && $0.strength > 0 }
        return !hasAnything && world.tickCount > 150
    case .unitsDestroyed:
        let hasUnits = world.objects.contains { $0.house == house && $0.strength > 0 &&
            ($0.kind == .unit || $0.kind == .infantry) }
        return !hasUnits && world.tickCount > 150
    case .buildingsDestroyed:
        let hasBuildings = world.objects.contains { $0.house == house && $0.strength > 0 && $0.kind == .structure }
        return !hasBuildings && world.tickCount > 30
    case .noFactories:
        let hasFactory = world.objects.contains { $0.house == house && $0.strength > 0 &&
            $0.kind == .structure && ["WEAP", "FACT", "AFLD", "HAND", "PYLE"].contains($0.typeName.uppercased()) }
        return !hasFactory && world.tickCount > 30
    case .credits:
        let credits = (house == world.playerHouse) ? session.sidebarCredits : getHouseState(house).credits
        return credits >= threshold
    case .nBuildingsDestroyed:
        return getHouseState(house).buildingsLost >= threshold && threshold > 0
    case .nUnitsDestroyed:
        return getHouseState(house).unitsLost >= threshold && threshold > 0
    case .houseDiscovered:
        guard world.tickCount % 15 == 0 else { return false }
        return world.objects.contains { obj in
            obj.house == house && obj.strength > 0 && !obj.isInLimbo && isCellVisible(obj.cell)
        }
    case .civEvacuated:
        guard world.tickCount % 8 == 0 else { return false }
        guard let evacPos = waypointWorldPos(25) else { return false }
        return world.objects.contains { obj in
            obj.house == .neutral && obj.kind == .infantry && obj.strength > 0 && !obj.isInLimbo &&
            abs(obj.worldX - evacPos.x) < 24.0 && abs(obj.worldY - evacPos.y) < 24.0
        }
    default:
        // Sprung events (.playerEntered/.attacked/.destroyed/.discovered/
        // .builtIt/.any) and .none are not polled here.
        return false
    }
}

/// Evaluate one of a trigger's events during the per-tick poll. Handles the
/// stateful `.time` countdown inline (per-event, using data/data2); other
/// polled events go through `polledEventReady`. On satisfaction it routes
/// through `registerEventSatisfied` so the combine logic decides whether to fire.
func evaluateTriggerEvent(_ trigger: GameTrigger, event: TriggerEvent, isEvent2: Bool, world: GameWorld) {
    if event == .time {
        if isEvent2 {
            if trigger.data2 > 0 {
                trigger.data2 -= 1
                if trigger.data2 <= 0 {
                    registerEventSatisfied(trigger, isEvent2: true)
                    if trigger.persistence == .persistent { trigger.data2 = trigger.data2Copy }
                }
            }
        } else {
            if trigger.data > 0 {
                trigger.data -= 1
                if trigger.data <= 0 {
                    registerEventSatisfied(trigger, isEvent2: false)
                    if trigger.persistence == .persistent { trigger.data = trigger.dataCopy }
                }
            }
        }
        return
    }
    let threshold = isEvent2 ? trigger.data2 : trigger.data
    if polledEventReady(event, threshold: threshold, house: trigger.house, world: world) {
        registerEventSatisfied(trigger, isEvent2: isEvent2)
    }
}

/// Tick all house-based triggers each game tick
func tickTriggers() {
    guard let world = session.world else { return }
    guard session.triggerWinState == .playing else { return }

    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }
        evaluateTriggerEvent(trigger, event: trigger.event, isEvent2: false, world: world)
        // Only multi-event triggers have a second event to poll.
        if trigger.eventControl != .only && trigger.event2 != .none {
            evaluateTriggerEvent(trigger, event: trigger.event2, isEvent2: true, world: world)
        }
    }
}

/// Spring a trigger by name (for object/cell events)
func springTrigger(named triggerName: String, event: TriggerEvent) {
    guard session.triggerWinState == .playing else { return }

    for trigger in session.gameTriggers {
        guard trigger.isActive else { continue }
        guard trigger.name.caseInsensitiveCompare(triggerName) == .orderedSame else { continue }

        let matchesE1 = (trigger.event == event || trigger.event == .any)
        let matchesE2 = trigger.eventControl != .only && trigger.event2 != .none &&
                        (trigger.event2 == event || trigger.event2 == .any)
        guard matchesE1 || matchesE2 else { continue }
        let isEvent2 = !matchesE1   // matched only via the second event

        if trigger.persistence == .semiPersistent {
            trigger.attachCount -= 1
            if trigger.attachCount <= 0 {
                registerEventSatisfied(trigger, isEvent2: isEvent2)
            }
        } else {
            registerEventSatisfied(trigger, isEvent2: isEvent2)
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
                        registerEventSatisfied(trigger, isEvent2: false)
                    }
                } else if !isPlayer {
                    // Only fire for non-player if we didn't already fire via springTrigger above
                    registerEventSatisfied(trigger, isEvent2: false)
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
        let isE1 = (trigger.event == .builtIt)
        let isE2 = trigger.eventControl != .only && trigger.event2 == .builtIt
        guard isE1 || isE2 else { continue }
        // In original C&C, "Built It" fires for the player's house when any structure is built.
        // The trigger is not attached to a specific type; it fires whenever any structure is placed.
        if let world = session.world, trigger.house == world.playerHouse {
            registerEventSatisfied(trigger, isEvent2: !isE1)
        }
    }
}

// MARK: - Trigger Actions

/// Complete a flagged win once the win Blockage is fully drained. Mirrors the
/// per-frame gate `if (IsToWin && ... && Blockage <= 0)` (HOUSE.CPP:794). Called
/// after a Win action flags the win and after each AllowWin action drains a unit
/// of blockage, so it resolves regardless of the two firing in either order.
func resolveFlaggedWin() {
    guard session.flaggedToWin, session.winBlockage <= 0,
          session.triggerWinState == .playing else { return }
    print(">>> MISSION WON <<<")
    session.triggerWinState = .won
}

func fireTrigger(_ trigger: GameTrigger) {
    guard trigger.isActive else { return }

    print("Trigger '\(trigger.name)' fired: actions=\(trigger.actions.map { $0.action })")

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

    // Run every action in order (classic triggers have exactly one).
    for spec in trigger.actions {
        executeTriggerAction(spec, trigger: trigger)
    }
}

/// Perform a single trigger action. Team-based actions use the spec's teamName
/// (falling back to the trigger's own team field).
func executeTriggerAction(_ spec: TriggerActionSpec, trigger: GameTrigger) {
    let teamName = spec.teamName ?? trigger.teamName
    switch spec.action {
    case .win:
        // Flag to win — but the mission only actually ends once every AllowWin
        // trigger has fired (winBlockage drained to 0). Mirrors Flag_To_Win +
        // the HOUSE.CPP:794 win gate. When a scenario has no AllowWin triggers,
        // blockage is 0 and this wins immediately (the common case).
        if session.triggerWinState == .playing { session.flaggedToWin = true }
        resolveFlaggedWin()

    case .lose:
        print(">>> MISSION LOST <<<")
        session.flaggedToWin = false      // Flag_To_Lose clears IsToWin (HOUSE.CPP:4155)
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
        // Enable production for the TRIGGER'S house only, mirroring
        // As_Pointer(House)->Begin_Production() (TRIGGER.CPP:490). The previous
        // behavior enabled every AI house at once, which over-activated the map.
        // A trigger with no house parses to .neutral; skip it (nothing to produce).
        if trigger.house != .neutral {
            getHouseState(trigger.house).productionEnabled = true
            print("Trigger: production enabled for \(trigger.house.rawValue)")
        }

    case .createTeam:
        if let teamName = teamName {
            triggerCreateTeam(named: teamName)
        }

    case .destroyTeam:
        if let teamName = teamName {
            triggerDestroyTeam(named: teamName)
        }

    case .reinforcements:
        if let teamName = teamName {
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
        // Cap=Win/Des=Lose — resolved by the firing event (see the event-aware
        // overload below). This event-less path is only reached by callers that
        // don't yet thread the firing event; it can't decide win vs lose, so it
        // is a no-op here. #2 (event threading + capture spring) is Wave B.
        print("Trigger: Win/Lose condition set (awaiting event-aware handling)")

    case .allowWin:
        // Consume one unit of win Blockage (TRIGGER.CPP:313-314); once the
        // blockage is drained a previously-flagged Win can complete.
        session.allowWinFlag = true
        if session.winBlockage > 0 { session.winBlockage -= 1 }
        print("Trigger: Allow win — blockage now \(session.winBlockage)")
        resolveFlaggedWin()

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
