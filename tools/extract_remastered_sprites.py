#!/usr/bin/env python3
"""
Extract remastered sprites from C&C Remastered Collection TEXTURES MEG archive.

Reads TEXTURES_TD_SRGB.MEG and extracts unit, structure, and VFX sprites.
Each sprite is stored as a ZIP inside the MEG containing cropped TGA frames
and JSON metadata. This script reconstructs full-canvas PNG frames.

It also extracts the remastered in-game UI art (`--category ui`): the animated
mouse cursors and the sidebar power-meter / progress-bar textures. Those live in
TEXTURES_SRGB.MEG (top-level `ICON_*.DDS` / `UI_*.DDS`, uncompressed 32-bit) with
cursor hotspots defined in CONFIG.MEG's MOUSEPOINTERS.XML. Output lands under
`<output-dir>/ui/cursors/` (per-family PNG frames + cursors.json manifest mapping
each POINTER_* to its texture family and hotspot, incl. _X2 hi-DPI frames) and
`<output-dir>/ui/sidebar/`. NOTE: the sidebar chrome/frame is vector/HTML in the
remaster (no bitmap) and the build cameos were never remastered (still classic
SHPs), so those are intentionally not produced here.

Requires: Pillow (pip install Pillow)

Usage:
    python3 tools/extract_remastered_sprites.py [--remastered-dir PATH] [--output-dir PATH]
    python3 tools/extract_remastered_sprites.py --category ui   # cursors + sidebar meters only

Default remastered dir: ~/CnCRemastered/Data
Default output dir:     ~/Library/Application Support/Vanilla-Conquer/vanillatd/extracted/sprites_remastered/
"""

import struct
import os
import sys
import json
import argparse
import zipfile
import io
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install with: pip install Pillow")
    sys.exit(1)


# ---------------------------------------------------------------------------
# MEG V3 Reader (shared with extract_remastered_audio.py)
# ---------------------------------------------------------------------------

class MEGFile:
    """Read Petroglyph MEG V3 archive format."""

    def __init__(self, path):
        self.path = path
        self.entries = {}  # name -> (offset, size)
        self._parse()

    def _parse(self):
        with open(self.path, 'rb') as f:
            header = f.read(24)
            if len(header) < 24:
                raise ValueError("File too small for MEG header")

            flags, magic, data_start, num_filenames, num_files, filenames_size = \
                struct.unpack_from('<IIIIII', header)

            if flags != 0xFFFFFFFF or magic != 0x3F7D70A4:
                raise ValueError(f"Not a valid MEG V3 file (flags={flags:#x}, magic={magic:#x})")

            # Read filename table
            fn_data = f.read(filenames_size)
            filenames = []
            pos = 0
            for _ in range(num_filenames):
                length = struct.unpack_from('<H', fn_data, pos)[0]
                pos += 2
                name = fn_data[pos:pos + length].decode('ascii', errors='replace')
                filenames.append(name)
                pos += length

            # Read file table (20 bytes per entry)
            for _ in range(num_files):
                entry = f.read(20)
                e_size = struct.unpack_from('<I', entry, 10)[0]
                e_offset = struct.unpack_from('<I', entry, 14)[0]
                e_name_idx = struct.unpack_from('<H', entry, 18)[0]
                self.entries[filenames[e_name_idx]] = (e_offset, e_size)

    def read_file(self, name):
        """Read a file from the archive by name."""
        if name not in self.entries:
            return None
        offset, size = self.entries[name]
        with open(self.path, 'rb') as f:
            f.seek(offset)
            return f.read(size)

    def list_files(self):
        """Return list of (name, size) tuples."""
        return [(name, size) for name, (_, size) in self.entries.items()]


# ---------------------------------------------------------------------------
# TGA Reader
# ---------------------------------------------------------------------------

