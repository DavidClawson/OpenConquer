import Foundation
import OpenConquerAssets

// MARK: - Campaign movies
//
// Which VQA movies play around a campaign mission. The names come from the
// scenario INI's [Basic] section (INI.CPP:296-300, default "x" = none); the
// sequencing is Start_Scenario's (SCENARIO.CPP:94-110), Do_Win's (393) and
// Do_Lose's (601). Presentation only — nothing here touches the sim.

/// The movie names a scenario declares.
package struct ScenarioMovies: Equatable {
    package var intro: String?
    package var brief: String?
    package var action: String?
    package var win: String?
    package var lose: String?

    package init(intro: String? = nil, brief: String? = nil, action: String? = nil,
                 win: String? = nil, lose: String? = nil) {
        self.intro = intro
        self.brief = brief
        self.action = action
        self.win = win
        self.lose = lose
    }

    package init(ini: INIFile) {
        func movie(_ key: String) -> String? {
            let v = ini.string("Basic", key, default: "x")
                .trimmingCharacters(in: .whitespaces).uppercased()
            return (v.isEmpty || v == "X") ? nil : v
        }
        self.init(intro: movie("Intro"), brief: movie("Brief"), action: movie("Action"),
                  win: movie("Win"), lose: movie("Lose"))
    }

    /// Start_Scenario's campaign sequence (SCENARIO.CPP:94-104): no intro on
    /// Nod mission 1 (the choose-sides screen stands in for it), no briefing
    /// on GDI mission 1, and no briefing when restarting after a loss.
    package func preMission(mission: Int, isGDI: Bool, briefing: Bool) -> [String] {
        var names: [String] = []
        if mission != 1 || isGDI, let intro { names.append(intro) }
        if (mission > 1 || !isGDI) && briefing, let brief { names.append(brief) }
        if let action { names.append(action) }
        return names
    }
}

extension CampaignManager {
    /// The movies declared by `scenarioName`'s INI, or nil if it can't be read.
    package func movies(forScenario scenarioName: String) -> ScenarioMovies? {
        guard let data = mixManager.retrieve("\(scenarioName).INI") else { return nil }
        return ScenarioMovies(ini: INIFile(data: data))
    }

    /// Movies to play before the mission `startNextMission()` will load.
    package func preMissionMovies() -> [String] {
        movies(forScenario: state.scenarioName)?
            .preMission(mission: state.currentMission, isGDI: state.currentFaction == "GDI",
                        briefing: true) ?? []
    }

    /// Movies to play before `restart()` reloads the current mission — the
    /// original restarts with `briefing = false` (SCENARIO.CPP:617).
    package func restartMovies() -> [String] {
        guard let name = currentScenarioName else { return [] }
        return movies(forScenario: name)?
            .preMission(mission: state.currentMission, isGDI: state.currentFaction == "GDI",
                        briefing: false) ?? []
    }

    /// The win or lose movie of the mission just played. Read it BEFORE
    /// `handleWin()`, which advances the campaign state.
    package func endMovie(won: Bool) -> String? {
        guard let name = currentScenarioName, let m = movies(forScenario: name) else { return nil }
        return won ? m.win : m.lose
    }
}
