#!/bin/bash -l

# Script for ensuring ray cluster stopped, and for performing cleanup.

# The command "ray stop" doesn't always stop GCS server proceses cleanly.
# Kill these explicitly, in practice stopping the ray cluster.
GCS_PIDS="$(pgrep -f 'gcs_server')"
if [ ! -z ${GCS_PIDS} ]; then
    kill -9 ${GCS_PIDS}
fi

# Remove core dump(s) if present.
# A core dump seems to occur during normal vLLM termination.
rm -f core.*
