#!/bin/bash
# Tests scripts/livereduce_filewatch.sh on its own - no systemd, mantid, or real livereduce needed.
# A stand-in livereduce.py records the signals the watcher sends it. Only the watcher's log path
# is changed (to a temp dir); everything else runs as written.
#
# usage: pixi run test-filewatch (or test/test-filewatch.sh)
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER_SRC="${REPO}/scripts/livereduce_filewatch.sh"

# inotifywait may only be available from the pixi environment
if ! command -v inotifywait &>/dev/null && [ -x "${REPO}/.pixi/envs/default/bin/inotifywait" ]; then
    PATH="${REPO}/.pixi/envs/default/bin:${PATH}"
fi
for tool in inotifywait /bin/jq python3 pkill md5sum; do
    command -v "${tool}" &>/dev/null || {
        echo "ERROR: '${tool}' is required" >&2
        exit 1
    }
done

# the watcher's own pattern, so this matches exactly what it signals
PATTERN="$(sed -n "s/^LIVEREDUCE_PATTERN='\(.*\)'$/\1/p" "${WATCHER_SRC}")"
if pgrep -u "$(id -u)" -f "${PATTERN}" &>/dev/null; then
    echo "ERROR: a livereduce.py is already running as $(id -un) - this test would signal it" >&2
    exit 1
fi

##################################################################################################
# scratch area
T="$(mktemp -d)"
WATCHER="${T}/livereduce_filewatch.sh"
CONF="${T}/etc/livereduce.conf"
SCRIPTS="${T}/scripts"
PROC="${SCRIPTS}/reduce_TEST_live_proc.py"
POST_PROC="${SCRIPTS}/reduce_TEST_live_post_proc.py"
SCRIPTS2="${T}/scripts2"
# normally published by livereduce.py; written here by publish() instead
export LIVEREDUCE_SCRIPTS_FILE="${T}/run/scripts.json"
SIGNALS="${T}/signals.log"         # written by the stand-in livereduce.py
FILEWATCH_LOG="${T}/filewatch.log" # written by the watcher
mkdir -p "${T}/etc" "${SCRIPTS}" "${SCRIPTS2}" "${T}/bin" "${T}/run"

sed "s#/var/log/SNS_applications/livereduce_filewatch.log#${FILEWATCH_LOG}#" "${WATCHER_SRC}" >"${WATCHER}"

# records each signal; on HUP also whether the processing script (argv[2]) was there to reload
cat >"${T}/bin/livereduce.py" <<'EOF'
import os, signal, sys

def record(message):
    with open(sys.argv[1], "a") as handle:
        handle.write(message + "\n")

def on_hup(sig, frame):
    record("HUP")
    if not os.path.exists(sys.argv[2]):
        record("MISSING")

def on_term(sig, frame):
    record("TERM")
    sys.exit(0)

signal.signal(signal.SIGHUP, on_hup)
signal.signal(signal.SIGTERM, on_term)
record("started")
while True:
    signal.pause()
EOF

