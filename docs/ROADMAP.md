# OpenConquer — Roadmap

This is the north-star sequence, not a rigid schedule. It's ordered so the project becomes **publishable and contributable** as early as possible, then compounds. See [`VISION.md`](VISION.md) for the "why."

The phases map to three overlapping goals: **(A)** play it & build new missions, **(B)** open-source it, **(C)** parity + configurable classic/modified rules.

---

## Phase 0 — Open-source foundation  *(in progress)*  → Goal B

Make it something a stranger can build, trust, and contribute to.

- [x] **LICENSE** — GPLv3.
- [x] **README** — what it is, requirements, asset-extraction walkthrough, disclaimer.
- [x] **CONTRIBUTING** — build, the determinism contract, conventions, "no assets" rule.
- [x] **VISION / ROADMAP** docs.
- [x] **CI** (GitHub Actions, macOS) — builds on every push/PR.
- [ ] **Publish:** rename the GitHub repo to `OpenConquer`, flip to public, add topics/description.
- [ ] **Streamlined asset installer** — one guided script that points at a Remastered install and runs all extraction steps, with a clear preflight error when assets are missing.
- [ ] **Synthetic (asset-free) test fixtures** so a subset of logic/determinism tests can run in CI.
- [ ] Issue templates, `good first issue` labels, screenshots/GIFs in the README.

## Phase 1 — Ruleset layer  *(starting)*  → Goals C, A, B

The architectural linchpin. Pull tunable behavior out of code and into data.

- [ ] Define a `Ruleset` model + a canonical **`Classic1995`** ruleset (the pinned, determinism-tested baseline).
- [ ] Named presets (`Enhanced`, …) and per-toggle overrides.
- [ ] **First proof: veterancy toggle** (off in `Classic1995`).
- [ ] Fold existing modern toggles (window size, zoom, fog-aware pathfinding) into the same system.
- [ ] In-game **Options** screen to pick a preset / flip toggles.
- [ ] Determinism becomes **per-ruleset**: `Classic1995` stays pinned; modified rulesets carry their own baselines or are exempt.

## Phase 2 — Missions & triggers  → Goals A, C

Faithful campaign replay *and* the ability to author new missions.

- [ ] Harden scenario INI + the trigger/team system to original fidelity (leverage the existing `--editor-roundtrip` check).
- [ ] Verify all original GDI/Nod missions play through correctly.
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
