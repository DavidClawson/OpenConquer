#!/bin/bash
#
# make-app.sh — package OpenConquer as a double-clickable macOS .app bundle.
#
# SwiftPM produces a bare executable that links SDL2 from an absolute Homebrew
# path, so it only runs on a machine with the same brew prefix. This script
# turns it into a self-contained bundle: it copies the SDL dylibs the binary
# actually needs into Contents/Frameworks, rewrites the load paths to @rpath,
# and ad-hoc signs the result (required on Apple Silicon once a binary has been
# modified).
#
# It bundles NO game data. Assets stay where install-assets.sh puts them, in
# ~/Library/Application Support/, and the app reads them from there at runtime.
#
# Usage:
#   ./tools/make-app.sh                 # build release + package to dist/
#   ./tools/make-app.sh --no-build      # package whatever is in .build/release
#   ./tools/make-app.sh --zip           # also produce dist/OpenConquer.zip
#   ./tools/make-app.sh --out DIR       # output somewhere other than dist/
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="OpenConquer"
BUNDLE_ID="org.openconquer.OpenConquer"
BINARY_NAME="TiberianDawnMax"     # SwiftPM target name (internal codename)
OUT_DIR="$REPO_ROOT/dist"
DO_BUILD=1
DO_ZIP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build) DO_BUILD=0; shift ;;
        --zip)      DO_ZIP=1; shift ;;
        --out)      OUT_DIR="$2"; shift 2 ;;
        -h|--help)  sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------- build

if [[ $DO_BUILD -eq 1 ]]; then
    say "Building release binary"
    swift build -c release
fi

BIN_SRC="$REPO_ROOT/.build/release/$BINARY_NAME"
[[ -f "$BIN_SRC" ]] || { echo "no release binary at $BIN_SRC — run without --no-build" >&2; exit 1; }

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo "0.0.0")"
BUILD_REV="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"

# ---------------------------------------------------------------- skeleton

APP="$OUT_DIR/$APP_NAME.app"
say "Creating $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

cp "$BIN_SRC" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"

# ---------------------------------------------------------------- dylibs
#
# Walk the binary's load commands and vendor anything that isn't shipped with
# macOS. In practice that is SDL2 alone — but `brew install sdl2` now installs
# sdl2-compat, a shim that dlopen()s libSDL3 at runtime, so that case needs
# handling too (see below).

