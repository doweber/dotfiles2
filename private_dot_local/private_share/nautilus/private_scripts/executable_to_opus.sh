#!/usr/bin/env bash

total=$#
n=0

(
for file in "$@"
do

  newfilename="${file%.*}.opus"

  # avoid clobbering the input (e.g. already .opus) or an existing file
  if [ "$newfilename" = "$file" ] || [ -e "$newfilename" ]; then
    c=1
    while [ -e "${file%.*} ($c).opus" ] || [ "${file%.*} ($c).opus" = "$file" ]; do
      ((c+=1))
    done
    newfilename="${file%.*} ($c).opus"
  fi

  echo "# converting $file to $newfilename ..."

  # this file's slice of the overall progress bar: [base, base+span)
  base=$(( n * 100 / total ))
  span=$(( 100 / total ))

  # total duration (seconds, float) so we can compute live progress
  duration=$(docker run --rm --user 1000:1000 -v "$(pwd)":/work -w /work \
    --entrypoint ffprobe jrottenberg/ffmpeg:4.1-scratch \
    -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$file")

  last=-1
  docker run --rm --user 1000:1000 -v "$(pwd)":/work -w /work jrottenberg/ffmpeg:4.1-scratch \
    -nostats -i "$file" -vn -c:a libopus -b:a 128k -vbr on -progress pipe:1 -y "$newfilename" 2>/dev/null |
  while IFS='=' read -r key value; do
    [ "$key" = "out_time_us" ] || continue
    case "$value" in ''|*[!0-9]*) continue ;; esac
    pct=$(awk -v t="$value" -v d="$duration" -v b="$base" -v s="$span" \
      'BEGIN { if (d > 0) { p = b + (t/1000000.0)/d*s; if (p > 100) p = 100; printf "%d", p } else { print b } }')
    if [ "$pct" != "$last" ]; then
      echo "$pct"
      last=$pct
    fi
  done

  ((n+=1))
  echo "$(( n * 100 / total ))"
done
echo "# done! 👍"
echo "100"
) |
zenity --progress --title="Convert Audio to Opus" --text="starting..." --percentage=1

if [ "$?" = -1 ] ; then
  zenity --error --text="conversion canceled."
fi
