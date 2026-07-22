# OpenConquer — Roadmap

This is the north-star sequence, not a rigid schedule. It's ordered so the project becomes **publishable and contributable** as early as possible, then compounds. See [`VISION.md`](VISION.md) for the "why."

The phases map to three overlapping goals: **(A)** play it & build new missions, **(B)** open-source it, **(C)** parity + configurable classic/modified rules.

## Milestones (current sequencing)

The phases below are the taxonomy; these milestones are the *order of attack* as of July 2026:

- **M1 — Full campaign fidelity** *(in progress)* — close out Phase 2. **Done:** `IsPrebuilt` production gating (#6C), campaign branching (map selection + GDI sabotage skip), the 28-mission verification sweep and its 8 fix classes (incl. two real determinism breaks), reinforcement fidelity (Edge= entry, TeamType mission lists, loaner rules, A10 hunt, limbo untargetability), and the civ-evac win model (SCG11/12 winnable). **Remaining:** the classic1995 gating decision for the non-classic AI layer (see Phase 2 notes).
- **M2 — Contributor onramp** — close out Phase 0 + start the parity doc: issue templates, `good first issue` labels, a `PARITY.md` verified-vs-approximated checklist, README screenshots.
- **M3 — Linux port** — Phase 5: image-loading abstraction, data-dir abstraction, Linux CI leg.
- **M4 — Polish & packaging** — Phase 4: HD sidebar meters, unsigned `.app` bundle.

---

## Phase 0 — Open-source foundation  *(mostly done)*  → Goal B

Make it something a stranger can build, trust, and contribute to.

- [x] **LICENSE** — GPLv3.
- [x] **README** — what it is, requirements, asset-extraction walkthrough, disclaimer.
- [x] **CONTRIBUTING** — build, the determinism contract, conventions, "no assets" rule.
- [x] **VISION / ROADMAP** docs.
- [x] **CI** (GitHub Actions, macOS) — multi-Swift matrix (5.10 + 6.x) builds on every push/PR.
- [x] **Publish:** repo public at `DavidClawson/OpenConquer`, GPLv3, topics/description set.
- [x] **Streamlined asset installer** — `install-assets.sh` probes for a Remastered install, preflight-checks the containers, and runs every extraction step.
- [x] **Synthetic (asset-free) test fixtures** — 13 `--test-*` logic/determinism tests build their world in code and run in CI on both Swift versions.
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
  - [x] **Wave B (#6, C):** `IsPrebuilt` production gating — the AI's build deciders now compute team-template demand (`Suggest_New_Object` port, HOUSE.CPP:3166-3383) ahead of the personality pool, with faithful build-nothing semantics when demand is satisfied/unbuildable. Covered by `--test-prebuilt`. **Wave B complete.**

  **Mission-coverage scan** (via `--dump-scenario`, over the classic campaign INIs):
  - AllowWin gating (#3, fixed) is used by **SCB04–SCB07** — four Nod missions that previously won early.
  - Cap=Win/Des=Lose (#2, fixed) is used by **SCB03, SCB12**.
  - Enemy superweapon (#5, open) affects **SCG15** (final GDI, Nuke), **SCB12, SCB13** (Ion) — the weapon currently arms the player instead of the AI; needs per-house / AI superweapon support.
  - Autocreate (#1, fixed) appears in ~35 team definitions across both campaigns.
- [x] Campaign branching + scenario variants + the GDI SCG06 sabotage skip — `GameCampaignGraph.swift` (CountryArray transcription), a map-selection screen between missions, `SabotagedType` recording/skip/destroyed-at-start rules. Covered by `--test-campaign-graph`.
- [~] Verify all original GDI/Nod missions play through correctly. A 28-mission / 47-variant verification sweep (July 2026) found and fixed 8 classes of defect: Data=0 time triggers never firing (13 variants, incl. SCG07/SCG15 auto-losing and SCG10's dead enemy production), SCG06EA loading blank (INI decode), the 'Area Guard' mission spelling, volatile WinLose triggers consumed by the wrong event (SCB12), cell-trigger house matching + aircraft exclusion (SCB04/SCG09), Production/Autocreate house scope (SCB13/SCB12), damaging self-ignite fire anims (SCG12 scenery), and two real determinism breaks (SCB08 tiberium-tie hash order, SCB11 cosmetic-fire damage). **Remaining known gaps** (tracked for the next wave):
  - [x] **Reinforcement fidelity** (`GameReinforcements.swift`, July 2026): full REINF.CPP port — reinforcement teams enter from the owning house's `Edge=` (`calculatedEdgeCell`, seeded random edge pick) under a force-active team that executes the TeamType mission list; transports are loaners only when carrying cargo, so transport-only teams (SCG12's evac chopper, `gdi5=TRAN:1`) survive and fly their routes; team-less fixed-wing (A10 strikes) gets MISSION_HUNT (REINF.CPP:366-368); limboed cargo is untargetable and splash-immune in transit. Covered by `--test-reinforcements`; all three determinism baselines legitimately repinned (both baseline missions fire `Reinforce.` triggers in-window).
  - [x] **Civ-evac win model** (July 2026): full classic evacuation chain — player-ordered transport boarding (right-click a friendly APC/TRAN with infantry selected, `tickEnterTransport`); a civilian boarding a transport **aircraft** sends it straight off the map (RADIO_IM_IN → MISSION_RETREAT, AIRCRAFT.CPP:2530-2542); the off-map retreat exit sets the house `isCivEvacuated` flag and removes evacuees as a classic *delete* (no Destroyed-trigger spring, AIRCRAFT.CPP:836-855); the `Civ. Evac.` event polls the flag (HOUSE.CPP:1257). SCG11 (Delphi) and SCG12 (Mobius) are now winnable. Covered by `--test-civ-evac`; determinism baselines unchanged.
  - **Non-classic AI layer gating**: rally/idle-aggro/attack-waves/production-timeout (`GameAI.swift`) run ungated under `classic1995` and override scripted mission pacing (SCB08/SCB10/SCB12) — needs a ruleset decision.
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
