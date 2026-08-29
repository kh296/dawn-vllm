#!/bin/bash
#SBATCH --job-name=vllm_install # create a name for your job
#SBATCH --output=%x_%j.log      # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:1            # number of allocated gpus per node
#SBATCH --time=02:00:00         # total run time limit (HH:MM:SS)

# Script for installing vLLM on the Dawn supercomputer.
#
# This installation relies on the user having a conda installation
# at ${CONDA_HOME}.  If CONDA_HOME is null but CONDA_PREFIX is non-null,
# the former is set to be equal to the latter.  If both CONDA_HOME and
# CONDA_PREFIX are null, CONDA_HOME is set to ${HOME}/miniforge3.  In this
# case, if conda isn't available at ${HOME}/miniforge3 then
# the Miniforge3 flavour of conda will be installed by running
# ./miniforge3_install.sh with default settings.
# For information about the Miniforge3 flavour
# of conda, see: https://conda-forge.org/download/
# For information about ./miniforge3_install.sh, use:
# ./miniforge3_install.sh -h
#
# After installation, if the environment variable CONDA_ENV wasn't set,
# the environment for using vLLM can be activated by sourcing the file
# vllm-setup.sh, created in the directory ../envs relative to where
# the current script is run.  Otherwise, the file to source is
# ../envs/${CONDA_ENV}-setup.sh
#
# On Dawn, the current script may be run interactively on a compute node
# (not on a login node):
# bash ./vllm_install.sh
# or it may be submitted from a login node to the Slurm batch system:
# sbatch --account=<project account> ./vllm_install.sh

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
    echo "If -e omitted, the name for the conda environment defaults to \"${PROJECT_NAME_LC}\"."
    echo "Any pre-existing conda environment <conda env> (specified with -e)"
    echo "    or \"${PROJECT_NAME_LC}\" (-e omitted) will be removed."
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
elif [[ "$(hostname)" == *"gpu-u"* ]]; then
    SYSTEM="Zenith"
elif [[ "$(hostname)" == *"-pl1"* ]]; then
    SYSTEM="aac6"
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
else
    CONDA_HOME=$(realpath ${CONDA_HOME})
fi

# Ensure cargo directory defined.
if [ -z "${CARGO_HOME}" ]; then
    RUSTC_PATH="$(echo $(command -v rustc))"
    if [ -z "${RUSTC_PATH}" ]; then
        CARGO_HOME="${HOME}/.cargo"
    else
        CARGO_HOME=$(dirname $(dirname "${RUSTC_PATH}"))
    fi
fi

# Perform installation.
echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) started: $(date)"
if [[ -f "/etc/os-release" ]]; then
    echo "Linux flavour:\
 $(echo $(cat /etc/os-release | grep 'PRETTY_NAME' | cut -d '"' -f 2))"
fi
T0=${SECONDS}

# Create script for environment setup.
ENVS_DIR=$(realpath ..)/envs
mkdir -p ${ENVS_DIR}
SETUP="${ENVS_DIR}/${CONDA_ENV}-setup.sh"
DAWN_SETUP="/dev/null"
ZENITH_SETUP="/dev/null"
AAC6_SETUP="/dev/null"
MACOS_SETUP="/dev/null"
if [[ "Dawn" == "${SYSTEM}" ]]; then
    DAWN_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/rds/hpc-work/vllm"
elif [[ "Zenith" == "${SYSTEM}" ]]; then
    ZENITH_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/rds/hpc-work/vllm"
elif [[ "aac6" == "${SYSTEM}" ]]; then
    AAC6_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/local-store/vllm"
elif [[ "macOS" == "${SYSTEM}" ]]; then
    MACOS_SETUP="${SETUP}"
    LOCAL_STORE="${HOME}/local-store/vllm"
fi

rm -rf ${SETUP}
cat <<EOF > ${SETUP}
# Setup script for ${CONDA_ENV} on ${SYSTEM}.
# Generated on $(hostname), $(date +"%Y-%m-%d (%a) %H:%M:%S %Z").

EOF

cat <<EOF >> ${DAWN_SETUP}
# Load modules.
module purge
module load rhel9/default-dawn
#module load intel-oneapi-ccl/2021.15.0
#module load intel-oneapi-compilers/2025.1.0
#source /usr/local/dawn/software/external/intel-oneapi/2026.0.0/setvars.sh
#source /usr/local/dawn/software/external/intel-oneapi/2025.3/setvars.sh
#source /usr/local/dawn/software/external/intel-oneapi/2025.3.1/setvars.sh
source /usr/local/dawn/software/external/intel-oneapi/2025.2.1/setvars.sh

