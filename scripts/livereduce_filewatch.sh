#!/bin/bash

##########################################################################################################
# When the livereduce service starts, `livereduce.py` runs in the background and generates
# `/var/lib/livereduce/livereduce_filewatch.json`, which contains:
# the filepath, md5 sum, and file size of the config file, proc script, and postproc script.
# This script reads that file and runs `inotifywait` to watch for changes to those files.
# When a change is detected, it first compares the new file size to the old file size.
# If the file size has changed, it sends SIGTERM to livereduce.py, using the pid in that file.
# If the file size has not changed, it compares the new md5 sum to the old md5 sum.
# livereduce.py shuts down cleanly on SIGTERM and `Restart=always` in livereduce.service restarts it,
# which will cause `livereduce.py` to reload the new config and scripts and write the new filewatch data.
# This script watches that file too, and re-reads it when it is rewritten.
##########################################################################################################

echo "Starting livereduce_filewatch.sh"
echo "ARGS: $*"

# Determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# Written by livereduce.py (see FILEWATCH_JSON in scripts/livereduce.py)
JSON_FILE="${LIVEREDUCE_FILEWATCH_JSON:-/var/lib/livereduce/livereduce_filewatch.json}"

FILEWATCH_LOG="${LIVEREDUCE_FILEWATCH_LOG:-/var/log/SNS_applications/livereduce_filewatch.log}"
# fail at startup, as livereduce.py does for its own log; a write failing later only warns (see signal_livereduce)
if ! { : >>"${FILEWATCH_LOG}"; } 2>/dev/null; then
    echo "ERROR: Cannot write to log file '${FILEWATCH_LOG}'." >&2
    exit 1
fi

######################
### Reusable functions
######################

# Read the filewatch data from the JSON file and set as global variables
read_filewatch_data() {
    local json_file="$JSON_FILE"
    if [ ! -f "$json_file" ]; then
        echo "Error: $json_file does not exist."
        exit 1
    fi
    # Read the JSON file and extract the file paths, md5 sums, and file sizes
    # Note, only one of proc or postproc is required;
    # if one is missing, they get set to "null"
    LIVEREDUCE_PID=$(jq -r '.pid' "$json_file")
    CONFIG_PATH=$(jq -r '.config_file' "$json_file")
    CONFIG_MD5=$(jq -r '.config_md5' "$json_file")
    CONFIG_SIZE=$(jq -r '.config_size_bytes' "$json_file")
    PROC_PATH=$(jq -r '.proc_script' "$json_file")
    PROC_MD5=$(jq -r '.proc_md5' "$json_file")
    PROC_SIZE=$(jq -r '.proc_size_bytes' "$json_file")
    POST_PROC_PATH=$(jq -r '.post_proc_script' "$json_file")
    POST_PROC_MD5=$(jq -r '.post_proc_md5' "$json_file")
    POST_PROC_SIZE=$(jq -r '.post_proc_size_bytes' "$json_file")
}

# Get file hash (md5 sum) of a file, or return "null" if the file does not exist or is empty
file_hash() { [ -s "${1}" ] && md5sum "${1}" | cut -d' ' -f1 || echo "null"; }

# Get file size of a file, or return "null" if the file does not exist or is empty
file_size() { [ -s "${1}" ] && stat -c%s "${1}" || echo "null"; }

# Compare the current file size and md5 sum of a file to the stored values, and kill the livereduce service if they differ
check_and_kill_if_changed() {
    local file_path="$1"
    local old_md5="$2"
    local old_size="$3"
    local new_md5
    local new_size

    # livereduce is already restarting, and will load the current files
    if [ "$WAITING" -eq 1 ]; then
        return
    fi

    # if path is "null", skip the check
    if [ "$file_path" = "null" ]; then
        echo "Skipping check for $file_path (not present)"
        return
    fi

    # First check file size
    new_size=$(file_size "$file_path")
    if [ "$new_size" != "$old_size" ]; then
        signal_livereduce TERM "File size changed for $file_path (old: $old_size, new: $new_size)" && WAITING=1
        return
    fi

    # If file size is the same, check md5 sum
    new_md5=$(file_hash "$file_path")
    if [ "$new_md5" != "$old_md5" ]; then
        signal_livereduce TERM "MD5 sum changed for $file_path (old: $old_md5, new: $new_md5)" && WAITING=1
    fi
}

# Check all files for changes
check_all () {
    check_and_kill_if_changed "$CONFIG_PATH" "$CONFIG_MD5" "$CONFIG_SIZE"
    check_and_kill_if_changed "$PROC_PATH" "$PROC_MD5" "$PROC_SIZE"
    check_and_kill_if_changed "$POST_PROC_PATH" "$POST_PROC_MD5" "$POST_PROC_SIZE"
}

