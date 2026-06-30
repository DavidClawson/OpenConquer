import Foundation

// MARK: - Tiberium System

// tiberiumCells is now in GameWorld.map (GameMap)

/// Maximum tiberium a harvester can carry
let maxTiberiumLoad: Int = 20

/// Credits per unit of tiberium
let tiberiumValue: Int = 25

// MARK: - Harvester docking tuning

/// Tiberium units deposited per tick while unloading at the refinery.
/// At maxTiberiumLoad=20 this empties a full harvester over ~20 ticks (~1.3s).
let harvesterUnloadRate: Int = 1

/// Ticks the harvester takes to slide into / back out of the refinery bay.
let harvesterDockSlideTicks: Int = 8

/// How far (pixels) the harvester sprite slides north into the bay when docked.
let harvesterDockDepth: Double = 22.0

// missionStatus values used by the harvester while returning to a refinery:
let dockApproaching = 0   // driving to the dock cell (or out harvesting)
let dockUnloading   = 1   // seated in the bay, depositing tiberium
let dockBackingOut  = 2   // sliding back out of the bay before heading to the field

/// Compute the cell a harvester should drive to for unloading.
/// PROC's 3x3 footprint center is structurally impassable, so we dock just
/// outside it. The canonical bay faces south (one cell below the footprint),
/// and the dock slide animation assumes that, so we prefer it. But on some
/// maps that cell is blocked (water, a wall, another structure, the map edge);
/// when it is, the harvester used to park wherever `findPath` rerouted it and
/// idle forever without ever reaching the arrival radius — so it never docked,
/// never animated, and never deposited credits. To make docking reliable we
/// fall back to the nearest *statically passable* cell around the footprint
/// perimeter so the harvester always has a reachable resting cell to dock at.
/// Returns (cellX, cellY) of the dock point.
func harvesterDockCell(refinery: GameObject) -> (cellX: Int, cellY: Int) {
    let cx = refinery.cellX
    let cy = refinery.cellY
    // Canonical south bay — keep the north-slide dock animation aligned.
    let canonical = (cellX: cx, cellY: cy + 2)
    guard session.world != nil else { return canonical }
    let pass = passabilityMap(for: .harvester)
    func passable(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, x < 64, y >= 0, y < 64 else { return false }
        return pass[y * 64 + x]
    }
    if passable(canonical.cellX, canonical.cellY) { return canonical }
    // South first (closest to the real bay), then east/west, then north.
    let candidates: [(Int, Int)] = [
        (cx, cy + 2), (cx - 1, cy + 2), (cx + 1, cy + 2),   // south row
        (cx + 2, cy + 1), (cx + 2, cy), (cx + 2, cy - 1),   // east column
        (cx - 2, cy + 1), (cx - 2, cy), (cx - 2, cy - 1),   // west column
        (cx, cy - 2), (cx - 1, cy - 2), (cx + 1, cy - 2),   // north row
    ]
    for (x, y) in candidates where passable(x, y) { return (cellX: x, cellY: y) }
    return canonical
}

/// Scan scenario overlays for tiberium
func initTiberiumCells() {
    guard let map = session.world?.map else { return }
    map.tiberiumCells.removeAll()
    map.tiberiumDensity.removeAll()
    map.tiberiumVariant.removeAll()
    guard let scenario = map.scenarioData else {
        print("GameEconomy: No scenarioData available for tiberium init (map.scenarioData is nil)")
        return
    }
    // First pass: register all tiberium cells.
    // The scenario's TI<N> overlay name is the *sprite variant* (which of the
    // 12 ground shapes to draw) — NOT the density. Density (0-11 in C&C, 1-12
    // here) is the maturity / frame index within that variant's SHP.
    for overlay in scenario.overlays {
        let upper = overlay.typeName.uppercased()
        if upper.hasPrefix("TI") {
            let numPart = upper.dropFirst(2)
            if let num = Int(numPart), num >= 1 && num <= 12 {
                map.tiberiumCells.insert(overlay.cell)
                map.tiberiumVariant[overlay.cell] = num
                // Start density low — Tiberium_Adjust below raises it based on
                // how surrounded a cell is, mirroring VC's initial growth pass.
                map.tiberiumDensity[overlay.cell] = 1
            }
        }
    }

    // Second pass: density rises with neighbor count (VC Tiberium_Adjust).
    // Cells surrounded by more tiberium start at a higher maturity frame.
    let adjTable = [0, 1, 3, 4, 6, 7, 8, 10, 11]
    for cell in map.tiberiumCells {
        let cx = cell % 64
        let cy = cell / 64
        var adjCount = 0
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = cx + dx
                let ny = cy + dy
                if nx >= 0 && nx < 64 && ny >= 0 && ny < 64 {
                    if map.tiberiumCells.contains(ny * 64 + nx) {
                        adjCount += 1
                    }
                }
            }
        }
        let neighborDensity = adjTable[min(adjCount, adjTable.count - 1)] + 1
        map.tiberiumDensity[cell] = min(neighborDensity, 12)
    }
    print("GameEconomy: Found \(map.tiberiumCells.count) tiberium cells")
}

