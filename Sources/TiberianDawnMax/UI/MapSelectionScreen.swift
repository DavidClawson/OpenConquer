import Foundation
import CSDL2

// MARK: - Map Selection Screen (campaign branching)
//
// The between-missions territory pick. The original shows a territory map
// (COUNTRYE/W.SHP) and loops until a valid territory is clicked — no cancel
// (MAPSEL.CPP:693-716); it appears even when there is exactly ONE choice
// (only Choices==0 skips it, MAPSEL.CPP:268). This first pass renders the
// choices as a list; the full territory-map art can replace it later.

class MapSelectionScreen: MenuScreen {
    private let choices: [CampaignChoice]

    init(choices: [CampaignChoice]) {
        // Defensive: an empty list would strand the screen; the graph never
        // returns one for an unfinished campaign (it defaults to E/A).
        self.choices = choices.isEmpty ? [CampaignChoice(dir: "E", variant: "A")] : choices
    }

    private func buttons() -> [Button] {
        let bw: Int32 = 360
        let bh: Int32 = 44
        let gap: Int32 = 16
        let cx = renderState.windowWidth / 2 - bw / 2
        let total = Int32(choices.count) * (bh + gap) - gap
        var y = renderState.windowHeight / 2 - total / 2

        var result: [Button] = []
        for (i, choice) in choices.enumerated() {
            let state = session.campaignState
            let prefix = state.currentFaction == "GDI" ? "SCG" : "SCB"
            let num = String(format: "%02d", state.currentMission)
            let label = "Territory \(i + 1)  (\(prefix)\(num)\(choice.suffix))"
            result.append(Button(label: label, x: cx, y: y, w: bw, h: bh) {
                session.campaignState.advance(choosing: choice)
                session.campaign.pendingChoices = []
                session.currentScreen = BriefingScreen()
            })
            y += bh + gap
        }
        return result
    }

    func render(_ renderer: OpaquePointer?) {
        drawText(renderer, "SELECT THE NEXT AREA OF CONFLICT",
                 centerX: renderState.windowWidth / 2, centerY: 100, color: .amber, scale: 2)
        for btn in buttons() {
            btn.draw(renderer, highlighted: btn.contains(input.mouseX, input.mouseY))
        }
        drawText(renderer, "Click a territory to continue",
                 centerX: renderState.windowWidth / 2,
                 centerY: renderState.windowHeight - 40, color: .gray, scale: 1)
    }

    func handleMouseDown(_ x: Int32, _ y: Int32, button: UInt8) {
        guard button == UInt8(SDL_BUTTON_LEFT) else { return }
        for btn in buttons() where btn.contains(x, y) {
            btn.action()
            return
        }
    }

    func handleKeyDown(_ key: Int32) {
        // Number keys pick directly; no escape — the original loops until a
        // territory is chosen (MAPSEL.CPP:693-716).
        let idx = Int(key) - Int(SDLK_1.rawValue)
        if idx >= 0 && idx < choices.count {
            session.campaignState.advance(choosing: choices[idx])
            session.campaign.pendingChoices = []
            session.currentScreen = BriefingScreen()
        }
    }
}
