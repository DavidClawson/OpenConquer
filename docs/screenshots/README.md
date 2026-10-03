# Screenshots

Images shown in the top-level `README.md`. The repo's `.gitignore` ignores
`*.png` everywhere **except** `docs/screenshots/` (and `docs/**/*.png`), so
images placed here are committable while extracted game art stays ignored.

These are illustrative captures of the engine running on a locally installed
copy of the game data; no game data is distributed with OpenConquer.

| Filename | Shot | How it was made |
|----------|------|-----------------|
| `title.png` | Title screen and main menu | `--test-title OUTDIR` (02-title), shown at 4:3 |
| `choose-side.png` | Choose your side | `--test-title OUTDIR` (06-choose) |
| `map-select.png` | Map selection, crosshairs over the candidates | `--test-map-select GDI 3 OUTDIR` (05-crosshairs) |
| `map-select-stats.png` | Map selection, country statistics | same run (07-stats) |
| `score.png` | End-of-mission score screen | `--test-score GDI OUTDIR` (11-t1320) |
| `options.png` | Classic-style Options dialog | `--test-classic-menus OUTDIR` (04-options) |
| `gameplay-classic.png` | GDI mission 12 base, classic sidebar | `--screenshot SCG12EA 300 OUT.png --classic --zoom 1.5 --camera 49 54` |
| `gameplay-modern.png` | Same base, modern sidebar | `--screenshot SCG12EA 300 OUT.png --modern --zoom 1.5 --camera 47 52` |

The classic screens are 640x400 and the game shows them at 4:3, so they were
resized to 800x600. All flags render headlessly from the installed data (see
CLAUDE.md). Keep files under ~500 KB.

Tips for in-game captures:
- Press **⌘S** (or **fn+F12**) in-game to save a clean PNG of the current frame (full Retina
  resolution, no F3 perf overlay) to `~/Desktop/OpenConquer-<timestamp>.png`.
- PNG keeps the crisp pixel/HD art.
