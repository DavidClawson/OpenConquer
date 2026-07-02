#!/usr/bin/env bash
#
# install-assets.sh — one-command guided asset installer for OpenConquer.
#
# OpenConquer ships NO game data. This script installs the assets from YOUR OWN
# legally-owned copy of the Command & Conquer Remastered Collection into the
# engine's data directory. It only orchestrates the existing python extractors
# in tools/ — it never downloads, bundles, or commits any game asset.
#
# Usage:  ./install-assets.sh [/path/to/CnCRemastered] [--dry-run]
# See --help for details.
#
# macOS / bash. No arguments needed if the Remastered Collection is in a common
# location; otherwise pass the path to the install (the folder that contains
# `Data/`, or the `Data/` folder itself).

set -uo pipefail

# ---------------------------------------------------------------------------
# Paths & constants
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR/tools"

# Engine data directory (same location Vanilla-Conquer uses). Classic MIX
# archives live here; extracted assets land under extracted/.
VANILLA_DIR="$HOME/Library/Application Support/Vanilla-Conquer/vanillatd"
EXTRACTED_DIR="$VANILLA_DIR/extracted"

# A file that is present in a valid Tiberian Dawn "Data" directory. Used to tell
# whether a supplied path is the install root or the Data dir itself.
SENTINEL_MEG="TEXTURES_TD_SRGB.MEG"

# Remastered .MEG containers the python extractors read from (must all exist).
REQUIRED_MEGS=(
  "TEXTURES_TD_SRGB.MEG"   # HD unit/structure/vfx sprites
  "TEXTURES_SRGB.MEG"      # HD UI (cursors + sidebar meters)
  "CONFIG.MEG"             # cursor hotspots (MOUSEPOINTERS.XML)
  "SFX3D.MEG"              # HD weapon/explosion sfx
  "SFX2D_EN-US.MEG"        # HD voices / EVA
  "MUSIC.MEG"              # HD music
)

# Classic MIX archives, extracted from CNCDATA/TIBERIAN_DAWN/.
#   CD1 = GDI disc (shared data + GDI briefings/scores)
#   CD2 = Nod disc (Nod briefings/scores)
# (md5 confirms CD1==CD3 GDI-side, CD2 is the Nod side.)
CLASSIC_BASE_MIX=(CONQUER.MIX DESERT.MIX TEMPERAT.MIX WINTER.MIX LOCAL.MIX SOUNDS.MIX SPEECH.MIX)
CLASSIC_SIDE_MIX=(GENERAL.MIX SCORES.MIX MOVIES.MIX)

DRY_RUN=false
DATA_DIR=""          # resolved Remastered .../Data directory
USER_PATH=""         # path the user supplied as $1 (if any)

# ---------------------------------------------------------------------------
# Pretty output
# ---------------------------------------------------------------------------

if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

info()  { printf '%s\n' "$*"; }
step()  { printf '\n%s==>%s %s\n' "$CYAN$BOLD" "$RESET$BOLD" "$*$RESET"; }
ok()    { printf '  %sok%s   %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '  %swarn%s %s\n' "$YELLOW" "$RESET" "$*"; }
fail()  { printf '  %smiss%s %s\n' "$RED" "$RESET" "$*"; }
die()   { printf '\n%sERROR:%s %s\n' "$RED$BOLD" "$RESET" "$*" >&2; exit 1; }

# Run a command, or just print it under --dry-run.
run() {
  if $DRY_RUN; then
    printf '  %s[dry-run]%s %s\n' "$DIM" "$RESET" "$*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

usage() {
  cat <<EOF
${BOLD}install-assets.sh${RESET} — one-command guided asset installer for OpenConquer

OpenConquer ships no game data. This installs assets from YOUR OWN copy of the
Command & Conquer Remastered Collection into the engine's data directory. It
only orchestrates the python extractors in tools/ — nothing is downloaded,
bundled, or committed.

${BOLD}Usage:${RESET}
  ./install-assets.sh [PATH] [options]

${BOLD}Arguments:${RESET}
  PATH            Path to the Remastered Collection install — either the folder
                  that contains 'Data/' or the 'Data/' folder itself. Optional:
                  if omitted, common macOS locations (Steam, ~/CnCRemastered,
                  /Applications, EA app) are probed automatically.

${BOLD}Options:${RESET}
  -n, --dry-run   Print the steps that would run, without executing anything.
  -h, --help      Show this help and exit.

${BOLD}What it does (in order):${RESET}
  1. Install classic MIX archives from CNCDATA into the engine data dir.
  2. Extract classic audio (AUD -> WAV) from those MIX archives.
  3. Extract remastered HD sprites (units/structures/vfx) + UI (cursors,
     sidebar meters).
  4. Extract remastered HD audio (music, sfx, voices).

${BOLD}Output:${RESET}
  Data dir:   $VANILLA_DIR
  Extracted:  $EXTRACTED_DIR

The script is idempotent — safe to re-run. It requires python3 and the Pillow
library (pip3 install Pillow) for HD sprite extraction.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

for arg in "$@"; do
  case "$arg" in
    -h|--help)    usage; exit 0 ;;
    -n|--dry-run) DRY_RUN=true ;;
    -*)           die "Unknown option: $arg (see --help)" ;;
    *)
      if [ -n "$USER_PATH" ]; then
        die "Too many path arguments: '$USER_PATH' and '$arg' (see --help)"
      fi
      USER_PATH="$arg"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Locate the Remastered "Data" directory