def read_tga(data):
    """Read an uncompressed 32-bit RGBA TGA file.

    Returns a PIL Image or None on failure.
    TGA origin is bottom-left, so we flip vertically.
    """
    if len(data) < 18:
        return None

    id_length = data[0]
    colormap_type = data[1]
    image_type = data[2]
    width = struct.unpack_from('<H', data, 12)[0]
    height = struct.unpack_from('<H', data, 14)[0]
    pixel_depth = data[16]
    descriptor = data[17]

    if image_type != 2:  # uncompressed true-color only
        return None
    if pixel_depth not in (24, 32):
        return None

    origin_upper = (descriptor & 0x20) != 0
    pixel_start = 18 + id_length + (0 if colormap_type == 0 else 0)
    bpp = pixel_depth // 8

    expected_size = pixel_start + width * height * bpp
    if len(data) < expected_size:
        return None

    # Read pixels (TGA stores as BGRA)
    if pixel_depth == 32:
        img = Image.new('RGBA', (width, height))
        pixels = []
        offset = pixel_start
        for y in range(height):
            row = []
            for x in range(width):
                b = data[offset]
                g = data[offset + 1]
                r = data[offset + 2]
                a = data[offset + 3]
                row.append((r, g, b, a))
                offset += 4
            pixels.append(row)
    else:  # 24-bit
        img = Image.new('RGBA', (width, height))
        pixels = []
        offset = pixel_start
        for y in range(height):
            row = []
            for x in range(width):
                b = data[offset]
                g = data[offset + 1]
                r = data[offset + 2]
                row.append((r, g, b, 255))
                offset += 3
            pixels.append(row)

    # Flip if origin is bottom-left (standard TGA)
    if not origin_upper:
        pixels.reverse()

    # Set pixels
    flat = []
    for row in pixels:
        flat.extend(row)
    img.putdata(flat)

    return img


# ---------------------------------------------------------------------------
# DDS Reader (uncompressed 32-bit only — the format the remastered UI uses)
# ---------------------------------------------------------------------------

def read_dds(data):
    """Decode an uncompressed 32-bit DDS surface into a PIL RGBA Image.

    The remastered UI textures (cursors, power segments, progress bars) are all
    stored as uncompressed 32-bit surfaces with a standard 128-byte DDS header
    and no mipmaps. Compressed (FourCC / DX10) surfaces are not supported and
    return None so the caller can skip them.
    """
    if len(data) < 128 or data[:4] != b'DDS ':
        return None

    height = struct.unpack_from('<I', data, 12)[0]
    width = struct.unpack_from('<I', data, 16)[0]
    pitch = struct.unpack_from('<I', data, 20)[0]
    # DDS_PIXELFORMAT starts at offset 76: dwSize, dwFlags, dwFourCC, dwRGBBits,
    # then R/G/B/A masks.
    fourcc = data[84:88]
    rgb_bits = struct.unpack_from('<I', data, 88)[0]
    r_mask, g_mask, b_mask, a_mask = struct.unpack_from('<4I', data, 92)

    if fourcc != b'\x00\x00\x00\x00' or rgb_bits != 32:
        return None  # compressed / DX10 — not handled here

    if width == 0 or height == 0:
        return None
    if pitch == 0:
        pitch = width * 4

    # Choose the byte order from the channel masks. Remastered UI = BGRA.
    if (r_mask, g_mask, b_mask) == (0x000000FF, 0x0000FF00, 0x00FF0000):
        rawmode = 'RGBA'
    else:
        rawmode = 'BGRA'  # (0x00FF0000, 0x0000FF00, 0x000000FF) and default

    pix = data[128:]
    row_bytes = width * 4
    if pitch == row_bytes:
        buf = pix[:row_bytes * height]
    else:
        buf = b''.join(pix[y * pitch:y * pitch + row_bytes] for y in range(height))
    if len(buf) < row_bytes * height:
        return None

    return Image.frombuffer('RGBA', (width, height), buf, 'raw', rawmode, 0, 1).copy()


# ---------------------------------------------------------------------------
# Sprite Extraction
# ---------------------------------------------------------------------------

