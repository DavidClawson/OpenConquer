import CSDL2
import Foundation

// MARK: - Sidebar Constants

let sidebarWidth: Int32 = 160
let unitInfoPanelHeight: Int32 = 110

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
            if by + buttonH > renderState.windowHeight - unitInfoPanelHeight - 70 { break }

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
            drawText(renderer, item.displayName.uppercased(), centerX: sx + iconSize + 20, centerY: by + buttonH / 2 - 6, color: textColor, scale: 1)
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
            if by + buttonH > renderState.windowHeight - unitInfoPanelHeight - 70 { break }

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
            let label = isReady ? "\(item.displayName.uppercased()) READY" : item.displayName.uppercased()
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

    // Unit info panel
    renderUnitInfoPanel(renderer)

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
                audioManager.speak(.building)
            } else if session.sidebarCredits < item.cost {
                audioManager.speak(.noCash)
                audioManager.play(.scold)
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
                audioManager.speak(.building)
            } else if session.sidebarCredits < item.cost {
                audioManager.speak(.noCash)
                audioManager.play(.scold)
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

        if isWorldPosOnBuilding(worldX: worldX, worldY: worldY, building: obj) {
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

// MARK: - Unit Info Panel

/// Look up the full display name for any object type (unit, infantry, structure, aircraft).
private func objectFullName(_ typeName: String) -> String {
    let upper = typeName.uppercased()
    if let ut = UnitType.from(iniName: upper), let data = unitTypeDataTable[ut] {
        return data.fullName
    }
    if let it = InfantryType.from(iniName: upper), let data = infantryTypeDataTable[it] {
        return data.fullName
    }
    if let st = StructType.from(iniName: upper), let data = buildingTypeDataTable[st] {
        return data.fullName
    }
    if let at = AircraftType.from(iniName: upper), let data = aircraftTypeDataTable[at] {
        return data.fullName
    }
    return typeName
}

/// Human-readable name for a weapon type.
private func weaponDisplayName(_ weapon: WeaponType) -> String {
    switch weapon {
    case .rifle:        return "SNIPER"
    case .chainGun:     return "CHAIN GUN"
    case .pistol:       return "PISTOL"
    case .m16:          return "M16"
    case .dragon:       return "ROCKET"
    case .flamethrower: return "FLAME"
    case .flameTongue:  return "FLAME"
    case .chemspray:    return "CHEM"
    case .grenade:      return "GRENADE"
    case .w75mm:        return "75MM"
    case .w105mm:       return "105MM"
    case .w120mm:       return "120MM"
    case .turretGun:    return "TURRET"
    case .mammothTusk:  return "TUSK"
    case .mlrs:         return "MLRS"
    case .w155mm:       return "155MM"
    case .m60mg:        return "M60"
    case .tomahawk:     return "TOMAHAWK"
    case .towTwo:       return "TOW"
    case .napalm:       return "NAPALM"
    case .obeliskLaser: return "LASER"
    case .nike:         return "SAM"
    case .honestJohn:   return "HONEST JOHN"
    case .steg:         return "HEADBUTT"
    case .trex:         return "BITE"
    }
}

/// Human-readable name for a speed type.
private func speedDisplayName(_ speed: SpeedType) -> String {
    switch speed {
    case .foot:      return "FOOT"
    case .track:     return "TRACKED"
    case .harvester: return "TRACKED"
    case .wheel:     return "WHEELED"
    case .winged:    return "AIRCRAFT"
    case .hover:     return "HOVER"
    case .float_:    return "NAVAL"
    }
}

/// Human-readable house name.
private func houseDisplayName(_ house: House) -> String {
    switch house {
    case .goodGuy: return "GDI"
    case .badGuy:  return "NOD"
    case .neutral: return "NEUTRAL"
    case .special: return "SPECIAL"
    default:       return house.rawValue.uppercased()
    }
}

/// Veterancy rank label from kill count.
private func veterancyLabel(_ obj: GameObject) -> String? {
    if obj.veteranLevel >= 2 { return "ELITE" }
    if obj.veteranLevel >= 1 { return "VETERAN" }
    return nil
}

/// Draw a health bar at the given position. Returns the Y below the bar.
@discardableResult
private func drawHealthBar(_ renderer: OpaquePointer?, x: Int32, y: Int32, w: Int32, fraction: Double) -> Int32 {
    let barH: Int32 = 6

    // Background
    SDL_SetRenderDrawColor(renderer, 20, 20, 20, 255)
    var bgRect = SDL_Rect(x: x, y: y, w: w, h: barH)
    SDL_RenderFillRect(renderer, &bgRect)

    // Fill color based on health percentage
    let fillW = max(0, Int32(Double(w) * min(1.0, max(0.0, fraction))))
    let color: (r: UInt8, g: UInt8, b: UInt8)
    if fraction > 0.5 {
        color = (0, 180, 0)        // Green: healthy
    } else if fraction > 0.25 {
        color = (180, 180, 0)      // Yellow: damaged
    } else {
        color = (200, 40, 0)       // Red: critical
    }
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, 255)
    var fillRect = SDL_Rect(x: x, y: y, w: fillW, h: barH)
    SDL_RenderFillRect(renderer, &fillRect)

    // Border
    SDL_SetRenderDrawColor(renderer, 80, 80, 80, 255)
    SDL_RenderDrawRect(renderer, &bgRect)

    return y + barH + 2
}

/// Find the game object under the current mouse position (for hover info).
private func findHoveredObject() -> GameObject? {
    guard let world = session.world else { return nil }
    let worldPos = gameScreenToWorld(input.mouseX, input.mouseY)

    // Check if mouse is over the sidebar area — if so, no hover
    let sx = renderState.windowWidth - sidebarWidth
    if input.mouseX >= sx { return nil }

    // Check structures first (larger hit areas)
    for obj in world.objects {
        if obj.strength <= 0 { continue }
        if obj.isInLimbo { continue }
        if obj.kind == .structure {
            if isWorldPosOnBuilding(worldX: worldPos.worldX, worldY: worldPos.worldY, building: obj) {
                return obj
            }
        }
    }

    // Check mobile units and infantry (within ~12px radius)
    var closest: GameObject? = nil
    var closestDist = Double.greatestFiniteMagnitude
    for obj in world.objects {
        if obj.strength <= 0 { continue }
        if obj.isInLimbo { continue }
        if obj.kind == .structure { continue }
        let dx = worldPos.worldX - obj.worldX
        let dy = worldPos.worldY - obj.worldY
        let dist = dx * dx + dy * dy
        if dist < 16.0 * 16.0 && dist < closestDist {
            closest = obj
            closestDist = dist
        }
    }
    return closest
}

/// Render the unit info panel in the lower portion of the sidebar.
func renderUnitInfoPanel(_ renderer: OpaquePointer?) {
    guard let world = session.world else { return }
    let sx = renderState.windowWidth - sidebarWidth
    let panelX = sx + 4
    let panelW = sidebarWidth - 8
    let panelY = renderState.windowHeight - unitInfoPanelHeight - 62
    let panelH = unitInfoPanelHeight

    let selected = world.selectedObjects()

    // Determine what to show
    if selected.count == 1 {
        // Single unit selected — detailed info
        renderSingleUnitInfo(renderer, obj: selected[0], x: panelX, y: panelY, w: panelW, h: panelH)
    } else if selected.count > 1 {
        // Multi-select summary
        renderMultiSelectInfo(renderer, units: selected, x: panelX, y: panelY, w: panelW, h: panelH)
    } else {
        // Nothing selected — check hover
        if let hovered = findHoveredObject() {
            renderHoverInfo(renderer, obj: hovered, x: panelX, y: panelY, w: panelW, h: panelH)
        }
        // If nothing hovered either, show nothing (empty panel area)
    }
}

/// Render detailed info for a single selected unit.
private func renderSingleUnitInfo(_ renderer: OpaquePointer?, obj: GameObject, x: Int32, y: Int32, w: Int32, h: Int32) {
    // Panel background
    SDL_SetRenderDrawColor(renderer, 25, 25, 25, 255)
    var panelRect = SDL_Rect(x: x, y: y, w: w, h: h)
    SDL_RenderFillRect(renderer, &panelRect)
    SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255)
    SDL_RenderDrawRect(renderer, &panelRect)

    let cx = x + w / 2
    var cy = y + 6

    // Unit name
    let fullName = objectFullName(obj.typeName)
    drawText(renderer, fullName.uppercased(), centerX: cx, centerY: cy, color: .green, scale: 1)
    cy += 10

    // Health bar with numeric HP
    let hpText = "\(obj.strength)/\(obj.maxStrength)"
    drawHealthBar(renderer, x: x + 4, y: cy, w: w - 8, fraction: obj.healthFraction)
    cy += 9
    drawText(renderer, hpText, centerX: cx, centerY: cy, color: .gray, scale: 1)
    cy += 11

    // Weapon info
    if let weapon = obj.primaryWeapon {
        let wName = weaponDisplayName(weapon)
        if let wData = weaponTypeData[weapon] {
            let rangeText = "\(wData.rangeInCells)R"
            drawText(renderer, "\(wName) \(rangeText)", centerX: cx, centerY: cy, color: .amber, scale: 1)
        } else {
            drawText(renderer, wName, centerX: cx, centerY: cy, color: .amber, scale: 1)
        }
    } else {
        drawText(renderer, "UNARMED", centerX: cx, centerY: cy, color: .gray, scale: 1)
    }
    cy += 11

    // Speed type (for mobile units) or Power info (for buildings)
    if obj.kind == .structure {
        if obj.powerOutput > 0 || obj.powerDrain > 0 {
            let pwrColor: Color = obj.powerOutput > 0 ? .green : .amber
            let pwrText = obj.powerOutput > 0 ? "PWR: +\(obj.powerOutput)" : "DRAIN: \(obj.powerDrain)"
            drawText(renderer, pwrText, centerX: cx, centerY: cy, color: pwrColor, scale: 1)
            cy += 11
        }
    } else {
        let speedLabel = speedDisplayName(obj.speedType)
        drawText(renderer, speedLabel, centerX: cx, centerY: cy, color: .gray, scale: 1)
        cy += 11
    }

    // Veterancy rank (if any kills)
    if let rank = veterancyLabel(obj) {
        let rankColor: Color = obj.veteranLevel >= 2 ? .amber : .green
        drawText(renderer, "\(rank) (\(obj.killCount) KILLS)", centerX: cx, centerY: cy, color: rankColor, scale: 1)
        cy += 11
    }

    // Harvester load info
    if obj.tiberiumLoad > 0 {
        drawText(renderer, "LOAD: \(obj.tiberiumLoad)", centerX: cx, centerY: cy, color: .green, scale: 1)
        cy += 11
    }

    // Mission indicator
    drawText(renderer, obj.mission.rawValue.uppercased(), centerX: cx, centerY: min(cy, y + h - 6), color: .gray, scale: 1)
}

