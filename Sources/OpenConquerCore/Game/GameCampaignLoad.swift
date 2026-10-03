import Foundation
import OpenConquerAssets

// MARK: - Campaign Load
// Restores a session from a save slot, plus slot listing, deletion and quick save/load.

// MARK: - Load Game

package func loadGame(slot: Int) -> Bool {
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
        // Restore deterministic RNG (older saves lack it — reseed from name).
        world.randomSeed = saveData.randomSeed ?? stableSeed(saveData.scenarioName)
        gameRng = GameRandom(seed: saveData.rngState ?? world.randomSeed)
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
            obj.rallyPointX = saved.rallyPointX
            obj.rallyPointY = saved.rallyPointY
            if let pwps = saved.patrolWaypoints {
                obj.patrolWaypoints = pwps.map { (x: Double($0.x), y: Double($0.y)) }
            }
            obj.patrolIndex = saved.patrolIndex ?? 0

            world.addObject(obj)
            world.nextObjectId = max(world.nextObjectId, saved.id + 1)
        }

        session.world = world
        session.sidebarCredits = saveData.credits
        var view = saveView.current()
        view.cameraX = saveData.cameraX
        view.cameraY = saveData.cameraY
        saveView.restore(view)
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
            map.tiberiumVariant.removeAll()
            if let densityEntries = saveData.tiberiumDensity {
                for entry in densityEntries {
                    map.tiberiumDensity[entry.cell] = entry.density
                    // Older saves don't have variant — keep the legacy mapping
                    // (variant = density) so visuals stay continuous, then new
                    // growth/spread will populate fresh variants.
                    map.tiberiumVariant[entry.cell] = entry.variant ?? entry.density
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

        print("LoadGame: Loaded slot \(slot) v\(saveData.version) - '\(saveData.description)' (\(world.objects.count) objects)")
        return true
    } catch {
        print("LoadGame: Failed to load slot \(slot): \(error)")
        return false
    }
}

// MARK: - Save Slot Info

package struct SaveSlotInfo {
    package let slot: Int
    package let description: String
    package let date: Date
    package let scenarioName: String
    package let exists: Bool
}

/// List available save slots
package func listSaveSlots() -> [SaveSlotInfo] {
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
package func deleteSaveSlot(_ slot: Int) {
    let filename = "save_\(slot).json"
    let fileURL = saveDirectory.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: fileURL)
}

// MARK: - Quick Save/Load

package func quickSave() -> Bool {
    return saveGame(slot: 0, description: "Quick Save")
}

package func quickLoad() -> Bool {
    return loadGame(slot: 0)
}
