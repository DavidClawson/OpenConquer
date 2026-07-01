# OpenConquer

**A native macOS reimplementation of the classic 1995 Westwood real-time strategy game *Command & Conquer: Tiberian Dawn*, written in Swift + SDL2.**

> ⚠️ **Unofficial fan project.** OpenConquer is not affiliated with, endorsed by, or sponsored by Electronic Arts. "Command & Conquer" and "Tiberian Dawn" are trademarks of Electronic Arts Inc. **No game assets are included.** You must own the [Command & Conquer Remastered Collection](https://www.ea.com/games/command-and-conquer/command-and-conquer-remastered) and supply your own assets (see [Assets](#assets)).

---

## Why this exists

There is no polished, native, *faithful* way to play the original Tiberian Dawn on a Mac:

- The **C&C Remastered Collection** is Windows-only (runs on Mac only via Wine/CrossOver/Parallels).
- **OpenRA** is native and excellent, but deliberately *reinterprets* the game on a modernized engine — it isn't original parity.
- **Vanilla-Conquer** (EA's GPL source, faithful) builds on Mac but is a niche, build-it-yourself experience.

OpenConquer aims at the empty square: **native Mac · faithful simulation · modern presentation · fully moddable.**

Design principle: **faithful simulation, modern presentation, data-driven.**
- *Faithful simulation* — mechanics and behaviors match the original where it counts (cross-checked against EA's released C++).
- *Modern presentation* — arbitrary window size, smooth zoom, and optional HD art from the Remastered Collection.
- *Data-driven* — units, rules, and missions live in data, so the game is configurable (classic vs. enhanced rulesets) and moddable.

See [`docs/VISION.md`](docs/VISION.md) and [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Status

Early but very playable: GDI and Nod campaign missions, AI, pathfinding, fog of war, economy/harvesting, combat, superweapons, save/load, and both classic-SHP and remastered-HD rendering. Expect rough edges and missing features — this is a work in progress and contributions are welcome.

## Requirements

- **macOS 13+**
- **SDL2** — `brew install sdl2 pkg-config`
- **Swift toolchain** (Xcode or the swift.org toolchain; the package targets swift-tools 5.9)
- **A legally-owned copy of the C&C Remastered Collection** (for game assets)

## Assets

OpenConquer ships **no game data** — you extract it from your own copy of the Remastered Collection. There are two asset sources:

1. **Classic game data (MIX archives)** — the original sprites, maps, audio, and scenarios. The engine reads these from
   `~/Library/Application Support/Vanilla-Conquer/vanillatd/`.
   (This is the same data directory [Vanilla-Conquer](https://github.com/TheAssemblyArmada/Vanilla-Conquer) uses; the classic `.MIX` files from the Remastered Collection's `CNCDATA` go here.)

2. **Remastered HD art & audio (optional but recommended)** — extracted from the Remastered Collection's `.MEG` archives into `…/vanillatd/extracted/`. With the Remastered install downloaded to `~/CnCRemastered/Data`:

   ```bash
   pip install Pillow
   python3 tools/extract_remastered_sprites.py            # HD units/structures/vfx
   python3 tools/extract_remastered_sprites.py --category ui   # HD cursors + sidebar meters
   python3 tools/extract_remastered_audio.py              # HD music & sound
   python3 tools/extract_audio.py                         # classic AUD → WAV (from MIX)
   ```

> The asset setup is currently multi-step. Streamlining it into a single guided installer that points at your Remastered install is a near-term roadmap item.

## Build & run

```bash
brew install sdl2 pkg-config
swift build          # or: swift run
./TiberianDawnMax.command   # convenience wrapper (runs `swift run`)
```

## Headless test harness

The simulation runs without a window/renderer/audio, which powers a deterministic regression suite (see [`CONTRIBUTING.md`](CONTRIBUTING.md)):

```bash
./.build/debug/TiberianDawnMax --determinism SCG01EA 2500   # 3 subprocess trials, assert identical
./.build/debug/TiberianDawnMax --headless    SCG01EA 600    # run + print a state digest
./.build/debug/TiberianDawnMax --test-crush   SCG01EA        # focused behavior self-tests
```

The seeded RNG makes runs bit-for-bit reproducible, so a change that perturbs the simulation shows up as a changed digest. **Please keep the determinism baselines green when changing simulation code.**

## Contributing

Contributions are very welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). A lot of the roadmap is *data* work (rules, missions, unit tables) that doesn't require deep Swift knowledge. Never commit game assets.

## License

**GNU General Public License v3.0** — see [`LICENSE`](LICENSE).

OpenConquer builds on the behavior of the Tiberian Dawn game logic that Electronic Arts released under the GPLv3 in 2020, and cross-references [Vanilla-Conquer](https://github.com/TheAssemblyArmada/Vanilla-Conquer) (also GPLv3). Licensing OpenConquer under GPLv3 keeps it compatible with that lineage.

*Copyright © 2024–2026 David Clawson and contributors.*

## Credits & thanks

- **Electronic Arts** / **Westwood Studios** — the original game, and the 2020 GPLv3 source release that makes faithful reimplementation possible.
- **Vanilla-Conquer** and the **OpenRA** project — invaluable references and inspiration for the open-source C&C ecosystem.
