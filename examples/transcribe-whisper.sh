#!/bin/bash
# Offline transcription example. Dependencies: ffmpeg, whisper.cpp's whisper-cli,
# python3, and a downloaded whisper.cpp model (WHISPER_MODEL=/path/to/ggml-model.bin).
# Config (also works under launchd, which does not inherit shell-exported variables):
# "transcribe_cmd": ["env", "WHISPER_MODEL=/absolute/path/to/ggml-model.bin",
#                    "/absolute/path/to/this/script", "{audio}", "{out_dir}"]
# Produces one <audio filename>.md with timestamped segments and a matching .srt.
set -euo pipefail
if [ "$#" -ne 2 ]; then
    printf 'Usage: %s AUDIO OUT_DIR\n' "$0" >&2
    exit 2
fi
: "${WHISPER_MODEL:?Set WHISPER_MODEL to a whisper.cpp model file}"
for tool in ffmpeg whisper-cli python3; do
    command -v "$tool" >/dev/null || { printf 'Missing dependency: %s\n' "$tool" >&2; exit 1; }
done
mkdir -p -- "$2"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT
ffmpeg -nostdin -hide_banner -loglevel error -i "$1" -vn -ar 16000 -ac 1 -c:a pcm_s16le "$WORK/audio.wav"
# Auto-detect language; write SRT only so the Markdown is derived from the same segments.
whisper-cli -m "$WHISPER_MODEL" -f "$WORK/audio.wav" -l auto -osrt -of "$WORK/transcript"
python3 - "$1" "$2" "$WORK/transcript.srt" <<'PY'
from pathlib import Path
import re
import shutil
import sys

audio, destination, subtitle = map(Path, sys.argv[1:])
title = re.sub(r'[\x00-\x1f\x7f/\\:]', '-', audio.stem).strip(' .-') or '录音'
segments = []
for block in re.split(r'\n\s*\n', subtitle.read_text(encoding='utf-8-sig').strip()):
    lines = block.splitlines()
    if len(lines) >= 3 and ' --> ' in lines[1]:
        start, end = lines[1].split(' --> ', 1)
        segments.append(f"[{start} - {end}] {' '.join(lines[2:])}")
if not segments:
    raise SystemExit('whisper-cli produced no timestamped segments')
(destination / f'{title}.md').write_text(f'# {title}\n\n' + '\n\n'.join(segments) + '\n', encoding='utf-8')
shutil.copyfile(subtitle, destination / f'{title}.srt')
PY
