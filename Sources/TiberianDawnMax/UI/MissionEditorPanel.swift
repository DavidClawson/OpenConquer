import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - The mission editor's side panel, one function per tab

extension MissionEditorScreen {
    // MARK: Panel

    func drawPanel(_ r: OpaquePointer?) {
        hits.removeAll()
        let x = panelX, w = panelWidth, h = renderState.windowHeight
        fill(r, SDL_Rect(x: x, y: 0, w: w, h: h), Color(r: 8, g: 12, b: 8, a: 255), alpha: 245)
        SDL_SetRenderDrawColor(r, Color.darkGreen.r, Color.darkGreen.g, Color.darkGreen.b, 255)
        SDL_RenderDrawLine(r, x, 0, x, h)

        // Header: title, the always-there buttons, the tabs.
        let pen = PanelPen(renderer: r, x: x + 12, w: w - 24, y: 10, clip: (0, h)) { [unowned self] rect, label, action in
            hits.append((rect, label, action))
        }
        pen.text("MISSION EDITOR", .amber)
        pen.row([("SAVE", false, { [unowned self] in save() }),
                 ("PLAY-TEST", false, { [unowned self] in playTest() }),
                 ("UNDO", false, { [unowned self] in undo() }),
                 ("EXIT", false, { [unowned self] in exit() })])
        pen.row(Tab.allCases.map { t in (t.rawValue, tab == t, { [unowned self] in switchTab(t) }) }, small: true)

        // Content, scrolled and clipped below the header.
        let top = headerHeight
        var clip = SDL_Rect(x: x, y: top, w: w, h: h - top)
        SDL_RenderSetClipRect(r, &clip)
        let offset = scroll[tab] ?? 0
        let content = PanelPen(renderer: r, x: x + 12, w: w - 24, y: top + 6 - offset, clip: (top, h)) { [unowned self] rect, label, action in
            hits.append((rect, label, action))
        }
        switch tab {
        case .file: fileTab(content)
        case .units: unitsTab(content)
        case .setup: setupTab(content)
        case .goals: goalsTab(content)
        case .reinforce: reinforceTab(content)
        }
        contentHeight = content.y + offset - top + 20
        SDL_RenderSetClipRect(r, nil)
        let maxScroll = max(0, contentHeight - (h - top))
        if offset > maxScroll { scroll[tab] = maxScroll }
    }

    func switchTab(_ t: Tab) {
        tab = t
        renaming = false
        if t == .file { savedMissions = customMissionNames() }
        if t != .goals && t != .reinforce { markingSpotsFor = nil }
        if t != .units { placeType = nil }
    }

    func exit() {
        app.currentScreen = makeMainMenu()
    }

    // MARK: FILE

    func fileTab(_ p: PanelPen) {
        p.heading("NAME")
        p.row([((renaming ? doc.name + "_" : doc.name), renaming, { [unowned self] in renaming.toggle() })])
        p.note(renaming ? "TYPE A NAME, THEN PRESS RETURN." : "CLICK THE NAME TO RENAME. SAVES TO THE MISSIONS FOLDER IN YOUR GAME DATA.")
        p.heading("YOUR MISSIONS")
        if savedMissions.isEmpty { p.note("NONE SAVED YET.") }
        p.grid(savedMissions.map { name in (name, name == doc.name, { [unowned self] in
            if let e = MissionEditorScreen.openSaved(name) { app.currentScreen = e }
        }) }, columns: 2)
        p.heading("NEW, ON AN EMPTY MAP")
        p.row(TheaterType.allCases.map { t in (t.rawValue, false, { app.currentScreen = MissionEditorScreen.blank(t) }) }, small: true)
        p.heading("NEW, FROM A CAMPAIGN MAP")
        p.grid(app.scenarioList.map { name in (name, false, {
            if let e = MissionEditorScreen.openCampaign(name) { app.currentScreen = e }
        }) }, columns: 3, small: true)
    }

    // MARK: UNITS

