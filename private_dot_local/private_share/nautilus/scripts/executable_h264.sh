#!/usr/bin/env bash

total=$#
i=0

(
for file in "$@"
do

  newfilename="${file%.*}.h264.mp4"

  echo "# converting $file to $newfilename ..."

  docker run --rm --user 1000:1000 -v "$(pwd)":/work -w /work jrottenberg/ffmpeg:4.1-scratch -stats -i "$file" -c:v libx264 -movflags +faststart -f mp4 "$newfilename"
  #docker run --rm --user 1000:1000 -v "$(pwd)":/work -w /work jrottenberg/ffmpeg:4.1-scratch -stats -i "$file" -c:v libx264 -pix_fmt yuv420p10 -f mp4 "$newfilename"

  ((i+=1))
  echo "$((i*100/total))"
done
echo "# done! 👍" 
) |
zenity --progress --title="Convert Videos" --text="starting..." --percentage=1

if [ "$?" = -1 ] ; then
  zenity --error --text="conversion canceled."
fi

