import CSDL2
import Foundation

// MARK: - Game Cursor Rendering

/// Cursor type with VC-authentic frame mapping from mouse.cpp MouseControl[]
struct CursorDef {
    let startFrame: Int
    let frameCount: Int
    let hotX: Int32
    let hotY: Int32
}

let cursorNormal    = CursorDef(startFrame: 0,   frameCount: 1,  hotX: 0,  hotY: 0)
let cursorCanMove   = CursorDef(startFrame: 10,  frameCount: 1,  hotX: 15, hotY: 12)
let cursorNoMove    = CursorDef(startFrame: 11,  frameCount: 1,  hotX: 15, hotY: 12)
let cursorCanSelect = CursorDef(startFrame: 12,  frameCount: 6,  hotX: 15, hotY: 12)
let cursorCanAttack = CursorDef(startFrame: 18,  frameCount: 8,  hotX: 15, hotY: 12)
let cursorDeploy    = CursorDef(startFrame: 53,  frameCount: 9,  hotX: 15, hotY: 12)
let cursorAttackMove = CursorDef(startFrame: 60,  frameCount: 1,  hotX: 15, hotY: 12)
let cursorEnter     = CursorDef(startFrame: 119, frameCount: 3,  hotX: 15, hotY: 12)
let cursorAreaGuard = CursorDef(startFrame: 153, frameCount: 1,  hotX: 15, hotY: 12)
let cursorRepair    = CursorDef(startFrame: 200, frameCount: 12, hotX: 15, hotY: 12)
let cursorSell      = CursorDef(startFrame: 210, frameCount: 1,  hotX: 15, hotY: 12)
let cursorNuke      = CursorDef(startFrame: 220, frameCount: 1,  hotX: 15, hotY: 12)

func renderGameCursor(_ renderer: OpaquePointer?, world: GameWorld) {
    // Hide system cursor when playing
    if !renderState.systemCursorHidden {
        SDL_ShowCursor(SDL_DISABLE)
        renderState.systemCursorHidden = true
    }

    // Animate cursor (cycle every ~66ms = 15 FPS like the game tick rate)
    let now = SDL_GetTicks()
    if now - renderState.cursorAnimTimer > 66 {
        renderState.cursorAnimTimer = now
        renderState.cursorAnimFrame += 1
    }

    // Determine cursor type based on what's under the mouse
    var cursor = cursorNormal

    // Super weapon targeting mode overrides cursor
    if session.superWeaponTargeting != nil {
        cursor = cursorNuke
    }

    // Attack-move mode overrides cursor
    if session.isAttackMoveMode {
        cursor = cursorAttackMove
    }

    // Sell mode cursor — overrides normal cursor when hovering over own buildings
    if session.isSellMode && input.mouseX < renderState.windowWidth - sidebarWidth {
        cursor = cursorSell
    }

    // Only apply game cursor logic when mouse is in the game viewport
    if !session.isAttackMoveMode && !session.isSellMode && input.mouseX < renderState.windowWidth - sidebarWidth {
        let worldPos = gameScreenToWorld(input.mouseX, input.mouseY)
        let selected = world.selectedObjects()

        // Check if hovering over a damaged friendly building in repair mode → repair wrench cursor
        var hoveringDamagedBuilding = false
        if session.isRepairMode {
            for obj in world.objects {
                if obj.kind != .structure { continue }
                if obj.house != world.playerHouse { continue }
                if obj.strength <= 0 { continue }
                if obj.strength >= obj.maxStrength { continue }
                if isWorldPosOnBuilding(worldX: worldPos.worldX, worldY: worldPos.worldY, building: obj) {
                    cursor = cursorRepair
                    hoveringDamagedBuilding = true
                    break
                }
            }
        }

        if !hoveringDamagedBuilding && !selected.isEmpty {
            // Check if hovering over a selected MCV -> deploy cursor
            var isHoveringMCV = false
            let hitRadius = 14.0 / renderState.gameZoomLevel
            for obj in selected {
                if obj.typeName.uppercased() == "MCV" && obj.house == world.playerHouse && obj.mission != .unload {
                    let dx = obj.worldX - worldPos.worldX
                    let dy = obj.worldY - worldPos.worldY
                    if sqrt(dx * dx + dy * dy) < hitRadius {
                        isHoveringMCV = true
                        break
                    }
                }
            }

            if isHoveringMCV {
                cursor = cursorDeploy
            } else if let _ = findEnemyAtWorldPos(worldX: worldPos.worldX, worldY: worldPos.worldY) {
                // Check for enemy under cursor -> attack cursor
                cursor = cursorCanAttack
            } else {
                // Check if terrain is passable for any selected unit
                let hoverCellX = Int(worldPos.worldX) / 24
                let hoverCellY = Int(worldPos.worldY) / 24
                var anyCanMove = false
                for obj in selected {
                    if obj.kind == .structure { continue }
                    let passMap = passabilityMap(for: obj.cachedSpeedType)
                    if hoverCellX >= 0 && hoverCellX < 64 && hoverCellY >= 0 && hoverCellY < 64 &&
                       passMap[hoverCellY * 64 + hoverCellX] {
                        anyCanMove = true
                        break
                    }
                }
                cursor = anyCanMove ? cursorCanMove : cursorNoMove
            }
        } else if !hoveringDamagedBuilding {
            // Check for own selectable unit under cursor
            let hitRadius = 14.0 / renderState.gameZoomLevel
            var foundOwn = false
            for obj in world.objects {
                if obj.kind == .structure { continue }
                if obj.house != world.playerHouse { continue }
                if obj.strength <= 0 { continue }
                let dx = obj.worldX - worldPos.worldX
                let dy = obj.worldY - worldPos.worldY
                if sqrt(dx * dx + dy * dy) < hitRadius {
                    foundOwn = true
                    break
                }
            }
            if foundOwn {
                cursor = cursorCanSelect
            }
        }
    }

    // Render procedural cursor
    drawProceduralCursor(renderer, cursor: cursor)
}