    static let overlayTypes: [(String, String)] = [
        ("TI1", "Tiberium"), ("SBAG", "Sandbags"), ("CYCL", "Chain link"), ("BRIK", "Concrete wall"),
        ("BARB", "Barbed wire"), ("WOOD", "Wood fence"), ("WCRATE", "Crate"),
    ]

    func displayName(_ type: String) -> String {
        let upper = type.uppercased()
        if let d = infantryTypeDataTable.values.first(where: { $0.iniName == upper }) { return d.fullName }
        if let d = unitTypeDataTable.values.first(where: { $0.iniName == upper }) { return d.fullName }
        if let d = aircraftTypeDataTable.values.first(where: { $0.iniName == upper }) { return d.fullName }
        if let d = buildingTypeDataTable.values.first(where: { $0.iniName == upper }) { return d.fullName }
        if upper.hasPrefix("TI") { return "Tiberium" }
        return Self.overlayTypes.first { $0.0 == upper }?.1 ?? type
    }

    /// The types a category offers: the sides' own first, then the rest.
    func types(_ c: Category) -> [String] {
        func order(_ names: [(String, Bool)]) -> [String] {
            names.sorted { a, b in a.1 != b.1 ? a.1 : a.0 < b.0 }.map(\.0)
        }
        switch c {
        case .infantry:
            return order(infantryTypeDataTable.values.map { ($0.iniName, $0.isBuildable) })
        case .vehicles:
            return order(unitTypeDataTable.values.map { ($0.iniName, $0.isBuildable) })
        case .buildings:
            // Walls are overlays in a scenario: they're under WALLS ETC.
            let walls = Set(Self.overlayTypes.map(\.0))
            return order(buildingTypeDataTable.values.filter { !$0.iniName.isEmpty && !walls.contains($0.iniName) }
                .map { ($0.iniName, $0.isBuildable) })
        case .other:
            return Self.overlayTypes.map(\.0)
        }
    }

    func unitsTab(_ p: PanelPen) {
        if let s = selection, isValid(s) {
            selectedObject(p, s)
        } else {
            selection = nil
        }
        p.heading("PLACE")
        p.row([("SELECT", placeType == nil, { [unowned self] in placeType = nil })])
        p.row([("GDI", placeHouse == .goodGuy, { [unowned self] in placeHouse = .goodGuy }),
               ("NOD", placeHouse == .badGuy, { [unowned self] in placeHouse = .badGuy }),
               ("CIVILIAN", placeHouse == .neutral, { [unowned self] in placeHouse = .neutral })], small: true)
        p.row(Category.allCases.map { c in (c.rawValue, category == c, { [unowned self] in category = c }) }, small: true)
        p.grid(types(category).map { t in
            ("\(t) \(displayName(t))", placeType == t, { [unowned self] in
                placeType = placeType == t ? nil : t
                selection = nil
            })
        }, columns: 1, small: true)
    }

