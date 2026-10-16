#!/bin/bash
# Tests scripts/livereduce_filewatch.sh on its own - no systemd, mantid, or real livereduce needed.
# A stand-in systemctl records the restarts the watcher asks for, and reports the invocation id of
# the current run of livereduce.service. publish() writes the json that livereduce.py would, for that
# run. Only the watcher's log path is changed.
#
# usage: pixi run test-filewatch (or test/test_filewatch.sh)
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="${REPO}/scripts/livereduce_filewatch.sh"

# inotifywait may only be available from the pixi environment
if ! command -v inotifywait &>/dev/null && [ -x "${REPO}/.pixi/envs/default/bin/inotifywait" ]; then
    PATH="${REPO}/.pixi/envs/default/bin:${PATH}"
fi
for tool in inotifywait jq md5sum stat; do
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
RESTARTS="${T}/restarts.log"                          # written by the stand-in systemctl
mkdir -p "${T}/etc" "${SCRIPTS}" "${SCRIPTS2}" "${T}/state" "${T}/bin"

# livereduce.service is active while ${T}/active exists, its current invocation id is in
# ${T}/invocation, and restarts are refused while ${T}/refuse exists
cat >"${T}/bin/systemctl" <<SYSTEMCTL
#!/bin/bash
case " \$* " in
    *" is-active "*) [ -e "${T}/active" ] ;;
    *" show "*) cat "${T}/invocation" ;;
    *" restart "*)
        if [ -e "${T}/refuse" ]; then
            echo "Access denied" >&2
            exit 1
        fi
        echo "\$*" >>"${RESTARTS}"
        ;;
    *)
        echo "unexpected: systemctl \$*" >&2
        exit 1
        ;;
esac
SYSTEMCTL
chmod +x "${T}/bin/systemctl"
PATH="${T}/bin:${PATH}"

