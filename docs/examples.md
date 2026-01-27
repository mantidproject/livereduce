# Integration Examples

This guide provides complete, working examples showing how to integrate live reduction into different workflows.

## Testing Locally

Before deploying to production, test your setup using the included test infrastructure.

```
┌──────────────────────────────────────────────────────────────────┐
│                    Local Testing Setup                           │
└──────────────────────────────────────────────────────────────────┘

Terminal 1                Terminal 2                Terminal 3
   │                         │                         │
   ↓                         ↓                         ↓
┌─────────┐             ┌─────────┐             ┌──────────┐
│ Fake    │   network   │ Live    │   writes    │ Monitor  │
│ Server  │────────────→│ Reduce  │────────────→│ Logs     │
│         │             │         │             │          │
│ Sends   │             │ Process │             │ tail -f  │
│ chunks  │             │ Data    │             │ output   │
└─────────┘             └─────────┘             └──────────┘
    ↑                                                  │
    │                                                  ↓
    └──────────────── See results ────────────────────┘
```

### Basic Local Testing

**1. Set up environment:**

```bash
cd /path/to/livereduce
pixi install
pixi shell
```

**2. Start fake data server** (Terminal 1):

```bash
python test/fake_server.py
```

This simulates ISIS histogram DAE producing:
- 5 periods
- 10 spectra per period
- 100 bins per spectrum

**3. Run live reduction** (Terminal 2):

```bash
python scripts/livereduce.py test/fake.conf
```

**4. Watch logs** (Terminal 3):

```bash
tail -f livereduce.log
```

**Expected output:**
```
2026-01-21 10:30:00 - livereduce - INFO - logging started by user 'youruser'
2026-01-21 10:30:01 - livereduce.Config - INFO - Loading configuration from 'test/fake.conf'
2026-01-21 10:30:02 - livereduce.LiveDataManager - INFO - StartLiveData(...)
2026-01-21 10:30:03 - Mantid - INFO - Processing started
```

**Stop testing:** Press `Ctrl+C` in Terminal 2 to cleanly shut down.

### Testing with Event Data

Test memory monitoring with continuously accumulating events:

**1. Start event server** (Terminal 1):

```bash
python test/fake_event_server.py
```

**2. Run with event config** (Terminal 2):

```bash
python scripts/livereduce.py test/fake_event.conf
```

This will accumulate events until memory limit is reached, then restart processing.

**Watch for memory warnings:**
```
2026-01-21 10:35:00 - livereduce - WARNING - Memory usage at 72.5%
2026-01-21 10:35:30 - livereduce - ERROR - Memory usage exceeds 70% limit - restarting
```

### Testing Post-Processing Only

Some workflows only need post-processing without per-chunk processing:

```bash
python scripts/livereduce.py test/postprocessing/fake.conf
```

This demonstrates:
- No processing script (`reduce_*_live_proc.py` not required)
- Only post-processing script runs on accumulated data
- Useful for simple workflows or summary operations

## Interactive Use in Mantid Workbench

### Basic Monitoring

Open Mantid Workbench and run in the Python console:

```python
from mantid.simpleapi import StartLiveData

# Monitor POWGEN live data
StartLiveData(
    Instrument='POWGEN',
    UpdateEvery=30,
    AccumulationMethod='Replace',
    OutputWorkspace='live_data'
)
```

**Result:** Workspace `live_data` updates every 30 seconds with latest chunk.

### With Processing Script

Apply reduction during acquisition:

```python
from mantid.simpleapi import StartLiveData

StartLiveData(
    Instrument='NOMAD',
    UpdateEvery=60,
    AccumulationMethod='Add',
    ProcessingAlgorithm='AlignAndFocusPowder',
    ProcessingProperties='CalFilename=/SNS/NOM/shared/CALIBRATION.cal;'
                         'GroupFilename=/SNS/NOM/shared/GROUP.xml',
    AccumulationWorkspace='accumulated',
    OutputWorkspace='live_nomad'
)
```

**What happens:**
1. Every 60s, new chunk arrives
2. `AlignAndFocusPowder` processes it
3. Result added to `accumulated`
4. `live_nomad` shows current accumulated state

### Starting from Specific Time

Resume monitoring from earlier in the run:

```python
from mantid.simpleapi import StartLiveData
from datetime import datetime, timedelta

# Start from 5 minutes ago
start_time = datetime.now() - timedelta(minutes=5)

StartLiveData(
    Instrument='CORELLI',
    FromTime=start_time.strftime('%Y-%m-%dT%H:%M:%S'),
    UpdateEvery=30,
    OutputWorkspace='live_corelli'
)
```

**Use cases:**
- Catch up after Workbench restart
- Review recent data while run continues
- Compare different time windows

### Custom Processing with Python Script

Use external processing script for complex workflows:

**Create `my_reduction.py`:**
```python
from mantid.simpleapi import (
    ConvertUnits,
    Rebin,
    SumSpectra,
    SaveNexus
)

# Process chunk
ConvertUnits(
    InputWorkspace=input,
    OutputWorkspace=output,
    Target='dSpacing'
)

Rebin(
    InputWorkspace=output,
    OutputWorkspace=output,
    Params='0.5,0.01,3.5',
    PreserveEvents=False
)

# Sum for quick view
SumSpectra(
    InputWorkspace=output,
    OutputWorkspace='summed',
    RemoveSpecialValues=True
)

# Optional: Save each chunk
run_number = output.getRun().getProperty('run_number').value
SaveNexus(
    InputWorkspace=output,
    Filename=f'/SNS/POWGEN/IPTS-12345/shared/live_chunk_{run_number}.nxs'
)
```

**Run with script:**
```python
StartLiveData(
    Instrument='POWGEN',
    UpdateEvery=45,
    ProcessingScriptFilename='/path/to/my_reduction.py',
    AccumulationMethod='Add',
    OutputWorkspace='live_reduced'
)
```

## Daemon-Based Production Setup

### Single Instrument Configuration

**File:** `/etc/livereduce.conf`

```json
{
  "instrument": "POWGEN",
  "CONDA_ENV": "mantid-production",
  "update_every": 60,
  "accum_method": "Add",
  "preserve_events": false,
  "system_mem_limit_perc": 70
}
```

**Processing script:** `/SNS/POWGEN/shared/livereduce/reduce_POWGEN_live_proc.py`

```python
from mantid.simpleapi import (
    AlignAndFocusPowder,
    ConvertUnits,
    Rebin,
    SaveNexus
)

# Align and focus using calibration
AlignAndFocusPowder(
    InputWorkspace=input,
    OutputWorkspace=output,
    CalFileName='/SNS/POWGEN/shared/calibration/POWGEN_2024.cal',
    Params=-0.0002,
    ResampleX=8192,
    PreserveEvents=False
)

# Convert to Q
ConvertUnits(
    InputWorkspace=output,
    OutputWorkspace=output,
    Target='MomentumTransfer'
)

# Save reduced chunk
run_info = output.getRun()
run_number = run_info.getProperty('run_number').value
SaveNexus(
    InputWorkspace=output,
    Filename=f'/SNS/POWGEN/IPTS/shared/live_reduced/POWGEN_{run_number}_live.nxs'
)
```

**Post-processing:** `/SNS/POWGEN/shared/livereduce/reduce_POWGEN_live_post_proc.py`

```python
from mantid.simpleapi import (
    SaveAscii,
    SaveNexus,
    mtd
)

# Accumulated workspace is named based on config
accum_ws = 'accumulation'

if mtd.doesExist(accum_ws):
    # Save accumulated data
    run_info = mtd[accum_ws].getRun()
    run_number = run_info.getProperty('run_number').value

    # Save as NeXus
    SaveNexus(
        InputWorkspace=accum_ws,
        Filename=f'/SNS/POWGEN/IPTS/shared/live_accumulated/POWGEN_{run_number}_accum.nxs'
    )

    # Also save ASCII for quick viewing
    SaveAscii(
        InputWorkspace=accum_ws,
        Filename=f'/SNS/POWGEN/IPTS/shared/live_accumulated/POWGEN_{run_number}_accum.dat',
        Separator='Space'
    )
```

**Start service:**
```bash
sudo systemctl start livereduce
sudo systemctl enable livereduce
```

### Multi-Period Event Data (ISIS)

**Configuration:** `/etc/livereduce.conf`

```json
{
  "instrument": "WISH",
  "listener": "ISISHistoDataListener",
  "CONDA_ENV": "mantid-nightly",
  "update_every": 30,
  "accum_method": "Replace",
  "preserve_events": true
}
```

**Processing script:** `/SNS/WISH/shared/livereduce/reduce_WISH_live_proc.py`