    func selectedObject(_ p: PanelPen, _ s: Selection) {
        let type = typeName(s)
        p.heading("SELECTED: \(displayName(type).uppercased())")
        p.note("\(type) AT CELL \(cellOf(s))")
        if let h = house(s) {
            p.row([("GDI", h == .goodGuy, { [unowned self] in setHouse(s, .goodGuy) }),
                   ("NOD", h == .badGuy, { [unowned self] in setHouse(s, .badGuy) }),
                   ("CIVILIAN", h == .neutral, { [unowned self] in setHouse(s, .neutral) })], small: true)
            let st = strength(s)
            p.stepper("HEALTH", "\(Int((Double(st) / 256 * 100).rounded()))%",
                      { [unowned self] in setStrength(s, st - 32) }, { [unowned self] in setStrength(s, st + 32) })
        }
        if case .structure = s {} else if case .overlay = s {} else {
            let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            p.stepper("FACING", names[((facing(s) + 16) / 32) % 8],
                      { [unowned self] in rotate(s, by: -32) }, { [unowned self] in rotate(s, by: 32) })
        }
        if let m = mission(s) {
            let options = ["Guard", "Area Guard", "Hunt", "Sleep"] + (type.uppercased() == "HARV" ? ["Harvest"] : [])
            p.label("ORDERS")
            p.grid(options.map { o in (o.uppercased(), m.caseInsensitiveCompare(o) == .orderedSame,
                                       { [unowned self] in setMission(s, o) }) }, columns: 3, small: true)
        }
        if house(s) != nil {
            let cell = cellOf(s)
            let t = trigger(s)
            let trig = doc.mission.triggers.first { $0.name == t }
            p.toggle("INVULNERABLE", doc.mission.flag("Invulnerable", at: cell)) { [unowned self] on in
                edit { doc.mission.setFlag("Invulnerable", at: cell, on) }
            }
            p.toggle("MUST SURVIVE (LOSE IF IT DIES)", doc.mission.flag("MustSurvive", at: cell)) { [unowned self] on in
                edit { doc.mission.setFlag("MustSurvive", at: cell, on) }
            }
            p.toggle("WIN WHEN DESTROYED", trig?.event == "Destroyed" && trig?.action == "Win") { [unowned self] on in
                setOutcomeIfDestroyed(s, action: "Win", on)
            }
            p.toggle("LOSE WHEN DESTROYED", trig?.event == "Destroyed" && trig?.action == "Lose") { [unowned self] on in
                setOutcomeIfDestroyed(s, action: "Lose", on)
            }
            if t != "None", trig?.event != "Destroyed" {
                p.note("RUNS TRIGGER \(t)" + (trig.map { ": \($0.action.uppercased()) WHEN \($0.when.uppercased())" } ?? ""))
            }
        }
        p.row([("DELETE", false, { [unowned self] in delete(s) }),
               ("DESELECT", false, { [unowned self] in selection = nil })])
    }

    // MARK: SETUP

    func setupTab(_ p: PanelPen) {
        p.heading("PLAYER COMMANDS")
        p.row([("GDI", doc.mission.player == .goodGuy, { [unowned self] in edit { doc.mission.player = .goodGuy } }),
               ("NOD", doc.mission.player == .badGuy, { [unowned self] in edit { doc.mission.player = .badGuy } })])
        for house in MissionState.sides {
            let name = EditorTrigger.sideName(house).uppercased() + (house == doc.mission.player ? " (PLAYER)" : " (COMPUTER)")
            p.heading(name)
            let c = doc.mission.credits[house] ?? 0
            p.stepper("MONEY", "\(c)", { [unowned self] in setCredits(house, c - 500) },
                      { [unowned self] in setCredits(house, c + 500) })
            let edge = doc.mission.edges[house] ?? .north
            p.label("REINFORCEMENTS ARRIVE FROM")
            p.row([MapEdge.north, .east, .south, .west].map { e in
                (e.rawValue.uppercased(), edge == e, { [unowned self] in edit { doc.mission.edges[house] = e } })
            }, small: true)
        }
        p.heading("TECH LEVEL")
        let level = doc.mission.buildLevel
        p.stepper("LEVEL", "\(level)", { [unowned self] in edit { doc.mission.buildLevel = max(1, level - 1) } },
                  { [unowned self] in edit { doc.mission.buildLevel = min(15, level + 1) } })
        p.note("WHAT THE PLAYER CAN BUILD GROWS WITH THE LEVEL, AS IN THE CAMPAIGN (MISSION N USES LEVEL N). CLICK A LINE TO OVERRIDE IT. * MARKS YOUR CHANGES.")
        let gdi = doc.mission.player != .badGuy
        var lastCategory = ""
        for entry in techTreeCandidates(gdi: gdi) {
            if entry.category != lastCategory {
                lastCategory = entry.category
                p.label(entry.category.uppercased())
            }
            let byLevel = techTreeIncludes(entry.name, gdi: gdi, level: level)
            let allowed = doc.mission.allow.contains(entry.name)
            let denied = doc.mission.deny.contains(entry.name)
            let on = (byLevel || allowed) && !denied
            let changed = allowed || denied
            p.toggle("\(entry.fullName.uppercased())\(changed ? " *" : "")", on) { [unowned self] _ in
                edit {
                    if changed {
                        doc.mission.allow.remove(entry.name)
                        doc.mission.deny.remove(entry.name)
                    } else if byLevel {
                        doc.mission.deny.insert(entry.name)
                    } else {
                        doc.mission.allow.insert(entry.name)
                    }
                }
            }
        }
    }