/// Render summary info for multiple selected units.
private func renderMultiSelectInfo(_ renderer: OpaquePointer?, units: [GameObject], x: Int32, y: Int32, w: Int32, h: Int32) {
    // Panel background
    SDL_SetRenderDrawColor(renderer, 25, 25, 25, 255)
    var panelRect = SDL_Rect(x: x, y: y, w: w, h: h)
    SDL_RenderFillRect(renderer, &panelRect)
    SDL_SetRenderDrawColor(renderer, 60, 60, 60, 255)
    SDL_RenderDrawRect(renderer, &panelRect)

    let cx = x + w / 2
    var cy = y + 6

    // Header
    drawText(renderer, "\(units.count) SELECTED", centerX: cx, centerY: cy, color: .green, scale: 1)
    cy += 12

    // Combined health
    let totalHP = units.reduce(0) { $0 + $1.strength }
    let totalMaxHP = units.reduce(0) { $0 + $1.maxStrength }
    let combinedFraction = totalMaxHP > 0 ? Double(totalHP) / Double(totalMaxHP) : 0.0
    drawHealthBar(renderer, x: x + 4, y: cy, w: w - 8, fraction: combinedFraction)
    cy += 9
    let pct = Int(combinedFraction * 100)
    drawText(renderer, "\(pct)% HEALTH", centerX: cx, centerY: cy, color: .gray, scale: 1)
    cy += 13

    // Count by type (show up to 5 types)
    var typeCounts: [(name: String, count: Int)] = []
    var countMap: [String: Int] = [:]
    for unit in units {
        countMap[unit.typeName, default: 0] += 1
    }
    for (typeName, count) in countMap.sorted(by: { $0.value > $1.value }) {
        typeCounts.append((name: typeName, count: count))
    }

    let maxTypes = min(typeCounts.count, 5)
    for i in 0..<maxTypes {
        let entry = typeCounts[i]
        if cy + 10 > y + h - 2 { break }
        let displayName = objectFullName(entry.name)
        let line = "\(entry.count)X \(displayName.uppercased())"
        // Truncate long names to fit sidebar
        let truncated = line.count > 22 ? String(line.prefix(22)) : line
        drawText(renderer, truncated, centerX: cx, centerY: cy, color: .amber, scale: 1)
        cy += 10
    }
    if typeCounts.count > maxTypes {
        drawText(renderer, "...", centerX: cx, centerY: min(cy, y + h - 6), color: .gray, scale: 1)
    }
}

