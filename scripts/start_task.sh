# Script to perform environment setup, and to initiate ray cluster,
# prior to running vLLM application.

# Ensure PROJECT_HOME defined.
if [[ -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

# Perform vLLM environment setup.
source ${PROJECT_HOME}/scripts/setup_project.sh "$1"
set --

# Ensure Slurm environment variables set, and variables derived from these.
source ${PROJECT_HOME}/scripts/setup_slurm.sh

# Initiate, or add to, ray cluster.
if [[ ${SLURM_NNODES} -gt 1 ]]; then
    ${PROJECT_HOME}/scripts/setup_ray.sh
fi
