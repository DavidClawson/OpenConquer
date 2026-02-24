import CSDL2
import Foundation

// MARK: - Sidebar Constants

let sidebarWidth: Int32 = 160

// MARK: - Credits & Production State

var sidebarCredits: Int = 5000
var displayedCredits: Int = 0  // Animated credit counter

/// Unit build queue (one at a time)
var unitBuildQueue: (typeName: String, progress: Int, cost: Int, totalTicks: Int)? = nil
/// Structure build queue (one at a time)
var structureBuildQueue: (typeName: String, progress: Int, cost: Int, totalTicks: Int)? = nil

/// Placement mode for structures
var isPlacingStructure: Bool = false
var placementType: String? = nil

// MARK: - Build Data (derived from type data tables)

struct BuildableItem {
    let name: String
    let cost: Int
    let buildTicks: Int
    let prerequisite: String?
    let faction: String?  // "GDI", "NOD", or nil for both
}

struct BuildableStructure {
    let name: String
    let cost: Int
    let buildTicks: Int
    let faction: String?
}

/// Generate unit/infantry build list from type data tables
func generateBuildableUnits() -> [BuildableItem] {
    var items: [BuildableItem] = []

    // Infantry from infantryTypeDataTable
    for (_, data) in infantryTypeDataTable {
        guard data.isBuildable else { continue }
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue  // Not buildable by GDI or Nod
        }
        // Infantry need PYLE (GDI) or HAND (Nod) — use prerequisite field if set
        let prereq: String?
        if data.prerequisite != .none {
            prereq = nil  // Has specific prerequisite from struct flags
        } else {
            prereq = faction == "NOD" ? "HAND" : (faction == "GDI" ? "PYLE" : nil)
        }
        let ticks = max(20, data.cost / 5)
        items.append(BuildableItem(name: data.iniName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction))
    }

    // Vehicles from unitTypeDataTable
    for (_, data) in unitTypeDataTable {
        guard data.isBuildable else { continue }
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue
        }
        // Vehicles need WEAP (or PROC for HARV)
        let prereq: String
        if data.iniName == "HARV" {
            prereq = "PROC"
        } else if data.iniName == "MCV" {
            prereq = "WEAP"
        } else {
            prereq = "WEAP"
        }
        let ticks = max(30, data.cost / 5)
        items.append(BuildableItem(name: data.iniName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction))
    }

    // Aircraft from aircraftTypeDataTable
    for (_, data) in aircraftTypeDataTable {
        guard data.isBuildable else { continue }
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue
        }
        // Aircraft need HPAD or AFLD
        let prereq: String = faction == "NOD" ? "AFLD" : "HPAD"
        let ticks = max(30, data.cost / 5)
        items.append(BuildableItem(name: data.iniName, cost: data.cost,
                                   buildTicks: ticks, prerequisite: prereq, faction: faction))
    }

    // Sort by cost for consistent ordering
    items.sort { $0.cost < $1.cost }
    return items
}

/// Generate structure build list from type data tables
func generateBuildableStructures() -> [BuildableStructure] {
    var items: [BuildableStructure] = []

    for (_, data) in buildingTypeDataTable {
        guard data.isBuildable else { continue }
        guard !data.isWall else { continue }  // Walls aren't sidebar buildable
        let faction: String?
        if data.ownable.contains(.good) && data.ownable.contains(.bad) {
            faction = nil
        } else if data.ownable.contains(.good) {
            faction = "GDI"
        } else if data.ownable.contains(.bad) {
            faction = "NOD"
        } else {
            continue
        }
        let ticks = max(30, data.cost / 5)
        items.append(BuildableStructure(name: data.iniName, cost: data.cost,
                                        buildTicks: ticks, faction: faction))
    }

    // Sort by cost for consistent ordering
    items.sort { $0.cost < $1.cost }
    return items
}

// Lazy-initialized build lists from type data
private var _buildableUnits: [BuildableItem]? = nil
private var _buildableStructures: [BuildableStructure]? = nil

var buildableUnits: [BuildableItem] {
    if _buildableUnits == nil { _buildableUnits = generateBuildableUnits() }
    return _buildableUnits!
}

var buildableStructures: [BuildableStructure] {
    if _buildableStructures == nil { _buildableStructures = generateBuildableStructures() }
    return _buildableStructures!
}