def extract_sprite_zip(zip_data, sprite_name, output_dir, save_sheet=True):
    """Extract frames from a sprite ZIP and save as PNGs.

    Each ZIP contains:
      <name>-NNNN.tga  -- cropped 32-bit RGBA frame
      <name>-NNNN.meta -- JSON {"size": [W,H], "crop": [L,T,R,B]}

    We reconstruct full-canvas frames and save as:
      <output_dir>/<SPRITE_NAME>/<SPRITE_NAME>-NNNN.png  (individual frames)
      <output_dir>/<SPRITE_NAME>.png                      (sprite sheet)
      <output_dir>/<SPRITE_NAME>.json                     (metadata manifest)

    Returns (frame_count, canvas_size) or None on failure.
    """
    try:
        zf = zipfile.ZipFile(io.BytesIO(zip_data))
    except zipfile.BadZipFile:
        return None

    # Collect frame pairs: frame_num -> (tga_name, meta_name)
    # Files use either '-' or '_' as separator: "e1-0000.tga" or "armor_0000.tga"
    frames = {}
    for name in zf.namelist():
        lower = name.lower()
        # Extract frame number from name like "e1-0000.tga" or "armor_0000.meta"
        base = name.rsplit('.', 1)[0]  # strip extension (.tga or .meta)
        # Try splitting on '-' first, then '_'
        parts = base.rsplit('-', 1)
        if len(parts) != 2 or not parts[1].isdigit():
            parts = base.rsplit('_', 1)
        if len(parts) != 2:
            continue
        try:
            frame_num = int(parts[1])
        except ValueError:
            continue

        if lower.endswith('.tga'):
            frames.setdefault(frame_num, {})['tga'] = name
        elif lower.endswith('.meta'):
            frames.setdefault(frame_num, {})['meta'] = name

    if not frames:
        return None

    # Sort by frame number
    sorted_frames = sorted(frames.items())

    # Determine if we have meta files
    has_meta = any('meta' in info for _, info in sorted_frames)

    # Read canvas size from first meta, or determine from TGA sizes
    canvas_w, canvas_h = 0, 0
    if has_meta:
        # Scan all metas to find the true canvas (some report 1x1)
        for _, info in sorted_frames:
            meta_name = info.get('meta')
            if meta_name:
                meta = json.loads(zf.read(meta_name))
                mw, mh = meta['size']
                crop = meta.get('crop', [0, 0, mw, mh])
                # Use the larger of declared size vs crop extents
                canvas_w = max(canvas_w, mw, crop[2] if len(crop) > 2 else mw)
                canvas_h = max(canvas_h, mh, crop[3] if len(crop) > 3 else mh)
                if mw > 1 and mh > 1:
                    break  # found a real canvas size
    else:
        # No meta files — find max TGA dimensions to use as canvas
        for _, info in sorted_frames:
            tga_name = info.get('tga')
            if tga_name:
                tga_data = zf.read(tga_name)
                if len(tga_data) >= 18:
                    w = struct.unpack_from('<H', tga_data, 12)[0]
                    h = struct.unpack_from('<H', tga_data, 14)[0]
                    canvas_w = max(canvas_w, w)
                    canvas_h = max(canvas_h, h)
        if canvas_w == 0 or canvas_h == 0:
            zf.close()
            return None

    # Create output directory for individual frames
    sprite_dir = os.path.join(output_dir, sprite_name)
    os.makedirs(sprite_dir, exist_ok=True)

    # Process each frame
    pil_frames = []
    frame_metadata = []
    failed_frames = 0

    for frame_num, info in sorted_frames:
        tga_name = info.get('tga')
        meta_name = info.get('meta')

        if not tga_name:
            failed_frames += 1
            continue

        # Read and decode TGA
        tga_data = zf.read(tga_name)
        tga_img = read_tga(tga_data)
        if tga_img is None:
            failed_frames += 1
            continue

        if meta_name:
            # Has meta — reconstruct full canvas with crop positioning
            meta = json.loads(zf.read(meta_name))
            cw, ch = meta['size']
            crop = meta['crop']  # [left, top, right, bottom]

            # Ensure canvas is large enough (some sprites report 1x1 canvas)
            actual_w = max(cw, crop[2] if len(crop) > 2 else cw)
            actual_h = max(ch, crop[3] if len(crop) > 3 else ch)
            cw, ch = actual_w, actual_h

            canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
            canvas.paste(tga_img, (crop[0], crop[1]))
        else:
            # No meta — TGA is the full frame, center on canvas if sizes differ
            cw, ch = canvas_w, canvas_h
            if tga_img.size == (cw, ch):
                canvas = tga_img
            else:
                canvas = Image.new('RGBA', (cw, ch), (0, 0, 0, 0))
                # Center the image on the canvas
                ox = (cw - tga_img.size[0]) // 2
                oy = (ch - tga_img.size[1]) // 2
                canvas.paste(tga_img, (ox, oy))
            crop = [0, 0, tga_img.size[0], tga_img.size[1]]

        # Save individual frame
        frame_path = os.path.join(sprite_dir, f"{sprite_name}-{frame_num:04d}.png")
        canvas.save(frame_path, 'PNG')

        pil_frames.append(canvas)
        frame_metadata.append({
            'frame': frame_num,
            'crop': crop,
            'crop_w': crop[2] - crop[0],
            'crop_h': crop[3] - crop[1],
        })

    if not pil_frames:
        return None

    # Save metadata manifest
    manifest = {
        'name': sprite_name,
        'canvas_width': canvas_w,
        'canvas_height': canvas_h,
        'frame_count': len(pil_frames),
        'frames': frame_metadata,
    }
    manifest_path = os.path.join(output_dir, f"{sprite_name}.json")
    with open(manifest_path, 'w') as f:
        json.dump(manifest, f, indent=2)

    # Generate sprite sheet (frames arranged in a grid)
    if save_sheet and pil_frames:
        sheet = make_sprite_sheet(pil_frames, canvas_w, canvas_h)
        sheet_path = os.path.join(output_dir, f"{sprite_name}.png")
        sheet.save(sheet_path, 'PNG')

    zf.close()
    return (len(pil_frames), (canvas_w, canvas_h))


