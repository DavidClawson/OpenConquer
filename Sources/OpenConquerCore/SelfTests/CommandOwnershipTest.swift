import Foundation
import OpenConquerAssets

// MARK: - Command Ownership (--test-command-ownership)

/// ASSET-FREE: a command acts only for the house that issued it
/// (EventClass::ID, EVENT.CPP). The same move order, naming both sides'
/// tanks, moves only GDI's when GDI gives it and only Nod's when Nod does;
/// Nod can't sell GDI's building; production from a house other than the
/// player's is dropped (only the player has build queues so far); and the
/// log records who gave each order.
package func headlessTestCommandOwnershipCommand() -> Int32 {
    print("test-command-ownership: orders act only for the house that gave them")
    let ini = """
    [Basic]
    BuildLevel=1
    [GoodGuy]
    Credits=50
    [MAP]
    Theater=TEMPERATE
    X=2
    Y=2
    Width=60
    Height=60
    [UNITS]
    0=GoodGuy,MTNK,256,1300,0,Guard,None
    1=BadGuy,LTNK,256,1940,0,Guard,None
    [STRUCTURES]
    0=GoodGuy,PROC,256,1500,0,None
    """
    let saved = session.rules
    session.rules = .classic1995
    defer { session.rules = saved; forcedGameSeed = nil }
    forcedGameSeed = 0x0_0517_E5_D0
    initGameWorld(scenario: parseScenarioData(INIFile(string: ini), name: "SYNTHOWN"), scenarioName: "SYNTHOWN")
    guard let world = session.world, world.playerHouse == .goodGuy,
          let gdiTank = world.objects.first(where: { $0.typeName == "MTNK" }),
          let nodTank = world.objects.first(where: { $0.typeName == "LTNK" }),
          let refinery = world.objects.first(where: { $0.typeName == "PROC" }) else {
        print("FAIL: scenario objects not placed"); return 1
    }
    let both = [gdiTank.id, nodTank.id]
    let target = MapPoint(x: 30 * 24, y: 30 * 24)
    func moving(_ obj: GameObject) -> Bool { obj.mission == .move }

    // GDI (the player, by default) orders both tanks: only GDI's moves.
    issue(.move(units: both, to: target, queued: false, attackMove: false))
    gameTick()
    guard moving(gdiTank), !moving(nodTank) else {
        print("FAIL: GDI's order moved \(moving(nodTank) ? "Nod's tank" : "nothing")"); return 1
    }

    // Nod orders both tanks to stop, then to move: only Nod's tank obeys.
    issue(.move(units: both, to: target, queued: false, attackMove: false), as: .badGuy)
    gameTick()
    guard moving(nodTank) else { print("FAIL: Nod's order didn't move Nod's tank"); return 1 }
    issue(.stop(units: both), as: .badGuy)
    gameTick()
    guard moving(gdiTank), !moving(nodTank) else {
        print("FAIL: Nod's stop order \(moving(nodTank) ? "didn't stop Nod's tank" : "stopped GDI's tank")"); return 1
    }

    // Nod can't sell GDI's refinery, or spend from the player's build queues.
    let credits = session.sidebarCredits
    issue(.sell(building: refinery.id), as: .badGuy)
    issue(.startProduction(structure: false, type: "LTNK", cost: 10, buildTicks: 10), as: .badGuy)
    gameTick()
    guard refinery.mission != .selling else { print("FAIL: Nod sold GDI's refinery"); return 1 }
    guard session.unitBuildQueue.item == nil, session.sidebarCredits == credits else {
        print("FAIL: Nod's production order used the player's queue"); return 1
    }

    // The log keeps each order's house, and round-trips through JSON.
    let houses = world.commandLog.map(\.house)
    guard houses == [.goodGuy, .badGuy, .badGuy, .badGuy, .badGuy] else {
        print("FAIL: logged houses \(houses.map(\.rawValue))"); return 1
    }
    guard let json = try? JSONEncoder().encode(world.commandLog),
          let decoded = try? JSONDecoder().decode([LoggedCommand].self, from: json), decoded == world.commandLog else {
        print("FAIL: the log doesn't round-trip through JSON"); return 1
    }
    print("PASS: each order moved only its own house's objects; \(houses.count) logged with their house")
    return 0
}