# ---------------------------------------------------------------------------

# Echo the resolved Data dir for a candidate path, or nothing (return 1).
resolve_data_dir() {
  local p="${1%/}"
  [ -z "$p" ] && return 1
  if [ -f "$p/$SENTINEL_MEG" ]; then printf '%s\n' "$p"; return 0; fi
  if [ -f "$p/Data/$SENTINEL_MEG" ]; then printf '%s\n' "$p/Data"; return 0; fi
  return 1
}

locate_install() {
  # 1) explicit path from the user
  if [ -n "$USER_PATH" ]; then
    local resolved
    if resolved="$(resolve_data_dir "$USER_PATH")"; then
      DATA_DIR="$resolved"
      return 0
    fi
    die "'$USER_PATH' does not look like a C&C Remastered Collection install.
       Expected to find '$SENTINEL_MEG' in that folder or in its 'Data/' subfolder.
       Pass the install folder (the one containing 'Data/') or the 'Data/' folder itself."
  fi

  # 2) probe common macOS locations
  local candidates=(
    "$HOME/CnCRemastered"
    "$HOME/Library/Application Support/Steam/steamapps/common/CnCRemastered"
    "/Applications/Command and Conquer Remastered Collection"
    "$HOME/Library/Application Support/Electronic Arts/Command and Conquer Remastered Collection"
    "$HOME/Applications/Command and Conquer Remastered Collection"
  )
  local c resolved
  for c in "${candidates[@]}"; do
    if resolved="$(resolve_data_dir "$c")"; then
      DATA_DIR="$resolved"
      info "Auto-detected Remastered Collection at: $DATA_DIR"
      return 0
    fi
  done

  # 3) nothing found
  if $DRY_RUN; then
    DATA_DIR="<path-to-CnCRemastered>/Data"
    warn "No Remastered Collection found in the usual locations."
    warn "Using a placeholder path for this dry run: $DATA_DIR"
    return 0
  fi
  die "Could not find your C&C Remastered Collection in the usual locations.
       Pass the path explicitly, e.g.:
           ./install-assets.sh \"\$HOME/CnCRemastered\"
           ./install-assets.sh \"\$HOME/Library/Application Support/Steam/steamapps/common/CnCRemastered\"
       You must own the Remastered Collection; this script does not download it."
}

# ---------------------------------------------------------------------------
# Tooling checks
# ---------------------------------------------------------------------------