def make_sprite_sheet(frames, frame_w, frame_h, max_cols=16):
    """Arrange frames into a grid sprite sheet."""
    n = len(frames)
    cols = min(n, max_cols)
    rows = (n + cols - 1) // cols

    sheet = Image.new('RGBA', (cols * frame_w, rows * frame_h), (0, 0, 0, 0))

    for i, frame in enumerate(frames):
        col = i % cols
        row = i // cols
        sheet.paste(frame, (col * frame_w, row * frame_h))

    return sheet


# ---------------------------------------------------------------------------
# MEG Path Helpers
# ---------------------------------------------------------------------------

# The MEG path prefix for TD sprites
MEG_PREFIX = "DATA\\ART\\TEXTURES\\SRGB\\TIBERIAN_DAWN\\"


def categorize_meg_entries(meg):
    """Sort MEG entries into categories by subdirectory."""
    units = {}      # name -> meg_path
    structures = {}
    vfx = {}

    for name, size in meg.list_files():
        if not name.startswith(MEG_PREFIX):
            continue
        rel = name[len(MEG_PREFIX):]

        if rel.startswith("UNITS\\") and rel.upper().endswith('.ZIP'):
            sprite_name = rel.split('\\')[-1].replace('.ZIP', '').replace('.zip', '')
            units[sprite_name.upper()] = name
        elif rel.startswith("STRUCTURES\\") and rel.upper().endswith('.ZIP'):
            sprite_name = rel.split('\\')[-1].replace('.ZIP', '').replace('.zip', '')
            structures[sprite_name.upper()] = name
        elif rel.startswith("VFX\\") and rel.upper().endswith('.ZIP'):
            sprite_name = rel.split('\\')[-1].replace('.ZIP', '').replace('.zip', '')
            vfx[sprite_name.upper()] = name

    return units, structures, vfx


# ---------------------------------------------------------------------------
# Remastered UI extraction (cursors, power segments, progress/fill bars)
# ---------------------------------------------------------------------------

# Texture-atlas prefix inside TEXTURES_SRGB.MEG (UI lives at the top level).
UI_TEX_PREFIX = "DATA\\ART\\TEXTURES\\SRGB\\"

# Sidebar / meter / progress fill textures we care about (base name, no .DDS).
# The remastered sidebar chrome itself is vector/HTML (no bitmap) and the build
# cameos were never remastered, so the extractable HD sidebar art is the power
# meter segments plus the various fill bars.
UI_SIDEBAR_TEXTURES = [
    "UI_SIDEBAR_POWERSEGMENT_EMPTY",
    "UI_SIDEBAR_POWERSEGMENT_FILLED",
    "UI_TOOLTIP_INPROGRESS_FILLED",
    "UI_TRAINQUEUEBAR_FILLED",
    "UI_WAVETIMER_PROGRESS_00",
    "UI_RESOURCEBAR_FILLED_CURRENT",
    "UI_RESOURCEBAR_FILLED_GOLD",
    "UI_RESOURCEBAR_FILLED_GROWTH",
    "UI_RESOURCEBAR_FILLED_LOSS",
    "UI_RESOURCEBAR_FILLED_COMMAND",
    "UI_XPBAR_FILLED_MID",
    "UI_HEALTHBAR_FILLED_GREYSCALE",
    "UI_HERO_HEALTHBAR_FILLED",
]


