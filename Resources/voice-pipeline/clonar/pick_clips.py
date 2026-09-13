#!/usr/bin/env python3
"""Elige N referencias largas, separadas y no usadas para condicionar la voz."""
import collections, os, re, subprocess, sys
project = sys.argv[1]; dataset = os.path.join(project, "dataset")
wavs = os.path.join(dataset, "wavs"); val = os.path.join(project, "val")
os.makedirs(val, exist_ok=True)
count = int(os.environ.get("VAL_N", "10")); target = float(os.environ.get("VAL_SEC", "30"))
maximum = target + 6; ffmpeg = os.environ.get("BTODICTA_FFMPEG", "ffmpeg")
ffprobe = os.environ.get("BTODICTA_FFPROBE", "ffprobe")
refs = set(line.strip() for line in open(os.path.join(project, "ref_list.txt"))) \
    if os.path.exists(os.path.join(project, "ref_list.txt")) else set()

def duration(path):
    try:
        return float(subprocess.run([ffprobe, "-v", "error", "-show_entries", "format=duration",
            "-of", "csv=p=0", path], capture_output=True, text=True).stdout or 0)
    except Exception: return 0.0

items = []
for line in open(os.path.join(dataset, "metadata.csv"), encoding="utf-8"):
    if "|" not in line: continue
    cid, text = line.strip().split("|", 1); wav = os.path.join(wavs, cid + ".wav")
    if not os.path.exists(wav): continue
    match = re.match(r"(.+)_(\d+)$", cid); base = match.group(1) if match else cid
    index = int(match.group(2)) if match else 0; items.append((base, index, wav, text.strip()))
grouped = collections.defaultdict(list)
for base, index, wav, text in items: grouped[base].append((index, wav, text))
segments = []
for _, group in grouped.items():
    group.sort(); cursor = 0
    while cursor < len(group):
        selected = []; texts = []; seconds = 0.0; previous = None
        while cursor < len(group) and seconds < target:
            index, wav, text = group[cursor]
            if previous is not None and index != previous + 1: break
            length = duration(wav)
            if seconds + length > maximum and selected: break
            selected.append(wav); texts.append(text); seconds += length
            previous = index; cursor += 1
        if selected and seconds >= min(target * 0.6, 12):
            segments.append((selected, " ".join(texts), seconds))
        if not selected: cursor += 1
segments = [s for s in segments if not any(w in refs for w in s[0])] or segments
segments.sort(key=lambda x: -x[2]); step = max(1, len(segments) // count)
chosen = segments[::step][:count] or segments[:count]; lines = []
for index, (sources, text, _) in enumerate(chosen):
    real = os.path.join(val, f"real_{index}.wav"); listing = os.path.join(val, f"_concat_{index}.txt")
    open(listing, "w").write("".join(f"file '{os.path.abspath(w)}'\n" for w in sources))
    subprocess.run([ffmpeg, "-y", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", listing, "-ar", "24000", "-ac", "1", real], check=False)
    os.remove(listing)
    if os.path.exists(real): lines.append(f"{real}|{text}")
open(os.path.join(project, "val_clips.txt"), "w").write("\n".join(lines))
print(f"OK {len(lines)} referencias de ~{target:.0f}s", flush=True)
