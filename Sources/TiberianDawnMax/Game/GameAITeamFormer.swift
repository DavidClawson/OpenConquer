import Foundation

// MARK: - AI Team Formation (Gap #6)
//
// Faithful port of the classic team-creation model. In Tiberian Dawn the AI
// forms teams two ways inside HouseClass::AI:
//   • a REGULAR former on a short timer that picks the best-scoring non-alerted
//     team (HOUSE.CPP:868-872, TeamTime = TEAM_DELAY = 90 ticks), and
//   • an ALERTED BURST that, while the house is alerted, spawns a difficulty-
//     scaled batch of teams (HOUSE.CPP:839-862).
// Both choose via TeamTypeClass::Suggested_New_Team (TEAMTYPE.CPP:930-1005),
// which scores each of the house's team types by RecruitPriority (halved if the
// house doesn't already own a needed member type — the UScan/IScan check) and
// skips any type already at its MaxAllowed cap.
//
// This replaces the old `tryAutocreateTeam` (a flat every-675-tick random pick),
// which ignored priority, MaxAllowed, and the alerted gate.
//
// Determinism: `decideSuggestedTeam` and the scan are PURE (no gameRng, no
// mutation) so the AI decide phase stays pure (`--ai-parity`). The only new RNG
// draw is the burst's team count, taken in a fixed per-house order in the
// effectful `tickAITeamFormation`.

/// TEAM_DELAY — the regular former's cadence (HOUSE.CPP:868, TICKS_PER_MINUTE/10).
private let teamFormDelayTicks = 90

/// The set of unit/infantry types this house currently owns in the field and
/// could recruit — the UScan/IScan analogue (HOUSE.CPP:774-788). Eligibility
/// mirrors `recruitMembers` (alive, deployed, not a harvester/MCV).
func ownedRecruitableTypes(house: House, world: GameWorld) -> Set<String> {
    var owned: Set<String> = []
    for obj in world.objects where obj.house == house {
        guard obj.strength > 0, !obj.isInLimbo, !obj.isHarvester, !obj.isMCV else { continue }
        owned.insert(obj.typeName.uppercased())
    }
    return owned
}

/// PURE (B3): mirrors TeamTypeClass::Suggested_New_Team (TEAMTYPE.CPP:930-1005).
/// Returns the highest-scoring team type this house should form now, or nil.
/// `alerted` gates autocreate types (they're only eligible while the house is
/// alerted, matching the C++ split between the regular former and the burst).
func decideSuggestedTeam(house: House, world: GameWorld, alerted: Bool) -> TeamType? {
    let owned = ownedRecruitableTypes(house: house, world: world)
    var best: TeamType? = nil
    var bestValue = 0
    for tt in session.teamTypes {                       // parse order == C++ index order
        guard tt.house == house else { continue }
        // Autocreate types only participate while alerted; non-autocreate always.
        // NOTE: here MaxAllowed is a literal cap — a type with MaxAllowed==0 is
        // never suggested (distinct from createTeam, where 0 means "unlimited").
        let cap = (alerted || !tt.isAutocreate) ? tt.maxAllowed : 0
        let active = session.activeTeams.reduce(0) { $0 + ($1.type.name == tt.name ? 1 : 0) }
        guard active < cap else { continue }             // TEAMTYPE.CPP:938-939
        // Full priority if the house owns a needed member type, else half.
        let hasNeeded = tt.classSlots.contains { owned.contains($0.typeName.uppercased()) }
        let value = hasNeeded ? tt.recruitPriority : tt.recruitPriority / 2
        if best == nil || bestValue < value {            // strict < → first wins ties
            bestValue = value
            best = tt
        }
    }
    return best
}

/// EFFECTFUL (B3): create one of the suggested team (Create_One_Of,
/// TEAMTYPE.CPP:877-884). `bypassCap` == the C++ `ScenarioInit++` used by the
/// alerted burst so it can exceed MaxAllowed. Drops a team that recruited nobody.
func applySuggestedTeam(_ tt: TeamType, bypassCap: Bool) {
    let team = bypassCap ? forceCreateAndRecruitTeam(type: tt) : createAndRecruitTeam(type: tt)
    if let team = team, team.memberCount == 0 {
        session.activeTeams.removeAll { $0 === team }
    }
}

/// Ticks (in game frames) between alerted bursts, scaled by difficulty. Fixed
/// (no RNG) so it doesn't perturb the draw order; harder difficulty bursts more
/// often. (C++ scales AlertTime by difficulty, HOUSE.CPP:844-851.)
func alertTimerReset() -> Int {
    switch session.campaignState.difficulty {   // 0=easy, 1=normal, 2=hard
    case 2:  return 15 * 60 * 5      // hard   — ~5 min
    case 0:  return 15 * 60 * 12     // easy   — ~12 min
    default: return 15 * 60 * 8      // normal — ~8 min
    }
}

/// Drive AI team formation. Called every 30 ticks from `tickAI`; the internal
/// 90-tick regular cadence and the alert-timer countdown are handled here.
func tickAITeamFormation(world: GameWorld) {
    for house in session.houseStates.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
        guard let state = session.houseStates[house], !state.isHuman else { continue }
        guard state.productionEnabled else { continue }

        // Alerted burst (HOUSE.CPP:839-862): a difficulty-scaled batch, allowed
        // to exceed MaxAllowed. RNG draw (team count) is taken here, per house,
        // in the fixed sorted order above.
        if state.isAlerted && state.alertTimer <= 0 {
            let bl = session.scenarioBuildLevel
            let maxTeams = rndInt(2...max(2, (bl - 1) / 3 + 1))     // Random_Pick(2, …)
            for _ in 0..<maxTeams {
                if let tt = decideSuggestedTeam(house: house, world: world, alerted: true) {
                    applySuggestedTeam(tt, bypassCap: true)
                }
            }
            state.alertTimer = alertTimerReset()
        } else if state.isAlerted {
            state.alertTimer -= 30      // this pass runs every 30 ticks
        }

        // Regular former (HOUSE.CPP:868-872): every TEAM_DELAY, one best team.
        if world.tickCount - state.aiLastTeamFormTick >= teamFormDelayTicks {
            state.aiLastTeamFormTick = world.tickCount
            if let tt = decideSuggestedTeam(house: house, world: world, alerted: false) {
                applySuggestedTeam(tt, bypassCap: false)
            }
        }
    }
}
