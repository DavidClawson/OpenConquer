import CSDL2
import Foundation
import OpenConquerAssets
import OpenConquerCore

// MARK: - The mission editor's MAP tab: the ground, trees and rocks, the play area
//
// The ground is the scenario's BIN: one template (a tile set from the theater's
// .TEM/.DES/.WIN ICNs) and icon per cell. Painting stamps a whole template at
// the clicked cell, top-left first, skipping the cells its ICN leaves empty
// (irregular shores and cliffs), as the original's map editor placed them.
// 0xFF is clear ground. Trees and rocks are [TERRAIN] objects; the play area is
// [Map] X/Y/Width/Height.

/// The template families, by the names cdata.cpp gives them.
enum TileGroup: String, CaseIterable {
    case water = "WATER", shore = "SHORE", cliffs = "CLIFFS", roads = "ROADS"
    case rivers = "RIVERS", bridges = "BRIDGES", rough = "ROUGH"

    func contains(_ icn: String) -> Bool {
        func prefixed(_ p: String) -> Bool {
            icn.hasPrefix(p) && icn.dropFirst(p.count).first.map(\.isNumber) == true
        }
        switch self {
        case .water: return icn == "W1" || icn == "W2"
        case .shore: return prefixed("SH")
        case .cliffs: return prefixed("S")
        case .roads: return prefixed("D")
        case .rivers: return prefixed("RV") || icn.hasPrefix("FORD") || icn.hasPrefix("FALLS")
        case .bridges: return icn.hasPrefix("BRIDGE")
        case .rough: return prefixed("P") || prefixed("B") || prefixed("BR")
        }
    }
}

/// Trees and rocks ([TERRAIN] objects, TDATA.CPP).
let terrainObjectTypes: [String] =
    (1...18).map { String(format: "T%02d", $0) } + (1...5).map { String(format: "TC%02d", $0) }
    + (1...7).map { "ROCK\($0)" } + ["SPLIT2", "SPLIT3"]

extension MissionEditorScreen {
    var theaterSuffix: String { doc.data.theater.suffix }

    /// Templates this theater has art for, in table order.
    func templates(in group: TileGroup) -> [Int] {
        templateTable.indices.filter { i in
            let icn = templateTable[i].icnName
            return group.contains(icn) && icnFile(icn) != nil
        }
    }

    func icnFile(_ name: String) -> ICNFile? {
        if let f = icnFiles[name] { return f }
        guard let data = mixManager.retrieve(name + theaterSuffix), let f = try? ICNFile(data: data) else { return nil }
        icnFiles[name] = f
        return f
    }

    func terrainAvailable(_ type: String) -> Bool { mixManager.contains(type + theaterSuffix) }

    /// The cells `template` covers when stamped at `cell`, with their icons.
    func stampCells(_ template: Int, at cell: Int) -> [(cell: Int, icon: Int)] {
        let t = templateTable[template]
        guard let icn = icnFile(t.icnName) else { return [] }
        let (x, y) = cellToXY(cell)
        var out: [(Int, Int)] = []
        for dy in 0..<t.height {
            for dx in 0..<t.width where x + dx < 64 && y + dy < 64 {
                let icon = dy * t.width + dx
                if icn.tile(icon: icon) != nil { out.append(((y + dy) * 64 + x + dx, icon)) }
            }
        }
        return out
    }

    // MARK: Painting

    func startPainting(at cell: Int) {
        lastStamp = []
        painting = true
        paint(at: cell, first: true)
    }

