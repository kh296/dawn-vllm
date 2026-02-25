# Script to perform project setup, including setting the environment variables
# PATH and LD_LIBRARY_PATH as needed.
#
# This script can be sourced in a bash shell:
#     source ./setup_project.sh [conda env]

# Ensure PROJECT_HOME defined.
if [[ ! -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

# Perform environment setup.
if [[ -n $1 ]]; then
    CONDA_ENV="$1"
fi
if [[ -z "${CONDA_ENV}" ]]; then
    CONDA_ENV="vllm"
fi
SETUP_SCRIPT="${PROJECT_HOME}/envs/${CONDA_ENV}-setup.sh"
unset CONDA_ENV
set --
SETUP=(source ${SETUP_SCRIPT})
echo ""
echo ${SETUP[@]}
echo ""
"${SETUP[@]}"
