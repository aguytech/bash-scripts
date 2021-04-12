#!/bin/bash
#
# Provides:             thunar_newtab
# Short-Description:    A wrapper with xdotool for thunar. Open new tab with URI in last thunar window
# Description:          A wrapper with xdotool for thunar. Open new tab with URI in last thunar window

file_log=/var/log/server/${0##*/}
app=thunar
uris="$@"

for uri in $uris; do
    if [ -d "$uri" ] || [ "${uri/sftp:/}" != "$uri" ]; then # test uri is file
        echo -n "$(date +"%d-%m-%Y %T") - $uri" >> "$file_log"

        wid=( $(xdotool search --desktop $(xdotool get_desktop) --class $app) )
        lastwid=${wid[*]: -1} # Get PID of newest active $app window.

        # if $wid is null launch app with filepath.
        if [ -z "$wid" ]; then
            echo -n "$(date +"%d-%m-%Y %T") - thunar $uri" >> "$file_log"
            $app "$uri" &
            sleep 0.5s

            wid=( $(xdotool search --desktop $(xdotool get_desktop) --class $app) )
            lastwid=${wid[*]: -1} # Get PID of newest active thunar window.

        # if app is already running, activate it and use shortcuts to paste filepath into path bar.
        else
            xdotool windowactivate --sync $lastwid key ctrl+t ctrl+l # Activate pathbar in thunar --delay 50
            xdotool type --delay 0 "$uri" # "--delay 0" removes default 12ms between each keystroke
            xdotool key Return
        fi

        echo " - OK"  >> "$file_log"
    else
        echo "$(date +"%d-%m-%Y %T") - $uri - FAILED: not exists" >> "$file_log"
    fi
done

exit 0