    /// One dab of the current tool. The first of a stroke opens an undo step;
    /// the rest join it.
    func paint(at cell: Int, first: Bool = false) {
        switch mapTool {
        case .ground:
            guard let template = brushTemplate else { return }
            let cells = stampCells(template, at: cell)
            guard !cells.isEmpty, first || lastStamp.isDisjoint(with: cells.map(\.cell)) else { return }
            edit(continuing: !first) {
                for c in cells { map[c.cell] = MapCell(templateType: UInt8(template), iconIndex: UInt8(c.icon)) }
            }
            lastStamp = Set(cells.map(\.cell))
        case .trees:
            guard first, let type = brushTerrain else { return }
            edit {
                doc.data.terrain.removeAll { $0.cell == cell }
                doc.data.terrain.append(ScenarioTerrain(cell: cell, typeName: type))
            }
        case .erase:
            let tree = doc.data.terrain.firstIndex { terrainCells($0).contains(cell) }
            let ground = map[cell].templateType != 0xFF
            guard tree != nil || ground, first || !lastStamp.contains(cell) else { return }
            edit(continuing: !first) {
                if let tree { doc.data.terrain.remove(at: tree) } else { map[cell] = MapCell(templateType: 0xFF, iconIndex: 0) }
            }
            lastStamp.insert(cell)
        }
    }

    /// The cells a tree or rock's picture covers, bottom-aligned on its cell
    /// as the map view draws it: its own cell and those up and right of it.
    func terrainCells(_ t: ScenarioTerrain) -> Set<Int> {
        let (x, y) = cellToXY(t.cell)
        var cells: Set<Int> = []
        for dy in 0..<2 { for dx in 0..<2 where x + dx < 64 && y - dy >= 0 { cells.insert((y - dy) * 64 + x + dx) } }
        return cells
    }

    func setBounds(_ change: (inout (x: Int, y: Int, w: Int, h: Int)) -> Void) {
        let b = doc.data.mapBounds ?? MapBounds(x: 1, y: 1, width: 62, height: 62)
        var v = (x: b.x, y: b.y, w: b.width, h: b.height)
        change(&v)
        v.w = max(8, min(62, v.w))
        v.h = max(8, min(62, v.h))
        v.x = max(1, min(63 - v.w, v.x))
        v.y = max(1, min(63 - v.h, v.y))
        edit { doc.data.mapBounds = MapBounds(x: v.x, y: v.y, width: v.w, height: v.h) }
    }

    // MARK: Panel

    func mapTab(_ p: PanelPen) {
        p.heading("PAINT")
        p.row(MapTool.allCases.map { t in (t.rawValue, mapTool == t, { [unowned self] in mapTool = t }) }, small: true)
        switch mapTool {
        case .ground:
            p.grid(TileGroup.allCases.map { g in (g.rawValue, tileGroup == g, { [unowned self] in tileGroup = g }) },
                   columns: 4, small: true)
            let list = templates(in: tileGroup)
            if list.isEmpty { p.note("THIS THEATER HAS NONE.") }
            p.thumbnails(list.map { t in
                (templateTable[t].icnName, brushTemplate == t, { [unowned self] rect in drawTemplate(t, in: rect) },
                 { [unowned self] in brushTemplate = brushTemplate == t ? nil : t })
            }, columns: 3, height: 74)
        case .trees:
            let list = terrainObjectTypes.filter(terrainAvailable)
            p.thumbnails(list.map { t in
                (t, brushTerrain == t, { [unowned self] rect in drawTerrainObject(t, in: rect) },
                 { [unowned self] in brushTerrain = brushTerrain == t ? nil : t })
            }, columns: 4, height: 64)
        case .erase:
            p.note("CLICK OR DRAG ON THE MAP: A TREE OR ROCK GOES FIRST, THEN THE GROUND UNDER IT BECOMES CLEAR.")
        }
        let b = doc.data.mapBounds ?? MapBounds(x: 1, y: 1, width: 62, height: 62)
        p.heading("PLAY AREA")
        p.note("THE PART OF THE 64 X 64 MAP THE MISSION USES. OUTSIDE IT IS DARK.")
        p.stepper("LEFT", "\(b.x)", { [unowned self] in setBounds { $0.x -= 1 } }, { [unowned self] in setBounds { $0.x += 1 } })
        p.stepper("TOP", "\(b.y)", { [unowned self] in setBounds { $0.y -= 1 } }, { [unowned self] in setBounds { $0.y += 1 } })
        p.stepper("WIDTH", "\(b.width)", { [unowned self] in setBounds { $0.w -= 1 } }, { [unowned self] in setBounds { $0.w += 1 } })
        p.stepper("HEIGHT", "\(b.height)", { [unowned self] in setBounds { $0.h -= 1 } }, { [unowned self] in setBounds { $0.h += 1 } })
    }

