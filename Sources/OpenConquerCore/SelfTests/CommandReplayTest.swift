import Foundation
import OpenConquerAssets

// MARK: - Command Replay (--test-command-replay)

/// ASSET-FREE: player orders go through the command queue and replay
/// exactly. Plays a scripted skirmish issuing move / attack / scatter / stop
/// / guard orders, then replays only the recorded command log from the same
/// seed. The two worlds must match tick for tick, and the orders must have
/// had effect.
package func headlessTestCommandReplayCommand() -> Int32 {
    print("test-command-replay: orders go through the queue and replay exactly")
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
    1=GoodGuy,MTNK,256,1302,0,Guard,None
    2=BadGuy,LTNK,256,1940,0,Guard,None
    [INFANTRY]
    0=GoodGuy,E1,256,1364,0,Guard,0,None
    1=GoodGuy,E1,256,1365,0,Guard,0,None
    2=BadGuy,E1,256,2006,0,Guard,0,None
    """
    let saved = session.rules
    session.rules = .classic1995
    defer { session.rules = saved; forcedGameSeed = nil }

    func start() -> GameWorld? {
        forcedGameSeed = 0xC0DE_5EED_0F_0DE5
        let data = parseScenarioData(INIFile(string: ini), name: "SYNTHCMD")
        initGameWorld(scenario: data, scenarioName: "SYNTHCMD")
        return session.world
    }
    func signature(_ world: GameWorld) -> String {
        world.objects.map { "\($0.id):\(Int($0.worldX * 16)),\(Int($0.worldY * 16)),\($0.strength),\($0.mission.rawValue)" }
            .joined(separator: ";") + "|rng=\(gameRng.state)"
    }
    let ticks = 400

    // 1. Scripted play: orders issued between ticks, as input would.
    guard let world = start() else { print("FAIL: no world"); return 1 }
    let player = world.objects.filter { $0.house == world.playerHouse }.map(\.id)
    guard player.count == 4, let enemyTank = world.objects.first(where: { $0.typeName == "LTNK" }) else {
        print("FAIL: scenario objects not placed"); return 1
    }
    let startX = world.findObject(id: player[0])!.worldX
    var trace: [String] = []
    for tick in 0..<ticks {
        switch tick {
        case 10:  issue(.move(units: player, to: MapPoint(x: 30 * 24, y: 25 * 24), queued: false, attackMove: false))
        case 120: issue(.attack(units: player, target: enemyTank.id))
        case 200: issue(.scatter(units: player))
        case 260: issue(.stop(units: player))
        case 300: issue(.guardPosition(units: Array(player.prefix(2))))
        default: break
        }
        gameTick()
        trace.append(signature(world))
    }
    let log = world.commandLog
    guard log.count == 5 else { print("FAIL: \(log.count) commands logged, expected 5"); return 1 }
    let moved = (world.findObject(id: player[0])?.worldX ?? startX) != startX
    guard moved else { print("FAIL: the move order had no effect"); return 1 }
    print("  played \(ticks) ticks, \(log.count) orders logged (first applied on tick \(log[0].tick))")

    // 2. Replay: the same seed plus the log, issued just before the tick each took effect on.
    guard let replay = start() else { print("FAIL: no replay world"); return 1 }
    var next = 0
    for tick in 0..<ticks {
        while next < log.count && log[next].tick == replay.tickCount + 1 {
            issue(log[next].command)
            next += 1
        }
        gameTick()
        if signature(replay) != trace[tick] {
            print("FAIL: replay diverged at tick \(tick + 1)"); return 1
        }
    }
    guard replay.commandLog == log else { print("FAIL: replay log differs"); return 1 }

    // 3. The log survives a JSON round trip (save files, replay files).
    guard let json = try? JSONEncoder().encode(log),
          let decoded = try? JSONDecoder().decode([LoggedCommand].self, from: json), decoded == log else {
        print("FAIL: command log doesn't round-trip through JSON"); return 1
    }
    print("  replayed from the log: identical for all \(ticks) ticks; log round-trips as JSON")
    print("PASS: player commands are queued, logged, and replay exactly")
    return 0
}
