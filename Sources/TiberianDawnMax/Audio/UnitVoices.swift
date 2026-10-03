import CSDL2
import Foundation

// MARK: - Per-Unit Voice Responses
//
// The commando (RMBO) has his own voice set in the original (INFANTRY.CPP
// Response_Select / Response_Move / Response_Attack, VOC_RAMBO_* in AUDIO.CPP);
// everyone else uses the shared pool. Pure presentation: picks use the system
// RNG and never touch the sim.

extension AudioManager {

    /// Reply when a unit is selected.
    func selectResponse(for obj: GameObject) -> VocType {
        if obj.isCommando { return [.ramboYea, .ramboYes, .ramboYo].randomElement()! }
        return unitReportSound()
    }

    /// Reply to a move order, voiced by the first unit of the selection.
    func moveResponse(for units: [GameObject]) -> VocType {
        if units.first?.isCommando == true {
            return [.ramboUgotit, .ramboOnit, .ramboNoprob].randomElement()!
        }
        return unitAcknowledgeSound()
    }

    /// Reply to an attack order. "No problem" is listed twice in the original.
    func attackResponse(for units: [GameObject]) -> VocType {
        if units.first?.isCommando == true {
            return [.ramboNoprob, .ramboUgotit, .ramboNoprob, .ramboOnit].randomElement()!
        }
        return unitAcknowledgeSound()
    }

    /// Death cry: the commando's own yell (INFANTRY.CPP, VOC_RAMBO_YELL).
    func deathScream(for obj: GameObject) -> VocType {
        obj.isCommando ? .ramboYell : infantryDeathScream()
    }
}

// MARK: - Commando Kill Quips

/// Ticks a kill keeps the commando "stoked" before he comments
/// (InfantryClass::Made_A_Kill: Comment = TICKS_PER_SECOND*2).
let commandoQuipDelayTicks = 30

/// Commandos who scored a kill, keyed by object id → tick of the kill.
/// Presentation state only — kept off GameObject so it never reaches saves or
/// the determinism digest.
var commandoQuipPending: [Int: Int] = [:]

/// Mark a commando as having just made a kill (called from applyDamage).
func noteCommandoKill(_ commando: GameObject, tick: Int) {
    commandoQuipPending[commando.id] = tick
}

/// Once the delay has passed and he has stopped moving, the commando quips —
/// one line per burst of kills (INFANTRY.CPP AI: IsStoked && Comment expired
/// && !Target_Legal(NavCom)). Called once per frame from updateGame().
func tickCommandoQuips() {
    guard !commandoQuipPending.isEmpty, let world = session.world else { return }
    for (id, killTick) in commandoQuipPending where world.tickCount - killTick >= commandoQuipDelayTicks {
        guard let commando = world.findObject(id: id), commando.strength > 0, !commando.isInLimbo else {
            commandoQuipPending[id] = nil
            continue
        }
        if commando.moveTargetX != nil { continue }  // wait until he's standing still
        commandoQuipPending[id] = nil
        let quip: VocType = [.ramboLefty, .ramboLaugh, .ramboComin, .ramboTuff].randomElement()!
        audioManager.play(quip, worldX: commando.worldX, worldY: commando.worldY)
    }
}
