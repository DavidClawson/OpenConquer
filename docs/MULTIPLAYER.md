# Multiplayer — per-player state (Phase 6, step 1)

Survey and plan for taking the simulation from "one human, everyone else is
AI" to "N players, each with their own house", the groundwork for skirmish
(step 2) and lockstep networking (steps 3–4) in `docs/ROADMAP.md`. Written Oct
2026 against `main` at `a58b847`.

## How the original does it

- **Houses own everything.** `HouseClass` (HOUSE.CPP) holds each house's
  credits, tiberium, power, factories and production, special weapons,
  `IsHuman`, alliances and win/lose flags. There is one `HouseClass` per
  house in every game, single- or multiplayer; nothing economic is
  "the player's".
- **The local player is a pointer, not a special case.** `PlayerPtr` is the
  house this machine controls (set from `Whom` in campaign, from the
  multiplayer setup otherwise). Rendering, the sidebar, the radar and fog use
  `PlayerPtr`; the simulation code mostly asks the object's own `House`.
- **Orders are events from a house.** Input builds an `EventClass` (EVENT.H)
  whose `ID` is the issuing house index and `Frame` the frame it executes on.
  Single-player puts events straight on `DoList`; multiplayer sends `OutList`
  to every peer, and every machine executes the same `DoList` on the same
  frame (`Queue_AI_Multiplayer`). `EventClass::Execute` acts *as* house `ID`:
  `Houses.Raw_Ptr(ID)->Begin_Production(...)`, `Place_Object(...)`, and SELL
  checks `techno->House == Houses.Raw_Ptr(ID)`. (MEGAMISSION itself trusts
  the sender — the stricter ownership check below is ours.)
- **Selection is never in the event stream.** `IsSelected` lives on the
  objects but is local display state; only the resulting orders travel.

## What assumes a single human here

`world.playerHouse` has ~95 reads across 27 Core files (Oct 2026). Grouped:

| Area | Where | What it assumes |
|---|---|---|
| **Commands** | `PlayerCommands.swift` | ~~`apply` checks ownership against `world.playerHouse`~~ — done: commands carry their house (slice 1) |
| **Production & credits** | `GameProduction.swift`, `session.unitBuildQueue` / `structureBuildQueue`, `session.sidebarCredits` | one pair of build queues and one credit balance, the player's; AI houses use `HouseState.credits` and their own production path. Two balances for "credits" (`GameTrigger.swift:564` picks between them). |
| **Power** | `GameHouse.swift:295`, `GameEconomy.swift:133` | per-house already (`HouseState.powerOutput/Drain`); only the low-power EVA line reads the player's |
| **Fog / shroud** | `GameFog.swift:50` | one `map.fogState` for the player; every house already has `map.houseVisibility` |
| **Super weapons** | `GameSuperWeapons.swift`, `session.combat` | the player's on `session.combat`, AI copies on `HouseState.superWeapons` |
| **AI** | `GameAI*.swift` (~14) | ~~"every house but the player's is AI"~~ — gating now asks `world.isHuman(house)` (slice 3); three reads that target "the player's" structures/harvesters remain (`GameAI.swift` 163/181/1064) |
| **Win / lose** | `GameTrigger.swift` (9) | triggers owned by `playerHouse` decide the outcome; enemy = the other of GDI/Nod (`:881`) |
| **EVA and feedback** | `GameCombat`, `GameMissions`, `GameEconomy`, `GameReinforcements`, `GameProjectiles` (~25) | speech/sounds only for the player's house — presentation, fine to keep keyed on the *local* house |
| **Selection** | ~~`GameObject.isSelected`, `world.controlGroups`~~ | done: local UI state on `session.selection` (slice 2) |

## Plan

Each slice must leave the three `--determinism` digests unchanged.

1. **Commands carry their house** — *done.* `issue(_:as:)` queues a
   `QueuedCommand(house:command:)`; `apply` only moves the issuing house's live
   objects; the log records the house. Production, placement and super
   weapons still exist only for the player's house, so those commands from
   any other house are rejected until step 3 below.
2. **Selection out of the sim** — *done.* The simulation never reads
   selection (it isn't in `WorldDigest` and no mission/AI code touches it), so
   it moved to `session.selection` (`SelectionState`: selected ids + the ten
   control groups). It is the local player's — in lockstep each machine has
   only its own. `GameObject.isSelected`, `world.selectedObjects()` and
   `world.deselectAll()` remain as thin accessors over it so UI call sites
   are unchanged; saves still write/read the same fields.
3. **Per-house production and credits.** Move the two build queues and the
   player's credit balance onto `HouseState` (one queue pair per house, as
   `HouseClass` has its factories), make `session.sidebarCredits` a view of
   the local house's, and route the AI's production through the same queues.
   This touches credit timing for the AI, so expect to re-baseline only if
   the AI path's ordering can't be preserved; keep the player path bit-exact.
4. **`isHuman` instead of `!= playerHouse`** — *gating done.* The AI's
   "skip the human" checks and `initHouseStates` call `world.isHuman(_:)`
   (still `== playerHouse`); next it reads the player list. Left: the AI's
   targeting of "the player's" buildings and harvesters, which should become
   "an enemy human's".
5. **Per-house fog.** `fogState` per human house (the local one drives
   rendering); `houseVisibility` already exists for AI target acquisition.
6. **Win/lose per house.** A house loses when it has nothing left (the
   multiplayer rule, HOUSE.CPP `Flag_To_Lose`); campaign triggers keep
   deciding single-player.
7. **Local house.** Rename the remaining presentation reads (EVA, sounds,
   radar, sidebar) to `localHouse` — the `PlayerPtr` equivalent — so
   `playerHouse` stops meaning two things.

Steps 3–6 are prerequisites for skirmish (Phase 6 step 2); 7 is cosmetic.
