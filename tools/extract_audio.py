#!/usr/bin/env python3
"""
Extract AUD files from C&C Tiberian Dawn MIX archives and convert to WAV.

Faithfully ports Vanilla Conquer's Audio_Unzap() from auduncmp.cpp for
Westwood's custom ADPCM decompression. Also handles IMA ADPCM (compression=99)
and raw PCM (compression=0).

Usage:
    python3 tools/extract_audio.py [--data-dir PATH] [--output-dir PATH]

Default data dir: ~/Library/Application Support/Vanilla-Conquer/vanillatd
Default output:   <data-dir>/extracted/audio/
"""

import struct
import os
import sys
import argparse
from pathlib import Path

# ---------------------------------------------------------------------------
# Westwood CRC hash — must match MIXFile.swift crc(for:)
# ---------------------------------------------------------------------------

def rotl32(v):
    """Rotate left 32-bit."""
    v &= 0xFFFFFFFF
    return ((v << 1) | (v >> 31)) & 0xFFFFFFFF

def ww_crc(filename):
    """Compute Westwood CRC hash for a filename (uppercased)."""
    data = filename.upper().encode('ascii')
    crc = 0
    i = 0
    while i + 4 <= len(data):
        block = struct.unpack_from('<I', data, i)[0]
        crc = (rotl32(crc) + block) & 0xFFFFFFFF
        i += 4
    if i < len(data):
        staging = 0
        for j in range(i, len(data)):
            staging |= data[j] << ((j - i) * 8)
        crc = (rotl32(crc) + staging) & 0xFFFFFFFF
    # Convert to signed int32 for comparison
    if crc >= 0x80000000:
        return crc - 0x100000000
    return crc

# ---------------------------------------------------------------------------
# MIX file parser
# ---------------------------------------------------------------------------

class MIXFile:
    def __init__(self, path):
        self.path = path
        with open(path, 'rb') as f:
            self.data = f.read()
        self.entries = {}  # crc -> (offset, size)
        self.data_start = 0
        self._parse()

    @classmethod
    def from_data(cls, data, name="<embedded>"):
        obj = cls.__new__(cls)
        obj.path = name
        obj.data = data
        obj.entries = {}
        obj.data_start = 0
        obj._parse()
        return obj

    def _parse(self):
        data = self.data
        if len(data) < 6:
            return

        first = struct.unpack_from('<H', data, 0)[0]
        pos = 2

        if first == 0:
            # Extended format (RA and later)
            flags = struct.unpack_from('<H', data, pos)[0]
            pos += 2
            if flags & 0x02:
                print(f"  Warning: {self.path} is encrypted, skipping")
                return
            count = struct.unpack_from('<H', data, pos)[0]
            pos += 2
            _data_size = struct.unpack_from('<I', data, pos)[0]
            pos += 4
        else:
            # Standard TD format: first 2 bytes = count
            count = first
            _data_size = struct.unpack_from('<I', data, pos)[0]
            pos += 4

        for _ in range(count):
            if pos + 12 > len(data):
                break
            crc, offset, size = struct.unpack_from('<iII', data, pos)
            pos += 12
            self.entries[crc] = (offset, size)

        self.data_start = pos

    def retrieve(self, filename):
        crc = ww_crc(filename)
        if crc not in self.entries:
            return None
        offset, size = self.entries[crc]
        start = self.data_start + offset
        end = start + size
        if start < 0 or end > len(self.data):
            return None
        return self.data[start:end]

    def contains(self, filename):
        return ww_crc(filename) in self.entries

# ---------------------------------------------------------------------------
# MIX file manager (mimics Swift MIXFileManager)
# ---------------------------------------------------------------------------

