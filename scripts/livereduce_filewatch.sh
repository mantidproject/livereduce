#!/bin/bash
echo "ARGS $*"

# Determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# The configuration isn't parsed here - livereduce.py resolves it (with mantid) and publishes the
# resulting script paths, see SCRIPTS_FILE below. It only has to be watched, so a file that doesn't
# exist yet is fine: livereduce.py falls back to defaults and creating it later is a change like any other
if [ ! -d "$(dirname "${CONFIG_FILE}")" ]; then
    echo "ERROR: Directory of config file '${CONFIG_FILE}' does not exist." >&2
    exit 1
fi

##############
### CONFIG ###
##############

FILEWATCH_LOG="/var/log/SNS_applications/livereduce_filewatch.log"

# matches only the python process running livereduce.py - not the livereduce.sh wrapper or a pixi
# process in between, whose command lines also mention livereduce.py but would die on SIGHUP
LIVEREDUCE_PATTERN='^[^ ]*python[0-9.]* [^ ]*livereduce\.py( |$)'

# The script paths depend on mantid's short instrument name (e.g. POWGEN -> PG3), so livereduce.py
# publishes the paths it resolved here rather than this script guessing them (see
# Config.__publishScriptPaths in scripts/livereduce.py). /run/livereduce comes from livereduce.service
SCRIPTS_FILE="${LIVEREDUCE_SCRIPTS_FILE:-/run/livereduce/scripts.json}"
if [ ! -d "$(dirname "${SCRIPTS_FILE}")" ]; then
    echo "ERROR: Directory of '${SCRIPTS_FILE}' does not exist - has livereduce.service been started?" >&2
    exit 1
fi
SCRIPTS_FILE="$(realpath "${SCRIPTS_FILE}")"

# livereduce.py writes it a few seconds after starting, so wait rather than fail
if [ ! -f "${SCRIPTS_FILE}" ]; then
    echo "Waiting for livereduce.py to publish '${SCRIPTS_FILE}'"
    until [ -f "${SCRIPTS_FILE}" ]; do sleep 1; done
fi

