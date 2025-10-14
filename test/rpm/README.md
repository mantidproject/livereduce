# RPM Testing Guide for LiveReduce

This document provides comprehensive testing procedures for the LiveReduce RPM package improvements.

## Overview

The LiveReduce RPM package has been enhanced with proper systemd scriptlets and user/group requirements according to Fedora packaging guidelines. This testing suite validates these improvements.

## Test Structure

```
test/rpm/
├── build_and_test.sh          # Main orchestrator script
├── quick_check.sh             # Fast validation of all requirements
├── setup_test_environment.sh  # Environment setup
├── test_docker_rpm.sh         # Docker-based isolated testing
├── test_manual_rpm.sh         # Interactive manual testing
└── README.md                  # This file
```

## Quick Start

### Automated Testing

Run the complete test suite:

```bash
cd /path/to/livereduce
./test/rpm/build_and_test.sh
```

This will:
1. Validate the spec file
2. Build the RPM package
3. Run automated functionality tests
4. Run Docker-based tests (if Docker is available)
5. Provide instructions for manual testing

### Skip Docker Tests

If Docker is not available or you want to skip Docker tests:

```bash
./test/rpm/build_and_test.sh --no-docker
```

## Test Types

### 1. Automated Functionality Tests

**Script**: `quick_check.sh`

**Purpose**: Fast validation of all spec file requirements and basic functionality.

**Tests Include**:
- Spec file syntax and requirements validation
- User and group dependency checks
- Systemd scriptlet verification
- Service file validation

**Usage**:
```bash
./test/rpm/quick_check.sh
```

**Output**: Simple PASS/FAIL status for each requirement.

### 2. Docker-based Isolated Testing

**Script**: `test_docker_rpm.sh`

**Purpose**: Tests RPM functionality in a clean, isolated Fedora environment.

**Benefits**:
- Clean testing environment
- No impact on host system
- Tests actual package installation/upgrade/removal
- Validates systemd integration

**Requirements**: Docker must be installed and accessible

**Usage**:
```bash
./test/rpm/test_docker_rpm.sh
```

**Process**:
1. Builds Fedora-based Docker image with required dependencies
2. Creates required users and groups
3. Builds RPM package
4. Tests fresh installation
5. Tests package upgrade
6. Tests package removal
7. Validates systemd scriptlet behavior

### 3. Manual Interactive Testing

**Script**: `test_manual_rpm.sh`

**Purpose**: Provides guided manual testing for scenarios requiring human verification.

**Tests Include**:
- Fresh installation
- Package upgrade scenarios
- Service lifecycle management
- Package removal
- Dependency verification

**Usage**:
```bash
./test/rpm/test_manual_rpm.sh
```

**Features**:
- Interactive menu system
- Step-by-step guidance
- Current system state display
- Confirmation prompts for destructive operations

## Prerequisites

### System Requirements

- Fedora/RHEL/CentOS system with RPM package manager
- `rpm-build` and `rpmdevtools` packages installed
- `systemd-rpm-macros` package installed
- Sudo access for package installation/removal

### Install Prerequisites

```bash
# Fedora/RHEL/CentOS
sudo dnf install rpm-build rpmdevtools systemd-rpm-macros

# For Docker testing
sudo dnf install docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

### User and Group Setup

The tests require these users and groups to exist (created automatically in Docker tests):

- **User**: `snsdata`
- **Groups**: `users`, `hfiradmin`

For manual testing, create them if they don't exist:

```bash
sudo groupadd -r users 2>/dev/null || true
sudo groupadd -r hfiradmin
sudo useradd -r -g users -G hfiradmin snsdata
```

## Test Scenarios

### Scenario 1: Fresh Installation

**Validates**:
- Package installs cleanly
- Systemd service is registered
- Users and groups are available
- Log directories are created with correct permissions
- Service can be enabled/disabled

### Scenario 2: Package Upgrade

**Validates**:
- Service restarts automatically during upgrade
- Configuration files are preserved
- No duplicate entries in systemd
- All functionality remains intact

### Scenario 3: Package Removal

**Validates**:
- Service is properly stopped and disabled
- Service file is removed from systemd
- Log files are cleaned up (configurable)
- No orphaned entries remain

### Scenario 4: Service Lifecycle

**Validates**:
- Service can be enabled/disabled
- Service starts with correct user/group
- Service configuration is valid
- Systemd recognizes the service

## Expected Test Results

### Success Criteria

- All automated tests show PASS status
- Docker tests complete without errors
- Service integrates properly with systemd
- Required users and groups are accessible
- File permissions are set correctly

### Common Issues and Solutions

#### "Service not found" errors
- **Cause**: systemd hasn't reloaded unit files
- **Solution**: Run `systemctl daemon-reload`

#### Permission denied errors
- **Cause**: Missing user/group or incorrect permissions
- **Solution**: Verify snsdata user exists and has proper group memberships

#### Docker tests fail
- **Cause**: Docker not running or permission issues
- **Solution**:
  ```bash
  sudo systemctl start docker
  sudo usermod -aG docker $USER
  # Log out and log back in
  ```

#### RPM build fails
- **Cause**: Missing build dependencies
- **Solution**: Install prerequisites as shown above

## Test Output Analysis

### Quick Check Output

The quick check script validates spec file requirements and produces simple output:
- Green ✓ for passing checks
- Red ✗ for failing checks
- Exits with status 0 on success, non-zero on failure

Example output:
```
===============================================
    LiveReduce RPM Spec File Quick Check
===============================================

✓ Spec file found
✓ BuildRequires systemd-rpm-macros
✓ Requires user(snsdata)
✓ Requires group(users)
✓ Requires group(hfiradmin)
✓ %systemd_post scriptlet
✓ %systemd_preun scriptlet
✓ %systemd_postun_with_restart scriptlet

All checks passed!
```

## Integration with CI/CD

### Automated Pipeline Integration

The test suite can be integrated into CI/CD pipelines:

```bash
# In CI script
./test/rpm/build_and_test.sh --no-docker
if [ $? -eq 0 ]; then
    echo "RPM tests passed"
else
    echo "RPM tests failed"
    exit 1
fi
```

### Test Artifacts

The following artifacts are generated:
- Built RPM package: `python-livereduce-*.rpm`
- Test results: `/tmp/rpm_test_results.txt`
- Build logs in `rpmbuild/` directory

## Troubleshooting

### Debug Mode

Enable verbose output in test scripts:

```bash
export DEBUG=1
./test/rpm/build_and_test.sh
```

### Manual RPM Operations

For debugging, you can manually test RPM operations:

```bash
# Build RPM
rpmbuild -ba livereduce.spec

# Install
sudo rpm -ivh python-livereduce-*.rpm

# Verify installation
rpm -V python-livereduce

# Check dependencies
rpm -qR python-livereduce

# Remove
sudo rpm -e python-livereduce
```

### Service Debugging

Debug systemd service issues:

```bash
# Check service status
systemctl status livereduce.service

# View service logs
journalctl -u livereduce.service

# Test service file
systemd-analyze verify livereduce.service
```
