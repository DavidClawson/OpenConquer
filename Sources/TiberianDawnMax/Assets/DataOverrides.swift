import Foundation

// MARK: - Data Overrides
// Modder-friendly hook for tweaking unit/building/infantry stats without
// recompiling the binary. Drop JSON files in
// `<dataPath>/extracted/data/{units,buildings,infantry}.json` and the
// listed iniName entries override the compiled defaults at startup.
//
// Each entry's fields are optional — only the listed fields are changed,
// everything else stays at the compiled default. Unknown iniNames log a
// warning and are skipped. A malformed JSON file is logged and ignored
// (game continues with defaults — never fails to launch over a bad mod).
//
// Example `extracted/data/units.json`:
//   { "MTNK": { "cost": 1500, "strength": 500, "sightRange": 5 } }

// MARK: - Override Schemas

struct UnitOverride: Codable {
    let cost: Int?
    let strength: Int?
    let sightRange: Int?
    let buildLevel: Int?
    let ammo: Int?
    let rot: Int?
    let fullName: String?
}

struct BuildingOverride: Codable {
    let cost: Int?
    let strength: Int?
    let sightRange: Int?
    let buildLevel: Int?
    let powerProduction: Int?
    let powerDrain: Int?
    let tiberiumCapacity: Int?
    let fullName: String?
}

struct InfantryOverride: Codable {
    let cost: Int?
    let strength: Int?
    let sightRange: Int?
    let buildLevel: Int?
    let fullName: String?
}

// MARK: - Per-Type Mergers

private extension UnitTypeData {
    func applying(_ o: UnitOverride) -> UnitTypeData {
        return UnitTypeData(
            type: self.type, iniName: self.iniName,
            fullName: o.fullName ?? self.fullName,
            buildLevel: o.buildLevel ?? self.buildLevel,
            prerequisite: self.prerequisite,
            cost: o.cost ?? self.cost,
            scenario: self.scenario, ownable: self.ownable,
            strength: o.strength ?? self.strength,
            armor: self.armor,
            primaryWeapon: self.primaryWeapon,
            secondaryWeapon: self.secondaryWeapon,
            sightRange: o.sightRange ?? self.sightRange,
            ammo: o.ammo ?? self.ammo,
            speed: self.speed, maxSpeed: self.maxSpeed,
            rot: o.rot ?? self.rot,
            isBuildable: self.isBuildable, isLeader: self.isLeader,
            hasTurret: self.hasTurret, isTwoShooter: self.isTwoShooter,
            isTransporter: self.isTransporter, isCrushable: self.isCrushable,
            isCrusher: self.isCrusher, isHarvester: self.isHarvester,
            isCloakable: self.isCloakable, isRepairable: self.isRepairable,
            hasCrew: self.hasCrew, isGigundo: self.isGigundo,
            isStealthy: self.isStealthy, isAnimating: self.isAnimating,
            isLockTurret: self.isLockTurret,
            riskValue: self.riskValue, rewardValue: self.rewardValue,
            explosion: self.explosion, defaultMission: self.defaultMission
        )
    }
}

private extension BuildingTypeData {
    func applying(_ o: BuildingOverride) -> BuildingTypeData {
        return BuildingTypeData(
            type: self.type, iniName: self.iniName,
            fullName: o.fullName ?? self.fullName,
            buildLevel: o.buildLevel ?? self.buildLevel,
            prerequisite: self.prerequisite,
            cost: o.cost ?? self.cost,
            scenario: self.scenario, ownable: self.ownable,
            strength: o.strength ?? self.strength,
            armor: self.armor,
            primaryWeapon: self.primaryWeapon,
            secondaryWeapon: self.secondaryWeapon,
            sightRange: o.sightRange ?? self.sightRange,
            powerProduction: o.powerProduction ?? self.powerProduction,
            powerDrain: o.powerDrain ?? self.powerDrain,
            tiberiumCapacity: o.tiberiumCapacity ?? self.tiberiumCapacity,
            sizeW: self.sizeW, sizeH: self.sizeH,
            isBuildable: self.isBuildable, hasTurret: self.hasTurret,
            isCapturable: self.isCapturable, isWall: self.isWall,
            isCivilian: self.isCivilian,
            riskValue: self.riskValue, rewardValue: self.rewardValue
        )
    }
}

