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

# Parse command-line options.
TRY_SETUP="true"
CONDA_FLAG="false"
CONDA_ENV="vllm"
CONTAINER_FLAG="false"
CONTAINER_IMAGE=\
$(ls ${PROJECT_HOME}/apptainer/vllm*.sif 2>/dev/null | head -n 1)

usage() {
    if [[ -z "${SETUP_LAUNCH}" ]]; then
        if [[ -f "$0" ]]; then
            SETUP_LAUNCH="$(basename $0)"
        else
            SETUP_LAUNCH="source $(basename ${BASH_SOURCE})"
        fi
    fi
    if [[ -z "${SETUP_INFO}" ]]; then
        SETUP_INFO="    Set up vLLM environment."
    fi
    echo \
    "usage: ${SETUP_LAUNCH} [-h] [-c [<conda e0nv>]] [-a0 0[<container image>]]"
    echo "${SETUP_INFO}"
    echo "Options:"
    echo "    -h: Print this help."
    echo "    -c: Use conda environment <conda env>."
    echo "    -a: Use apptainer image at path <image path>."
    echo "If <conda env> not specified, defaults to: \"${CONDA_ENV}\"."
    echo \
    "If <container image> not specified, defaults to: \"${CONTAINER_IMAGE}\"."
    echo "If both -c and -a specified, or if neither of -c and -a specified,"
    echo "    first try using conda environment, and only if unsuccessful"
    echo "    try using apptainer image."
    echo "If -c specified and -a unspecified, only try using conda environment."
    echo "If -a specified and -c unspecified, only try using apptainer image."
    unset SETUP_LAUNCH
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
	    TRY_SETUP="false"
	    break
            ;;
        -c)
            CONDA_FLAG="true"
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_ENV="$2"
		shift 2
            else
                shift 1
            fi
            ;;
        -a)
            CONTAINER_FLAG="true"
            if [[ -n "$2" && "$2" != -* ]]; then
                CONTAINER_IMAGE="$2"
                shift 2
            else
                shift 1
            fi
            ;;
        -*)
            echo "Unknown option: $1"
            usage
	    TRY_SETUP="false"
	    break
            ;;
    esac
done

# Perform environment setup.
export PROJECT_ENVIRONMENT_SET="false"
if [[ "true" == "${TRY_SETUP}" ]]; then

    if [[ "true" == "${CONDA_FLAG}" || "false" == "${CONTAINER_FLAG}" ]]
    then
       SETUP_SCRIPT="${PROJECT_HOME}/envs/${CONDA_ENV}-setup.sh"
        if [[ -f "${SETUP_SCRIPT}" ]]; then
            set --
            SETUP=(source "${SETUP_SCRIPT}")
            echo ""
            echo "${SETUP[@]}"
            echo ""
            "${SETUP[@]}"
            export PROJECT_ENVIRONMENT_SET="true"
	    CONDA_FLAG="true"
        fi
    fi

    if [[ "true" == "${CONTAINER_FLAG}" || "false" == "${CONDA_FLAG}" ]]
    then
        if [[ -f "${CONTAINER_IMAGE}" ]]; then
            module purge
            module load rhel9/default-dawn
            export CCL_TOPO_FABRIC_VERTEX_CONNECTION_CHECK=0
            export FI_PROVIDER="tcp"
	    if [[ -z "${ZE_FLAT_DEVICE_HIERARCHY}" ]]; then
                export ZE_FLAT_DEVICE_HIERARCHY="FLAT"
	    fi 
            export VLLM_USE_V1=1
            export VLLM_WORKER_MULTIPROC_METHOD="spawn"
            export W_LONG_MAX_MODEL_LEN=1
            export CONTAINER_LAUNCH="apptainer exec ${CONTAINER_IMAGE} "
            export PROJECT_ENVIRONMENT_SET="true"
        fi
    fi

fi