class MIXFileManager:
    def __init__(self):
        self.archives = []  # list of (name, MIXFile)

    def register(self, path):
        try:
            mix = MIXFile(path)
            name = os.path.basename(path).upper()
            self.archives.append((name, mix))
            print(f"  Registered {name} ({len(mix.entries)} files)")
        except Exception as e:
            print(f"  Failed to load {path}: {e}")

    def register_all(self, directory):
        if not os.path.isdir(directory):
            return
        for f in sorted(os.listdir(directory)):
            if f.upper().endswith('.MIX'):
                self.register(os.path.join(directory, f))

    def register_sub_archive(self, name):
        upper = name.upper()
        if any(n == upper for n, _ in self.archives):
            return
        data = self.retrieve(name)
        if data is None:
            return
        try:
            mix = MIXFile.from_data(data, name=upper)
            self.archives.append((upper, mix))
            print(f"  Registered sub-archive {upper} ({len(mix.entries)} files)")
        except Exception as e:
            print(f"  Failed to register sub-archive {name}: {e}")

    def retrieve(self, filename):
        crc = ww_crc(filename)
        for _name, mix in self.archives:
            if crc in mix.entries:
                offset, size = mix.entries[crc]
                start = mix.data_start + offset
                end = start + size
                if 0 <= start and end <= len(mix.data):
                    return mix.data[start:end]
        return None

    def contains(self, filename):
        crc = ww_crc(filename)
        return any(crc in mix.entries for _, mix in self.archives)

# ---------------------------------------------------------------------------
# Audio_Unzap — faithful port of Vanilla Conquer auduncmp.cpp
# ---------------------------------------------------------------------------

ZAP_TAB_TWO = [-2, -1, 0, 1]
ZAP_TAB_FOUR = [-9, -8, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 8]

def audio_unzap(source, size):
    """
    Faithful port of Audio_Unzap() from Vanilla-Conquer/common/auduncmp.cpp.

    Decodes Westwood's custom ADPCM compression.
    source: bytes of compressed data
    size:   expected uncompressed output size
    Returns: bytes of 8-bit unsigned PCM
    """
    sample = 0x80
    src = 0
    dst = bytearray()
    remaining = size

    while remaining > 0 and src < len(source):
        shifted = source[src] << 2
        src += 1
        code = (shifted & 0xFF00) >> 8
        count = (shifted & 0x00FF) >> 2

        # count is effectively a signed char in the C code for case 2
        # but for the loop counts in cases 0,1,3 it's used as unsigned

        if code == 2:
            if count & 0x20:
                # Single delta sample
                # Faithful VC: count <<= 3; sample += count >> 3;
                # count is signed char — the << 3 truncates to 8 bits, >> 3 is arithmetic
                sc = (count << 3) & 0xFF  # truncate to unsigned 8-bit
                if sc >= 128:
                    sc -= 256  # convert to signed 8-bit
                sc >>= 3  # Python >> is arithmetic for negative numbers
                sample += sc
                sample = max(0, min(255, sample))
                dst.append(sample)
                remaining -= 1
            else:
                # Raw bytes: copy count+1 bytes directly
                for _ in range(count + 1):
                    if src >= len(source) or remaining <= 0:
                        break
                    dst.append(source[src])
                    src += 1
                    remaining -= 1
                # Update sample to last byte sent to output
                if dst:
                    sample = dst[-1]

        elif code == 1:
            # 4-bit ADPCM: 1 source byte -> 2 output bytes
            for _ in range(count + 1):
                if src >= len(source) or remaining <= 0:
                    break
                byte = source[src]
                src += 1
                # Lower nibble
                sample += ZAP_TAB_FOUR[byte & 0x0F]
                sample = max(0, min(255, sample))
                dst.append(sample)
                remaining -= 1
                # Upper nibble
                if remaining <= 0:
                    break
                sample += ZAP_TAB_FOUR[(byte >> 4) & 0x0F]
                sample = max(0, min(255, sample))
                dst.append(sample)
                remaining -= 1

        elif code == 0:
            # 2-bit ADPCM: 1 source byte -> 4 output bytes
            for _ in range(count + 1):
                if src >= len(source) or remaining <= 0:
                    break
                byte = source[src]
                src += 1
                for shift in [0, 2, 4, 6]:
                    if remaining <= 0:
                        break
                    sample += ZAP_TAB_TWO[(byte >> shift) & 0x03]
                    sample = max(0, min(255, sample))
                    dst.append(sample)
                    remaining -= 1

        else:
            # Silence/repeat: fill count+1 bytes with current sample
            fill = max(0, min(255, sample))
            for _ in range(count + 1):
                if remaining <= 0:
                    break
                dst.append(fill)
                remaining -= 1

    return bytes(dst)

# ---------------------------------------------------------------------------
# IMA ADPCM decoder
# ---------------------------------------------------------------------------

