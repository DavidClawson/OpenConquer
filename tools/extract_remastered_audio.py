#!/usr/bin/env python3
"""
Extract remastered audio from C&C Remastered Collection MEG archives.

Reads MEG V3 files (SFX3D.MEG, SFX2D_EN-US.MEG, MUSIC.MEG) and extracts
the remastered (TDR_*) WAV files, converting from MS ADPCM to PCM WAV
and renaming to match the engine's expected filenames.

Usage:
    python3 tools/extract_remastered_audio.py [--remastered-dir PATH] [--output-dir PATH]

Default remastered dir: ~/CnCRemastered/Data
Default output dir:     ~/Library/Application Support/Vanilla-Conquer/vanillatd/extracted/audio_remastered/
"""

import struct
import os
import sys
import argparse
from pathlib import Path

# ---------------------------------------------------------------------------
# MEG V3 Reader
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
# MS ADPCM Decoder
# ---------------------------------------------------------------------------

# Standard MS ADPCM adaptation table
ADAPTATION_TABLE = [
    230, 230, 230, 230, 307, 409, 512, 614,
    768, 614, 512, 409, 307, 230, 230, 230
]

# Default MS ADPCM coefficient pairs (7 standard pairs)
DEFAULT_COEFS = [
    (256, 0),
    (512, -256),
    (0, 0),
    (192, 64),
    (240, 0),
    (460, -208),
    (392, -232),
]


def decode_ms_adpcm_wav(data):
    """Decode an MS ADPCM WAV file to PCM samples.

    Returns (samples, sample_rate, channels) or None on failure.
    samples is a list of interleaved Int16 values.
    """
    if data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        return None

    # Parse chunks
    pos = 12
    fmt_data = None
    audio_data = None

    while pos + 8 <= len(data):
        chunk_id = data[pos:pos + 4]
        chunk_size = struct.unpack_from('<I', data, pos + 4)[0]
        chunk_body = data[pos + 8:pos + 8 + chunk_size]

        if chunk_id == b'fmt ':
            fmt_data = chunk_body
        elif chunk_id == b'data':
            audio_data = chunk_body
        elif chunk_id == b'fact':
            pass  # ignore

        pos += 8 + chunk_size
        if pos % 2 != 0:
            pos += 1  # chunks are word-aligned

    if fmt_data is None or audio_data is None:
        return None

    # Parse fmt chunk
    fmt_code = struct.unpack_from('<H', fmt_data, 0)[0]
    if fmt_code != 2:
        # Not MS ADPCM — check if it's already PCM
        if fmt_code == 1:
            channels = struct.unpack_from('<H', fmt_data, 2)[0]
            sample_rate = struct.unpack_from('<I', fmt_data, 4)[0]
            bps = struct.unpack_from('<H', fmt_data, 14)[0]
            if bps == 16:
                samples = []
                for i in range(0, len(audio_data) - 1, 2):
                    samples.append(struct.unpack_from('<h', audio_data, i)[0])
                return (samples, sample_rate, channels)
        return None

    channels = struct.unpack_from('<H', fmt_data, 2)[0]
    sample_rate = struct.unpack_from('<I', fmt_data, 4)[0]
    block_align = struct.unpack_from('<H', fmt_data, 12)[0]
    # bits_per_sample = struct.unpack_from('<H', fmt_data, 14)[0]  # always 4

    # Extra format data
    extra_size = struct.unpack_from('<H', fmt_data, 16)[0]
    samples_per_block = struct.unpack_from('<H', fmt_data, 18)[0]
    num_coefs = struct.unpack_from('<H', fmt_data, 20)[0]

    # Read coefficient pairs
    coefs = []
    coef_offset = 22
    for i in range(num_coefs):
        if coef_offset + 4 <= len(fmt_data):
            c1 = struct.unpack_from('<h', fmt_data, coef_offset)[0]
            c2 = struct.unpack_from('<h', fmt_data, coef_offset + 2)[0]
            coefs.append((c1, c2))
            coef_offset += 4
        else:
            coefs.append(DEFAULT_COEFS[i] if i < len(DEFAULT_COEFS) else (0, 0))

    # Pad with defaults if needed
    while len(coefs) < 7:
        coefs.append(DEFAULT_COEFS[len(coefs)])

    # Decode blocks
    all_samples = []
    block_pos = 0

    while block_pos + block_align <= len(audio_data):
        block = audio_data[block_pos:block_pos + block_align]
        block_samples = _decode_ms_adpcm_block(block, channels, coefs, samples_per_block)
        all_samples.extend(block_samples)
        block_pos += block_align

    return (all_samples, sample_rate, channels)


