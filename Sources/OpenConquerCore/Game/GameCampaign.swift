import Foundation
import OpenConquerAssets

// MARK: - M14: Campaign Progression
// Save format, save and load live in GameCampaignSaveFormat/Save/Load.swift.
// Ported from Vanilla Conquer saveload.cpp, scenario.cpp, score.cpp

// MARK: - Campaign State

package class CampaignState {
    package var currentFaction: String = "GDI"   // "GDI" or "NOD"
    package var currentMission: Int = 1
    package var currentVariant: String = "EA"    // EA, EB, EC, WA, WB, WC
    package var difficulty: Int = 1              // 0=easy, 1=normal, 2=hard
    package var carryOverCredits: Int = 0
    package var carryOverPercent: Int = 50       // Percentage of credits to carry (VC default 50%)
    package var completedMissions: Set<String> = []
    package var isActive: Bool = false
    /// Building type C4'd by a commando in the CURRENT mission (mirrors the
    /// SabotagedType global, GLOBALS.CPP:214-218). Drives the GDI mission-6
    /// airstrip skip and the mission-7 destroyed-at-start rule; cleared
    /// unconditionally when the next mission starts (SCENARIO.CPP:522).
    package var sabotagedBuildingType: String? = nil

    /// Get the scenario INI name for the current mission
    package var scenarioName: String {
        let prefix = currentFaction == "GDI" ? "SCG" : "SCB"
        let num = String(format: "%02d", currentMission)
        return "\(prefix)\(num)\(currentVariant)"
    }

    /// Maximum missions for each faction
    package var maxMission: Int {
        return currentFaction == "GDI" ? 15 : 13
    }

    /// The direction letter of the current variant ('E' or 'W').
    package var dir: Character { currentVariant.first ?? "E" }

    /// Complete the current mission and return the map-selection choices for
    /// the next one. Mirrors Do_Win's sequence (SCENARIO.CPP:468-478): apply
    /// the GDI airstrip-sabotage skip FIRST (472-474), consult the campaign
    /// graph at the post-skip row (Map_Selection indexes the just-won number,
    /// MAPSEL.CPP:258), then the caller picks a territory via `advance`.
    package func completeMission() -> [CampaignChoice] {
        completedMissions.insert(scenarioName)
        carryOverCredits = min(carryOverCredits, 5000)  // Cap carry-over

        let skipped = (currentFaction == "GDI" && currentMission == 6 &&
                       sabotagedBuildingType?.uppercased() == "AFLD")
        let next = CampaignGraph.nextMissionNumber(faction: currentFaction,
                                                   wonMission: currentMission,
                                                   sabotagedAirstrip: skipped)
        if skipped {
            // The skipped mission's sabotage bonus is spent on the skip
            // itself; nothing carries into mission 8's start.
            sabotagedBuildingType = nil
            print("Campaign: airstrip sabotaged in mission 6 — skipping mission 7")
        }
        let wonRow = next - 1     // post-skip row, exactly like the original
        currentMission = next
        if currentMission > maxMission {
            isActive = false
            return []
        }
        return CampaignGraph.choices(faction: currentFaction, wonMission: wonRow, dir: dir)
    }

    /// Commit a map-selection choice (MAPSEL.CPP:717-718 ScenVar/ScenDir).
    package func advance(choosing choice: CampaignChoice) {
        currentVariant = choice.suffix
    }

    /// Check if campaign is complete
    package var isComplete: Bool {
        return currentMission > maxMission
    }

    package init() {}
}

// MARK: - Score Tracking

package class MissionScore {
    package var gdiUnitsKilled: Int = 0
    package var nodUnitsKilled: Int = 0
    package var civUnitsKilled: Int = 0
    package var gdiBuildingsKilled: Int = 0
    package var nodBuildingsKilled: Int = 0
    package var civBuildingsKilled: Int = 0
    package var creditsHarvested: Int = 0
    package var elapsedTicks: Int = 0
    package var startTime: Date = Date()

    /// Calculate a score from mission performance
    package var totalScore: Int {
        let kills = gdiUnitsKilled + nodUnitsKilled
        let buildings = gdiBuildingsKilled + nodBuildingsKilled
        let timeMinutes = max(1, elapsedTicks / (15 * 60))
        // Score formula approximating VC: kills + buildings*2 + credits/100 - time penalty
        return max(0, kills * 25 + buildings * 50 + creditsHarvested / 100 - timeMinutes * 5)
    }

    /// Star rating (1-3 stars based on performance)
    package var starRating: Int {
        let score = totalScore
        if score >= 500 { return 3 }
        if score >= 200 { return 2 }
        return 1
    }

    package func reset() {
        gdiUnitsKilled = 0
        nodUnitsKilled = 0
        civUnitsKilled = 0
        gdiBuildingsKilled = 0
        nodBuildingsKilled = 0
        civBuildingsKilled = 0
        creditsHarvested = 0
        elapsedTicks = 0
        startTime = Date()
    }
}

