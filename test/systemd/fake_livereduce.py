"""Stand-in for scripts/livereduce.py with only what livereduce_filewatch.sh relies on: at startup it writes
its pid and the config and script paths, with their sizes and md5s, to /var/lib/livereduce/livereduce_filewatch.json,
as Config.write_md5_json does. SIGTERM (sent by the watcher to that pid) exits cleanly. Each event is logged with the pid
so the test can tell a restart happened."""

import hashlib
import json
import os
import signal
import sys

LOG_FILE = "/var/log/SNS_applications/livereduce.log"
CONFIG_FILE = "/etc/livereduce.conf"
FILEWATCH_JSON = "/var/lib/livereduce/livereduce_filewatch.json"


def log(message):
    with open(LOG_FILE, "a") as handle:
        handle.write(f"{message} pid={os.getpid()}\n")


def md5(filename):
    with open(filename, "rb") as handle:
        return hashlib.md5(handle.read(), usedforsecurity=False).hexdigest()


def publish():
    # the real one resolves the instrument's short name through mantid; the test uses short names
    with open(CONFIG_FILE) as handle:
        config = json.load(handle)
    start = os.path.join(config["script_dir"], f"reduce_{config['instrument']}_live")
    data = {
        "pid": os.getpid(),
        "config_file": CONFIG_FILE,
        "config_size_bytes": os.path.getsize(CONFIG_FILE),
        "config_md5": md5(CONFIG_FILE),
    }
    # as in livereduce.py, a missing script is left out entirely
    for key, filename in (("proc", start + "_proc.py"), ("post_proc", start + "_post_proc.py")):
        if os.path.exists(filename):
            data[f"{key}_script"] = filename
            data[f"{key}_size_bytes"] = os.path.getsize(filename)
            data[f"{key}_md5"] = md5(filename)
    with open(FILEWATCH_JSON + ".tmp", "w") as handle:
        json.dump(data, handle, indent=2)
    os.replace(FILEWATCH_JSON + ".tmp", FILEWATCH_JSON)


def on_term(sig_received, frame):  # noqa: ARG001
    log("SIGTERM")
    sys.exit(0)


signal.signal(signal.SIGTERM, on_term)
publish()
log("started")
while True:
    signal.pause()
