# RPM Testing Guide for LiveReduce

This document provides testing procedures for the LiveReduce RPM package.

## Overview

The LiveReduce RPM package includes proper systemd scriptlets and user/group requirements according to Fedora packaging guidelines. This testing suite helps validate these requirements locally.

## Test Structure

```
test/rpm/
├── build_and_test.sh          # Main orchestrator for local testing
├── quick_check.sh             # Fast spec file validation (runs in CI)
├── setup_test_environment.sh  # One-time environment setup
└── README.md                  # This file
```

**Note**: Docker-based RPM building and testing is handled by the CI workflow. See `.github/workflows/actions.yml` and the `Dockerfile` in the project root.

## Quick Start

### Local Development Testing

1. **Set up your environment** (one-time setup):
```bash
./test/rpm/setup_test_environment.sh
```

This will:
- Install build dependencies from the spec file using `dnf builddep`
- Install `rpmdevtools`
- Create required users and groups (`snsdata`, `users`, `hfiradmin`)

2. **Build the RPM locally**:
```bash
./rpmbuild.sh
```

3. **Quick validation**:
```bash
./test/rpm/quick_check.sh
```

### CI Testing

The CI workflow (`.github/workflows/actions.yml`) automatically:
- Runs `quick_check.sh` to validate the spec file
- Builds the RPM in an isolated Docker container (using `Dockerfile`)
- Installs the RPM and verifies basic functionality
- Runs systemd dry-run tests (`systemctl --dry-run enable/disable`)

**Note**: Additional static analysis with `rpmlint` is being added in a separate PR.

## Prerequisites

### System Requirements

- Fedora/RHEL/CentOS 8+ with DNF package manager
- Sudo access for installing packages and creating users/groups

### Install Prerequisites

The `setup_test_environment.sh` script will install everything needed, but you can also manually run:

```bash
# Install build dependencies from spec file
sudo dnf builddep -y ./livereduce.spec

# Install additional tools
sudo dnf install -y rpmdevtools
```

### User and Group Setup

The following are required by the RPM:
- **User**: `snsdata`
- **Groups**: `users`, `hfiradmin`

These are created by `setup_test_environment.sh` or on production systems when the RPM is installed.

## Validation Tests

### quick_check.sh

Fast validation of spec file requirements:
- Checks for required BuildRequires (`systemd-rpm-macros`)
- Validates user/group dependencies
- Verifies systemd scriptlet sections exist
- Ensures service file requirements are declared

**Usage**:
```bash
./test/rpm/quick_check.sh
```

**CI Integration**: This runs automatically in the `rpm-quick-check` CI job.

### build_and_test.sh

Orchestrates local RPM building and testing:
- Uses the existing `rpmbuild.sh` script
- Builds the RPM package
- Runs basic validation

**Usage**:
```bash
./test/rpm/build_and_test.sh
```

## Local RPM Testing Workflow

On SNS systems (like `ndav`), the typical workflow is:

```bash
# 1. Build the RPM
./rpmbuild.sh

# 2. Install it (if needed for testing)
sudo dnf install -y ~/rpmbuild/RPMS/noarch/python-livereduce-*.rpm

# 3. Test the service
sudo systemctl enable livereduce.service
sudo systemctl start livereduce.service
systemctl status livereduce.service

# 4. Check logs
tail -f /var/log/SNS_applications/livereduce.log

# 5. Stop and remove (if needed)
sudo systemctl stop livereduce.service
sudo systemctl disable livereduce.service
sudo dnf remove -y python-livereduce
```

## CI/CD Integration

### GitHub Actions Workflow

The `.github/workflows/actions.yml` currently includes:

1. **rpm-quick-check**: Validates spec file requirements
2. **python-build**: Builds source distribution with pixi
3. **rpm**: Full Docker-based RPM build and installation test

**Note**: Additional jobs like `rpmlint` for static analysis are being added in separate PRs.

### Docker-based Testing

The `Dockerfile` in the project root:
- Uses Red Hat UBI9 as the base image
- Installs EPEL and build tools
- Creates required users and groups
- Uses `dnf builddep` to install dependencies from spec file
- Builds and installs the RPM
- Runs systemd dry-run tests

## Troubleshooting

### Common Issues

#### "Service not found" errors
- **Cause**: systemd hasn't reloaded unit files
- **Solution**: `sudo systemctl daemon-reload`

#### Permission denied errors
- **Cause**: Missing user/group or incorrect permissions
- **Solution**: Run `./test/rpm/setup_test_environment.sh` or verify `snsdata` user exists

#### RPM build fails
- **Cause**: Missing build dependencies
- **Solution**: `sudo dnf builddep -y ./livereduce.spec`

### Debug Commands

```bash
# Check RPM dependencies (use -p to check the .rpm file before installing)
rpm -qRp python-livereduce*.rpm

# Verify installation (use -p to check the .rpm file before installing)
rpm -Vp python-livereduce*.rpm

# Check service status
systemctl status livereduce.service

# View service logs
journalctl -u livereduce.service --no-pager
```

## Development Notes

- The RPM requires `nsd-app-wrap` which is SNS-specific and not available in public repositories
- For CI testing, the RPM is installed with `rpm -ivh --nodeps` to bypass unavailable dependencies
- The service file is validated with `systemctl --dry-run` tests in CI
- Log files go to `/var/log/SNS_applications/livereduce.log` when run as `snsdata`, or to the current directory otherwise

## Additional Resources

- [Fedora Packaging Guidelines](https://docs.fedoraproject.org/en-US/packaging-guidelines/)
- [Systemd for Administrators](https://www.freedesktop.org/wiki/Software/systemd/)
- [RPM Packaging Guide](https://rpm-packaging-guide.github.io/)