IMA_INDEX_TABLE = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

IMA_STEP_TABLE = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37,
    41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173,
    190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658,
    724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484,
    7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500,
    20350, 22385, 24623, 27086, 29794, 32767,
]

def decode_ima_adpcm(source, sample_count):
    """Decode IMA ADPCM data to signed 16-bit PCM samples."""
    predictor = 0
    step_index = 0
    samples = []
    idx = 0

    while idx < len(source) and len(samples) < sample_count:
        byte = source[idx]
        idx += 1
        for shift in [0, 4]:
            if len(samples) >= sample_count:
                break
            nibble = (byte >> shift) & 0x0F
            step = IMA_STEP_TABLE[step_index]
            diff = step >> 3
            if nibble & 1: diff += step >> 2
            if nibble & 2: diff += step >> 1
            if nibble & 4: diff += step
            if nibble & 8: diff = -diff
            predictor += diff
            predictor = max(-32768, min(32767, predictor))
            samples.append(predictor)
            step_index += IMA_INDEX_TABLE[nibble]
            step_index = max(0, min(88, step_index))

    return samples

# ---------------------------------------------------------------------------
# AUD file decoder
# ---------------------------------------------------------------------------

def decode_aud(data):
    """
    Decode a Westwood AUD file to signed 16-bit PCM samples.
    Returns (samples_int16_list, sample_rate) or None.
    """
    if len(data) < 12:
        return None

    # Parse 12-byte AUD header
    sample_rate = struct.unpack_from('<H', data, 0)[0]
    # comp_size = struct.unpack_from('<I', data, 2)[0]  # not needed
    # uncomp_size = struct.unpack_from('<I', data, 6)[0]  # not needed
    flags = data[10]
    compression = data[11]
    is_16bit = (flags & 2) != 0

    if sample_rate == 0 or sample_rate > 44100:
        return None

    header_size = 12

    # Uncompressed
    if compression == 0:
        samples = []
        if is_16bit:
            i = header_size
            while i + 1 < len(data):
                s = struct.unpack_from('<h', data, i)[0]
                samples.append(s)
                i += 2
        else:
            for i in range(header_size, len(data)):
                samples.append((data[i] - 128) * 256)
        return (samples, sample_rate) if samples else None

    # Westwood ADPCM (compression == 1)
    if compression == 1:
        samples = []
        offset = header_size
        while offset + 8 <= len(data):
            comp_size = struct.unpack_from('<H', data, offset)[0]
            uncomp_size = struct.unpack_from('<H', data, offset + 2)[0]
            chunk_id = struct.unpack_from('<I', data, offset + 4)[0]
            offset += 8

            if chunk_id != 0x0000DEAF:
                break
            if offset + comp_size > len(data):
                break

            chunk_data = data[offset:offset + comp_size]
            pcm8 = audio_unzap(chunk_data, uncomp_size)
            # Convert 8-bit unsigned to 16-bit signed
            for b in pcm8:
                samples.append((b - 128) * 256)
            offset += comp_size

        return (samples, sample_rate) if samples else None

    # IMA ADPCM (compression == 99)
    if compression == 99:
        samples = []
        offset = header_size
        while offset + 8 <= len(data):
            comp_size = struct.unpack_from('<H', data, offset)[0]
            uncomp_size = struct.unpack_from('<H', data, offset + 2)[0]
            chunk_id = struct.unpack_from('<I', data, offset + 4)[0]
            offset += 8

            if chunk_id != 0x0000DEAF:
                break
            if offset + comp_size > len(data):
                break

            chunk_data = data[offset:offset + comp_size]
            decoded = decode_ima_adpcm(chunk_data, uncomp_size)
            samples.extend(decoded)
            offset += comp_size

        return (samples, sample_rate) if samples else None

    return None

# ---------------------------------------------------------------------------
# WAV writer
# ---------------------------------------------------------------------------

def normalize_samples(samples, target_peak=30000):
    """Normalize sample array so peak maps to target_peak."""
    if not samples:
        return samples
    peak = max(abs(s) for s in samples)
    if peak < 1:
        return samples
    if peak >= target_peak:
        return samples  # already loud enough
    scale = target_peak / peak
    return [max(-32768, min(32767, int(s * scale))) for s in samples]


