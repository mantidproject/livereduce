#!/bin/bash
# Checks how livereduce_filewatch.service drives livereduce.service under real systemd: a change to the
# config or a processing script restarts livereduce (SIGTERM to the pid it published, then Restart=always), and a change
# of the published paths restarts the watcher too.
# Runs as root inside the container built from the root Dockerfile (see `pixi run test-systemd`).
set -u

DAEMON_LOG="/var/log/SNS_applications/livereduce.log" # written by fake_livereduce.py
CONFIG_FILE="/etc/livereduce.conf"
SCRIPTS_A="/srv/livereduce/scripts_a"
SCRIPTS_B="/srv/livereduce/scripts_b"
PROC_SCRIPT="reduce_TEST_live_proc.py"
FILEWATCH_JSON="/var/lib/livereduce/livereduce_filewatch.json" # written by fake_livereduce.py
# only the python process running livereduce.py - not the livereduce.sh wrapper whose command line also mentions it
PATTERN='^[^ ]*python[0-9.]* [^ ]*livereduce\.py( |$)'

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

# poll a condition for up to N seconds - restarts take RestartSec=10 plus startup
wait_for() { # wait_for seconds command...
    local deadline=$((SECONDS + ${1}))
    shift
    until "$@"; do
        [ "${SECONDS}" -ge "${deadline}" ] && return 1
        sleep 0.5
    done
}

daemon_pid() { pgrep -u snsdata -f "${PATTERN}"; }
main_pid() { systemctl show --property MainPID --value "${1}"; }
logged() { grep -qs "${1}" "${DAEMON_LOG}"; }
not_logged() { ! logged "${1}"; }
watcher_journal_count() { journalctl --unit livereduce_filewatch.service --output cat | grep -c "${1}"; }
daemon_restarted() {
    local pid
    pid="$(daemon_pid)"
    [ -n "${pid}" ] && [ "${pid}" != "${P1}" ]
}
watcher_started() { [ "$(watcher_journal_count 'Watches established')" -ge 1 ]; }
watcher_reloaded() { [ "$(watcher_journal_count 'Watches established')" -ge 2 ]; }
published_md5() { /bin/jq --raw-output ".${1}_md5" "${FILEWATCH_JSON}"; }
published_current() { # published_current proc|config file
    [ "$(published_md5 "${1}")" = "$(md5sum "${2}" | cut -d' ' -f1)" ]
}
# waits for livereduce.py to be killed and restarted by systemd, then moves P1 to the new pid
expect_restart() { # expect_restart "what changed"
    check "${1}: livereduce.py received SIGTERM" wait_for 10 logged "SIGTERM pid=${P1}"
    check "${1}: systemd restarted livereduce.py" wait_for 30 daemon_restarted
    P1="$(daemon_pid)"
}

write_config() { # write_config script_dir [update_every] - replace via rename, as editors and config management do
    echo "{\"instrument\": \"TEST\", \"script_dir\": \"${1}\", \"update_every\": ${2:-30}}" >"${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
}

###########################################################################
echo "== setup"
mkdir -p "${SCRIPTS_A}" "${SCRIPTS_B}"
echo "# v1" >"${SCRIPTS_A}/${PROC_SCRIPT}"
echo "# v1" >"${SCRIPTS_B}/${PROC_SCRIPT}"
write_config "${SCRIPTS_A}"

systemctl start livereduce.service livereduce_filewatch.service
wait_for 30 logged "started" || {
    fail "livereduce.service started"
    journalctl --unit livereduce.service --no-pager | tail -20
    exit 1
}
wait_for 30 watcher_started || {
    fail "livereduce_filewatch.service started"
    journalctl --unit livereduce_filewatch.service --no-pager | tail -20
    exit 1
}

P1="$(daemon_pid)"
check "livereduce.py runs as snsdata" test "$(ps -o user= -p "${P1}")" = snsdata
check "livereduce.py published its own pid" test "$(/bin/jq .pid "${FILEWATCH_JSON}")" = "${P1}"

###########################################################################
echo "== touching a script without changing it"
touch "${SCRIPTS_A}/${PROC_SCRIPT}"
sleep 3
check "livereduce.py was not killed" not_logged "SIGTERM"

###########################################################################
echo "== editing a script"
W1="$(main_pid livereduce_filewatch.service)"
echo "# v2" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
expect_restart "script edit"
check "restarted livereduce.py published the new md5" wait_for 10 published_current proc "${SCRIPTS_A}/${PROC_SCRIPT}"
check "watcher kept running, since the paths are unchanged" test "$(main_pid livereduce_filewatch.service)" = "${W1}"

###########################################################################
echo "== editing the script again after the restart"
sleep 3 # let the watcher re-read the json
echo "# v3" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
expect_restart "second script edit"

###########################################################################
echo "== changing the configuration without moving the scripts"
sleep 3
write_config "${SCRIPTS_A}" 5
expect_restart "config edit"
check "restarted livereduce.py published the new config md5" wait_for 10 published_current config "${CONFIG_FILE}"
sleep 3
check "watcher kept running, since the paths are unchanged" test "$(main_pid livereduce_filewatch.service)" = "${W1}"

###########################################################################
echo "== changing the configuration to point at a different script_dir"
write_config "${SCRIPTS_B}"
expect_restart "config pointing at a new script_dir"
# livereduce.py restarts after RestartSec, then the watcher sees the new paths and restarts after another
check "systemd restarted the watcher" wait_for 40 watcher_reloaded
check "watcher has a new pid" test "$(main_pid livereduce_filewatch.service)" != "${W1}"

###########################################################################
echo "== editing scripts in the old and new script_dir"
echo "# v4" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
sleep 3
check "old script_dir is no longer watched" not_logged "SIGTERM pid=${P1}"
echo "# v2" >>"${SCRIPTS_B}/${PROC_SCRIPT}"
expect_restart "script edit in the new script_dir"

###########################################################################
echo
if [ "${FAILURES}" -gt 0 ]; then
    echo "${FAILURES} check(s) failed"
    echo "--- ${DAEMON_LOG}"
    cat "${DAEMON_LOG}"
    echo "--- /var/log/SNS_applications/livereduce_filewatch.log"
    cat /var/log/SNS_applications/livereduce_filewatch.log
    exit 1
fi
echo "all checks passed"
