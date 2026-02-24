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

// MARK: - Campaign Manager

class CampaignManager {
    var state = CampaignState()
    var score = MissionScore()
    var currentScenarioName: String? = nil

    /// Track a kill for scoring purposes
    func trackKill(victimHouse: House, victimKind: ObjectKind) {
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
    func handleWin() {
        guard state.isActive else { return }

        print("Campaign: Mission \(state.scenarioName) WON!")
        audioManager.speak(.accomplished)

        // Save carry-over credits
        state.carryOverCredits = session.sidebarCredits * state.carryOverPercent / 100

        // Record score
        score.elapsedTicks = session.world?.tickCount ?? 0

        // Advance campaign
        state.advanceMission()

        if state.isComplete {
            print("Campaign: \(state.currentFaction) campaign COMPLETE!")
        } else {
            print("Campaign: Next mission is \(state.scenarioName)")
        }
    }

    /// Handle mission loss
    func handleLoss() {
        guard state.isActive else { return }

        print("Campaign: Mission \(state.scenarioName) LOST!")
        audioManager.speak(.fail)
    }

    /// Restart current mission
    func restart() {
        guard let scenName = currentScenarioName else { return }

        // Reload the scenario
        if let scenario = loadScenario(scenName + ".INI", from: mixManager) {
            scenarioData = scenario
            initGameWorld(scenario: scenario, scenarioName: scenName)
            score.reset()
            session.lastTickTime = 0
            session.tickAccumulator = 0
            print("Campaign: Restarted mission \(scenName)")
        }
    }

    /// Start the next campaign mission
    func startNextMission() -> Bool {
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

        // Set credits from scenario INI (+ carry-over from previous mission)
        session.sidebarCredits = scenario.credits + state.carryOverCredits
        session.displayedCredits = session.sidebarCredits

        // Set build level from scenario INI
        session.scenarioBuildLevel = scenario.buildLevel

        // Reset score for new mission
        score.reset()
        session.lastTickTime = 0
        session.tickAccumulator = 0

        print("Campaign: Started mission \(scenName) with \(state.carryOverCredits) carry-over credits")
        return true
    }

    /// Get briefing text for a scenario
    func briefingText() -> String? {
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
    func briefingText(scenarioName: String) -> String? {
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
    func scoreScreen(won: Bool) -> ScoreScreenData {
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

    // --- V2 fields (optional for backward compat with V1 saves) ---

    // Control groups
    var controlGroups: [[Int]]?

    // Map state: tiberium
    var tiberiumCells: [Int]?
    var tiberiumDensity: [SavedTiberiumEntry]?
    var tiberiumScan: Int?
    var isForwardScan: Bool?

    // Map state: smudges
    var smudges: [SavedSmudge]?

    // Map state: fog
    var fogState: [Int]?

    // Production queues
    var unitBuildQueue: SavedProductionQueue?
    var structureBuildQueue: SavedProductionQueue?

    // Super weapon charge state
    var ionCannon: SavedSuperWeapon?
    var airStrike: SavedSuperWeapon?
    var nukeStrike: SavedSuperWeapon?

    // Active teams
    var activeTeams: [SavedActiveTeam]?

    // Scripting state
    var triggerWinState: String?
    var allowWinFlag: Bool?
    var aiTickCounter: Int?
    var scenarioBuildLevel: Int?
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

    // --- V2 fields (optional for backward compat) ---

    // Movement
    var moveTargetX: Double?
    var moveTargetY: Double?
    var movePath: [SavedCell]?
    var navTargetId: Int?
    var group: Int?
    var isAttackMoving: Bool?
    var moveWaypoints: [SavedCell]?

    // Combat
    var attackTarget: Int?
    var suspendedTarget: Int?
    var reloadTimer: Int?
    var lastFireTick: Int?
    var lastDamagedTick: Int?

    // Mission state
    var turretFacing: Int?
    var missionQueue: String?
    var suspendedMission: String?
    var missionStatus: Int?

    // Cargo / transport
    var passengers: [Int]?
    var isALoaner: Bool?

    // Harvesting
    var tiberiumLoad: Int?

    // Infantry
    var fear: UInt8?
    var isProne: Bool?

    // Building
    var isRepairing: Bool?
    var buildUpFrame: Int?
    var buildUpTotalFrames: Int?
    var buildUpDelay: Int?
    var samDeployState: Int?
    var powerOutput: Int?
    var powerDrain: Int?

    // Aircraft
    var isLanding: Bool?
    var isTakingOff: Bool?

    // Flags
    var isInLimbo: Bool?
    var isTethered: Bool?
}

struct SavedCell: Codable {
    let x: Int
    let y: Int
}

struct SavedTrigger: Codable {
    let name: String
    let isActive: Bool
    let data: Int
    let attachCount: Int
}

struct SavedTiberiumEntry: Codable {
    let cell: Int
    let density: Int
}

struct SavedSmudge: Codable {
    let type: String
    let cell: Int
}

struct SavedProductionQueue: Codable {
    var typeName: String?
    var progress: Int?
    var cost: Int?
    var totalTicks: Int?
    var isOnHold: Bool?
}

struct SavedSuperWeapon: Codable {
    var isPresent: Bool
    var isReady: Bool
    var isOneTime: Bool
    var isSuspended: Bool
    var chargeRemaining: Int
    var suspendedTime: Int
}

struct SavedActiveTeam: Codable {
    let typeName: String
    let members: [Int]
    let isMoving: Bool
    let isFullStrength: Bool
    let isUnderStrength: Bool
    let isHasBeen: Bool
    let currentMission: Int
    let isNextMission: Bool
    let centerX: Double
    let centerY: Double
    let target: Int?
    let targetCell: Int?
    let missionTimeout: Int
    let isSuspended: Bool
    let suspendTimer: Int
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
    guard let world = session.world else {
        print("SaveGame: No world to save")
        return false
    }

    let desc = description.isEmpty ? "Save \(slot) - \(session.campaignState.scenarioName)" : description

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
            subCell: obj.subCell,
            // V2 movement
            moveTargetX: obj.moveTargetX,
            moveTargetY: obj.moveTargetY,
            movePath: obj.movePath.isEmpty ? nil : obj.movePath.map { SavedCell(x: $0.cellX, y: $0.cellY) },
            navTargetId: obj.navTargetId,
            group: obj.group >= 0 ? obj.group : nil,
            isAttackMoving: obj.isAttackMoving ? true : nil,
            moveWaypoints: obj.moveWaypoints.isEmpty ? nil : obj.moveWaypoints.map { SavedCell(x: Int($0.x), y: Int($0.y)) },
            // V2 combat
            attackTarget: obj.attackTarget,
            suspendedTarget: obj.suspendedTarget,
            reloadTimer: obj.reloadTimer > 0 ? obj.reloadTimer : nil,
            lastFireTick: obj.lastFireTick > 0 ? obj.lastFireTick : nil,
            lastDamagedTick: obj.lastDamagedTick > 0 ? obj.lastDamagedTick : nil,
            // V2 mission state
            turretFacing: obj.turretFacing != obj.facing ? obj.turretFacing : nil,
            missionQueue: obj.missionQueue?.saveName,
            suspendedMission: obj.suspendedMission?.saveName,
            missionStatus: obj.missionStatus != 0 ? obj.missionStatus : nil,
            // V2 cargo
            passengers: obj.passengers.isEmpty ? nil : obj.passengers,
            isALoaner: obj.isALoaner ? true : nil,
            // V2 harvesting
            tiberiumLoad: obj.tiberiumLoad > 0 ? obj.tiberiumLoad : nil,
            // V2 infantry
            fear: obj.fear > 0 ? obj.fear : nil,
            isProne: obj.isProne ? true : nil,
            // V2 building
            isRepairing: obj.isRepairing ? true : nil,
            buildUpFrame: obj.buildUpFrame >= 0 ? obj.buildUpFrame : nil,
            buildUpTotalFrames: obj.buildUpTotalFrames > 0 ? obj.buildUpTotalFrames : nil,
            buildUpDelay: obj.buildUpDelay > 0 ? obj.buildUpDelay : nil,
            samDeployState: obj.samDeployState > 0 ? obj.samDeployState : nil,
            powerOutput: obj.powerOutput > 0 ? obj.powerOutput : nil,
            powerDrain: obj.powerDrain > 0 ? obj.powerDrain : nil,
            // V2 aircraft
            isLanding: obj.isLanding ? true : nil,
            isTakingOff: obj.isTakingOff ? true : nil,
            // V2 flags
            isInLimbo: obj.isInLimbo ? true : nil,
            isTethered: obj.isTethered ? true : nil
        )
        savedObjects.append(saved)
    }

    // Serialize trigger state
    var savedTriggers: [SavedTrigger] = []
    for trigger in session.gameTriggers {
        savedTriggers.append(SavedTrigger(
            name: trigger.name,
            isActive: trigger.isActive,
            data: trigger.data,
            attachCount: trigger.attachCount
        ))
    }

    // Serialize tiberium density
    let map = world.map
    var tiberiumDensityEntries: [SavedTiberiumEntry] = []
    for (cell, density) in map.tiberiumDensity {
        tiberiumDensityEntries.append(SavedTiberiumEntry(cell: cell, density: density))
    }

    // Serialize smudges
    let savedSmudges = map.smudges.map { SavedSmudge(type: $0.type.rawValue, cell: $0.cell) }

    // Serialize fog state as compact int array (0=unexplored, 1=explored, 2=visible)
    let fogInts = map.fogState.map { fog -> Int in
        switch fog {
        case .unexplored: return 0
        case .explored: return 1
        case .visible: return 2
        }
    }

    // Serialize production queues
    let savedUnitQueue = serializeProductionQueue(session.unitBuildQueue)
    let savedStructQueue = serializeProductionQueue(session.structureBuildQueue)

    // Serialize super weapons
    let savedIonCannon = serializeSuperWeapon(session.playerIonCannon)
    let savedAirStrike = serializeSuperWeapon(session.playerAirStrike)
    let savedNukeStrike = serializeSuperWeapon(session.playerNukeStrike)

    // Serialize active teams
    var savedTeams: [SavedActiveTeam] = []
    for team in session.activeTeams {
        savedTeams.append(SavedActiveTeam(
            typeName: team.type.name,
            members: team.members,
            isMoving: team.isMoving,
            isFullStrength: team.isFullStrength,
            isUnderStrength: team.isUnderStrength,
            isHasBeen: team.isHasBeen,
            currentMission: team.currentMission,
            isNextMission: team.isNextMission,
            centerX: team.centerX,
            centerY: team.centerY,
            target: team.target,
            targetCell: team.targetCell,
            missionTimeout: team.missionTimeout,
            isSuspended: team.isSuspended,
            suspendTimer: team.suspendTimer
        ))
    }

    // Serialize win state
    let winStateStr: String
    switch session.triggerWinState {
    case .playing: winStateStr = "playing"
    case .won: winStateStr = "won"
    case .lost: winStateStr = "lost"
    }

    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    var saveData = SaveGameData(
        version: 2,
        description: desc,
        saveDate: Date(),
        scenarioName: session.currentScenarioName ?? session.campaignState.scenarioName,
        tickCount: world.tickCount,
        playerHouse: world.playerHouse.rawValue,
        theater: world.theater.rawValue,
        mapBoundsX: bounds.x,
        mapBoundsY: bounds.y,
        mapBoundsW: bounds.width,
        mapBoundsH: bounds.height,
        credits: session.sidebarCredits,
        objects: savedObjects,
        campaignFaction: session.campaignState.currentFaction,
        campaignMission: session.campaignState.currentMission,
        campaignVariant: session.campaignState.currentVariant,
        campaignDifficulty: session.campaignState.difficulty,
        carryOverCredits: session.campaignState.carryOverCredits,
        scoreGDIKills: session.missionScore.gdiUnitsKilled,
        scoreNodKills: session.missionScore.nodUnitsKilled,
        scoreCivKills: session.missionScore.civUnitsKilled,
        scoreGDIBuildings: session.missionScore.gdiBuildingsKilled,
        scoreNodBuildings: session.missionScore.nodBuildingsKilled,
        scoreCivBuildings: session.missionScore.civBuildingsKilled,
        scoreCreditsHarvested: session.missionScore.creditsHarvested,
        scoreElapsedTicks: session.missionScore.elapsedTicks,
        triggers: savedTriggers,
        cameraX: renderState.gameCameraX,
        cameraY: renderState.gameCameraY
    )
    // V2 fields
    saveData.controlGroups = world.controlGroups
    saveData.tiberiumCells = Array(map.tiberiumCells)
    saveData.tiberiumDensity = tiberiumDensityEntries
    saveData.tiberiumScan = map.tiberiumScan
    saveData.isForwardScan = map.isForwardScan
    saveData.smudges = savedSmudges
    saveData.fogState = fogInts
    saveData.unitBuildQueue = savedUnitQueue
    saveData.structureBuildQueue = savedStructQueue
    saveData.ionCannon = savedIonCannon
    saveData.airStrike = savedAirStrike
    saveData.nukeStrike = savedNukeStrike
    saveData.activeTeams = savedTeams
    saveData.triggerWinState = winStateStr
    saveData.allowWinFlag = session.allowWinFlag
    saveData.aiTickCounter = session.aiTickCounter
    saveData.scenarioBuildLevel = session.scenarioBuildLevel

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

        guard saveData.version >= 1 && saveData.version <= 2 else {
            print("LoadGame: Unsupported save version \(saveData.version)")
            return false
        }
        let isV2 = saveData.version >= 2

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

            // V2 fields
            obj.moveTargetX = saved.moveTargetX
            obj.moveTargetY = saved.moveTargetY
            if let path = saved.movePath {
                obj.movePath = path.map { (cellX: $0.x, cellY: $0.y) }
            }
            obj.navTargetId = saved.navTargetId
            obj.group = saved.group ?? -1
            obj.isAttackMoving = saved.isAttackMoving ?? false
            if let wps = saved.moveWaypoints {
                obj.moveWaypoints = wps.map { (x: Double($0.x), y: Double($0.y)) }
            }
            obj.attackTarget = saved.attackTarget
            obj.suspendedTarget = saved.suspendedTarget
            obj.reloadTimer = saved.reloadTimer ?? 0
            obj.lastFireTick = saved.lastFireTick ?? 0
            obj.lastDamagedTick = saved.lastDamagedTick ?? 0
            if let tf = saved.turretFacing { obj.turretFacing = tf }
            if let mq = saved.missionQueue { obj.missionQueue = Mission.from(mq) }
            if let sm = saved.suspendedMission { obj.suspendedMission = Mission.from(sm) }
            obj.missionStatus = saved.missionStatus ?? 0
            obj.passengers = saved.passengers ?? []
            obj.isALoaner = saved.isALoaner ?? false
            obj.tiberiumLoad = saved.tiberiumLoad ?? 0
            obj.fear = saved.fear ?? 0
            obj.isProne = saved.isProne ?? false
            obj.isRepairing = saved.isRepairing ?? false
            obj.buildUpFrame = saved.buildUpFrame ?? -1
            obj.buildUpTotalFrames = saved.buildUpTotalFrames ?? 0
            obj.buildUpDelay = saved.buildUpDelay ?? 0
            obj.samDeployState = saved.samDeployState ?? 0
            if let po = saved.powerOutput { obj.powerOutput = po }
            if let pd = saved.powerDrain { obj.powerDrain = pd }
            obj.isLanding = saved.isLanding ?? false
            obj.isTakingOff = saved.isTakingOff ?? false
            obj.isInLimbo = saved.isInLimbo ?? false
            obj.isTethered = saved.isTethered ?? false

            world.addObject(obj)
            world.nextObjectId = max(world.nextObjectId, saved.id + 1)
        }

        session.world = world
        session.sidebarCredits = saveData.credits
        renderState.gameCameraX = saveData.cameraX
        renderState.gameCameraY = saveData.cameraY
        session.currentScenarioName = scenName

        // Restore campaign state
        session.campaignState.currentFaction = saveData.campaignFaction
        session.campaignState.currentMission = saveData.campaignMission
        session.campaignState.currentVariant = saveData.campaignVariant
        session.campaignState.difficulty = saveData.campaignDifficulty
        session.campaignState.carryOverCredits = saveData.carryOverCredits
        session.campaignState.isActive = true

        // Restore score
        session.missionScore.gdiUnitsKilled = saveData.scoreGDIKills
        session.missionScore.nodUnitsKilled = saveData.scoreNodKills
        session.missionScore.civUnitsKilled = saveData.scoreCivKills
        session.missionScore.gdiBuildingsKilled = saveData.scoreGDIBuildings
        session.missionScore.nodBuildingsKilled = saveData.scoreNodBuildings
        session.missionScore.civBuildingsKilled = saveData.scoreCivBuildings
        session.missionScore.creditsHarvested = saveData.scoreCreditsHarvested
        session.missionScore.elapsedTicks = saveData.scoreElapsedTicks

        // Restore trigger states
        for savedTrigger in saveData.triggers {
            if let trigger = session.gameTriggers.first(where: { $0.name == savedTrigger.name }) {
                trigger.isActive = savedTrigger.isActive
                trigger.data = savedTrigger.data
                trigger.attachCount = savedTrigger.attachCount
            }
        }

        // Rebuild derived data
        buildPassabilityMap()
        initHouseStates()

        // Restore tiberium state from save or re-init from scenario
        if isV2, let savedTibCells = saveData.tiberiumCells {
            let map = world.map
            map.tiberiumCells = Set(savedTibCells)
            map.tiberiumDensity.removeAll()
            if let densityEntries = saveData.tiberiumDensity {
                for entry in densityEntries {
                    map.tiberiumDensity[entry.cell] = entry.density
                }
            }
            map.tiberiumScan = saveData.tiberiumScan ?? 0
            map.isForwardScan = saveData.isForwardScan ?? true
        } else {
            initTiberiumCells()
        }

        // Restore smudges from save or leave empty
        if isV2, let savedSmudges = saveData.smudges {
            world.map.smudges = savedSmudges.compactMap { entry in
                guard let smType = SmudgeType(rawValue: entry.type) else { return nil }
                return Smudge(type: smType, cell: entry.cell)
            }
        }

        // Restore fog from save or re-init
        if isV2, let savedFog = saveData.fogState, savedFog.count == 4096 {
            world.map.fogState = savedFog.map { val in
                switch val {
                case 2: return FogLevel.visible
                case 1: return FogLevel.explored
                default: return FogLevel.unexplored
                }
            }
        } else {
            initFog()
        }

        // Restore control groups
        if isV2, let groups = saveData.controlGroups, groups.count == 10 {
            world.controlGroups = groups
        }

        // Restore production queues
        if isV2 {
            restoreProductionQueue(session.unitBuildQueue, from: saveData.unitBuildQueue)
            restoreProductionQueue(session.structureBuildQueue, from: saveData.structureBuildQueue)
        }

        // Restore super weapons
        if isV2 {
            if let sw = saveData.ionCannon { restoreSuperWeapon(session.playerIonCannon, from: sw) }
            else { resetSuperWeapons() }
            if let sw = saveData.airStrike { restoreSuperWeapon(session.playerAirStrike, from: sw) }
            if let sw = saveData.nukeStrike { restoreSuperWeapon(session.playerNukeStrike, from: sw) }
        } else {
            resetSuperWeapons()
        }

        // Restore active teams
        if isV2, let savedTeams = saveData.activeTeams {
            session.activeTeams.removeAll()
            for st in savedTeams {
                guard let type = session.teamTypes.first(where: { $0.name == st.typeName }) else { continue }
                let team = ActiveTeam(type: type)
                team.members = st.members
                team.isMoving = st.isMoving
                team.isFullStrength = st.isFullStrength
                team.isUnderStrength = st.isUnderStrength
                team.isHasBeen = st.isHasBeen
                team.currentMission = st.currentMission
                team.isNextMission = st.isNextMission
                team.centerX = st.centerX
                team.centerY = st.centerY
                team.target = st.target
                team.targetCell = st.targetCell
                team.missionTimeout = st.missionTimeout
                team.isSuspended = st.isSuspended
                team.suspendTimer = st.suspendTimer
                session.activeTeams.append(team)
            }
        }

        // Restore scripting state
        if isV2 {
            switch saveData.triggerWinState {
            case "won": session.triggerWinState = .won
            case "lost": session.triggerWinState = .lost
            default: session.triggerWinState = .playing
            }
            session.allowWinFlag = saveData.allowWinFlag ?? false
            session.aiTickCounter = saveData.aiTickCounter ?? 0
            session.scenarioBuildLevel = saveData.scenarioBuildLevel ?? 99
        }

        // Reload palette for theater
        let palName: String
        switch world.theater {
        case .temperate: palName = "TEMPERAT.PAL"
        case .desert: palName = "DESERT.PAL"
        case .winter: palName = "WINTER.PAL"
        }
        renderState.gamePalette = loadPalette(palName)

        print("LoadGame: Loaded slot \(slot) v\(saveData.version) - '\(saveData.description)' (\(world.objects.count) objects)")
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

// MARK: - Serialization Helpers

func serializeProductionQueue(_ queue: ProductionQueue) -> SavedProductionQueue? {
    guard let item = queue.item else { return nil }
    return SavedProductionQueue(
        typeName: item.typeName,
        progress: item.progress,
        cost: item.cost,
        totalTicks: item.totalTicks,
        isOnHold: queue.isOnHold
    )
}

func restoreProductionQueue(_ queue: ProductionQueue, from saved: SavedProductionQueue?) {
    guard let saved = saved, let typeName = saved.typeName else {
        queue.clear()
        return
    }
    queue.item = (
        typeName: typeName,
        progress: saved.progress ?? 0,
        cost: saved.cost ?? 0,
        totalTicks: saved.totalTicks ?? 0
    )
    queue.isOnHold = saved.isOnHold ?? false
}

func serializeSuperWeapon(_ weapon: SuperWeapon) -> SavedSuperWeapon {
    return SavedSuperWeapon(
        isPresent: weapon.isPresent,
        isReady: weapon.isReady,
        isOneTime: weapon.isOneTime,
        isSuspended: weapon.isSuspended,
        chargeRemaining: weapon.chargeRemaining,
        suspendedTime: weapon.suspendedTime
    )
}

func restoreSuperWeapon(_ weapon: SuperWeapon, from saved: SavedSuperWeapon) {
    weapon.isPresent = saved.isPresent
    weapon.isReady = saved.isReady
    weapon.isOneTime = saved.isOneTime
    weapon.isSuspended = saved.isSuspended
    weapon.chargeRemaining = saved.chargeRemaining
    weapon.suspendedTime = saved.suspendedTime
}

// MARK: - Helper Functions

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
        case .sabotage: return "Sabotage"
        }
    }
}
