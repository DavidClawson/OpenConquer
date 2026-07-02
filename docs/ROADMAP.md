# OpenConquer — Roadmap

This is the north-star sequence, not a rigid schedule. It's ordered so the project becomes **publishable and contributable** as early as possible, then compounds. See [`VISION.md`](VISION.md) for the "why."

The phases map to three overlapping goals: **(A)** play it & build new missions, **(B)** open-source it, **(C)** parity + configurable classic/modified rules.

---

## Phase 0 — Open-source foundation  *(mostly done)*  → Goal B

Make it something a stranger can build, trust, and contribute to.

- [x] **LICENSE** — GPLv3.
- [x] **README** — what it is, requirements, asset-extraction walkthrough, disclaimer.
- [x] **CONTRIBUTING** — build, the determinism contract, conventions, "no assets" rule.
- [x] **VISION / ROADMAP** docs.
- [x] **CI** (GitHub Actions, macOS) — multi-Swift matrix (5.10 + 6.x) builds on every push/PR.
- [x] **Publish:** repo public at `DavidClawson/OpenConquer`, GPLv3, topics/description set.
- [ ] **Streamlined asset installer** — one guided script that points at a Remastered install and runs all extraction steps, with a clear preflight error when assets are missing.
- [ ] **Synthetic (asset-free) test fixtures** so a subset of logic/determinism tests can run in CI.
- [ ] Issue templates, `good first issue` labels, screenshots/GIFs in the README (screenshots: awaiting user PNGs in `docs/screenshots/`).

## Phase 1 — Ruleset layer  *(mostly done)*  → Goals C, A, B

The architectural linchpin. Pull tunable behavior out of code and into data.

- [x] Define a `Ruleset` model + a canonical **`Classic1995`** ruleset (the pinned, determinism-tested baseline) — `Game/GameRules.swift`.
- [x] Named presets (`Enhanced`) and per-toggle fields.
- [x] **First proof: veterancy toggle** (off in `Classic1995`, gated at `GameObject.veteranLevel`).
- [x] Fold fog-aware pathfinding into the ruleset (`fogAwarePathfinding`). *(window size / zoom are runtime view settings, not sim rules — intentionally left out.)*
- [x] In-game **Options** screen to pick a preset (`UI/OptionsScreen`, `MenuRenderer.makeRulesetButtons`).
- [x] Determinism is **per-ruleset**: `Classic1995` stays pinned; `.enhanced` carries its own (or is exempt).
- [ ] Per-toggle overrides on top of a preset (e.g. Classic + just fog pathfinding) — currently preset-level only.
- [ ] Expand the toggle vocabulary (more classic-vs-modified knobs as parity work surfaces them).

## Phase 2 — Missions & triggers  *(in progress)*  → Goals A, C

Faithful campaign replay *and* the ability to author new missions. A full
trigger/team/campaign fidelity audit against the EA C++ has been done; the gaps
below are tracked as Wave A (landed) and Wave B (remaining).

- [~] Harden scenario INI + the trigger/team system to original fidelity (leverage the existing `--editor-roundtrip` check).
  - [x] **Wave A:** `IsAutocreate` parse fix (enemy attack waves); AllowWin/Blockage win-gating (no more premature wins, covered by `--test-wingate`); `BeginProduction` scoped to the trigger's own house.
  - [x] **Wave B (#2):** `WinLose` (Cap=Win/Des=Lose) now branches on the firing event — DESTROYED→lose, capture (PLAYER_ENTERED)→win. Firing event threaded through `fireTrigger`/`executeTriggerAction`; building capture springs the trigger. Covered by `--test-winlose`.
  - [x] **Wave B (#5):** `Nuke`/`Ion` arm the owning house (Nod/GDI), not the player; and the enemy now **charges and fires** its trigger-granted superweapon at the player's highest-value building (per-house `HouseState.superWeapons`, one-time + force-charged, mirrors HouseClass::AI). Fixes SCG15/SCB12/SCB13. Covered by `--test-enemy-superweapon`.
  - [x] **Wave B (#7):** `InitNum`-at-start team spawning is now ruleset-gated — `classic1995` skips it (faithful; InitNum is editor-only in classic TD), `enhanced` keeps it. Covered by `--test-initteams`.
  - [x] **Wave B (#9):** event-detection parity — Built It matches the specific target structure (was: any structure → wrong wins); NoFactories ignores the Construction Yard; all/units-destroyed exclude gunboat/transport/cargo/A-10 (HOUSE.CPP scan masks). Covered by `--test-eventparity`.
  - [x] **Wave B (#6, A+B):** AI team-creation model — a `Suggested_New_Team`-scored regular former (RecruitPriority, MaxAllowed cap, owned-type check) plus an alerted burst; `isAlerted` wired from the Autocreate trigger. Replaces the old flat every-675-tick random pick. Covered by `--test-team-former`; decide phase stays pure (`--ai-parity`).
  - [ ] **Wave B (#6, C — deferred):** `IsPrebuilt` production gating (pre-build units to fill team templates) — the highest-risk composition change; fold into the build deciders as a follow-up.

  **Mission-coverage scan** (via `--dump-scenario`, over the classic campaign INIs):
  - AllowWin gating (#3, fixed) is used by **SCB04–SCB07** — four Nod missions that previously won early.
  - Cap=Win/Des=Lose (#2, fixed) is used by **SCB03, SCB12**.
  - Enemy superweapon (#5, open) affects **SCG15** (final GDI, Nuke), **SCB12, SCB13** (Ion) — the weapon currently arms the player instead of the AI; needs per-house / AI superweapon support.
  - Autocreate (#1, fixed) appears in ~35 team definitions across both campaigns.
- [ ] Campaign branching + scenario variants + the GDI SCG06 sabotage skip (replace the linear `advanceMission`).
- [ ] Verify all original GDI/Nod missions play through correctly (needs a mission-coverage scan over the scenario INIs).
- [ ] Mission authoring path (hand-authored INI first; in-game editor per `docs/MISSION_EDITOR_PLAN.md` later).
- [ ] Let a mission declare its ruleset.

## Phase 3 — Parity hardening  → Goal C  *(ongoing)*

- [ ] Drive unit/structure/weapon/economy tables from the original data with cited C++ line refs.
- [ ] A **parity checklist** doc: what's verified vs. approximated.
- [ ] Tighten combat, harvesting, production, and AI feel against the reference.
- [ ] (Deferred) A3 stage-2 speed-cost weighting in A* pathfinding.

## Phase 4 — Presentation polish  → Goals A, B

- [x] HD cursors wired in (`Rendering/GameCursorHD.swift`).
- [ ] Wire the extracted HD **sidebar power/progress meters** (art already extracted to `ui/sidebar/`).
- [ ] Options UI polish; classic-vs-HD art toggle.
- [ ] Friendlier packaging: an unsigned `.app` to start; notarized build later (needs an Apple Developer account).

## Phase 5 — Cross-platform (Linux)  → Goal B

Assessed and tractable: the **only** Apple-specific code is PNG→texture decoding in `Assets/RemasteredSprites.swift` (CoreGraphics/ImageIO). Everything else is `CSDL2` + `Foundation`, both cross-platform.

- [ ] Swap ImageIO → SDL_image (or stb_image) behind a small image-loading abstraction.
- [ ] Abstract the data directory (`~/Library/Application Support/…`) per platform.
- [ ] Linux CI + build instructions.
- [ ] (Stretch) Windows via the swift.org toolchain.

## Explicitly deferred / out of scope

- Multiplayer / netcode.
- Red Alert and later titles.
- Any bundling of assets.
