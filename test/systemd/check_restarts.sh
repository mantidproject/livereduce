#!/bin/bash
# Checks how livereduce_filewatch.service drives livereduce.service under real systemd.
# Runs as root inside the container built from test/systemd/Dockerfile (see `pixi run test-systemd`).
set -u

DAEMON_LOG="/var/log/SNS_applications/livereduce.log" # written by fake_livereduce.py
CONFIG_FILE="/etc/livereduce.conf"
SCRIPTS_A="/srv/livereduce/scripts_a"
SCRIPTS_B="/srv/livereduce/scripts_b"
PROC_SCRIPT="reduce_TEST_live_proc.py"
# use the watcher's own pattern, so this finds exactly the process it signals
PATTERN="$(sed -n "s/^LIVEREDUCE_PATTERN='\(.*\)'$/\1/p" /usr/bin/livereduce_filewatch.sh)"

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
M1="$(main_pid livereduce.service)"
check "livereduce.py runs as snsdata" test "$(ps -o user= -p "${P1}")" = snsdata
# the reason the watcher signals by pattern rather than through systemd's MainPID
check "livereduce.sh wrapper, not python, is the service's main process" test "${M1}" != "${P1}"

###########################################################################
echo "== touching a script without changing it"
touch "${SCRIPTS_A}/${PROC_SCRIPT}"
sleep 3
check "no SIGHUP sent" not_logged "SIGHUP"

###########################################################################
echo "== editing a script"
echo "# v2" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
check "livereduce.py received SIGHUP" wait_for 10 logged "SIGHUP pid=${P1}"
check "livereduce.py reloaded in place (same pid)" test "$(daemon_pid)" = "${P1}"
check "livereduce.service was not restarted" test "$(main_pid livereduce.service)" = "${M1}"

###########################################################################
echo "== changing the configuration without moving the scripts"
W1="$(main_pid livereduce_filewatch.service)"
write_config "${SCRIPTS_A}" 5
check "livereduce.py received SIGTERM" wait_for 10 logged "SIGTERM pid=${P1}"
check "systemd restarted livereduce.py" wait_for 30 daemon_restarted
check "restarted livereduce.py published its script paths" test -s /run/livereduce/scripts.json
sleep 3
check "watcher kept running, since the script paths are unchanged" test "$(main_pid livereduce_filewatch.service)" = "${W1}"
P1="$(daemon_pid)"

###########################################################################
echo "== changing the configuration to point at a different script_dir"
write_config "${SCRIPTS_B}"
check "livereduce.py received SIGTERM" wait_for 10 logged "SIGTERM pid=${P1}"
check "systemd restarted livereduce.py" wait_for 30 daemon_restarted
# livereduce.py restarts after RestartSec, then the watcher sees the new paths and restarts after another
check "systemd restarted the watcher" wait_for 40 watcher_reloaded
check "watcher now watches the new script_dir" test "$(watcher_journal_count "${SCRIPTS_B}")" -ge 1
check "watcher has a new pid" test "$(main_pid livereduce_filewatch.service)" != "${W1}"
P2="$(daemon_pid)"

###########################################################################
echo "== editing scripts in the old and new script_dir"
echo "# v2" >>"${SCRIPTS_A}/${PROC_SCRIPT}"
sleep 3
check "old script_dir is no longer watched" not_logged "SIGHUP pid=${P2}"
echo "# v2" >>"${SCRIPTS_B}/${PROC_SCRIPT}"
check "new script_dir triggers SIGHUP" wait_for 10 logged "SIGHUP pid=${P2}"

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
