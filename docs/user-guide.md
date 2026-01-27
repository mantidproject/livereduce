# User Guide

This guide shows how to use Mantid Workbench to connect to live data streams and monitor experiments in real-time.

## Using StartLiveData Interactively

### Prerequisites

- Mantid Workbench installed
- Network access to the instrument's DAS
- Facility and instrument configured in Mantid settings

### Step-by-Step Tutorial

**1. Configure Mantid settings**
- Open Workbench: File → Settings
- Set Facility (e.g., "SNS" or "ISIS")
- Set Default Instrument (e.g., "POWGEN", "REF_M")

**2. Open the StartLiveData algorithm**
- Click the algorithm search or press Ctrl+F
- Type "StartLiveData" and open it

**3. Configure basic properties**
```
Instrument: (auto-filled from settings)
UpdateEvery: 30 (seconds between updates)
OutputWorkspace: live_data
```

**4. Set timing options**
- **From Start of Run**: Collect all data since run began (recommended)
- **From Now**: Only collect data from this moment forward
- **From Time**: Start from specific timestamp

**5. Configure processing** (optional)
- Processing tab: Add algorithms to run on each chunk
- Example: Use "Rebin" with Params="1000,100,20000"

**6. Configure post-processing** (optional)
- Post-Processing Step tab
- Select "Python Script" and load your post-processing script
- Or choose an algorithm to run on accumulated data

**7. Click "Run"** to start live data collection

**8. Monitor the data**
- Right-click the `live_data` workspace → Plot Spectrum
- The plot updates automatically as data arrives
- Check the Messages panel for errors

**9. Stop collection**
- Click the "Details" button (bottom right of Workbench)
- Click "Cancel" next to MonitorLiveData

### Tips for Interactive Use

- Start with `From Start of Run` to get all existing data
- Use `UpdateEvery=10` for faster updates during testing
- Watch memory usage in system monitor when preserving events
- Test scripts with fake data servers (see [test directory](../test/README.md))

## Simple Monitoring

For quick visualization without custom processing:

```python
# In Workbench's script window or Python interface
from mantid.simpleapi import StartLiveData

StartLiveData(
    Instrument='POWGEN',
    OutputWorkspace='monitor',
    UpdateEvery=30,
    FromStartOfRun=True,
    AccumulationMethod='Add'
)

# Now plot it
plotSpectrum('monitor', [0, 1, 2])
```

The plot updates automatically as new data arrives.

### Use Cases for Simple Monitoring

- Checking if the instrument is collecting data
- Monitoring detector health
- Quick visualization during alignment
- Verifying event rates
- Sanity checking during setup

## Understanding Timing Options

The timing options control what data you receive when connecting:

### FromStartOfRun (Recommended)

**What it does**: Collects all data since the current run began

**When to use**: Starting monitoring mid-run, want complete picture

**How it works**:
- DAS buffers all events/histograms since run start
- You receive everything collected so far
- Then continues with new data as it arrives

### FromNow

**What it does**: Only collects data from the moment you connect

**When to use**: Only interested in future data, memory constrained

**Trade-offs**:
- Misses anything collected before connection
- Lower memory usage
- Simpler for quick checks

### FromTime

**What it does**: Starts collecting from a specific timestamp

**Format**: UTC, ISO8601 format (e.g., "2026-01-21T14:30:00")

**When to use**: Replaying or analyzing specific time windows

### UpdateEvery

**What it does**: How often (in seconds) post-processing runs

**Default**: 30 seconds

**Trade-offs**:
- Shorter = more responsive but more CPU usage
- Longer = less overhead but slower updates
- Does not affect how often chunks arrive (DAS controls that)

### Run Transition Behavior

Controls what happens when runs start/stop:

- **Restart**: Clear accumulated data when new run starts (default)
- **Stop**: Stop monitoring when run ends
- **Rename**: Keep old data in renamed workspace, start fresh for new run

## Example Scenarios

### Monitoring Detector Health

```python
StartLiveData(
    Instrument='NOMAD',
    OutputWorkspace='detector_check',
    UpdateEvery=10,
    FromNow=True,
    AccumulationMethod='Replace'
)
# Plot updates every 10 seconds with latest data only
```

### Accumulating Full Run Data

```python
StartLiveData(
    Instrument='POWGEN',
    OutputWorkspace='full_run',
    UpdateEvery=30,
    FromStartOfRun=True,
    AccumulationMethod='Add',
    PreserveEvents=False  # Convert to histogram to save memory
)
```

### Time-Series Analysis

```python
StartLiveData(
    Instrument='CORELLI',
    OutputWorkspace='timeseries',
    UpdateEvery=60,
    FromStartOfRun=True,
    AccumulationMethod='Append'  # Each chunk becomes separate spectrum
)
```

## Common Issues

### Connection Fails

**Check**:
- Network access to DAS
- Facility/instrument settings correct
- Instrument is actually running

### Memory Fills Up

**Solutions**:
- Set `PreserveEvents=False`
- Use `AccumulationMethod='Replace'`
- Increase `UpdateEvery` to reduce frequency
- Close other memory-intensive applications

### Plot Doesn't Update

**Check**:
- MonitorLiveData is still running (check Details button)
- Log messages for errors
- DAS is sending data (ask instrument scientist)

## Related Documentation

- [Architecture](architecture.md) - How the system works
- [Processing Scripts](processing-scripts.md) - Writing custom processing
- [Troubleshooting](troubleshooting.md) - Fixing problems
- [Mantid StartLiveData docs](https://docs.mantidproject.org/nightly/algorithms/StartLiveData-v1.html)
