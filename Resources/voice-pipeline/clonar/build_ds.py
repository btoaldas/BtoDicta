#!/usr/bin/env python3
"""Audios de una persona -> dataset XTTS limpio, transcrito y segmentado."""
import glob, os, random, re, subprocess, sys
import mlx_whisper

FOLDER, PROJ = sys.argv[1], sys.argv[2]
DS = os.path.join(PROJ, "dataset"); WAVS = os.path.join(DS, "wavs")
os.makedirs(WAVS, exist_ok=True)
SR = 24000; MODEL = "mlx-community/whisper-large-v3-turbo"
MIN_S, MAX_S = 2.0, 15.0
EXTS = (".mp3", ".ogg", ".wav", ".opus", ".m4a", ".aac", ".flac")
FFMPEG = os.environ.get("BTODICTA_FFMPEG", "ffmpeg")
FFPROBE = os.environ.get("BTODICTA_FFPROBE", "ffprobe")
files = sorted(f for f in glob.glob(os.path.join(FOLDER, "**", "*"), recursive=True)
               if f.lower().endswith(EXTS))
print(f"[i] {len(files)} audios en {FOLDER}", flush=True)

def clean(src, dst):
    subprocess.run([FFMPEG, "-y", "-v", "error", "-i", src, "-af",
                    "highpass=f=60,afftdn=nr=10:nf=-25,loudnorm=I=-20:TP=-2",
                    "-ar", str(SR), "-ac", "1", dst], check=True)

def cut(src, start, end, dst):
    subprocess.run([FFMPEG, "-y", "-v", "error", "-ss", f"{start:.3f}",
                    "-to", f"{end:.3f}", "-i", src, "-ar", str(SR), "-ac", "1", dst], check=True)

def duration(wav):
    try:
        return float(subprocess.run([FFPROBE, "-v", "error", "-show_entries", "format=duration",
                    "-of", "csv=p=0", wav], capture_output=True, text=True).stdout or 0)
    except Exception:
        return 0.0

meta_path = os.path.join(DS, "metadata.csv")
tmp = os.path.join(DS, "_clean.wav"); kept = 0; total = 0.0
with open(meta_path, "w", encoding="utf-8") as meta:
    for i, source in enumerate(files):
        base = re.sub(r"[^A-Za-z0-9]", "_", os.path.splitext(os.path.basename(source))[0])[:36] + f"_{i}"
        try:
            clean(source, tmp)
            result = mlx_whisper.transcribe(tmp, path_or_hf_repo=MODEL, language="es")
        except Exception as exc:
            print("[!]", os.path.basename(source), exc, flush=True); continue
        for j, segment in enumerate(result.get("segments", [])):
            start, end = segment["start"], segment["end"]
            text = re.sub(r"\s+", " ", segment["text"].strip()); seconds = end - start
            if seconds < MIN_S or seconds > MAX_S or len(text) < 4: continue
            if not re.search(r"[a-zA-ZáéíóúñÁÉÍÓÚÑ]", text): continue
            cps = len(text) / seconds
            if cps < 3 or cps > 25: continue
            cid = f"{base}_{j:02d}"; wav = os.path.join(WAVS, cid + ".wav")
            cut(tmp, start, end, wav)
            if 2.0 <= duration(wav) <= 15.0:
                meta.write(f"{cid}|{text}\n"); kept += 1; total += seconds
            else:
                try: os.remove(wav)
                except OSError: pass
        if (i + 1) % max(1, len(files) // 30) == 0 or i + 1 == len(files):
            meta.flush(); print(f"[i] {i+1}/{len(files)} notas | clips={kept} | {total/60:.1f}min", flush=True)
if os.path.exists(tmp): os.remove(tmp)

lines = [line.strip() for line in open(meta_path, encoding="utf-8") if "|" in line]
random.seed(42)
rows = [f"wavs/{line.split('|')[0]}.wav|{line.split('|', 1)[1]}|voz" for line in lines]
random.shuffle(rows); ne = max(10, int(len(rows) * 0.02)); ev, tr = rows[:ne], rows[ne:]
header = "audio_file|text|speaker_name\n"
open(os.path.join(DS, "metadata_train.csv"), "w", encoding="utf-8").write(header + "\n".join(tr) + "\n")
open(os.path.join(DS, "metadata_eval.csv"), "w", encoding="utf-8").write(header + "\n".join(ev) + "\n")
refs = []
for line in lines:
    wav = os.path.join(WAVS, line.split("|")[0] + ".wav")
    if 7 <= duration(wav) <= 11: refs.append(wav)
    if len(refs) >= 8: break
if not refs and lines: refs = [os.path.join(WAVS, lines[0].split("|")[0] + ".wav")]
open(os.path.join(PROJ, "ref_list.txt"), "w", encoding="utf-8").write("\n".join(refs))
print(f"[OK] clips={kept} {total/60:.1f}min | train={len(tr)} eval={len(ev)} ref={len(refs)}", flush=True)