// MARK: - Harvester Extension

extension GameObject {

    /// Tick harvester state machine
    func tickHarvest() {
        guard let world = session.world else { return }
        let upper = typeName.uppercased()
        if upper != "HARV" { return }

        // Are we mid-dock (seated in the bay or backing out)? Once we're at our
        // own refinery we ignore threats and never re-path for tiberium.
        let isDocking = (missionStatus == dockUnloading) || (missionStatus == dockBackingOut)

        // Harvester threat avoidance: check for nearby enemy combat units every 15 ticks
        if !isDocking && world.tickCount % 15 == 0 {
            let fleeRange = 5.0 * 24.0  // 5 cells in pixels
            var nearestEnemy: GameObject? = nil
            var nearestEnemyDist = Double.infinity

            for other in world.objects {
                guard other.strength > 0 else { continue }
                guard other.house != house else { continue }
                guard other.house != .neutral else { continue }
                guard !other.isAircraft else { continue }
                // Only flee from armed ground units (not other harvesters, not unarmed)
                guard other.isArmed else { continue }
                guard other.kind == .unit || other.kind == .infantry else { continue }

                let dx = other.worldX - worldX
                let dy = other.worldY - worldY
                let dist = sqrt(dx * dx + dy * dy)
                if dist < fleeRange && dist < nearestEnemyDist {
                    nearestEnemy = other
                    nearestEnemyDist = dist
                }
            }

            if let enemy = nearestEnemy {
                if tiberiumLoad > 0 {
                    // Carrying tiberium: force return to refinery immediately
                    tiberiumLoad = maxTiberiumLoad
                    moveTargetX = nil
                    moveTargetY = nil
                    movePath = []
                    // Fall through to the normal "full" return-to-refinery logic below
                } else {
                    // Empty: flee in opposite direction from enemy
                    let dx = worldX - enemy.worldX
                    let dy = worldY - enemy.worldY
                    let dist = max(1.0, sqrt(dx * dx + dy * dy))
                    let fleeX = max(12, min(64 * 24 - 12, worldX + dx / dist * 120))
                    let fleeY = max(12, min(64 * 24 - 12, worldY + dy / dist * 120))
                    moveTargetX = fleeX
                    moveTargetY = fleeY
                    movePath = []
                    moveOneStep()
                    return
                }
            }
        }

        // State machine based on current conditions
        if tiberiumLoad >= maxTiberiumLoad || isDocking {
            // Full, or already docking — run the refinery docking sequence.
            guard let refinery = findNearestRefinery() else {
                // No refinery — abandon the dock and just sit.
                missionStatus = dockApproaching
                isTethered = false
                dockTimer = 0
                moveTargetX = nil
                moveTargetY = nil
                movePath = []
                return
            }

            // The refinery's worldX/worldY is the CENTER of its 3x3 footprint,
            // which is impassable. Dock one cell south of the PROC center — one
            // cell beyond the footprint, where the bay door faces. We can't
            // physically drive into the bay (the footprint blocks pathing), so
            // the "into the bay" motion is a render offset on a tethered unit,
            // mirroring the original engine's RADIO_TETHER docking.
            let dock = harvesterDockCell(refinery: refinery)
            let dockWorldX = Double(dock.cellX * 24) + 12.0
            let dockWorldY = Double(dock.cellY * 24) + 12.0
            let dx = dockWorldX - worldX
            let dy = dockWorldY - worldY
            let dist = sqrt(dx * dx + dy * dy)

            // Safety: if we hold a docking sub-state but aren't actually at the
            // bay (e.g. the player redirected us mid-dock, or the refinery moved
            // because the nearest one changed), drop back to approaching so we
            // never deposit tiberium away from the refinery.
            if (missionStatus == dockUnloading || missionStatus == dockBackingOut) && dist > 44.0 {
                missionStatus = dockApproaching
                isTethered = false
                dockTimer = 0
            }

            if ProcessInfo.processInfo.environment["HARV_DEBUG"] != nil, world.tickCount % 45 == 0 {
                print("HARV t=\(world.tickCount) id=\(id) house=\(house.rawValue) cell=(\(cellX),\(cellY)) load=\(tiberiumLoad) status=\(missionStatus) dock=(\(dock.cellX),\(dock.cellY)) dist=\(String(format: "%.1f", dist)) path=\(movePath.count)")
            }

            switch missionStatus {
            case dockUnloading:
                // Seated in the bay: stay put, face into the refinery (north),
                // slide in, then meter out the load.
                isTethered = true
                facing = 0
                moveTargetX = nil
                moveTargetY = nil
                movePath = []
                dockTimer += 1
                // Wait for the slide-in to finish before depositing.
                if dockTimer >= harvesterDockSlideTicks {
                    if tiberiumLoad > 0 {
                        let chunk = min(harvesterUnloadRate, tiberiumLoad)
                        depositTiberium(load: chunk)
                        tiberiumLoad -= chunk
                    }
                    if tiberiumLoad <= 0 {
                        // Empty — begin backing out of the bay.
                        missionStatus = dockBackingOut
                        dockTimer = 0
                        isTethered = false
                    }
                }

            case dockBackingOut:
                // Slide back out of the bay before resuming harvesting.
                isTethered = false
                moveTargetX = nil
                moveTargetY = nil
                movePath = []
                dockTimer += 1
                if dockTimer >= harvesterDockSlideTicks {
                    missionStatus = dockApproaching
                    dockTimer = 0
                }

            default:
                // Approaching the dock cell.
                if dist < 14.0 {
                    // Arrived — begin docking.
                    missionStatus = dockUnloading
                    dockTimer = 0
                    isTethered = true
                    facing = 0
                    moveTargetX = nil
                    moveTargetY = nil
                    movePath = []
                } else {
                    // Drive to the dock cell, not the refinery's blocked center.
                    moveTargetX = dockWorldX
                    moveTargetY = dockWorldY
                    var stuck = false
                    if movePath.isEmpty {
                        movePath = findPath(
                            fromX: cellX, fromY: cellY,
                            toX: dock.cellX, toY: dock.cellY,
                            ignoring: self,
                            speedType: .harvester
                        )
                        // An empty result here means findPath rerouted the dock
                        // cell onto our own cell — we're already as close as the
                        // map allows and can't get any nearer. On a normal
                        // approach findPath returns a non-empty path, so this is
                        // only true for a genuinely stuck harvester.
                        stuck = movePath.isEmpty
                    }
                    // Safety net: if we can't path any closer (the dock cell is
                    // blocked, or a refinery hemmed in by silos/walls rerouted us
                    // several cells short) but we're clearly *at* the refinery,
                    // dock in place rather than idling at the bay forever. We
                    // gauge "at the refinery" by distance to the 3x3 footprint
                    // center (~1.5 cells to its edge): a harvester within ~2.5
                    // cells of the edge (≈ 4 cells / 96px from center) that can't
                    // path closer is as docked as it's going to get.
                    let rdx = refinery.worldX - worldX
                    let rdy = refinery.worldY - worldY
                    let distToRefinery = sqrt(rdx * rdx + rdy * rdy)
                    if stuck && distToRefinery < 96.0 {
                        if ProcessInfo.processInfo.environment["HARV_DEBUG"] != nil {
                            print("HARV-DOCK(rescue) id=\(id) house=\(house.rawValue) cell=(\(cellX),\(cellY)) distToRefinery=\(String(format: "%.1f", distToRefinery)) dock=(\(dock.cellX),\(dock.cellY))")
                        }
                        missionStatus = dockUnloading
                        dockTimer = 0
                        isTethered = true
                        facing = 0
                        moveTargetX = nil
                        moveTargetY = nil
                    } else {
                        let _ = moveOneStep()
                    }
                }
            }
        } else if world.map.tiberiumCells.contains(cell) {
            // On tiberium — harvest
            // Harvest one unit every few ticks
            if world.tickCount % 4 == 0 {
                tiberiumLoad += 1
                // Reduce density; remove cell when depleted
                if tiberiumLoad % 5 == 0 {
                    let density = world.map.tiberiumDensity[cell] ?? 1
                    if density <= 1 {
                        world.map.tiberiumCells.remove(cell)
                        world.map.tiberiumDensity.removeValue(forKey: cell)
                        world.map.tiberiumVariant.removeValue(forKey: cell)
                    } else {
                        world.map.tiberiumDensity[cell] = density - 1
                    }
                }
            }
        } else {
            // Not on tiberium and not full — find nearest tiberium
            if let target = findNearestTiberium() {
                let targetPx = Double(target.cellX * 24) + 12.0
                let targetPy = Double(target.cellY * 24) + 12.0

                // Check if we're already moving to tiberium
                if let mx = moveTargetX, let my = moveTargetY {
                    let dx = mx - targetPx
                    let dy = my - targetPy
                    if sqrt(dx * dx + dy * dy) < 2.0 {
                        // Already heading there
                        let _ = moveOneStep()
                        return
                    }
                }

                moveTargetX = targetPx
                moveTargetY = targetPy
                movePath = findPath(
                    fromX: cellX, fromY: cellY,
                    toX: target.cellX, toY: target.cellY,
                    ignoring: self,
                    speedType: .harvester
                )
                let _ = moveOneStep()
            } else {
                // No tiberium left — return to refinery if carrying anything
                if tiberiumLoad > 0 {
                    tiberiumLoad = maxTiberiumLoad  // Force return
                }
            }
        }
    }