// MARK: - Procedural Cursor Drawing

func drawProceduralCursor(_ renderer: OpaquePointer?, cursor: CursorDef) {
    let mx = input.mouseX
    let my = input.mouseY

    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    if cursor.startFrame == cursorCanAttack.startFrame {
        drawCursorAttack(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorCanMove.startFrame {
        drawCursorMove(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorNoMove.startFrame {
        drawCursorNoMove(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorDeploy.startFrame {
        drawCursorDeploy(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorAttackMove.startFrame {
        drawCursorAttackMove(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorCanSelect.startFrame {
        drawCursorSelect(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorRepair.startFrame {
        drawCursorRepair(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorSell.startFrame {
        drawCursorSell(renderer, mx: mx, my: my)
    } else if cursor.startFrame == cursorNuke.startFrame {
        drawCursorSuperWeapon(renderer, mx: mx, my: my)
    } else {
        drawCursorNormal(renderer, mx: mx, my: my)
    }
}

// MARK: - Individual Cursor Shapes

private func drawCursorAttack(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let sz: Int32 = 10
    SDL_SetRenderDrawColor(renderer, 255, 40, 40, 255)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - 3, my)
    SDL_RenderDrawLine(renderer, mx + 3, my, mx + sz, my)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx, my - 3)
    SDL_RenderDrawLine(renderer, mx, my + 3, mx, my + sz)
    var dot = SDL_Rect(x: mx - 1, y: my - 1, w: 3, h: 3)
    SDL_RenderFillRect(renderer, &dot)
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
    SDL_RenderDrawLine(renderer, mx - sz - 1, my - 1, mx - 3, my - 1)
    SDL_RenderDrawLine(renderer, mx - sz - 1, my + 1, mx - 3, my + 1)
    SDL_RenderDrawLine(renderer, mx + 3, my - 1, mx + sz + 1, my - 1)
    SDL_RenderDrawLine(renderer, mx + 3, my + 1, mx + sz + 1, my + 1)
    SDL_RenderDrawLine(renderer, mx - 1, my - sz - 1, mx - 1, my - 3)
    SDL_RenderDrawLine(renderer, mx + 1, my - sz - 1, mx + 1, my - 3)
    SDL_RenderDrawLine(renderer, mx - 1, my + 3, mx - 1, my + sz + 1)
    SDL_RenderDrawLine(renderer, mx + 1, my + 3, mx + 1, my + sz + 1)
}

private func drawCursorMove(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let sz: Int32 = 8
    SDL_SetRenderDrawColor(renderer, 0, 220, 0, 255)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx - 3, my - sz + 4)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx + 3, my - sz + 4)
    SDL_RenderDrawLine(renderer, mx, my + sz, mx - 3, my + sz - 4)
    SDL_RenderDrawLine(renderer, mx, my + sz, mx + 3, my + sz - 4)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - sz + 4, my - 3)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - sz + 4, my + 3)
    SDL_RenderDrawLine(renderer, mx + sz, my, mx + sz - 4, my - 3)
    SDL_RenderDrawLine(renderer, mx + sz, my, mx + sz - 4, my + 3)
    var dot = SDL_Rect(x: mx - 1, y: my - 1, w: 3, h: 3)
    SDL_RenderFillRect(renderer, &dot)
}

private func drawCursorNoMove(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let sz: Int32 = 8
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200)
    SDL_RenderDrawLine(renderer, mx - sz - 1, my - sz, mx + sz, my + sz + 1)
    SDL_RenderDrawLine(renderer, mx + sz, my - sz, mx - sz - 1, my + sz + 1)
    SDL_SetRenderDrawColor(renderer, 255, 50, 50, 255)
    SDL_RenderDrawLine(renderer, mx - sz, my - sz, mx + sz, my + sz)
    SDL_RenderDrawLine(renderer, mx + sz, my - sz, mx - sz, my + sz)
    SDL_RenderDrawLine(renderer, mx - sz + 1, my - sz, mx + sz + 1, my + sz)
    SDL_RenderDrawLine(renderer, mx + sz - 1, my - sz, mx - sz - 1, my + sz)
}

private func drawCursorDeploy(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let phase = Double(renderState.cursorAnimFrame % 20) / 20.0
    let expand = Int32(phase * 8.0)
    let alpha = UInt8(255 - Int(phase * 180))
    let baseSz: Int32 = 4
    let sz = baseSz + expand

    SDL_SetRenderDrawColor(renderer, 0, 220, 0, alpha)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx - 4, my - sz + 5)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx + 4, my - sz + 5)
    SDL_RenderDrawLine(renderer, mx - 1, my - sz, mx - 5, my - sz + 5)
    SDL_RenderDrawLine(renderer, mx + 1, my - sz, mx + 5, my - sz + 5)
    SDL_RenderDrawLine(renderer, mx, my + sz, mx - 4, my + sz - 5)
    SDL_RenderDrawLine(renderer, mx, my + sz, mx + 4, my + sz - 5)
    SDL_RenderDrawLine(renderer, mx - 1, my + sz, mx - 5, my + sz - 5)
    SDL_RenderDrawLine(renderer, mx + 1, my + sz, mx + 5, my + sz - 5)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - sz + 5, my - 4)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - sz + 5, my + 4)
    SDL_RenderDrawLine(renderer, mx - sz, my - 1, mx - sz + 5, my - 5)
    SDL_RenderDrawLine(renderer, mx - sz, my + 1, mx - sz + 5, my + 5)
    SDL_RenderDrawLine(renderer, mx + sz, my, mx + sz - 5, my - 4)
    SDL_RenderDrawLine(renderer, mx + sz, my, mx + sz - 5, my + 4)
    SDL_RenderDrawLine(renderer, mx + sz, my - 1, mx + sz - 5, my - 5)
    SDL_RenderDrawLine(renderer, mx + sz, my + 1, mx + sz - 5, my + 5)

    let phase2 = Double((renderState.cursorAnimFrame + 10) % 20) / 20.0
    let expand2 = Int32(phase2 * 8.0)
    let alpha2 = UInt8(255 - Int(phase2 * 180))
    let sz2 = baseSz + expand2
    SDL_SetRenderDrawColor(renderer, 0, 220, 0, alpha2)
    SDL_RenderDrawLine(renderer, mx, my - sz2, mx - 4, my - sz2 + 5)
    SDL_RenderDrawLine(renderer, mx, my - sz2, mx + 4, my - sz2 + 5)
    SDL_RenderDrawLine(renderer, mx, my + sz2, mx - 4, my + sz2 - 5)
    SDL_RenderDrawLine(renderer, mx, my + sz2, mx + 4, my + sz2 - 5)
    SDL_RenderDrawLine(renderer, mx - sz2, my, mx - sz2 + 5, my - 4)
    SDL_RenderDrawLine(renderer, mx - sz2, my, mx - sz2 + 5, my + 4)
    SDL_RenderDrawLine(renderer, mx + sz2, my, mx + sz2 - 5, my - 4)
    SDL_RenderDrawLine(renderer, mx + sz2, my, mx + sz2 - 5, my + 4)
}

private func drawCursorAttackMove(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let sz: Int32 = 10
    SDL_SetRenderDrawColor(renderer, 255, 180, 0, 255)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - 3, my)
    SDL_RenderDrawLine(renderer, mx + 3, my, mx + sz, my)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx, my - 3)
    SDL_RenderDrawLine(renderer, mx, my + 3, mx, my + sz)
    var dot = SDL_Rect(x: mx - 1, y: my - 1, w: 3, h: 3)
    SDL_RenderFillRect(renderer, &dot)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx - 2, my - sz + 3)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx + 2, my - sz + 3)
    SDL_RenderDrawLine(renderer, mx, my + sz, mx - 2, my + sz - 3)
    SDL_RenderDrawLine(renderer, mx, my + sz, mx + 2, my + sz - 3)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - sz + 3, my - 2)
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - sz + 3, my + 2)
    SDL_RenderDrawLine(renderer, mx + sz, my, mx + sz - 3, my - 2)
    SDL_RenderDrawLine(renderer, mx + sz, my, mx + sz - 3, my + 2)
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
    SDL_RenderDrawLine(renderer, mx - sz - 1, my - 1, mx - 3, my - 1)
    SDL_RenderDrawLine(renderer, mx + 3, my + 1, mx + sz + 1, my + 1)
    SDL_RenderDrawLine(renderer, mx - 1, my - sz - 1, mx - 1, my - 3)
    SDL_RenderDrawLine(renderer, mx + 1, my + 3, mx + 1, my + sz + 1)
}