# Read in one jq call, so every field comes from the same version of the file. The md5s are of what
# livereduce.py actually loaded, and empty for a missing or empty file
{
    read -r PUBLISHED_CONFIG
    read -r CONFIG_MD5
    read -r SCRIPT_DIR
    read -r PROC_SCRIPT
    read -r PROC_MD5
    read -r POST_PROC_SCRIPT
    read -r POST_PROC_MD5
} < <(/bin/jq --raw-output '.config_file // "", .config_md5 // "", .script_dir // "", .proc_script // "",
    .proc_md5 // "", .post_proc_script // "", .post_proc_md5 // ""' "${SCRIPTS_FILE}" 2>/dev/null)
if [ -z "${SCRIPT_DIR}" ] || [ -z "${PROC_SCRIPT}" ] || [ -z "${POST_PROC_SCRIPT}" ]; then
    echo "ERROR: '${SCRIPTS_FILE}' is not valid JSON or is missing a script path." >&2
    exit 1
fi

# the published paths, to tell a republish with new paths from one that only updates the md5s
paths_signature() {
    /bin/jq --raw-output '[.config_file // "", .script_dir // "", .proc_script // "", .post_proc_script // ""]
        | join("|")' "${SCRIPTS_FILE}" 2>/dev/null
}
PATHS_SIG="${PUBLISHED_CONFIG}|${SCRIPT_DIR}|${PROC_SCRIPT}|${POST_PROC_SCRIPT}"

if [ ! -d "${SCRIPT_DIR}" ]; then
    echo "ERROR: script_dir '${SCRIPT_DIR}' does not exist." >&2
    exit 1
fi

# Absolute paths, so they can be compared against the paths inotifywait reports below. Only the
# directory is resolved: a symlinked file keeps its own path, so repointing the link is seen
canonical() { echo "$(realpath "$(dirname "${1}")")/$(basename "${1}")"; }
# the config livereduce.py actually read, if any; otherwise the one it would read once created
[ -n "${PUBLISHED_CONFIG}" ] && CONFIG_FILE="${PUBLISHED_CONFIG}"
CONFIG_FILE="$(canonical "${CONFIG_FILE}")"
SCRIPT_DIR="$(realpath "${SCRIPT_DIR}")"
PROC="${SCRIPT_DIR}/$(basename "${PROC_SCRIPT}")"
POST_PROC="${SCRIPT_DIR}/$(basename "${POST_PROC_SCRIPT}")"

# A symlinked file is also watched through its target's directory, so editing the target is seen.
# TARGET is what each file linked to at startup (empty if not a link); ALIAS maps a target back
link_target() { [ -L "${1}" ] && realpath -m "${1}"; }
declare -A TARGET ALIAS WATCH_DIRS
WATCH_DIRS["${SCRIPT_DIR}"]=1
WATCH_DIRS["$(dirname "${CONFIG_FILE}")"]=1
WATCH_DIRS["$(dirname "${SCRIPTS_FILE}")"]=1
for f in "${CONFIG_FILE}" "${PROC}" "${POST_PROC}"; do
    TARGET["${f}"]="$(link_target "${f}")"
    if [ -n "${TARGET[${f}]}" ] && [ -d "$(dirname "${TARGET[${f}]}")" ]; then
        ALIAS["${TARGET[${f}]}"]="${f}"
        WATCH_DIRS["$(dirname "${TARGET[${f}]}")"]=1
    fi
done

for f in "${CONFIG_FILE}" "${PROC}" "${POST_PROC}"; do
    echo "Watching ${f}${TARGET[${f}]:+ -> ${TARGET[${f}]}}"
done
echo "Script paths published in ${SCRIPTS_FILE}"


##################################################################################################
# md5sum of each watched file, starting from what livereduce.py loaded rather than what's on disk now,
# so a change made before the watches were set up is still acted on. Empty counts as absent, as it
# does for livereduce.py
file_hash() { [ -s "${1}" ] && md5sum "${1}" | cut -d' ' -f1 || echo "absent"; }

declare -A LAST_HASH=(
    ["${CONFIG_FILE}"]="${CONFIG_MD5:-absent}"
    ["${PROC}"]="${PROC_MD5:-absent}"
    ["${POST_PROC}"]="${POST_PROC_MD5:-absent}"
)

changed() {  # returns 0 and updates the stored hash if content differs
    local new; new="$(file_hash "${1}")"
    [ "${new}" = "${LAST_HASH[${1}]}" ] && return 1
    LAST_HASH["${1}"]="${new}"
}

##################################################################################################
# Function to signal livereduce.py and log the reason
#   HUP  - reload the processing scripts in-process (see the main loop in livereduce.py)
#   TERM - shut down cleanly; livereduce.service's Restart=always starts it again on the new config
# Signals go straight to the process rather than through systemctl: both services run as the same
# user, so no polkit permission is needed, and the livereduce.sh wrapper stays out of the way.
signal_livereduce() {
    local signal="${1}"
    local reason="${2}"
    {
        echo -e "\n#############################################################################"
        echo "$(date --iso-8601=seconds) ${reason}"
        if pkill "-${signal}" -u "$(id -u)" -f "${LIVEREDUCE_PATTERN}"; then
            echo "sent SIG${signal} to livereduce.py"
        else
            # nothing to do - it picks up the current files whenever it next starts
            echo "livereduce.py is not running, no SIG${signal} sent"
        fi
    } >>"${FILEWATCH_LOG}"
}

##################################################################################################
# Events are acted on once they stop arriving for SETTLE_US. Saves that rename the old file away or
# delete it first (vim, git checkout) then leave the file in place before the daemon rereads it, and
# a burst of events from one save gives one signal. PENDING holds the events for each file meanwhile.
SETTLE_US=1000000
declare -A PENDING
DEADLINE=0
now_us() { echo "${EPOCHREALTIME//[.,]/}"; }

exit_to_reload() {  # the watch list is only built at startup - exit and let systemd restart us
    echo -e "\n$(date --iso-8601=seconds) ${1}, exiting so the watcher reloads them" >>"${FILEWATCH_LOG}"
    exit 0
}

flush() {
    local f retarget="" reasons=()
    for f in "${!PENDING[@]}"; do
        [ "$(link_target "${f}")" != "${TARGET[${f}]}" ] && retarget="${f}"
    done
    if [ -n "${PENDING[${CONFIG_FILE}]:-}" ] && changed "${CONFIG_FILE}"; then
        signal_livereduce TERM "Configuration file '${CONFIG_FILE}' changed (${PENDING[${CONFIG_FILE}]})"
        # it rereads the scripts when it restarts, so they need no HUP of their own
        changed "${PROC}"
        changed "${POST_PROC}"
    else
        for f in "${PROC}" "${POST_PROC}"; do
            [ -n "${PENDING[${f}]:-}" ] && changed "${f}" &&
                reasons+=("Processing script '${f}' changed (${PENDING[${f}]})")
        done
        [ "${#reasons[@]}" -gt 0 ] && signal_livereduce HUP "$(printf '%s\n' "${reasons[@]}")"
    fi
    PENDING=()
    [ -n "${retarget}" ] && exit_to_reload "Symlink '${retarget}' now points elsewhere"
}

# once the watches are set up, catch anything that changed before then
reconcile() {
    local f
    [ "$(paths_signature)" != "${PATHS_SIG}" ] && exit_to_reload "livereduce.py published new paths"
    for f in "${CONFIG_FILE}" "${PROC}" "${POST_PROC}"; do
        [ "$(file_hash "${f}")" != "${LAST_HASH[${f}]}" ] && PENDING["${f}"]="before watching"
    done
    DEADLINE=$(($(now_us) + SETTLE_US))
}

##################################################################################################
# -m: keep running after the first event
# -e: close_write fires once per completed save (modify fires on every write);
#     moved_to/moved_from catch saves that write a temp file and rename it into place
# Directories are watched, not files: a file watch is lost when the file is renamed over
# --format: "dir|file|event", to rebuild the full path below. Its own messages (stderr) come through
# too, with no "|", so "Watches established." can start reconcile()
#
# Process substitution, not a pipe, so `exit` in the loop ends the script; the trap stops inotifywait
exec {EVENTS}< <(inotifywait -m -e close_write,delete,moved_to,moved_from \
    --format '%w|%f|%e' "${!WATCH_DIRS[@]}" 2>&1)
INOTIFY_PID=$!
trap 'kill "${INOTIFY_PID}" 2>/dev/null' EXIT

while true; do
    timeout=()
    if [ "${#PENDING[@]}" -gt 0 ]; then
        remaining=$((DEADLINE - $(now_us)))
        if [ "${remaining}" -le 0 ]; then
            flush
            continue
        fi
        timeout=(-t "$(printf '%d.%06d' $((remaining / 1000000)) $((remaining % 1000000)))")
    fi
    IFS='|' read -r "${timeout[@]}" -u "${EVENTS}" dir file event
    status=$?
    [ "${status}" -gt 128 ] && continue # timed out - flushed at the top of the loop
    if [ "${status}" -ne 0 ]; then
        echo "ERROR: inotifywait stopped" >&2
        exit 1
    fi

    if [ -z "${file}" ]; then # a message from inotifywait itself
        echo "${dir}"
        [ "${dir}" = "Watches established." ] && reconcile
        continue
    fi

    path="${dir%/}/${file}"
    path="${ALIAS[${path}]:-${path}}"
    case "${path}" in
        "${SCRIPTS_FILE}")
            # republished after every reload with new md5s; only new paths need a restart
            [ "$(paths_signature)" != "${PATHS_SIG}" ] && exit_to_reload "livereduce.py published new paths"
            ;;
        "${CONFIG_FILE}" | "${PROC}" | "${POST_PROC}")
            PENDING["${path}"]="${PENDING[${path}]:+${PENDING[${path}]} }${event}"
            DEADLINE=$(($(now_us) + SETTLE_US))
            ;;
    esac
    # any other file in the watched directories is ignored
done
