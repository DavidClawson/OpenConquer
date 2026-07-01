# OpenConquer — Vision

## One sentence

A **native macOS (and eventually cross-platform), faithful reimplementation** of *Command & Conquer: Tiberian Dawn* with **modern presentation** and a **data-driven, moddable** core.

## The gap we fill

| Option | Native Mac | Faithful to original | Modern QoL | Moddable |
|---|:---:|:---:|:---:|:---:|
| C&C Remastered Collection | ❌ (Windows-only) | ✅ | ✅ | limited |
| OpenRA | ✅ | ❌ (reinterpreted) | ✅ | ✅ |
| Vanilla-Conquer | ⚠️ (build-it-yourself) | ✅ | ⚠️ | ⚠️ |
| **OpenConquer** | ✅ | ✅ (goal) | ✅ | ✅ (goal) |

Nobody occupies "native, faithful, modern, and moddable" at once. That's the target.

## Design principles

1. **Faithful simulation.** Mechanics and behaviors match the original where it matters, cross-checked against EA's released C++. We pick an explicit parity bar (see below) rather than chasing pixel-exactness forever.
2. **Modern presentation.** The *simulation* is faithful; the *presentation* is free to improve. Arbitrary window size, smooth zoom, HD assets, and quality-of-life are welcome and are **not** considered parity violations.
3. **Data-driven & moddable.** Units, rules, and missions live in data. This is the linchpin that makes everything else possible:
   - **Configurable rulesets** — a canonical `Classic1995` ruleset plus named presets (e.g. `Enhanced`) and per-toggle overrides (veterancy on/off, crush rules, economy constants, fog-aware pathfinding, …).
   - **Custom missions** — scenarios + triggers as data; a mission can declare which ruleset it uses.
   - **Approachable contribution** — most work becomes editing data, not engine internals, which widens the contributor pool dramatically.

## What "faithful" means here (the parity bar)

- **Campaign-faithful:** the original GDI/Nod missions play through with correct objectives, triggers, and reinforcements.
- **Stat-accurate:** unit/structure/weapon/economy numbers are driven from the original data with cited C++ references.
- **Behaviorally close:** combat, harvesting, production, and AI *feel* like the original.
- **Best-effort, not guaranteed:** frame-exact pathfinding and every obscure edge case are aspirational, not blocking. Deviations are documented in a parity checklist.

## Deliberate deviations (features the original lacked, made optional)

Kept behind ruleset toggles so "classic" stays pure:
- Resizable window / free zoom (always on — a presentation feature, not a rule).
- Veterancy (off in `Classic1995`).
- Fog-aware player pathfinding (planning only against explored terrain).
- HD remastered art and cursors (presentation; classic SHP art remains the fallback).

## Non-goals (for now)

- **Multiplayer / netcode.** The determinism work would help here someday, but it's out of scope initially.
- **Red Alert or later titles.** Focus is Tiberian Dawn. (The engine may generalize later; not a near-term goal.)
- **Bundling assets or a no-purchase-required experience.** Users must own the Remastered Collection. This is both legal necessity and respect for EA's IP.
- **Being a drop-in OpenRA replacement.** Different philosophy: OpenRA modernizes; we stay faithful.

## Legal posture

- **Code:** GPLv3, consistent with EA's 2020 source release and the Vanilla-Conquer lineage.
- **Assets:** never distributed. Extracted locally by the user from their own Remastered Collection.
- **Trademarks:** "Command & Conquer" and "Tiberian Dawn" are EA trademarks; used only descriptively. The project is named to avoid branding with the marks and carries a clear "unofficial / not affiliated" disclaimer.