// MARK: - Query Functions

/// Get the set of building type names owned by the player
func getOwnedBuildingTypes() -> Set<String> {
    guard let world = gameWorld else { return [] }
    var owned = Set<String>()
    for obj in world.objects {
        if obj.kind == .structure && obj.house == world.playerHouse && obj.strength > 0 {
            owned.insert(obj.typeName.uppercased())
        }
    }
    return owned
}

/// Get available units the player can build
func getAvailableUnits() -> [BuildableItem] {
    let owned = getOwnedBuildingTypes()
    let faction = gameWorld?.playerHouse == .goodGuy ? "GDI" : "NOD"
    var seen = Set<String>()
    var result: [BuildableItem] = []
    for item in buildableUnits {
        if let prereq = item.prerequisite, !owned.contains(prereq) { continue }
        if let f = item.faction, f != faction { continue }
        if seen.contains(item.name) { continue }
        seen.insert(item.name)
        result.append(item)
    }
    return result
}

/// Get available structures the player can build
func getAvailableStructures() -> [BuildableStructure] {
    let owned = getOwnedBuildingTypes()
    let faction = gameWorld?.playerHouse == .goodGuy ? "GDI" : "NOD"
    // Need a construction yard to build structures
    if !owned.contains("FACT") { return [] }
    var result: [BuildableStructure] = []
    for item in buildableStructures {
        if let f = item.faction, f != faction { continue }
        result.append(item)
    }
    return result
}

// MARK: - Sidebar Rendering

/// Sidebar scroll offset for the build list
var sidebarScrollOffset: Int = 0
/// Which tab: 0 = units, 1 = structures
var sidebarTab: Int = 0

