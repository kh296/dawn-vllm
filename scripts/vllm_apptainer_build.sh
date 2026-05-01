#!/bin/bash -l
#SBATCH --job-name=apptainer_build # create a short name for the job
#SBATCH --output=%x.log        # job output file
#SBATCH --partition=pvc9       # cluster partition to be used
#SBATCH --nodes=1              # number of nodes
#SBATCH --gres=gpu:1           # number of allocated gpus per node
#SBATCH --time=00:15:00        # total run time limit (HH:MM:SS)

# Script for building an Apptainer image from a Docker image that has
# vLLM installed with Intel extensions and GPU drivers.
# For information about available Docker images, see:
# https://hub.docker.com/r/intel/vllm

# This script can be run interactively on a Dawn compute node:
# ./vllm_apptainer_build.sh [<options>]
# or can be submitted to Dawn's Slurm batch system, substituting a
# valid project account for <project_account>:.
# sbatch --acount=<project_account> ./vllm_apptainer_build.sh [<options>]
#
# For information about options, from a compute node or login node use:
# ./vllm_apptainer_build.sh -h
T0=${SECONDS}
PROJECT_NAME="vLLM"
PROJECT_NAME_LC="$(echo ${PROJECT_NAME} | tr [:upper:] [:lower:])"
if [[ " $* " != *" -h "* ]]; then
    echo "Apptainer build for ${PROJECT_NAME} started on $(hostname): $(date)"
    echo ""
fi

# Exit at first failure.
set -e

# Ensure PROJECT_HOME defined.
if [[ ! -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

# Set defaults.
VERSION="0.14.1-xpu"
IDENTIFIER="intel/${PROJECT_NAME_LC}:${VERSION}"
DOCKER_URI="docker://${IDENTIFIER}"
IMAGE_PATH=${PROJECT_HOME}/apptainer
IMAGE_NAME="${PROJECT_NAME_LC}-${VERSION}.sif"

# Parse command-line options.
usage() {
    echo "usage: vllm_apptainer_build.sh [-h] [-d <docker image>][-a <apptainer image>]"
    echo "    Build Apptainer image from Docker Image with vLLM for Intel GPUs."
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
                    DOCKER_URI="$2"
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
#eval ${CMD}

echo ""
echo "Apptainer build for ${PROJECT_NAME} completed on $(hostname): $(date)"
echo "Time for apptainer build: $((${SECONDS}-${T0})) seconds"