```python
from mantid.simpleapi import (
    CompressEvents,
    FilterByXValue,
    SumSpectra
)

# Compress events to manage memory
CompressEvents(
    InputWorkspace=input,
    OutputWorkspace=output,
    Tolerance=0.01
)

# Remove invalid TOF
FilterByXValue(
    InputWorkspace=output,
    OutputWorkspace=output,
    XMin=1000,
    XMax=20000
)

# Create summed spectrum for quick viewing
SumSpectra(
    InputWorkspace=output,
    OutputWorkspace='wish_sum',
    RemoveSpecialValues=True
)
```

**Handle periods in post-processing:**

```python
from mantid.simpleapi import (
    GroupWorkspaces,
    mtd,
    SaveNexusProcessed
)

# Accumulated workspace contains all periods
accum = 'accumulation'

if mtd.doesExist(accum):
    ws = mtd[accum]

    # Check if multi-period
    if hasattr(ws, 'getNumberOfEntries'):
        # WorkspaceGroup with one workspace per period
        period_names = ws.getNames()
        print(f"Processing {len(period_names)} periods: {period_names}")

        # Save group
        SaveNexusProcessed(
            InputWorkspace=accum,
            Filename='/SNS/WISH/shared/live_data/WISH_live_multiperiod.nxs'
        )
    else:
        # Single period
        SaveNexusProcessed(
            InputWorkspace=accum,
            Filename='/SNS/WISH/shared/live_data/WISH_live_single.nxs'
        )
```

### Memory-Constrained System

For systems with limited RAM, use aggressive memory management:

```json
{
  "instrument": "NOMAD",
  "CONDA_ENV": "mantid",
  "update_every": 45,
  "accum_method": "Replace",
  "preserve_events": false,
  "system_mem_limit_perc": 60,
  "mem_check_interval_sec": 2
}
```

**Processing script with memory optimization:**

```python
from mantid.simpleapi import (
    AlignAndFocusPowder,
    CompressEvents,
    DeleteWorkspace,
    mtd
)

# Immediately compress to reduce memory
CompressEvents(
    InputWorkspace=input,
    OutputWorkspace='compressed',
    Tolerance=0.05
)

# Focus and convert to histogram
AlignAndFocusPowder(
    InputWorkspace='compressed',
    OutputWorkspace=output,
    CalFileName='/SNS/NOM/shared/cal/NOMAD.cal',
    Params=-0.0004,
    PreserveEvents=False  # Convert to histogram
)

# Clean up intermediate workspace
DeleteWorkspace('compressed')

# Don't create additional workspaces
# Everything stays in 'output'
```

### Selective Spectra Loading

Process only specific detector banks to reduce memory:

```json
{
  "instrument": "SEQUOIA",
  "update_every": 30,
  "spectra": [0, 100, 200, 300, 400],
  "preserve_events": true
}
```

**Processing script:**

```python
from mantid.simpleapi import (
    ConvertUnits,
    Rebin,
    SumSpectra
)

# Input already contains only requested spectra
print(f"Processing {input.getNumberHistograms()} spectra")

# Standard reduction
ConvertUnits(
    InputWorkspace=input,
    OutputWorkspace=output,
    Target='DeltaE',
    EMode='Direct',
    EFixed=50.0
)

Rebin(
    InputWorkspace=output,
    OutputWorkspace=output,
    Params='-20,0.5,50',
    PreserveEvents=False
)
```

## Integration with Automated Workflows

### Triggering External Scripts

Post-processing can trigger analysis pipelines:

```python
import subprocess
from mantid.simpleapi import SaveNexus, mtd

accum = 'accumulation'

if mtd.doesExist(accum):
    ws = mtd[accum]
    run_number = ws.getRun().getProperty('run_number').value

    # Save data
    output_file = f'/SNS/INSTR/shared/live/run_{run_number}.nxs'
    SaveNexus(InputWorkspace=accum, Filename=output_file)

    # Trigger external analysis
    try:
        subprocess.run(
            ['/SNS/INSTR/shared/scripts/analyze_live.sh', output_file],
            timeout=30,
            check=True
        )
    except subprocess.TimeoutExpired:
        print(f"Analysis script timed out for {output_file}")
    except subprocess.CalledProcessError as e:
        print(f"Analysis script failed: {e}")
```

### Publishing Results to Web Dashboard

