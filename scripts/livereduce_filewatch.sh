#!/bin/bash

##########################################################################################################
# When the livereduce service starts, `livereduce.py` runs in the background and generates
# `/var/lib/livereduce/livereduce_filewatch.json`, which contains:
# the systemd invocation id of the service run that wrote it, and the filepath, md5 sum, and file size
# of the config file, proc script, and postproc script.
# This script waits for that file, reads it once and runs `inotifywait` to watch for changes to those files.
# When a change is detected, it waits until the files have been quiet for `filewatch.delay` seconds
# (default 5) from the config file, so that several saves in a row lead to one restart.
# It then compares each file's size, then md5 sum, with what livereduce.py loaded, and logs each that changed.
# If any did, it restarts livereduce.service with `systemctl`, as the watchdog does
# (allowed by the polkit rule 50-snsdata-livereduce.rules).
# The restarted `livereduce.py` reloads the new config and scripts and writes the new filewatch data.
# `PartOf=livereduce.service` restarts this script along with it, so it then watches the new files.
# A file that is a symlink is followed: the directory of the file it points to is watched as well.
##########################################################################################################

echo "Starting livereduce_filewatch.sh"
echo "ARGS: $*"

# Written by livereduce.py (see FILEWATCH_JSON in scripts/livereduce.py)
JSON_FILE="${LIVEREDUCE_FILEWATCH_JSON:-/var/lib/livereduce/livereduce_filewatch.json}"

SERVICE="livereduce.service"

FILEWATCH_LOG="${LIVEREDUCE_FILEWATCH_LOG:-/var/log/SNS_applications/livereduce_filewatch.log}"
# fail at startup, as livereduce.py does for its own log; a write failing later only warns (see log_entry)
if ! { : >>"${FILEWATCH_LOG}"; } 2>/dev/null; then
    echo "ERROR: Cannot write to log file '${FILEWATCH_LOG}'." >&2
    exit 1
fi

######################
### Reusable functions
######################

# Read the filewatch data from the JSON file and set as global variables. Returns 1 if it doesn't exist
read_filewatch_data() {
    local json_file="$JSON_FILE"
    [ -f "$json_file" ] || return 1
    # Read the JSON file and extract the file paths, md5 sums, and file sizes
    # Note, only one of proc or postproc is required;
    # if one is missing, they get set to "null"
    # Read the file once, as livereduce.py may replace it between the jq calls
    local json
    json=$(<"$json_file") || return 1
    INVOCATION_ID=$(jq -r '.invocation_id' <<<"$json")
    CONFIG_PATH=$(jq -r '.config_file' <<<"$json")
    CONFIG_MD5=$(jq -r '.config_md5' <<<"$json")
    CONFIG_SIZE=$(jq -r '.config_size_bytes' <<<"$json")
    PROC_PATH=$(jq -r '.proc_script' <<<"$json")
    PROC_MD5=$(jq -r '.proc_md5' <<<"$json")
    PROC_SIZE=$(jq -r '.proc_size_bytes' <<<"$json")
    POST_PROC_PATH=$(jq -r '.post_proc_script' <<<"$json")
    POST_PROC_MD5=$(jq -r '.post_proc_md5' <<<"$json")
    POST_PROC_SIZE=$(jq -r '.post_proc_size_bytes' <<<"$json")
    # the files the published paths point to, which differ only if a path is, or is under, a symlink
    CONFIG_REAL=$(resolve_path "$CONFIG_PATH")
    PROC_REAL=$(resolve_path "$PROC_PATH")
    POST_PROC_REAL=$(resolve_path "$POST_PROC_PATH")
}

# Resolve every symlink in a path, or return "null" for a "null" path
resolve_path() { if [ "${1}" = "null" ]; then echo "null"; else readlink -m "${1}"; fi; }

# Get file hash (md5 sum) of a file, or return "null" if the file does not exist or is empty
file_hash() { [ -s "${1}" ] && md5sum "${1}" | cut -d' ' -f1 || echo "null"; }

# Get file size of a file, following symlinks as livereduce.py does, or return "null" if the file does not exist or is empty
file_size() { [ -s "${1}" ] && stat -L -c%s "${1}" || echo "null"; }

# Compare a file's size, then md5 sum, with the stored values. If it changed, add why to CHANGES and return 0
file_changed() {
    local file_path="$1" old_md5="$2" old_size="$3" new_md5 new_size

    # if path is "null", skip the check
    if [ "$file_path" = "null" ]; then
        echo "Skipping check for $file_path (not present)"
        return 1
    fi

    # First check file size
    new_size=$(file_size "$file_path")
    if [ "$new_size" != "$old_size" ]; then
        CHANGES+=("File size changed for $file_path (old: $old_size, new: $new_size)")
        return 0
    fi

    # If file size is the same, check md5 sum
    new_md5=$(file_hash "$file_path")
    if [ "$new_md5" != "$old_md5" ]; then
        CHANGES+=("MD5 sum changed for $file_path (old: $old_md5, new: $new_md5)")
        return 0
    fi
    return 1
}

# Check all files for changes, listing them in CHANGES. Returns 0 if any changed
check_all() {
    CHANGES=()
    file_changed "$CONFIG_PATH" "$CONFIG_MD5" "$CONFIG_SIZE"
    file_changed "$PROC_PATH" "$PROC_MD5" "$PROC_SIZE"
    file_changed "$POST_PROC_PATH" "$POST_PROC_MD5" "$POST_PROC_SIZE"
    [ "${#CHANGES[@]}" -gt 0 ]
}

