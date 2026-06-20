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
  unchanged (4000t `0xAD2FA4BFC4723E0A`), reset-check green.
- Next: T2 (multiple actions per trigger), then T3 (AND/OR events), T4 (regions).
