#!/bin/bash -l
#SBATCH --job-name=apptainer_build # create a short name for the job
#SBATCH --output=%x.log        # job output file
#SBATCH --partition=pvc9       # cluster partition to be used
#SBATCH --nodes=1              # number of nodes
#SBATCH --gres=gpu:1           # number of allocated gpus per node
#SBATCH --time=00:15:00        # total run time limit (HH:MM:SS)

# Script for building an Apptainer image from a Docker image that has
# vLLM installed.
# For information about available Docker images, see:
# Intel GPUs : https://hub.docker.com/r/intel/vllm
# AMD GPUs   : https://hub.docker.com/r/vllm/vllm-openai-rocm

# This script can be run interactively on a Dawn compute node:
# ./vllm_apptainer_build.sh [<options>]
# or can be submitted to a Slurm batch system, substituting a
# valid project account for <project_account>
# and a valid partition for <partition>:.
# sbatch --acount=<project_account> --partition=<partition> ./vllm_apptainer_build.sh [<options>]
#
# For information about options, from a compute node or login node use:
# ./vllm_apptainer_build.sh -h

# Exit at first failure.
set -e

T0=${SECONDS}
PROJECT_NAME="vLLM"
PROJECT_NAME_LC="$(echo ${PROJECT_NAME} | tr [:upper:] [:lower:])"
if [[ " $* " != *" -h "* ]]; then
    echo "Apptainer build for ${PROJECT_NAME} started on $(hostname): $(date)"
    echo ""
fi

# Ensure PROJECT_HOME defined.
if [[ ! -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

# Set defaults.
VERSION="latest"
# Match default identifier to system used.
if [[ "$(hostname)" == "pvc-s"* || "$(hostname)" == "login-s"* ]]; then
    SYSTEM="Dawn"
    IDENTIFIER="intel/${PROJECT_NAME_LC}:${VERSION}"
elif [[ "$(hostname)" == *"pl1"* ]]; then
    SYSTEM="aac6"
    IDENTIFIER="vllm/vllm-openai-rocm:${VERSION}"
else
    SYSTEM="unknown"
    IDENTIFIER=""
fi
DOCKER_URI="docker://${IDENTIFIER}"
IMAGE_PATH=${PROJECT_HOME}/apptainer
IMAGE_NAME="${PROJECT_NAME_LC}-${VERSION}.sif"

# Parse command-line options.
usage() {
    echo "usage: vllm_apptainer_build.sh [-h] [-d <docker image>][-a <apptainer image>]"
    echo "    Build Apptainer image from Docker Image with ${PROJECT_NAME}."
    echo "Options:"
    echo "    -h: Print this help."
    echo "    -d: Build from docker image with local path or identifier <docker image>;"
    echo "    -a: Write apptainer image to path <apptainer image>."
    echo ""
    echo "Docker image identifiers are as defined for docker hub, for example:"
    echo "    ${IDENTIFIER}"
    echo "If -d is omitted, the apptainer build is from: ${DOCKER_URI}."
    echo "If -a is omitted, the apptainer image is written to:"
    echo "    ${IMAGE_PATH},"
    echo "    with filename determined from the path or identifier of the docker image,"
    echo "    for example:"
    echo "    ${IMAGE_NAME}."
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h)
            usage
	    exit 0
            ;;
        -d)
            if [[ -n "$2" && "$2" != -* ]]; then
                if [[ -f "$2" ]]; then
                    DOCKER_URI="docker-archive://$2"
                    NAME=$(basename "$2")
                    IMAGE_NAME="${NAME%.*}.sif"
                else
                   DOCKER_URI="docker://$2";
		   NAME="${2##*/}"
		   IMAGE_NAME="${NAME%%:*}-${2##*:}.sif"
                fi
		shift 2
            else
                echo \
"-d must be followed by the local path or identifier of a docker image, "
                usage
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

if [[ "docker://" == "${DOCKER_URI}" ]]; then
    echo "Docker image not known from URI \"${DOCKER_URI}\""
    echo "Exiting: $(date)"
    exit 1
fi

if [[ ${IMAGE_PATH} != *.sif ]]; then
    IMAGE_PATH="${IMAGE_PATH}/${IMAGE_NAME}"
fi
IMAGE_DIR=$(dirname ${IMAGE_PATH})

# Set APPTAINER_TMPDIR to location with sufficient space for build files.
if [[ -d "/ramdisks" ]]; then
    export APPTAINER_TMPDIR="/ramdisks/apptainer_tmpdir"
    rm -rf "${APPTAINER_TMPDIR}"
    mkdir "${APPTAINER_TMPDIR}"
fi

# Define and run build command.
mkdir -p ${IMAGE_DIR}
CMD="apptainer build --force ${IMAGE_PATH} ${DOCKER_URI}"
echo "${CMD}"
eval ${CMD}

echo ""
echo "Apptainer build for ${PROJECT_NAME} completed on $(hostname): $(date)"
echo "Time for apptainer build: $((${SECONDS}-${T0})) seconds"
