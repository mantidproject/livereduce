## Table of Contents

- [Configuration](#configuration)
- [Managing the service](#managing-the-service)
- [Logging](#logging)
- [Python processing scripts](#python-processing-scripts)
- [Behavior](#behavior)
- [Building and packaging](#building-and-packaging)
  - [Testing](#testing)
  - [Building the RPM](#building-the-rpm)
- [The Watchdog Service](#the-watchdog-service)
  - [Watchdog Configuration](#watchdog-configuration)
  - [Managing the watchdog service](#managing-the-watchdog-service)
  - [Watchdog Logging](#watchdog-logging)
  - [Watchdog Scripts](#watchdog-scripts)
  - [Building and packaging the watchdog](#building-and-packaging-the-watchdog)
- [Developer notes](#developer-notes)
- [Acknowledgements and other links](#acknowledgements-and-other-links)

Configuration
-------------

The configuration is automatically read from `/etc/livereduce.conf`unless specified as a command line argument.
Defaults will be attempted to be determined from the environment.
A minimal configuration to specify using nightly builds of mantid installed in a conda environment `mantid-dev` is
```json
{
  "instrument": "PG3",
  "CONDA_ENV": "mantid-dev"
}
```
For testing, a configuration file can be supplied as a command line argument when running
```shell
$ python scripts/livereduce.py ./livereduce.conf
```
If the instrument is not defined in the configuration file,
the software will ask mantid for the default instrument using
`mantid.kerel.ConfigService.getInstrument()` ([docs](https://docs.mantidproject.org/nightly/api/python/mantid/kernel/ConfigServiceImpl.html#mantid.kernel.ConfigServiceImpl.getInstrument)).
The default instrument is controlled in the [mantid properties files](https://docs.mantidproject.org/nightly/concepts/PropertiesFile.html)
and is typically defined in `/etc/mantid.local.properties`.


Managing the service
--------------------

If run from inside `systemctl`, use the standard commands for starting and stopping it.

```shell
sudo systemctl start livereduce
sudo systemctl stop livereduce
sudo systemctl restart livereduce
```
The status of the service can be found via
```shell
sudo systemctl status livereduce
```

Logging
--------

The logfile of what was setup for running, as well as other messages, is
`/var/log/SNS_applications/livereduce.log` if run as the user `snsdata`,
or `livereduce.log` in the current working directory (if run from the
command line).

the logs are stored in `/var/log/SNS_applications/livereduce.log` and are readable by anyone.
People with extra permissions can run ``sudo journalctl -u livereduce -f`` and see all of the logs without them flushing on restart of the service.
Sometimes the service refuses to restart, in that case `stop` then `start` it in separate commands.


Python processing scripts
-------------------------


- [livereduce.sh](../scripts/livereduce.sh) is the script that is run when the service is started.
  This shell script invokes `livereduce.py` within a conda environment
  specified in the configuration file. Otherwise the environment is set to `"mantid-dev"`.
- [livereduce.py](../scripts/livereduce.py) script manages live data reduction using the Mantid framework.
  It configures logging, handles signals for graceful termination, reads the configuration JSON,
  and manages live data processing with Mantid's StartLiveData and MonitorLiveData algorithms.
  The script monitors memory usage and restarts the live data processing if memory limits are exceeded.
  It uses `pyinotify` to watch for changes in configuration and processing scripts,
  restarting the live data processing as needed. The service relies on instrument-specific processing scripts
  for data accumulation and reduction
- `<script_dir>/reduce_<instrument>_proc.py` is the instrument-specific processing script for each chunk (required).
- `<script_dir>/reduce_<instrument>_post_proc.py` is the post-processing script for the accumulated data.
  To disable this step rename the python script so it is not found by the daemon.

Example instrument-specific scripts for NOMAD with default script location are
`/SNS/NOM/shared/livereduce/reduce_NOM_live_proc.py` and
`/SNS/NOM/shared/livereduce/reduce_NOM_live_post_proc.py`.


Behavior
--------

The daemon will immediately cancel
[StartLiveData](http://docs.mantidproject.org/nightly/algorithms/StartLiveData-v1.html)
and
[MonitorLiveData](http://docs.mantidproject.org/nightly/algorithms/MonitorLiveData-v1.html)
and restart them when one of processing scripts is changed (verified
by md5sum) or removed. This is to be resilient against changes in the scripts.

The process will exit and systemd will restart it if the configuration
file is changed. This is done in case the version of mantid wanted is
changed.


Building and packaging
----------------------

### Testing

Testing is described in the [`test/` subdirectory](test/README.md).

RPM development and testing is described in the [RPM testing guide](test/rpm/README.md).

### Building the RPM

This package uses a hand-written spec file for releasing on rpm based systems rather than the one generated by python. To run it execute

```
./rpmbuild.sh
```

And look for the results in the `~/rpmbuild/RPMS/noarch/` directory.

This package depends on
[pyinotify](https://github.com/seb-m/pyinotify) and (of course)
[mantid](http://www.mantidproject.org).

Developer notes
---------------

This repository is configured to use pre-commit. This can be done using pixi via

```
pixi install
pixi shell
pre-commit install
```

More information about testing can be found in [test/README.md](test/README.md).

The Watchdog Service
--------------------

The watchdog service monitors the main `livereduce` service and automatically restarts it
when it detects that the service has become unresponsive or inactive.
It operates independently from the main service but works in tandem to ensure continuous live data reduction.


### Watchdog Configuration

The watchdog service reads its configuration from the same `/etc/livereduce.conf` file as the main service,
but uses only a subset of settings specific to monitoring behavior.
The watchdog-specific configuration is optional and uses sensible defaults if not specified.

The watchdog configuration section supports the following optional keys:
```json
{
  "watchdog": {
    "interval": 60,
    "threshold": 300
  }
}
```

Configuration parameters:
- `watchdog.interval` (default: 60 seconds) - How often the watchdog checks the livereduce log file for activity.
- `watchdog.threshold` (default: 300 seconds) - Maximum allowed time without log activity
  before the watchdog considers the service unresponsive and triggers a restart. Must be at least 20 seconds.

If the configuration file does not contain a `watchdog` section,
the watchdog will use the default values shown above.
Invalid values will trigger a warning and fall back to defaults.

### Managing the watchdog service

The watchdog service is managed independently of the main `livereduce` service using standard systemd commands:

```shell
sudo systemctl start livereduce_watchdog
sudo systemctl stop livereduce_watchdog
sudo systemctl restart livereduce_watchdog
```

Check the watchdog service status:
```shell
sudo systemctl status livereduce_watchdog
```

**Important operational considerations:**

- The watchdog service starts **after** the `livereduce` service
  (as defined by `After=livereduce.service` in the systemd unit).
- **Stopping the watchdog does not stop the main `livereduce` service** - it only stops monitoring.
  The main service will continue running without supervision.
- **Restarting the watchdog does not restart `livereduce`**
  unless the watchdog detects that the main service has become unresponsive.
- The watchdog and main service must be managed separately.
  Starting/stopping one does not automatically affect the other.
- The watchdog service has `Restart=always` configured,
  so systemd will automatically restart the watchdog if it crashes.

### Watchdog Logging

The watchdog maintains its own separate log file at `/var/log/SNS_applications/livereduce_watchdog.log`
when run as the user `snsdata`.

This log captures:
- Watchdog startup and configuration validation messages
- Detection of inactivity (when the main service log hasn't been updated within the threshold)
- Restart actions taken against the main `livereduce` service
- The last 20 lines of the main livereduce log at the time of restart (for correlation)
- Status output from systemctl after triggering a restart

To view the watchdog logs in real-time:
```shell
sudo tail -f /var/log/SNS_applications/livereduce_watchdog.log
```

For systemd journal logs:
```shell
sudo journalctl -u livereduce_watchdog -f
```

**Correlating watchdog and main service logs:**

When the watchdog restarts the main service, it logs a clear marker:
```
#############################################################################
[timestamp] No change for XXX s in /var/log/SNS_applications/livereduce.log
---- Last 20 lines of /var/log/SNS_applications/livereduce.log before restart:
[last lines of main log]

restarting livereduce.service.
```

You can correlate these events with the main service log (`/var/log/SNS_applications/livereduce.log`)
by comparing timestamps to understand what caused the service to become unresponsive.

### Watchdog Scripts

Unlike the main `livereduce` service which uses Python scripts for data processing,
the watchdog uses a simple bash script for monitoring:

- [livereduce_watchdog.sh](scripts/livereduce_watchdog.sh) - The main watchdog script executed by systemd.
  This script:
  - Reads configuration from `/etc/livereduce.conf` (or a path provided as an argument)
  - Monitors `/var/log/SNS_applications/livereduce.log` for modification time changes
  - Enters an infinite loop that checks file activity every `interval` seconds
  - Triggers a restart of `livereduce.service` via `systemctl restart`
    if the log hasn't been modified for `threshold` seconds
  - Implements restart throttling to prevent repeated restarts within the same inactivity window
  - Logs all monitoring actions and restart decisions to the watchdog log file

### Building and Packaging the Watchdog

The watchdog service is distributed as a separate subpackage (`livereduce-watchdog`) within the same RPM
but can be installed independently.

The build installs:
- `livereduce_watchdog.sh` to `/usr/bin/`
- `livereduce_watchdog.service` systemd unit file to `/usr/lib/systemd/system/`

**Important notes:**

- The watchdog service is **not enabled by default** after installation. You must manually enable it:
  ```shell
  sudo systemctl enable livereduce_watchdog
  sudo systemctl start livereduce_watchdog
  ```
- The watchdog package has no additional dependencies beyond standard system utilities
  (`bash`, `jq`, `systemctl`, `stat`, `tail`).
- When the watchdog package is removed, its log file (`/var/log/SNS_applications/livereduce_watchdog.log`)
  is automatically deleted.


Acknowledgements and other links
--------------------------------
Information and ideas taken from:
* [StatisticsService](https://github.com/neutrons/StatisticsService)
* [autoreduce](https://github.com/mantidproject/autoreduce)
* [post_processing_agent](https://github.com/neutrons/post_processing_agent)
* [Logging in python](https://fangpenlin.com/posts/2012/08/26/good-logging-practice-in-python/)
* [systemd](https://fangpenlin.com/posts/2012/08/26/good-logging-practice-in-python/) and [systemd.service](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