is_system_lib() {
    case "$1" in
        /usr/lib/*|/System/*) return 0 ;;
        *) return 1 ;;
    esac
}

FRAMEWORKS="$APP/Contents/Frameworks"

# macOS ships bash 3.2, which has no associative arrays — the queue and the
# "already vendored" set are plain space-delimited strings.
PENDING="$APP/Contents/MacOS/$APP_NAME"
VENDORED=" "

while [[ -n "$PENDING" ]]; do
    target="${PENDING%% *}"
    if [[ "$PENDING" == *" "* ]]; then PENDING="${PENDING#* }"; else PENDING=""; fi

    # tail -n +2 drops otool's header line; for a dylib the first entry that
    # follows is its own id, which the self-reference check below skips.
    for dep in $(otool -L "$target" | tail -n +2 | awk '{print $1}'); do
        is_system_lib "$dep" && continue
        base="$(basename "$dep")"
        [[ "$(basename "$target")" == "$base" ]] && continue   # self-reference

        case "$VENDORED" in
            *" $base "*) ;;                                     # already copied
            *)
                if [[ ! -f "$dep" ]]; then
                    warn "dependency not found on disk, skipping: $dep"
                    continue
                fi
                say "Vendoring $base"
                cp "$dep" "$FRAMEWORKS/$base"
                chmod u+w "$FRAMEWORKS/$base"
                install_name_tool -id "@rpath/$base" "$FRAMEWORKS/$base" 2>/dev/null || true
                VENDORED="$VENDORED$base "
                if [[ -n "$PENDING" ]]; then
                    PENDING="$PENDING $FRAMEWORKS/$base"
                else
                    PENDING="$FRAMEWORKS/$base"
                fi
                ;;
        esac
        install_name_tool -change "$dep" "@rpath/$base" "$target" 2>/dev/null || true
    done
done

# sdl2-compat resolves SDL3 with dlopen(), which otool cannot see. It searches
# @loader_path first, so dropping libSDL3 next to libSDL2 in Frameworks/ is
# enough — no path rewriting needed.
for sdl2 in "$FRAMEWORKS"/libSDL2*.dylib; do
    [[ -e "$sdl2" ]] || continue
    if strings -a "$sdl2" | grep -q 'libSDL3'; then
        say "Detected sdl2-compat — vendoring libSDL3 for its dlopen path"
        sdl3_dir="$(pkg-config --variable=libdir sdl3 2>/dev/null || echo "")"
        [[ -z "$sdl3_dir" && -d "$(brew --prefix sdl3 2>/dev/null)/lib" ]] \
            && sdl3_dir="$(brew --prefix sdl3)/lib"
        if [[ -n "$sdl3_dir" ]]; then
            # Only the core runtime — NOT libSDL3_mixer or the other satellite
            # libraries, which nothing here links.
            #
            # cp -L, not cp -a: Homebrew's lib dir is a symlink chain into
            # ../Cellar, so copying the links verbatim leaves them dangling
            # inside the bundle. sdl2-compat then fails to dlopen SDL3 and puts
            # up a modal NSAlert from its library initializer, which hangs the
            # process forever with no output.
            sdl3_real=""
            for f in "$sdl3_dir"/libSDL3.[0-9]*.dylib; do
                [[ -e "$f" ]] || continue
                b="$(basename "$f")"
                cp -L "$f" "$FRAMEWORKS/$b"
                chmod u+w "$FRAMEWORKS/$b"
                install_name_tool -id "@rpath/$b" "$FRAMEWORKS/$b" 2>/dev/null || true
                sdl3_real="$b"
            done
            # The shim dlopen()s the unversioned name; point it at the real file.
            if [[ -n "$sdl3_real" ]]; then
                ln -sf "$sdl3_real" "$FRAMEWORKS/libSDL3.dylib"
            elif [[ -e "$sdl3_dir/libSDL3.dylib" ]]; then
                cp -L "$sdl3_dir/libSDL3.dylib" "$FRAMEWORKS/libSDL3.dylib"
                chmod u+w "$FRAMEWORKS/libSDL3.dylib"
            fi
        else
            warn "sdl2-compat needs libSDL3 but it wasn't found — 'brew install sdl3'"
        fi
    fi
done

install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# ---------------------------------------------------------------- icon

if command -v iconutil >/dev/null 2>&1 && python3 -c "import PIL" >/dev/null 2>&1; then
    say "Generating app icon"
    python3 "$REPO_ROOT/tools/make_icon.py" "$APP/Contents/Resources/$APP_NAME.icns" >/dev/null
    ICON_LINE="    <key>CFBundleIconFile</key>
    <string>$APP_NAME</string>"
else
    warn "skipping icon (needs Pillow: pip3 install Pillow)"
    ICON_LINE=""
fi

# ---------------------------------------------------------------- Info.plist

say "Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_REV</string>
$ICON_LINE
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.strategy-games</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>GPLv3. Unofficial fan project — not affiliated with or endorsed by Electronic Arts. No game assets included.</string>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------- sign
#
# Ad-hoc signature. Apple Silicon refuses to run a binary whose load commands
# were edited unless it is re-signed, so this is required, not cosmetic. It is
# NOT notarization — first launch still needs right-click > Open.

say "Ad-hoc signing"
for lib in "$FRAMEWORKS"/*.dylib; do
    [[ -e "$lib" ]] || continue
    [[ -L "$lib" ]] && continue          # symlink alias — the target gets signed
    codesign --force --sign - --timestamp=none "$lib" >/dev/null 2>&1 || \
        warn "could not sign $(basename "$lib")"
done
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
    warn "could not sign the bundle"

# ---------------------------------------------------------------- verify

say "Verifying"
if otool -L "$APP/Contents/MacOS/$APP_NAME" | grep -qE '/opt/homebrew|/usr/local/(opt|Cellar)'; then
    warn "the binary still references a Homebrew path — it will not run on another Mac:"
    otool -L "$APP/Contents/MacOS/$APP_NAME" | grep -E '/opt/homebrew|/usr/local/(opt|Cellar)' >&2
else
    echo "    no Homebrew paths remain in the executable"
fi
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /' || true
echo "    bundled: $(ls "$FRAMEWORKS" | tr '\n' ' ')"

# Dangling symlinks are the failure mode this script hit in development: brew's
# lib dirs are symlink chains into ../Cellar, and a link copied verbatim points
# nowhere once it is inside the bundle.
for link in "$FRAMEWORKS"/*; do
    [[ -L "$link" && ! -e "$link" ]] && warn "dangling symlink in bundle: $(basename "$link")"
done

# Smoke test. Runs an asset-free self-test through the BUNDLED binary, so a
# broken dylib path fails here rather than on a stranger's Mac. It is capped
# because the specific way this breaks — sdl2-compat failing to find SDL3 —
# raises a modal NSAlert from a library initializer and hangs forever.
say "Smoke testing the bundle"
SMOKE_LOG="$(mktemp -t openconquer-smoke)"
"$APP/Contents/MacOS/$APP_NAME" --test-synthetic 100 >"$SMOKE_LOG" 2>&1 &
SMOKE_PID=$!
SMOKE_WAITED=0
while kill -0 "$SMOKE_PID" 2>/dev/null; do
    if [[ $SMOKE_WAITED -ge 30 ]]; then
        kill -9 "$SMOKE_PID" 2>/dev/null || true
        warn "the bundled binary hung — it is probably blocked on a modal dialog"
        warn "from a library initializer (check Frameworks/ for a missing dylib)"
        exit 1
    fi
    sleep 1
    SMOKE_WAITED=$((SMOKE_WAITED + 1))
done
if grep -q "^PASS" "$SMOKE_LOG"; then
    echo "    the bundled binary runs and passes its asset-free self-test"
    rm -f "$SMOKE_LOG"
else
    warn "the bundled binary did not pass --test-synthetic. Output:"
    tail -20 "$SMOKE_LOG" >&2
    exit 1
fi

if [[ $DO_ZIP -eq 1 ]]; then
    say "Zipping"
    (cd "$OUT_DIR" && rm -f "$APP_NAME.zip" && \
        ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$APP_NAME.zip")
    echo "    $OUT_DIR/$APP_NAME.zip"
fi

say "Done: $APP"
echo
echo "  Try it:     open \"$APP\""
echo "  Install it: drag it to /Applications"
echo
echo "  Because the bundle is ad-hoc signed rather than notarized, the first"
echo "  launch on another Mac needs right-click > Open (once)."
