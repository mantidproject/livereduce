#!/bin/bash
# Tests scripts/livereduce_filewatch.sh on its own - no systemd, mantid, or real livereduce needed.
# A stand-in livereduce.py records the signals the watcher sends it, and publish() writes the json
# that livereduce.py would, with the stand-in's pid. Only the watcher's log path is changed.
#
# usage: pixi run test-filewatch (or test/test_filewatch.sh)
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="${REPO}/scripts/livereduce_filewatch.sh"

# inotifywait may only be available from the pixi environment
if ! command -v inotifywait &>/dev/null && [ -x "${REPO}/.pixi/envs/default/bin/inotifywait" ]; then
    PATH="${REPO}/.pixi/envs/default/bin:${PATH}"
fi
for tool in inotifywait jq md5sum stat python3; do
    command -v "${tool}" &>/dev/null || {
        echo "ERROR: '${tool}' is required" >&2
        exit 1
    }
done

##################################################################################################
# scratch area
T="$(mktemp -d)"
CONF="${T}/etc/livereduce.conf"
SCRIPTS="${T}/scripts"
PROC="${SCRIPTS}/reduce_TEST_live_proc.py"
POST_PROC="${SCRIPTS}/reduce_TEST_live_post_proc.py"
SCRIPTS2="${T}/scripts2"
export LIVEREDUCE_FILEWATCH_JSON="${T}/state/livereduce_filewatch.json"
export LIVEREDUCE_FILEWATCH_LOG="${T}/filewatch.log" # written by the watcher
SIGNALS="${T}/signals.log"                            # written by the stand-in livereduce.py
mkdir -p "${T}/etc" "${SCRIPTS}" "${SCRIPTS2}" "${T}/state" "${T}/bin"

# records each signal it gets; exits on SIGTERM, as livereduce.py does
cat >"${T}/bin/livereduce.py" <<'PYTHON'
import signal, sys

def record(message):
    with open(sys.argv[1], "a") as handle:
        handle.write(message + "\n")

def on_signal(sig, frame):
    record(signal.Signals(sig).name)
    if sig == signal.SIGTERM:
        sys.exit(0)

for sig in (signal.SIGHUP, signal.SIGTERM):
    signal.signal(sig, on_signal)
record("started")
while True:
    signal.pause()
PYTHON

WATCHER_PID=""
FAKE_PID=""
OTHER_PID=""
cleanup() {
    [ -n "${WATCHER_PID}" ] && pkill -P "${WATCHER_PID}" 2>/dev/null
    [ -n "${WATCHER_PID}" ] && kill "${WATCHER_PID}" 2>/dev/null
    [ -n "${FAKE_PID}" ] && kill -KILL "${FAKE_PID}" 2>/dev/null
    [ -n "${OTHER_PID}" ] && kill "${OTHER_PID}" 2>/dev/null
    pkill -f "inotifywait .*${T}" 2>/dev/null
    wait 2>/dev/null
    rm -rf "${T}"
}
trap cleanup EXIT

##################################################################################################
# helpers
FAILURES=0
pass() { echo "PASS: $1"; }
fail() {
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}
check() { # check "description" command...
    local description="${1}"
    shift
    if "$@"; then pass "${description}"; else fail "${description}"; fi
}

wait_for() { # wait_for seconds command...
    local deadline=$((SECONDS + ${1}))
    shift
    until "$@"; do
        [ "${SECONDS}" -ge "${deadline}" ] && return 1
        sleep 0.2
    done
}

recorded() { cat "${SIGNALS}" 2>/dev/null | grep -c "^${1}$"; }
kills() { recorded SIGTERM; }
kills_are() { [ "$(kills)" -eq "${1}" ]; }
alive() { kill -0 "${1}" 2>/dev/null; }
dead() { ! alive "${1}"; }
inotifywait_gone() { ! pgrep -f "inotifywait .*${T}" >/dev/null; }
logged() { grep -qF "${1}" "${LIVEREDUCE_FILEWATCH_LOG}"; }

# waits for the SIGTERM count to reach N, then makes sure no extra one follows
expect_kills() { # expect_kills N "description"
    wait_for 5 kills_are "${1}" && sleep 1
    check "${2} (kills: $(kills), expected ${1})" kills_are "${1}"
}

replace() { # replace file content - via rename, as editors and config management do
    echo "${2}" >"${1}.tmp"
    mv "${1}.tmp" "${1}"
}

