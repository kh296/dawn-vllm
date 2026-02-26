#!/bin/bash
#SBATCH --job-name=vllm_install # create a name for your job
#SBATCH --output=%x.log         # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:1            # number of allocated gpus per node
#SBATCH --time=04:00:00         # total run time limit (HH:MM:SS)

# Script for installing vLLM on the Dawn supercomputer.
#
# This installation relies on the user having a conda installation
# at ${CONDA_HOME}.  If CONDA_HOME is null but CONDA_PREFIX is non-null,
# the former is set to be equal to the latter.  If both CONDA_HOME and
# CONDA_PREFIX are null, CONDA_HOME is set to ${HOME}/miniforge3.  In this
# case, if conda isn't available at ${HOME}/miniforge 3 then, on Dawn,
# the Miniforge3 flavour of conda will be installed to
# ${HOME}/rds/hpc-work/miniforge3, and this directory will be linked
# to ${HOME}/miniforge3.  For information about the Miniforge3 flavour
# of conda, see: https://conda-forge.org/download/
#
# After installation, if the environment variable CONDA_ENV isn't set
# before starting this, the environment for using vLLM can
# be activated by sourcing the file vllm-setup.sh,
# created in the directory ../envs relative to where the current script is run.
# Otherwise, the file to source is ../envs/${CONDA_ENV}-setup.sh
#
# On Dawn, the current script may be run interactively on a compute node
# (not on a login node):
# bash ./vllm_install.sh
# or it may be submitted from a login node to the Slurm batch system:
# sbatch --account=<project account> ./vllm_install.sh
#

# Exit at first failure.
set -e

PROJECT_NAME="vLLM"
PROJECT_NAME_LC="$(echo ${PROJECT_NAME} | tr [:upper:] [:lower:])"

# Parse command-line options.
usage() {
    echo "usage: vllm_install.sh [-h] [-c <conda home>] [-e <conda env>]"
    echo "    Install vLLM in a conda environment."
    echo "Options:"
    echo "    -h: Print this help."
    echo "    -c: Use conda installation at <conda home>."
    echo "    -e: Create, and install to, conda environment <conda env>."
    echo "If -c omitted, path to conda installation is first non-empty string from:"
    echo "    \"\${CONDA_HOME}\", \"\${CONDA_PREFIX}\", \"\${HOME}/miniforge3\""
    echo "    If last of these is selected, conda will be installed here"
    echo "    if not already present."
    echo "If -e omitted, name for conda environment defaults to \"${PROJECT_NAME_LC}\"."
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
	    exit 0
            ;;
        -c)
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_HOME="$2"
		shift 2
            else
                echo "-c must be followed by path to conda installation"
                usage
		exit 1
            fi
            ;;
        -e)
            if [[ -n "$2" && "$2" != -* ]]; then
                CONDA_ENV="$2"
                shift 2
            else
                echo "-e must be followed by name of conda environment"
                exit 1
            fi
            ;;
        -*)
            echo "Unknown option: $1"
            usage
	    exit 1
            ;;
    esac
done

if [[ -z "${CONDA_ENV}" ]]; then
    CONDA_ENV=${PROJECT_NAME_LC}
fi

# Determine system being used.
if [[ "$(hostname)" == "pvc-s"* ]]; then
    SYSTEM="Dawn"
elif [[ "${OSTYPE}" == "darwin"* ]]; then
    SYSTEM="macOS"
else
    echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) not handled"
    echo "Exiting: $(date)"
    exit
fi

# Check that conda is available.
if [ -z "${CONDA_HOME}" ]; then
    if [ -z "${CONDA_PREFIX}" ]; then
        CONDA_HOME="${HOME}/miniforge3"
        if ! [ -d "${CONDA_HOME}" ]; then
            ./miniforge3_install.sh
        fi
    else
        CONDA_HOME="${CONDA_PREFIX}"
    fi
fi

# Expand path, without following symbolic links.
CONDA_HOME="${CONDA_HOME/#\~/${HOME}}"
CONDA_HOME=$(cd "$(dirname "${CONDA_HOME}")" && pwd -P)/$(basename "${CONDA_HOME}")

if ! [ -d "${CONDA_HOME}" ]; then
    echo "Conda installation not found at ${CONDA_HOME}"
    echo "Exiting: $(date)"
    exit 2
fi

# Perform installation.
echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) started: $(date)"
T0=${SECONDS}