if [[ -z "${ZE_FLAT_DEVICE_HIERARCHY}" ]]; then
    export ZE_FLAT_DEVICE_HIERARCHY="FLAT"
fi 
export CCL_ATL_SHM=1
export ONEAPI_DEVICE_SELECTOR="level_zero:gpu;opencl:gpu"
export VLLM_HOST_IP="\$(getent hosts \$(hostname) | cut -d' ' -f1)"
export VLLM_TARGET_DEVICE="xpu"
EOF

cat <<EOF >> ${ZENITH_SETUP}
# Load modules.
module purge
module load rhel9/mi355x/base
module load openmpi

# Record system characteristics.
export VLLM_TARGET_DEVICE="rocm"
export PYTORCH_ROCM_ARCH="gfx950"

# Ensure number of visible devices defined.
if [[ -z "\${HIP_VISIBLE_DEVICES}" ]]; then
    export HIP_VISIBLE_DEVICES="\${ROCR_VISIBLE_DEVICES}"
fi

# Set VLLM logging level
export VLLM_LOGGING_LEVEL="INFO"

# Enable Flash Attention.
export FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE
EOF

cat <<EOF >>${AAC6_SETUP}
# Load modules.
module purge
module load rocm
module load openmpi

# Set network interface for communication:
# https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/env.html#nccl-socket-ifname
# Possibilities for listing network interfaces include:
# Linux: ip addr, netstat -i, ifconfig
# MacOS: networksetup -listallhardwarereports, netstat -i, ifconfig
export NCCL_SOCKET_IFNAME="enp129s0"
EOF

cat <<EOF >>${MACOS_SETUP}
export GLOO_SOCKET_IFNAME="en0"
export VLLM_CPU_KVCACHE_SPACE=4
export VLLM_HOST_IP="127.0.0.1"
export VLLM_TARGET_DEVICE="cpu"
EOF

if [[ -f "${CARGO_HOME}/env" ]]; then
cat <<EOF >>${SETUP}

# Initialise rust.
source ${CARGO_HOME}/env
EOF
fi

cat <<EOF >>${SETUP}

# Initialise conda.
source ${CONDA_HOME}/bin/activate

# Activate environment.
EOF

# Set up installation environment.
source ${SETUP}

# Delete any pre-existing environment.
if [ -d "${CONDA_HOME}/envs/${CONDA_ENV}" ]; then
    rm -rf ${CONDA_HOME}/envs/${CONDA_ENV}
fi

# Create and activate the environment.
# Set upper and lower version limits for selected packages.
# For fastapi issue, see:
# https://github.com/trallnag/prometheus-fastapi-instrumentator/issues/370
if [[ "Zenith" == "${SYSTEM}" ]]; then
    CMD="conda create -n ${CONDA_ENV} -y python=3.12 libdrm"
else
    CMD="conda create -n ${CONDA_ENV} -y python=3.12\
 'setuptools>=77.0.3,<81.0.0' 'fastapi>=0.115.0,<0.137.0'" 
fi
echo ""
echo "${CMD}"
eval "${CMD}"
CMD="conda activate ${CONDA_ENV}"
echo "${CMD}" >> "${SETUP}"
eval "${CMD}"

CMD="python -m pip install --upgrade pip"
echo ""
echo "Ensuring pip up to date:"
echo "${CMD}"
eval "${CMD}"
echo ""

# Install additional packages.
PROJECTS_DIR=$(realpath ..)/projects
mkdir -p ${PROJECTS_DIR}
VLLM_HOME=${PROJECTS_DIR}/${PROJECT_NAME_LC}
if [[ -z "${VLLM_VERSION}" ]]; then
    if [[ "Dawn" == "${SYSTEM}" ]]; then
        VLLM_VERSION="v0.15.1"
    elif [[ "Zenith" == "${SYSTEM}" ]]; then
        VLLM_VERSION="v0.27.1"
    elif [[ "aac6" == "${SYSTEM}" ]]; then
        VLLM_VERSION="v0.15.1"
    elif [[ "macOS" == "${SYSTEM}" ]]; then
        VLLM_VERSION="v0.20.2"
    fi
fi

