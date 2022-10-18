#!/bin/bash
/usr/bin/echo "LIVE REDUCE for user $USER"
CONDA_ENV=$(/bin/jq --raw-output '.CONDA_ENV' /etc/livereduce.conf)
/usr/bin/echo "CONDA_ENV = ${CONDA_ENV}"
#
PYTHON_VERSION=$(/bin/which python3)
/usr/bin/echo "Before Conda: ${PYTHON_VERSION}" # echoes /usr/bin/python3
#
source /home/jbq/repositories/code.ornl.gov/sns-hfir-scse/infrastructure/nsd-app-wrap/nsd-app-wrap.sh
APPLICATION=/home/jbq/repositories/GitHub/mantidproject/livereduce/scripts/which_python.py
args=("${CONDA_ENV}" "python3" "$APPLICATION" "")
activate_and_launch "${args[@]}"
#source /home/jbq/.local/opt/mambaforge/bin/activate ""
#/home/jbq/.local/opt/mambaforge/bin/conda activate "${CONDA_ENV}"
#PYTHON_VERSION=$(/bin/which python3)
#/usr/bin/echo "After Conda: ${PYTHON_VERSION}"

