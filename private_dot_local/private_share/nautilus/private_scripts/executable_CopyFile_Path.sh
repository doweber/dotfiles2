#!/bin/bash
## Variables: (Refer to: https://help.ubuntu.com/community/NautilusScriptsHowto)
# NAUTILUS_SCRIPT_CURRENT_URI='file://... current directory'
# NAUTILUS_SCRIPT_SELECTED_FILE_PATHS='... each file is terminated with \n'
# NAUTILUS_SCRIPT_SELECTED_URIS='file://... each file is terminated with \n'
# NAUTILUS_SCRIPT_WINDOW_GEOMETRY=1920x999+0+0

echo -n "$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS" | sed -z 's/.$//' | xsel -b -i
zenity --info --no-wrap --no-markup \
  --title="File name(s) copied to Clipboard:" \
  --text="$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS"
