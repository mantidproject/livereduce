"""Exercise ``Config.refresh_scripts()`` from scripts/livereduce.py.

livereduce.py is a daemon script that starts live data as soon as it is imported,
so only the definitions above its main section are executed here.

The config files, script copies and log live in a temporary directory; only the md5 json
written by ``refresh_scripts()`` is kept, in test/output, for inspection.

Run with ``pixi run python test/test_config.py`` or with pytest.
"""

import functools
import json
import os
import shutil
import signal
import tempfile
from pathlib import Path

REPO_DIR = Path(__file__).resolve().parent.parent
SCRIPT = REPO_DIR / "scripts" / "livereduce.py"
OUTPUT_DIR = Path(__file__).resolve().parent / "output"
WORK_DIR = tempfile.TemporaryDirectory(prefix="livereduce-test-")  # removed when the interpreter exits
FILEWATCH_JSON = Path(WORK_DIR.name) / "livereduce_filewatch.json"
MAIN_MARKER = "# determine the configuration file"

PROC_SCRIPT = REPO_DIR / "test" / "reduce_ISIS_Histogram_live_proc.py"
POST_PROC_SCRIPT = REPO_DIR / "test" / "postprocessing" / "reduce_ISIS_Histogram_live_post_proc.py"


###############
### Helpers ###
###############


@functools.cache
def load_livereduce():
    """Execute livereduce.py up to its main section and return the resulting namespace"""
    source = SCRIPT.read_text()
    source = source[: source.index(MAIN_MARKER)]

    os.environ.setdefault("USER", "livereduce-test")
    os.environ["LIVEREDUCE_FILEWATCH_JSON"] = str(FILEWATCH_JSON)

    namespace = {"__name__": "livereduce", "__file__": str(SCRIPT)}
    cwd = os.getcwd()
    # livereduce.py replaces these with a handler that only queues the signal for its main loop,
    # which would leave the test run unable to be interrupted
    handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGQUIT, signal.SIGTERM)}
    os.chdir(WORK_DIR.name)  # so livereduce.log lands in the temporary directory
    try:
        exec(compile(source, str(SCRIPT), "exec"), namespace)  # noqa: S102 - exec is intentional here
    finally:
        os.chdir(cwd)
        for sig, handler in handlers.items():
            signal.signal(sig, handler)
    return namespace


def make_config(name, scripts):
    """Create a config file whose script_dir holds copies of ``scripts``, and return the Config for it"""
    script_dir = Path(WORK_DIR.name) / name
    script_dir.mkdir()
    for script in scripts:
        shutil.copy(script, script_dir)

    config_file = Path(WORK_DIR.name) / f"{name}.conf"
    config_file.write_text(
        json.dumps({"instrument": "ISIS_Histogram", "script_dir": str(script_dir), "accum_method": "Replace"})
    )
    return load_livereduce()["Config"](str(config_file))


def run_refresh_scripts(config, output_name):
    FILEWATCH_JSON.unlink(missing_ok=True)
    config.refresh_scripts()

    assert FILEWATCH_JSON.exists()
    data = json.loads(FILEWATCH_JSON.read_text())
    OUTPUT_DIR.mkdir(exist_ok=True)
    shutil.copy(FILEWATCH_JSON, OUTPUT_DIR / output_name)
    print(json.dumps(data, indent=2))

    assert data["config_file"] == config.filename
    assert data["config_size_bytes"] == config.config_size_bytes
    assert data["config_md5"] == config.config_md5
    return data


#############
### Tests ###
#############


def test_refresh_scripts():
    config = make_config("both_scripts", [PROC_SCRIPT, POST_PROC_SCRIPT])
    data = run_refresh_scripts(config, "both_scripts.json")

    assert data["proc_script"] == config.procScript
    assert data["proc_size_bytes"] == PROC_SCRIPT.stat().st_size
    assert data["proc_md5"] is not None
    assert data["post_proc_script"] == config.postProcScript
    assert data["post_proc_size_bytes"] == POST_PROC_SCRIPT.stat().st_size
    assert data["post_proc_md5"] is not None


def test_refresh_scripts_post_proc_only():
    config = make_config("post_proc_only", [POST_PROC_SCRIPT])
    data = run_refresh_scripts(config, "post_proc_only.json")

    # a missing script is left out of the json entirely
    assert not {"proc_script", "proc_size_bytes", "proc_md5"} & data.keys()
    assert data["post_proc_script"] == config.postProcScript
    assert data["post_proc_size_bytes"] == POST_PROC_SCRIPT.stat().st_size
    assert data["post_proc_md5"] is not None


def test_refresh_scripts_default_config():
    config = make_config("default_config", [PROC_SCRIPT])
    # as if no config file had been found, which livereduce.py allows
    config.filename = config.config_md5 = config.config_size_bytes = None
    data = run_refresh_scripts(config, "default_config.json")

    assert data["config_file"] is None
    assert data["config_size_bytes"] is None
    assert data["config_md5"] is None
    assert data["proc_script"] == config.procScript


if __name__ == "__main__":
    test_refresh_scripts()
    test_refresh_scripts_post_proc_only()
    test_refresh_scripts_default_config()