def _decode_ms_adpcm_block(block, channels, coefs, samples_per_block):
    """Decode a single MS ADPCM block."""
    pos = 0

    # Read block preamble (per channel)
    predictor_indices = []
    for _ in range(channels):
        idx = block[pos]
        if idx >= len(coefs):
            idx = 0
        predictor_indices.append(idx)
        pos += 1

    deltas = []
    for _ in range(channels):
        deltas.append(struct.unpack_from('<h', block, pos)[0])
        pos += 2

    sample1 = []  # second-to-last sample
    for _ in range(channels):
        sample1.append(struct.unpack_from('<h', block, pos)[0])
        pos += 2

    sample2 = []  # third-to-last sample
    for _ in range(channels):
        sample2.append(struct.unpack_from('<h', block, pos)[0])
        pos += 2

    # Output buffer — preamble gives us 2 samples per channel
    # Order: sample2 first, then sample1 (they're stored reverse order)
    output = []
    if channels == 1:
        output.append(sample2[0])
        output.append(sample1[0])
    else:
        output.append(sample2[0])
        output.append(sample2[1])
        output.append(sample1[0])
        output.append(sample1[1])

    # Decode nibbles
    total_samples = samples_per_block * channels
    sample_count = 2 * channels  # already have 2 per channel

    while pos < len(block) and sample_count < total_samples:
        byte = block[pos]
        pos += 1

        # High nibble first, then low nibble
        for nibble_shift in [4, 0]:
            if sample_count >= total_samples:
                break

            nibble = (byte >> nibble_shift) & 0x0F
            # Sign-extend nibble
            if nibble >= 8:
                nibble -= 16

            ch = sample_count % channels
            c1, c2 = coefs[predictor_indices[ch]]

            # Predict
            predicted = (sample1[ch] * c1 + sample2[ch] * c2) >> 8

            # Add error
            sample = predicted + nibble * deltas[ch]
            sample = max(-32768, min(32767, sample))

            output.append(sample)

            # Update state
            sample2[ch] = sample1[ch]
            sample1[ch] = sample

            # Adapt delta
            deltas[ch] = max(16, (deltas[ch] * ADAPTATION_TABLE[nibble & 0x0F]) >> 8)

            sample_count += 1

    return output


# ---------------------------------------------------------------------------
# WAV Writer
# ---------------------------------------------------------------------------

def write_pcm_wav(path, samples, sample_rate, channels=1):
    """Write a standard 16-bit PCM WAV file."""
    bits_per_sample = 16
    byte_rate = sample_rate * channels * (bits_per_sample // 8)
    block_align = channels * (bits_per_sample // 8)
    data_size = len(samples) * 2

    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + data_size))
        f.write(b'WAVE')

        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(struct.pack('<H', 1))  # PCM
        f.write(struct.pack('<H', channels))
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', byte_rate))
        f.write(struct.pack('<H', block_align))
        f.write(struct.pack('<H', bits_per_sample))

        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        for s in samples:
            f.write(struct.pack('<h', max(-32768, min(32767, int(s)))))


# ---------------------------------------------------------------------------
# Filename Mapping: Remastered names → Engine names
# ---------------------------------------------------------------------------

