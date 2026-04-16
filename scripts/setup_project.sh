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
VLLM_CMD=""
if [[ "${OSTYPE}" == "darwin"* ]]; then
    HF_MODEL="Qwen/Qwen3-0.6B"
else
    HF_MODEL="Qwen/Qwen3-4B"
fi

usage() {
    if [[ -z "${SETUP_LAUNCH}" ]]; then
        if [[ -f "$0" ]]; then
            SETUP_LAUNCH="$(basename $0)"
        else
            SETUP_LAUNCH="source $(basename ${BASH_SOURCE})"
        fi
    fi
    if [[ -z "${SETUP_INFO}" ]]; then
        SETUP_INFO="Set up vLLM environment."
    fi
    if [[ "true" == "${NO_RUN_OPTION}" ]]; then
        RUN_OPTION=""
    else
        RUN_OPTION=" [-r [<command or shortcut>]]"
    fi
    echo ""
    echo \
    "usage: ${SETUP_LAUNCH} [-h] [-c [<conda env>]] [-a [<container image>]]${RUN_OPTION} [-m [<model identifier]]"
    echo ""
    echo "${SETUP_INFO}"
    echo ""
    echo "Options:"
    echo "    -h: Print this help."
    echo "    -c: Use conda environment <conda env>."
    echo "    -a: Use apptainer image at path <image path>."
    if [[ ! -z "${RUN_OPTION}" ]]; then
        echo \
        "    -r: Set environment variable VLLM_CMD to <command or shortcut>."
    fi
    echo "    -m: Set environment variable HF_MODEL to <model identifier>."
    echo "If <conda env> not specified, defaults to: \"${CONDA_ENV}\"."
    echo \
    "If <container image> not specified, defaults to: \"${CONTAINER_IMAGE}\"."
    echo "If both -c and -a specified, or if neither of -c and -a specified,"
    echo "    first try using conda environment, and only if unsuccessful"
    echo "    try using apptainer image."
    echo "If -c specified and -a unspecified, only try using conda environment."
    echo "If -a specified and -c unspecified, only try using apptainer image."
    if [[ ! -z "${RUN_OPTION}" ]]; then
        echo "If <command or shortcut> specified, it should correspond to"
        echo "    a command that can be run in the vLLM environment,"
        echo "    or to a user-defined shortcut for such a command."
        echo "    If it includes spaces, it should be enclosed in quotes."
        echo "If -r unspecified, or <command or shortcut> unspecified",
        echo "    the environment variable VLLM_CMD is set to \"${VLLM_CMD}\"."
    fi
    echo "If <model identifier> specified, it should correspond to"
    echo "    the identifier of a Hugging Face Model, or to the local path"
    echo "    to such a model."
    echo "If -m unspecified, or <model identifier> unspecified",
    echo "    the environment variable HF_MODEL is set to \"${HF_MODEL}\"."
    echo "The environment variables VLLM_CMD and HF_MODEL should be handled"
    echo "    in the user's run script (run_vllm_single.sh or similar)."
    echo ""
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
        -r)
            if [[ -n "$2" && "$2" != -* ]]; then
                VLLM_CMD="$2"
                shift 2
            else
                shift 1
            fi
            ;;
        -m)
            if [[ -n "$2" && "$2" != -* ]]; then
                HF_MODEL="$2"
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
    export VLLM_CMD
    export HF_MODEL

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