def write_wav(path, samples, sample_rate, bits_per_sample=16, channels=1):
    """Write a standard RIFF WAV file with PCM data."""
    byte_rate = sample_rate * channels * (bits_per_sample // 8)
    block_align = channels * (bits_per_sample // 8)
    data_size = len(samples) * (bits_per_sample // 8)

    with open(path, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + data_size))  # file size - 8
        f.write(b'WAVE')

        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))  # chunk size
        f.write(struct.pack('<H', 1))   # PCM format
        f.write(struct.pack('<H', channels))
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', byte_rate))
        f.write(struct.pack('<H', block_align))
        f.write(struct.pack('<H', bits_per_sample))

        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', data_size))
        for s in samples:
            f.write(struct.pack('<h', max(-32768, min(32767, s))))

# ---------------------------------------------------------------------------
# Known audio filenames from GameAudio.swift
# ---------------------------------------------------------------------------

# VocType filenames (sound effects)
VOC_FILENAMES = {
    "BOMBIT1": "Commando Present",
    "CMON1": "Commando C'mon",
    "GOTIT1": "Commando You Got It",
    "KEEPEM1": "Commando Keep Em Comin'",
    "LAUGH1": "Commando Laugh",
    "LEFTY1": "Commando Lefty",
    "NOPRBLM1": "Commando No Problem",
    "ONIT1": "Commando On It",
    "RAMYELL1": "Commando Yell",
    "ROKROLL1": "Commando Rock",
    "TUFFGUY1": "Commando Tough Guy",
    "YEAH1": "Commando Yeah",
    "YES1": "Commando Yes",
    "YO1": "Commando Yo",
    "GIRLOKAY": "Girl Okay",
    "GIRLYEAH": "Girl Yeah",
    "GUYOKAY1": "Guy Okay",
    "GUYYEAH1": "Guy Yeah",
    "2DANGR1": "Danger",
    "ACKNO": "Acknowledge",
    "AFFIRM1": "Affirmative",
    "AWAIT1": "Awaiting",
    "MOVOUT1": "Move Out",
    "NEGATV1": "Negative",
    "NOPROB": "No Problem",
    "READY": "Ready",
    "REPORT1": "Reporting",
    "RITAWAY": "Right Away",
    "ROGER": "Roger",
    "UNIT1": "Unit Ready",
    "VEHIC1": "Vehicle Ready",
    "YESSIR1": "Yes Sir",
    "BAZOOK1": "Bazooka",
    "BLEEP2": "Bleep",
    "BOMB1": "Bomb",
    "BUTTON": "Button",
    "COMCNTR1": "Radar On",
    "CONSTRU2": "Construction",
    "CRUMBLE": "Crumble",
    "FLAMER2": "Flamethrower",
    "GUN18": "Rifle",
    "GUN19": "Machine Gun",
    "GUN20": "Gun",
    "GUN5": "M60",
    "GUN8": "Minigun",
    "GUNCLIP1": "Reload",
    "HVYDOOR1": "Heavy Door",
    "HVYGUN10": "Heavy Gun",
    "ION1": "Ion Cannon",
    "MGUN11": "Machine Gun 2",
    "MGUN2": "Machine Gun 3",
    "NUKEMISL": "Nuke Fire",
    "NUKEXPLO": "Nuke Explode",
    "OBELRAY1": "Obelisk Laser",
    "OBELPOWR": "Obelisk Power",
    "POWRDN1": "Radar Off",
    "RAMGUN2": "Sniper",
    "ROCKET1": "Rocket 1",
    "ROCKET2": "Rocket 2",
    "SAMMOTR2": "SAM Motor",
    "SCOLD2": "Scold",
    "SIDBAR1C": "Sidebar Open",
    "SIDBAR2C": "Sidebar Close",
    "SQUISH2": "Squish",
    "TNKFIRE2": "Tank Fire 1",
    "TNKFIRE3": "Tank Fire 2",
    "TNKFIRE4": "Tank Fire 3",
    "TNKFIRE6": "Tank Fire 4",
    "TONE15": "Tone Up",
    "TONE16": "Tone Down",
    "TONE2": "Target",
    "TONE5": "Sonar",
    "TOSS1": "Grenade Toss",
    "TRANS1": "Cloak",
    "TREEBRN1": "Tree Burn",
    "TURRFIR5": "Turret Fire",
    "XPLOBIG4": "Explosion Big 1",
    "XPLOBIG6": "Explosion Big 2",
    "XPLOBIG7": "Explosion Big 3",
    "XPLODE": "Explosion",
    "XPLOS": "Explosion Small 1",
    "XPLOSML2": "Explosion Small 2",
    "NUYELL1": "Scream 1",
    "NUYELL3": "Scream 3",
    "NUYELL4": "Scream 4",
    "NUYELL5": "Scream 5",
    "NUYELL6": "Scream 6",
    "NUYELL7": "Scream 7",
    "NUYELL10": "Scream 10",
    "NUYELL11": "Scream 11",
    "NUYELL12": "Scream 12",
    "YELL1": "Yell",
    "MYES1": "EVA Yes",
    "MCOMND1": "EVA Commander",
    "MHELLO1": "EVA Hello",
    "MHMMM1": "EVA Hmmm",
    "CASHTURN": "Cash Turn",
    "BEACON": "Beacon",
}

