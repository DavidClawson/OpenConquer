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

// MARK: - Team-demand production (Suggest_New_Object port, #6C)

/// PURE: how many of each unit/infantry type this house should build to fill
/// its team templates and top up under-strength active teams, minus free field
/// units. Ports the counter[] passes of HouseClass::Suggest_New_Object
/// (HOUSE.CPP:3166-3383). Keys are uppercased INI names; only types resolvable
/// via UnitType/InfantryType.from enter the map (mirrors the C++ RTTI checks —
/// aircraft-only team slots contribute no demand). Values may go <= 0 after the
/// free-unit subtraction; callers pick among entries > 0.
func computeTeamBuildDemand(house: House, kind: ObjectKind, world: GameWorld,
                            alerted: Bool) -> [String: Int] {
    var demand: [String: Int] = [:]

    // Pass 1 — active teams (HOUSE.CPP:3209-3223 units, 3306-3319 infantry).
    for team in session.activeTeams where team.house == house {
        // Units: any not-full-strength team wants 1 of each member type
        // (assignment, not accumulation — HOUSE.CPP:3217). Infantry: any
        // reinforcable OR under-strength team ACCUMULATES desired+1 (3313).
        for slot in team.type.classSlots where slot.kind == kind {
            let name = slot.typeName.uppercased()
            switch kind {
            case .unit:
                guard !team.isFullStrength, UnitType.from(iniName: name) != nil else { continue }
                demand[name] = 1
            case .infantry:
                guard team.type.isReinforcable || !team.isFullStrength,
                      InfantryType.from(iniName: name) != nil else { continue }
                demand[name, default: 0] += slot.desiredCount + 1
            default:
                continue
            }
        }
    }

    // Pass 2 — prebuilt team TEMPLATES (the #6C gate, HOUSE.CPP:3233/3328):
    // IsPrebuilt && (!IsAutocreate || house alerted). Units take the max
    // (3237); infantry take the max then clamp at 5 (3333-3334).
    for tt in session.teamTypes where tt.house == house {
        guard tt.isPrebuilt && (!tt.isAutocreate || alerted) else { continue }
        for slot in tt.classSlots where slot.kind == kind {
            let name = slot.typeName.uppercased()
            switch kind {
            case .unit:
                guard UnitType.from(iniName: name) != nil else { continue }
                demand[name] = max(demand[name] ?? 0, slot.desiredCount)
            case .infantry:
                guard InfantryType.from(iniName: name) != nil else { continue }
                demand[name] = min(max(demand[name] ?? 0, slot.desiredCount), 5)
            default:
                continue
            }
        }
    }

    // Pass 3 — every FREE (team-less) fielded unit of this house satisfies one
    // point of demand, unless it's busy on guard-area/hunt/sticky/sleep
    // (HOUSE.CPP:3248-3253 units, 3343-3350 infantry).
    let busyMissions: Set<Mission> = [.guardArea, .hunt, .sticky, .sleep]
    for obj in world.objects {
        guard obj.house == house, obj.kind == kind, obj.strength > 0,
              !obj.isInLimbo, !obj.isAircraft else { continue }
        guard !busyMissions.contains(obj.mission), !isInTeam(obj.id) else { continue }
        demand[obj.typeName.uppercased()]? -= 1
    }

    return demand
}

/// PURE: resolve a demand map to a build plan, reproducing the classic pick
/// loop (HOUSE.CPP:3258-3277 / 3353-3374): iterate types in FIXED enum order
/// (UNIT_FIRST..COUNT — never the Dictionary, whose order is per-process),
/// keep types with demand > 0 that are buildable and affordable, and preserve
/// the faithful bestlist quirk: the list resets only on a STRICTLY larger
/// count, so later lower-count survivors stay in it. Uniform weight-1
/// candidates ⇒ applyBuildPlan's single rndInt == Random_Pick(0, bestcount-1).
/// Returns nil when the demand map is EMPTY (caller may fall back to its
/// pool); returns .none when demand exists but nothing is buildable — the
/// classic AI waits (returns NULL) rather than building something else.
func resolveTeamDemand(_ demand: [String: Int], kind: ObjectKind,
                       houseState: HouseState, costMultiplier: Double) -> AIBuildPlan? {
    guard !demand.isEmpty else { return nil }

    var bestval = -1
    var bestlist: [BuildCandidate] = []

    func consider(name: String, count: Int, cost: Int, buildTime: Int) {
        if bestval == -1 || bestval < count {
            bestval = count
            bestlist.removeAll()
        }
        bestlist.append(BuildCandidate(name: name, weight: 1, cost: cost, buildTime: buildTime))
    }

    switch kind {
    case .unit:
        for ut in UnitType.allCases {
            guard let data = unitTypeDataTable[ut] else { continue }
            let n = demand[data.iniName.uppercased()] ?? 0
            guard n > 0, houseState.canBuildUnit(data) else { continue }
            let cost = Int(Double(data.cost) * costMultiplier)
            guard cost <= houseState.credits else { continue }
            consider(name: data.iniName.uppercased(), count: n,
                     cost: cost, buildTime: max(30, cost / 5))
        }
    case .infantry:
        for it in InfantryType.allCases {
            guard let data = infantryTypeDataTable[it] else { continue }
            let n = demand[data.iniName.uppercased()] ?? 0
            guard n > 0, houseState.canBuildInfantry(data) else { continue }
            let cost = Int(Double(data.cost) * costMultiplier)
            guard cost <= houseState.credits else { continue }
            consider(name: data.iniName.uppercased(), count: n,
                     cost: cost, buildTime: max(20, cost / 5))
        }
    default:
        return nil
    }

    return bestlist.isEmpty ? AIBuildPlan.none : .weighted(bestlist)
}
