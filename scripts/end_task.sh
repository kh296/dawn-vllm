#!/bin/bash -l

# Script for ensuring ray cluster stopped, and for performing cleanup.
#
# This script can be sourced in a bash shell:
# source ./setup_slurm.sh
# or can be run:
# ./setup_slurm.sh

ray stop --grace-period 60 1>/dev/null 2>&1

# The command "ray stop" doesn't always stop GCS server proceses cleanly.
# Kill these explicitly, in practice stopping the ray cluster.
GCS_PIDS="$(pgrep -f 'gcs_server' || true)"
if [ ! -z ${GCS_PIDS} ]; then
    kill -9 ${GCS_PIDS}
fi

# Remove core dump(s) if present.
# A core dump seems to occur during normal vLLM termination.
rm -f core.*
