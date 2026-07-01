# Contributing to OpenConquer

Thanks for your interest! OpenConquer is an unofficial, faithful macOS reimplementation of *Command & Conquer: Tiberian Dawn*. This guide covers how to build, how the test harness works, and the conventions that keep the project healthy.

## Ground rules

- **Never commit game assets.** No `.MIX`, `.SHP`, `.AUD`, `.VQA`, `.PAL`, extracted PNG/WAV, or any Electronic Arts content. Assets are the user's own, extracted locally. `.gitignore` blocks the common formats, but be careful.
- **License:** by contributing you agree your contributions are licensed under the project's **GPLv3**.
- **Match the original.** When implementing a behavior, cross-check EA's released C++ (see *Reference sources* below) and cite the file/line in a comment where a choice mirrors the original — the existing code already does this (e.g. `// mirrors building.cpp:560-634`).

## Build

```bash
brew install sdl2 pkg-config
swift build          # debug
swift build -c release
swift run            # build + launch
```

- Target: **macOS 13+**, swift-tools **5.9** (language mode 5).
- SDL2 is wired via the `CSDL2` system-library target (pkg-config `sdl2`).
- **Swift version range:** CI builds on a matrix of **Swift 5.10** (macos-14) and
  **Swift 6.x** (macos-15), so keep code compatible with both — avoid Swift 6-only
  stdlib APIs (e.g. `Sequence.count(where:)`; use `filter{}.count`). We do **not**
  use the Swift 6 language mode (strict concurrency); this is a single-threaded,
  deterministic sim built on global state, so strict concurrency is all cost and
  no benefit here.

## The determinism contract (please read)

The simulation is **deterministic given a seed** — identical across separate processes and across two `initGameWorld` calls in one process. This is the project's safety net: it lets contributors change gameplay code without fear, because a change that unintentionally perturbs the simulation shows up immediately as a changed digest.

```bash
# 3 clean subprocess trials, assert identical digest (the regression net):
./.build/debug/TiberianDawnMax --determinism SCG01EA 2500
./.build/debug/TiberianDawnMax --determinism SCG01EA 4000
./.build/debug/TiberianDawnMax --determinism SCB01EA 4000

# Print a state digest for a run (stableSeed — NOT comparable to --determinism):
./.build/debug/TiberianDawnMax --headless SCG01EA 600

# Focused behavior self-tests:
./.build/debug/TiberianDawnMax --test-repair   SCG01EA
./.build/debug/TiberianDawnMax --test-crush    SCG01EA
./.build/debug/TiberianDawnMax --test-fogpath  SCG01EA
./.build/debug/TiberianDawnMax --test-stacking SCG01EA
./.build/debug/TiberianDawnMax --test-harvester-economy
./.build/debug/TiberianDawnMax --test-flags    SCG01EA
```

Rules of thumb:
- **Simulation randomness** (anything mutating world/object/house/AI state during `gameTick`) MUST use the seeded helpers in `Game/GameRandom.swift` (`rndInt`/`rndDouble`/`rndBool`/`.rndElement()`), never `Int.random(...)`.
- **Cosmetic randomness** (screen shake, debris/explosion offsets, sprite flicker, audio, menus) deliberately stays on the system RNG and must **not** use the seeded helpers.
- If your change *intentionally* alters the simulation, the digest will change — re-run `--determinism` to confirm it's still deterministic (all 3 trials match), then update the documented baselines in `CLAUDE.md`, explaining why in your PR.
- Interactive-only features (e.g. fog-aware pathfinding) are gated so headless/AI stay omniscient and baselines hold. Keep it that way.

> **CI note:** the determinism/`--test-*` flags load scenarios, which require game assets, so they run **locally**, not in CI. Continuous integration currently verifies that the project builds. A near-term roadmap item is a set of tiny synthetic (asset-free) fixtures so logic tests can also run in CI.

## Code conventions

- **Architecture:** a single global `session: GameSession` owns all mutable state via nested containers (`world`, `production`, `scripting`, `combat`, `campaign`). Game objects are a single `GameObject` **class**; behavior is attached via `extension GameObject` blocks in topically-appropriate `Game/*.swift` files.
- **Fixed-tick loop:** the sim runs at a fixed 15 FPS (`Game/GameLoop.swift`), decoupled from render FPS; rendering interpolates. `gameTick()` phase order is load-bearing (= RNG-consumption order) — don't reorder or fuse phases; re-verify `--determinism` after touching it.
- **New behavior** goes in an `extension GameObject` in the right `Game/` file, not a catch-all.
- **Split files on contact,** not in dedicated passes: if you're editing a file that's crossed ~800 lines or clearly mixes two concerns, split it along its natural seam as part of that work.
- Prefer guards over force-unwraps.

See [`CLAUDE.md`](CLAUDE.md) for a deeper architecture guide and current status.

## Reference sources (read-only, not bundled)

These are EA's GPLv3 releases, kept alongside the repo as behavior references — not part of the build and not redistributed here:

- **`../CnC_Tiberian_Dawn/`** — the original Westwood C++ (UNIT.CPP, BUILDING.CPP, CELL.CPP, MAP.CPP, CONST.CPP, …). The authoritative behavior reference.
- **`../Vanilla-Conquer/`** — the modern open-source port; cleaner C++, good for cross-checking constants and frame layouts.

Before guessing at a behavior, grep the C++ for the relevant `Mission_*`, `LAND_*`, `BSTATE_*`, or data table.

## Good places to start

- **Data/rules** (no deep Swift needed): unit/structure stat tables, mission INI tuning, and — once the ruleset layer lands — classic-vs-enhanced toggle values.
- **Missions:** authoring or fixing campaign scenarios and triggers.
- **Bugs:** anything labeled `good first issue`.

## Pull requests

1. Branch from the default branch.
2. Keep changes focused; explain gameplay-affecting changes and any baseline updates.
3. Run `swift build` and the relevant `--determinism` / `--test-*` checks locally before pushing.
4. No assets, ever.