# Whether the pid livereduce.py published is still livereduce.py, run by this user. It may have exited,
# and its pid been reused, since it wrote the json
livereduce_running() {
    [[ "$LIVEREDUCE_PID" =~ ^[0-9]+$ ]] || return 1
    [ -O "/proc/$LIVEREDUCE_PID" ] || return 1
    tr '\0' '\n' <"/proc/$LIVEREDUCE_PID/cmdline" 2>/dev/null | grep -qx '\(.*/\)\?livereduce\.py'
}

# Signal livereduce.py with a reason, which is logged. Returns 1 if livereduce.py isn't running
signal_livereduce() {
    local signal="${1}" reason="${2}" result entry status=0
    # signal first, so a log file that can't be written never stops the change being delivered
    if livereduce_running && kill "-${signal}" "${LIVEREDUCE_PID}" 2>/dev/null; then
        result="sent SIG${signal} to livereduce.py (pid ${LIVEREDUCE_PID})"
    else
        # nothing to do - it picks up the current files whenever it next starts
        result="livereduce.py (pid ${LIVEREDUCE_PID}) is not running, no SIG${signal} sent"
        status=1
    fi
    entry="$(date --iso-8601=seconds) ${reason}"$'\n'"${result}"
    echo "${entry}" # journal
    printf '\n%s\n%s\n' "#############################################################################" "${entry}" \
        >>"${FILEWATCH_LOG}" 2>/dev/null || echo "WARNING: could not write to ${FILEWATCH_LOG}" >&2
    return "${status}"
}

#############################
### Main script execution ###
#############################

# Wait while livereduce service is restarting and generating new filewatch data
WAITING=0

# Read the filewatch data and initial check of the files
read_filewatch_data
check_all

# The directories below are only computed once, so a change of paths needs a restart of this script
WATCHED_PATHS="$CONFIG_PATH|$PROC_PATH|$POST_PROC_PATH"

# Watch the directories of the files, not the files themselves: a file watch is lost when an
# editor saves by renaming a new file over the old one, and inotifywait fails on a "null" path
mapfile -t WATCH_DIRS < <(
    for file in "$JSON_FILE" "$CONFIG_PATH" "$PROC_PATH" "$POST_PROC_PATH"; do
        [ "$file" != "null" ] && dirname "$file"
    done | sort -u
)

# Set up inotifywait to watch for changes to the files
# When a change is detected, it will call check_and_kill_if_changed for the changed file
# close_write fires once per completed save (modify fires on every write, mid-save);
# moved_to/moved_from/delete catch saves that rename a temp file into place or remove the file
#
# Read through process substitution, not a pipe: a piped loop runs in a subshell, where `exit` would
# only end the loop and leave inotifywait (and this script) running. The trap stops inotifywait
exec {EVENTS}< <(inotifywait -m -e close_write,delete,moved_to,moved_from \
    --format '%w|%f|%e' \
    "${WATCH_DIRS[@]}" 2>&1)
INOTIFY_PID=$!
trap 'kill "$INOTIFY_PID" 2>/dev/null' EXIT

while IFS='|' read -r -u "$EVENTS" dir file event; do
    # inotifywait's own messages (e.g. "Watches established.") have no "|"
    if [ -z "$file" ]; then
        echo "$dir"
        continue
    fi
    path="${dir%/}/${file}"
    case "$path" in
        "$JSON_FILE")
            # livereduce.py writes a temp file and renames it into place
            [ "$event" = "MOVED_TO" ] || continue
            read_filewatch_data
            if [ "$CONFIG_PATH|$PROC_PATH|$POST_PROC_PATH" != "$WATCHED_PATHS" ]; then
                echo "Watched paths changed, exiting so systemd restarts the watcher"
                exit 0
            fi
            WAITING=0
            # catch changes made after livereduce.py loaded the files
            check_all
            ;;
        "$CONFIG_PATH")
            check_and_kill_if_changed "$path" "$CONFIG_MD5" "$CONFIG_SIZE"
            ;;
        "$PROC_PATH")
            check_and_kill_if_changed "$path" "$PROC_MD5" "$PROC_SIZE"
            ;;
        "$POST_PROC_PATH")
            check_and_kill_if_changed "$path" "$POST_PROC_MD5" "$POST_PROC_SIZE"
            ;;
    esac
    # any other file in the watched directories is ignored
done

echo "Error: inotifywait stopped" >&2
exit 1
