import Foundation

// MARK: - M14: Save/Load & Campaign Progression
// Ported from Vanilla Conquer saveload.cpp, scenario.cpp, score.cpp

// MARK: - Campaign State

class CampaignState {
    var currentFaction: String = "GDI"   // "GDI" or "NOD"
    var currentMission: Int = 1
    var currentVariant: String = "EA"    // EA, EB, EC, WA, WB, WC
    var difficulty: Int = 1              // 0=easy, 1=normal, 2=hard
    var carryOverCredits: Int = 0
    var carryOverPercent: Int = 50       // Percentage of credits to carry (VC default 50%)
    var completedMissions: Set<String> = []
    var isActive: Bool = false

    /// Get the scenario INI name for the current mission
    var scenarioName: String {
        let prefix = currentFaction == "GDI" ? "SCG" : "SCB"
        let num = String(format: "%02d", currentMission)
        return "\(prefix)\(num)\(currentVariant)"
    }

    /// Maximum missions for each faction
    var maxMission: Int {
        return currentFaction == "GDI" ? 15 : 13
    }

    /// Advance to the next mission
    func advanceMission() {
        completedMissions.insert(scenarioName)
        carryOverCredits = min(carryOverCredits, 5000)  // Cap carry-over

        currentMission += 1

        // Pick a variant — try EA first, then EB, EC
        currentVariant = "EA"
        if currentMission > maxMission {
            // Campaign complete
            isActive = false
        }
    }

    /// Check if campaign is complete
    var isComplete: Bool {
        return currentMission > maxMission
    }
}

/// Global campaign state
var campaignState = CampaignState()

// MARK: - Score Tracking

class MissionScore {
    var gdiUnitsKilled: Int = 0
    var nodUnitsKilled: Int = 0
    var civUnitsKilled: Int = 0
    var gdiBuildingsKilled: Int = 0
    var nodBuildingsKilled: Int = 0
    var civBuildingsKilled: Int = 0
    var creditsHarvested: Int = 0
    var elapsedTicks: Int = 0
    var startTime: Date = Date()

    /// Calculate a score from mission performance
    var totalScore: Int {
        let kills = gdiUnitsKilled + nodUnitsKilled
        let buildings = gdiBuildingsKilled + nodBuildingsKilled
        let timeMinutes = max(1, elapsedTicks / (15 * 60))
        // Score formula approximating VC: kills + buildings*2 + credits/100 - time penalty
        return max(0, kills * 25 + buildings * 50 + creditsHarvested / 100 - timeMinutes * 5)
    }

    /// Star rating (1-3 stars based on performance)
    var starRating: Int {
        let score = totalScore
        if score >= 500 { return 3 }
        if score >= 200 { return 2 }
        return 1
    }