func renderSidebar(_ renderer: OpaquePointer?) {
    guard gameWorld != nil else { return }
    let sx = windowWidth - sidebarWidth

    // Background
    SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
    var bg = SDL_Rect(x: sx, y: 0, w: sidebarWidth, h: windowHeight)
    SDL_RenderFillRect(renderer, &bg)

    // Border line
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
    SDL_RenderDrawLine(renderer, sx, 0, sx, windowHeight)

    // Credits display
    // Animate credits counter toward actual value
    if displayedCredits < sidebarCredits {
        displayedCredits = min(sidebarCredits, displayedCredits + max(1, (sidebarCredits - displayedCredits) / 8))
    } else if displayedCredits > sidebarCredits {
        displayedCredits = max(sidebarCredits, displayedCredits - max(1, (displayedCredits - sidebarCredits) / 8))
    }

    drawText(renderer, "CREDITS", centerX: sx + sidebarWidth / 2, centerY: 10, color: .amber, scale: 1)
    drawText(renderer, "$\(displayedCredits)", centerX: sx + sidebarWidth / 2, centerY: 24, color: .green, scale: 2)

    // Power bar
    renderPowerBar(renderer, sx: sx)

    // Tab buttons
    let tabY: Int32 = 50
    let tabW: Int32 = sidebarWidth / 2
    let tabH: Int32 = 20

    // Units tab
    let unitTabColor: (r: UInt8, g: UInt8, b: UInt8) = sidebarTab == 0 ? (0, 180, 0) : (60, 60, 60)
    SDL_SetRenderDrawColor(renderer, unitTabColor.r, unitTabColor.g, unitTabColor.b, 255)
    var unitTab = SDL_Rect(x: sx, y: tabY, w: tabW, h: tabH)
    SDL_RenderFillRect(renderer, &unitTab)
    drawText(renderer, "UNITS", centerX: sx + tabW / 2, centerY: tabY + tabH / 2, color: .white, scale: 1)

    // Structures tab
    let structTabColor: (r: UInt8, g: UInt8, b: UInt8) = sidebarTab == 1 ? (0, 180, 0) : (60, 60, 60)
    SDL_SetRenderDrawColor(renderer, structTabColor.r, structTabColor.g, structTabColor.b, 255)
    var structTab = SDL_Rect(x: sx + tabW, y: tabY, w: tabW, h: tabH)
    SDL_RenderFillRect(renderer, &structTab)
    drawText(renderer, "BUILD", centerX: sx + tabW + tabW / 2, centerY: tabY + tabH / 2, color: .white, scale: 1)

    // Build list
    let listY: Int32 = tabY + tabH + 4
    let buttonW: Int32 = sidebarWidth - 8
    let buttonH: Int32 = 48
    let buttonSpacing: Int32 = 2
    let iconSize: Int32 = 40

    if sidebarTab == 0 {
        // Unit build list
        let available = getAvailableUnits()
        for (i, item) in available.enumerated() {
            let by = listY + Int32(i) * (buttonH + buttonSpacing)
            if by + buttonH > windowHeight - 70 { break }

            let isBuilding = unitBuildQueue?.typeName == item.name
            let canAfford = sidebarCredits >= item.cost

            // Button background
            if isBuilding {
                SDL_SetRenderDrawColor(renderer, 0, 80, 0, 255)
            } else if canAfford {
                SDL_SetRenderDrawColor(renderer, 50, 50, 50, 255)
            } else {
                SDL_SetRenderDrawColor(renderer, 40, 30, 30, 255)
            }
            var btnRect = SDL_Rect(x: sx + 4, y: by, w: buttonW, h: buttonH)
            SDL_RenderFillRect(renderer, &btnRect)

            // Border
            SDL_SetRenderDrawColor(renderer, canAfford ? 100 : 60, canAfford ? 100 : 40, canAfford ? 100 : 40, 255)
            SDL_RenderDrawRect(renderer, &btnRect)

            // Cameo icon (sprite frame 0)
            let house = gameWorld?.playerHouse ?? .goodGuy
            let theater = gameWorld?.theater ?? .temperate
            if let tex = getObjectTexture(renderer, typeName: item.name, frame: 0, house: house, theater: theater) {
                let scale = min(Float(iconSize) / Float(tex.width), Float(iconSize) / Float(tex.height))
                let drawW = Int32(Float(tex.width) * scale)
                let drawH = Int32(Float(tex.height) * scale)
                let iconX = sx + 6 + (iconSize - drawW) / 2
                let iconY = by + (buttonH - drawH) / 2
                var dstRect = SDL_Rect(x: iconX, y: iconY, w: drawW, h: drawH)
                SDL_RenderCopy(renderer, tex.texture, nil, &dstRect)
            }

            // Label (offset right to make room for icon)
            let textColor: Color = canAfford ? .green : .red
            drawText(renderer, item.name, centerX: sx + iconSize + 20, centerY: by + buttonH / 2 - 6, color: textColor, scale: 1)
            drawText(renderer, "$\(item.cost)", centerX: sx + iconSize + 20, centerY: by + buttonH / 2 + 8, color: .gray, scale: 1)

            // Progress bar
            if isBuilding, let queue = unitBuildQueue {
                let progress = Double(queue.progress) / Double(queue.totalTicks)
                let barW = Int32(Double(buttonW - 4) * progress)
                SDL_SetRenderDrawColor(renderer, 0, 200, 0, 100)
                var barRect = SDL_Rect(x: sx + 6, y: by + buttonH - 5, w: barW, h: 3)
                SDL_RenderFillRect(renderer, &barRect)
            }
        }

        if available.isEmpty {
            drawText(renderer, "No production", centerX: sx + sidebarWidth / 2, centerY: listY + 30, color: .gray, scale: 1)
            drawText(renderer, "buildings", centerX: sx + sidebarWidth / 2, centerY: listY + 45, color: .gray, scale: 1)
        }
    } else {
        // Structure build list
        let available = getAvailableStructures()
        for (i, item) in available.enumerated() {
            let by = listY + Int32(i) * (buttonH + buttonSpacing)
            if by + buttonH > windowHeight - 70 { break }

            let isBuilding = structureBuildQueue?.typeName == item.name
            let isReady = isBuilding && structureBuildQueue!.progress >= structureBuildQueue!.totalTicks
            let canAfford = sidebarCredits >= item.cost

            // Button background
            if isReady {
                SDL_SetRenderDrawColor(renderer, 0, 120, 0, 255)
            } else if isBuilding {
                SDL_SetRenderDrawColor(renderer, 0, 80, 0, 255)
            } else if canAfford {
                SDL_SetRenderDrawColor(renderer, 50, 50, 50, 255)
            } else {
                SDL_SetRenderDrawColor(renderer, 40, 30, 30, 255)
            }
            var btnRect = SDL_Rect(x: sx + 4, y: by, w: buttonW, h: buttonH)
            SDL_RenderFillRect(renderer, &btnRect)

            // Border
            SDL_SetRenderDrawColor(renderer, canAfford ? 100 : 60, canAfford ? 100 : 40, canAfford ? 100 : 40, 255)
            SDL_RenderDrawRect(renderer, &btnRect)

            // Cameo icon (sprite frame 0)
            let house = gameWorld?.playerHouse ?? .goodGuy
            let theater = gameWorld?.theater ?? .temperate
            if let tex = getObjectTexture(renderer, typeName: item.name, frame: 0, house: house, theater: theater) {
                let scale = min(Float(iconSize) / Float(tex.width), Float(iconSize) / Float(tex.height))
                let drawW = Int32(Float(tex.width) * scale)
                let drawH = Int32(Float(tex.height) * scale)
                let iconX = sx + 6 + (iconSize - drawW) / 2
                let iconY = by + (buttonH - drawH) / 2
                var dstRect = SDL_Rect(x: iconX, y: iconY, w: drawW, h: drawH)
                SDL_RenderCopy(renderer, tex.texture, nil, &dstRect)
            }

            // Label (offset right to make room for icon)
            let textColor: Color = isReady ? .amber : (canAfford ? .green : .red)
            let label = isReady ? "\(item.name) READY" : item.name
            drawText(renderer, label, centerX: sx + iconSize + 20, centerY: by + buttonH / 2 - 6, color: textColor, scale: 1)
            if !isReady {
                drawText(renderer, "$\(item.cost)", centerX: sx + iconSize + 20, centerY: by + buttonH / 2 + 8, color: .gray, scale: 1)
            }

            // Progress bar
            if isBuilding, let queue = structureBuildQueue, !isReady {
                let progress = Double(queue.progress) / Double(queue.totalTicks)
                let barW = Int32(Double(buttonW - 4) * progress)
                SDL_SetRenderDrawColor(renderer, 0, 200, 0, 100)
                var barRect = SDL_Rect(x: sx + 6, y: by + buttonH - 5, w: barW, h: 3)
                SDL_RenderFillRect(renderer, &barRect)
            }
        }

        if available.isEmpty {
            drawText(renderer, "Need FACT", centerX: sx + sidebarWidth / 2, centerY: listY + 30, color: .gray, scale: 1)
            drawText(renderer, "(Constr Yard)", centerX: sx + sidebarWidth / 2, centerY: listY + 45, color: .gray, scale: 1)
        }
    }

    // Repair/Sell buttons
    renderRepairSellButtons(renderer)

    // Placement mode indicator
    if isPlacingStructure, let pType = placementType {
        drawText(renderer, "PLACE: \(pType)", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 85, color: .amber, scale: 1)
        drawText(renderer, "Click to place", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 75, color: .green, scale: 1)
    }

    // Super weapons display
    renderSuperWeaponButtons(renderer)

    // Repair/Sell mode indicators
    if isRepairMode {
        drawText(renderer, "Click building", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 30, color: .amber, scale: 1)
        drawText(renderer, "to REPAIR", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 18, color: .green, scale: 1)
    } else if isSellMode {
        drawText(renderer, "Click building", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 30, color: .amber, scale: 1)
        drawText(renderer, "to SELL", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 18, color: .red, scale: 1)
    } else if superWeaponTargeting != nil {
        drawText(renderer, "Click target", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 30, color: .amber, scale: 1)
        drawText(renderer, "for STRIKE", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 18, color: .red, scale: 1)
    }
}