private func drawCursorSelect(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let pulse = abs(sin(Double(renderState.cursorAnimFrame) * 0.3))
    let alpha = UInt8(160 + Int(pulse * 95))
    let sz: Int32 = 9
    let corner: Int32 = 4
    SDL_SetRenderDrawColor(renderer, 0, 230, 0, alpha)
    SDL_RenderDrawLine(renderer, mx - sz, my - sz, mx - sz + corner, my - sz)
    SDL_RenderDrawLine(renderer, mx - sz, my - sz, mx - sz, my - sz + corner)
    SDL_RenderDrawLine(renderer, mx + sz, my - sz, mx + sz - corner, my - sz)
    SDL_RenderDrawLine(renderer, mx + sz, my - sz, mx + sz, my - sz + corner)
    SDL_RenderDrawLine(renderer, mx - sz, my + sz, mx - sz + corner, my + sz)
    SDL_RenderDrawLine(renderer, mx - sz, my + sz, mx - sz, my + sz - corner)
    SDL_RenderDrawLine(renderer, mx + sz, my + sz, mx + sz - corner, my + sz)
    SDL_RenderDrawLine(renderer, mx + sz, my + sz, mx + sz, my + sz - corner)
}

private func drawCursorRepair(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let angle = Double(renderState.cursorAnimFrame % 60) / 60.0 * 2.0 * Double.pi
    let cosA = cos(angle)
    let sinA = sin(angle)

    let handleLen: Double = 10.0
    let hx1 = Int32(Double(mx) + cosA * 2.0)
    let hy1 = Int32(Double(my) + sinA * 2.0)
    let hx2 = Int32(Double(mx) + cosA * handleLen)
    let hy2 = Int32(Double(my) + sinA * handleLen)

    let headLen: Double = 5.0
    let perpX = -sinA
    let perpY = cosA
    let whx1 = Int32(Double(mx) + cosA * handleLen + perpX * headLen)
    let why1 = Int32(Double(my) + sinA * handleLen + perpY * headLen)
    let whx2 = Int32(Double(mx) + cosA * handleLen - perpX * headLen)
    let why2 = Int32(Double(my) + sinA * handleLen - perpY * headLen)

    let jawLen: Double = 3.0
    let jx1 = Int32(Double(mx) - cosA * 1.0 + perpX * jawLen)
    let jy1 = Int32(Double(my) - sinA * 1.0 + perpY * jawLen)
    let jx2 = Int32(Double(mx) - cosA * 1.0 - perpX * jawLen)
    let jy2 = Int32(Double(my) - sinA * 1.0 - perpY * jawLen)

    // Shadow
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
    SDL_RenderDrawLine(renderer, hx1 + 1, hy1 + 1, hx2 + 1, hy2 + 1)
    SDL_RenderDrawLine(renderer, whx1 + 1, why1 + 1, whx2 + 1, why2 + 1)
    SDL_RenderDrawLine(renderer, jx1 + 1, jy1 + 1, jx2 + 1, jy2 + 1)

    // Wrench in golden/amber
    SDL_SetRenderDrawColor(renderer, 255, 200, 0, 255)
    SDL_RenderDrawLine(renderer, hx1, hy1, hx2, hy2)
    SDL_RenderDrawLine(renderer, hx1 + Int32(perpX), hy1 + Int32(perpY), hx2 + Int32(perpX), hy2 + Int32(perpY))
    SDL_RenderDrawLine(renderer, hx1 - Int32(perpX), hy1 - Int32(perpY), hx2 - Int32(perpX), hy2 - Int32(perpY))
    SDL_RenderDrawLine(renderer, whx1, why1, whx2, why2)
    SDL_RenderDrawLine(renderer, whx1 + Int32(cosA), why1 + Int32(sinA), whx2 + Int32(cosA), why2 + Int32(sinA))
    SDL_RenderDrawLine(renderer, jx1, jy1, jx2, jy2)

    var dot = SDL_Rect(x: mx - 1, y: my - 1, w: 3, h: 3)
    SDL_SetRenderDrawColor(renderer, 255, 220, 0, 255)
    SDL_RenderFillRect(renderer, &dot)
}