# Music: TDR_MUS_<REMASTERED_NAME> → <ENGINE_FILENAME>
# Built from ThemeType in GameAudio.swift
MUSIC_MAP = {
    "ACT_ON_INSTINCT": "AOI",
    "AIRSTRIKE": "AIRSTRIK",
    "CC_80S_MIX": "80MX",
    "CANYON_CHASE": "CHRG",
    "CREEPING_UPON": "CREP",
    "DRILL": "DRIL",
    "DRONE": "DRON",
    "IRON_FIST": "FIST",
    "RECON": "RECON",
    "VOICE_OF_ROME": "VOICE",
    "HEAVY_GLOVE": "HEAVYG",
    "JUST_DO_IT_UP": "JUSTDOIT",
    "CC_THANG": "CCTHANG",
    "DIE": "DIE",
    "FIGHT_WIN_PREVAIL": "FWP",
    "INDUSTRIAL": "IND",
    "INDUSTRIAL_2": "IND2",
    "IN_THE_LINE_OF_FIRE": "LINEFIRE",
    "MARCH_TO_YOUR_DOOM": "MARCH",
    "MECHANICAL_MAN": "J1",
    "JDI_V2": "JDI_V2",
    "NO_MERCY": "NOMERCY",
    "ON_THE_PROWL": "OTP",
    "PREPARE_FOR_BATTLE": "PRP",
    "REACHING_OUT": "ROUT",
    "DECEPTION": "HEART",
    "STOP_THEM": "STOPTHEM",
    "LOOKS_LIKE_TROUBLE": "TROUBLE",
    "WARFARE": "WARFARE",
    "ENEMIES_TO_BE_FEARED": "BFEARED",
    "I_AM": "IAM",
    "TARGET_MECHANICAL_MAN": "J1",
    "GREAT_SHOT": "WIN1",
    "MAP_SELECT": "MAP1",
    "RADIO": "RADIO",
    "RAIN_IN_THE_NIGHT": "RAIN",
    "RIDE_OF_THE_VALKYRIES": "VALKYRIE",
}

# EVA speech: TDR_SFX_EVA_<NAME>_EN-US → <ENGINE_FILENAME>
# Built from VoxType in GameAudio.swift
EVA_MAP = {
    "ACCOM1": "ACCOM1",
    "FAIL1": "FAIL1",
    "BLDG1": "BLDG1",
    "CONSTRU1": "CONSTRU1",
    "UNITREDY": "UNITREDY",
    "NEWOPT1": "NEWOPT1",
    "DEPLOY1": "DEPLOY1",
    "GDIDEAD1": "GDIDEAD1",
    "NODDEAD1": "NODDEAD1",
    "CIVDEAD1": "CIVDEAD1",
    "NOCASH1": "NOCASH1",
    "BATLCON1": "BATLCON1",
    "REINFOR1": "REINFOR1",
    "CANCEL1": "CANCEL1",
    "BLDGING1": "BLDGING1",
    "LOPOWER1": "LOPOWER1",
    "NOPOWER1": "NOPOWER1",
    "MOCASH1": "MOCASH1",
    "BASEATK1": "BASEATK1",
    "INCOME1": "INCOME1",
    "ENEMYA": "ENEMYA",
    "NUKE1": "NUKE1",
    "NOBUILD1": "NOBUILD1",
    "PRIBLDG1": "PRIBLDG1",
    "NODCAPT1": "NODCAPT1",
    "GDICAPT1": "GDICAPT1",
    "IONCHRG1": "IONCHRG1",
    "IONREDY1": "IONREDY1",
    "NUKAVAIL": "NUKAVAIL",
    "NUKLNCH1": "NUKLNCH1",
    "UNITLOST": "UNITLOST",
    "STRCLOST": "STRCLOST",
    "NEEDHARV": "NEEDHARV",
    "SELECT1": "SELECT1",
    "AIRREDY1": "AIRREDY1",
    "NOREDY1": "NOREDY1",
    "TRANSSEE": "TRANSSEE",
    "TRANLOAD": "TRANLOAD",
    "ENMYAPP1": "ENMYAPP1",
    "SILOS1": "SILOS1",
    "ONHOLD1": "ONHOLD1",
    "REPAIR1": "REPAIR1",
    "ESTRUCX": "ESTRUCX",
    "GSTRUC1": "GSTRUC1",
    "NSTRUC1": "NSTRUC1",
    "ENMYUNIT": "ENMYUNIT",
}


def map_sfx3d_name(meg_name):
    """Map SFX3D filename: TDR_SFX_BAZOOK1.WAV → BAZOOK1"""
    base = meg_name.replace('.WAV', '')
    if base.startswith('TDR_SFX_'):
        return base[8:]  # strip TDR_SFX_
    return None


