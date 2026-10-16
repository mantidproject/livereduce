#!/bin/bash
# Checks how livereduce_filewatch.service drives livereduce.service under real systemd: a change to the
# config or a processing script restarts livereduce (`systemctl restart` by snsdata, allowed by the polkit
# rule), and every restart of livereduce restarts the watcher too (PartOf=), which then watches what the
# new livereduce.py published.
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
watcher_pid() { main_pid livereduce_filewatch.service; }
logged() { grep -qs "${1}" "${DAEMON_LOG}"; }
not_logged() { ! logged "${1}"; }
watcher_said() { journalctl --unit livereduce_filewatch.service --output cat | grep -qF "${1}"; }
daemon_restarted() {
    local pid
    pid="$(daemon_pid)"
    [ -n "${pid}" ] && [ "${pid}" != "${P1}" ]
}
watcher_restarted() {
    local pid
    pid="$(watcher_pid)"
    [ "${pid}" != 0 ] && [ "${pid}" != "${W1}" ]
}
invocation_id() { systemctl show --property InvocationID --value livereduce.service; }
# the watcher read the json of the current run of livereduce.service, and is watching its files
watching_current() { watcher_said "Watching the files published by livereduce.py (invocation $(invocation_id))"; }
FILEWATCH_LOG="/var/log/SNS_applications/livereduce_filewatch.log"
restart_count() { grep -cs "^restarting livereduce.service$" "${FILEWATCH_LOG}"; }
restarts_are() { [ "$(restart_count)" -eq "${1}" ]; }
inactive() { ! systemctl is-active --quiet "${1}"; }
published_md5() { /bin/jq --raw-output ".${1}_md5" "${FILEWATCH_JSON}"; }
published_current() { # published_current proc|config file
    [ "$(published_md5 "${1}")" = "$(md5sum "${2}" | cut -d' ' -f1)" ]
}
# waits for the watcher to restart livereduce.service, and itself with it, then moves P1 and W1 to the new pids
expect_restart() { # expect_restart "what changed"
    RESTARTS=$((RESTARTS + 1))
    check "${1}: the watcher restarted livereduce.service" wait_for 10 restarts_are "${RESTARTS}"
    check "${1}: livereduce.py received SIGTERM" wait_for 10 logged "SIGTERM pid=${P1}"
    check "${1}: systemd restarted livereduce.py" wait_for 30 daemon_restarted
    P1="$(daemon_pid)"
    check "${1}: the watcher was restarted with it" wait_for 10 watcher_restarted
    check "${1}: the watcher watches what the new livereduce.py published" wait_for 15 watching_current
    W1="$(watcher_pid)"
}

write_config() { # write_config script_dir [update_every] - replace via rename, as editors and config management do
    echo "{\"instrument\": \"TEST\", \"script_dir\": \"${1}\", \"update_every\": ${2:-30}, \"filewatch\": {\"delay\": 1}}" >"${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "${CONFIG_FILE}"
}

###########################################################################
echo "== setup"
mkdir -p "${SCRIPTS_A}" "${SCRIPTS_B}"
echo "# v1" >"${SCRIPTS_A}/${PROC_SCRIPT}"
echo "# v1" >"${SCRIPTS_B}/${PROC_SCRIPT}"
write_config "${SCRIPTS_A}"

# enabled, the watcher is wanted by livereduce.service, so starting livereduce starts it
systemctl enable livereduce_filewatch.service
systemctl start livereduce.service
wait_for 30 logged "started" || {
    fail "livereduce.service started"
    journalctl --unit livereduce.service --no-pager | tail -20
    exit 1
}
P1="$(daemon_pid)"
RESTARTS=0
wait_for 30 watching_current || {
    fail "livereduce_filewatch.service started with livereduce.service"
    journalctl --unit livereduce_filewatch.service --no-pager | tail -20
    exit 1
}
pass "livereduce_filewatch.service started with livereduce.service"
W1="$(watcher_pid)"
check "livereduce.py runs as snsdata" test "$(ps -o user= -p "${P1}")" = snsdata
check "livereduce.py published its invocation id" test "$(/bin/jq -r .invocation_id "${FILEWATCH_JSON}")" = "$(invocation_id)"

###########################################################################
echo "== touching a script without changing it"
touch "${SCRIPTS_A}/${PROC_SCRIPT}"
sleep 3
check "livereduce.py was not killed" not_logged "SIGTERM"

###########################################################################
echo "== editing a script"
echo "# v2" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
expect_restart "script edit"
check "restarted livereduce.py published the new md5" published_current proc "${SCRIPTS_A}/${PROC_SCRIPT}"

###########################################################################
echo "== editing the script again after the restart"
echo "# v3" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
expect_restart "second script edit"

###########################################################################
echo "== changing the configuration without moving the scripts"
write_config "${SCRIPTS_A}" 5
expect_restart "config edit"
check "restarted livereduce.py published the new config md5" published_current config "${CONFIG_FILE}"

###########################################################################
echo "== changing the configuration to point at a different script_dir"
write_config "${SCRIPTS_B}"
expect_restart "config pointing at a new script_dir"

###########################################################################
echo "== editing scripts in the old and new script_dir"
echo "# v4" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
sleep 3
check "old script_dir is no longer watched" not_logged "SIGTERM pid=${P1}"
echo "# v2" >>"${SCRIPTS_B}/${PROC_SCRIPT}"
expect_restart "script edit in the new script_dir"

###########################################################################
echo "== stopping and starting livereduce.service"
systemctl stop livereduce.service
check "stopping livereduce.service stops the watcher" wait_for 10 inactive livereduce_filewatch.service
systemctl start livereduce.service
check "systemd started livereduce.py" wait_for 30 daemon_restarted
P1="$(daemon_pid)"
check "starting livereduce.service starts the watcher" wait_for 15 watching_current

###########################################################################
echo
check "systemctl never refused a restart" test "$(grep -cs "could not restart" "${FILEWATCH_LOG}")" -eq 0

###########################################################################
echo
if [ "${FAILURES}" -gt 0 ]; then
    echo "${FAILURES} check(s) failed"
    echo "--- ${DAEMON_LOG}"
    cat "${DAEMON_LOG}"
    echo "--- /var/log/SNS_applications/livereduce_filewatch.log"
    cat /var/log/SNS_applications/livereduce_filewatch.log
    echo "--- journalctl -u livereduce_filewatch"
    journalctl --unit livereduce_filewatch.service --output cat --no-pager | tail -40
    exit 1
fi
echo "all checks passed"