private func drawCursorSell(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    let sz: Int32 = 8
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180)
    SDL_RenderDrawLine(renderer, mx + 1, my - sz + 1, mx + 1, my + sz + 1)
    SDL_SetRenderDrawColor(renderer, 255, 200, 0, 255)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx, my + sz)
    SDL_RenderDrawLine(renderer, mx - 4, my - sz + 2, mx + 4, my - sz + 2)
    SDL_RenderDrawLine(renderer, mx - 4, my - sz + 2, mx - 4, my - 1)
    SDL_RenderDrawLine(renderer, mx - 3, my, mx + 3, my)
    SDL_RenderDrawLine(renderer, mx + 4, my + 1, mx + 4, my + sz - 2)
    SDL_RenderDrawLine(renderer, mx - 4, my + sz - 2, mx + 4, my + sz - 2)
}

private func drawCursorNormal(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 220)
    SDL_RenderDrawLine(renderer, mx + 1, my + 1, mx + 1, my + 17)
    SDL_RenderDrawLine(renderer, mx + 1, my + 17, mx + 5, my + 13)
    SDL_RenderDrawLine(renderer, mx + 5, my + 13, mx + 8, my + 19)
    SDL_RenderDrawLine(renderer, mx + 10, my + 18, mx + 7, my + 12)
    SDL_RenderDrawLine(renderer, mx + 7, my + 12, mx + 12, my + 12)
    SDL_RenderDrawLine(renderer, mx + 12, my + 12, mx + 1, my + 1)

    SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255)
    SDL_RenderDrawLine(renderer, mx, my, mx, my + 16)
    SDL_RenderDrawLine(renderer, mx, my + 16, mx + 4, my + 12)
    SDL_RenderDrawLine(renderer, mx + 4, my + 12, mx + 7, my + 18)
    SDL_RenderDrawLine(renderer, mx + 9, my + 17, mx + 6, my + 11)
    SDL_RenderDrawLine(renderer, mx + 6, my + 11, mx + 11, my + 11)
    SDL_RenderDrawLine(renderer, mx + 11, my + 11, mx, my)
    for fy in Int32(0)..<Int32(16) {
        let maxFillX = min(fy * 11 / 16, Int32(10))
        if maxFillX > 0 {
            SDL_RenderDrawLine(renderer, mx + 1, my + fy + 1, mx + maxFillX, my + fy + 1)
        }
    }
}

