#!/bin/bash
echo "ARGS $@"

# determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# determine the conda environment
CONDA_ENVIRON="mantid-dev"  # default
if [ -f "${CONFIG_FILE}" ]; then
    if grep -q CONDA_ENV "${CONFIG_FILE}"; then
        echo "Determine conda environment from \"${CONFIG_FILE}"\"
        CONDA_ENVIRON="$(/bin/jq --raw-output '.CONDA_ENV' ${CONFIG_FILE})"
    fi
fi

# remove font-cache to side step startup speed issue
rm -f ${HOME}/.cache/fontconfig/*

# location of this script
THISFILE=$(readlink -f "$0")
INSTALLDIR=$(dirname "${THISFILE}")   # directory of executable

# launch the application using nsd-conda-wrap.sh
NSD_CONDA_WRAP=$(which nsd-conda-wrap.sh)
if [ -z "${NSD_CONDA_WRAP}" ];then
    echo "Failed to find nsd-conda-wrap.sh"
    exit -1
fi
APPLICATION="${INSTALLDIR}/livereduce.py"
exec "${NSD_CONDA_WRAP}" "${CONDA_ENVIRON}" --classic python3 "${APPLICATION}" "$@"
