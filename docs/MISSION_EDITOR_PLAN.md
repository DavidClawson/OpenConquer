# Mission Editor — Tier-1 (RA1-level) plan

Target expressive ceiling (chosen 2026-06): **faithful classic TD triggers, plus**
AND/OR/LINKED two-event combining, multiple actions per trigger, per-instance
object flags (invulnerable / must-survive / owner-change), and named region
zones. Everything is **backward-compatible**: classic `.INI` missions load and
round-trip unchanged; Tier-1 features live in *new* INI sections a classic engine
simply ignores.

See `docs/B3_B4_PLAN.md` Part C for the original editor design (EditorScenario
document + INIWriter), and `docs/IMPROVEMENT_PLAN.md` for the trigger model this
extends.

## Why this is now feasible

Two things this engine has that the 1994 one didn't:
- **Deterministic simulation** (seeded `gameRng`, headless harness) — the editor
  can fast-forward a mission headlessly to verify triggers actually fire.
- **The decide/apply AI seam** (B3) — missions can eventually *script* AI goals,
  not just spawn blobs.

## The classic model we're extending (recap)

A trigger is `Name = Event, Action, Data, House, Team, Persistence` in
`[Triggers]`. One event → one action, 3 persistence modes (volatile /
semi-persistent / persistent), attached to a cell, an object, or a house. ~17
events, ~17 actions. No boolean logic, no per-instance flags. Faithfully mirrored
in `Game/GameTrigger.swift`.

## Backward-compatible storage strategy

Classic sections stay **byte-for-byte classic**. Tier-1 additions are new
sections keyed so a classic loader ignores them:

- `[ObjectFlags]` — per-instance flags, keyed by **cell** (the stable positional
  identity of a placed object in a TD INI):
  ```ini
  [ObjectFlags]
  2310 = Invulnerable
  2048 = MustSurvive
  1900 = Invulnerable,MustSurvive
  ```
- `[TriggersEx]` — per-trigger extension keyed by **trigger name**, carrying the
  optional second event + combine mode + extra actions. A trigger with no
  `[TriggersEx]` entry is exactly classic:
  ```ini
  [TriggersEx]
  TR04 = Event2=Time:300; Control=AND; Action2=Reinforcements:BadTeam
  ```
- `[Regions]` — named rectangular / waypoint-radius zones:
  ```ini
  [Regions]
  beachhead = rect,30,40,8,6        ; x,y,w,h in cells
  lz = wp,25,5                      ; waypoint 25, radius 5 cells
  ```

A classic-only round-trip never emits these sections; a Tier-1 mission emits them
in addition to the classic ones.

## Phased build order

Each engine phase keeps `--determinism` / `--reset-check` green (the new feature
is absent from classic scenarios, so the digest is unchanged) and adds a focused
headless self-test that exercises the feature.

- **T1 — per-instance flags (invulnerable, must-survive).** `GameObject`
  fields + damage-chokepoint guard + must-survive lose-check + `[ObjectFlags]`
  parse in `GameInit`. Directly fixes the "units that can't be killed" gap.
  Self-test: `--test-flags`. *(this phase)*
- **T2 — multiple actions per trigger.** Refactor `GameTrigger.action` → an
  action list; `[TriggersEx]` `Action2..N`; `fireTrigger` loops. Classic single
  action = a 1-element list.
- **T3 — two-event AND/OR/LINKED.** Add `event2` + `eventControl` + per-event
  latch state; fire when the combination is satisfied. `[TriggersEx]` `Event2` /
  `Control`.
- **T4 — region zones.** `[Regions]` parse + `EVENT_ENTERED_REGION` /
  `EVENT_LEFT_REGION`; replaces single-cell enter triggers with areas.
- **T5 — owner-change / capture flag** (optional within Tier-1).

Then the **editor track** (depends on T1–T4 for the data model):
- **E0** — pure passability refactor (placement validation without a live world;
  from B4 plan).
- **E1** — `EditorScenario` document + classic INI **round-trip** (load → model →
  save; byte-comparable on stock campaign missions) + `INIWriter` + the Tier-1
  section writers.
- **E2** — edit commands + validation. **E3–E6** — map/object/trigger UI +
  play-test launch. (E7 AI-preview is Tier-3, deferred.)

## Status

- **T1 done + verified:** `GameObject.isInvulnerable` / `mustSurvive`; invuln
  guard in `applyDamage` (GameCombat.swift); must-survive lose-check in the
  removal loop (GameLoop.swift); `[ObjectFlags]` parse keyed by cell in
  `GameInit`. Self-test `--test-flags SCG01EA` PASS (invuln object ignores 99999
  damage; killing a must-survive object sets win state .lost). Determinism
  unchanged at T1 time. (Baselines later moved by the 2026-06-30 LST walk-off
  fix — current `--determinism` baselines: SCG01EA 2500t `0xD1596F2E7234204A`,
  4000t `0x9D62132321684A74`, SCB01EA 4000t `0xC6BACBDF0518D5B7`. See
  `docs/IMPROVEMENT_PLAN.md` Part A status.)
