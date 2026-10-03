# OpenConquer v0.1.0

The first release of **OpenConquer**, a native macOS reimplementation of the 1995
Westwood game *Command & Conquer: Tiberian Dawn*, written in Swift and SDL2.

> Unofficial fan project, not affiliated with Electronic Arts. **No game data is
> included**: you need your own copy of the *Command & Conquer Remastered
> Collection*.

## What it is

The GDI and Nod campaigns, playable from the Westwood logo to the final movie,
with the simulation and presentation ported from the game source Electronic Arts
released under the GPLv3 in 2020. It runs natively on the Mac, in a resizable
window, with the original 1995 art or the Remastered Collection's HD art.

## Requirements

- **macOS 13 (Ventura) or later.** The optional *Enhanced* movie mode needs macOS 26.
- **Your own copy of the C&C Remastered Collection** (Steam or the EA app). It is
  Windows-only to play, but it only needs to be installed somewhere a Mac can read,
  for example via CrossOver, or copied over from a PC.
- **Python 3 with Pillow** (`pip3 install Pillow`) for the one-time asset install.

## Install

1. Open `OpenConquer.dmg` and drag **OpenConquer** to Applications. The DMG is
   signed with a Developer ID and notarized by Apple, so it opens normally.
2. Install the game data from your own Remastered Collection, from a checkout of
   the repository:

   ```bash
   ./install-assets.sh /path/to/CnCRemastered
   ```

   This copies the classic archives and extracts the HD art and audio into
   `~/Library/Application Support/Vanilla-Conquer/vanillatd/`. It never downloads
   or redistributes anything. If you launch the app first, it shows a setup screen
   with the exact command to run.
3. Launch OpenConquer.

If you installed assets with an earlier version of the script, run it again: it
now also installs the Win95 archives (`CCLOCAL`, `UPDATE`, `UPDATA`, `TRANSIT.MIX`)
behind the title screen, choose-your-side and hi-res fonts, and the HD repair wrench.
It is safe to re-run.

## What works

- **Both campaigns**: all 28 missions and 47 variants play through, with the
  original's triggers, teams, reinforcements, superweapons and campaign branching.
- **The classic front end**: Westwood logo, the Win95 title screen and main menu,
  choose your side, and classic-style Load Mission and Options dialogs.
- **Movies**: intro, briefing and action movies before each mission, win and lose
  movies after, decoded from your own `MOVIES.MIX`. Settings: Off, Pixels, Smooth,
  or Enhanced (live Apple super-resolution, macOS 26+).
- **Between missions**: the end-of-mission score screen with the hall of fame, and
  the animated map selection where you pick the next territory.
- **Endings**: both campaign endings, including Nod's satellite target selection.
- **The battlefield**: the original's target acquisition, pathfinding, harvesting
  economy, power, repair and selling. Buildings play their construction animation,
  the MCV turns before it unfolds, and the sidebar offers what the original would
  for each mission.
- **Two looks**: the classic 1995 hi-res sidebar, or a modern sidebar with the
  Remastered HD power and build meters; classic or HD unit art; classic or modern
  controls.
- **Two rulesets**: *Classic (1995)* is the faithful one; *Enhanced* adds veterancy,
  a smarter enemy and other optional changes.
- **Save and load** during missions (F5 / F9), and a screenshot key (⌘S).

## Known gaps

The full, honest list is [`docs/PARITY.md`](PARITY.md). The ones you are most likely
to notice:

- **Sidebar**: the strips jump one entry per click instead of scrolling smoothly,
  buttons don't show a pressed frame, and the Map button does nothing yet (radar
  zoom isn't implemented). The tab bar across the top of the battlefield isn't drawn.
- **Production**: build times use a simple formula rather than the original's
  staged model, the full cost is charged up front, and owning several factories
  doesn't speed production.
- **Nod mission 11**: the special rule tying the Stealth Tank to the mission's
  objective buildings isn't modelled, and Stealth Tanks don't cloak.
- **Mission end overlay**: the victory/defeat overlay shows an approximate score;
  the score screen that follows uses the original formula.
- **Scrolling** in missions is tied to the frame rate.
- **Multiplayer** isn't available yet. It's planned (see
  [`docs/MULTIPLAYER.md`](MULTIPLAYER.md)): skirmish against the computer first,
  then networked play.

## Reporting bugs

Please open an issue at
<https://github.com/DavidClawson/OpenConquer/issues> with the mission, what
happened, and what the original does if you know. A screenshot (⌘S in game) or a
crash report from macOS helps a lot. Gaps against the original are tracked as
`parity` issues.

## Thanks

Westwood Studios and Electronic Arts for the game and the 2020 source release;
Vanilla Conquer and OpenRA for the references and the inspiration.
