#!/bin/bash -l
#SBATCH --job-name=vllm         # create a short name for the job
#SBATCH --output=%x_%j.log      # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:4            # number of allocated gpus per node
#SBATCH --time=04:00:00         # total run time limit (HH:MM:SS)

# Script for running vllm over 1 or multiple nodes.
#
# This script can be run interactively on a compute node:
# ./go_vllm.sh [<options>]
# or can be submitted to a Slurm batch system, substituting
# valid project account for <project_account>:.
# sbatch --account=<project_account> ./go_vllm.sh [<options>]
#
# For information about options, from a compute node or login node use:
# ./go_vllm.sh -h

# In the case of batch submission, the number of nodes to be used defaults
# to the number set in the Slurm directive at the top of this script,
# or can be set at the command line, for example:
#     sbatch --account=<project_account> --nodes=4 ./go_vllm.sh [conda env]
#
# Environment setup and vLLM configuration is performed in the script
# ./run_vllm_single.sh [<options>], launched here either directly or using srun.
# See the script ./run_vllm_single.sh for usage information.

T1=${SECONDS}

# Determine project home.
PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
    PROJECT_HOME=$(dirname $(pwd))
fi

# Default to 1 node allocated if running outside of Slurm.
if [[ -z "${SLURM_NNODES}" ]]; then
    SLURM_NNODES=1
fi

# Unset and set Slurm variables for compatibility with srun.
unset SLURM_MEM_PER_CPU
unset SLURM_MEM_PER_NODE
SLURM_EXPORT_ENV="ALL"

# Define the script to be run, interactively or via Slurm submission.
RUN_SCRIPT="${PROJECT_HOME}/examples/run_vllm_single.sh"

# Ensure that help in ../scripts/setup_project.sh refers to this script.
if [[ " $* " == *" -h "* ]]; then
    export SETUP_LAUNCH="$(basename $0)"
    export SETUP_INFO=\
"    Launch application in vLLM environment on one or multiple nodes."
    ${RUN_SCRIPT} -h
    exit 0
fi

# Launch the run script.
echo "Job start on $(hostname): $(date)"
echo ""
if [[ "${SLURM_NNODES}" -eq "1" ]]; then
    echo "Running task on 1 node:"
    CMD=("${RUN_SCRIPT}" "$@")
else
    echo "Running tasks on ${SLURM_NNODES} nodes:"
    CMD=(srun --nodes=${SLURM_NNODES} --ntasks-per-node=1 "${RUN_SCRIPT}" "$@")
fi
echo "${CMD[@]}"
"${CMD[@]}"

echo "Job time: $((${SECONDS}-${T1})) seconds"