private extension InfantryTypeData {
    func applying(_ o: InfantryOverride) -> InfantryTypeData {
        return InfantryTypeData(
            type: self.type, iniName: self.iniName,
            fullName: o.fullName ?? self.fullName,
            buildLevel: o.buildLevel ?? self.buildLevel,
            prerequisite: self.prerequisite,
            cost: o.cost ?? self.cost,
            scenario: self.scenario, ownable: self.ownable,
            strength: o.strength ?? self.strength,
            armor: self.armor,
            primaryWeapon: self.primaryWeapon,
            secondaryWeapon: self.secondaryWeapon,
            sightRange: o.sightRange ?? self.sightRange,
            maxSpeed: self.maxSpeed,
            isBuildable: self.isBuildable, isLeader: self.isLeader,
            isCivilian: self.isCivilian, isFraidycat: self.isFraidycat,
            canCapture: self.canCapture, hasCrawl: self.hasCrawl,
            isFemale: self.isFemale,
            riskValue: self.riskValue, rewardValue: self.rewardValue
        )
    }
}

// MARK: - Loader Entry Point

/// Apply any data overrides found under `<dataPath>/extracted/data/`.
/// Idempotent and safe to call once at startup — silently no-op if the
/// directory or files don't exist.
func loadDataOverrides() {
    let dir = assetManager.dataPath
        .appendingPathComponent("extracted")
        .appendingPathComponent("data")

    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
          isDir.boolValue else {
        return
    }

    applyOverrides(at: dir.appendingPathComponent("units.json"),
                   as: [String: UnitOverride].self,
                   label: "unit",
                   apply: applyUnitOverrides)

    applyOverrides(at: dir.appendingPathComponent("buildings.json"),
                   as: [String: BuildingOverride].self,
                   label: "building",
                   apply: applyBuildingOverrides)

    applyOverrides(at: dir.appendingPathComponent("infantry.json"),
                   as: [String: InfantryOverride].self,
                   label: "infantry",
                   apply: applyInfantryOverrides)
}

private func applyOverrides<T: Decodable>(
    at url: URL,
    as type: T.Type,
    label: String,
    apply: (T) -> Int
) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    guard let data = try? Data(contentsOf: url) else {
        print("DataOverrides: Could not read \(url.lastPathComponent)")
        return
    }
    do {
        let parsed = try JSONDecoder().decode(T.self, from: data)
        let count = apply(parsed)
        print("DataOverrides: applied \(count) \(label) override(s) from \(url.lastPathComponent)")
    } catch {
        print("DataOverrides: Failed to parse \(url.lastPathComponent): \(error)")
    }
}

// MARK: - Apply Functions

private func applyUnitOverrides(_ overrides: [String: UnitOverride]) -> Int {
    var applied = 0
    for (iniName, override) in overrides {
        let key = iniName.uppercased()
        guard let ut = UnitType.from(iniName: key),
              let existing = unitTypeDataTable[ut] else {
            print("DataOverrides: Unknown unit '\(iniName)' — skipped")
            continue
        }
        unitTypeDataTable[ut] = existing.applying(override)
        applied += 1
    }
    return applied
}

private func applyBuildingOverrides(_ overrides: [String: BuildingOverride]) -> Int {
    var applied = 0
    for (iniName, override) in overrides {
        let key = iniName.uppercased()
        guard let st = StructType.from(iniName: key),
              let existing = buildingTypeDataTable[st] else {
            print("DataOverrides: Unknown building '\(iniName)' — skipped")
            continue
        }
        buildingTypeDataTable[st] = existing.applying(override)
        applied += 1
    }
    return applied
}

private func applyInfantryOverrides(_ overrides: [String: InfantryOverride]) -> Int {
    var applied = 0
    for (iniName, override) in overrides {
        let key = iniName.uppercased()
        guard let it = InfantryType.from(iniName: key),
              let existing = infantryTypeDataTable[it] else {
            print("DataOverrides: Unknown infantry '\(iniName)' — skipped")
            continue
        }
        infantryTypeDataTable[it] = existing.applying(override)
        applied += 1
    }
    return applied
}
