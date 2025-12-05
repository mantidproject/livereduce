#!/bin/bash
echo "ARGS $*"

# determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# Check if the configuration file exists
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "ERROR: Config file '${CONFIG_FILE}' not found." >&2
    exit 1
fi

# --- CONFIG ---
WATCHDOG_TARGET="/var/log/SNS_applications/livereduce.log"
MANAGED_SERVICE="livereduce.service"
# Default values
DEFAULT_INTERVAL=60
DEFAULT_THRESHOLD=300
# How often we check WATCHDOG_TARGET. Default is 60 seconds.
INTERVAL="$(/bin/jq --raw-output '.watchdog.interval // 60' "${CONFIG_FILE}")"
# Inactivity threshold. Default is 300 seconds.
THRESHOLD="$(/bin/jq --raw-output '.watchdog.threshold // 300' "${CONFIG_FILE}")"

# Validate INTERVAL is a positive integer, otherwise use default
if ! [[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARNING: Invalid INTERVAL value '$INTERVAL'. Using default: $DEFAULT_INTERVAL" >&2
  INTERVAL=$DEFAULT_INTERVAL
fi
# Validate THRESHOLD is a positive integer, otherwise use default
if ! [[ "$THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARNING: Invalid THRESHOLD value '$THRESHOLD'. Using default: $DEFAULT_THRESHOLD" >&2
  THRESHOLD=$DEFAULT_THRESHOLD
fi

WATCHDOG_LOG="/var/log/SNS_applications/livereduce_watchdog.log"
# Track when we last issued a restart so we don't keep restarting every loop
last_restart=0

# Infinite loop
while true; do

  if [[ ! -e "$WATCHDOG_TARGET" ]]; then
    echo "$(date --iso-8601=seconds) ERROR: '$WATCHDOG_TARGET' not found." >> "$WATCHDOG_LOG"

  else
    # Get file mtime (epoch seconds) and current time
    last_mod=$(stat -c %Y "$WATCHDOG_TARGET")
    now=$(date +%s)
    age=$(( now - last_mod ))

    if (( age >= THRESHOLD )); then
      # Only restart if we haven't already done so in this inactivity window
      since_restart=$(( now - last_restart ))
      if (( since_restart >= THRESHOLD )); then
        {
          echo -e "\n#############################################################################"
          echo "$(date --iso-8601=seconds) No change for $age s in $WATCHDOG_TARGET"
          echo "---- Last 20 lines of $WATCHDOG_TARGET before restart:"
          tail -n 20 "$WATCHDOG_TARGET"
          echo -e "\nrestarting $MANAGED_SERVICE."
        } >> "$WATCHDOG_LOG"
        # Restart the service (use systemctl or service as appropriate)
        if command -v systemctl &>/dev/null; then
          systemctl restart "$MANAGED_SERVICE"
          sleep 5 # give it a moment to start
          systemctl status "$MANAGED_SERVICE" >> "$WATCHDOG_LOG"
        else
          service "$MANAGED_SERVICE" restart
          sleep 5 # give it a moment to start
          service "$MANAGED_SERVICE" status >> "$WATCHDOG_LOG"
        fi
        last_restart=$now
      fi
    fi
  fi

  sleep "$INTERVAL"
done