# what livereduce.py's Config.write_md5_json writes, also via rename: its pid (the stand-in's unless
# given), and each file's path, size and md5 as it is now, standing in for what livereduce.py loaded.
# A missing script is left out entirely, and config_file is null for the default configuration (publish "" ...)
publish() { # publish config script_dir instrument [pid]
    local proc="${2}/reduce_${3}_live_proc.py" post="${2}/reduce_${3}_live_post_proc.py"
    {
        jq -n --argjson pid "${4:-${FAKE_PID}}" '{pid: $pid}'
        if [ -n "${1}" ]; then
            jq -n --arg f "${1}" --argjson s "$(stat -c%s "${1}")" --arg m "$(md5sum "${1}" | cut -d' ' -f1)" \
                '{config_file: $f, config_size_bytes: $s, config_md5: $m}'
        else
            jq -n '{config_file: null, config_size_bytes: null, config_md5: null}'
        fi
        [ -e "${proc}" ] && jq -n --arg f "${proc}" --argjson s "$(stat -c%s "${proc}")" \
            --arg m "$(md5sum "${proc}" | cut -d' ' -f1)" '{proc_script: $f, proc_size_bytes: $s, proc_md5: $m}'
        [ -e "${post}" ] && jq -n --arg f "${post}" --argjson s "$(stat -c%s "${post}")" \
            --arg m "$(md5sum "${post}" | cut -d' ' -f1)" \
            '{post_proc_script: $f, post_proc_size_bytes: $s, post_proc_md5: $m}'
    } | jq -s add >"${LIVEREDUCE_FILEWATCH_JSON}.tmp"
    mv "${LIVEREDUCE_FILEWATCH_JSON}.tmp" "${LIVEREDUCE_FILEWATCH_JSON}"
}

started_more_than() { [ "$(recorded started)" -gt "${1}" ]; }
start_fake_livereduce() {
    local before
    before="$(recorded started)"
    python3 "${T}/bin/livereduce.py" "${SIGNALS}" &
    FAKE_PID=$!
    wait_for 5 started_more_than "${before}"
}
# livereduce.py started again, as systemd does after it exits on SIGTERM, and published what it
# loaded. A stand-in that wasn't signalled is killed without being recorded
restarted() {
    wait_for 5 dead "${FAKE_PID}" || kill -KILL "${FAKE_PID}" 2>/dev/null
    wait "${FAKE_PID}" 2>/dev/null
    start_fake_livereduce
    publish "${CONF}" "${SCRIPTS}" TEST
}

watcher_said() { grep -q "${1}" "${T}/watcher.out"; }
watching() { watcher_said "Watches established"; }
start_watcher() {
    bash "${WATCHER}" >"${T}/watcher.out" 2>&1 &
    WATCHER_PID=$!
    wait_for 5 watching
}
stop_watcher() {
    pkill -P "${WATCHER_PID}" 2>/dev/null
    kill "${WATCHER_PID}" 2>/dev/null
    wait "${WATCHER_PID}" 2>/dev/null
    WATCHER_PID=""
    wait_for 5 inotifywait_gone
}

##################################################################################################
echo "== startup"
output="$(bash "${WATCHER}" 2>&1)"
check "missing json is rejected" test $? -ne 0 -a -n "$(grep -F "does not exist" <<<"${output}")"
output="$(LIVEREDUCE_FILEWATCH_LOG="${T}/nope/filewatch.log" bash "${WATCHER}" 2>&1)"
check "unwritable log file is rejected" test $? -ne 0 -a -n "$(grep -F "Cannot write to log file" <<<"${output}")"

echo '{"instrument": "TEST"}' >"${CONF}"
echo "# v1" >"${PROC}"
start_fake_livereduce || {
    echo "ERROR: stand-in livereduce.py did not start" >&2
    exit 1
}
publish "${CONF}" "${SCRIPTS}" TEST
start_watcher || {
    echo "ERROR: watcher did not start:" >&2
    cat "${T}/watcher.out" >&2
    exit 1
}
pass "watcher starts"
expect_kills 0 "nothing is killed when the files match the json"
check "the absent post-processing script is skipped" watcher_said "Skipping check for null"

##################################################################################################
echo "== processing script changes"
touch "${PROC}"
expect_kills 0 "touch without a content change is ignored"

echo "# v1" >"${PROC}"
expect_kills 0 "rewriting identical content is ignored"

echo "# v2" >"${PROC}"
expect_kills 1 "editing the script sends SIGTERM"
check "...the reason is logged" logged "MD5 sum changed for ${PROC}"
check "...with the pid signalled" logged "sent SIGTERM to livereduce.py (pid ${FAKE_PID})"

echo "# v3" >"${PROC}"
expect_kills 1 "edits while livereduce restarts are ignored"

restarted
expect_kills 1 "the republished json matches, so nothing is sent"

echo "# v4" >"${PROC}"
expect_kills 2 "the watcher is re-armed by the republished json"

# livereduce.py loaded v4, then the script was edited again before the json was re-read
echo "# v5" >"${PROC}.new"
restarted
mv "${PROC}.new" "${PROC}"
expect_kills 3 "a change after livereduce.py loaded the script is caught when the json is re-read"
restarted

echo "# v6" >"${PROC}"
sleep 1
echo "# v66" >"${PROC}"
expect_kills 4 "a script edit with the same size is caught by its md5"
restarted