# VoxType filenames (EVA speech)
VOX_FILENAMES = {
    "ACCOM1": "Accomplished",
    "FAIL1": "Mission Failed",
    "BLDG1": "No Factory",
    "CONSTRU1": "Construction",
    "UNITREDY": "Unit Ready",
    "NEWOPT1": "New Construction",
    "DEPLOY1": "Deploy",
    "GDIDEAD1": "GDI Dead",
    "NODDEAD1": "Nod Dead",
    "CIVDEAD1": "Civilian Dead",
    "NOCASH1": "Insufficient Funds",
    "BATLCON1": "Control Exit",
    "REINFOR1": "Reinforcements",
    "CANCEL1": "Canceled",
    "BLDGING1": "Building",
    "LOPOWER1": "Low Power",
    "NOPOWER1": "No Power",
    "MOCASH1": "Need More Cash",
    "BASEATK1": "Base Under Attack",
    "INCOME1": "Incoming Missile",
    "ENEMYA": "Enemy Planes",
    "NUKE1": "Incoming Nuke",
    "NOBUILD1": "Unable to Build",
    "PRIBLDG1": "Primary Selected",
    "NODCAPT1": "Nod Captured",
    "GDICAPT1": "GDI Captured",
    "IONCHRG1": "Ion Charging",
    "IONREDY1": "Ion Ready",
    "NUKAVAIL": "Nuke Available",
    "NUKLNCH1": "Nuke Launched",
    "UNITLOST": "Unit Lost",
    "STRCLOST": "Structure Lost",
    "NEEDHARV": "Need Harvester",
    "SELECT1": "Select Target",
    "AIRREDY1": "Airstrike Ready",
    "NOREDY1": "Not Ready",
    "TRANSSEE": "Transport Sighted",
    "TRANLOAD": "Transport Loaded",
    "ENMYAPP1": "Prepare",
    "SILOS1": "Need More Capacity",
    "ONHOLD1": "Suspended",
    "REPAIR1": "Repairing",
    "ESTRUCX": "Enemy Structure",
    "GSTRUC1": "GDI Structure",
    "NSTRUC1": "Nod Structure",
    "ENMYUNIT": "Enemy Unit",
}

# ThemeType filenames (music)
THEME_FILENAMES = {
    "AIRSTRIK": "Airstrike",
    "80MX": "80MX",
    "CHRG": "Charge",
    "CREP": "Creeping",
    "DRIL": "Drill",
    "DRON": "Drone",
    "FIST": "Fist",
    "RECON": "Recon",
    "VOICE": "Voice",
    "HEAVYG": "Heavy G",
    "J1": "J1",
    "JDI_V2": "JDI V2",
    "RADIO": "Radio",
    "RAIN": "Rain",
    "AOI": "Act On Instinct",
    "CCTHANG": "C&C Thang",
    "DIE": "Die!!",
    "FWP": "Fight Win Prevail",
    "IND": "Industrial",
    "IND2": "Industrial 2",
    "JUSTDOIT": "Just Do It!",
    "LINEFIRE": "In The Line Of Fire",
    "MARCH": "March To Your Doom",
    "NOMERCY": "No Mercy",
    "OTP": "On The Prowl",
    "PRP": "Prepare For Battle",
    "ROUT": "Reaching Out",
    "HEART": "Heart",
    "STOPTHEM": "Stop Them",
    "TROUBLE": "Looks Like Trouble",
    "WARFARE": "Warfare",
    "BFEARED": "Enemies To Be Feared",
    "IAM": "I Am",
    "WIN1": "Great Shot!",
    "MAP1": "Map",
    "VALKYRIE": "Ride of the Valkyries",
}