    func setCredits(_ house: House, _ value: Int) {
        edit { doc.mission.credits[house] = max(0, min(99_900, value)) }
    }

    // MARK: GOALS

    func goalsTab(_ p: PanelPen) {
        let player = doc.mission.player, enemy = doc.mission.enemy
        let goals = doc.mission.goals
        for (heading, action) in [("THE PLAYER WINS WHEN", "Win"), ("THE PLAYER LOSES WHEN", "Lose")] {
            p.heading(heading)
            let list = goals.filter { $0.action == action || ($0.action == "Cap=Win/Des=Lose" && action == "Win") }
            if list.isEmpty { p.note(action == "Win" ? "NOTHING YET: THE MISSION CAN'T BE WON." : "NOTHING YET.") }
            for t in list { goalCard(p, t) }
        }
        p.heading("ADD A WAY TO WIN")
        p.grid([
            ("DESTROY EVERYTHING", false, { [unowned self] in addGoal("All Destr.", "Win", enemy) }),
            ("DESTROY THEIR BASE", false, { [unowned self] in addGoal("Bldgs Destr.", "Win", enemy) }),
            ("DESTROY THEIR UNITS", false, { [unowned self] in addGoal("Units Destr.", "Win", enemy) }),
            ("SURVIVE FOR A TIME", false, { [unowned self] in addGoal("Time", "Win", player, data: 100) }),
            ("REACH A SPOT", false, { [unowned self] in markingSpotsFor = addGoal("Player Enters", "Win", player) }),
            ("DESTROY TARGETS", false, { [unowned self] in
                tab = .units
                placeType = nil
                say("SELECT A TARGET, THEN TICK WIN WHEN DESTROYED")
            }),
        ], columns: 2, small: true)
        p.heading("ADD A WAY TO LOSE")
        p.grid([
            ("LOSE EVERYTHING", false, { [unowned self] in addGoal("All Destr.", "Lose", player) }),
            ("LOSE THE BASE", false, { [unowned self] in addGoal("Bldgs Destr.", "Lose", player) }),
            ("TIME LIMIT", false, { [unowned self] in addGoal("Time", "Lose", player, data: 200) }),
            ("ENEMY REACHES A SPOT", false, { [unowned self] in markingSpotsFor = addGoal("Player Enters", "Lose", enemy) }),
            ("PROTECT UNITS", false, { [unowned self] in
                tab = .units
                placeType = nil
                say("SELECT A UNIT, THEN TICK MUST SURVIVE")
            }),
        ], columns: 2, small: true)
        let mustSurvive = doc.mission.objectFlags.values.filter { $0.contains("MustSurvive") }.count
        if mustSurvive > 0 { p.note("ALSO LOST IF ANY OF THE \(mustSurvive) MUST-SURVIVE OBJECTS DIES.") }
        let others = doc.mission.triggers.count - goals.count - doc.mission.reinforcements.count
        if others > 0 { p.note("\(others) OTHER TRIGGERS FROM THE ORIGINAL MISSION ARE KEPT AS THEY ARE.") }
    }

    @discardableResult
    func addGoal(_ event: String, _ action: String, _ house: House, data: Int = 0) -> String {
        let name = doc.mission.newTriggerName(action == "Win" ? "WN" : "LS")
        edit { doc.mission.addTrigger(EditorTrigger(name: name, event: event, action: action, data: data, house: house.rawValue)) }
        if event == "Player Enters" { say("CLICK THE MAP TO MARK THE SPOT") }
        return name
    }

