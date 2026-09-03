#!/usr/bin/env bash

total=$#
i=0
watermark="/home/dweber/Pictures/HOP_Mark-white-150.png"

(
for file in "$@"
do
  echo "# optimizing $file ..."

  newfile="${file%.*}.watermark.jpg"

  #composite -gravity south -geometry +10+10 -dissolve 75% "$watermark" "$file" "$newfile"
  composite -gravity south -geometry +0+30 -dissolve 30% "$watermark" "$file" "$newfile"

  ((i+=1))
  echo "$((i*100/total))"
done
echo "# done! 👍" 
) |
zenity --progress --title="Optimize Images" --text="starting..." --percentage=0

if [ "$?" = -1 ] ; then
  zenity --error --text="Optimization canceled."
fi