echo "# v7" >"${SCRIPTS}/.tmp" && mv "${SCRIPTS}/.tmp" "${PROC}"
expect_kills 5 "renaming a new file over the script sends SIGTERM"
restarted

# vim's default: rename the original to a backup, then write a new file
mv "${PROC}" "${PROC}~" && sleep 0.3 && echo "# v8" >"${PROC}"
expect_kills 6 "a save that renames the old file away first sends one SIGTERM"
restarted

# git checkout: delete, then write
rm "${PROC}" && sleep 0.3 && echo "# v9" >"${PROC}"
expect_kills 7 "a save that deletes the old file first sends one SIGTERM"
restarted

echo "x" >"${SCRIPTS}/unrelated.py"
expect_kills 7 "unrelated file in the script directory is ignored"

# livereduce only notices a new script when restarted; it then publishes a new path, which the
# watcher can only watch by restarting
echo "# post v1" >"${POST_PROC}"
restarted # not signalled, so this stands in for a restart for some other reason
check "watcher exits when a script is added to the json" wait_for 5 dead "${WATCHER_PID}"
WATCHER_PID=""
start_watcher || fail "watcher restarted"
expect_kills 7 "the restarted watcher accepts the json with the new script"

echo "# post v2" >>"${POST_PROC}"
expect_kills 8 "editing the post-processing script sends SIGTERM"
restarted

rm "${POST_PROC}"
expect_kills 9 "deleting the post-processing script sends SIGTERM"
restarted
check "watcher exits when a script is dropped from the json" wait_for 5 dead "${WATCHER_PID}"
WATCHER_PID=""
start_watcher || fail "watcher restarted"

##################################################################################################
echo "== configuration changes"
touch "${CONF}"
echo "x" >"${T}/etc/unrelated.conf"
expect_kills 9 "touching the config or editing a neighbour is ignored"

replace "${CONF}" '{"instrument": "TEST", "update_every": 5}'
expect_kills 10 "changing the config sends SIGTERM"
restarted

##################################################################################################
echo "== livereduce.py not running"
# a stale pid: livereduce.py exited, and its pid was reused by an unrelated process of the same user
sleep 300 &
OTHER_PID=$!
publish "${CONF}" "${SCRIPTS}" TEST "${OTHER_PID}"
sleep 1
echo "# v10" >"${PROC}"
expect_kills 10 "a stale pid is not signalled"
check "...the unrelated process is untouched" alive "${OTHER_PID}"
check "...and nothing to signal is logged" logged "(pid ${OTHER_PID}) is not running, no SIGTERM sent"
check "the watcher keeps running" alive "${WATCHER_PID}"
kill "${OTHER_PID}" && wait "${OTHER_PID}" 2>/dev/null
OTHER_PID=""
restarted
expect_kills 10 "livereduce.py started again with the current files"
echo "# v11" >"${PROC}"
expect_kills 11 "...and is signalled on the next change"
restarted

##################################################################################################
echo "== changes made before the watcher started"
stop_watcher
echo "# v12" >"${PROC}" # after livereduce.py loaded it, before the watcher is watching
start_watcher || fail "watcher restarted"
expect_kills 12 "a script edited before the watcher started sends SIGTERM"
restarted
expect_kills 12 "...and the republished json re-arms it"

##################################################################################################
echo "== default configuration"
stop_watcher
publish "" "${SCRIPTS}" TEST
start_watcher || fail "watcher started with the default configuration"
expect_kills 12 "a null config_file is skipped"
echo "# v13" >"${PROC}"
expect_kills 13 "scripts are still watched"
restarted

##################################################################################################
echo "== published paths change"
echo "# v1" >"${SCRIPTS2}/reduce_PG3_live_proc.py"
publish "${CONF}" "${SCRIPTS2}" PG3
check "watcher exits when the paths change, so it can watch the new ones" wait_for 5 dead "${WATCHER_PID}"
wait "${WATCHER_PID}"
check "watcher exit status is 0" test $? -eq 0
check "inotifywait was stopped with it" wait_for 5 inotifywait_gone
check "no signal for a path change" kills_are 13
WATCHER_PID=""

start_watcher || fail "watcher restarted"
echo "# v14" >"${PROC}"
expect_kills 13 "the old script directory is no longer watched"
echo "# v2" >"${SCRIPTS2}/reduce_PG3_live_proc.py"
expect_kills 14 "the new script directory is watched"

##################################################################################################
echo
check "only SIGTERM was sent" test "$(grep -vc "^SIGTERM$\|^started$" "${SIGNALS}")" -eq 0
if [ "${FAILURES}" -gt 0 ]; then
    echo "${FAILURES} check(s) failed"
    echo "--- watcher output"
    cat "${T}/watcher.out"
    echo "--- watcher log"
    cat "${LIVEREDUCE_FILEWATCH_LOG}"
    echo "--- signals received"
    cat "${SIGNALS}"
    exit 1
fi
echo "all checks passed"
