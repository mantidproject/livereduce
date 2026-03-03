# Live Data Reduction Documentation

This directory contains comprehensive documentation for the livereduce system, which provides real-time data processing for neutron scattering instruments.

```
┌──────────────────────────────────────────────────────────────────┐
│                   Documentation Structure                        │
└──────────────────────────────────────────────────────────────────┘

For Understanding
    └── Architecture ──────→ System design and data flow

For Setting Up
    ├── Developer Guide ───→ Installing daemon on servers
    ├── Processing Scripts → Writing reduction scripts
    └── Configuration ─────→ Parameter reference

For Problems
    └── Troubleshooting ───→ Debugging and fixes

For Contributing
    ├── Examples ──────────→ Integration patterns
    └── CONTRIBUTING.md ───→ Development workflow
```

## Documentation Structure

### For Developers
- **[Architecture](architecture.md)** - System components, data flow, and design overview
- **[Developer Guide](developer-guide.md)** - Setting up live reduction for a beamline
- **[Processing Scripts](processing-scripts.md)** - Creating and deploying processing scripts
- **[Configuration Reference](configuration.md)** - Complete configuration options reference
- **[Examples](examples.md)** - Integration examples and patterns

### For Operations
- **[Troubleshooting](troubleshooting.md)** - Debugging, common issues, and service management

### For Contributors
- **[Contributing Guide](../CONTRIBUTING.md)** - Development workflow and guidelines

## Quick Links

### I want to...
- **Set up live reduction for my beamline**: See [Developer Guide](developer-guide.md)
- **Write processing scripts**: See [Processing Scripts](processing-scripts.md)
- **Integrate with existing workflows**: See [Examples](examples.md)
- **Fix a problem**: See [Troubleshooting](troubleshooting.md)
- **Understand the system**: See [Architecture](architecture.md)
- **Configure the daemon**: See [Configuration Reference](configuration.md)
- **Contribute to the project**: See [Contributing Guide](../CONTRIBUTING.md)

## Overview

Live reduction provides real-time data processing as the Data Acquisition System (DAS) collects neutron scattering data. Scientists can monitor results and adjust experimental parameters without waiting for runs to complete.

The `livereduce` systemd service provides automated processing for beamline operations. For interactive usage of live data in Mantid Workbench, see the [Mantid StartLiveData documentation](https://docs.mantidproject.org/nightly/algorithms/StartLiveData-v1.html).

## Additional Resources

- [Main README](../README.md) - Installation and basic usage
- [Mantid StartLiveData documentation](https://docs.mantidproject.org/nightly/algorithms/StartLiveData-v1.html)
- [livereduce GitHub repository](https://github.com/mantidproject/livereduce)
- [Test examples](../test/README.md)
