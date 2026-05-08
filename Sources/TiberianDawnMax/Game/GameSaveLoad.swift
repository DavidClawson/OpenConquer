import Foundation

// MARK: - Mid-Mission Save/Load System
// Captures and restores full in-progress mission state, complementing the
// between-mission campaign save (GameCampaign.swift).  Serialization patterns
// are deliberately compatible with the existing SavedObject / SavedCell /
// SavedTrigger structs so the two systems share vocabulary.

// MARK: - Save Directory

private let missionSaveDirectory: URL = {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TiberianDawnMax/saves")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}()

// MARK: - Codable Data Structures

/// Top-level container for a full mid-mission snapshot.
struct MissionSaveData: Codable {
    // Header / metadata
    let version: Int                    // Format version (start at 1)
    let saveTimestamp: Date
    let missionName: String             // e.g. "SCG01EA"
    let slotDescription: String         // Human-readable label

    // World-level state
    let tickCount: Int
    let playerHouse: String             // House.rawValue
    let theater: String                 // TheaterType.rawValue
    let mapBoundsX: Int
    let mapBoundsY: Int
    let mapBoundsW: Int
    let mapBoundsH: Int
    let nextObjectId: Int

    // Camera
    let cameraX: Double
    let cameraY: Double
    let zoomLevel: Double

    // Credits / economy
    let sidebarCredits: Int
    let displayedCredits: Int

    // Scenario metadata
    let scenarioBuildLevel: Int

    // Campaign state
    let campaignFaction: String
    let campaignMission: Int
    let campaignVariant: String
    let campaignDifficulty: Int
    let carryOverCredits: Int
    let campaignIsActive: Bool

    // Score tracking
    let scoreGDIKills: Int
    let scoreNodKills: Int
    let scoreCivKills: Int
    let scoreGDIBuildings: Int
    let scoreNodBuildings: Int
    let scoreCivBuildings: Int
    let scoreCreditsHarvested: Int
    let scoreElapsedTicks: Int

    // Win/lose state
    let triggerWinState: String         // "playing", "won", "lost"
    let allowWinFlag: Bool
    let aiTickCounter: Int

    // Control groups (10 groups, each an array of object IDs)
    let controlGroups: [[Int]]

    // Objects
    let objects: [MidMissionSavedObject]

    // Map: tiberium
    let tiberiumCells: [Int]
    let tiberiumDensity: [SavedTiberiumEntry]
    let tiberiumScan: Int
    let isForwardScan: Bool

    // Map: smudges
    let smudges: [SavedSmudge]

    // Map: fog of war (4096 ints: 0=unexplored, 1=explored, 2=visible)
    let fogState: [Int]

    // Triggers
    let triggers: [MidMissionSavedTrigger]

    // Production queues (player)
    let unitBuildQueue: SavedProductionQueue?
    let structureBuildQueue: SavedProductionQueue?

    // Super weapons (player)
    let ionCannon: SavedSuperWeapon
    let airStrike: SavedSuperWeapon
    let nukeStrike: SavedSuperWeapon

    // Active teams
    let activeTeams: [SavedActiveTeam]

    // Projectiles in flight
    let projectiles: [MidMissionSavedProjectile]

    // Active animations
    let animations: [MidMissionSavedAnimation]

    // House states (keyed by House.rawValue)
    let houseStates: [MidMissionSavedHouse]

    // Pending reinforcements
    let pendingReinforcements: [MidMissionSavedReinforcement]

    // Crate state
    let crates: [MidMissionSavedCrate]
    let nextCrateId: Int
    let nextCrateSpawnTick: Int
    let crateSpawnedCount: Int
}

// MARK: - Object Snapshot

/// Extended object snapshot that captures ALL runtime state.
/// Mirrors SavedObject from GameCampaign.swift but is self-contained.
struct MidMissionSavedObject: Codable {
    // Identity
    let id: Int
    let typeName: String
    let house: String
    let kind: String                    // "unit", "infantry", "structure"

    // Position
    let worldX: Double
    let worldY: Double
    let facing: Int
    let turretFacing: Int
    let strength: Int

    // Mission
    let mission: String
    let missionQueue: String?
    let suspendedMission: String?
    let missionStatus: Int
    let isSelected: Bool

    // Movement
    let speed: Double
    let moveTargetX: Double?
    let moveTargetY: Double?
    let movePath: [SavedCell]?
    let navTargetId: Int?
    let group: Int
    let isAttackMoving: Bool
    let moveWaypoints: [SavedCell]?

    // Patrol
    let patrolWaypoints: [SavedCell]?
    let patrolIndex: Int

    // Combat
    let attackTarget: Int?
    let suspendedTarget: Int?
    let reloadTimer: Int
    let lastFireTick: Int
    let lastDamagedTick: Int
    let ammo: Int
    let killCount: Int

    // Harvesting
    let tiberiumLoad: Int

    // Infantry
    let subCell: Int
    let fear: UInt8
    let isProne: Bool

    // Building
    let isRepairing: Bool
    let rallyPointX: Double?
    let rallyPointY: Double?
    let powerOutput: Int
    let powerDrain: Int
    let buildUpFrame: Int
    let buildUpTotalFrames: Int
    let buildUpDelay: Int
    let samDeployState: Int

    // Aircraft
    let isAircraft: Bool
    let altitude: Int
    let isLanding: Bool
    let isTakingOff: Bool
    let landingPadId: Int?

    // Cargo
    let passengers: [Int]
    let isALoaner: Bool

    // Flags
    let isInLimbo: Bool
    let isTethered: Bool

    // Trigger
    let triggerName: String?

    // Crate buff
    let crateBuffSpeed: Double
    let crateBuffFirepower: Double
    let crateBuffExpiration: Int
}

// MARK: - Trigger Snapshot

struct MidMissionSavedTrigger: Codable {
    let name: String
    let isActive: Bool
    let data: Int
    let attachCount: Int
    let firedForHouses: [String]        // House rawValues
}

// MARK: - Projectile Snapshot

struct MidMissionSavedProjectile: Codable {
    let id: Int
    let bulletType: Int                 // BulletType.rawValue (Int)
    let worldX: Double
    let worldY: Double
    let targetX: Double
    let targetY: Double
    let targetId: Int?
    let facing: Int
    let damage: Int
    let warhead: Int                    // WarheadType.rawValue (Int)
    let sourceHouse: String
    let sourceObjectId: Int?
    let sourceX: Double
    let sourceY: Double
    let age: Int
    let speed: Double
}

// MARK: - Animation Snapshot

struct MidMissionSavedAnimation: Codable {
    let type: String                    // GameAnimType.rawValue
    let worldX: Double
    let worldY: Double
    let currentFrame: Int
    let loopsRemaining: Int
    let delayCounter: Int
    let attachedToId: Int?
}

// MARK: - House State Snapshot

struct MidMissionSavedHouse: Codable {
    let house: String                   // House.rawValue
    let credits: Int
    let tiberium: Int
    let capacity: Int
    let isHuman: Bool
    let powerOutput: Int
    let powerDrain: Int
    let unitsKilled: Int
    let unitsLost: Int
    let buildingsKilled: Int
    let buildingsLost: Int
    let isAlerted: Bool
    let alertTimer: Int
    let productionEnabled: Bool

    // AI production queues
    let aiUnitQueue: SavedProductionQueue?
    let aiInfantryQueue: SavedProductionQueue?
    let aiStructureQueue: SavedProductionQueue?

    // AI base building
    let aiBuildCycleCount: Int
    let aiLastAttackTick: Int
    let aiLastBuildCheckTick: Int
}

// MARK: - Pending Reinforcement Snapshot

struct MidMissionSavedReinforcement: Codable {
    let transportId: Int
    let dropCell: Int
    let house: String
    let state: String                   // "flyingIn", "unloading", "flyingOut"
}

// MARK: - Crate Snapshot

struct MidMissionSavedCrate: Codable {
    let id: Int
    let cell: Int
    let worldX: Double
    let worldY: Double
    let crateType: String               // CrateType case name
    let isCollected: Bool
}

// MARK: - Save Function

/// Save the current mid-mission state to a numbered slot.
/// Files are written to ~/Library/Application Support/TiberianDawnMax/saves/mission_save_<slot>.json
func saveMission(slot: Int, description: String? = nil) -> Bool {
    guard let world = session.world else {
        print("MissionSave: No active world to save")
        return false
    }

    let scenName = session.currentScenarioName ?? session.campaignState.scenarioName
    let desc = description ?? "Mission Save \(slot) - \(scenName)"

    // --- Serialize objects ---
    var savedObjects: [MidMissionSavedObject] = []
    for obj in world.objects {
        let so = MidMissionSavedObject(
            id: obj.id,
            typeName: obj.typeName,
            house: obj.house.rawValue,
            kind: objectKindString(obj.kind),
            worldX: obj.worldX,
            worldY: obj.worldY,
            facing: obj.facing,
            turretFacing: obj.turretFacing,
            strength: obj.strength,
            mission: obj.mission.saveName,
            missionQueue: obj.missionQueue?.saveName,
            suspendedMission: obj.suspendedMission?.saveName,
            missionStatus: obj.missionStatus,
            isSelected: obj.isSelected,
            speed: obj.speed,
            moveTargetX: obj.moveTargetX,
            moveTargetY: obj.moveTargetY,
            movePath: obj.movePath.isEmpty ? nil : obj.movePath.map { SavedCell(x: $0.cellX, y: $0.cellY) },
            navTargetId: obj.navTargetId,
            group: obj.group,
            isAttackMoving: obj.isAttackMoving,
            moveWaypoints: obj.moveWaypoints.isEmpty ? nil : obj.moveWaypoints.map { SavedCell(x: Int($0.x), y: Int($0.y)) },
            patrolWaypoints: obj.patrolWaypoints.isEmpty ? nil : obj.patrolWaypoints.map { SavedCell(x: Int($0.x), y: Int($0.y)) },
            patrolIndex: obj.patrolIndex,
            attackTarget: obj.attackTarget,
            suspendedTarget: obj.suspendedTarget,
            reloadTimer: obj.reloadTimer,
            lastFireTick: obj.lastFireTick,
            lastDamagedTick: obj.lastDamagedTick,
            ammo: obj.ammo,
            killCount: obj.killCount,
            tiberiumLoad: obj.tiberiumLoad,
            subCell: obj.subCell,
            fear: obj.fear,
            isProne: obj.isProne,
            isRepairing: obj.isRepairing,
            rallyPointX: obj.rallyPointX,
            rallyPointY: obj.rallyPointY,
            powerOutput: obj.powerOutput,
            powerDrain: obj.powerDrain,
            buildUpFrame: obj.buildUpFrame,
            buildUpTotalFrames: obj.buildUpTotalFrames,
            buildUpDelay: obj.buildUpDelay,
            samDeployState: obj.samDeployState,
            isAircraft: obj.isAircraft,
            altitude: obj.altitude,
            isLanding: obj.isLanding,
            isTakingOff: obj.isTakingOff,
            landingPadId: obj.landingPadId,
            passengers: obj.passengers,
            isALoaner: obj.isALoaner,
            isInLimbo: obj.isInLimbo,
            isTethered: obj.isTethered,
            triggerName: obj.triggerName,
            crateBuffSpeed: obj.crateBuff.speedMultiplier,
            crateBuffFirepower: obj.crateBuff.firepowerMultiplier,
            crateBuffExpiration: obj.crateBuff.expirationTick
        )
        savedObjects.append(so)
    }

    // --- Serialize triggers ---
    var savedTriggers: [MidMissionSavedTrigger] = []
    for trigger in session.gameTriggers {
        savedTriggers.append(MidMissionSavedTrigger(
            name: trigger.name,
            isActive: trigger.isActive,
            data: trigger.data,
            attachCount: trigger.attachCount,
            firedForHouses: trigger.firedForHouses.map { $0.rawValue }
        ))
    }

    // --- Serialize map state ---
    let map = world.map
    let tibDensity = map.tiberiumDensity.map {
        SavedTiberiumEntry(cell: $0.key, density: $0.value, variant: map.tiberiumVariant[$0.key])
    }
    let savedSmudges = map.smudges.map { SavedSmudge(type: $0.type.rawValue, cell: $0.cell) }
    let fogInts = map.fogState.map { fog -> Int in
        switch fog {
        case .unexplored: return 0
        case .explored: return 1
        case .visible: return 2
        }
    }

    // --- Serialize production queues ---
    let savedUnitQueue = serializeProductionQueue(session.unitBuildQueue)
    let savedStructQueue = serializeProductionQueue(session.structureBuildQueue)

    // --- Serialize super weapons ---
    let savedIon = serializeSuperWeapon(session.playerIonCannon)
    let savedAir = serializeSuperWeapon(session.playerAirStrike)
    let savedNuke = serializeSuperWeapon(session.playerNukeStrike)

    // --- Serialize active teams ---
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

    // --- Serialize projectiles ---
    var savedProjectiles: [MidMissionSavedProjectile] = []
    for proj in session.activeProjectiles {
        savedProjectiles.append(MidMissionSavedProjectile(
            id: proj.id,
            bulletType: proj.bulletType.rawValue,    // Int
            worldX: proj.worldX,
            worldY: proj.worldY,
            targetX: proj.targetX,
            targetY: proj.targetY,
            targetId: proj.targetId,
            facing: proj.facing,
            damage: proj.damage,
            warhead: proj.warhead.rawValue,          // Int
            sourceHouse: proj.sourceHouse.rawValue,
            sourceObjectId: proj.sourceObjectId,
            sourceX: proj.sourceX,
            sourceY: proj.sourceY,
            age: proj.age,
            speed: proj.speed
        ))
    }

    // --- Serialize animations ---
    var savedAnims: [MidMissionSavedAnimation] = []
    for anim in session.activeAnimations {
        savedAnims.append(MidMissionSavedAnimation(
            type: anim.type.rawValue,
            worldX: anim.worldX,
            worldY: anim.worldY,
            currentFrame: anim.currentFrame,
            loopsRemaining: anim.loopsRemaining,
            delayCounter: anim.delayCounter,
            attachedToId: anim.attachedToId
        ))
    }

    // --- Serialize house states ---
    var savedHouses: [MidMissionSavedHouse] = []
    for (house, state) in session.houseStates {
        savedHouses.append(MidMissionSavedHouse(
            house: house.rawValue,
            credits: state.credits,
            tiberium: state.tiberium,
            capacity: state.capacity,
            isHuman: state.isHuman,
            powerOutput: state.powerOutput,
            powerDrain: state.powerDrain,
            unitsKilled: state.unitsKilled,
            unitsLost: state.unitsLost,
            buildingsKilled: state.buildingsKilled,
            buildingsLost: state.buildingsLost,
            isAlerted: state.isAlerted,
            alertTimer: state.alertTimer,
            productionEnabled: state.productionEnabled,
            aiUnitQueue: serializeProductionQueue(state.aiUnitQueue),
            aiInfantryQueue: serializeProductionQueue(state.aiInfantryQueue),
            aiStructureQueue: serializeProductionQueue(state.aiStructureQueue),
            aiBuildCycleCount: state.aiBuildCycleCount,
            aiLastAttackTick: state.aiLastAttackTick,
            aiLastBuildCheckTick: state.aiLastBuildCheckTick
        ))
    }

    // --- Serialize pending reinforcements ---
    var savedReinforcements: [MidMissionSavedReinforcement] = []
    for r in session.pendingReinforcements {
        let stateStr: String
        switch r.state {
        case .flyingIn: stateStr = "flyingIn"
        case .unloading: stateStr = "unloading"
        case .flyingOut: stateStr = "flyingOut"
        }
        savedReinforcements.append(MidMissionSavedReinforcement(
            transportId: r.transportId,
            dropCell: r.dropCell,
            house: r.house.rawValue,
            state: stateStr
        ))
    }

    // --- Serialize crates ---
    var savedCrates: [MidMissionSavedCrate] = []
    for crate in world.crateState.crates {
        savedCrates.append(MidMissionSavedCrate(
            id: crate.id,
            cell: crate.cell,
            worldX: crate.worldX,
            worldY: crate.worldY,
            crateType: crateTypeToString(crate.crateType),
            isCollected: crate.isCollected
        ))
    }

    // --- Win state ---
    let winStateStr: String
    switch session.triggerWinState {
    case .playing: winStateStr = "playing"
    case .won: winStateStr = "won"
    case .lost: winStateStr = "lost"
    }

    let bounds = world.mapBounds ?? MapBounds(x: 0, y: 0, width: 64, height: 64)

    let saveData = MissionSaveData(
        version: 1,
        saveTimestamp: Date(),
        missionName: scenName,
        slotDescription: desc,
        tickCount: world.tickCount,
        playerHouse: world.playerHouse.rawValue,
        theater: world.theater.rawValue,
        mapBoundsX: bounds.x,
        mapBoundsY: bounds.y,
        mapBoundsW: bounds.width,
        mapBoundsH: bounds.height,
        nextObjectId: world.nextObjectId,
        cameraX: renderState.gameCameraX,
        cameraY: renderState.gameCameraY,
        zoomLevel: renderState.gameZoomLevel,
        sidebarCredits: session.sidebarCredits,
        displayedCredits: session.displayedCredits,
        scenarioBuildLevel: session.scenarioBuildLevel,
        campaignFaction: session.campaignState.currentFaction,
        campaignMission: session.campaignState.currentMission,
        campaignVariant: session.campaignState.currentVariant,
        campaignDifficulty: session.campaignState.difficulty,
        carryOverCredits: session.campaignState.carryOverCredits,
        campaignIsActive: session.campaignState.isActive,
        scoreGDIKills: session.missionScore.gdiUnitsKilled,
        scoreNodKills: session.missionScore.nodUnitsKilled,
        scoreCivKills: session.missionScore.civUnitsKilled,
        scoreGDIBuildings: session.missionScore.gdiBuildingsKilled,
        scoreNodBuildings: session.missionScore.nodBuildingsKilled,
        scoreCivBuildings: session.missionScore.civBuildingsKilled,
        scoreCreditsHarvested: session.missionScore.creditsHarvested,
        scoreElapsedTicks: session.missionScore.elapsedTicks,
        triggerWinState: winStateStr,
        allowWinFlag: session.allowWinFlag,
        aiTickCounter: session.aiTickCounter,
        controlGroups: world.controlGroups,
        objects: savedObjects,
        tiberiumCells: Array(map.tiberiumCells),
        tiberiumDensity: tibDensity,
        tiberiumScan: map.tiberiumScan,
        isForwardScan: map.isForwardScan,
        smudges: savedSmudges,
        fogState: fogInts,
        triggers: savedTriggers,
        unitBuildQueue: savedUnitQueue,
        structureBuildQueue: savedStructQueue,
        ionCannon: savedIon,
        airStrike: savedAir,
        nukeStrike: savedNuke,
        activeTeams: savedTeams,
        projectiles: savedProjectiles,
        animations: savedAnims,
        houseStates: savedHouses,
        pendingReinforcements: savedReinforcements,
        crates: savedCrates,
        nextCrateId: world.crateState.nextCrateId,
        nextCrateSpawnTick: world.crateState.nextSpawnTick,
        crateSpawnedCount: world.crateState.spawnedCount
    )

    // Write JSON
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(saveData)

        let filename = "mission_save_\(slot).json"
        let fileURL = missionSaveDirectory.appendingPathComponent(filename)
        try jsonData.write(to: fileURL)

        print("MissionSave: Saved slot \(slot) '\(desc)' (\(savedObjects.count) objects, \(jsonData.count) bytes)")
        return true
    } catch {
        print("MissionSave: Failed to save slot \(slot): \(error)")
        return false
    }
}