private func drawCursorSuperWeapon(_ renderer: OpaquePointer?, mx: Int32, my: Int32) {
    // Large animated crosshair for super weapon targeting
    let phase = Double(renderState.cursorAnimFrame % 30) / 30.0
    let pulse = Int32(sin(phase * 2.0 * Double.pi) * 3.0)
    let sz: Int32 = 14 + pulse

    // Determine color based on weapon type
    let r: UInt8, g: UInt8, b: UInt8
    switch session.superWeaponTargeting {
    case .ionCannon:
        r = 100; g = 180; b = 255  // Blue
    case .nuclearStrike:
        r = 255; g = 60; b = 60    // Red
    case .airStrike:
        r = 255; g = 220; b = 60   // Yellow
    default:
        r = 255; g = 255; b = 255
    }

    // Outer circle-like crosshair
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 200)
    SDL_RenderDrawLine(renderer, mx - sz - 1, my + 1, mx - 4, my + 1)
    SDL_RenderDrawLine(renderer, mx + 4, my + 1, mx + sz + 1, my + 1)
    SDL_RenderDrawLine(renderer, mx + 1, my - sz - 1, mx + 1, my - 4)
    SDL_RenderDrawLine(renderer, mx + 1, my + 4, mx + 1, my + sz + 1)

    SDL_SetRenderDrawColor(renderer, r, g, b, 255)
    // Crosshair lines with gap in center
    SDL_RenderDrawLine(renderer, mx - sz, my, mx - 4, my)
    SDL_RenderDrawLine(renderer, mx + 4, my, mx + sz, my)
    SDL_RenderDrawLine(renderer, mx, my - sz, mx, my - 4)
    SDL_RenderDrawLine(renderer, mx, my + 4, mx, my + sz)
    // Thicker lines
    SDL_RenderDrawLine(renderer, mx - sz, my - 1, mx - 4, my - 1)
    SDL_RenderDrawLine(renderer, mx + 4, my - 1, mx + sz, my - 1)
    SDL_RenderDrawLine(renderer, mx - 1, my - sz, mx - 1, my - 4)
    SDL_RenderDrawLine(renderer, mx - 1, my + 4, mx - 1, my + sz)

    // Center dot
    var dot = SDL_Rect(x: mx - 1, y: my - 1, w: 3, h: 3)
    SDL_RenderFillRect(renderer, &dot)

    // Corner brackets
    let corner: Int32 = 4
    SDL_RenderDrawLine(renderer, mx - sz, my - sz, mx - sz + corner, my - sz)
    SDL_RenderDrawLine(renderer, mx - sz, my - sz, mx - sz, my - sz + corner)
    SDL_RenderDrawLine(renderer, mx + sz, my - sz, mx + sz - corner, my - sz)
    SDL_RenderDrawLine(renderer, mx + sz, my - sz, mx + sz, my - sz + corner)
    SDL_RenderDrawLine(renderer, mx - sz, my + sz, mx - sz + corner, my + sz)
    SDL_RenderDrawLine(renderer, mx - sz, my + sz, mx - sz, my + sz - corner)
    SDL_RenderDrawLine(renderer, mx + sz, my + sz, mx + sz - corner, my + sz)
    SDL_RenderDrawLine(renderer, mx + sz, my + sz, mx + sz, my + sz - corner)
}