// MARK: - Sidebar Click Handling

func handleSidebarClick(_ x: Int32, _ y: Int32) {
    let sx = windowWidth - sidebarWidth

    // Tab selection
    let tabY: Int32 = 50
    let tabH: Int32 = 20
    if y >= tabY && y < tabY + tabH {
        if x < sx + sidebarWidth / 2 {
            sidebarTab = 0
        } else {
            sidebarTab = 1
        }
        return
    }

    // Build list clicks
    let listY = tabY + tabH + 4
    let buttonH: Int32 = 48
    let buttonSpacing: Int32 = 2

    let clickIdx = Int((y - listY) / (buttonH + buttonSpacing))
    if clickIdx < 0 { return }

    if sidebarTab == 0 {
        let available = getAvailableUnits()
        if clickIdx < available.count {
            let item = available[clickIdx]
            if unitBuildQueue == nil && sidebarCredits >= item.cost {
                unitBuildQueue = (typeName: item.name, progress: 0, cost: item.cost, totalTicks: item.buildTicks)
                sidebarCredits -= item.cost
                speak(.building)
            } else if sidebarCredits < item.cost {
                speak(.noCash)
                soundEffect(.scold)
            }
        }
    } else {
        let available = getAvailableStructures()
        if clickIdx < available.count {
            let item = available[clickIdx]

            // If structure is ready, enter placement mode
            if let queue = structureBuildQueue, queue.typeName == item.name,
               queue.progress >= queue.totalTicks {
                isPlacingStructure = true
                placementType = item.name
                return
            }

            if structureBuildQueue == nil && sidebarCredits >= item.cost {
                structureBuildQueue = (typeName: item.name, progress: 0, cost: item.cost, totalTicks: item.buildTicks)
                sidebarCredits -= item.cost
                speak(.building)
            } else if sidebarCredits < item.cost {
                speak(.noCash)
                soundEffect(.scold)
            }
        }
    }
}