    /// Deposit `load` units of tiberium into this harvester's house, honoring
    /// silo capacity. Factored out of tickHarvest so the unload can be metered
    /// over several ticks instead of dumped in one lump.
    func depositTiberium(load: Int) {
        guard load > 0 else { return }
        var creditsGained = load * tiberiumValue
        let houseState = getHouseState(house)
        let fullValue = creditsGained
        // Enforce silo capacity: only store up to the capacity limit.
        if houseState.capacity > 0 {
            let spaceLeft = max(0, houseState.capacity - houseState.tiberium)
            let creditsToStore = min(creditsGained, spaceLeft)
            houseState.tiberium += creditsToStore
            creditsGained = creditsToStore
        }
        if ProcessInfo.processInfo.environment["HARV_DEBUG"] != nil {
            let clipped = creditsGained < fullValue ? "  *** CLIPPED by silo capacity (silos full) ***" : ""
            print("DEPOSIT house=\(house.rawValue) load=\(load) gained=\(creditsGained)/\(fullValue) cap=\(houseState.capacity) tib=\(houseState.tiberium) credits=\(houseState.credits + creditsGained)\(clipped)")
        }
        houseState.addCredits(creditsGained)
        // Keep sidebar credits in sync for the player.
        if house == session.world?.playerHouse {
            session.sidebarCredits += creditsGained
        }
        if creditsGained > 0 {
            eventBus.emit(.tiberiumHarvested(house: house, amount: creditsGained))
        }
    }