    func reset() {
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

var missionScore = MissionScore()

/// Track a kill for scoring purposes
func trackKill(victimHouse: House, victimKind: ObjectKind) {
    switch victimKind {
    case .structure:
        switch victimHouse {
        case .goodGuy: missionScore.gdiBuildingsKilled += 1
        case .badGuy: missionScore.nodBuildingsKilled += 1
        case .neutral: missionScore.civBuildingsKilled += 1
        default: break
        }
    case .unit, .infantry:
        switch victimHouse {
        case .goodGuy: missionScore.gdiUnitsKilled += 1
        case .badGuy: missionScore.nodUnitsKilled += 1
        case .neutral: missionScore.civUnitsKilled += 1
        default: break
        }
    }
}

// MARK: - Save Game Data Structure

struct SaveGameData: Codable {
    // Header
    let version: Int
    let description: String
    let saveDate: Date
    let scenarioName: String

    // World state
    let tickCount: Int
    let playerHouse: String
    let theater: String
    let mapBoundsX: Int
    let mapBoundsY: Int
    let mapBoundsW: Int
    let mapBoundsH: Int

    // Credits
    let credits: Int

    // Objects
    let objects: [SavedObject]

    // Campaign
    let campaignFaction: String
    let campaignMission: Int
    let campaignVariant: String
    let campaignDifficulty: Int
    let carryOverCredits: Int

    // Score
    let scoreGDIKills: Int
    let scoreNodKills: Int
    let scoreCivKills: Int
    let scoreGDIBuildings: Int
    let scoreNodBuildings: Int
    let scoreCivBuildings: Int
    let scoreCreditsHarvested: Int
    let scoreElapsedTicks: Int

    // Triggers
    let triggers: [SavedTrigger]

    // Camera
    let cameraX: Double
    let cameraY: Double
}

struct SavedObject: Codable {
    let id: Int
    let typeName: String
    let house: String
    let kind: String
    let worldX: Double
    let worldY: Double
    let facing: Int
    let strength: Int
    let mission: String
    let speed: Double
    let isSelected: Bool
    let triggerName: String?
    let isAircraft: Bool
    let altitude: Int
    let ammo: Int
    let subCell: Int
}

struct SavedTrigger: Codable {
    let name: String
    let isActive: Bool
    let data: Int
    let attachCount: Int
}

// MARK: - Save Directory

let saveDirectory: URL = {
    let appSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TiberianDawnMax")
    try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    return appSupport
}()

// MARK: - Save Game

func saveGame(slot: Int, description: String = "") -> Bool {
    guard let world = gameWorld else {
        print("SaveGame: No world to save")
        return false
    }

    let desc = description.isEmpty ? "Save \(slot) - \(campaignState.scenarioName)" : description

    // Serialize objects
    var savedObjects: [SavedObject] = []
    for obj in world.objects {
        let saved = SavedObject(
            id: obj.id,
            typeName: obj.typeName,
            house: obj.house.rawValue,
            kind: objectKindString(obj.kind),
            worldX: obj.worldX,
            worldY: obj.worldY,
            facing: obj.facing,
            strength: obj.strength,
            mission: obj.mission.saveName,
            speed: obj.speed,
            isSelected: obj.isSelected,
            triggerName: obj.triggerName,
            isAircraft: obj.isAircraft,
            altitude: obj.altitude,
            ammo: obj.ammo,
            subCell: obj.subCell
        )
        savedObjects.append(saved)
    }

    // Serialize trigger state
    var savedTriggers: [SavedTrigger] = []
    for trigger in gameTriggers {
        savedTriggers.append(SavedTrigger(
            name: trigger.name,
            isActive: trigger.isActive,
            data: trigger.data,
            attachCount: trigger.attachCount
        ))
    }

    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    let saveData = SaveGameData(
        version: 1,
        description: desc,
        saveDate: Date(),
        scenarioName: currentScenarioName ?? campaignState.scenarioName,
        tickCount: world.tickCount,
        playerHouse: world.playerHouse.rawValue,
        theater: world.theater.rawValue,
        mapBoundsX: bounds.x,
        mapBoundsY: bounds.y,
        mapBoundsW: bounds.width,
        mapBoundsH: bounds.height,
        credits: sidebarCredits,
        objects: savedObjects,
        campaignFaction: campaignState.currentFaction,
        campaignMission: campaignState.currentMission,
        campaignVariant: campaignState.currentVariant,
        campaignDifficulty: campaignState.difficulty,
        carryOverCredits: campaignState.carryOverCredits,
        scoreGDIKills: missionScore.gdiUnitsKilled,
        scoreNodKills: missionScore.nodUnitsKilled,
        scoreCivKills: missionScore.civUnitsKilled,
        scoreGDIBuildings: missionScore.gdiBuildingsKilled,
        scoreNodBuildings: missionScore.nodBuildingsKilled,
        scoreCivBuildings: missionScore.civBuildingsKilled,
        scoreCreditsHarvested: missionScore.creditsHarvested,
        scoreElapsedTicks: missionScore.elapsedTicks,
        triggers: savedTriggers,
        cameraX: gameCameraX,
        cameraY: gameCameraY
    )

    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(saveData)

        let filename = "save_\(slot).json"
        let fileURL = saveDirectory.appendingPathComponent(filename)
        try jsonData.write(to: fileURL)

        print("SaveGame: Saved to slot \(slot) (\(savedObjects.count) objects, \(jsonData.count) bytes)")
        return true
    } catch {
        print("SaveGame: Failed to save: \(error)")
        return false
    }
}

// MARK: - Load Game

func loadGame(slot: Int) -> Bool {
    let filename = "save_\(slot).json"
    let fileURL = saveDirectory.appendingPathComponent(filename)

    do {
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        let saveData = try decoder.decode(SaveGameData.self, from: jsonData)

        guard saveData.version == 1 else {
            print("LoadGame: Unsupported save version \(saveData.version)")
            return false
        }

        // First load the scenario to get terrain, overlays, triggers etc.
        let scenName = saveData.scenarioName
        guard let scenario = loadScenario(scenName + ".INI", from: mixManager) else {
            print("LoadGame: Cannot load scenario '\(scenName)'")
            return false
        }
        scenarioData = scenario

        // Create world
        let world = GameWorld()
        world.theater = TheaterType(rawValue: saveData.theater) ?? .temperate
        world.mapBounds = MapBounds(
            x: saveData.mapBoundsX, y: saveData.mapBoundsY,
            width: saveData.mapBoundsW, height: saveData.mapBoundsH
        )
        world.tickCount = saveData.tickCount
        world.playerHouse = House.from(saveData.playerHouse)

        // Restore objects
        for saved in saveData.objects {
            let kind = objectKindFromString(saved.kind)
            let obj = GameObject(
                id: saved.id,
                typeName: saved.typeName,
                house: House.from(saved.house),
                kind: kind,
                worldX: saved.worldX, worldY: saved.worldY,
                facing: saved.facing,
                strength: saved.strength,
                mission: Mission.from(saved.mission),
                speed: saved.speed,
                subCell: saved.subCell
            )
            obj.isSelected = saved.isSelected
            obj.triggerName = saved.triggerName
            obj.isAircraft = saved.isAircraft
            obj.altitude = saved.altitude
            obj.ammo = saved.ammo
            world.addObject(obj)
            world.nextObjectId = max(world.nextObjectId, saved.id + 1)
        }

        gameWorld = world
        sidebarCredits = saveData.credits
        gameCameraX = saveData.cameraX
        gameCameraY = saveData.cameraY
        currentScenarioName = scenName

        // Restore campaign state
        campaignState.currentFaction = saveData.campaignFaction
        campaignState.currentMission = saveData.campaignMission
        campaignState.currentVariant = saveData.campaignVariant
        campaignState.difficulty = saveData.campaignDifficulty
        campaignState.carryOverCredits = saveData.carryOverCredits
        campaignState.isActive = true

        // Restore score
        missionScore.gdiUnitsKilled = saveData.scoreGDIKills
        missionScore.nodUnitsKilled = saveData.scoreNodKills
        missionScore.civUnitsKilled = saveData.scoreCivKills
        missionScore.gdiBuildingsKilled = saveData.scoreGDIBuildings
        missionScore.nodBuildingsKilled = saveData.scoreNodBuildings
        missionScore.civBuildingsKilled = saveData.scoreCivBuildings
        missionScore.creditsHarvested = saveData.scoreCreditsHarvested
        missionScore.elapsedTicks = saveData.scoreElapsedTicks

        // Restore trigger states
        for savedTrigger in saveData.triggers {
            if let trigger = gameTriggers.first(where: { $0.name == savedTrigger.name }) {
                trigger.isActive = savedTrigger.isActive
                trigger.data = savedTrigger.data
                trigger.attachCount = savedTrigger.attachCount
            }
        }

        // Rebuild derived data
        buildPassabilityMap()
        initTiberiumCells()
        initFog()
        initHouseStates()
        resetSuperWeapons()

        // Reload palette for theater
        let palName: String
        switch world.theater {
        case .temperate: palName = "TEMPERAT.PAL"
        case .desert: palName = "DESERT.PAL"
        case .winter: palName = "WINTER.PAL"
        }
        gamePalette = loadPalette(palName)

        print("LoadGame: Loaded slot \(slot) - '\(saveData.description)' (\(world.objects.count) objects)")
        return true
    } catch {
        print("LoadGame: Failed to load slot \(slot): \(error)")
        return false
    }
}

// MARK: - Save Slot Info

struct SaveSlotInfo {
    let slot: Int
    let description: String
    let date: Date
    let scenarioName: String
    let exists: Bool
}

/// List available save slots
func listSaveSlots() -> [SaveSlotInfo] {
    var slots: [SaveSlotInfo] = []

    for slot in 0..<10 {
        let filename = "save_\(slot).json"
        let fileURL = saveDirectory.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let jsonData = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                let saveData = try decoder.decode(SaveGameData.self, from: jsonData)
                slots.append(SaveSlotInfo(
                    slot: slot,
                    description: saveData.description,
                    date: saveData.saveDate,
                    scenarioName: saveData.scenarioName,
                    exists: true
                ))
            } catch {
                slots.append(SaveSlotInfo(slot: slot, description: "Corrupted", date: Date(), scenarioName: "", exists: true))
            }
        } else {
            slots.append(SaveSlotInfo(slot: slot, description: "Empty", date: Date(), scenarioName: "", exists: false))
        }
    }

    return slots
}