// MARK: - Production Tick

func tickProduction() {
    guard let world = gameWorld else { return }

    // Advance unit production
    if var queue = unitBuildQueue {
        queue.progress += 1
        if queue.progress >= queue.totalTicks {
            // Unit complete — spawn it
            spawnProducedUnit(queue.typeName, world: world)
            unitBuildQueue = nil
            speak(.unitReady)
            soundEffect(.construction)
        } else {
            unitBuildQueue = queue
        }
    }

    // Advance structure production
    if var queue = structureBuildQueue {
        if queue.progress < queue.totalTicks {
            queue.progress += 1
            structureBuildQueue = queue
            if queue.progress >= queue.totalTicks {
                speak(.construction)
                soundEffect(.construction)
            }
        }
        // Don't auto-complete — wait for placement
    }
}

// MARK: - Unit Spawning

func spawnProducedUnit(_ typeName: String, world: GameWorld) {
    let upper = typeName.uppercased()

    // Check if this is an aircraft
    if let acType = AircraftType.from(iniName: upper) {
        // Aircraft spawn at helipad or airstrip
        let padType = world.playerHouse == .badGuy ? "AFLD" : "HPAD"
        guard let pad = world.objects.first(where: {
            $0.kind == .structure && $0.typeName.uppercased() == padType &&
            $0.house == world.playerHouse && $0.strength > 0
        }) else { return }

        let obj = createAircraft(
            world: world,
            type: acType,
            house: world.playerHouse,
            worldX: pad.worldX,
            worldY: pad.worldY,
            facing: 0,
            mission: .guard_
        )
        world.addObject(obj)
        return
    }

    // Find the producing structure
    let producerType: String
    if ["E1", "E2", "E3", "E4", "E5", "E6", "RMBO"].contains(upper) {
        producerType = getOwnedBuildingTypes().contains("PYLE") ? "PYLE" : "HAND"
    } else {
        producerType = "WEAP"
    }

    // Find the producing structure
    guard let producer = world.objects.first(where: {
        $0.kind == .structure && $0.typeName.uppercased() == producerType && $0.house == world.playerHouse && $0.strength > 0
    }) else { return }

    // Spawn near the exit of the producing structure
    let size = buildingSize(producerType)
    let exitX = producer.worldX + Double(size.w * 24) / 2.0 + 12.0
    let exitY = producer.worldY + Double(size.h * 24) / 2.0

    let isInfantry = ["E1", "E2", "E3", "E4", "E5", "E6", "E7", "RMBO"].contains(upper)
    let kind: ObjectKind = isInfantry ? .infantry : .unit
    let speed = resolveSpeed(typeName: upper, kind: kind)

    let obj = GameObject(
        id: world.allocateId(),
        typeName: typeName,
        house: world.playerHouse,
        kind: kind,
        worldX: exitX, worldY: exitY,
        facing: 128,  // Face south
        strength: resolveStrength(typeName: upper, kind: kind, scenarioStrength: 256),
        mission: upper == "HARV" ? .harvest : .guard_,
        speed: speed
    )
    world.addObject(obj)
}