    /// Render-space offset (pixels) that slides a docked harvester into and out
    /// of the refinery bay. Returns zero unless this is a harvester actively
    /// docking on a Harvest mission, so a redirected harvester never floats.
    func harvesterDockOffset() -> (dx: Double, dy: Double) {
        guard isHarvester, mission == .harvest else { return (0, 0) }
        let slide = Double(max(1, harvesterDockSlideTicks))
        switch missionStatus {
        case dockUnloading:
            // Slide north into the bay as dockTimer ramps to slide length.
            let frac = min(1.0, Double(dockTimer) / slide)
            return (0, -harvesterDockDepth * frac)
        case dockBackingOut:
            // Slide back out (full depth -> 0) as dockTimer ramps.
            let frac = min(1.0, Double(dockTimer) / slide)
            return (0, -harvesterDockDepth * (1.0 - frac))
        default:
            return (0, 0)
        }
    }

    /// Find nearest tiberium cell to this harvester
    func findNearestTiberium() -> (cellX: Int, cellY: Int)? {
        guard let map = session.world?.map else { return nil }
        var bestCell: (cellX: Int, cellY: Int)? = nil
        var bestDist = Double.infinity

        for cell in map.tiberiumCells {
            let cx = cell % 64
            let cy = cell / 64
            let dx = Double(cx) - Double(cellX)
            let dy = Double(cy) - Double(cellY)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < bestDist {
                bestDist = dist
                bestCell = (cellX: cx, cellY: cy)
            }
        }
        return bestCell
    }

    /// Find nearest refinery owned by this object's house
    func findNearestRefinery() -> GameObject? {
        guard let world = session.world else { return nil }
        var nearest: GameObject? = nil
        var nearestDist = Double.infinity

        for other in world.objects {
            if other.kind != .structure { continue }
            if other.house != house { continue }
            if other.strength <= 0 { continue }
            if other.typeName.uppercased() != "PROC" { continue }

            let dx = other.worldX - worldX
            let dy = other.worldY - worldY
            let dist = sqrt(dx * dx + dy * dy)
            if dist < nearestDist {
                nearest = other
                nearestDist = dist
            }
        }
        return nearest
    }
}

// MARK: - Tiberium Growth & Spread

extension GameMap {

    /// Number of cells scanned per tick (VC scans MAP_CELL_TOTAL over ~136 ticks)
    private static let scanBlockSize = 4096 / 136  // ~30 cells per tick