/// Delete a save slot
func deleteSaveSlot(_ slot: Int) {
    let filename = "save_\(slot).json"
    let fileURL = saveDirectory.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: fileURL)
}

// MARK: - Quick Save/Load

func quickSave() -> Bool {
    return saveGame(slot: 0, description: "Quick Save")
}

func quickLoad() -> Bool {
    return loadGame(slot: 0)
}

// MARK: - Mission Completion

/// Handle mission win
func handleMissionWin() {
    guard campaignState.isActive else { return }

    print("Campaign: Mission \(campaignState.scenarioName) WON!")
    speak(.accomplished)

    // Save carry-over credits
    campaignState.carryOverCredits = sidebarCredits * campaignState.carryOverPercent / 100

    // Record score
    missionScore.elapsedTicks = gameWorld?.tickCount ?? 0

    // Advance campaign
    campaignState.advanceMission()

    if campaignState.isComplete {
        print("Campaign: \(campaignState.currentFaction) campaign COMPLETE!")
    } else {
        print("Campaign: Next mission is \(campaignState.scenarioName)")
    }
}

/// Handle mission loss
func handleMissionLoss() {
    guard campaignState.isActive else { return }

    print("Campaign: Mission \(campaignState.scenarioName) LOST!")
    speak(.fail)
}

