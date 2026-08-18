## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Why

<!-- For gameplay changes, cite the reference: e.g. "COMBAT.CPP:87-91". -->

## Checks run

<!-- Delete what doesn't apply; paste the result for what does. -->

- [ ] `swift build` (and `swift build -c release` if it's a perf/sim change)
- [ ] Asset-free logic tests — the `--test-*` list in [`.github/workflows/ci.yml`](.github/workflows/ci.yml)
- [ ] `--determinism SCG01EA 2500` / `4000` and `--determinism SCB01EA 4000` (any simulation change)
- [ ] `--reset-check` / `--ai-parity` (AI or session-state changes)

## Determinism

<!-- Required for anything touching the sim. -->

- [ ] Digests unchanged — this change doesn't perturb `Classic1995`.
- [ ] Digests **changed on purpose**. New baselines are below and `CLAUDE.md` is updated
      with what changed and why.

```
SCG01EA 2500t
SCG01EA 4000t
SCB01EA 4000t
```

## Ground rules

- [ ] **No game assets.** No `.MIX`/`.SHP`/`.AUD`/`.VQA`/`.PAL`, no extracted art, no EA content.
- [ ] Simulation randomness goes through the seeded helpers in `GameRandom.swift`
      (cosmetic randomness deliberately stays on the system RNG).
- [ ] New behavior that isn't 1995-faithful is behind a ruleset toggle, default off.
- [ ] `docs/PARITY.md` updated if this moves a row.