# Seconds to wait for the files to be quiet before acting on a change: filewatch.delay in the config
# file livereduce.py loaded, or the default when that is missing, unreadable or invalid
read_delay() {
    local delay=""
    if [ "$CONFIG_PATH" != "null" ]; then
        delay=$(jq -r ".filewatch.delay // ${DEFAULT_DELAY}" "$CONFIG_PATH" 2>/dev/null)
    fi
    if ! [[ "$delay" =~ ^[0-9]+$ ]]; then
        [ -n "$delay" ] && echo "WARNING: Invalid filewatch.delay value '$delay'. Using default: $DEFAULT_DELAY" >&2
        delay=$DEFAULT_DELAY
    fi
    echo "$delay"
}

# Whether the json was written by the current run of livereduce.service, which is running. Until then
# it is missing, or left over from the previous run
published_by_current_run() {
    [ "$INVOCATION_ID" != "null" ] || return 1
    systemctl --quiet is-active "$SERVICE" || return 1
    [ "$(systemctl show --property InvocationID --value "$SERVICE")" = "$INVOCATION_ID" ]
}

# Log an entry to the journal and the log file
log_entry() {
    local entry
    entry="$(date --iso-8601=seconds) ${1}"
    echo "${entry}" # journal
    printf '\n%s\n%s\n' "#############################################################################" "${entry}" \
        >>"${FILEWATCH_LOG}" 2>/dev/null || echo "WARNING: could not write to ${FILEWATCH_LOG}" >&2
}

# Restart livereduce.service, logging each of the CHANGES that caused it. Returns 1 if systemctl refused
restart_livereduce() {
    local error
    # log first: the restart stops this script too (PartOf=), which may not get to log afterwards.
    # A log file that can't be written only warns, so never stops the change being delivered
    log_entry "$(printf '%s\n' "${CHANGES[@]}")"$'\n'"restarting ${SERVICE}"
    # --no-block: don't wait for the job, which stops this script
    if ! error=$(systemctl restart --no-block "${SERVICE}" 2>&1); then
        log_entry "could not restart ${SERVICE}: ${error}" # a later change tries again
        return 1
    fi
}

#############################
### Main script execution ###
#############################

# Set once livereduce.service has been restarted; this script is restarted with it
WAITING=0
# When to check the files after a change ($SECONDS), once they have been quiet for DELAY seconds; empty when no change
DEADLINE=""
DEFAULT_DELAY=5

# A change was seen: check the files once they have been quiet for DELAY seconds
schedule_check() { DEADLINE=$((SECONDS + DELAY)); }

# The files have been quiet since a change: restart livereduce.service if any of them changed. An edit
# that was undone in the meantime changes nothing
apply_changes() {
    DEADLINE=""
    check_all && restart_livereduce && WAITING=1
}

# Wait for the run of livereduce.service this script was started with to publish what it loaded
echo "Waiting for livereduce.py to publish $JSON_FILE"
until read_filewatch_data && published_by_current_run; do
    sleep 1
done
echo "Watching the files published by livereduce.py (invocation $INVOCATION_ID)"
DELAY=$(read_delay)
echo "Acting on changes once the files have been quiet for $DELAY s"
# catch changes made after livereduce.py loaded the files
check_all && schedule_check

# Watch the directories of the files, not the files themselves: a file watch is lost when an
# editor saves by renaming a new file over the old one, and inotifywait fails on a "null" path.
# The directories of symlink targets are watched too, so editing the file a symlink points to is seen
mapfile -t WATCH_DIRS < <(
    for file in "$CONFIG_PATH" "$PROC_PATH" "$POST_PROC_PATH" \
        "$CONFIG_REAL" "$PROC_REAL" "$POST_PROC_REAL"; do
        [ "$file" != "null" ] && dirname "$file"
    done | sort -u
)

# Set up inotifywait to watch for changes to the files
# When a change to one of them is detected, the files are checked once they have been quiet for DELAY seconds
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

while true; do
    # wait for the next event, or only until the deadline when a change is pending
    timeout=()
    if [ -n "$DEADLINE" ]; then
        remaining=$((DEADLINE - SECONDS))
        if [ "$remaining" -le 0 ]; then
            apply_changes
            continue
        fi
        timeout=(-t "$remaining")
    fi
    IFS='|' read -r -u "$EVENTS" "${timeout[@]}" dir file _event
    status=$?
    if [ "$status" -gt 128 ]; then # timed out: the files have been quiet
        apply_changes
        continue
    fi
    [ "$status" -eq 0 ] || break # inotifywait stopped

    # inotifywait's own messages (e.g. "Watches established.") have no "|"
    if [ -z "$file" ]; then
        echo "$dir"
        continue
    fi
    # livereduce is already restarting, and will load the current files. systemd restarts this script with it
    [ "$WAITING" -eq 1 ] && continue
    path="${dir%/}/${file}"
    case "$path" in
        "$CONFIG_PATH" | "$CONFIG_REAL" | "$PROC_PATH" | "$PROC_REAL" | "$POST_PROC_PATH" | "$POST_PROC_REAL")
            schedule_check
            ;;
    esac
    # any other file in the watched directories is ignored
done

echo "Error: inotifywait stopped" >&2
exit 1