/// Render brief hover info for an unselected unit under the cursor.
private func renderHoverInfo(_ renderer: OpaquePointer?, obj: GameObject, x: Int32, y: Int32, w: Int32, h: Int32) {
    // Panel background (slightly transparent feel via darker shade)
    SDL_SetRenderDrawColor(renderer, 22, 22, 28, 255)
    var panelRect = SDL_Rect(x: x, y: y, w: w, h: h)
    SDL_RenderFillRect(renderer, &panelRect)
    SDL_SetRenderDrawColor(renderer, 50, 50, 60, 255)
    SDL_RenderDrawRect(renderer, &panelRect)

    let cx = x + w / 2
    var cy = y + 6

    // Unit name
    let fullName = objectFullName(obj.typeName)
    drawText(renderer, fullName.uppercased(), centerX: cx, centerY: cy, color: .cyan, scale: 1)
    cy += 12

    // Owner
    let ownerName = houseDisplayName(obj.house)
    let ownerColor: Color = obj.house == (session.world?.playerHouse ?? .goodGuy) ? .green : .red
    drawText(renderer, ownerName, centerX: cx, centerY: cy, color: ownerColor, scale: 1)
    cy += 12

    // Brief health indicator
    let healthPct = Int(obj.healthFraction * 100)
    let healthLabel: String
    let healthColor: Color
    if obj.healthFraction > 0.75 {
        healthLabel = "HEALTHY"
        healthColor = .green
    } else if obj.healthFraction > 0.5 {
        healthLabel = "DAMAGED"
        healthColor = .amber
    } else if obj.healthFraction > 0.25 {
        healthLabel = "HEAVILY DAMAGED"
        healthColor = .red
    } else {
        healthLabel = "CRITICAL"
        healthColor = .red
    }
    drawText(renderer, "\(healthLabel) \(healthPct)%", centerX: cx, centerY: cy, color: healthColor, scale: 1)
    cy += 9
    drawHealthBar(renderer, x: x + 4, y: cy, w: w - 8, fraction: obj.healthFraction)
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
