import Foundation

// MARK: - Campaign Graph (map-selection branching)
//
// A pure Swift transcription of the original CountryArray (MAPSEL.CPP:76-119).
// After winning mission N, the map-selection screen offers up to 3 territory
// choices; each choice carries the DIRECTION (E/W) and VARIANT (A/B/C) letters
// of mission N+1's scenario file — `SC<G|B><NN><dir><var>` (INI.CPP:84-186,
// Set_Scenario_Name). The node is indexed by the JUST-WON mission number
// (MAPSEL.CPP:258), consulted AFTER the GDI sabotage skip (SCENARIO.CPP:472-478,
// where Do_Win applies `Scenario++` for the skip BEFORE Map_Selection and the
// regular `Scenario++` after it).

/// One territory choice on the map-selection screen.
struct CampaignChoice: Equatable {
    let dir: Character       // 'E' | 'W'
    let variant: Character   // 'A' | 'B' | 'C'

    /// The two-letter scenario suffix ("EA", "WB", ...).
    var suffix: String { "\(dir)\(variant)" }
}

enum CampaignGraph {

    /// Per (dir) choice lists, indexed by the just-won mission number.
    private struct Node {
        let east: [CampaignChoice]
        let west: [CampaignChoice]
    }

    private static func c(_ dir: Character, _ variant: Character) -> CampaignChoice {
        CampaignChoice(dir: dir, variant: variant)
    }

    /// GDI rows 1-14 of CountryArray (MAPSEL.CPP:88-102). The W columns of
    /// rows 7-14 are SDN/SVN in the original (randomly resolved) but are
    /// unreachable: rows 5-6 funnel the West path back East, so they default.
    private static let gdi: [Int: Node] = [
        1:  Node(east: [c("E", "A")], west: []),
        2:  Node(east: [c("E", "A")], west: []),
        3:  Node(east: [c("W", "A"), c("W", "B"), c("E", "A")],           // the 3-way fork
                 west: []),
        4:  Node(east: [c("E", "A"), c("E", "A")],
                 west: [c("W", "A"), c("W", "B")]),                       // West path continues
        5:  Node(east: [c("E", "A"), c("E", "A")],
                 west: [c("E", "A"), c("E", "A")]),                       // funnels back East
        6:  Node(east: [c("E", "A"), c("E", "A")],
                 west: [c("E", "A"), c("E", "A")]),
        7:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        8:  Node(east: [c("E", "A")], west: []),
        9:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        10: Node(east: [c("E", "A")], west: []),
        11: Node(east: [c("E", "A"), c("E", "B")], west: []),
        12: Node(east: [c("E", "A"), c("E", "B")], west: []),
        13: Node(east: [c("E", "A")], west: []),
        14: Node(east: [c("E", "A"), c("E", "B"), c("E", "C")], west: []),  // final: SCG15EA/EB/EC
    ]

    /// Nod rows 1-12 (MAPSEL.CPP:105-118). The Nod campaign never branches West.
    private static let nod: [Int: Node] = [
        1:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        2:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        3:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        4:  Node(east: [c("E", "A")], west: []),
        5:  Node(east: [c("E", "A"), c("E", "B"), c("E", "C")], west: []),
        6:  Node(east: [c("E", "A"), c("E", "B"), c("E", "C")], west: []),
        7:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        8:  Node(east: [c("E", "A")], west: []),
        9:  Node(east: [c("E", "A"), c("E", "B")], west: []),
        10: Node(east: [c("E", "A"), c("E", "B")], west: []),
        11: Node(east: [c("E", "A")], west: []),
        12: Node(east: [c("E", "A"), c("E", "B"), c("E", "C")], west: []),  // final: SCB13EA/EB/EC
    ]

    /// The territory choices offered after winning `wonMission` (post-skip
    /// number) while travelling `dir`. Missing rows or empty columns default
    /// to a single East-A path, matching every non-branching transition.
    static func choices(faction: String, wonMission: Int, dir: Character) -> [CampaignChoice] {
        let node = (faction == "GDI" ? gdi : nod)[wonMission]
        let list = (dir == "W") ? (node?.west ?? []) : (node?.east ?? [])
        return list.isEmpty ? [CampaignChoice(dir: "E", variant: "A")] : list
    }

    /// Next mission number after a win: won+1, or won+2 for the GDI mission-6
    /// airstrip sabotage skip (SCENARIO.CPP:472-474 — `if (Scenario == 6 &&
    /// house == GOOD && SabotagedType == STRUCT_AIRSTRIP) Scenario++;` before
    /// the regular increment).
    static func nextMissionNumber(faction: String, wonMission: Int,
                                  sabotagedAirstrip: Bool) -> Int {
        if faction == "GDI" && wonMission == 6 && sabotagedAirstrip {
            return wonMission + 2
        }
        return wonMission + 1
    }
}
