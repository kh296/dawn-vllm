#!/bin/bash -l
#SBATCH --job-name=vllm         # create a short name for the job
#SBATCH --output=%x_%j.log      # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:4            # number of allocated gpus per node
#SBATCH --time=04:00:00         # total run time limit (HH:MM:SS)

# Script for running vLLM benchmark on a single node,
# which in a ray cluster can be either the head node or a worker node.
#
# Startup operations are performed using:
#     ../scripts/start_task.sh
# The main operations are:
# - environment setup for running vLLM, with reference to <conda env>,
#   the conda environment to be used (see next section):
#     ../scripts/setup_project.sh
#     ../scripts/<conda env>-setup.sh
# - checking of Slurm environment variables, and determination from these
#   of environment variables used in vLLM configuration:
#     ../scripts/setup_slurm.sh
# - if more than a single node is being used, creation of ray cluster:
#     ../scripts/setup_ray.sh
#
# Closedown operations are performed using:
#     ../scripts/end_task.sh
# The operation here is:
# - if more than a single node is being used, close down ray cluster;
#
# This script can be run interactively:
#     ./run_vllm_single.sh [<conda env>]
# or can be submitted to a Slurm batch system, substituting
# valid project account for <project_account>:.
#     sbatch --acount=<project_account> run_vllm_single.sh [<conda env>]
# The optional positional argument defines the name of the conda environment
# to be used subsequently.  If the argument is omitted, the name used is
# "${CONDA_ENV}" if not an empty string, or otherwise "vllm".
#
# This script can also run in parallel on multiple nodes,
# using srun within a Slurm script: see ./go_vllm.sh.
# The number of nodes to be used can be set in the #SBATCH directives
# at the start of ./go_vllm.sh, but in the current script should be left as 1.
# For informtion about #SBATCH directives, see:
# https://slurm.schedmd.com/sbatch.html#SECTION_DESCRIPTION

# Exit at first failure.
set -e

# Determine project home.
PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
    PROJECT_HOME=$(dirname $(pwd))
fi

# Ensure that help in ../scripts/setup_project.sh refers to this script.
export SETUP_INFO="    Launch application in vLLM environment on single node."

# Perform environment setup; initiate ray cluster if running on multiple nodes.
source ${PROJECT_HOME}/scripts/start_task.sh

if [[ "true" != "${PROJECT_ENVIRONMENT_SET}" ]]; then
    exit
fi

if [[ -z "${APPTAINER_CONTAINER}" ]]; then
    export TASK_T1=${SECONDS}
    echo ""
    echo "Task start on $(hostname): $(date)"
fi

if [[ ! -z ${CONTAINER_LAUNCH} && -z ${APPTAINER_CONTAINER} ]]; then
    CMD=(${CONTAINER_LAUNCH} $0)
    echo ""
    echo "Launching apptainer on $(hostname): $(date)"
    echo "${CMD[@]}"
    "${CMD[@]}"
    exit
fi
set --

if [[ "true" != "${IS_HEAD_NODE}" ]]; then
    exit
fi

# Define model.
if [[ "${OSTYPE}" == "darwin"* ]]; then
    MODEL="Qwen/Qwen3-0.6B"
else
    MODEL="Qwen/Qwen3-4B"
fi

# Define storage locations and logging level.
VLLM_STORE="/home/kh296/rds/hpc-work/vllm"
export VLLM_CACHE_ROOT="${VLLM_STORE}"
export HF_HOME="${VLLM_STORE}"
export HF_HUB_CACHE="${VLLM_STORE}"
export VLLM_LOGGING_LEVEL="INFO"

# Define options to be passed to application.
# Exclamation mark used to avoid forced exit (with set -e)
# when read reaches end of stream (non-zero return code).
! read -r -d "" VLLM_OPTS << EOS
 --model=${MODEL}\
 --dtype bfloat16\
 --tensor-parallel-size 2\
 --max-model-len 32768\
 --enforce-eager\
 --api-key=test\
 --port 8199
EOS

# Run vLLM serving.
CMD=(vllm serve ${VLLM_OPTS})
T3=${SECONDS}
echo ""
echo "vLLM serving started: $(date)"
echo "${CMD[@]}"
echo ""
"${CMD[@]}"
echo ""
echo "vLLM serving completed: $(date)"
echo "Time for vLLM serving: $((${SECONDS}-${T3})) seconds"

# Close down ray cluster, and perform cleanup.
source ${PROJECT_HOME}/scripts/end_task.sh

echo ""
echo "Task time on $(hostname): $((${SECONDS}-${TASK_T1})) seconds"
