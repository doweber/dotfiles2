#!/usr/bin/env bash
#
# Convert audio (or a video's audio track) into clean, voice-optimised mono Opus.
#
# Pipeline per file:
#   1. prep     – mono, 48 kHz, high-pass 70 Hz (rumble / handling noise)
#   2. denoise  – DeepFilterNet (neural speech enhancer, ~50 dB noise suppression)
#                 fallback: RNNoise via ffmpeg `arnndn`, then plain `afftdn`
#   3. level    – speechnorm (per-syllable AGC, lifts quiet speakers up to +34 dB)
#                 → dynaudnorm (smooths level across the whole recording)
#                 → agate (keeps the AGC from pumping residual noise up in pauses)
#   4. loudnorm – TWO-PASS EBU R128 to -16 LUFS / -1.5 dBTP (measure, then linear gain)
#
# Requirements: /usr/bin/ffmpeg >= 4.4 (uses the real binary, NOT the docker alias)
# Optional:     ~/.local/bin/deep-filter        https://github.com/Rikorose/DeepFilterNet
#               ~/.local/share/rnnoise/sh.rnnn  https://github.com/GregorR/rnnoise-models
#
# Debug without a GUI:  VOICE_NO_GUI=1 ./to_voice.sh file.mp4

FFMPEG=/usr/bin/ffmpeg
FFPROBE=/usr/bin/ffprobe
DEEPFILTER="${DEEPFILTER:-$HOME/.local/bin/deep-filter}"
RNNOISE_MODEL="${RNNOISE_MODEL:-$HOME/.local/share/rnnoise/sh.rnnn}"

# loudness target (podcast / voice standard)
TARGET_I=-16
TARGET_TP=-1.5
TARGET_LRA=7

# voice levelling chain (applied identically in the measure and render passes)
LEVEL="speechnorm=e=50:r=0.0001:l=1:t=0.002"
LEVEL+=",dynaudnorm=f=250:g=11:m=30:p=0.9:s=3"
LEVEL+=",agate=threshold=0.03:ratio=3:attack=10:release=300:range=0.03:knee=6"

total=$#
n=0

# stream ffmpeg -progress output and map out_time_us onto [lo, hi] percent
# usage: <ffmpeg cmd> -progress pipe:1 ... | progress <lo> <hi> <duration>
progress() {
  local lo=$1 hi=$2 dur=$3 last=-1 key value pct
  while IFS='=' read -r key value; do
    [ "$key" = "out_time_us" ] || continue
    case "$value" in ''|*[!0-9]*) continue ;; esac
    pct=$(awk -v t="$value" -v d="$dur" -v lo="$lo" -v hi="$hi" \
      'BEGIN { if (d > 0) { p = lo + (t/1000000.0)/d*(hi-lo); if (p > hi) p = hi; printf "%d", p } else { print lo } }')
    if [ "$pct" != "$last" ]; then echo "$pct"; last=$pct; fi
  done
}

process_all() {
for file in "$@"
do
  newfilename="${file%.*}_voice.opus"
  if [ "$newfilename" = "$file" ] || [ -e "$newfilename" ]; then
    c=1
    while [ -e "${file%.*}_voice ($c).opus" ] || [ "${file%.*}_voice ($c).opus" = "$file" ]; do
      ((c+=1))
    done
    newfilename="${file%.*}_voice ($c).opus"
  fi

  # this file's slice of the overall progress bar
  base=$(( n * 100 / total ))
  span=$(( 100 / total ))
  p() { echo $(( base + span * $1 / 100 )); }   # percent-of-slice -> overall percent

  tmp=$(mktemp -d)
  duration=$("$FFPROBE" -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")
  ok=1

  # ---- 1. prep: mono 48k, rumble filter --------------------------------------
  echo "# [$((n+1))/$total] preparing: $file"
  "$FFMPEG" -nostats -loglevel error -i "$file" -vn -ac 1 -ar 48000 \
    -af "highpass=f=70" -c:a pcm_s16le -progress pipe:1 -y "$tmp/prep.wav" \
    | progress "$(p 0)" "$(p 10)" "$duration"
  [ -s "$tmp/prep.wav" ] || ok=0

  # ---- 2. denoise --------------------------------------------------------------
  if [ $ok = 1 ]; then
    if [ -x "$DEEPFILTER" ]; then
      echo "# [$((n+1))/$total] denoising (DeepFilterNet): $file"
      echo "$(p 10)"
      "$DEEPFILTER" -D --pf -o "$tmp/df" "$tmp/prep.wav" >/dev/null 2>&1 \
        && mv "$tmp/df/prep.wav" "$tmp/clean.wav"
    fi
    if [ ! -s "$tmp/clean.wav" ]; then
      if [ -f "$RNNOISE_MODEL" ]; then
        echo "# [$((n+1))/$total] denoising (RNNoise): $file"
        dn="arnndn=m=$RNNOISE_MODEL"
      else
        echo "# [$((n+1))/$total] denoising (afftdn): $file"
        dn="afftdn=nf=-25:nr=12"
      fi
      "$FFMPEG" -nostats -loglevel error -i "$tmp/prep.wav" -af "$dn" \
        -c:a pcm_s16le -progress pipe:1 -y "$tmp/clean.wav" \
        | progress "$(p 10)" "$(p 55)" "$duration"
    fi
    [ -s "$tmp/clean.wav" ] || ok=0
    echo "$(p 55)"
  fi

  # ---- 3. level + loudnorm pass 1 (measure) ------------------------------------
  if [ $ok = 1 ]; then
    echo "# [$((n+1))/$total] measuring loudness: $file"
    "$FFMPEG" -nostats -i "$tmp/clean.wav" \
      -af "$LEVEL,loudnorm=I=$TARGET_I:TP=$TARGET_TP:LRA=$TARGET_LRA:print_format=json" \
      -progress pipe:1 -f null - 2>"$tmp/measure.log" \
      | progress "$(p 55)" "$(p 70)" "$duration"
    read -r mI mTP mLRA mTH mOFF <<<"$(sed -n '/^{/,/^}/p' "$tmp/measure.log" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(d["input_i"], d["input_tp"], d["input_lra"], d["input_thresh"], d["target_offset"])' 2>/dev/null)"
    [ -n "$mOFF" ] || ok=0
  fi

  # ---- 4. level + loudnorm pass 2 (linear gain) -> opus ------------------------
  if [ $ok = 1 ]; then
    echo "# [$((n+1))/$total] rendering: $newfilename"
    "$FFMPEG" -nostats -loglevel error -i "$tmp/clean.wav" \
      -af "$LEVEL,loudnorm=I=$TARGET_I:TP=$TARGET_TP:LRA=$TARGET_LRA:measured_I=$mI:measured_TP=$mTP:measured_LRA=$mLRA:measured_thresh=$mTH:offset=$mOFF:linear=true" \
      -c:a libopus -b:a 64k -vbr on -application voip -progress pipe:1 -y "$newfilename" \
      | progress "$(p 70)" "$(p 100)" "$duration"
    [ -s "$newfilename" ] || ok=0
  fi

  [ $ok = 1 ] || { echo "# FAILED: $file"; rm -f "$newfilename"; }
  rm -rf "$tmp"
  ((n+=1))
  echo "$(( n * 100 / total ))"
done
echo "# done! 👍"
echo "100"
}

if [ -n "$VOICE_NO_GUI" ]; then
  process_all "$@"
else
  process_all "$@" | zenity --progress --title="Optimise Audio for Voice" --text="starting..." --percentage=1
  if [ "$?" = -1 ] ; then
    zenity --error --text="conversion canceled."
  fi
fi