    func goalCard(_ p: PanelPen, _ t: EditorTrigger) {
        let color: Color = t.action == "Lose" ? .red : .brightGreen
        p.text(t.when.uppercased(), color)
        switch t.eventType {
        case .time:
            timeStepper(p, t)
        case .destroyed:
            let n = allObjects().filter { trigger($0) == t.name }.count
            p.note(n == 0 ? "NO OBJECTS MARKED. SELECT ONE ON THE UNITS TAB." : "\(n) OBJECT\(n == 1 ? "" : "S") MARKED.")
        case .playerEntered:
            spotsRow(p, t)
        default:
            break
        }
        p.row([("REMOVE", false, { [unowned self] in removeTrigger(t.name) })], small: true)
        p.gap(6)
    }

    func timeStepper(_ p: PanelPen, _ t: EditorTrigger) {
        p.stepper("TIME", EditorTrigger.clock(tenths: t.data), { [unowned self] in
            var u = t
            u.data = max(0, t.data - 5)
            edit { doc.mission.updateTrigger(u) }
        }, { [unowned self] in
            var u = t
            u.data = t.data + 5
            edit { doc.mission.updateTrigger(u) }
        })
    }

    func spotsRow(_ p: PanelPen, _ t: EditorTrigger) {
        let n = doc.data.cellTriggers.filter { $0.triggerName == t.name }.count
        p.note("\(n) SPOT\(n == 1 ? "" : "S") MARKED" + (n == 0 ? ": IT CAN'T HAPPEN YET." : "."))
        let marking = markingSpotsFor == t.name
        p.row([(marking ? "DONE MARKING" : "MARK SPOTS", marking, { [unowned self] in
            markingSpotsFor = marking ? nil : t.name
        })], small: true)
    }

    // MARK: REINFORCEMENTS

    func reinforceTab(_ p: PanelPen) {
        let list = doc.mission.reinforcements
        p.heading("REINFORCEMENTS")
        if list.isEmpty { p.note("NONE YET.") }
        for t in list {
            let team = doc.mission.team(named: t.team)
            let side = team.map { EditorTrigger.sideName(House.from($0.house)) } ?? t.houseName
            let summary = (team?.members ?? []).filter { ReinforcementTransport(rawValue: $0.type.uppercased()) == nil }
                .map { "\($0.count) \($0.type)" }.joined(separator: " ")
            let open = activeReinforcement == t.name
            p.row([("\(side.uppercased()): \(summary.isEmpty ? "EMPTY" : summary)", open, { [unowned self] in
                activeReinforcement = open ? nil : t.name
                addingMemberTo = nil
            })], small: true)
            if open, let team { reinforcementCard(p, t, team) }
        }
        p.gap(4)
        p.row([("+ FOR \(EditorTrigger.sideName(doc.mission.player).uppercased())", false, { [unowned self] in
                    newReinforcement(doc.mission.player) }),
               ("+ FOR \(EditorTrigger.sideName(doc.mission.enemy).uppercased())", false, { [unowned self] in
                    newReinforcement(doc.mission.enemy) })], small: true)
        p.note("A TEAM ARRIVES FROM ITS SIDE'S EDGE (SET ON THE SETUP TAB). THE PLAYER'S WAITS FOR ORDERS. THE COMPUTER'S ATTACKS.")
    }

    func newReinforcement(_ house: House) {
        var name = ""
        edit {
            name = doc.mission.addReinforcement(house: house, afterTenths: 10,
                                                members: [EditorTeamMember(type: "E1", count: 3)],
                                                transport: .none).name
        }
        activeReinforcement = name
    }

