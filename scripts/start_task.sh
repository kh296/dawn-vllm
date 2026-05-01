# Script to perform environment setup, and to initiate ray cluster,
# prior to running vLLM application.
#
# This script can be sourced in a bash shell:
# source ./setup_slurm.sh

# Ensure PROJECT_HOME defined.
if [[ -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

if [[ "true" != "${PROJECT_ENVIRONMENT_SET}" ]]; then
    # Perform vLLM environment setup.
    source ${PROJECT_HOME}/scripts/setup_project.sh
fi
set --

if [[ "true" == "${PROJECT_ENVIRONMENT_SET}" ]]; then
    # Ensure Slurm environment variables set, and variables derived from these.
    if [[ -z "${IS_HEAD_NODE}" ]]; then
        source ${PROJECT_HOME}/scripts/setup_slurm.sh
    fi

    # As needed, initiate, or add to, ray cluster.
    if [[ "${SLURM_NNODES}" -gt 1 ]]; then
        if [[ ! -f "$0" || -z "${CONTAINER_LAUNCH}" || \
            ! -z "${APPTAINER_CONTAINER}" ]]; then
            ${PROJECT_HOME}/scripts/setup_ray.sh
        fi
    fi
fi