// MARK: - Spinning Wrench for Building Repair Indicator

func renderRepairWrench(_ renderer: OpaquePointer?, cx: Int32, cy: Int32, tickCount: Int) {
    let angle = Double(tickCount % 30) / 30.0 * 2.0 * Double.pi
    let cosA = cos(angle)
    let sinA = sin(angle)

    let handleLen: Double = 6.0
    let headLen: Double = 3.0
    let perpX = -sinA
    let perpY = cosA

    let hx1 = Int32(Double(cx) + cosA * 1.0)
    let hy1 = Int32(Double(cy) + sinA * 1.0)
    let hx2 = Int32(Double(cx) + cosA * handleLen)
    let hy2 = Int32(Double(cy) + sinA * handleLen)
    let whx1 = Int32(Double(cx) + cosA * handleLen + perpX * headLen)
    let why1 = Int32(Double(cy) + sinA * handleLen + perpY * headLen)
    let whx2 = Int32(Double(cx) + cosA * handleLen - perpX * headLen)
    let why2 = Int32(Double(cy) + sinA * handleLen - perpY * headLen)

    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 160)
    SDL_RenderDrawLine(renderer, hx1 + 1, hy1 + 1, hx2 + 1, hy2 + 1)
    SDL_RenderDrawLine(renderer, whx1 + 1, why1 + 1, whx2 + 1, why2 + 1)

    SDL_SetRenderDrawColor(renderer, 255, 200, 0, 255)
    SDL_RenderDrawLine(renderer, hx1, hy1, hx2, hy2)
    SDL_RenderDrawLine(renderer, hx1 + Int32(perpX), hy1 + Int32(perpY), hx2 + Int32(perpX), hy2 + Int32(perpY))
    SDL_RenderDrawLine(renderer, whx1, why1, whx2, why2)
}

