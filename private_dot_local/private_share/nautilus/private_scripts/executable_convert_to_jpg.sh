#!/usr/bin/env bash

total=$#
i=0

(
for file in "$@"
do
  echo "# converting $file ..."

  magick "$file" "${file}.jpg"

  ((i+=1))
  echo "$((i*100/total))"
done
echo "# done! 👍" 
) |
zenity --progress --title="converting Images" --text="starting..." --percentage=0

if [ "$?" = -1 ] ; then
  zenity --error --text="Converting canceled."
fi

