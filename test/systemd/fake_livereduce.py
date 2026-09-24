"""Stand-in for scripts/livereduce.py with only what livereduce_filewatch.sh relies on: it publishes
the config and script paths, with md5s, to /run/livereduce/scripts.json, SIGHUP reloads in place, and SIGTERM
exits cleanly. Each event is logged with the pid so the test can tell an in-place reload from a restart."""

import hashlib
import json
import os
import signal
import sys

LOG_FILE = "/var/log/SNS_applications/livereduce.log"
CONFIG_FILE = "/etc/livereduce.conf"
SCRIPTS_FILE = "/run/livereduce/scripts.json"


def log(message):
    with open(LOG_FILE, "a") as handle:
        handle.write(f"{message} pid={os.getpid()}\n")


def md5(filename):  # None for a missing or empty file, as in livereduce.py
    if not os.path.isfile(filename) or os.path.getsize(filename) == 0:
        return None
    with open(filename, "rb") as handle:
        return hashlib.md5(handle.read(), usedforsecurity=False).hexdigest()


def publish():
    # the real one resolves the instrument's short name through mantid; the test uses short names
    with open(CONFIG_FILE) as handle:
        config = json.load(handle)
    start = os.path.join(config["script_dir"], f"reduce_{config['instrument']}_live")
    paths = dict(
        config_file=CONFIG_FILE,
        config_md5=md5(CONFIG_FILE),
        script_dir=config["script_dir"],
        proc_script=start + "_proc.py",
        proc_md5=md5(start + "_proc.py"),
        post_proc_script=start + "_post_proc.py",
        post_proc_md5=md5(start + "_post_proc.py"),
    )
    with open(SCRIPTS_FILE + ".tmp", "w") as handle:
        json.dump(paths, handle)
    os.replace(SCRIPTS_FILE + ".tmp", SCRIPTS_FILE)


def on_hup(sig_received, frame):  # noqa: ARG001
    log("SIGHUP")
    publish()


def on_term(sig_received, frame):  # noqa: ARG001
    log("SIGTERM")
    sys.exit(0)


signal.signal(signal.SIGHUP, on_hup)
signal.signal(signal.SIGTERM, on_term)
publish()
log("started")
while True:
    signal.pause()
