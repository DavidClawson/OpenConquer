# OpenConquer — Roadmap

This is the north-star sequence, not a rigid schedule. It's ordered so the project becomes **publishable and contributable** as early as possible, then compounds. See [`VISION.md`](VISION.md) for the "why."

The phases map to three overlapping goals: **(A)** play it & build new missions, **(B)** open-source it, **(C)** parity + configurable classic/modified rules.

## Milestones (current sequencing)

The phases below are the taxonomy; these milestones are the *order of attack* as of July 2026:

- **M1 — Full campaign fidelity** *(complete — July 2026)* — closed out Phase 2's fidelity track: `IsPrebuilt` production gating (#6C), campaign branching (map selection + GDI sabotage skip), the 28-mission verification sweep and its 8 fix classes (incl. two real determinism breaks), reinforcement fidelity (Edge= entry, TeamType mission lists, loaner rules, A10 hunt, limbo untargetability), the civ-evac win model (SCG11/12 winnable), and the enhanced-AI ruleset gate (`classic1995` = scripted, trigger/teamtype-driven AI only).
- **M2 — Contributor onramp** *(in progress — one item left)* — close out Phase 0 + start the parity doc: ~~issue templates~~ ✅, ~~`PARITY.md` verified-vs-approximated checklist~~ ✅, ~~labels + starter issues~~ ✅. Remaining: **README screenshots** (needs PNGs in `docs/screenshots/` — press **⌘S** in-game to capture).
- **M3 — Linux port** — Phase 5: image-loading abstraction, data-dir abstraction, Linux CI leg.
- **M4 — Polish & packaging** *(mostly done)* — Phase 4: ~~unsigned `.app` bundle~~ ✅, ~~first-run setup screen~~ ✅, ~~DMG~~ ✅ (Sept 2026). ~~HD sidebar meters (#1)~~ ✅. Remaining: notarization is blocked on a paid Apple Developer account.
- **M5 — Classic presentation** *(in progress — Oct 2026)* — the 1995 front end around the campaign: ~~CPS/WSA/PAL decoders~~ ✅, ~~VQA movie decoder~~ ✅, ~~movie player~~ ✅ (startup logo; intro/briefing/action before each campaign mission, win/lose after, intro/action on retry — per the scenario INI and Start_Scenario; Off/Pixels/Smooth/Enhanced setting), ~~the animated map-selection screen~~ ✅ (grey globe → colour → spin and zoom → territory dissolves → flashing crosshairs → click-map pick → country stats, MAPSEL.CPP; plain-list fallback without the art), ~~the title screen and main menu~~ ✅ (Win95 HTITLE.PCX with Main_Menu's dialog and buttons, our Options and Developer Tools in the classic style), ~~choose your side~~ ✅ (CHOOSE.WSA with the side's first movie, GDI1 / NOD1PRE), straight from the briefing movie into the mission (the text briefing only when no movie plays), ~~the end-of-mission score screen~~ ✅ (SCORE.CPP's leadership / efficiency / total arithmetic, count-ups, GDI bar graphs, Nod's firing-squad and exploding-yard graphs, ending credits, and the hall of fame with name entry; after every won campaign mission but each side's last, before map selection). Optional live movie upscaling via Apple's low-latency super-resolution (see Phase 4).
- **M6 — Multiplayer groundwork** *(planned — after M5)* — Phase 6, steps 1–2: per-player state and skirmish vs. the computer on the original multiplayer maps. Each step is useful alone; networking (steps 3–4) follows once these hold.

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
- [x] **Issue + PR templates** — `.github/ISSUE_TEMPLATE/` (bug / parity gap / feature, each steering toward `PARITY.md` and the ruleset rules) and a PR template that gates on the determinism digests and the no-assets rule.
- [x] **Labels + starter issues** — `parity` / `determinism` / `ruleset` / `rendering` labels, and 7 seeded issues (#1-#7) covering the open `PARITY.md` rows: HD sidebar meters, Stealth Tank cloaking, splash falloff, sell refund, multi-factory acceleration, the installment build model, and the data-table citation pass. Six are `good first issue`.
- [ ] Screenshots/GIFs in the README (awaiting PNGs in `docs/screenshots/`).

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
  - [x] **Non-classic AI layer gating** (July 2026): the enhanced enemy-AI layer is now a ruleset toggle (`Ruleset.enhancedEnemyAI`) that is OFF in `classic1995` — rally raids, idle-army attack waves, the 5-minute escalation, the tactics suite, damaged retreat, the 3-minute production auto-enable, the personality-pool production fallback, and free-form base building are enhanced-only. Classic missions are paced purely by triggers/teamtypes (production starts only via the Production trigger, HOUSE.CPP:1892); the faithful AI paths (guard/turret targeting, hunt, Suggested_New_Team former, Suggest_New_Object demand production) stay on. Covered by `--test-ai-gating`; determinism baselines repinned.
- [ ] Mission authoring path (hand-authored INI first; in-game editor per `docs/MISSION_EDITOR_PLAN.md` later).
- [ ] Let a mission declare its ruleset.

## Phase 3 — Parity hardening  → Goal C  *(ongoing)*

- [ ] Drive unit/structure/weapon/economy tables from the original data with cited C++ line refs.
- [x] A **parity checklist** doc: what's verified vs. approximated — [`PARITY.md`](PARITY.md), covering determinism, data tables, combat, movement, economy, production, fog, triggers/scenarios, AI, superweapons, save/load, and the deliberate `enhanced` deviations.
- [ ] Tighten combat, harvesting, production, and AI feel against the reference.
- [ ] (Deferred) A3 stage-2 speed-cost weighting in A* pathfinding.

## Phase 4 — Presentation polish  → Goals A, B

- [x] HD cursors wired in (`Rendering/GameCursorHD.swift`).
- [x] Wire the extracted HD **sidebar power/progress meters** (`Rendering/SidebarHD.swift`, modern sidebar; procedural fallback).
- [ ] Options UI polish; classic-vs-HD art toggle.
- [ ] **Movie upscaling** (M5). Remastered's HD movies are Bink 2 (no open decoder) and redistributing upscaled footage is off the table (EA's IP), so any enhancement runs locally on the user's own `MOVIES.MIX`. Findings from an Oct 2026 experiment (M1 Max, 320×156 TD movies, 4×):
  - **Apple low-latency super-resolution** (`VTLowLatencySuperResolutionScalerConfiguration`, macOS 26+) — **shipped as the Enhanced movie mode** (`Rendering/MovieFrameEnhancer.swift`, ~10 ms/frame on the render thread): built into the OS, no model to ship, ~19 fps including PNG I/O so it can run live during playback; conservative (slightly crisper than bicubic, no hallucinated detail). Supports 1.5×/2×/4× at 320×156; needs the configuration's own `sourcePixelBufferAttributes`/`destinationPixelBufferAttributes` (plain BGRA buffers fail with -19730), and the Swift `VTFrameProcessor.process(parameters:)` returns a lazy `AsyncSequence` that must be iterated.
  - **Real-ESRGAN** (BSD, `realesrgan-ncnn-vulkan`) — great on the pre-rendered CGI cutscenes, uncanny on the live-action faces; `x4plus` ~1.7 fps (batch only), `animevideov3` ~13 fps (waxy). Candidate for an opt-in "Enhance (experimental)" batch mode.
  - [ ] **Re-investigate Apple's downloadable high-quality model** (`VTSuperResolutionScalerConfiguration`, 4× only). The model downloads and reports `.ready`, and processing "succeeds", but every output buffer came back all zeros — in video mode, image mode, and with 640×312 input. Might be our usage or an early-API issue; retry on later macOS releases. If it works it could replace Real-ESRGAN for the batch mode and improves with OS updates. Probe: `tools/experiments/vt_superres_probe.swift`.
- [~] Friendlier packaging.
  - [x] **`.app` bundle** — `tools/make-app.sh` produces `dist/OpenConquer.app`: SDL dylibs vendored into the bundle with `@rpath` load paths, generated icon (`tools/make_icon.py`, drawn procedurally — no game art), `Info.plist`, ad-hoc signature, and a smoke test that runs the bundled binary's asset-free self-test. Runs on a Mac with no Homebrew and no Swift toolchain. `OPENCONQUER_DATA_DIR` overrides the asset location.
  - [x] **First-run experience** — `UI/SetupScreen.swift` replaces the blank window with a setup screen when no MIX archives load: what's missing, the exact path checked (flagged when it came from an override), the extraction command, and a RETRY that re-runs discovery in place. Asset-free by construction — SDL primitives and the built-in pixel font, whose glyph table gained the punctuation needed to render a path.
  - [x] **Disk image** — `make-app.sh --dmg` builds the drag-to-Applications image (~2.5 MB) with a READ ME covering the right-click-to-open step and the no-assets policy.
  - [ ] Notarized build (needs a paid Apple Developer account); until then first launch needs right-click → Open.

## Phase 5 — Cross-platform (Linux)  → Goal B

Assessed and tractable: the **only** Apple-specific code is PNG→texture decoding in `Assets/RemasteredSprites.swift` (CoreGraphics/ImageIO). Everything else is `CSDL2` + `Foundation`, both cross-platform.

- [ ] Swap ImageIO → SDL_image (or stb_image) behind a small image-loading abstraction.
- [ ] Abstract the data directory (`~/Library/Application Support/…`) per platform.
- [ ] Linux CI + build instructions.
- [ ] (Stretch) Windows via the swift.org toolchain.

## Phase 6 — Multiplayer  → Goals A, B  *(planned)*

Lockstep, like the original, Red Alert and OpenRA: every machine runs the full
simulation and players exchange only their orders ("tick 512: player 2 moves
these units here"), so traffic is tiny and replays/spectating come almost free.
The two hard prerequisites already exist: the sim is deterministic given a seed
(`--determinism`, CI), and all input flows through logged, replayable
`PlayerCommand`s (`--test-command-replay`).

What still assumes a single human (as of Oct 2026):
- **Selection** lives in the sim (`GameObject.isSelected`, `world.selectedObjects()`) — it must become per-player UI state.
- **`playerHouse`** is referenced ~95 times across 27 Core files: fog, sidebar/production queues, credits, win/lose all assume one human house.
- **Commands carry no sender** — each `PlayerCommand` needs its issuing house, and `apply` must validate ownership against it.
- **Cross-machine determinism:** the sim uses `Double` math (and ~17 libm calls: sin/cos/atan2/…). Same build on Macs should agree; Mac↔Linux may drift (most RTS engines use fixed point). Detect drift by exchanging `WorldDigest` every N ticks and stopping on mismatch.

Steps (each useful on its own):
1. [ ] **Per-player state** — commands carry their house; selection out of the sim; per-house fog, production, credits, win/lose.
2. [ ] **Skirmish vs. AI** on the original multiplayer maps (`SCM*.INI`, in GENERAL.MIX) — exercises the multi-house plumbing with no networking.
3. [ ] **Two-player lockstep** over direct IP / LAN (Tailscale works among friends): input delay of a few ticks, per-tick command exchange, digest-based desync detection; saved replays fall out of this.
4. [ ] **Lobby and connectivity** — a small relay server and invite codes instead of IP addresses / port forwarding. (Game Center would need the paid Apple Developer account, like notarization.)

Every player installs their own game data, as today — nothing changes about the no-assets rule.

## Explicitly deferred / out of scope

- Multiplayer *beyond* Phase 6 (matchmaking services, ranked play, more than a handful of players).
- Red Alert and later titles.
- Any bundling of assets.