# Create script for environment setup.
ENVS_DIR=$(realpath ..)/envs
mkdir -p ${ENVS_DIR}
SETUP="${ENVS_DIR}/${CONDA_ENV}-setup.sh"
DAWN_SETUP="/dev/null"
MACOS_SETUP="/dev/null"
if [[ "Dawn" == "${SYSTEM}" ]]; then
    DAWN_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/rds/hpc-work/vllm"
elif [[ "macOS" == "${SYSTEM}" ]]; then
    MACOS_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/local-store/vllm"
fi

cat <<EOF >${SETUP}
# Setup script for ${CONDA_ENV} on ${SYSTEM}.
# Generated: $(date)

EOF

cat <<EOF >>${DAWN_SETUP}
# Load modules.
module purge
module load rhel9/default-dawn
module load intel-oneapi-ccl/2021.15.0

export CCL_ATL_SHM=1
export ZE_FLAT_DEVICE_HIERARCHY="FLAT"
export ONEAPI_DEVICE_SELECTOR="level_zero:gpu;opencl:gpu"
export VLLM_HOST_IP="\$(getent hosts \$(hostname) | cut -d' ' -f1)"
export VLLM_TARGET_DEVICE="xpu"
EOF

cat <<EOF >>${MACOS_SETUP}
export GLOO_SOCKET_IFNAME="en0"
export VLLM_HOST_IP="127.0.0.1"
export VLLM_TARGET_DEVICE="cpu"
EOF

cat <<EOF >>${SETUP}
export VLLM_CACHE_ROOT="${LOCAL_STORE}"
export VLLM_LOGGING_LEVEL="INFO"
export VLLM_USE_V1=1
export VLLM_WORKER_MULTIPROC_METHOD="spawn"
export W_LONG_MAX_MODEL_LEN=1
export HF_HOME="${LOCAL_STORE}"
export HF_HUB_CACHE="${LOCAL_STORE}"

# Initialise conda.
source ${CONDA_HOME}/bin/activate

# Activate environment.
EOF

# Set up installation environment.
source ${SETUP}
conda update -n base -c conda-forge conda -y

# Delete any pre-existing environment.
if [ -d "${CONDA_HOME}/envs/${CONDA_ENV}" ]; then
    conda env remove -n ${CONDA_ENV} -y
fi

# Create and activate the environment.
conda create -n ${CONDA_ENV} -y python=3.12
CMD="conda activate ${CONDA_ENV}"
echo "${CMD}" >> "${SETUP}"
eval "${CMD}"

# Install additional packages.
PROJECTS_DIR=$(realpath ..)/projects
mkdir -p ${PROJECTS_DIR}
VLLM_HOME=${PROJECTS_DIR}/${PROJECT_NAME_LC}
# Choose latest vLLM version that uses torch 2.9.1.
if [[ "Dawn" == "${SYSTEM}" ]]; then
    VLLM_VERSION="v0.15.1"
elif [[ "macOS" == "${SYSTEM}" ]]; then
    VLLM_VERSION="v0.14.1"
fi
rm -rf ${VLLM_HOME}
mkdir -p ${VLLM_HOME}
CMD="git clone https://github.com/vllm-project/vllm.git ${VLLM_HOME}"
echo ""
echo "Cloning vLLM repository, checking out version ${VLLM_VERSION}:"
echo "${CMD}"
eval "${CMD}"

cd ${VLLM_HOME}
CMD="git checkout ${VLLM_VERSION}"
echo "${CMD}"
eval "${CMD}"

# Installation based on instructions for build from source at:
# https://docs.vllm.ai/en/stable/getting_started/installation/
CMD="python -m pip install --upgrade pip"
echo ""
echo "Ensuring pip up to date:"
echo "${CMD}"
eval "${CMD}"

echo ""
echo "Performing installation for target device '${VLLM_TARGET_DEVICE}':"
CMD="python -m pip install -v -r requirements/${VLLM_TARGET_DEVICE}.txt"
echo "${CMD}"
eval "${CMD}"

CMD="python -m pip install -v -e ."
if [[ "Dawn" == "${SYSTEM}" ]]; then
    CMD="${CMD} --no-build-isolation"
fi
echo ""
echo "${CMD}"
eval "${CMD}"

# Check installation by importing modules.
CMD="python -c 'from vllm import LLM, SamplingParams'"
echo ""
echo "Performing initial imports:"
echo "${CMD}"
eval "${CMD}"

echo ""
echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) completed: $(date)"
echo "Installation time: $((${SECONDS}-${T0})) seconds"

echo ""
echo "Set up environment for ${PROJECT_NAME} with:"
echo "source ${SETUP}"