def _parse_mouse_pointers(config_meg):
    """Parse MOUSEPOINTERS(.X2).XML → {pointer_name: (texture_family, hotX, hotY)}.

    texture_family is the uppercased base name with the extension stripped, e.g.
    "icon_movement_command.tga" → "ICON_MOVEMENT_COMMAND", which matches the DDS
    family stem in TEXTURES_SRGB.MEG.
    """
    import re

    def parse(xml_name):
        raw = config_meg.read_file(xml_name)
        if raw is None:
            return {}
        text = raw.decode('utf-8', 'replace')
        out = {}
        for m in re.finditer(
                r'<MousePointerDataClass\s+Name="([^"]+)">(.*?)</MousePointerDataClass>',
                text, re.S):
            name, body = m.group(1), m.group(2)
            tex = re.search(r'<BaseTextureName>\s*(\S+)\s*</BaseTextureName>', body)
            hx = re.search(r'<HotX>\s*(-?\d+)\s*</HotX>', body)
            hy = re.search(r'<HotY>\s*(-?\d+)\s*</HotY>', body)
            if not tex:
                continue
            fam = tex.group(1).rsplit('.', 1)[0].upper()
            out[name] = (fam, int(hx.group(1)) if hx else 0, int(hy.group(1)) if hy else 0)
        return out

    return parse('DATA\\XML\\MOUSEPOINTERS.XML'), parse('DATA\\XML\\MOUSEPOINTERSX2.XML')


