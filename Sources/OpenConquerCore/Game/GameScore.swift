import Foundation

// MARK: - Campaign score (ScoreClass::Presentation's arithmetic)
//
// The numbers the end-of-mission score screen shows, computed exactly as
// SCORE.CPP:643-696 does, including its fixed-point helpers and quirks. Pure:
// the app gathers the inputs from the finished mission (or a test fakes them).

/// What ScoreClass reads from the world when the screen comes up.
package struct ScoreInputs: Equatable {
    package var isGDI: Bool
    /// The mission just won. For campaign missions BuildLevel == Scenario
    /// (INI.CPP:309), which multiplies the total.
    package var scenario: Int
    /// Game frames played (15 per second).
    package var elapsedTicks: Int
    /// Objects on the logic list owned by the player at the end (the
    /// "leadership" numerator, SCORE.CPP:648-654).
    package var survivingObjects: Int
    /// HouseClass::UnitsLost / BuildingsLost per house (SCORE.CPP:661-666).
    package var gdiUnitsLost: Int
    package var nodUnitsLost: Int
    package var civUnitsLost: Int
    package var gdiBuildingsLost: Int
    package var nodBuildingsLost: Int
    package var civBuildingsLost: Int
    /// The player's HarvestedCredits, InitialCredits and Available_Money().
    package var harvestedCredits: Int
    package var initialCredits: Int
    package var credits: Int

    package init(isGDI: Bool, scenario: Int, elapsedTicks: Int, survivingObjects: Int,
                 gdiUnitsLost: Int, nodUnitsLost: Int, civUnitsLost: Int,
                 gdiBuildingsLost: Int, nodBuildingsLost: Int, civBuildingsLost: Int,
                 harvestedCredits: Int, initialCredits: Int, credits: Int) {
        self.isGDI = isGDI
        self.scenario = scenario
        self.elapsedTicks = elapsedTicks
        self.survivingObjects = survivingObjects
        self.gdiUnitsLost = gdiUnitsLost
        self.nodUnitsLost = nodUnitsLost
        self.civUnitsLost = civUnitsLost
        self.gdiBuildingsLost = gdiBuildingsLost
        self.nodBuildingsLost = nodBuildingsLost
        self.civBuildingsLost = civBuildingsLost
        self.harvestedCredits = harvestedCredits
        self.initialCredits = initialCredits
        self.credits = credits
    }
}

package struct ScoreResult: Equatable {
    package let leadership: Int   // percent, 0-100
    package let efficiency: Int   // percent, 1-100
    package let total: Int
    package let minutes: Int      // as printed next to TIME:

    package init(_ s: ScoreInputs) {
        // ElapsedTime gains TIMER_SECOND / TICKS_PER_SECOND (4) per game
        // frame (CONQUER.CPP:1597); minutes = ElapsedTime / TIMER_MINUTE + 1.
        minutes = s.elapsedTicks * 4 / 3600 + 1

        // Leadership. The original always uses GDI's losses here, whichever
        // side the player is on (SCORE.CPP:675) — kept as is.
        var lead = UInt32(max(0, s.survivingObjects))
        if lead == 0 { lead = 1 }
        lead = Self.cardinalToFixed(UInt32(max(0, s.gdiUnitsLost + s.gdiBuildingsLost)) &+ lead, lead)
        lead = Self.fixedToCardinal(100, lead)
        leadership = Int(min(lead, 100))

        // Efficiency: money left over what was harvested plus what you had.
        var eff = Self.cardinalToFixed(UInt32(truncatingIfNeeded: s.harvestedCredits + s.initialCredits + 1),
                                       UInt32(truncatingIfNeeded: s.credits + 1))
        if eff == 0 { eff = 1 }
        eff = Self.fixedToCardinal(100, eff)
        efficiency = Int(min(eff, 100))

        var t = (leadership * 40 + 4600 + efficiency * 14) / 100
        if t == 0 { t = 1 }
        total = t * (s.scenario + 1)
    }

    /// Cardinal_To_Fixed: cardinal / base as 8.8 fixed point.
    static func cardinalToFixed(_ base: UInt32, _ cardinal: UInt32) -> UInt32 {
        base == 0 ? 0xFFFF : (cardinal &<< 8) / base
    }

    /// Fixed_To_Cardinal: base * fixed, rounded, saturating at 0xFFFF.
    static func fixedToCardinal(_ base: UInt32, _ fixed: UInt32) -> UInt32 {
        let tmp = fixed &* base &+ 128
        return tmp & 0xFF00_0000 != 0 ? 0xFFFF : tmp >> 8
    }
}

// MARK: - Hall of fame (HALLFAME.DAT)

package struct FameEntry: Codable, Equatable {
    package var name: String
    package var score: Int
    package var level: Int

    package init(name: String = "", score: Int = 0, level: Int = 0) {
        self.name = name
        self.score = score
        self.level = level
    }
}

package enum HallOfFame {
    package static let count = 7          // NUMFAMENAMES
    package static let nameLength = 12   // MAX_FAMENAME_LENGTH, terminator included

    /// Enter `total` the way SCORE.CPP:900-913 does and return the row the
    /// player names, or nil if it doesn't place. Because the last row's
    /// score is cleared when it isn't beaten, a new score always places —
    /// at worst replacing the bottom entry.
    package static func insert(total: Int, level: Int, into list: inout [FameEntry]) -> Int? {
        while list.count < count { list.append(FameEntry()) }
        if list.count > count { list.removeLast(list.count - count) }
        if list[count - 1].score >= total { list[count - 1].score = 0 }
        for index in 0..<count where total > list[index].score {
            if index < count - 1 {
                for i in stride(from: count - 1, to: index, by: -1) { list[i] = list[i - 1] }
            }
            list[index] = FameEntry(name: String(repeating: " ", count: nameLength - 1),
                                    score: total, level: level)
            return index
        }
        return nil
    }
}