def map_sfx2d_name(meg_name):
    """Map SFX2D filename to engine name.

    Patterns:
      EN-US\\TDR_SFX_UNT_YESSIR1.V00_EN-US.WAV → YESSIR1
      EN-US\\TDR_SFX_EVA_BASEATK1_EN-US.WAV → BASEATK1
      EN-US\\TDR_SFX_CMD_BOMBIT1_EN-US.WAV → BOMBIT1
    """
    # Strip directory prefix
    if '\\' in meg_name:
        meg_name = meg_name.split('\\')[-1]

    # Only want remastered TD files
    if not meg_name.startswith('TDR_SFX_'):
        return None

    base = meg_name.replace('.WAV', '')

    # Strip _EN-US suffix
    if base.endswith('_EN-US'):
        base = base[:-6]

    # Strip language suffixes like _DE
    for suffix in ['_DE', '_FR', '_JA', '_KO', '_ZH']:
        if base.endswith(suffix):
            return None  # skip non-English

    # Unit voices: TDR_SFX_UNT_YESSIR1.V00 → YESSIR1
    if base.startswith('TDR_SFX_UNT_'):
        name = base[len('TDR_SFX_UNT_'):]  # strip prefix
        # Strip variation extension (.V00, .V01, etc.) — we take V00 as default
        for ext in ['.V00', '.V01', '.V02', '.V03']:
            if ext in name:
                if ext != '.V00':
                    return None  # skip non-V00 variations
                name = name.replace(ext, '')
                break
        return name

    # EVA speech: TDR_SFX_EVA_BASEATK1 → BASEATK1
    if base.startswith('TDR_SFX_EVA_'):
        name = base[len('TDR_SFX_EVA_'):]
        return name if name in EVA_MAP else None

    # Commando: TDR_SFX_CMD_BOMBIT1 → BOMBIT1
    if base.startswith('TDR_SFX_CMD_'):
        return base[len('TDR_SFX_CMD_'):]

    return None


def map_music_name(meg_name):
    """Map music filename: DATA\\AUDIO\\MUSIC\\TDR_MUS_ACT_ON_INSTINCT.WAV → AOI"""
    # Strip path
    if '\\' in meg_name:
        meg_name = meg_name.split('\\')[-1]

    base = meg_name.replace('.WAV', '')

    # Only remastered TD music
    if not base.startswith('TDR_MUS_'):
        return None

    track_name = base[8:]  # strip TDR_MUS_

    # Skip OST/bonus versions — take the base version
    for suffix in ['_OST_VERSION', '_FKTS', '_CO', '_SHORT']:
        if track_name.endswith(suffix):
            track_name = track_name[:-len(suffix)]
            break

    return MUSIC_MAP.get(track_name)


# ---------------------------------------------------------------------------
# Stereo to Mono Downmix
# ---------------------------------------------------------------------------

