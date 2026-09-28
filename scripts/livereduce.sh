#!/usr/bin/bash
echo "ARGS $*"

# determine the configuration file
if [ $# -ge 1 ]; then
    CONFIG_FILE="${1}"
else
    CONFIG_FILE=/etc/livereduce.conf
fi

# determine the pixi environment
export PIXI_PREFIX=/var/tmp/share
export PIXI_ENVIRON=v2.19.0	# /var/tmp/share/mr_reduction:v2.19.0 restoration
export PIXI_FROZEN=true
export PIXI_CACHE_DIR=${PIXI_PREFIX}/${PIXI_ENVIRON}/.cache
git config --global --add safe.directory ${PIXI_PREFIX}/${PIXI_ENVIRON}

# remove font-cache to side step startup speed issue
rm -f "${HOME}"/.cache/fontconfig/*

# location of livereduce.py and nsd-app-wrap.sh
##APPLICATION=/usr/bin/livereduce.py
APPLICATION=/var/tmp/livereduce.py
TRACE_OUT=$(mktemp -u)-${PIXI_ENVIRON}.trace
##NSD_APP_WRAP="$(which nsd-app-wrap.sh 2>/dev/null || true)"
##if [ -z "${NSD_APP_WRAP}" ]; then
##    echo "Failed to find nsd-app-wrap.sh"
##    exit 1
##fi

# Tell shellcheck where to find the sourced script for static analysis
# shellcheck source=./nsd-app-wrap.sh
# Disable SC1091 (file not found) since the path is resolved at runtime
# shellcheck disable=SC1091
##. "${NSD_APP_WRAP}"  # load bash function `pixi_launch`
##pixi_launch "${PIXI_ENVIRON}" python "${APPLICATION}" "$@"

# https://github.com/fractal-analytics-platform/fractal-server/issues/2638
# https://github.com/prefix-dev/pixi/discussions/2681
source ${PIXI_PREFIX}/${PIXI_ENVIRON}/activate.sh
if [ ! -z "${TRACE_OUT}" ] ; then
	echo "Tracing to ${TRACE_OUT}"
	#( umask 0002 && ${PIXI_PREFIX}/${PIXI_ENVIRON}/.pixi/envs/default/bin/python -m trace --trace ${APPLICATION} > ${TRACE_OUT} )
	( PIXI_PREFIX=/var/tmp/share PIXI_ENVIRON=v2.19.0 PIXI_FROZEN=true PIXI_CACHE_DIR=/var/tmp/share/v2.19.0/.cache source /var/tmp/share/v2.19.0/activate.sh && /var/tmp/share/v2.19.0/.pixi/envs/default/bin/python -m trace --trace /usr/bin/livereduce.py > "${TRACE_OUT}" )
else
	${PIXI_PREFIX}/${PIXI_ENVIRON}/.pixi/envs/default/bin/python ${APPLICATION}
fi