    /// A template's tiles, scaled to fit `rect`.
    func drawTemplate(_ template: Int, in rect: SDL_Rect) {
        let t = templateTable[template]
        let side = min((rect.w - 8) / Int32(t.width), (rect.h - 8) / Int32(t.height), 24)
        let ox = rect.x + (rect.w - side * Int32(t.width)) / 2
        let oy = rect.y + (rect.h - side * Int32(t.height)) / 2
        for c in stampCells(template, at: 0) {
            guard let tex = getTileTexture(renderState.sdlRenderer, icnName: t.icnName, iconIndex: c.icon,
                                           theater: doc.data.theater) else { continue }
            let (dx, dy) = cellToXY(c.cell)
            var dst = SDL_Rect(x: ox + Int32(dx) * side, y: oy + Int32(dy) * side, w: side, h: side)
            SDL_RenderCopy(renderState.sdlRenderer, tex, nil, &dst)
        }
    }

    func drawTerrainObject(_ type: String, in rect: SDL_Rect) {
        guard let info = getTerrainTexture(renderState.sdlRenderer, typeName: type, theater: doc.data.theater) else { return }
        let scale = min(1.0, Double(rect.w - 6) / Double(info.width), Double(rect.h - 6) / Double(info.height))
        let w = Int32(Double(info.width) * scale), h = Int32(Double(info.height) * scale)
        var dst = SDL_Rect(x: rect.x + (rect.w - w) / 2, y: rect.y + (rect.h - h) / 2, w: w, h: h)
        SDL_RenderCopy(renderState.sdlRenderer, info.texture, nil, &dst)
    }

    // MARK: On the map

    var mapHint: String {
        switch mapTool {
        case .ground where brushTemplate == nil: return "PICK A GROUND PIECE ON THE RIGHT, THEN CLICK OR DRAG ON THE MAP"
        case .ground: return "CLICK OR DRAG TO PAINT \(templateTable[brushTemplate!].icnName). RIGHT DRAG PANS"
        case .trees where brushTerrain == nil: return "PICK A TREE OR ROCK ON THE RIGHT, THEN CLICK THE MAP"
        case .trees: return "CLICK TO PLACE \(brushTerrain!). RIGHT DRAG PANS"
        case .erase: return "CLICK OR DRAG TO ERASE. RIGHT DRAG PANS"
        }
    }

    func drawMapToolOverlays(_ r: OpaquePointer?) {
        // The play area.
        if let b = doc.data.mapBounds {
            outline(r, cellRect(b.y * 64 + b.x, w: b.width, h: b.height), .amber, thick: 2)
        }
        guard let cell = cellUnderMouse() else { return }
        switch mapTool {
        case .ground:
            guard let template = brushTemplate else { return }
            let t = templateTable[template]
            for c in stampCells(template, at: cell) {
                guard let tex = getTileTexture(r, icnName: t.icnName, iconIndex: c.icon, theater: doc.data.theater) else { continue }
                var dst = cellRect(c.cell)
                SDL_SetTextureAlphaMod(tex, 170)
                SDL_RenderCopy(r, tex, nil, &dst)
                SDL_SetTextureAlphaMod(tex, 255)
            }
            outline(r, cellRect(cell, w: t.width, h: t.height), .brightGreen, thick: 1)
        case .trees:
            outline(r, cellRect(cell), .brightGreen, thick: 1)
        case .erase:
            outline(r, cellRect(cell), .red, thick: 2)
        }
    }
}