// MARK: - Structure Placement

func handleStructurePlacement(_ x: Int32, _ y: Int32) {
    guard let world = gameWorld, let pType = placementType else { return }
    let worldPos = gameScreenToWorld(x, y)

    let cellX = Int(worldPos.worldX) / 24
    let cellY = Int(worldPos.worldY) / 24
    let size = buildingSize(pType)

    // Check if area is passable
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let cx = cellX + dx
            let cy = cellY + dy
            if cx < 0 || cx >= 64 || cy < 0 || cy >= 64 { return }
            let cell = cy * 64 + cx
            if !staticPassability[cell] { return }
        }
    }

    // Place the structure
    let pos = cellToPixel(cellY * 64 + cellX)
    let cx = Double(pos.px) + Double(size.w * 24) / 2.0
    let cy = Double(pos.py) + Double(size.h * 24) / 2.0

    let obj = GameObject(
        id: world.allocateId(),
        typeName: pType,
        house: world.playerHouse,
        kind: .structure,
        worldX: cx, worldY: cy,
        facing: 0,
        strength: resolveStrength(typeName: pType, kind: .structure, scenarioStrength: 256),
        mission: .guard_,
        speed: 0.0
    )
    world.addObject(obj)

    // Mark footprint as impassable
    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let cell = (cellY + dy) * 64 + (cellX + dx)
            staticPassability[cell] = false
        }
    }

    // Clear placement mode
    isPlacingStructure = false
    placementType = nil
    structureBuildQueue = nil
}

// MARK: - Power Bar Rendering

func renderPowerBar(_ renderer: OpaquePointer?, sx: Int32) {
    guard let world = gameWorld else { return }
    let playerHouse = world.playerHouse
    let houseState = getHouseState(playerHouse)

    let barX = sx + 4
    let barY: Int32 = 36
    let barW: Int32 = sidebarWidth - 8
    let barH: Int32 = 12

    // Background
    SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255)
    var bgRect = SDL_Rect(x: barX, y: barY, w: barW, h: barH)
    SDL_RenderFillRect(renderer, &bgRect)

    // Power level indicator
    let maxVal = max(1, max(houseState.powerOutput, houseState.powerDrain))
    let outputFrac = min(1.0, Double(houseState.powerOutput) / Double(maxVal))
    let drainFrac = min(1.0, Double(houseState.powerDrain) / Double(maxVal))

    // Green bar = power output
    let greenW = Int32(Double(barW) * outputFrac)
    SDL_SetRenderDrawColor(renderer, 0, 180, 0, 255)
    var greenRect = SDL_Rect(x: barX, y: barY, w: greenW, h: barH / 2)
    SDL_RenderFillRect(renderer, &greenRect)

    // Yellow/red bar = power drain
    let drainW = Int32(Double(barW) * drainFrac)
    let drainColor: (r: UInt8, g: UInt8, b: UInt8) = houseState.hasPower ? (180, 180, 0) : (200, 40, 0)
    SDL_SetRenderDrawColor(renderer, drainColor.r, drainColor.g, drainColor.b, 255)
    var drainRect = SDL_Rect(x: barX, y: barY + barH / 2, w: drainW, h: barH / 2)
    SDL_RenderFillRect(renderer, &drainRect)

    // Border
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
    SDL_RenderDrawRect(renderer, &bgRect)

    // Label
    let powerLabel = houseState.isLowPower ? "LOW PWR" : "POWER"
    let powerColor: Color = houseState.isLowPower ? .red : .green
    drawText(renderer, powerLabel, centerX: sx + sidebarWidth / 2, centerY: barY + barH / 2, color: powerColor, scale: 1)
}

// MARK: - Repair / Sell Mode

var isRepairMode: Bool = false
var isSellMode: Bool = false