/// Render veterancy chevrons above a unit
/// - level 1 (Veteran): one yellow chevron
/// - level 2 (Elite): two yellow chevrons (or a star)
func renderVeterancyChevrons(_ renderer: OpaquePointer?, cx: Int32, cy: Int32, level: Int) {
    guard level > 0 else { return }
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)

    // Draw chevron(s) — small "V" shape(s) in yellow
    let chevronW: Int32 = 3
    let chevronH: Int32 = 2

    if level >= 2 {
        // Elite: draw a star (two overlapping triangles)
        SDL_SetRenderDrawColor(renderer, 255, 255, 0, 255)
        // Upper chevron
        SDL_RenderDrawLine(renderer, cx - chevronW, cy, cx, cy - chevronH)
        SDL_RenderDrawLine(renderer, cx, cy - chevronH, cx + chevronW, cy)
        // Lower chevron
        SDL_RenderDrawLine(renderer, cx - chevronW, cy - 3, cx, cy - 3 - chevronH)
        SDL_RenderDrawLine(renderer, cx, cy - 3 - chevronH, cx + chevronW, cy - 3)
    } else {
        // Veteran: single chevron
        SDL_SetRenderDrawColor(renderer, 255, 220, 0, 230)
        SDL_RenderDrawLine(renderer, cx - chevronW, cy, cx, cy - chevronH)
        SDL_RenderDrawLine(renderer, cx, cy - chevronH, cx + chevronW, cy)
    }
}
