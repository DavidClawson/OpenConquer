import CSDL2
import Foundation

// MARK: - Sidebar Constants

let sidebarWidth: Int32 = 160

// MARK: - Sidebar Rendering

func renderSidebar(_ renderer: OpaquePointer?) {
    guard session.world != nil else { return }
    let sx = renderState.windowWidth - sidebarWidth

    // Background
    SDL_SetRenderDrawColor(renderer, 30, 30, 30, 255)
    var bg = SDL_Rect(x: sx, y: 0, w: sidebarWidth, h: renderState.windowHeight)
    SDL_RenderFillRect(renderer, &bg)

    // Border line
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
    SDL_RenderDrawLine(renderer, sx, 0, sx, renderState.windowHeight)

    // Credits display (ticker animation driven by GameSession.tickCreditsDisplay)
    drawText(renderer, "CREDITS", centerX: sx + sidebarWidth / 2, centerY: 10, color: .amber, scale: 1)
    drawText(renderer, "\(session.displayedCredits)", centerX: sx + sidebarWidth / 2, centerY: 24, color: .green, scale: 2)

    // Power bar
    renderPowerBar(renderer, sx: sx)

    // Tab buttons
    let tabY: Int32 = 50
    let tabW: Int32 = sidebarWidth / 2
    let tabH: Int32 = 20

    // Units tab
    let unitTabColor: (r: UInt8, g: UInt8, b: UInt8) = session.sidebarTab == 0 ? (0, 180, 0) : (60, 60, 60)
    SDL_SetRenderDrawColor(renderer, unitTabColor.r, unitTabColor.g, unitTabColor.b, 255)
    var unitTab = SDL_Rect(x: sx, y: tabY, w: tabW, h: tabH)
    SDL_RenderFillRect(renderer, &unitTab)
    drawText(renderer, "UNITS", centerX: sx + tabW / 2, centerY: tabY + tabH / 2, color: .white, scale: 1)

    // Structures tab
    let structTabColor: (r: UInt8, g: UInt8, b: UInt8) = session.sidebarTab == 1 ? (0, 180, 0) : (60, 60, 60)
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

    if session.sidebarTab == 0 {
        // Unit build list
        let available = getAvailableUnits()
        for (i, item) in available.enumerated() {
            let by = listY + Int32(i) * (buttonH + buttonSpacing)
            if by + buttonH > renderState.windowHeight - 70 { break }

            let isBuilding = session.unitBuildQueue.item?.typeName == item.name
            let canAfford = session.sidebarCredits >= item.cost

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
            let house = session.world?.playerHouse ?? .goodGuy
            let theater = session.world?.theater ?? .temperate
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
            if isBuilding, let queue = session.unitBuildQueue.item {
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
            if by + buttonH > renderState.windowHeight - 70 { break }

            let isBuilding = session.structureBuildQueue.item?.typeName == item.name
            let isReady = isBuilding && session.structureBuildQueue.isComplete
            let canAfford = session.sidebarCredits >= item.cost

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
            let house = session.world?.playerHouse ?? .goodGuy
            let theater = session.world?.theater ?? .temperate
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
            if isBuilding, let queue = session.structureBuildQueue.item, !isReady {
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
    if session.isPlacingStructure, let pType = session.placementType {
        drawText(renderer, "PLACE: \(pType)", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 85, color: .amber, scale: 1)
        drawText(renderer, "Click to place", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 75, color: .green, scale: 1)
    }

    // Super weapons display
    renderSuperWeaponButtons(renderer)

    // Repair/Sell mode indicators
    if session.isRepairMode {
        drawText(renderer, "Click building", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 30, color: .amber, scale: 1)
        drawText(renderer, "to REPAIR", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 18, color: .green, scale: 1)
    } else if session.isSellMode {
        drawText(renderer, "Click building", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 30, color: .amber, scale: 1)
        drawText(renderer, "to SELL", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 18, color: .red, scale: 1)
    } else if session.superWeaponTargeting != nil {
        drawText(renderer, "Click target", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 30, color: .amber, scale: 1)
        drawText(renderer, "for STRIKE", centerX: sx + sidebarWidth / 2, centerY: renderState.windowHeight - 18, color: .red, scale: 1)
    }
}

// MARK: - Sidebar Click Handling

func handleSidebarClick(_ x: Int32, _ y: Int32) {
    let sx = renderState.windowWidth - sidebarWidth

    // Tab selection
    let tabY: Int32 = 50
    let tabH: Int32 = 20
    if y >= tabY && y < tabY + tabH {
        if x < sx + sidebarWidth / 2 {
            session.sidebarTab = 0
        } else {
            session.sidebarTab = 1
        }
        return
    }

    // Build list clicks
    let listY = tabY + tabH + 4
    let buttonH: Int32 = 48
    let buttonSpacing: Int32 = 2

    let clickIdx = Int((y - listY) / (buttonH + buttonSpacing))
    if clickIdx < 0 { return }

    if session.sidebarTab == 0 {
        let available = getAvailableUnits()
        if clickIdx < available.count {
            let item = available[clickIdx]
            if session.unitBuildQueue.item == nil && session.sidebarCredits >= item.cost {
                session.unitBuildQueue.start(typeName: item.name, cost: item.cost, buildTime: item.buildTicks)
                session.sidebarCredits -= item.cost
                speak(.building)
            } else if session.sidebarCredits < item.cost {
                speak(.noCash)
                soundEffect(.scold)
            }
        }
    } else {
        let available = getAvailableStructures()
        if clickIdx < available.count {
            let item = available[clickIdx]

            // If structure is ready, enter placement mode
            if let queue = session.structureBuildQueue.item, queue.typeName == item.name,
               session.structureBuildQueue.isComplete {
                session.isPlacingStructure = true
                session.placementType = item.name
                return
            }

            if session.structureBuildQueue.item == nil && session.sidebarCredits >= item.cost {
                session.structureBuildQueue.start(typeName: item.name, cost: item.cost, buildTime: item.buildTicks)
                session.sidebarCredits -= item.cost
                speak(.building)
            } else if session.sidebarCredits < item.cost {
                speak(.noCash)
                soundEffect(.scold)
            }
        }
    }
}

// MARK: - Power Bar Rendering

func renderPowerBar(_ renderer: OpaquePointer?, sx: Int32) {
    guard let world = session.world else { return }
    let playerHouse = world.playerHouse
    let houseState = getHouseState(playerHouse)

    let barX = sx + 4
    let barY: Int32 = 30
    let barW: Int32 = sidebarWidth - 8
    let barH: Int32 = 10

    // Background
    SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255)
    var bgRect = SDL_Rect(x: barX, y: barY, w: barW, h: barH)
    SDL_RenderFillRect(renderer, &bgRect)

    // Power level indicator
    let maxVal = max(1, max(houseState.powerOutput, houseState.powerDrain))
    let outputFrac = min(1.0, Double(houseState.powerOutput) / Double(maxVal))
    let drainFrac = min(1.0, Double(houseState.powerDrain) / Double(maxVal))

    // Determine bar color based on power ratio (matches original C&C logic)
    // Green = surplus, Yellow = drain > output, Red = drain > 2x output
    let barColor: (r: UInt8, g: UInt8, b: UInt8)
    if houseState.powerDrain > houseState.powerOutput * 2 {
        barColor = (200, 40, 0)       // Red: critically low
    } else if houseState.powerDrain > houseState.powerOutput {
        barColor = (180, 180, 0)      // Yellow: deficit
    } else {
        barColor = (0, 180, 0)        // Green: surplus
    }

    // Power output bar (top half)
    let greenW = Int32(Double(barW) * outputFrac)
    SDL_SetRenderDrawColor(renderer, barColor.r, barColor.g, barColor.b, 255)
    var greenRect = SDL_Rect(x: barX, y: barY, w: greenW, h: barH / 2)
    SDL_RenderFillRect(renderer, &greenRect)

    // Power drain bar (bottom half)
    let drainW = Int32(Double(barW) * drainFrac)
    let drainBarColor: (r: UInt8, g: UInt8, b: UInt8) = houseState.hasPower ? (140, 140, 0) : (180, 30, 0)
    SDL_SetRenderDrawColor(renderer, drainBarColor.r, drainBarColor.g, drainBarColor.b, 255)
    var drainRect = SDL_Rect(x: barX, y: barY + barH / 2, w: drainW, h: barH / 2)
    SDL_RenderFillRect(renderer, &drainRect)

    // Border
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
    SDL_RenderDrawRect(renderer, &bgRect)

    // Numerical power values
    let powerColor: Color = houseState.isLowPower ? .red : (houseState.hasPower ? .green : .amber)
    let powerText = "\(houseState.powerOutput)/\(houseState.powerDrain)"
    drawText(renderer, powerText, centerX: sx + sidebarWidth / 2, centerY: barY + barH / 2, color: powerColor, scale: 1)

    // Low power warning label below the bar
    if houseState.isLowPower {
        drawText(renderer, "LOW POWER", centerX: sx + sidebarWidth / 2, centerY: barY + barH + 5, color: .red, scale: 1)
    }
}

// MARK: - Repair / Sell Mode

/// Handle repair/sell button clicks (below the build list)
func handleRepairSellClick(_ x: Int32, _ y: Int32) -> Bool {
    let sx = renderState.windowWidth - sidebarWidth
    let buttonY = renderState.windowHeight - 60
    let buttonW: Int32 = (sidebarWidth - 12) / 2
    let buttonH: Int32 = 20

    // Repair button
    if x >= sx + 4 && x < sx + 4 + buttonW && y >= buttonY && y < buttonY + buttonH {
        session.isRepairMode = !session.isRepairMode
        session.isSellMode = false
        return true
    }

    // Sell button
    if x >= sx + 8 + buttonW && x < sx + 8 + buttonW * 2 && y >= buttonY && y < buttonY + buttonH {
        session.isSellMode = !session.isSellMode
        session.isRepairMode = false
        return true
    }

    return false
}

/// Apply repair/sell click to a structure in the game world
func handleRepairSellGameClick(worldX: Double, worldY: Double) -> Bool {
    guard let world = session.world else { return false }

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
            if session.isRepairMode {
                // Toggle repair on this building
                if obj.isRepairing {
                    obj.isRepairing = false
                    obj.mission = .guard_
                } else if obj.strength < obj.maxStrength {
                    obj.isRepairing = true
                    obj.mission = .repair
                }
                session.isRepairMode = false
                return true
            } else if session.isSellMode {
                // Sell this building
                obj.mission = .selling
                session.isSellMode = false
                return true
            }
        }
    }
    return false
}

// MARK: - Repair/Sell Buttons Rendering

func renderRepairSellButtons(_ renderer: OpaquePointer?) {
    let sx = renderState.windowWidth - sidebarWidth
    let buttonY = renderState.windowHeight - 60
    let buttonW: Int32 = (sidebarWidth - 12) / 2
    let buttonH: Int32 = 20

    // Repair button
    let repairColor: (r: UInt8, g: UInt8, b: UInt8) = session.isRepairMode ? (0, 120, 0) : (50, 50, 50)
    SDL_SetRenderDrawColor(renderer, repairColor.r, repairColor.g, repairColor.b, 255)
    var repairRect = SDL_Rect(x: sx + 4, y: buttonY, w: buttonW, h: buttonH)
    SDL_RenderFillRect(renderer, &repairRect)
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255)
    SDL_RenderDrawRect(renderer, &repairRect)
    drawText(renderer, "REPAIR", centerX: sx + 4 + buttonW / 2, centerY: buttonY + buttonH / 2,
             color: session.isRepairMode ? .amber : .green, scale: 1)

    // Sell button
    let sellColor: (r: UInt8, g: UInt8, b: UInt8) = session.isSellMode ? (120, 0, 0) : (50, 50, 50)
    SDL_SetRenderDrawColor(renderer, sellColor.r, sellColor.g, sellColor.b, 255)
    var sellRect = SDL_Rect(x: sx + 8 + buttonW, y: buttonY, w: buttonW, h: buttonH)
    SDL_RenderFillRect(renderer, &sellRect)
    SDL_SetRenderDrawColor(renderer, 100, 100, 100, 255)
    SDL_RenderDrawRect(renderer, &sellRect)
    drawText(renderer, "SELL", centerX: sx + 8 + buttonW + buttonW / 2, centerY: buttonY + buttonH / 2,
             color: session.isSellMode ? .amber : .red, scale: 1)
}

