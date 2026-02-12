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
# at ${CONDA_HOME}.  If not set by the user, CONDA_HOME
# defaults to ${HOME}/miniforge3.  For instructions for installing
# the Miniforge3 flavour of conda, see: https://conda-forge.org/download/
#
# After installation, the environment for using vLLM can
# be activated by sourcing the file vllm-setup.sh,
# created in the directory ../envs relative to where the current script is run.
#
# On Dawn, the current script may be run interactively on a compute node
# (not on a login node):
# bash ./vllm_install.sh
# or it may be submitted from a login node to the Slurm batch system:
# sbatch --account=<project account> ./vllm_install.sh
#

# Exit at first failure.
set -e

ENV_NAME="vllm"

# Determine system being used.
if [[ "$(hostname)" == "pvc-s"* ]]; then
    SYSTEM="Dawn"
elif [[ "${OSTYPE}" == "darwin"* ]]; then
    SYSTEM="macOS"
else
    echo "Installation of ${ENV_NAME} for ${OSTYPE} on $(hostname) not handled"
    echo "Exiting: $(date)"
fi
#
# Check that conda is available.
if [ -z "${CONDA_HOME}" ]; then
    if [ -z "${CONDA_PREFIX}" ]; then
        CONDA_HOME=${HOME}/miniforge3
    else
        CONDA_HOME=${CONDA_PREFIX}
    fi
fi

if ! [ -d "${CONDA_HOME}" ]; then
    echo "Conda installation not found at ${CONDA_HOME}"
    echo "Exiting: $(date)"
    exit 2
fi
#
# Perform installation.
echo "Installation of ${ENV_NAME} for ${OSTYPE} on $(hostname) started: $(date)"
T0=${SECONDS}

# Create script for environment setup.
ENVS_DIR=$(realpath ..)/envs
mkdir -p ${ENVS_DIR}
SETUP="${ENVS_DIR}/${ENV_NAME}-setup.sh"
DAWN_SETUP="/dev/null"
MACOS_SETUP="/dev/null"
if [[ "Dawn" == "${SYSTEM}" ]]; then
    DAWN_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/rds/hpc-work"
elif [[ "macOS" == "${SYSTEM}" ]]; then
    MACOS_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/local-store"
fi

cat <<EOF >${SETUP}
# Setup script for ${ENV_NAME} on ${SYSTEM}.
# Generated: $(date)

EOF

cat <<EOF >>${DAWN_SETUP}
# Load modules.
module purge
module load rhel9/default-dawn
module load intel-oneapi-ccl/2021.15.0

export ZE_FLAT_DEVICE_HIERARCHY="FLAT"
export ONEAPI_DEVICE_SELECTOR="level_zero:gpu;opencl:gpu"
export VLLM_TARGET_DEVICE="xpu"

EOF

cat <<EOF >>${MACOS_SETUP}
export VLLM_TARGET_DEVICE="cpu"

EOF

cat <<EOF >>${SETUP}
export HF_HOME="${LOCAL_STORE}"
export HF_HUB_CACHE="${LOCAL_STORE}"
export VLLM_CACHE_ROOT="${LOCAL_STORE}"
export VLLM_LOGGING_LEVEL="INFO"
#
# Initialise conda.
source $(realpath ${CONDA_HOME})/bin/activate

# Activate environment.
EOF

# Set up installation environment.
source ${SETUP}
conda update -n base -c conda-forge conda -y

# Delete any pre-existing environment.
if [ -d "${CONDA_HOME}/envs/${ENV_NAME}" ]; then
    conda env remove -n ${ENV_NAME} -y
fi

# Create and activate the environment.
conda create -n ${ENV_NAME} -y python=3.12
CMD="conda activate ${ENV_NAME}"
echo "${CMD}" >> "${SETUP}"
eval "${CMD}"

# Install additional packages.
PROJECTS_DIR=$(realpath ..)/projects
mkdir -p ${PROJECTS_DIR}
VLLM_HOME=${PROJECTS_DIR}/${ENV_NAME}
VLLM_VERSION="v0.15.1"
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

CMD="python -m pip install --upgrade pip"
echo ""
echo "Ensuring pip up to date:"
echo "${CMD}"
eval "${CMD}"

if [[ "macOS" != "${SYSTEM}" ]]; then
    CMD="python -m pip install -v -r requirements/${VLLM_TARGET_DEVICE}.txt"
else
    CMD="python -m pip install ."
fi
echo ""
echo "Installing packages:"
echo "${CMD}"
eval "${CMD}"

# Build and install for vLLM target device.
if [[ "macOS" != "${SYSTEM}" ]]; then
    CMD="python setup.py install"
    echo ""
    echo "Performing build and install for target device: ${VLLM_TARGET_DEVICE}"
    echo "${CMD}"
    eval "${CMD}"
fi

# Check installation by importing modules.
CMD="python -c 'from vllm import LLM, SamplingParams'"
echo ""
echo "Performing initial imports:"
echo "${CMD}"
eval "${CMD}"

echo ""
echo "Installation of ${ENV_NAME} for ${OSTYPE} on $(hostname) completed: $(date)"
echo "Installation time: $((${SECONDS}-${T0})) seconds"