    func reinforcementCard(_ p: PanelPen, _ t: EditorTrigger, _ team: EditorTeam) {
        let house = House.from(team.house)
        // When.
        p.label("WHEN")
        let enemy: House = house == doc.mission.player ? doc.mission.enemy : doc.mission.player
        let options: [(String, String, String, Int)] = [
            ("AFTER A TIME", "Time", house.rawValue, t.event == "Time" ? t.data : 10),
            ("SPOT REACHED", "Player Enters", doc.mission.player.rawValue, 0),
            ("\(EditorTrigger.sideName(enemy).uppercased()) BASE GONE", "Bldgs Destr.", enemy.rawValue, 0),
        ]
        p.grid(options.map { o in (o.0, t.event == o.1, { [unowned self] in
            var u = t
            u.event = o.1
            u.house = o.2
            u.data = o.3
            u.persistence = 0
            edit {
                doc.mission.updateTrigger(u)
                if o.1 != "Player Enters" { doc.data.cellTriggers.removeAll { $0.triggerName == t.name } }
            }
            markingSpotsFor = o.1 == "Player Enters" ? t.name : nil
        }) }, columns: 3, small: true)
        switch t.eventType {
        case .time:
            timeStepper(p, t)
            p.toggle("REPEAT EVERY \(EditorTrigger.clock(tenths: t.data))", t.persistence == 2) { [unowned self] on in
                var u = t
                u.persistence = on ? 2 : 0
                edit { doc.mission.updateTrigger(u) }
            }
        case .playerEntered:
            spotsRow(p, t)
        default:
            p.note("WHEN \(t.when.uppercased()).")
        }
        // Side.
        p.label("SIDE")
        p.row([("GDI", house == .goodGuy, { [unowned self] in setTeamHouse(t, team, .goodGuy) }),
               ("NOD", house == .badGuy, { [unowned self] in setTeamHouse(t, team, .badGuy) })], small: true)
        // How.
        let transport = ReinforcementTransport.of(team)
        p.label("ARRIVES BY")
        p.grid(ReinforcementTransport.allCases.map { tr in (tr.label.uppercased(), transport == tr, { [unowned self] in
            var u = team
            u.members.removeAll { ReinforcementTransport(rawValue: $0.type.uppercased()) != nil && !$0.type.isEmpty }
            if tr != .none { u.members.append(EditorTeamMember(type: tr.rawValue, count: 1)) }
            edit { doc.mission.updateTeam(u) }
        }) }, columns: 2, small: true)
        if transport == .hovercraft || transport == .chinook || transport == .cargoPlane {
            p.note("A TRANSPORT CARRIES 5. HOVERCRAFT LAND ON A BEACH, SO THE MAP NEEDS ONE.")
        }
        // Who.
        p.label("UNITS")
        for (i, m) in team.members.enumerated() where ReinforcementTransport(rawValue: m.type.uppercased()) == nil || m.type.isEmpty {
            p.stepper("\(m.count) X \(displayName(m.type).uppercased())", "", { [unowned self] in
                var u = team
                if m.count <= 1 { u.members.remove(at: i) } else { u.members[i].count -= 1 }
                edit { doc.mission.updateTeam(u) }
            }, { [unowned self] in
                var u = team
                u.members[i].count += 1
                edit { doc.mission.updateTeam(u) }
            })
        }
        let adding = addingMemberTo == t.name
        p.row([(adding ? "CLOSE LIST" : "+ ADD A UNIT TYPE", adding, { [unowned self] in
            addingMemberTo = adding ? nil : t.name
        })], small: true)
        if adding {
            // What the side builds, any tech level.
            let choices = techTreeCandidates(gdi: house != .badGuy)
                .filter { $0.category == "Infantry" || $0.category == "Vehicles" }.map(\.name)
            p.grid(choices.map { c in ("\(c) \(displayName(c))", false, { [unowned self] in
                var u = team
                if let i = u.members.firstIndex(where: { $0.type == c }) { u.members[i].count += 1 } else {
                    let at = u.members.firstIndex { ReinforcementTransport(rawValue: $0.type.uppercased()) != nil } ?? u.members.count
                    u.members.insert(EditorTeamMember(type: c, count: 1), at: at)
                }
                edit { doc.mission.updateTeam(u) }
            }) }, columns: 2, small: true)
        }
        p.row([("DELETE THIS REINFORCEMENT", false, { [unowned self] in removeTrigger(t.name) })], small: true)
        p.gap(8)
    }

    func setTeamHouse(_ t: EditorTrigger, _ team: EditorTeam, _ house: House) {
        var u = team
        u.house = house.rawValue
        u.missions = house == doc.mission.player ? [] : [EditorTeamMission(mission: "Attack Units", argument: 0)]
        var trig = t
        if trig.event == "Time" { trig.house = house.rawValue }
        edit {
            doc.mission.updateTeam(u)
            doc.mission.updateTrigger(trig)
        }
    }
}