// MARK: - Score Screen Data

package struct ScoreScreenData {
    package let scenarioName: String
    package let won: Bool
    package let score: Int
    package let stars: Int
    package let gdiKills: Int
    package let nodKills: Int
    package let civKills: Int
    package let gdiBuildings: Int
    package let nodBuildings: Int
    package let creditsHarvested: Int
    package let elapsedTime: String
    package let briefing: String?
}

// MARK: - Campaign Manager

package class CampaignManager {
    package var state = CampaignState()
    package var score = MissionScore()
    package var currentScenarioName: String? = nil
    /// Map-selection choices produced by the last win, consumed by the
    /// MapSelectionScreen between the score screen and the briefing. Not
    /// persisted: saves only happen in-mission, never mid-selection.
    package var pendingChoices: [CampaignChoice] = []

    /// Track a kill for scoring purposes
    package func trackKill(victimHouse: House, victimKind: ObjectKind) {
        switch victimKind {
        case .structure:
            switch victimHouse {
            case .goodGuy: score.gdiBuildingsKilled += 1
            case .badGuy: score.nodBuildingsKilled += 1
            case .neutral: score.civBuildingsKilled += 1
            default: break
            }
        case .unit, .infantry:
            switch victimHouse {
            case .goodGuy: score.gdiUnitsKilled += 1
            case .badGuy: score.nodUnitsKilled += 1
            case .neutral: score.civUnitsKilled += 1
            default: break
            }
        }
    }

    /// Handle mission win
    package func handleWin() {
        guard state.isActive else { return }

        print("Campaign: Mission \(state.scenarioName) WON!")
        audioManager.speak(.accomplished)

        // Save carry-over credits
        state.carryOverCredits = session.sidebarCredits * state.carryOverPercent / 100

        // Record score
        score.elapsedTicks = session.world?.tickCount ?? 0

        // Advance campaign: compute the next mission (incl. the GDI sabotage
        // skip) and stash the map-selection choices for the UI. The variant
        // is committed by state.advance(choosing:) when the player picks.
        pendingChoices = state.completeMission()

        if state.isComplete {
            print("Campaign: \(state.currentFaction) campaign COMPLETE!")
        } else {
            print("Campaign: mission \(state.currentMission) next — \(pendingChoices.count) territory choice(s)")
        }
    }

    /// Handle mission loss
    package func handleLoss() {
        guard state.isActive else { return }

        print("Campaign: Mission \(state.scenarioName) LOST!")
        audioManager.speak(.fail)
    }

    /// Restart current mission
    package func restart() {
        guard let scenName = currentScenarioName else { return }

        // Reload the scenario
        if let scenario = loadScenario(scenName + ".INI", from: mixManager) {
            scenarioData = scenario
            initGameWorld(scenario: scenario, scenarioName: scenName)
            score.reset()
            print("Campaign: Restarted mission \(scenName)")
        }
    }

    /// Start the next campaign mission
    package func startNextMission() -> Bool {
        guard state.isActive && !state.isComplete else { return false }

        let scenName = state.scenarioName

        // Check if the scenario exists
        guard mixManager.contains("\(scenName).INI") else {
            // Try alternate variants
            for variant in ["EA", "EB", "EC"] {
                let prefix = state.currentFaction == "GDI" ? "SCG" : "SCB"
                let num = String(format: "%02d", state.currentMission)
                let altName = "\(prefix)\(num)\(variant)"
                if mixManager.contains("\(altName).INI") {
                    state.currentVariant = variant
                    return startNextMission()
                }
            }
            print("Campaign: Cannot find scenario \(scenName)")
            return false
        }

        guard let scenario = loadScenario(scenName + ".INI", from: mixManager) else {
            print("Campaign: Failed to load \(scenName)")
            return false
        }

        scenarioData = scenario
        initGameWorld(scenario: scenario, scenarioName: scenName)
        // Record it: the HUD title and restart() both key off this name.
        currentScenarioName = scenName

        // GDI mission 7: the building type sabotaged in mission 6 (if it
        // wasn't the airstrip — that skips mission 7 entirely) starts the
        // mission destroyed. Classic removes the FIRST matching non-limbo
        // enemy building of that TYPE — deliberately type-based, not
        // instance-based (SCENARIO.CPP:496-522).
        if state.currentFaction == "GDI", state.currentMission == 7,
           let sabotaged = state.sabotagedBuildingType?.uppercased(),
           let world = session.world {
            if let victim = world.objects.first(where: {
                $0.kind == .structure && $0.strength > 0 && !$0.isInLimbo &&
                $0.house != world.playerHouse && $0.house != .neutral &&
                $0.typeName.uppercased() == sabotaged
            }) {
                victim.strength = 0
                print("Campaign: \(sabotaged) sabotaged last mission — starts destroyed")
            }
        }
        // Reset unconditionally at mission start (SCENARIO.CPP:522).
        state.sabotagedBuildingType = nil

        // Set credits from scenario INI (+ carry-over from previous mission)
        session.sidebarCredits = scenario.credits + state.carryOverCredits
        session.displayedCredits = session.sidebarCredits
        if let player = session.world?.playerHouse {
            session.houseStates[player]?.initialCredits = session.sidebarCredits
        }

        // Set build level from scenario INI
        session.scenarioBuildLevel = scenario.buildLevel

        // Reset score for new mission
        score.reset()

        print("Campaign: Started mission \(scenName) with \(state.carryOverCredits) carry-over credits")
        return true
    }

    /// Get briefing text for a scenario
    package func briefingText() -> String? {
        let scenName = state.scenarioName
        guard let iniData = mixManager.retrieve("\(scenName).INI") else { return nil }
        guard let iniString = String(data: Data(iniData), encoding: .ascii) else { return nil }

        // Parse the INI to find [Briefing] section
        let lines = iniString.components(separatedBy: .newlines)
        var inBriefing = false
        var briefingParts: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if inBriefing { break }
                if trimmed.lowercased() == "[briefing]" {
                    inBriefing = true
                }
                continue
            }
            if inBriefing && !trimmed.isEmpty {
                // Briefing lines are numbered: 1=text, 2=text, etc.
                if let eqIdx = trimmed.firstIndex(of: "=") {
                    let text = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                    briefingParts.append(text)
                }
            }
        }

        if briefingParts.isEmpty { return nil }
        return briefingParts.joined(separator: " ")
    }

    /// Get briefing text for a specific scenario name
    package func briefingText(scenarioName: String) -> String? {
        guard let iniData = mixManager.retrieve("\(scenarioName).INI") else { return nil }
        guard let iniString = String(data: Data(iniData), encoding: .ascii) else { return nil }

        let lines = iniString.components(separatedBy: .newlines)
        var inBriefing = false
        var briefingParts: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                if inBriefing { break }
                if trimmed.lowercased() == "[briefing]" {
                    inBriefing = true
                }
                continue
            }
            if inBriefing && !trimmed.isEmpty {
                if let eqIdx = trimmed.firstIndex(of: "=") {
                    let text = String(trimmed[trimmed.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                    briefingParts.append(text)
                }
            }
        }

        if briefingParts.isEmpty { return nil }
        return briefingParts.joined(separator: " ")
    }

    /// Generate score screen data for the completed mission
    package func scoreScreen(won: Bool) -> ScoreScreenData {
        let ticks = score.elapsedTicks
        let minutes = ticks / (15 * 60)
        let seconds = (ticks / 15) % 60
        let timeStr = String(format: "%d:%02d", minutes, seconds)

        return ScoreScreenData(
            scenarioName: currentScenarioName ?? "Unknown",
            won: won,
            score: score.totalScore,
            stars: score.starRating,
            gdiKills: score.gdiUnitsKilled,
            nodKills: score.nodUnitsKilled,
            civKills: score.civUnitsKilled,
            gdiBuildings: score.gdiBuildingsKilled,
            nodBuildings: score.nodBuildingsKilled,
            creditsHarvested: score.creditsHarvested,
            elapsedTime: timeStr,
            briefing: briefingText(scenarioName: currentScenarioName ?? "")
        )
    }
}