    /// Maximum entries in growth/spread candidate lists (VC uses MAP_CELL_W/2 = 32)
    private static let maxCandidates = 32

    /// 8-directional adjacency offsets (dx, dy)
    private static let adjacentOffsets: [(dx: Int, dy: Int)] = [
        (0, -1), (1, -1), (1, 0), (1, 1),
        (0, 1), (-1, 1), (-1, 0), (-1, -1)
    ]

    /// Tick tiberium growth and spread.
    /// Faithfully ports VC MapClass::Logic() — scans a block of cells each tick,
    /// accumulates growth/spread candidates across multiple ticks, then processes
    /// them all when a full scan cycle completes.
    func tickTiberiumGrowth() {
        // Scan a block of cells this tick, accumulating candidates
        var remaining = GameMap.scanBlockSize
        var index = tiberiumScan

        while index < 4096 && remaining > 0 {
            let cell = isForwardScan ? index : (4095 - index)

            if tiberiumCells.contains(cell) {
                let density = tiberiumDensity[cell] ?? 1

                // Growth: cells with density < 12 can grow
                if density < 12 {
                    if tiberiumGrowthCandidates.count < GameMap.maxCandidates {
                        tiberiumGrowthCandidates.append(cell)
                    } else {
                        // Reservoir sampling — replace a random existing entry
                        tiberiumGrowthCandidates[rndInt(0..<tiberiumGrowthCandidates.count)] = cell
                    }
                }

                // Spread: cells with density > 6 can spread (VC: OverlayData > 6)
                if density > 6 {
                    if tiberiumSpreadCandidates.count < GameMap.maxCandidates {
                        tiberiumSpreadCandidates.append(cell)
                    } else {
                        tiberiumSpreadCandidates[rndInt(0..<tiberiumSpreadCandidates.count)] = cell
                    }
                }
            }

            index += 1
            remaining -= 1
        }

        tiberiumScan = index

        // Only process candidates when a full scan cycle completes
        guard tiberiumScan >= 4096 else { return }

        // Reset scan for next cycle
        tiberiumScan = 0
        isForwardScan.toggle()

        // Growth: pick random candidates and increase their density
        // Process up to 4 growth candidates per cycle for visible growth rate
        let growthPicks = min(4, tiberiumGrowthCandidates.count)
        for _ in 0..<growthPicks {
            let pick = rndInt(0..<tiberiumGrowthCandidates.count)
            let cell = tiberiumGrowthCandidates[pick]
            if tiberiumCells.contains(cell) {
                let current = tiberiumDensity[cell] ?? 1
                if current < 12 {
                    tiberiumDensity[cell] = current + 1
                }
            }
        }

        // Spread: pick random candidates and try to spread to adjacent empty cells
        // Process up to 2 spread candidates per cycle
        let spreadPicks = min(2, tiberiumSpreadCandidates.count)
        for _ in 0..<spreadPicks {
            let pick = rndInt(0..<tiberiumSpreadCandidates.count)
            let cell = tiberiumSpreadCandidates[pick]
            let cx = cell % 64
            let cy = cell / 64

            // Start from a random direction and try all 8 adjacent cells
            let startDir = rndInt(0..<8)
            for i in 0..<8 {
                let dir = (startDir + i) % 8
                let offset = GameMap.adjacentOffsets[dir]
                let nx = cx + offset.dx
                let ny = cy + offset.dy

                guard nx >= 0 && nx < 64 && ny >= 0 && ny < 64 else { continue }
                let adjCell = ny * 64 + nx

                // Only spread to passable land cells without existing tiberium
                guard !tiberiumCells.contains(adjCell) else { continue }
                guard adjCell < landPassability.count && landPassability[adjCell] else { continue }

                // Don't spread onto water
                guard adjCell < waterPassability.count && !waterPassability[adjCell] else { continue }

                // Don't spread onto cells occupied by structures
                if let world = session.world {
                    let occupied = world.objects.contains { obj in
                        obj.kind == .structure && obj.strength > 0 && obj.cell == adjCell
                    }
                    if occupied { continue }
                }

                // Spread tiberium to this cell. Pick a random visual variant
                // 1..12 so spread tiles aren't all identical clones.
                tiberiumCells.insert(adjCell)
                tiberiumDensity[adjCell] = 1
                tiberiumVariant[adjCell] = rndInt(1...12)
                break
            }
        }

        // Clear candidate lists for next scan cycle
        tiberiumGrowthCandidates.removeAll(keepingCapacity: true)
        tiberiumSpreadCandidates.removeAll(keepingCapacity: true)
    }
}