check_tooling() {
  step "Checking tooling"

  if command -v python3 >/dev/null 2>&1; then
    ok "python3 ($(python3 --version 2>&1))"
  else
    if $DRY_RUN; then
      warn "python3 not found (required to run the extractors)"
    else
      die "python3 not found. Install Xcode command-line tools ('xcode-select --install')
       or Homebrew python ('brew install python')."
    fi
  fi

  if python3 -c 'import PIL' >/dev/null 2>&1; then
    ok "Pillow (Python imaging library) available"
  else
    if $DRY_RUN; then
      warn "Pillow not installed (required for HD sprite extraction: pip3 install Pillow)"
    else
      die "Pillow is required for HD sprite extraction. Install it with:
           pip3 install Pillow"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Preflight — verify every source container exists before touching anything
# ---------------------------------------------------------------------------

preflight() {
  step "Preflight: verifying source assets in $DATA_DIR"

  local cd1="$DATA_DIR/CNCDATA/TIBERIAN_DAWN/CD1"
  local cd2="$DATA_DIR/CNCDATA/TIBERIAN_DAWN/CD2"
  local missing=()

  # In a dry run against a placeholder path we can't actually check; just report.
  if $DRY_RUN && [ ! -d "$DATA_DIR" ]; then
    warn "Skipping existence checks (placeholder path — this is a dry run)."
    return 0
  fi

  # Remastered .MEG containers
  local m
  for m in "${REQUIRED_MEGS[@]}"; do
    if [ -f "$DATA_DIR/$m" ]; then ok "$m"; else fail "$m"; missing+=("$DATA_DIR/$m"); fi
  done

  # Classic MIX source (CD1 = GDI/shared, CD2 = Nod)
  if [ -d "$cd1" ]; then ok "CNCDATA/TIBERIAN_DAWN/CD1/"; else fail "CNCDATA/TIBERIAN_DAWN/CD1/ (classic data)"; missing+=("$cd1"); fi
  if [ -d "$cd2" ]; then ok "CNCDATA/TIBERIAN_DAWN/CD2/"; else fail "CNCDATA/TIBERIAN_DAWN/CD2/ (Nod classic data)"; missing+=("$cd2"); fi

  local f
  if [ -d "$cd1" ]; then
    for f in "${CLASSIC_BASE_MIX[@]}" "${CLASSIC_SIDE_MIX[@]}"; do
      [ -f "$cd1/$f" ] || { fail "CD1/$f"; missing+=("$cd1/$f"); }
    done
  fi
  if [ -d "$cd2" ]; then
    for f in "${CLASSIC_SIDE_MIX[@]}"; do
      [ -f "$cd2/$f" ] || { fail "CD2/$f"; missing+=("$cd2/$f"); }
    done
  fi

  if [ "${#missing[@]}" -gt 0 ]; then
    if $DRY_RUN; then
      warn "${#missing[@]} required file(s) missing — a real run would stop here."
      return 0
    fi
    printf '\n%sERROR:%s missing %d required asset file(s):\n' "$RED$BOLD" "$RESET" "${#missing[@]}" >&2
    for f in "${missing[@]}"; do printf '  - %s\n' "$f" >&2; done
    cat >&2 <<EOF

These come from a full install of the Command & Conquer Remastered Collection.
Make sure the collection is fully installed/downloaded, then point this script
at it:
    ./install-assets.sh "/path/to/CnCRemastered"

You must own the Remastered Collection; this script does not download game data.
EOF
    exit 1
  fi

  ok "all required source assets present"
}

# ---------------------------------------------------------------------------
# Step 1: install classic MIX archives into the engine data dir (idempotent)
# ---------------------------------------------------------------------------

install_classic_mix() {
  step "Step 1/4: Install classic MIX archives -> $VANILLA_DIR"

  local cd1="$DATA_DIR/CNCDATA/TIBERIAN_DAWN/CD1"
  local cd2="$DATA_DIR/CNCDATA/TIBERIAN_DAWN/CD2"

  run mkdir -p "$VANILLA_DIR" "$VANILLA_DIR/gdi" "$VANILLA_DIR/nod"

  # Shared base archives -> data dir root.
  local f copied=0 skipped=0
  for f in "${CLASSIC_BASE_MIX[@]}"; do
    if [ -f "$VANILLA_DIR/$f" ] && ! $DRY_RUN; then
      skipped=$((skipped + 1)); continue
    fi
    run cp "$cd1/$f" "$VANILLA_DIR/$f"
    copied=$((copied + 1))
  done

  # Side-specific archives: CD1 (GDI) -> gdi/, CD2 (Nod) -> nod/.
  for f in "${CLASSIC_SIDE_MIX[@]}"; do
    if [ ! -f "$VANILLA_DIR/gdi/$f" ] || $DRY_RUN; then
      run cp "$cd1/$f" "$VANILLA_DIR/gdi/$f"; copied=$((copied + 1))
    else skipped=$((skipped + 1)); fi
    if [ ! -f "$VANILLA_DIR/nod/$f" ] || $DRY_RUN; then
      run cp "$cd2/$f" "$VANILLA_DIR/nod/$f"; copied=$((copied + 1))
    else skipped=$((skipped + 1)); fi
  done

  $DRY_RUN || ok "classic MIX archives in place (copied $copied, already present $skipped)"
}

# ---------------------------------------------------------------------------
# Steps 2-4: run the existing python extractors
# ---------------------------------------------------------------------------

extract_classic_audio() {
  step "Step 2/4: Extract classic audio (AUD -> WAV)"
  run python3 "$TOOLS_DIR/extract_audio.py" --data-dir "$VANILLA_DIR"
}

extract_remastered_sprites() {
  step "Step 3/4: Extract remastered HD sprites + UI (cursors, sidebar meters)"
  run python3 "$TOOLS_DIR/extract_remastered_sprites.py" \
      --remastered-dir "$DATA_DIR" --category all
}

extract_remastered_audio() {
  step "Step 4/4: Extract remastered HD audio (music, sfx, voices)"
  run python3 "$TOOLS_DIR/extract_remastered_audio.py" \
      --remastered-dir "$DATA_DIR"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

summary() {
  step "Done"
  if $DRY_RUN; then
    info "Dry run complete — nothing was written. Re-run without --dry-run to install."
    return 0
  fi
  cat <<EOF
Assets installed from: $DATA_DIR

  Classic MIX archives  -> $VANILLA_DIR
  Classic audio (WAV)   -> $EXTRACTED_DIR/audio
  HD sprites + UI (PNG) -> $EXTRACTED_DIR/sprites_remastered
  HD audio (WAV)        -> $EXTRACTED_DIR/audio_remastered

${BOLD}Now run:${RESET}  swift run
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

printf '%sOpenConquer asset installer%s\n' "$BOLD" "$RESET"
if $DRY_RUN; then info "(dry run — no files will be written)"; fi

locate_install
check_tooling
preflight
install_classic_mix
extract_classic_audio
extract_remastered_sprites
extract_remastered_audio
summary
