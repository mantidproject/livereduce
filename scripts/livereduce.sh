#!/bin/bash

CONDA_ENVIRON="$(/bin/jq --raw-output '.CONDA_ENV' /etc/livereduce.conf)"
if test -z "${CONDA_ENVIRON}";then
  CONDA_ENVIRON="mantid-dev"
fi

# remove font-cache to side step startup speed issue
rm -f ${HOME}/.cache/fontconfig/*

# initialize conda and launch the application
source $(locate nsd-app-wrap.sh)
APPLICATION=/usr/bin/livereduce.py
args=("${CONDA_ENVIRON}" "python3" "$APPLICATION" "")
activate_and_launch "${args[@]}"
