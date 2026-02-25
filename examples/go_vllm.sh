#!/bin/bash -l
#SBATCH --job-name=vllm         # create a short name for the job
#SBATCH --output=%x_%j.log      # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=2               # number of nodes
#SBATCH --gres=gpu:4            # number of allocated gpus per node
#SBATCH --time=01:00:00         # total run time limit (HH:MM:SS)

# Script for running vllm over 1 or multiple nodes.
#
# This script can be run interactively on a compute node:
#     ./go_vllm.sh [<conda env>]
# or can be submitted to a Slurm batch system, substituting
# valid project account for <project_account>:.
#     sbatch --account=<project_account> ./go_vllm.sh [<conda env>]
# The optional positional argument defines the name of the conda environment
# to be used subsequently.  If the argument is omitted, the name used is
# "${CONDA_ENV}" if this isn't an empty string, or otherwise "vllm".

# In the case of batch submission, the number of nodes to be used defaults
# to the number set in the Slurm directive at the top of this script,
# or can be set at the command line, for example:
#     sbatch --account=<project_account> --nodes=4 ./go_vllm.sh [conda env]
#
# Environment setup and vLLM configuration is performed in the script
# ./run_vllm_single.sh, launched directly or using srun here.
# See this script for details.

T1=${SECONDS}

echo "Job start on $(hostname): $(date)"

# Default to 1 node allocated if running outside of Slurm.
if [[ -z "${SLURM_NNODES}" ]]; then
    SLURM_NNODES=1
fi

# Unset and set Slurm variables for compatibility with srun.
unset SLURM_MEM_PER_CPU
unset SLURM_MEM_PER_NODE
SLURM_EXPORT_ENV="ALL"

echo ""
if [[ "${SLURM_NNODES}" -eq "1" ]]; then
    echo "Running task on 1 node:"
    CMD=(./run_vllm_single.sh $1)
else
    echo "Running tasks on ${SLURM_NNODES} nodes:"
    CMD=(srun --nodes=${SLURM_NNODES} --ntasks-per-node=1 run_vllm_single.sh $1)
fi
echo "${CMD[@]}"
"${CMD[@]}"

echo "Job time: $((${SECONDS}-${T1})) seconds"
