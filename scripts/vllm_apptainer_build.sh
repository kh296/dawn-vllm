#!/bin/bash -l
#SBATCH --job-name=apptainer_build # create a short name for the job
#SBATCH --output=%x.log        # job output file
#SBATCH --partition=pvc9       # cluster partition to be used
#SBATCH --nodes=1              # number of nodes
#SBATCH --gres=gpu:1           # number of allocated gpus per node
#SBATCH --time=00:15:00        # total run time limit (HH:MM:SS)

# Script for building Apptainer image from Docker image that has
# vLLM installed with Intel extensions and GPU drivers.
# For information about available Docker images, see:
# https://hub.docker.com/r/intel/vllm

# This script can be run interactively on a Dawn compute node or login node:
#     ./vllm_apptainer_build.sh
# or can be submitted to Dawn's Slurm batch system, substituting a
# valid project account for <project_account>:.
#     sbatch --acount=<project_account> ./vllm_apptainer_build.sh

T0=${SECONDS}
PROJECT_NAME="vLLM"
PROJECT_NAME_LC="$(echo ${PROJECT_NAME} | tr [:upper:] [:lower:])"
echo "Apptainer build for ${PROJECT_NAME} started on $(hostname): $(date)"
echo ""

# Exit at first failure.
set -e

# Ensure PROJECT_HOME defined.
if [[ ! -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

# Set APPTAINER_TMPDIR to location with sufficient space for build files.
export APPTAINER_TMPDIR="/ramdisks/apptainer_tmpdir"
rm -rf "${APPTAINER_TMPDIR}"
mkdir "${APPTAINER_TMPDIR}"

# Define and run build command.
APPTAINER_HOME=${PROJECT_HOME}/apptainer
mkdir -p ${APPTAINER_HOME}
VERSION="0.14.1-xpu"
IMAGE_PATH="${APPTAINER_HOME}/${PROJECT_NAME_LC}-${VERSION}.sif"
DOCKER_URI="docker://intel/${PROJECT_NAME_LC}:${VERSION}"
CMD="apptainer build --force ${IMAGE_PATH} ${DOCKER_URI}"
echo "${CMD}"
eval ${CMD}

echo ""
echo "Apptainer build for ${PROJECT_NAME} completed on $(hostname): $(date)"
echo "Time for apptainer build: $((${SECONDS}-${T0})) seconds"
