# LiveReduce

Automated live data reduction service for neutron scattering beamlines.

LiveReduce provides a daemon-based system for processing neutron scattering data in real-time as it arrives from the Data Acquisition System (DAS). It uses Mantid's `StartLiveData` and `MonitorLiveData` algorithms to process data chunks and accumulate results continuously during experimental runs.

## Documentation

- **[Complete User and Developer Guide](docs/README.md)** - Start here for comprehensive documentation
- **[Architecture](docs/architecture.md)** - System design and data flow
- **[Configuration Reference](docs/configuration.md)** - All configuration options
- **[Processing Scripts](docs/processing-scripts.md)** - Writing data processing scripts
- **[Troubleshooting](docs/troubleshooting.md)** - Solving common problems

## Quick Start

### For Users

1. **Install the service:**
```bash
sudo dnf install python-livereduce
```

2. **Configure:** Create `/etc/livereduce.conf`
```json
{
  "instrument": "POWGEN",
  "CONDA_ENV": "mantid"
}
```

3. **Start:**
```bash
sudo systemctl start livereduce
sudo systemctl status livereduce
```

See the [Developer Guide](docs/developer-guide.md) for detailed installation instructions.

### For Developers

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Developer Guide](docs/developer-guide.md).

## Configuration

The configuration is automatically read from `/etc/livereduce.conf`. A minimal configuration requires only the instrument name:

```json
{
  "instrument": "POWGEN",
  "CONDA_ENV": "mantid"
}
```

See [Configuration Reference](docs/configuration.md) for all options.

## Managing the Service

```bash
# Start/stop/restart
sudo systemctl start livereduce
sudo systemctl stop livereduce
sudo systemctl restart livereduce

# Check status
systemctl status livereduce

# View logs
tail -f /var/log/SNS_applications/livereduce.log
sudo journalctl -u livereduce -f
```

## Processing Scripts

LiveReduce executes instrument-specific Python scripts:

- `reduce_<INSTRUMENT>_live_proc.py` - Processes each data chunk
- `reduce_<INSTRUMENT>_live_post_proc.py` - Processes accumulated data

Example for NOMAD:
- `/SNS/NOM/shared/livereduce/reduce_NOM_live_proc.py`
- `/SNS/NOM/shared/livereduce/reduce_NOM_live_post_proc.py`

See [Processing Scripts](docs/processing-scripts.md) for writing these scripts.

## Watchdog Service

The optional watchdog service monitors the main daemon and restarts it if unresponsive:

```bash
sudo dnf install python-livereduce-watchdog
sudo systemctl enable livereduce_watchdog
sudo systemctl start livereduce_watchdog
```

Configure in `/etc/livereduce.conf`:
```json
{
  "watchdog": {
    "interval": 60,
    "threshold": 300
  }
}
```

## Acknowledgements

Information and ideas taken from:
* [StatisticsService](https://github.com/neutrons/StatisticsService)
* [autoreduce](https://github.com/mantidproject/autoreduce)
* [post_processing_agent](https://github.com/neutrons/post_processing_agent)
* [Logging in python](https://fangpenlin.com/posts/2012/08/26/good-logging-practice-in-python/)
* [systemd](https://www.freedesktop.org/software/systemd/man/systemd.service.html) documentation