if [[ "Zenith" == "${SYSTEM}" ]]; then
    # Installation based on instructions for ROCm at:
    # https://rocm.docs.amd.com/projects/ai-ecosystem/en/latest/inference/vllm.html?fam=instinct&vllm-ver=0.23&i=pip&w=compute&gpu=mi355x&gfx=gfx950
    echo "Performing installation for ROCm."
    ROCM_VLLM="https://rocm.frameworks.amd.com/whl-multi-arch/vllm-cdna"
    AITER_HOME="${PROJECTS_DIR}/aiter"
    AMD_SMI_SYSTEM="/software/externals/rocm/rocm-7.14/share/amd_smi"
    AMD_SMI_HOME="${PROJECTS_DIR}/amd_smi"
    CMDS=(
        # Install uv.
        "python -m pip install uv"
        # Install PyTorch.
        "uv pip install --index-url https://repo.amd.com/rocm/whl-multi-arch/\
 torch[device-gfx950]==2.11.0+rocm7.14.0\
 torchvision[device-gfx950]==0.26.0+rocm7.14.0"
        # Install Flash Attention.
#        "uv pip install ${ROCM_VLLM}/flash-attn/\
#flash_attn-2.8.3-cp314-cp314-linux_x86_64.whl"
        "uv pip install https://wheels.vllm.ai/rocm/\
6e448d0ea9bf3d88d898b65449ca6dc2aec170ac/\
flash_attn-2.8.3-cp312-cp312-manylinux_2_34_x86_64.whl"
        # Install AITER.
#"uv pip install ${ROCM_VLLM}/amd-aiter/\
#amd_aiter-0.1.13.post2.dev1%2Bgb32deb267-cp314-cp314-linux_x86_64.whl"
        "rm -rf ${AITER_HOME}"
        "mkdir -p ${AITER_HOME}"
        "git clone --recursive https://github.com/ROCm/aiter.git ${AITER_HOME}"
        "cd ${AITER_HOME}"
        "git checkout v0.1.19.post2"
        "git submodule sync"
        "git submodule update --init --recursive"
        "uv pip install ."
        "cd -"
        # Install jax.
        "uv pip install --upgrade jax[rocm7-local] flax optax"
        # Install amdsmi.
        "rm -rf ${AMD_SMI_HOME}"
        "cp -rp ${AMD_SMI_SYSTEM} ${AMD_SMI_HOME}"
        "uv pip install ${AMD_SMI_HOME}"
        "rm -rf ${CONDA_HOME}/envs/${CONDA_ENV}/lib/python*\
/site-packages/_rocm_sdk_core/lib/libamd_smi*"
        # Install vllm.
#"uv pip install ${ROCM_VLLM}/vllm/\
#vllm-0.23.1.dev1%2Brocm7.14.0.g9ddef7117.d20260715-cp314-cp314-linux_x86_64.whl"
        "rm -rf ${VLLM_HOME}"
        "mkdir -p ${VLLM_HOME}"
        "git clone https://github.com/vllm-project/vllm.git ${VLLM_HOME}"
        "cd ${VLLM_HOME}"
        "git checkout ${VLLM_VERSION}"
        "uv pip install --upgrade numba scipy huggingface-hub setuptools_scm"
        "uv pip install -r requirements/${VLLM_TARGET_DEVICE}.txt"
        "export PKG_CONFIG_PATH=${CONDA_HOME}/envs/${CONDA_ENV}/lib/pkgconfig"
        "uv pip install --no-build-isolation ."
        "cd -"
        # Install ray.
        "uv pip install ray"
    )
    for CMD in "${CMDS[@]}"; do
        echo ""
        echo "${CMD}"
        ${CMD}
    done
else
    # Installation based on instructions for build from source at:
    # https://docs.vllm.ai/en/stable/getting_started/installation/
    echo "Performing installation for target device '${VLLM_TARGET_DEVICE}':"
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
fi
T1=${SECONDS}

# Check installation by importing modules.
CMD="python -c 'import vllm; from vllm import LLM, SamplingParams;\
 print(f\"vLLM version: {vllm.__version__}\")'"
echo ""
echo "Performing initial imports:"
echo "${CMD}"
eval "${CMD}"
T2=${SECONDS}

echo ""
echo "Installation of ${PROJECT_NAME} for ${OSTYPE} on $(hostname) completed: $(date)"
echo "Time for installation: $((${T1}-${T0})) seconds"
echo "Time for initial imports:: $((${T2}-${T1})) seconds"

echo ""
echo "Set up environment for ${PROJECT_NAME} with:"
echo "source ${SETUP}"