// MARK: - Super Weapon Buttons

let superWeaponButtonY: Int32 = 42  // Below credits, above tabs

func renderSuperWeaponButtons(_ renderer: OpaquePointer?) {
    let sx = renderState.windowWidth - sidebarWidth

    // Only render if any super weapon is present
    let weapons: [(SuperWeapon, String, (r: UInt8, g: UInt8, b: UInt8))] = [
        (session.playerIonCannon, "ION", (r: 100, g: 180, b: 255)),
        (session.playerAirStrike, "AIR", (r: 200, g: 200, b: 100)),
        (session.playerNukeStrike, "NUKE", (r: 255, g: 80, b: 80)),
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
    let sx = renderState.windowWidth - sidebarWidth
    let y = superWeaponButtonY
    let bw: Int32 = (sidebarWidth - 16) / 3
    let bh: Int32 = 18

    guard screenY >= y && screenY <= y + bh else { return false }
    guard screenX >= sx + 4 else { return false }

    let relX = screenX - (sx + 4)
    let index = Int(relX / (bw + 2))

    let weapons: [(SuperWeapon, SpecialWeaponType)] = [
        (session.playerIonCannon, .ionCannon),
        (session.playerAirStrike, .airStrike),
        (session.playerNukeStrike, .nuclearStrike),
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
    guard let type = session.superWeaponTargeting else { return false }
    deploySuperWeapon(type, worldX: worldX, worldY: worldY)
    return true
}

// MARK: - Placement Preview Rendering

func renderPlacementPreview(_ renderer: OpaquePointer?, mouseScreenX: Int32, mouseScreenY: Int32) {
    guard let pType = session.placementType else { return }
    let worldPos = gameScreenToWorld(mouseScreenX, mouseScreenY)
    let cellX = Int(worldPos.worldX) / 24
    let cellY = Int(worldPos.worldY) / 24
    let size = buildingSize(pType)
    let camX = Int(renderState.gameCameraX)
    let camY = Int(renderState.gameCameraY)

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
