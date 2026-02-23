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

// MARK: - Build Data

struct BuildableItem {
    let name: String
    let cost: Int
    let buildTicks: Int
    let prerequisite: String?
    let faction: String?  // "GDI", "NOD", or nil for both
}

let buildableUnits: [BuildableItem] = [
    BuildableItem(name: "E1",   cost: 100,  buildTicks: 30,  prerequisite: "PYLE", faction: nil),
    BuildableItem(name: "E2",   cost: 160,  buildTicks: 35,  prerequisite: "PYLE", faction: nil),
    BuildableItem(name: "E3",   cost: 300,  buildTicks: 50,  prerequisite: "PYLE", faction: nil),
    BuildableItem(name: "E1",   cost: 100,  buildTicks: 30,  prerequisite: "HAND", faction: nil),
    BuildableItem(name: "E2",   cost: 160,  buildTicks: 35,  prerequisite: "HAND", faction: nil),
    BuildableItem(name: "E3",   cost: 300,  buildTicks: 50,  prerequisite: "HAND", faction: nil),
    BuildableItem(name: "E4",   cost: 200,  buildTicks: 35,  prerequisite: "HAND", faction: "NOD"),
    BuildableItem(name: "MTNK", cost: 800,  buildTicks: 100, prerequisite: "WEAP", faction: nil),
    BuildableItem(name: "LTNK", cost: 600,  buildTicks: 80,  prerequisite: "WEAP", faction: "NOD"),
    BuildableItem(name: "HTNK", cost: 1500, buildTicks: 150, prerequisite: "WEAP", faction: "GDI"),
    BuildableItem(name: "HMMV", cost: 400,  buildTicks: 60,  prerequisite: "WEAP", faction: "GDI"),
    BuildableItem(name: "BGGY", cost: 300,  buildTicks: 50,  prerequisite: "WEAP", faction: "NOD"),
    BuildableItem(name: "APC",  cost: 700,  buildTicks: 90,  prerequisite: "WEAP", faction: nil),
    BuildableItem(name: "ARTY", cost: 450,  buildTicks: 70,  prerequisite: "WEAP", faction: "NOD"),
    BuildableItem(name: "MSAM", cost: 800,  buildTicks: 100, prerequisite: "WEAP", faction: "GDI"),
    BuildableItem(name: "HARV", cost: 1400, buildTicks: 120, prerequisite: "PROC", faction: nil),
]

struct BuildableStructure {
    let name: String
    let cost: Int
    let buildTicks: Int
    let faction: String?
}

let buildableStructures: [BuildableStructure] = [
    BuildableStructure(name: "NUKE", cost: 300,  buildTicks: 60,  faction: nil),
    BuildableStructure(name: "PYLE", cost: 300,  buildTicks: 60,  faction: "GDI"),
    BuildableStructure(name: "HAND", cost: 300,  buildTicks: 60,  faction: "NOD"),
    BuildableStructure(name: "PROC", cost: 1500, buildTicks: 120, faction: nil),
    BuildableStructure(name: "WEAP", cost: 2000, buildTicks: 150, faction: nil),
    BuildableStructure(name: "GUN",  cost: 600,  buildTicks: 60,  faction: "GDI"),
    BuildableStructure(name: "GTWR", cost: 800,  buildTicks: 80,  faction: "GDI"),
    BuildableStructure(name: "OBLI", cost: 1500, buildTicks: 100, faction: "NOD"),
    BuildableStructure(name: "ATWR", cost: 1000, buildTicks: 90,  faction: nil),
    BuildableStructure(name: "SILO", cost: 150,  buildTicks: 40,  faction: nil),
    BuildableStructure(name: "HPAD", cost: 1500, buildTicks: 120, faction: nil),
    BuildableStructure(name: "HQ",   cost: 1000, buildTicks: 90,  faction: nil),
    BuildableStructure(name: "FACT", cost: 5000, buildTicks: 200, faction: nil),
]

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

    drawText(renderer, "CREDITS", centerX: sx + sidebarWidth / 2, centerY: 15, color: .amber, scale: 1)
    drawText(renderer, "$\(displayedCredits)", centerX: sx + sidebarWidth / 2, centerY: 32, color: .green, scale: 2)

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
    let buttonH: Int32 = 24
    let buttonSpacing: Int32 = 2

    if sidebarTab == 0 {
        // Unit build list
        let available = getAvailableUnits()
        for (i, item) in available.enumerated() {
            let by = listY + Int32(i) * (buttonH + buttonSpacing)
            if by + buttonH > windowHeight - 20 { break }

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

            // Label
            let textColor: Color = canAfford ? .green : .red
            drawText(renderer, item.name, centerX: sx + 30, centerY: by + buttonH / 2, color: textColor, scale: 1)
            drawText(renderer, "$\(item.cost)", centerX: sx + sidebarWidth - 40, centerY: by + buttonH / 2, color: textColor, scale: 1)

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
            if by + buttonH > windowHeight - 20 { break }

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

            // Label
            let textColor: Color = isReady ? .amber : (canAfford ? .green : .red)
            let label = isReady ? "\(item.name) READY" : item.name
            drawText(renderer, label, centerX: sx + 38, centerY: by + buttonH / 2, color: textColor, scale: 1)
            if !isReady {
                drawText(renderer, "$\(item.cost)", centerX: sx + sidebarWidth - 40, centerY: by + buttonH / 2, color: textColor, scale: 1)
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

    // Placement mode indicator
    if isPlacingStructure, let pType = placementType {
        drawText(renderer, "PLACE: \(pType)", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 40, color: .amber, scale: 1)
        drawText(renderer, "Click to place", centerX: sx + sidebarWidth / 2, centerY: windowHeight - 25, color: .green, scale: 1)
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
    let buttonH: Int32 = 24
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
        } else {
            unitBuildQueue = queue
        }
    }

    // Advance structure production
    if var queue = structureBuildQueue {
        if queue.progress < queue.totalTicks {
            queue.progress += 1
            structureBuildQueue = queue
        }
        // Don't auto-complete — wait for placement
    }
}

// MARK: - Unit Spawning

func spawnProducedUnit(_ typeName: String, world: GameWorld) {
    // Find the producing structure
    let producerType: String
    let upper = typeName.uppercased()
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
    let speed = unitSpeeds[upper] ?? (isInfantry ? 0.8 : 1.5)

    let obj = GameObject(
        id: world.allocateId(),
        typeName: typeName,
        house: world.playerHouse,
        kind: kind,
        worldX: exitX, worldY: exitY,
        facing: 128,  // Face south
        strength: 256,
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
        strength: 256,
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
