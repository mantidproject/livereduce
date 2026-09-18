#!/bin/bash
echo "ARGS $*"

# determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# Check if the configuration file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

# --- CONFIG ---
MANAGED_SERVICE="livereduce.service"
FILEWATCH_LOG="/var/log/SNS_applications/livereduce_filewatch.log"

# livereduce.py reads script_dir/instrument once at startup and never watches them itself
# (see Config.__init__ / Config.__determineScriptNames in scripts/livereduce.py), so this
# service exists to notice changes on its behalf and restart it.
INSTRUMENT="$(/bin/jq --raw-output '.instrument // empty' "${CONFIG_FILE}")"
SCRIPT_DIR="$(/bin/jq --raw-output '.script_dir // empty' "${CONFIG_FILE}")"
if [ -z "${SCRIPT_DIR}" ]; then
    if [ -z "${INSTRUMENT}" ]; then
        echo "ERROR: '${CONFIG_FILE}' has neither 'script_dir' nor 'instrument' set - cannot determine which directory to watch." >&2
        exit 1
    fi
    # must match the default computed by Config.__init__ in scripts/livereduce.py
    SCRIPT_DIR="/SNS/${INSTRUMENT}/shared/livereduce"
fi

if [ ! -d "${SCRIPT_DIR}" ]; then
    echo "ERROR: script_dir '${SCRIPT_DIR}' does not exist." >&2
    exit 1
fi

# the two filenames livereduce.py looks for (see Config.__determineScriptNames)
PROC_SCRIPT="reduce_${INSTRUMENT}_live_proc.py"
POST_PROC_SCRIPT="reduce_${INSTRUMENT}_live_post_proc.py"

echo "Watching configuration file: ${CONFIG_FILE}"
echo "Watching script directory  : ${SCRIPT_DIR}"
echo "  processing script        : ${PROC_SCRIPT}"
echo "  post-processing script   : ${POST_PROC_SCRIPT}"

restart_livereduce() {
    local reason="${1}"
    {
        echo -e "\n#############################################################################"
        echo "$(date --iso-8601=seconds) ${reason}"
        echo "restarting ${MANAGED_SERVICE}."
    } >>"${FILEWATCH_LOG}"
    if command -v systemctl &>/dev/null; then
        systemctl restart "${MANAGED_SERVICE}"
        sleep 5 # give it a moment to start
        systemctl status "${MANAGED_SERVICE}" >>"${FILEWATCH_LOG}"
    else
        service "${MANAGED_SERVICE}" restart
        sleep 5 # give it a moment to start
        service "${MANAGED_SERVICE}" status >>"${FILEWATCH_LOG}"
    fi
}

# -m: monitor mode, keep running instead of exiting after the first event
# -e: create (new script deployed), modify (edited in place), delete, and the two "moved"
#     events (covers editors/scp that write to a temp file and rename it over the target)
# --format: emit "path|event" per line so the reader below can match against known filenames
inotifywait -m -e modify,create,delete,moved_to,moved_from \
    --format '%w%f|%e' \
    "${SCRIPT_DIR}" "${CONFIG_FILE}" |
    while IFS='|' read -r path event; do
        if [ "${path}" = "${CONFIG_FILE}" ]; then
            restart_livereduce "Configuration file '${path}' changed (${event})"
            continue
        fi

        base="$(basename "${path}")"
        if [ "${base}" = "${PROC_SCRIPT}" ] || [ "${base}" = "${POST_PROC_SCRIPT}" ]; then
            restart_livereduce "Processing script '${path}' changed (${event})"
        fi
        # other files created/modified/deleted in script_dir are ignored, same as the old
        # pyinotify-based EventHandler only acting on the tracked proc/post_proc filenames
    done