- **E1 done + verified:** the editor data layer / round-trip foundation.
  `INIFile` gained a serializer (`serialize()`), mutation API (`setEntries`/
  `setValue`/`removeSection`), and original-header-casing preservation
  (`Assets/INIFile.swift`). New `EditorScenario` document
  (`Scenario/EditorScenario.swift`) regenerates the lossless entity sections
  (STRUCTURES/UNITS/INFANTRY/OVERLAY/CellTriggers/Base) from the typed model with
  exact classic comma layouts (inverse of the loader), and passes through every
  other section verbatim from the source `INIFile` (TERRAIN/Waypoints — lossy in
  the typed model — plus Triggers/TeamTypes/house blocks/Map/Briefing/Tier-1).
  `loadScenario` was split so `parseScenarioData(ini:name:)` can re-parse
  serialized text. `EditorScenario.save(toPath:)` writes a loose `.INI` (MIX is
  read-only). Gate `--editor-roundtrip <SCEN>` proves load → document → INI →
  re-parse equals the original typed model, serialize-twice is idempotent, and a
  programmatic edit (move a unit) survives the cycle with other sections intact.
  **28/28 stock campaign missions pass.** Sim untouched (determinism + reset-check
  green). The per-section Tier-1 writers ([TriggersEx]/[Regions]) fold into T2–T4
  as each defines its data model; existing Tier-1 sections already pass through.
- **T2 done + verified:** multiple actions per trigger. `GameTrigger.action`
  became `var actions: [TriggerActionSpec]` (`{action, teamName?}`); the classic
  `[Triggers]` line seeds `actions[0]`, and `[TriggersEx]` `Action2..N` (parsed
  by `parseTriggersEx`, called from `parseTriggers`) append more, sorted by N.
  `fireTrigger` extracted its action switch into `executeTriggerAction(spec:)`
  and loops over `actions`; team-based actions use the spec's `teamName` (falling
  back to the trigger's). `action` kept as a computed accessor (`actions[0]`).
  Self-test `--test-triggers-ex` (parse: TR1 gains a 2nd action, classic TR2
  keeps one; execute: firing TR1 runs both allowWin+win). Classic scenarios have
  no `[TriggersEx]` → one action, byte-identical: determinism baselines unchanged
  (SCG01EA 2500t `0xD1596F2E7234204A`, SCB01EA 4000t `0xC6BACBDF0518D5B7`).
- **T3 done + verified:** two-event AND/OR/LINKED combining. `GameTrigger` gained
  `event2`/`data2`/`eventControl` + per-event latches (`e1/e2Satisfied`);
  `EventControl` is `.only`(classic)/`.or`/`.and`/`.linked` (linked ≈ and for
  Tier-1). The per-tick poll was refactored: `polledEventReady` (pure condition
  check for the non-time polled events) + `evaluateTriggerEvent` (handles the
  `.time` countdown inline, per-event via data/data2) + `registerEventSatisfied`
  (the combine gate: ONLY fires on event1 exactly as before, OR on either, AND/
  LINKED once both latched). All fire sites (`tickTriggers`, `springTrigger`,
  `checkCellTriggers`, `springTriggerBuiltIt`) route through
  `registerEventSatisfied` and match event2. `[TriggersEx]` now parses
  `Event2=Name[:Data]` and `Control=AND|OR|ONLY|LINKED`. Self-test
  `--test-two-event` (AND fires only after both events; OR fires on either).
  Classic single-event triggers (`Control=ONLY`, the only case in stock data)
  fire bit-for-bit identically: all three determinism baselines unchanged
  (SCG01EA 2500t `0xD1596F2E7234204A`, 4000t `0x9D62132321684A74`, SCB01EA 4000t
  `0xC6BACBDF0518D5B7`).
- **T4 done + verified:** region (area) zones. New `ScenarioRegion`
  (rect `x,y,w,h` or `wp,waypoint,radius`) parsed from `[Regions]` into
  `session.scenarioRegions`; new `TriggerEvent` cases `.enteredRegion`/
  `.leftRegion` ("Enter Region"/"Leave Region"); `GameTrigger.regionName` (from
  `[TriggersEx]` `Region=`) + `regionOccupied` latch. `tickRegionTriggers` (run
  each tick from `gameTick`, after `tickTriggers`) fires Enter/Leave on the
  occupancy transition for units of the trigger's house, routing through
  `registerEventSatisfied` (so region events compose with AND/OR too).
  `parseRegions` primes occupancy at load so a unit that *starts* inside doesn't
  spuriously fire Enter. Self-test `--test-regions` (outside=no fire, enter→win,
  leave→lose). Inert without a `[Regions]` section, so classic missions are
  unchanged: determinism baselines (SCG01EA 2500t `0xD1596F2E7234204A`, SCB01EA
  4000t `0xC6BACBDF0518D5B7`) and reset-check green.
- **Tier-1 engine (T1–T4) complete.** Remaining: T5 (owner-change/capture,
  optional) and the editor UI track (E2–E6) + per-section Tier-1 writers in the
  EditorScenario document (so the editor can author [TriggersEx]/[Regions], not
  just pass them through).
