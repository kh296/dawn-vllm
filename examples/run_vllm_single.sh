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
# This script can be run interactively from a compute node, for example:
#     ./run_vllm_single.sh -a -r bench_throughput
# or can be submitted to a Slurm batch system, substituting
# valid project account for <project_account>, for example:.
#     sbatch --acount=<project_account> run_vllm_single.sh -c -r env
# For more information about options, from a compute node or login node use:
#     ./run_vllm_single.sh -h
#
# This script can also run in parallel on multiple nodes,
# using srun within a Slurm script: see ./go_vllm.sh.
# The number of nodes to be used can be set in the #SBATCH directives
# at the start of ./go_vllm.sh, but in the current script (./run_vllm_single.sh)
# should be left as 1.
# For informtion about #SBATCH directives, see:
# https://slurm.schedmd.com/sbatch.html#SECTION_DESCRIPTION

# Exit at first failure.
set -e

# Determine project home.
PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
    PROJECT_HOME=$(dirname $(pwd))
fi

# Allow for distributed processing.
if [[ -z "${SLURM_NNODES}" ]]; then
    export SLURM_NNODES=1
fi

if [[ ${SLURM_NNODES} -gt 1 ]]; then
    VLLM_DISTRIBUTED_OPT=" --distributed-executor-backend ray"
else
    VLLM_DISTRIBUTED_OPT=""
fi

# Define command shortcuts.
SHORTCUTS=("VLLM_BENCH_THROUGHPUT" "VLLM_BENCH_SERVE" "VLLM_SERVE")

# Use exclamation marks below to avoid forced exit (with set -e)
# whenever read reaches end of stream (non-zero return code).

! read -r -d "" VLLM_BENCH_THROUGHPUT << EOS
vllm bench throughput\
 --model=\${HF_MODEL}\
 -tp \${SLURM_NTASKS}\
 --input-len=1024\
 --output-len=1024\
 --enforce-eager${VLLM_DISTRIBUTED_OPT}
EOS

! read -r -d "" VLLM_BENCH_SERVE << EOS
vllm bench serve\
 --backend openai\
 --model \${HF_MODEL}\
 --dataset-name random\
 --random-input-len 512\
 --random-output-len 512\
 --num-prompts 100\
 --max-concurrency 1\
 --host ${VLLM_HOST:-$(hostname)}\
 --port ${VLLM_PORT:-8000}
EOS

! read -r -d "" VLLM_SERVE << EOS
vllm serve\
 \${HF_MODEL}\
 -tp \${SLURM_NTASKS}\
 --dtype bfloat16\
 --max-model-len 32768\
 --host $(hostname)\
 --port ${VLLM_PORT:-8000}\
 --enforce-eager${VLLM_DISTRIBUTED_OPT}
EOS

# Ensure that help in ../scripts/setup_project.sh refers to this script.
SETUP_INFO="Launch application in vLLM environment on single node.

Defined command shortcuts:"
for SHORTCUT in "${SHORTCUTS[@]}"; do
    SHORTCUT_LC=$(echo "${SHORTCUT}" | tr '[:upper:]' '[:lower:]')
    SETUP_INFO="${SETUP_INFO}
    ${SHORTCUT_LC}: ${!SHORTCUT}"
done
SETUP_INFO="${SETUP_INFO}

The environment variable \"HF_MODEL\" can be set via the option -m.
The environment variable \"SLURM_NTASKS\" is calculated based on allocated nodes
and GPUs when sourcing:
    ${PROJECT_HOME}/scripts/setup_slurm.sh"
export SETUP_INFO

# Perform environment setup; initiate ray cluster if running on multiple nodes.
source ${PROJECT_HOME}/scripts/start_task.sh

if [[ "true" != "${PROJECT_ENVIRONMENT_SET}" ]]; then
    exit
fi

if [[ -z "${APPTAINER_CONTAINER}" ]]; then
    export TASK_T1=${SECONDS}
    echo ""
    echo "Task start on $(hostname): $(date)"

    # Define task to be run, with shortcut substitution.
    # This is done before container launch, as envsubst
    # isn't available in the container environment.
    SHORTCUT_USED=""
    TASK_CMD=${VLLM_CMD}
    VLLM_CMD_LC=$(echo "${VLLM_CMD}" | tr '[:upper:]' '[:lower:]')
    for SHORTCUT in "${SHORTCUTS[@]}"; do
        SHORTCUT_LC=$(echo "${SHORTCUT}" | tr '[:upper:]' '[:lower:]')
        if [[ ${VLLM_CMD_LC} == ${SHORTCUT_LC} ]]; then
            TASK_CMD=${!SHORTCUT}
	    SHORTCUT_USED=${SHORTCUT_LC}
            break
        fi
    done
    export TASK_CMD="$(echo "${TASK_CMD}" | envsubst)"
    export SHORTCUT_USED

    if [[ "vllm_serve" == ${SHORTCUT_USED} ]];then
        if [[ -z ${VLLM_API_KEY} ]]; then
            export VLLM_API_KEY=$(pwgen 16 1)
	    echo ""
	    echo "INFO: Setting api-key to: ${VLLM_API_KEY}"
	    echo \
            "INFO: To pre-define api-key, set environment variable VLLM_API_KEY"
        fi
    fi
fi

if [[ ! -z ${CONTAINER_LAUNCH} && -z ${APPTAINER_CONTAINER} ]]; then
    LAUNCH_CMD=(${CONTAINER_LAUNCH} $0)
    echo ""
    echo "Launching apptainer on $(hostname): $(date)"
    echo "${LAUNCH_CMD[@]}"
    "${LAUNCH_CMD[@]}"
    exit
fi
set --

if [[ "true" != "${IS_HEAD_NODE}" ]]; then
    exit
fi

# Define storage locations and logging level.
if [[ -z "${VLLM_STORE}" ]]; then
    HPC_WORK="$(realpath ${HOME}/rds/hpc-work)"
    if [[ -d "${HPC_WORK}" ]]; then
        VLLM_STORE="${HPC_WORK}/vllm"
    else
        VLLM_STORE="${PROJECT_HOME}/vllm"
    fi
fi
export VLLM_CACHE_ROOT="${VLLM_STORE}"
export HF_HOME="${VLLM_STORE}"
export HF_HUB_CACHE="${VLLM_STORE}"
export VLLM_LOGGING_LEVEL="INFO"

# Run vLLM command.
# For vLLM CLI reference, see:
# https://docs.vllm.ai/en/stable/cli/
T3=${SECONDS}
echo ""
echo "Command execution started: $(date)"
echo "${TASK_CMD}"
echo ""
if [[ "vllm_serve" == ${SHORTCUT_USED} ]];then
    TASK_CMD="${TASK_CMD} --api-key ${VLLM_API_KEY}"
fi
read -r -a TASK_CMD <<< "${TASK_CMD}"
"${TASK_CMD[@]}"
echo ""
echo "Command execution completed: $(date)"
echo "Command execution time: $((${SECONDS}-${T3})) seconds"

# Close down ray cluster, and perform cleanup.
source ${PROJECT_HOME}/scripts/end_task.sh

echo ""
echo "Task time on $(hostname): $((${SECONDS}-${TASK_T1})) seconds"
