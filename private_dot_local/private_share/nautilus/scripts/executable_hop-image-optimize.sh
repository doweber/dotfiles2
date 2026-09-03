#!/usr/bin/env bash

total=$#
i=0

(
for file in "$@"
do
  echo "# optimizing $file ..."

  convert -resize 1920x1080 "$file" "$file"
  jpegoptim --strip-all "$file"

  ((i+=1))
  echo "$((i*100/total))"
done
echo "# done! 👍" 
) |
zenity --progress --title="Optimize Images" --text="starting..." --percentage=0

if [ "$?" = -1 ] ; then
  zenity --error --text="Optimization canceled."
fi