def stereo_to_mono(samples, channels):
    """Downmix interleaved stereo samples to mono."""
    if channels == 1:
        return samples
    mono = []
    for i in range(0, len(samples) - channels + 1, channels):
        avg = sum(samples[i:i + channels]) // channels
        mono.append(max(-32768, min(32767, avg)))
    return mono


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Extract remastered audio from C&C Remastered MEG archives")
    parser.add_argument('--remastered-dir', default=os.path.expanduser('~/CnCRemastered/Data'),
                        help='Path to CnCRemastered/Data directory')
    parser.add_argument('--output-dir', default=None,
                        help='Output directory for extracted WAV files')
    parser.add_argument('--keep-stereo', action='store_true',
                        help='Keep stereo files as-is (default: downmix to mono)')
    args = parser.parse_args()

    data_dir = args.remastered_dir
    if args.output_dir:
        output_dir = args.output_dir
    else:
        output_dir = os.path.join(
            os.path.expanduser('~/Library/Application Support/Vanilla-Conquer/vanillatd'),
            'extracted', 'audio_remastered')

    os.makedirs(output_dir, exist_ok=True)

    if not os.path.isdir(data_dir):
        print(f"ERROR: Remastered data directory not found: {data_dir}")
        print("Download with: steamcmd +@sSteamCmdForcePlatformType windows ...")
        sys.exit(1)

    print(f"Remastered data: {data_dir}")
    print(f"Output:          {output_dir}")
    print()

    extracted = 0
    failed = 0
    skipped = 0

    # --- SFX3D: weapon/explosion sounds ---
    sfx3d_path = os.path.join(data_dir, 'SFX3D.MEG')
    if os.path.exists(sfx3d_path):
        print("=== SFX3D.MEG (weapons, explosions, ambient) ===")
        meg = MEGFile(sfx3d_path)
        for meg_name, size in sorted(meg.list_files()):
            engine_name = map_sfx3d_name(meg_name)
            if engine_name is None:
                continue

            wav_data = meg.read_file(meg_name)
            result = decode_ms_adpcm_wav(wav_data)
            if result is None:
                print(f"  FAILED: {meg_name}")
                failed += 1
                continue

            samples, sample_rate, channels = result
            if channels > 1 and not args.keep_stereo:
                samples = stereo_to_mono(samples, channels)
                channels = 1

            out_path = os.path.join(output_dir, f"{engine_name}.WAV")
            write_pcm_wav(out_path, samples, sample_rate, channels)
            dur = len(samples) / (sample_rate * channels)
            print(f"  OK: {engine_name}.WAV  {sample_rate}Hz {channels}ch  {dur:.2f}s  <- {meg_name}")
            extracted += 1
    else:
        print(f"WARNING: {sfx3d_path} not found")

    # --- SFX2D_EN-US: voices, EVA, commando ---
    sfx2d_path = os.path.join(data_dir, 'SFX2D_EN-US.MEG')
    if os.path.exists(sfx2d_path):
        print()
        print("=== SFX2D_EN-US.MEG (voices, EVA, commando) ===")
        meg = MEGFile(sfx2d_path)

        # Track what we've already extracted to avoid duplicates
        seen = set()
        for meg_name, size in sorted(meg.list_files()):
            engine_name = map_sfx2d_name(meg_name)
            if engine_name is None:
                continue
            if engine_name in seen:
                continue
            seen.add(engine_name)

            wav_data = meg.read_file(meg_name)
            result = decode_ms_adpcm_wav(wav_data)
            if result is None:
                print(f"  FAILED: {meg_name}")
                failed += 1
                continue

            samples, sample_rate, channels = result
            if channels > 1 and not args.keep_stereo:
                samples = stereo_to_mono(samples, channels)
                channels = 1

            out_path = os.path.join(output_dir, f"{engine_name}.WAV")
            write_pcm_wav(out_path, samples, sample_rate, channels)
            dur = len(samples) / (sample_rate * channels)
            print(f"  OK: {engine_name}.WAV  {sample_rate}Hz {channels}ch  {dur:.2f}s  <- {meg_name}")
            extracted += 1
    else:
        print(f"WARNING: {sfx2d_path} not found")

    # --- MUSIC.MEG: remastered music tracks ---
    music_path = os.path.join(data_dir, 'MUSIC.MEG')
    if os.path.exists(music_path):
        print()
        print("=== MUSIC.MEG (remastered music) ===")
        meg = MEGFile(music_path)

        seen = set()
        for meg_name, size in sorted(meg.list_files()):
            engine_name = map_music_name(meg_name)
            if engine_name is None:
                continue
            if engine_name in seen:
                continue
            seen.add(engine_name)

            wav_data = meg.read_file(meg_name)
            result = decode_ms_adpcm_wav(wav_data)
            if result is None:
                print(f"  FAILED: {meg_name}")
                failed += 1
                continue

            samples, sample_rate, channels = result
            if channels > 1 and not args.keep_stereo:
                samples = stereo_to_mono(samples, channels)
                channels = 1

            out_path = os.path.join(output_dir, f"{engine_name}.WAV")
            write_pcm_wav(out_path, samples, sample_rate, channels)
            dur = len(samples) / (sample_rate * channels)
            mb = os.path.getsize(out_path) / 1024 / 1024
            print(f"  OK: {engine_name}.WAV  {sample_rate}Hz {channels}ch  {dur:.1f}s  {mb:.1f}MB  <- {meg_name}")
            extracted += 1
    else:
        print(f"WARNING: {music_path} not found")

    print()
    print("=" * 60)
    print(f"  Extracted: {extracted}")
    print(f"  Failed:    {failed}")
    print(f"  Output:    {output_dir}")
    print("=" * 60)


if __name__ == '__main__':
    main()