Send reduced data to monitoring system:

```python
import json
import requests
from mantid.simpleapi import mtd

accum = 'accumulation'

if mtd.doesExist(accum):
    ws = mtd[accum]

    # Extract key metrics
    run_info = ws.getRun()
    run_number = run_info.getProperty('run_number').value
    proton_charge = run_info.getProperty('gd_prtn_chrg').value

    # Get intensity in region of interest
    y_data = ws.readY(0)
    total_counts = sum(y_data)

    # Publish to dashboard
    payload = {
        'run': run_number,
        'instrument': 'POWGEN',
        'proton_charge': proton_charge,
        'total_counts': int(total_counts),
        'timestamp': run_info.getProperty('start_time').value
    }

    try:
        response = requests.post(
            'http://dashboard.facility.gov/api/live_data',
            json=payload,
            timeout=5
        )
        response.raise_for_status()
    except requests.RequestException as e:
        print(f"Failed to publish to dashboard: {e}")
```

### Email Notifications

Alert users when specific conditions are met:

```python
import smtplib
from email.message import EmailMessage
from mantid.simpleapi import mtd

accum = 'accumulation'

if mtd.doesExist(accum):
    ws = mtd[accum]

    # Check if interesting feature appeared
    y_data = ws.readY(0)
    peak_intensity = max(y_data)
    threshold = 10000

    if peak_intensity > threshold:
        # Send alert
        msg = EmailMessage()
        msg['Subject'] = 'Live Reduction Alert: Strong Peak Detected'
        msg['From'] = 'livereduce@facility.gov'
        msg['To'] = 'scientist@facility.gov'

        run_number = ws.getRun().getProperty('run_number').value
        msg.set_content(f"""
A strong peak (intensity {peak_intensity:.0f}) was detected in run {run_number}.

You may want to adjust experimental parameters.

View live data at: http://dashboard.facility.gov/run/{run_number}
        """)

        try:
            with smtplib.SMTP('smtp.facility.gov') as smtp:
                smtp.send_message(msg)
        except Exception as e:
            print(f"Failed to send email: {e}")
```

## Debugging Integration Issues

### Add Detailed Logging

Enhance scripts with debugging information:

```python
import logging
from mantid.simpleapi import mtd

logger = logging.getLogger('Mantid')

logger.info("=== Processing Script Started ===")
logger.info(f"Input workspace: {input.name()}")
logger.info(f"Number of histograms: {input.getNumberHistograms()}")
logger.info(f"Number of bins: {input.blocksize()}")

# Check run properties
run_info = input.getRun()
if run_info.hasProperty('run_number'):
    run_number = run_info.getProperty('run_number').value
    logger.info(f"Run number: {run_number}")

# Your processing here
# ...

logger.info(f"Output workspace: {output.name()}")
logger.info("=== Processing Script Completed ===")
```

### Workspace Verification

Validate workspace state before operations:

```python
from mantid.simpleapi import mtd

def validate_workspace(ws_name):
    """Check if workspace is valid for processing"""
    if not mtd.doesExist(ws_name):
        raise ValueError(f"Workspace {ws_name} does not exist")

    ws = mtd[ws_name]

    if ws.getNumberHistograms() == 0:
        raise ValueError(f"Workspace {ws_name} has no histograms")

    if ws.blocksize() == 0:
        raise ValueError(f"Workspace {ws_name} has no bins")

    return ws

# Use in scripts
try:
    validate_workspace('input')
    # Processing continues
except ValueError as e:
    print(f"Validation failed: {e}")
    # Handle error appropriately
```

### Test Before Deploying

Always test scripts with fake server before production:

```bash
# Terminal 1: Start server
python test/fake_server.py

# Terminal 2: Test your script
cat > test/my_test.conf <<EOF
{
  "instrument": "ISIS",
  "listener": "ISISHistoDataListener",
  "script_dir": "/path/to/my/scripts"
}
EOF

python scripts/livereduce.py test/my_test.conf

# Watch for errors
tail -f livereduce.log | grep -i error
```

## Related Documentation

- [Architecture](architecture.md) - Understanding data flow
- [Developer Guide](developer-guide.md) - Production deployment
- [Processing Scripts](processing-scripts.md) - Script writing details
- [Configuration Reference](configuration.md) - All config options
- [Troubleshooting](troubleshooting.md) - Fixing problems