/// Handle repair/sell button clicks (below the build list)
func handleRepairSellClick(_ x: Int32, _ y: Int32) -> Bool {
    let sx = windowWidth - sidebarWidth
    let buttonY = windowHeight - 60
    let buttonW: Int32 = (sidebarWidth - 12) / 2
    let buttonH: Int32 = 20

    // Repair button
    if x >= sx + 4 && x < sx + 4 + buttonW && y >= buttonY && y < buttonY + buttonH {
        isRepairMode = !isRepairMode
        isSellMode = false
        return true
    }

    // Sell button
    if x >= sx + 8 + buttonW && x < sx + 8 + buttonW * 2 && y >= buttonY && y < buttonY + buttonH {
        isSellMode = !isSellMode
        isRepairMode = false
        return true
    }

    return false
}

/// Apply repair/sell click to a structure in the game world
func handleRepairSellGameClick(worldX: Double, worldY: Double) -> Bool {
    guard let world = gameWorld else { return false }

    // Find player structure under click
    for obj in world.objects {
        if obj.kind != .structure { continue }
        if obj.house != world.playerHouse { continue }
        if obj.strength <= 0 { continue }

        let size = buildingSize(obj.typeName)
        let halfW = Double(size.w * 24) / 2.0
        let halfH = Double(size.h * 24) / 2.0
        let dx = worldX - obj.worldX
        let dy = worldY - obj.worldY

        if abs(dx) <= halfW && abs(dy) <= halfH {
            if isRepairMode {
                // Toggle repair on this building
                if obj.isRepairing {
                    obj.isRepairing = false
                    obj.mission = .guard_
                } else if obj.strength < obj.maxStrength {
                    obj.isRepairing = true
                    obj.mission = .repair
                }
                isRepairMode = false
                return true
            } else if isSellMode {
                // Sell this building
                obj.mission = .selling
                isSellMode = false
                return true
            }
        }
    }
    return false
}

// MARK: - Repair/Sell Buttons Rendering

func renderRepairSellButtons(_ renderer: OpaquePointer?) {
    let sx = windowWidth - sidebarWidth
    let buttonY = windowHeight - 60
    let buttonW: Int32 = (sidebarWidth - 12) / 2
    let buttonH: Int32 = 20

    // Repair button
    let repairColor: (r: UInt8, g: UInt8, b: UInt8) = isRepairMode ? (0, 120, 0) : (50, 50, 50)
    SDL_SetRenderDrawColor(renderer, repairColor.r, repairColor.g, repairColor.b, 255)
    var repairRect = SDL_Rect(x: sx + 4, y: buttonY, w: buttonW, h: buttonH)
    SDL_RenderFillRect(renderer, &repairRect)
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255)
    SDL_RenderDrawRect(renderer, &repairRect)
    drawText(renderer, "REPAIR", centerX: sx + 4 + buttonW / 2, centerY: buttonY + buttonH / 2,
             color: isRepairMode ? .amber : .green, scale: 1)

    // Sell button
    let sellColor: (r: UInt8, g: UInt8, b: UInt8) = isSellMode ? (120, 0, 0) : (50, 50, 50)
    SDL_SetRenderDrawColor(renderer, sellColor.r, sellColor.g, sellColor.b, 255)
    var sellRect = SDL_Rect(x: sx + 8 + buttonW, y: buttonY, w: buttonW, h: buttonH)
    SDL_RenderFillRect(renderer, &sellRect)
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255)
    SDL_RenderDrawRect(renderer, &sellRect)
    drawText(renderer, "SELL", centerX: sx + 8 + buttonW + buttonW / 2, centerY: buttonY + buttonH / 2,
             color: isSellMode ? .amber : .red, scale: 1)
}

// MARK: - Super Weapon Buttons

let superWeaponButtonY: Int32 = 42  // Below credits, above tabs