WATCHER_PID=""
cleanup() {
    [ -n "${WATCHER_PID}" ] && pkill -P "${WATCHER_PID}" 2>/dev/null
    [ -n "${WATCHER_PID}" ] && kill "${WATCHER_PID}" 2>/dev/null
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

restarts() { cat "${RESTARTS}" 2>/dev/null | wc -l; }
restarts_are() { [ "$(restarts)" -eq "${1}" ]; }
alive() { kill -0 "${1}" 2>/dev/null; }
dead() { ! alive "${1}"; }
inotifywait_gone() { ! pgrep -f "inotifywait .*${T}" >/dev/null; }
logged() { grep -qF "${1}" "${LIVEREDUCE_FILEWATCH_LOG}"; }

# waits for N more restarts than expected so far, then makes sure no extra one follows, after the
# watcher's quiet period (filewatch.delay, 1 s in CONF) has passed
EXPECTED=0
expect_restarts() { # expect_restarts +N "description"
    EXPECTED=$((EXPECTED + ${1#+}))
    wait_for 10 restarts_are "${EXPECTED}" && sleep 2
    check "${2} (restarts: $(restarts), expected ${EXPECTED})" restarts_are "${EXPECTED}"
}

replace() { # replace file content - via rename, as editors and config management do
    echo "${2}" >"${1}.tmp"
    mv "${1}.tmp" "${1}"
}

# systemd starts a new run of livereduce.service, with a new invocation id
new_run() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' >"${T}/invocation"
    touch "${T}/active"
}

# what livereduce.py's Config.write_md5_json writes, also via rename: the invocation id of the current
# run, and each file's path, size and md5 as it is now, standing in for what livereduce.py loaded.
# A missing script is left out entirely, and config_file is null for the default configuration (publish "" ...)
publish() { # publish config script_dir instrument
    local proc="${2}/reduce_${3}_live_proc.py" post="${2}/reduce_${3}_live_post_proc.py"
    {
        jq -n --arg id "$(cat "${T}/invocation")" '{invocation_id: $id}'
        if [ -n "${1}" ]; then
            jq -n --arg f "${1}" --argjson s "$(stat -L -c%s "${1}")" --arg m "$(md5sum "${1}" | cut -d' ' -f1)" \
                '{config_file: $f, config_size_bytes: $s, config_md5: $m}'
        else
            jq -n '{config_file: null, config_size_bytes: null, config_md5: null}'
        fi
        [ -e "${proc}" ] && jq -n --arg f "${proc}" --argjson s "$(stat -L -c%s "${proc}")" \
            --arg m "$(md5sum "${proc}" | cut -d' ' -f1)" '{proc_script: $f, proc_size_bytes: $s, proc_md5: $m}'
        [ -e "${post}" ] && jq -n --arg f "${post}" --argjson s "$(stat -L -c%s "${post}")" \
            --arg m "$(md5sum "${post}" | cut -d' ' -f1)" \
            '{post_proc_script: $f, post_proc_size_bytes: $s, post_proc_md5: $m}'
    } | jq -s add >"${LIVEREDUCE_FILEWATCH_JSON}.tmp"
    mv "${LIVEREDUCE_FILEWATCH_JSON}.tmp" "${LIVEREDUCE_FILEWATCH_JSON}"
}

watcher_said() { grep -q "${1}" "${T}/watcher.out"; }
watching() { watcher_said "Watches established"; }
not_watching() { ! watching; }
launch_watcher() {
    bash "${WATCHER}" >"${T}/watcher.out" 2>&1 &
    WATCHER_PID=$!
}
start_watcher() {
    launch_watcher
    wait_for 5 watching
}
stop_watcher() {
    pkill -P "${WATCHER_PID}" 2>/dev/null
    kill "${WATCHER_PID}" 2>/dev/null
    wait "${WATCHER_PID}" 2>/dev/null
    WATCHER_PID=""
    wait_for 5 inotifywait_gone
}

# livereduce.service restarted - asked for by the watcher, or for some other reason - and the watcher
# restarted with it (PartOf=), before the new livereduce.py has published what it loaded - so the
# watcher first sees the json of the previous run
restarted() { # restarted [config script_dir instrument]
    stop_watcher
    new_run
    launch_watcher
    sleep 0.5
    publish "${1:-${CONF}}" "${2:-${SCRIPTS}}" "${3:-TEST}"
    wait_for 5 watching || fail "watcher started after the restart"
}

##################################################################################################
echo "== startup"
output="$(LIVEREDUCE_FILEWATCH_LOG="${T}/nope/filewatch.log" bash "${WATCHER}" 2>&1)"
check "unwritable log file is rejected" test $? -ne 0 -a -n "$(grep -F "Cannot write to log file" <<<"${output}")"

new_run
launch_watcher
sleep 1
check "the watcher waits for a missing json" watcher_said "Waiting for livereduce.py"
check "...without watching yet" not_watching

echo '{"instrument": "TEST", "filewatch": {"delay": 1}}' >"${CONF}"
echo "# v1" >"${PROC}"
publish "${CONF}" "${SCRIPTS}" TEST
wait_for 5 watching || {
    echo "ERROR: watcher did not start:" >&2
    cat "${T}/watcher.out" >&2
    exit 1
}
pass "watcher starts once livereduce.py publishes the json"
check "...for the current run" watcher_said "invocation $(cat "${T}/invocation")"
check "...with the delay from the config" watcher_said "quiet for 1 s"
expect_restarts +0 "nothing is restarted when the files match the json"
check "the absent post-processing script is skipped" watcher_said "Skipping check for null"

##################################################################################################
echo "== processing script changes"
touch "${PROC}"
expect_restarts +0 "touch without a content change is ignored"

echo "# v1" >"${PROC}"
expect_restarts +0 "rewriting identical content is ignored"

echo "# v2" >"${PROC}"
expect_restarts +1 "editing the script restarts livereduce.service"
check "...without waiting for the restart, which stops the watcher too" \
    test "$(tail -n 1 "${RESTARTS}")" = "restart --no-block livereduce.service"
check "...the reason is logged" logged "MD5 sum changed for ${PROC}"
check "...with the restart" logged "restarting livereduce.service"

echo "# v3" >"${PROC}"
expect_restarts +0 "edits while livereduce restarts are ignored"

restarted
expect_restarts +0 "the restarted watcher waits for the republished json, which matches, so nothing is restarted"

echo "# v4" >"${PROC}"
expect_restarts +1 "the restarted watcher restarts livereduce.service again"
restarted

echo "# v6" >"${PROC}"
sleep 1
echo "# v66" >"${PROC}"
expect_restarts +1 "a script edit with the same size is caught by its md5"
restarted

echo "# v7" >"${SCRIPTS}/.tmp" && mv "${SCRIPTS}/.tmp" "${PROC}"
expect_restarts +1 "renaming a new file over the script restarts livereduce.service"
restarted

# vim's default: rename the original to a backup, then write a new file
mv "${PROC}" "${PROC}~" && sleep 0.3 && echo "# v8" >"${PROC}"
expect_restarts +1 "a save that renames the old file away first restarts once"
restarted

# git checkout: delete, then write
rm "${PROC}" && sleep 0.3 && echo "# v9" >"${PROC}"
expect_restarts +1 "a save that deletes the old file first restarts once"
restarted

echo "x" >"${SCRIPTS}/unrelated.py"
expect_restarts +0 "unrelated file in the script directory is ignored"

# livereduce only notices a new script when restarted, and the watcher restarted with it watches it
echo "# post v1" >"${POST_PROC}"
restarted # stands in for a restart for some other reason
expect_restarts +0 "the restarted watcher accepts the json with the new script"

echo "# post v2" >>"${POST_PROC}"
expect_restarts +1 "editing the post-processing script restarts livereduce.service"
restarted

rm "${POST_PROC}"
expect_restarts +1 "deleting the post-processing script restarts livereduce.service"
restarted

##################################################################################################
echo "== configuration changes"
touch "${CONF}"
echo "x" >"${T}/etc/unrelated.conf"
expect_restarts +0 "touching the config or editing a neighbour is ignored"

replace "${CONF}" '{"instrument": "TEST", "update_every": 5, "filewatch": {"delay": 1}}'
expect_restarts +1 "changing the config restarts livereduce.service"
restarted

##################################################################################################
echo "== changes close together"
replace "${CONF}" '{"instrument": "TEST", "update_every": 5, "filewatch": {"delay": 3}}'
expect_restarts +1 "changing the delay restarts livereduce.service"
restarted
check "the restarted watcher uses the new delay" watcher_said "quiet for 3 s"
entries="$(grep -c "^restarting livereduce.service$" "${LIVEREDUCE_FILEWATCH_LOG}")"
echo "# v10a" >"${PROC}"
sleep 2
echo "# v10b" >"${PROC}"
sleep 2
replace "${CONF}" '{"instrument": "TEST", "update_every": 4, "filewatch": {"delay": 3}}'
sleep 2
check "saves less than the delay apart keep postponing the restart" restarts_are "${EXPECTED}"
expect_restarts +1 "...then restart livereduce.service once"
check "...logging every file that changed" \
    test "$(tail -n 4 "${LIVEREDUCE_FILEWATCH_LOG}" | grep -c "changed for ${PROC}\|changed for ${CONF}")" -eq 2
check "...in one entry" test "$(grep -c "^restarting livereduce.service$" "${LIVEREDUCE_FILEWATCH_LOG}")" -eq $((entries + 1))
restarted

echo "# v10c" >"${PROC}"
sleep 1
echo "# v10b" >"${PROC}" # what livereduce.py loaded
expect_restarts +0 "an edit undone within the delay doesn't restart livereduce.service"
sleep 2

replace "${CONF}" '{"instrument": "TEST", "update_every": 4, "filewatch": {"delay": "soon"}}'
expect_restarts +1 "changing the delay to an invalid value restarts livereduce.service"
restarted
check "the restarted watcher warns about the invalid delay" watcher_said "Invalid filewatch.delay value 'soon'"
check "...and uses the default" watcher_said "quiet for 5 s"
replace "${CONF}" '{"instrument": "TEST", "update_every": 5, "filewatch": {"delay": 1}}'
expect_restarts +1 "...after which a change restarts livereduce.service"
restarted

##################################################################################################
echo "== systemctl refuses the restart"
touch "${T}/refuse"
echo "# v10" >"${PROC}"
expect_restarts +0 "a refused restart isn't counted"
check "...the reason is logged" logged "could not restart livereduce.service: Access denied"
check "the watcher keeps running" alive "${WATCHER_PID}"
rm "${T}/refuse"
echo "# v11" >"${PROC}"
expect_restarts +1 "...and restarts livereduce.service on the next change"
restarted

##################################################################################################
echo "== json not from the current run"
# livereduce.service isn't active, e.g. the watcher was started on its own
stop_watcher
rm "${T}/active"
launch_watcher
sleep 2
check "the watcher waits while livereduce.service isn't active" not_watching
touch "${T}/active"
check "...and starts once it is" wait_for 5 watching

# a new run that hasn't published yet
stop_watcher
new_run
echo "# v12" >"${PROC}" # changed since the previous run published, but that run is gone
launch_watcher
sleep 2
check "the watcher waits while the json is from the previous run" not_watching
publish "${CONF}" "${SCRIPTS}" TEST
check "...and starts once the current run publishes" wait_for 5 watching
expect_restarts +0 "...with the files it loaded"

##################################################################################################
echo "== changes made before the watcher started"
stop_watcher
echo "# v13" >"${PROC}" # after livereduce.py loaded it, before the watcher is watching
start_watcher || fail "watcher restarted"
expect_restarts +1 "a script edited before the watcher started restarts livereduce.service"
restarted
expect_restarts +0 "...and the restarted watcher matches the republished json"

##################################################################################################
echo "== default configuration"
stop_watcher
publish "" "${SCRIPTS}" TEST
start_watcher || fail "watcher started with the default configuration"
expect_restarts +0 "a null config_file is skipped"
check "...and the default delay is used" watcher_said "quiet for 5 s"
echo "# v14" >"${PROC}"
sleep 3
check "scripts are still watched, but the default delay of 5 s is waited" restarts_are "${EXPECTED}"
expect_restarts +1 "...before restarting livereduce.service"
restarted

##################################################################################################
echo "== symlinked files"
# config management often links the published path to a file kept elsewhere
stop_watcher
mkdir -p "${T}/managed"
mv "${CONF}" "${T}/managed/livereduce.conf"
ln -s "${T}/managed/livereduce.conf" "${CONF}"
mv "${PROC}" "${T}/managed/proc.py"
ln -s "${T}/managed/proc.py" "${PROC}"
publish "${CONF}" "${SCRIPTS}" TEST
start_watcher || fail "watcher started with symlinked files"
expect_restarts +0 "a symlinked file matching the json is not mistaken for a change"
echo "x" >"${T}/managed/unrelated.py"
expect_restarts +0 "an unrelated file next to a symlink target is ignored"
echo "# v15" >"${T}/managed/proc.py"
expect_restarts +1 "editing the file a script symlink points to restarts livereduce.service"
check "...the published path is logged" logged "MD5 sum changed for ${PROC}"
restarted
replace "${T}/managed/livereduce.conf" '{"instrument": "TEST", "update_every": 6, "filewatch": {"delay": 1}}'
expect_restarts +1 "renaming a new file over the config symlink target restarts livereduce.service"
restarted
echo "# v16" >"${T}/managed/proc2.py"
ln -sfn "${T}/managed/proc2.py" "${PROC}"
expect_restarts +1 "pointing the script symlink at another file restarts livereduce.service"
restarted
echo "# v17" >"${T}/managed/proc2.py"
expect_restarts +1 "the restarted watcher watches the new symlink target"
restarted

##################################################################################################
echo "== published paths change"
echo "# v1" >"${SCRIPTS2}/reduce_PG3_live_proc.py"
restarted "${CONF}" "${SCRIPTS2}" PG3 # e.g. a new script_dir, applied by a restart
expect_restarts +0 "no restart when the restarted livereduce.py publishes new paths"
echo "# v18" >"${PROC}"
expect_restarts +0 "the old script directory is no longer watched"
echo "# v2" >"${SCRIPTS2}/reduce_PG3_live_proc.py"
expect_restarts +1 "the new script directory is watched"

##################################################################################################
echo "== stopped by systemd"
kill -TERM "${WATCHER_PID}"
check "the watcher exits on SIGTERM" wait_for 5 dead "${WATCHER_PID}"
check "...and inotifywait was stopped with it" wait_for 5 inotifywait_gone
WATCHER_PID=""

##################################################################################################
echo
check "every restart was of livereduce.service, without blocking" \
    test "$(grep -vcx "restart --no-block livereduce.service" "${RESTARTS}")" -eq 0
if [ "${FAILURES}" -gt 0 ]; then
    echo "${FAILURES} check(s) failed"
    echo "--- watcher output"
    cat "${T}/watcher.out"
    echo "--- watcher log"
    cat "${LIVEREDUCE_FILEWATCH_LOG}"
    echo "--- restarts"
    cat "${RESTARTS}"
    exit 1
fi
echo "all checks passed"