def extract_ui(data_dir, output_dir):
    """Extract remastered cursors and sidebar meter/progress textures to PNG."""
    import re

    tex_path = os.path.join(data_dir, 'TEXTURES_SRGB.MEG')
    if not os.path.exists(tex_path):
        print(f"ERROR: {tex_path} not found (needed for UI textures)")
        return
    tex = MEGFile(tex_path)
    config_path = os.path.join(data_dir, 'CONFIG.MEG')
    config = MEGFile(config_path) if os.path.exists(config_path) else None

    ui_dir = os.path.join(output_dir, 'ui')
    cur_dir = os.path.join(ui_dir, 'cursors')
    side_dir = os.path.join(ui_dir, 'sidebar')
    os.makedirs(cur_dir, exist_ok=True)
    os.makedirs(side_dir, exist_ok=True)

    # --- Group cursor families -------------------------------------------------
    # family stem (e.g. ICON_MOVEMENT_COMMAND) + scale (1 or 2) -> [(frame, meg)]
    fam_frames = {}
    for name in tex.entries:
        if not name.startswith(UI_TEX_PREFIX):
            continue
        rel = name[len(UI_TEX_PREFIX):]
        if '\\' in rel or not rel.upper().endswith('.DDS'):
            continue
        stem = rel[:-4]
        if not stem.upper().startswith('ICON_'):
            continue
        m = re.match(r'(.*?)(_X2)?_(\d+)$', stem, re.I)
        if m:
            fam, is_x2, num = m.group(1).upper(), bool(m.group(2)), int(m.group(3))
        else:
            m2 = re.match(r'(.*?)(_X2)?$', stem, re.I)
            fam, is_x2, num = m2.group(1).upper(), bool(m2.group(2)), 0
        fam_frames.setdefault((fam, 2 if is_x2 else 1), []).append((num, name))

    families = {}
    print("=== CURSORS ===")
    for (fam, scale), frames in sorted(fam_frames.items()):
        frames.sort()
        out_frames = []
        w = h = 0
        for i, (num, meg_name) in enumerate(frames):
            img = read_dds(tex.read_file(meg_name))
            if img is None:
                continue
            w, h = img.size
            suffix = '_X2' if scale == 2 else ''
            fdir = os.path.join(cur_dir, fam)
            os.makedirs(fdir, exist_ok=True)
            img.save(os.path.join(fdir, f"{fam}{suffix}-{i:04d}.png"), 'PNG')
            out_frames.append(i)
        if not out_frames:
            continue
        entry = families.setdefault(fam, {})
        if scale == 2:
            entry.update({'x2_frames': len(out_frames), 'x2_w': w, 'x2_h': h})
        else:
            entry.update({'frames': len(out_frames), 'w': w, 'h': h})
        print(f"  OK: {fam:36s} {'x2' if scale==2 else '1x'}  {len(out_frames):3d} frames  {w}x{h}")

    # --- Cursor manifest (semantic pointer -> family + hotspot) ---------------
    pointers = {}
    if config is not None:
        hot1, hot2 = _parse_mouse_pointers(config)
        for pname, (fam, hx, hy) in hot1.items():
            if fam not in families:
                continue  # references a texture we didn't extract (scroll edges, etc.)
            rec = {'family': fam, 'hotX': hx, 'hotY': hy}
            if pname in hot2:
                _, hx2, hy2 = hot2[pname]
                rec['hotX_x2'] = hx2
                rec['hotY_x2'] = hy2
            pointers[pname] = rec

    manifest = {'pointers': pointers, 'families': families}
    with open(os.path.join(cur_dir, 'cursors.json'), 'w') as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
    print(f"  manifest: {len(families)} families, {len(pointers)} named pointers")

    # --- Sidebar / meter / progress fill textures -----------------------------
    print("\n=== SIDEBAR / METERS ===")
    side_manifest = {}
    for base in UI_SIDEBAR_TEXTURES:
        meg_name = UI_TEX_PREFIX + base + '.DDS'
        raw = tex.read_file(meg_name)
        if raw is None:
            print(f"  MISSING: {base}")
            continue
        img = read_dds(raw)
        if img is None:
            print(f"  UNSUPPORTED FORMAT: {base}")
            continue
        img.save(os.path.join(side_dir, base + '.png'), 'PNG')
        side_manifest[base] = {'w': img.size[0], 'h': img.size[1]}
        print(f"  OK: {base:36s} {img.size[0]}x{img.size[1]}")
    with open(os.path.join(side_dir, 'sidebar.json'), 'w') as f:
        json.dump(side_manifest, f, indent=2, sort_keys=True)

    print(f"\n  UI output: {ui_dir}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Extract remastered sprites from C&C Remastered MEG archives")
    parser.add_argument('--remastered-dir',
                        default=os.path.expanduser('~/CnCRemastered/Data'),
                        help='Path to CnCRemastered/Data directory')
    parser.add_argument('--output-dir', default=None,
                        help='Output directory for extracted sprites')
    parser.add_argument('--no-sheets', action='store_true',
                        help='Skip sprite sheet generation (only save individual frames)')
    parser.add_argument('--only', default=None,
                        help='Only extract specific sprite(s), comma-separated (e.g., E1,MTNK,FACT)')
    parser.add_argument('--category', default=None,
                        choices=['units', 'structures', 'vfx', 'ui', 'all'],
                        help='Only extract specific category (default: all)')
    args = parser.parse_args()

    data_dir = args.remastered_dir
    if args.output_dir:
        output_dir = args.output_dir
    else:
        output_dir = os.path.join(
            os.path.expanduser('~/Library/Application Support/Vanilla-Conquer/vanillatd'),
            'extracted', 'sprites_remastered')

    if not os.path.isdir(data_dir):
        print(f"ERROR: Remastered data directory not found: {data_dir}")
        print("Download with: steamcmd +@sSteamCmdForcePlatformType windows ...")
        sys.exit(1)

    # UI (cursors + sidebar meters) lives in TEXTURES_SRGB.MEG / CONFIG.MEG, not
    # the TD sprite MEG — handle it standalone so it works even without the TD MEG.
    if (args.category or 'all') == 'ui':
        print(f"Remastered data: {data_dir}")
        print(f"Output:          {output_dir}\n")
        extract_ui(data_dir, output_dir)
        return

    meg_path = os.path.join(data_dir, 'TEXTURES_TD_SRGB.MEG')
    if not os.path.exists(meg_path):
        print(f"ERROR: Textures MEG not found: {meg_path}")
        sys.exit(1)

    print(f"Remastered data: {data_dir}")
    print(f"Output:          {output_dir}")
    print()

    # Parse MEG
    print(f"Reading {meg_path}...")
    meg = MEGFile(meg_path)
    print(f"  Total entries: {len(meg.entries)}")

    # Categorize entries
    units, structures, vfx = categorize_meg_entries(meg)
    print(f"  Units:      {len(units)}")
    print(f"  Structures: {len(structures)}")
    print(f"  VFX:        {len(vfx)}")
    print()

    # Filter if requested
    only_set = None
    if args.only:
        only_set = set(s.strip().upper() for s in args.only.split(','))

    category = args.category or 'all'
    save_sheets = not args.no_sheets

    extracted = 0
    failed = 0

    # --- Units ---
    if category in ('all', 'units'):
        print("=== UNITS ===")
        unit_dir = os.path.join(output_dir, 'units')
        os.makedirs(unit_dir, exist_ok=True)

        for sprite_name in sorted(units.keys()):
            if only_set and sprite_name not in only_set:
                continue

            meg_name = units[sprite_name]
            zip_data = meg.read_file(meg_name)
            if zip_data is None:
                print(f"  FAILED to read: {sprite_name}")
                failed += 1
                continue

            result = extract_sprite_zip(zip_data, sprite_name, unit_dir, save_sheets)
            if result is None:
                print(f"  FAILED to extract: {sprite_name}")
                failed += 1
                continue

            frame_count, (cw, ch) = result
            sheet_info = ""
            if save_sheets:
                sheet_path = os.path.join(unit_dir, f"{sprite_name}.png")
                if os.path.exists(sheet_path):
                    mb = os.path.getsize(sheet_path) / 1024 / 1024
                    sheet_info = f"  sheet: {mb:.1f}MB"
            print(f"  OK: {sprite_name:12s}  {frame_count:4d} frames  {cw}x{ch} canvas{sheet_info}")
            extracted += 1

    # --- Structures ---
    if category in ('all', 'structures'):
        print()
        print("=== STRUCTURES ===")
        struct_dir = os.path.join(output_dir, 'structures')
        os.makedirs(struct_dir, exist_ok=True)

        for sprite_name in sorted(structures.keys()):
            if only_set and sprite_name not in only_set:
                continue

            meg_name = structures[sprite_name]
            zip_data = meg.read_file(meg_name)
            if zip_data is None:
                print(f"  FAILED to read: {sprite_name}")
                failed += 1
                continue

            result = extract_sprite_zip(zip_data, sprite_name, struct_dir, save_sheets)
            if result is None:
                print(f"  FAILED to extract: {sprite_name}")
                failed += 1
                continue

            frame_count, (cw, ch) = result
            sheet_info = ""
            if save_sheets:
                sheet_path = os.path.join(struct_dir, f"{sprite_name}.png")
                if os.path.exists(sheet_path):
                    mb = os.path.getsize(sheet_path) / 1024 / 1024
                    sheet_info = f"  sheet: {mb:.1f}MB"
            print(f"  OK: {sprite_name:12s}  {frame_count:4d} frames  {cw}x{ch} canvas{sheet_info}")
            extracted += 1

    # --- VFX ---
    if category in ('all', 'vfx'):
        print()
        print("=== VFX ===")
        vfx_dir = os.path.join(output_dir, 'vfx')
        os.makedirs(vfx_dir, exist_ok=True)

        for sprite_name in sorted(vfx.keys()):
            if only_set and sprite_name not in only_set:
                continue

            meg_name = vfx[sprite_name]
            zip_data = meg.read_file(meg_name)
            if zip_data is None:
                print(f"  FAILED to read: {sprite_name}")
                failed += 1
                continue

            result = extract_sprite_zip(zip_data, sprite_name, vfx_dir, save_sheets)
            if result is None:
                print(f"  FAILED to extract: {sprite_name}")
                failed += 1
                continue

            frame_count, (cw, ch) = result
            sheet_info = ""
            if save_sheets:
                sheet_path = os.path.join(vfx_dir, f"{sprite_name}.png")
                if os.path.exists(sheet_path):
                    mb = os.path.getsize(sheet_path) / 1024 / 1024
                    sheet_info = f"  sheet: {mb:.1f}MB"
            print(f"  OK: {sprite_name:12s}  {frame_count:4d} frames  {cw}x{ch} canvas{sheet_info}")
            extracted += 1

    # --- UI (cursors + sidebar meters) ---
    if category == 'all':
        print()
        extract_ui(data_dir, output_dir)

    print()
    print("=" * 60)
    print(f"  Extracted: {extracted} sprites")
    print(f"  Failed:    {failed}")
    print(f"  Output:    {output_dir}")
    print("=" * 60)


if __name__ == '__main__':
    main()