// MARK: - Load Function

/// Load a mid-mission save from the given slot, fully restoring world state.
/// Returns true on success, false on failure.
@discardableResult
func loadMission(slot: Int) -> Bool {
    let filename = "mission_save_\(slot).json"
    let fileURL = missionSaveDirectory.appendingPathComponent(filename)

    do {
        let jsonData = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let save = try decoder.decode(MissionSaveData.self, from: jsonData)

        guard save.version == 1 else {
            print("MissionLoad: Unsupported save version \(save.version)")
            return false
        }

        // Load the scenario INI so terrain, overlays, cell triggers, etc. are present
        let scenName = save.missionName
        guard let scenario = loadScenario(scenName + ".INI", from: mixManager) else {
            print("MissionLoad: Cannot load scenario '\(scenName)'")
            return false
        }
        scenarioData = scenario

        // Also parse triggers and team types from the scenario INI so their
        // definitions are available before we restore runtime state.
        if let iniData = mixManager.retrieve(scenName + ".INI"),
           let iniStr = String(data: Data(iniData), encoding: .ascii) {
            let ini = INIFile(string: iniStr)
            parseTriggers(from: ini)
            parseTeamTypes(from: ini)
        }

        // --- Create world ---
        let world = GameWorld()
        world.theater = TheaterType(rawValue: save.theater) ?? .temperate
        world.mapBounds = MapBounds(
            x: save.mapBoundsX, y: save.mapBoundsY,
            width: save.mapBoundsW, height: save.mapBoundsH
        )
        world.tickCount = save.tickCount
        world.playerHouse = House.from(save.playerHouse)
        world.nextObjectId = save.nextObjectId
        world.controlGroups = save.controlGroups

        // --- Restore objects ---
        for so in save.objects {
            let kind = objectKindFromString(so.kind)
            let obj = GameObject(
                id: so.id,
                typeName: so.typeName,
                house: House.from(so.house),
                kind: kind,
                worldX: so.worldX,
                worldY: so.worldY,
                facing: so.facing,
                strength: so.strength,
                mission: Mission.from(so.mission),
                speed: so.speed,
                subCell: so.subCell
            )

            // Turret
            obj.turretFacing = so.turretFacing

            // Mission state
            if let mq = so.missionQueue { obj.missionQueue = Mission.from(mq) }
            if let sm = so.suspendedMission { obj.suspendedMission = Mission.from(sm) }
            obj.missionStatus = so.missionStatus
            obj.isSelected = so.isSelected

            // Movement
            obj.moveTargetX = so.moveTargetX
            obj.moveTargetY = so.moveTargetY
            if let path = so.movePath {
                obj.movePath = path.map { (cellX: $0.x, cellY: $0.y) }
            }
            obj.navTargetId = so.navTargetId
            obj.group = so.group
            obj.isAttackMoving = so.isAttackMoving
            if let wps = so.moveWaypoints {
                obj.moveWaypoints = wps.map { (x: Double($0.x), y: Double($0.y)) }
            }

            // Patrol
            if let pwps = so.patrolWaypoints {
                obj.patrolWaypoints = pwps.map { (x: Double($0.x), y: Double($0.y)) }
            }
            obj.patrolIndex = so.patrolIndex

            // Combat
            obj.attackTarget = so.attackTarget
            obj.suspendedTarget = so.suspendedTarget
            obj.reloadTimer = so.reloadTimer
            obj.lastFireTick = so.lastFireTick
            obj.lastDamagedTick = so.lastDamagedTick
            obj.ammo = so.ammo
            obj.killCount = so.killCount

            // Harvesting
            obj.tiberiumLoad = so.tiberiumLoad

            // Infantry
            obj.fear = so.fear
            obj.isProne = so.isProne

            // Building
            obj.isRepairing = so.isRepairing
            obj.rallyPointX = so.rallyPointX
            obj.rallyPointY = so.rallyPointY
            obj.powerOutput = so.powerOutput
            obj.powerDrain = so.powerDrain
            obj.buildUpFrame = so.buildUpFrame
            obj.buildUpTotalFrames = so.buildUpTotalFrames
            obj.buildUpDelay = so.buildUpDelay
            obj.samDeployState = so.samDeployState

            // Aircraft
            obj.isAircraft = so.isAircraft
            obj.altitude = so.altitude
            obj.isLanding = so.isLanding
            obj.isTakingOff = so.isTakingOff
            obj.landingPadId = so.landingPadId

            // Cargo
            obj.passengers = so.passengers
            obj.isALoaner = so.isALoaner

            // Flags
            obj.isInLimbo = so.isInLimbo
            obj.isTethered = so.isTethered

            // Trigger
            obj.triggerName = so.triggerName

            // Crate buff
            obj.crateBuff = CrateBuff(
                speedMultiplier: so.crateBuffSpeed,
                firepowerMultiplier: so.crateBuffFirepower,
                expirationTick: so.crateBuffExpiration
            )

            world.addObject(obj)
        }

        // Rebuild the object index for O(1) lookups
        world.rebuildObjectIndex()

        // Assign world to session BEFORE rebuilding derived data
        session.world = world

        // --- Restore map state ---
        let map = world.map
        map.tiberiumCells = Set(save.tiberiumCells)
        map.tiberiumDensity.removeAll()
        map.tiberiumVariant.removeAll()
        for entry in save.tiberiumDensity {
            map.tiberiumDensity[entry.cell] = entry.density
            map.tiberiumVariant[entry.cell] = entry.variant ?? entry.density
        }
        map.tiberiumScan = save.tiberiumScan
        map.isForwardScan = save.isForwardScan

        // Smudges
        map.smudges = save.smudges.compactMap { entry in
            guard let smType = SmudgeType(rawValue: entry.type) else { return nil }
            return Smudge(type: smType, cell: entry.cell)
        }

        // Fog of war
        if save.fogState.count == 4096 {
            map.fogState = save.fogState.map { val in
                switch val {
                case 2: return FogLevel.visible
                case 1: return FogLevel.explored
                default: return FogLevel.unexplored
                }
            }
        } else {
            initFog()
        }

        // --- Camera ---
        renderState.gameCameraX = save.cameraX
        renderState.gameCameraY = save.cameraY
        renderState.gameZoomLevel = save.zoomLevel

        // --- Credits ---
        session.sidebarCredits = save.sidebarCredits
        session.displayedCredits = save.displayedCredits
        session.scenarioBuildLevel = save.scenarioBuildLevel
        session.currentScenarioName = scenName

        // --- Campaign state ---
        session.campaignState.currentFaction = save.campaignFaction
        session.campaignState.currentMission = save.campaignMission
        session.campaignState.currentVariant = save.campaignVariant
        session.campaignState.difficulty = save.campaignDifficulty
        session.campaignState.carryOverCredits = save.carryOverCredits
        session.campaignState.isActive = save.campaignIsActive

        // --- Score ---
        session.missionScore.gdiUnitsKilled = save.scoreGDIKills
        session.missionScore.nodUnitsKilled = save.scoreNodKills
        session.missionScore.civUnitsKilled = save.scoreCivKills
        session.missionScore.gdiBuildingsKilled = save.scoreGDIBuildings
        session.missionScore.nodBuildingsKilled = save.scoreNodBuildings
        session.missionScore.civBuildingsKilled = save.scoreCivBuildings
        session.missionScore.creditsHarvested = save.scoreCreditsHarvested
        session.missionScore.elapsedTicks = save.scoreElapsedTicks

        // --- Win/lose & scripting ---
        switch save.triggerWinState {
        case "won": session.triggerWinState = .won
        case "lost": session.triggerWinState = .lost
        default: session.triggerWinState = .playing
        }
        session.allowWinFlag = save.allowWinFlag
        session.aiTickCounter = save.aiTickCounter

        // --- Restore trigger runtime state ---
        for st in save.triggers {
            if let trigger = session.gameTriggers.first(where: { $0.name == st.name }) {
                trigger.isActive = st.isActive
                trigger.data = st.data
                trigger.attachCount = st.attachCount
                trigger.firedForHouses = Set(st.firedForHouses.map { House.from($0) })
            }
        }

        // --- Production queues ---
        restoreProductionQueue(session.unitBuildQueue, from: save.unitBuildQueue)
        restoreProductionQueue(session.structureBuildQueue, from: save.structureBuildQueue)

        // --- Super weapons ---
        restoreSuperWeapon(session.playerIonCannon, from: save.ionCannon)
        restoreSuperWeapon(session.playerAirStrike, from: save.airStrike)
        restoreSuperWeapon(session.playerNukeStrike, from: save.nukeStrike)

        // --- Active teams ---
        session.activeTeams.removeAll()
        for st in save.activeTeams {
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

        // --- Projectiles ---
        // Drop in-flight projectiles on load (they are ephemeral and short-lived;
        // restoring them requires matching BulletType enums which may not round-trip
        // cleanly). This is the same trade-off the original C&C makes.
        session.activeProjectiles.removeAll()
        session.nextProjectileId = (save.projectiles.map { $0.id }.max() ?? 0) + 1

        // --- Animations ---
        session.activeAnimations.removeAll()
        for sa in save.animations {
            guard let animType = GameAnimType(rawValue: sa.type) else { continue }
            let anim = GameAnimation(type: animType, worldX: sa.worldX, worldY: sa.worldY)
            anim.currentFrame = sa.currentFrame
            anim.loopsRemaining = sa.loopsRemaining
            anim.delayCounter = sa.delayCounter
            anim.attachedToId = sa.attachedToId
            session.activeAnimations.append(anim)
        }

        // --- House states ---
        session.houseStates.removeAll()
        for sh in save.houseStates {
            let house = House.from(sh.house)
            let hs = HouseState(type: house, credits: sh.credits, isHuman: sh.isHuman)
            hs.tiberium = sh.tiberium
            hs.capacity = sh.capacity
            hs.powerOutput = sh.powerOutput
            hs.powerDrain = sh.powerDrain
            hs.unitsKilled = sh.unitsKilled
            hs.unitsLost = sh.unitsLost
            hs.buildingsKilled = sh.buildingsKilled
            hs.buildingsLost = sh.buildingsLost
            hs.isAlerted = sh.isAlerted
            hs.alertTimer = sh.alertTimer
            hs.productionEnabled = sh.productionEnabled
            hs.aiBuildCycleCount = sh.aiBuildCycleCount
            hs.aiLastAttackTick = sh.aiLastAttackTick
            hs.aiLastBuildCheckTick = sh.aiLastBuildCheckTick
            restoreProductionQueue(hs.aiUnitQueue, from: sh.aiUnitQueue)
            restoreProductionQueue(hs.aiInfantryQueue, from: sh.aiInfantryQueue)
            restoreProductionQueue(hs.aiStructureQueue, from: sh.aiStructureQueue)
            session.houseStates[house] = hs
        }

        // If house states were empty in save (shouldn't happen), rebuild
        if session.houseStates.isEmpty {
            initHouseStates()
        }

        // --- Pending reinforcements ---
        session.pendingReinforcements.removeAll()
        for sr in save.pendingReinforcements {
            let state: PendingReinforcement.ReinforcementState
            switch sr.state {
            case "unloading": state = .unloading
            case "flyingOut": state = .flyingOut
            default: state = .flyingIn
            }
            let pr = PendingReinforcement(
                transportId: sr.transportId,
                dropCell: sr.dropCell,
                house: House.from(sr.house)
            )
            pr.state = state
            session.pendingReinforcements.append(pr)
        }

        // --- Crates ---
        world.crateState.crates.removeAll()
        for sc in save.crates {
            guard let ct = crateTypeFromString(sc.crateType) else { continue }
            let crate = GameCrate(
                id: sc.id,
                cell: sc.cell,
                worldX: sc.worldX,
                worldY: sc.worldY,
                crateType: ct,
                isCollected: sc.isCollected
            )
            world.crateState.crates.append(crate)
        }
        world.crateState.nextCrateId = save.nextCrateId
        world.crateState.nextSpawnTick = save.nextCrateSpawnTick
        world.crateState.spawnedCount = save.crateSpawnedCount

        // --- Rebuild derived data ---
        buildPassabilityMap()
        updateOccupancy()

        // Reload palette for theater
        let palName: String
        switch world.theater {
        case .temperate: palName = "TEMPERAT.PAL"
        case .desert: palName = "DESERT.PAL"
        case .winter: palName = "WINTER.PAL"
        }
        renderState.gamePalette = loadPalette(palName)

        // Reset tick timing so the game loop doesn't try to catch up
        session.lastTickTime = 0
        session.tickAccumulator = 0

        // Clear transient UI state
        session.isPlacingStructure = false
        session.placementType = nil
        session.isRepairMode = false
        session.isSellMode = false
        session.isAttackMoveMode = false
        session.isPatrolMode = false
        session.patrolModeWaypoints = []
        session.superWeaponTargeting = nil

        print("MissionLoad: Loaded slot \(slot) '\(save.slotDescription)' (\(world.objects.count) objects, tick \(world.tickCount))")
        return true
    } catch {
        print("MissionLoad: Failed to load slot \(slot): \(error)")
        return false
    }
}

// MARK: - List Saves

/// Return metadata for each occupied mid-mission save slot.
func listMissionSaves() -> [(slot: Int, name: String, date: Date, scenario: String)] {
    var results: [(slot: Int, name: String, date: Date, scenario: String)] = []

    for slot in 0..<100 {
        let filename = "mission_save_\(slot).json"
        let fileURL = missionSaveDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

        do {
            let data = try Data(contentsOf: fileURL)
            // Decode only the lightweight header fields
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let save = try decoder.decode(MissionSaveHeader.self, from: data)
            results.append((slot: slot, name: save.slotDescription, date: save.saveTimestamp, scenario: save.missionName))
        } catch {
            results.append((slot: slot, name: "Corrupted", date: Date(), scenario: ""))
        }
    }

    return results
}

/// Lightweight header-only decode for listing saves without loading full state.
private struct MissionSaveHeader: Codable {
    let version: Int
    let saveTimestamp: Date
    let missionName: String
    let slotDescription: String
}

// MARK: - Delete Save

/// Remove a mid-mission save file for the given slot.
func deleteMissionSave(slot: Int) {
    let filename = "mission_save_\(slot).json"
    let fileURL = missionSaveDirectory.appendingPathComponent(filename)
    try? FileManager.default.removeItem(at: fileURL)
    print("MissionSave: Deleted slot \(slot)")
}

// MARK: - Quick Mission Save/Load (slot 0)

func quickMissionSave() -> Bool {
    return saveMission(slot: 0, description: "Quick Save")
}

func quickMissionLoad() -> Bool {
    return loadMission(slot: 0)
}

// MARK: - CrateType Serialization Helpers

private func crateTypeToString(_ ct: CrateType) -> String {
    switch ct {
    case .money:     return "money"
    case .heal:      return "heal"
    case .speed:     return "speed"
    case .firepower: return "firepower"
    case .revealMap: return "revealMap"
    case .freeUnit:  return "freeUnit"
    case .explosion: return "explosion"
    }
}

private func crateTypeFromString(_ str: String) -> CrateType? {
    switch str {
    case "money":     return .money
    case "heal":      return .heal
    case "speed":     return .speed
    case "firepower": return .firepower
    case "revealMap": return .revealMap
    case "freeUnit":  return .freeUnit
    case "explosion": return .explosion
    default:          return nil
    }
}