WATCHER_PID=""
WRAPPER_PID=""
cleanup() {
    [ -n "${WATCHER_PID}" ] && kill "${WATCHER_PID}" 2>/dev/null
    [ -n "${WRAPPER_PID}" ] && pkill -P "${WRAPPER_PID}" 2>/dev/null
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

count() { cat "${SIGNALS}" 2>/dev/null | grep -c "^${1}$"; }
count_is() { [ "$(count "${1}")" -eq "${2}" ]; }
alive() { kill -0 "${1}" 2>/dev/null; }
dead() { ! alive "${1}"; }
inotifywait_gone() { ! pgrep -f "inotifywait .*${T}" >/dev/null; }
fake_pid() { pgrep -u "$(id -u)" -f "${PATTERN}"; }

# waits for the HUP count to reach N, then makes sure no extra one follows
expect_hups() { # expect_hups N "description"
    wait_for 5 count_is HUP "${1}" && sleep 1 && count_is HUP "${1}"
    check "${2} (HUPs: $(count HUP), expected ${1})" count_is HUP "${1}"
}

write_config() { # write_config json - replaced via rename, as editors and config management do
    echo "${1}" >"${CONF}.tmp"
    mv "${CONF}.tmp" "${CONF}"
}

# what livereduce.py's Config.__publishScriptPaths writes, also via rename: the paths, plus the md5 of
# each file as it is now, standing in for what livereduce.py loaded (null if missing or empty)
md5_of() { [ -s "${1}" ] && md5sum "${1}" | cut -d' ' -f1; }
publish() { # publish script_dir instrument
    local proc="${1}/reduce_${2}_live_proc.py" post="${1}/reduce_${2}_live_post_proc.py"
    /bin/jq -n --arg config "${CONF}" --arg config_md5 "$(md5_of "${CONF}")" --arg dir "${1}" \
        --arg proc "${proc}" --arg proc_md5 "$(md5_of "${proc}")" \
        --arg post "${post}" --arg post_md5 "$(md5_of "${post}")" \
        'def n: if . == "" then null else . end;
         {config_file: $config, config_md5: ($config_md5 | n), script_dir: $dir,
          proc_script: $proc, proc_md5: ($proc_md5 | n), post_proc_script: $post, post_proc_md5: ($post_md5 | n)}' \
        >"${LIVEREDUCE_SCRIPTS_FILE}.tmp"
    mv "${LIVEREDUCE_SCRIPTS_FILE}.tmp" "${LIVEREDUCE_SCRIPTS_FILE}"
}

# runs from ${T} with a relative config path, which the watcher must resolve itself
launch_watcher() {
    (cd "${T}" && exec bash "${WATCHER}" etc/livereduce.conf) >"${T}/watcher.out" 2>&1 &
    WATCHER_PID=$!
}
watching() { grep -q "Watches established" "${T}/watcher.out"; }
start_watcher() {
    launch_watcher
    wait_for 5 watching
}

# the stand-in runs under a bash wrapper whose command line also mentions livereduce.py, like
# livereduce.sh and pixi do in production - the wrapper must not be signalled
start_fake_livereduce() {
    bash -c "python3 '${T}/bin/livereduce.py' '${SIGNALS}' '${PROC}'; true" &
    WRAPPER_PID=$!
    wait_for 5 count_is started 1
}

# runs the watcher expecting it to refuse to start
expect_startup_error() { # expect_startup_error "description" "expected message" config-arg [scripts-file]
    local output rc
    output="$(LIVEREDUCE_SCRIPTS_FILE="${4:-${LIVEREDUCE_SCRIPTS_FILE}}" bash "${WATCHER}" "${3}" 2>&1)"
    rc=$?
    check "${1}" test "${rc}" -ne 0 -a -n "$(grep -F "${2}" <<<"${output}")"
}

##################################################################################################
echo "== startup validation"
echo '{}' >"${CONF}"
expect_startup_error "config file in a missing directory is rejected" "does not exist" "${T}/nope/livereduce.conf"
expect_startup_error "missing directory for the published paths is rejected" "has livereduce.service been started" \
    "${CONF}" "${T}/nope/scripts.json"
echo '{"script_dir": "'"${SCRIPTS}"'",' >"${LIVEREDUCE_SCRIPTS_FILE}"
expect_startup_error "invalid published paths are rejected" "not valid JSON" "${CONF}"
echo '{"script_dir": "'"${SCRIPTS}"'", "proc_script": "'"${PROC}"'"}' >"${LIVEREDUCE_SCRIPTS_FILE}"
expect_startup_error "published paths missing a script are rejected" "missing a script path" "${CONF}"
publish "${T}/missing" TEST
expect_startup_error "missing script_dir is rejected" "does not exist" "${CONF}"
sed "s#${FILEWATCH_LOG}#${T}/nope/filewatch.log#" "${WATCHER}" >"${T}/watcher_badlog.sh"
output="$(bash "${T}/watcher_badlog.sh" "${CONF}" 2>&1)"
check "unwritable log file is rejected" test $? -ne 0 -a -n "$(grep -F "Cannot write to log file" <<<"${output}")"

##################################################################################################
echo "== waiting for livereduce.py to publish the script paths"
rm "${LIVEREDUCE_SCRIPTS_FILE}"
echo "# v1" >"${PROC}"
start_fake_livereduce || {
    echo "ERROR: stand-in livereduce.py did not start" >&2
    exit 1
}
launch_watcher
check "watcher waits for the published paths" wait_for 5 grep -q "Waiting for livereduce.py" "${T}/watcher.out"
sleep 1
check "watcher still running while waiting" alive "${WATCHER_PID}"
publish "${SCRIPTS}" TEST
wait_for 5 watching || {
    echo "ERROR: watcher did not start:" >&2
    cat "${T}/watcher.out" >&2
    exit 1
}
pass "watcher starts once the paths are published"
check "watcher uses the published script names" grep -q "reduce_TEST_live_proc.py" "${T}/watcher.out"

##################################################################################################
echo "== processing script changes"
FAKE_PID="$(fake_pid)"

touch "${PROC}"
expect_hups 0 "touch without a content change is ignored"

echo "# v2" >"${PROC}"
expect_hups 1 "editing the script sends HUP"
check "livereduce.py reloaded in place (same pid)" test "$(fake_pid)" = "${FAKE_PID}"
check "wrapper process was not signalled" alive "${WRAPPER_PID}"

echo "# v2" >"${PROC}"
expect_hups 1 "rewriting identical content is ignored"

{
    echo "# v3"
    sleep 0.2
    echo "# more"
} >"${PROC}"
expect_hups 2 "a save made of several writes sends one HUP"

echo "# v4" >"${SCRIPTS}/.tmp" && mv "${SCRIPTS}/.tmp" "${PROC}"
expect_hups 3 "renaming a new file over the script sends HUP"

# vim's default: rename the original to a backup, then write a new file
mv "${PROC}" "${PROC}~" && sleep 0.3 && echo "# v5" >"${PROC}"
expect_hups 4 "a save that renames the old file away first sends one HUP"
# git checkout: delete, then write
rm "${PROC}" && sleep 0.3 && echo "# v6" >"${PROC}"
expect_hups 5 "a save that deletes the old file first sends one HUP"
check "the script was back in place for every reload" count_is MISSING 0

echo "# post v1" >"${POST_PROC}"
expect_hups 6 "creating the post-processing script sends HUP"

echo "x" >"${SCRIPTS}/unrelated.py"
expect_hups 6 "unrelated file in script_dir is ignored"

rm "${POST_PROC}"
expect_hups 7 "deleting the post-processing script sends HUP"

# root can write it regardless, so this can only be checked as another user
if [ "$(id -u)" -ne 0 ]; then
    chmod 000 "${FILEWATCH_LOG}"
    echo "# v8" >"${PROC}"
    expect_hups 8 "a log file that can't be written doesn't stop the HUP"
    check "...and the failure is reported" grep -q "could not write to ${FILEWATCH_LOG}" "${T}/watcher.out"
    chmod 644 "${FILEWATCH_LOG}"
else
    echo "# v8" >"${PROC}"
    expect_hups 8 "script edit sends HUP (unwritable log not checked as root)"
fi

##################################################################################################
echo "== configuration changes"
touch "${CONF}"
echo "x" >"${T}/etc/unrelated.conf"
sleep 1
check "touching the config or editing a neighbour sends nothing" count_is TERM 0
check "watcher still running" alive "${WATCHER_PID}"

write_config '{"instrument": "TEST", "script_dir": "'"${SCRIPTS}"'", "update_every": 5}'
check "changing the config sends TERM" wait_for 5 count_is TERM 1
sleep 1
check "watcher keeps running when the script paths don't change" alive "${WATCHER_PID}"

##################################################################################################
echo "== published script paths"
publish "${SCRIPTS}" TEST
sleep 1
check "republishing the same paths is ignored" alive "${WATCHER_PID}"

publish "${SCRIPTS2}" PG3
check "watcher exits when the paths change, so it can reload them" wait_for 5 dead "${WATCHER_PID}"
wait "${WATCHER_PID}"
check "watcher exit status is 0" test $? -eq 0
check "inotifywait was stopped with it" wait_for 5 inotifywait_gone
check "no signal sent for a path change" test "$(count HUP)" -eq 8 -a "$(count TERM)" -eq 1
WATCHER_PID=""

##################################################################################################
echo "== livereduce not running"
wait "${WRAPPER_PID}" 2>/dev/null # the stand-in exited on TERM
WRAPPER_PID=""
start_watcher || fail "watcher restarted"
check "restarted watcher uses the new paths" grep -q "reduce_PG3_live_proc.py" "${T}/watcher.out"
echo "# v1" >"${SCRIPTS2}/reduce_PG3_live_proc.py"
check "script change is logged as nothing to signal" wait_for 5 grep -q "not running, no SIGHUP sent" "${FILEWATCH_LOG}"
check "watcher keeps running" alive "${WATCHER_PID}"

##################################################################################################
echo "== changes made before the watcher started"
kill "${WATCHER_PID}" && wait "${WATCHER_PID}" 2>/dev/null
WATCHER_PID=""
rm -f "${SIGNALS}"
start_fake_livereduce || fail "stand-in livereduce.py restarted"
publish "${SCRIPTS}" TEST
echo "# v7" >"${PROC}" # after livereduce.py loaded it, before the watcher is watching
start_watcher || fail "watcher restarted"
expect_hups 1 "a script edited before the watcher started sends HUP"

kill "${WATCHER_PID}" && wait "${WATCHER_PID}" 2>/dev/null
publish "${SCRIPTS}" TEST
write_config '{"instrument": "TEST", "script_dir": "'"${SCRIPTS}"'", "update_every": 7}'
start_watcher || fail "watcher restarted"
check "a config edited before the watcher started sends TERM" wait_for 5 count_is TERM 1
check "...and no HUP on top" count_is HUP 1

##################################################################################################
echo "== symlinks"
kill "${WATCHER_PID}" && wait "${WATCHER_PID}" 2>/dev/null
wait "${WRAPPER_PID}" 2>/dev/null
rm -f "${SIGNALS}"
start_fake_livereduce || fail "stand-in livereduce.py restarted"
STORE="${T}/store"
mkdir -p "${STORE}"
echo '{"a": 1}' >"${STORE}/a.conf"
echo '{"b": 1}' >"${STORE}/b.conf"
cp "${STORE}/b.conf" "${STORE}/b_copy.conf"
echo "# real v1" >"${STORE}/proc.py"
ln -sfn "${STORE}/a.conf" "${CONF}"
ln -sfn "${STORE}/proc.py" "${PROC}"
publish "${SCRIPTS}" TEST
start_watcher || fail "watcher started with symlinks"
check "watcher shows where the links point" grep -q -- "-> ${STORE}/a.conf" "${T}/watcher.out"
expect_hups 0 "no signal at startup"

echo "# real v2" >>"${STORE}/proc.py"
expect_hups 1 "editing a symlinked script's target sends HUP"

config_changes() { grep -c "Configuration file" "${FILEWATCH_LOG}"; }
config_changed_since() { [ "$(config_changes)" -gt "${1}" ]; }
BEFORE="$(config_changes)"
echo '{"a": 2}' >"${STORE}/a.conf"
check "editing a symlinked config's target sends TERM" wait_for 5 count_is TERM 1
check "watcher keeps running when a link's target is edited" alive "${WATCHER_PID}"

BEFORE="$(config_changes)"
ln -sfn "${STORE}/b.conf" "${CONF}"
check "repointing the config link is acted on" wait_for 5 config_changed_since "${BEFORE}"
check "watcher exits to watch the new target" wait_for 5 dead "${WATCHER_PID}"

publish "${SCRIPTS}" TEST
start_watcher || fail "watcher restarted"
BEFORE="$(config_changes)"
ln -sfn "${STORE}/b_copy.conf" "${CONF}"
check "repointing to identical content: watcher exits to watch the new target" wait_for 5 dead "${WATCHER_PID}"
check "...but sends nothing" test "$(config_changes)" -eq "${BEFORE}"
WATCHER_PID=""

##################################################################################################
echo
if [ "${FAILURES}" -gt 0 ]; then
    echo "${FAILURES} check(s) failed"
    echo "--- watcher output"
    cat "${T}/watcher.out"
    echo "--- watcher log"
    cat "${FILEWATCH_LOG}"
    exit 1
fi
echo "all checks passed"
