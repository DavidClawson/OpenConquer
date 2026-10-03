import Foundation

// MARK: - Campaign Save
// Serializes the live session into SaveGameData and writes it to a slot.

// MARK: - Save Game

package func saveGame(slot: Int, description: String = "") -> Bool {
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
            isTethered: obj.isTethered ? true : nil,
            // Rally point
            rallyPointX: obj.rallyPointX,
            rallyPointY: obj.rallyPointY,
            // Patrol
            patrolWaypoints: obj.patrolWaypoints.isEmpty ? nil : obj.patrolWaypoints.map { SavedCell(x: Int($0.x), y: Int($0.y)) },
            patrolIndex: obj.patrolIndex > 0 ? obj.patrolIndex : nil
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

    // Serialize tiberium density + variant
    let map = world.map
    var tiberiumDensityEntries: [SavedTiberiumEntry] = []
    for (cell, density) in map.tiberiumDensity {
        tiberiumDensityEntries.append(SavedTiberiumEntry(
            cell: cell, density: density, variant: map.tiberiumVariant[cell]
        ))
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
        randomSeed: world.randomSeed,
        rngState: gameRng.state,
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
        cameraX: saveView.current().cameraX,
        cameraY: saveView.current().cameraY
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

// MARK: - Serialization Helpers

package func serializeProductionQueue(_ queue: ProductionQueue) -> SavedProductionQueue? {
    guard let item = queue.item else { return nil }
    return SavedProductionQueue(
        typeName: item.typeName,
        progress: item.progress,
        cost: item.cost,
        totalTicks: item.totalTicks,
        isOnHold: queue.isOnHold
    )
}

package func restoreProductionQueue(_ queue: ProductionQueue, from saved: SavedProductionQueue?) {
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

package func serializeSuperWeapon(_ weapon: SuperWeapon) -> SavedSuperWeapon {
    return SavedSuperWeapon(
        isPresent: weapon.isPresent,
        isReady: weapon.isReady,
        isOneTime: weapon.isOneTime,
        isSuspended: weapon.isSuspended,
        chargeRemaining: weapon.chargeRemaining,
        suspendedTime: weapon.suspendedTime
    )
}

package func restoreSuperWeapon(_ weapon: SuperWeapon, from saved: SavedSuperWeapon) {
    weapon.isPresent = saved.isPresent
    weapon.isReady = saved.isReady
    weapon.isOneTime = saved.isOneTime
    weapon.isSuspended = saved.isSuspended
    weapon.chargeRemaining = saved.chargeRemaining
    weapon.suspendedTime = saved.suspendedTime
}
