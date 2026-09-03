#!/usr/bin/env bash
#
# Convert audio (or a video's audio track) into clean, voice-optimised mono Opus.
#
# Pipeline per file:
#   1. prep     – mono, 48 kHz, high-pass 70 Hz (rumble / handling noise)
#   2. denoise  – DeepFilterNet (neural speech enhancer, ~50 dB noise suppression)
#                 fallback: RNNoise via ffmpeg `arnndn`, then plain `afftdn`
#   3. level    – compand: envelope-based upward compression (smooth gain, no
#                 per-cycle modulation) lifts quiet speakers by up to ~28 dB
#                 → speechnorm with mild expansion (e=4) to close the remaining gap
#   4. loudness – measure integrated loudness (EBU R128), apply ONE fixed gain to
#                 hit -16 LUFS, then a lookahead limiter at ~-1.9 dBFS. No dynamic
#                 loudnorm / no extra AGC stage — those were audibly distorting.
#
# Measured on synthetic two-speaker tests (20 ms window nonlinearity vs clean ref):
#   old speechnorm e=50 + dynaudnorm + 2-pass loudnorm  p95 = 8.2 %  (audible)
#   this chain                                         p95 = 0.18 %
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

# loudness target (podcast / voice standard) and limiter ceiling (linear, 0.89 = -1 dBFS)
TARGET_I=-16
LIMIT=0.89

# Opus encoding — always 'audio' application, NOT 'voip': voip mode measured ~5x
# more codec distortion (p95 62% vs 12% residual at 64k).
#
# Bitrate ladder for mono speech (measured codec residual, p95 / approx size per hour):
#   128k  6.4%  58 MB      96k  7.6%  43 MB      64k  12%  29 MB      48k  ~22 MB
# 48k is chosen for size parity with a typical 48k AAC m4a source; Opus is far more
# bit-efficient than AAC for speech, and the denoised signal no longer wastes bits
# on noise, so this should still sound at least as good as the original.
# Raise to 64k or 96k if you can hear sibilant softening.
OPUS_BITRATE=48k

# -cutoff 12000: declare the content as superwideband (nothing useful above 12 kHz
#   in voice), so the encoder spends no bits there. ~5-10% smaller, no audible cost.
# -frame_duration 40: 40 ms frames instead of 20 ms halve packet/container overhead.
#   ~3-5% smaller; only a latency cost, which is irrelevant for an offline file.
OPUS_OPTS=(-cutoff 12000 -frame_duration 40)

# voice levelling chain (applied identically in the measure and render passes)
#   compand points are in/out dB: -60->-32, -40->-22, -20->-16, 0->-10
LEVEL="compand=attacks=0.05:decays=0.4:points=-80/-80|-60/-32|-40/-22|-20/-16|0/-10:soft-knee=6"
LEVEL+=",speechnorm=e=4:r=0.00005:f=0.00005:l=1:t=0.002:p=0.6"

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
      # -D compensates model latency; no --pf (post-filter adds speech artifacts)
      "$DEEPFILTER" -D -o "$tmp/df" "$tmp/prep.wav" >/dev/null 2>&1 \
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

  # ---- 3. level, then measure integrated loudness ------------------------------
  if [ $ok = 1 ]; then
    echo "# [$((n+1))/$total] measuring loudness: $file"
    "$FFMPEG" -nostats -i "$tmp/clean.wav" \
      -af "$LEVEL,loudnorm=I=$TARGET_I:print_format=json" \
      -progress pipe:1 -f null - 2>"$tmp/measure.log" \
      | progress "$(p 55)" "$(p 70)" "$duration"
    gain=$(sed -n '/^{/,/^}/p' "$tmp/measure.log" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print("%.2f" % ('"$TARGET_I"' - float(d["input_i"])))' 2>/dev/null)
    [ -n "$gain" ] || ok=0
  fi

  # ---- 4. level + fixed gain + lookahead limiter -> opus -----------------------
  if [ $ok = 1 ]; then
    echo "# [$((n+1))/$total] rendering (${gain} dB): $newfilename"
    "$FFMPEG" -nostats -loglevel error -i "$tmp/clean.wav" \
      -af "$LEVEL,volume=${gain}dB,alimiter=limit=$LIMIT:attack=5:release=100:level=false" \
      -c:a libopus -b:a "$OPUS_BITRATE" -vbr on -application audio "${OPUS_OPTS[@]}" \
      -progress pipe:1 -y "$newfilename" \
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
