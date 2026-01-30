#!/bin/bash
echo "ARGS $*"

# determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# determine the pixi environment
PIXI_ENVIRON="mantid_dev"  # default
if [ -f "${CONFIG_FILE}" ]; then
    if grep -q PIXI_ENV "${CONFIG_FILE}"; then
        echo "Determine pixi environment from \"${CONFIG_FILE}\""
        PIXI_ENVIRON="$(/bin/jq --raw-output '.PIXI_ENV' "${CONFIG_FILE}")"
    elif grep -q CONDA_ENV "${CONFIG_FILE}"; then  # backward compatibility
        echo "Determine pixi environment from CONDA_ENV entry in \"${CONFIG_FILE}\""
        CONDA_ENVIRON="$(/bin/jq --raw-output '.CONDA_ENV' "${CONFIG_FILE}")"
        if [[ "${CONDA_ENVIRON}" == *-dev ]]; then  # substitute dash for underscore in dev/qa suffix
            PIXI_ENVIRON="${CONDA_ENVIRON%-dev}_dev"
        elif [[ "${CONDA_ENVIRON}" == *-qa ]]; then
            PIXI_ENVIRON="${CONDA_ENVIRON%-qa}_qa"
        else
            PIXI_ENVIRON="${CONDA_ENVIRON}"
        fi
    fi
fi

# remove font-cache to side step startup speed issue
rm -f "${HOME}"/.cache/fontconfig/*

# location of livereduce.py and nsd-app-wrap.sh
THISFILE=$(readlink -f "$0")  # absolute path of this script
INSTALLDIR=$(dirname "${THISFILE}")
APPLICATION="${INSTALLDIR}/livereduce.py"
NSD_APP_WRAP="${INSTALLDIR}/nsd-app-wrap.sh"  # assumes nsd-app-wrap.sh in the same directory
if [ -z "${NSD_APP_WRAP}" ];then
    echo "Failed to find nsd-app-wrap.sh"
    exit 1
fi

# Tell shellcheck where to find the sourced script for static analysis
# shellcheck source=./nsd-app-wrap.sh
# Disable SC1091 (file not found) since the path is resolved at runtime
# shellcheck disable=SC1091
. "${NSD_APP_WRAP}"  # load bash function `pixi_launch`
pixi_launch "${PIXI_ENVIRON}" python "${APPLICATION}" "$@"