# ---------------------------------------------------------------------------
# Main extraction
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Extract AUD files from C&C MIX archives to WAV")
    parser.add_argument('--data-dir', type=str,
                        default=os.path.expanduser("~/Library/Application Support/Vanilla-Conquer/vanillatd"),
                        help="Path to game data directory containing MIX files")
    parser.add_argument('--output-dir', type=str, default=None,
                        help="Output directory for WAV files (default: <data-dir>/extracted/audio/)")
    args = parser.parse_args()

    data_dir = args.data_dir
    output_dir = args.output_dir or os.path.join(data_dir, "extracted", "audio")

    if not os.path.isdir(data_dir):
        print(f"Error: Data directory not found: {data_dir}")
        sys.exit(1)

    print(f"Data directory: {data_dir}")
    print(f"Output directory: {output_dir}")
    print()

    # Register MIX archives
    print("Loading MIX archives...")
    mgr = MIXFileManager()
    mgr.register_all(data_dir)

    # Check gdi/ and nod/ subdirs
    for subdir in ['gdi', 'nod']:
        mgr.register_all(os.path.join(data_dir, subdir))

    # Register sub-archives containing audio
    print("\nRegistering sub-archives...")
    for sub in ["SOUNDS.MIX", "SPEECH.MIX", "SCORES.MIX", "GENERAL.MIX", "CONQUER.MIX"]:
        mgr.register_sub_archive(sub)

    print()

    # Gather all filenames to extract
    all_files = {}
    all_files.update(VOC_FILENAMES)
    all_files.update(VOX_FILENAMES)
    all_files.update(THEME_FILENAMES)

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Extract
    found = 0
    decoded_ok = 0
    failed = 0
    not_found = 0

    print(f"Extracting {len(all_files)} audio files...\n")

    for filename, label in sorted(all_files.items()):
        # Try .AUD first, then voice variation extensions .V00-.V03
        data = None
        source_ext = ".AUD"
        for ext in [".AUD", ".V00", ".V01", ".V02", ".V03"]:
            data = mgr.retrieve(f"{filename}{ext}")
            if data is not None:
                source_ext = ext
                break

        if data is None:
            not_found += 1
            continue

        found += 1
        result = decode_aud(data)

        if result is None:
            failed += 1
            if len(data) >= 12:
                sr = struct.unpack_from('<H', data, 0)[0]
                comp = data[11]
                print(f"  FAILED: {filename}{source_ext} ({len(data)} bytes, rate={sr}, comp={comp})")
            else:
                print(f"  FAILED: {filename}{source_ext} ({len(data)} bytes, too small)")
            continue

        samples, sample_rate = result
        wav_path = os.path.join(output_dir, f"{filename}.WAV")
        write_wav(wav_path, samples, sample_rate)
        decoded_ok += 1

        duration = len(samples) / sample_rate if sample_rate > 0 else 0
        ext_note = f" [{source_ext}]" if source_ext != ".AUD" else ""
        print(f"  OK: {filename}.WAV  rate={sample_rate}  samples={len(samples)}  dur={duration:.2f}s  ({label}){ext_note}")

    print(f"\n{'='*60}")
    print(f"Results:")
    print(f"  Total filenames searched: {len(all_files)}")
    print(f"  Found in archives:        {found}")
    print(f"  Decoded successfully:      {decoded_ok}")
    print(f"  Decode failed:             {failed}")
    print(f"  Not found in archives:     {not_found}")
    print(f"  Output directory:          {output_dir}")
    print(f"{'='*60}")

    if decoded_ok > 0:
        print(f"\nSuccess! {decoded_ok} WAV files written to {output_dir}")
    else:
        print("\nNo files were extracted. Check that MIX archives exist in the data directory.")

    return 0 if failed == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