/// Restart current mission
func restartMission() {
    guard let scenName = currentScenarioName else { return }

    // Reload the scenario
    if let scenario = loadScenario(scenName + ".INI", from: mixManager) {
        scenarioData = scenario
        initGameWorld(scenario: scenario, scenarioName: scenName)
        missionScore.reset()
        lastTickTime = 0
        tickAccumulator = 0
        print("Campaign: Restarted mission \(scenName)")
    }
}

/// Start the next campaign mission
func startNextMission() -> Bool {
    guard campaignState.isActive && !campaignState.isComplete else { return false }

    let scenName = campaignState.scenarioName

    // Check if the scenario exists
    guard mixManager.contains("\(scenName).INI") else {
        // Try alternate variants
        for variant in ["EA", "EB", "EC"] {
            let prefix = campaignState.currentFaction == "GDI" ? "SCG" : "SCB"
            let num = String(format: "%02d", campaignState.currentMission)
            let altName = "\(prefix)\(num)\(variant)"
            if mixManager.contains("\(altName).INI") {
                campaignState.currentVariant = variant
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

    // Apply carry-over credits
    sidebarCredits += campaignState.carryOverCredits

    // Reset score for new mission
    missionScore.reset()
    lastTickTime = 0
    tickAccumulator = 0

    print("Campaign: Started mission \(scenName) with \(campaignState.carryOverCredits) carry-over credits")
    return true
}

// MARK: - Helper Functions

/// Current scenario name tracking
var currentScenarioName: String? = nil

func objectKindString(_ kind: ObjectKind) -> String {
    switch kind {
    case .unit: return "unit"
    case .infantry: return "infantry"
    case .structure: return "structure"
    }
}

func objectKindFromString(_ str: String) -> ObjectKind {
    switch str.lowercased() {
    case "unit": return .unit
    case "infantry": return .infantry
    case "structure": return .structure
    default: return .unit
    }
}

// MARK: - Mission extensions

extension Mission {
    var saveName: String {
        switch self {
        case .sleep: return "Sleep"
        case .attack: return "Attack"
        case .move: return "Move"
        case .guard_: return "Guard"
        case .guardArea: return "Area Guard"
        case .harvest: return "Harvest"
        case .return_: return "Return"
        case .stop: return "Stop"
        case .ambush: return "Ambush"
        case .hunt: return "Hunt"
        case .timedHunt: return "Timed Hunt"
        case .enter: return "Enter"
        case .capture: return "Capture"
        case .retreat: return "Retreat"
        case .unload: return "Unload"
        case .construction: return "Construction"
        case .deconstruction: return "Deconstruction"
        case .repair: return "Repair"
        case .selling: return "Selling"
        case .missile: return "Missile"
        case .sticky: return "Sticky"
        }
    }
}

// MARK: - Campaign Briefing Text

/// Get briefing text for a scenario
func getBriefingText(scenarioName: String) -> String? {
    guard let iniData = mixManager.retrieve("\(scenarioName).INI") else { return nil }
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

// MARK: - Score Screen Data

struct ScoreScreenData {
    let scenarioName: String
    let won: Bool
    let score: Int
    let stars: Int
    let gdiKills: Int
    let nodKills: Int
    let civKills: Int
    let gdiBuildings: Int
    let nodBuildings: Int
    let creditsHarvested: Int
    let elapsedTime: String
    let briefing: String?
}

/// Generate score screen data for the completed mission
func generateScoreScreen(won: Bool) -> ScoreScreenData {
    let ticks = missionScore.elapsedTicks
    let minutes = ticks / (15 * 60)
    let seconds = (ticks / 15) % 60
    let timeStr = String(format: "%d:%02d", minutes, seconds)

    return ScoreScreenData(
        scenarioName: currentScenarioName ?? "Unknown",
        won: won,
        score: missionScore.totalScore,
        stars: missionScore.starRating,
        gdiKills: missionScore.gdiUnitsKilled,
        nodKills: missionScore.nodUnitsKilled,
        civKills: missionScore.civUnitsKilled,
        gdiBuildings: missionScore.gdiBuildingsKilled,
        nodBuildings: missionScore.nodBuildingsKilled,
        creditsHarvested: missionScore.creditsHarvested,
        elapsedTime: timeStr,
        briefing: getBriefingText(scenarioName: currentScenarioName ?? "")
    )
}