func renderSuperWeaponButtons(_ renderer: OpaquePointer?) {
    let sx = windowWidth - sidebarWidth

    // Only render if any super weapon is present
    let weapons: [(SuperWeapon, String, (r: UInt8, g: UInt8, b: UInt8))] = [
        (playerIonCannon, "ION", (r: 100, g: 180, b: 255)),
        (playerAirStrike, "AIR", (r: 200, g: 200, b: 100)),
        (playerNukeStrike, "NUKE", (r: 255, g: 80, b: 80)),
    ]

    var x = sx + 4
    let y = superWeaponButtonY
    let bw: Int32 = (sidebarWidth - 16) / 3
    let bh: Int32 = 18

    for (weapon, label, color) in weapons {
        guard weapon.isPresent else {
            x += bw + 2
            continue
        }

        // Background: darker when charging, bright when ready
        if weapon.isReady {
            SDL_SetRenderDrawColor(renderer, color.r / 2, color.g / 2, color.b / 2, 255)
        } else {
            SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
        }
        var rect = SDL_Rect(x: x, y: y, w: bw, h: bh)
        SDL_RenderFillRect(renderer, &rect)

        // Charge bar
        if !weapon.isReady {
            let fillW = Int32(Double(bw - 2) * weapon.chargeFraction)
            SDL_SetRenderDrawColor(renderer, color.r / 3, color.g / 3, color.b / 3, 200)
            var fillRect = SDL_Rect(x: x + 1, y: y + 1, w: fillW, h: bh - 2)
            SDL_RenderFillRect(renderer, &fillRect)
        }

        // Border: highlight when ready
        if weapon.isReady {
            SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, 255)
        } else if weapon.isSuspended {
            SDL_SetRenderDrawColor(renderer, 80, 80, 0, 255)
        } else {
            SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
        }
        SDL_RenderDrawRect(renderer, &rect)

        // Label
        let textColor: Color = weapon.isReady ? .green : (weapon.isSuspended ? .red : .gray)
        drawText(renderer, label, centerX: x + bw / 2, centerY: y + bh / 2, color: textColor, scale: 1)

        x += bw + 2
    }
}

/// Handle click on super weapon buttons, returns true if handled
func handleSuperWeaponClick(_ screenX: Int32, _ screenY: Int32) -> Bool {
    let sx = windowWidth - sidebarWidth
    let y = superWeaponButtonY
    let bw: Int32 = (sidebarWidth - 16) / 3
    let bh: Int32 = 18

    guard screenY >= y && screenY <= y + bh else { return false }
    guard screenX >= sx + 4 else { return false }

    let relX = screenX - (sx + 4)
    let index = Int(relX / (bw + 2))

    let weapons: [(SuperWeapon, SpecialWeaponType)] = [
        (playerIonCannon, .ionCannon),
        (playerAirStrike, .airStrike),
        (playerNukeStrike, .nuclearStrike),
    ]

    guard index >= 0 && index < weapons.count else { return false }
    let (weapon, type) = weapons[index]

    guard weapon.isPresent else { return false }

    if weapon.isReady {
        startSuperWeaponTargeting(type)
        return true
    } else {
        print("SuperWeapon: \(type) not ready yet (\(Int(weapon.chargeFraction * 100))%)")
        return true
    }
}

/// Handle game click when in super weapon targeting mode
func handleSuperWeaponGameClick(worldX: Double, worldY: Double) -> Bool {
    guard let type = superWeaponTargeting else { return false }
    deploySuperWeapon(type, worldX: worldX, worldY: worldY)
    return true
}

// MARK: - Placement Preview Rendering

func renderPlacementPreview(_ renderer: OpaquePointer?, mouseScreenX: Int32, mouseScreenY: Int32) {
    guard let pType = placementType else { return }
    let worldPos = gameScreenToWorld(mouseScreenX, mouseScreenY)
    let cellX = Int(worldPos.worldX) / 24
    let cellY = Int(worldPos.worldY) / 24
    let size = buildingSize(pType)
    let camX = Int(gameCameraX)
    let camY = Int(gameCameraY)

    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    for dy in 0..<size.h {
        for dx in 0..<size.w {
            let cx = cellX + dx
            let cy = cellY + dy
            let screenX = Int32(cx * 24 - camX)
            let screenY = Int32(cy * 24 - camY)
            var rect = SDL_Rect(x: screenX, y: screenY, w: 24, h: 24)

            let passable: Bool
            if cx >= 0 && cx < 64 && cy >= 0 && cy < 64 {
                passable = staticPassability[cy * 64 + cx]
            } else {
                passable = false
            }

            if passable {
                SDL_SetRenderDrawColor(renderer, 0, 255, 0, 80)
            } else {
                SDL_SetRenderDrawColor(renderer, 255, 0, 0, 80)
            }
            SDL_RenderFillRect(renderer, &rect)
            SDL_SetRenderDrawColor(renderer, 0, 255, 0, 200)
            SDL_RenderDrawRect(renderer, &rect)
        }
    }
}
