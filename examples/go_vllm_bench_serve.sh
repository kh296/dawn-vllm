#!/bin/bash -l
#SBATCH --job-name=vllm_bench_serve # create a short name for the job
#SBATCH --output=%x_%j.log      # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:4            # number of allocated gpus per node
#SBATCH --time=04:00:00         # total run time limit (HH:MM:SS)

# Script for starting a vLLM server on one or multiple nodes,
# and from another node running a benchmark test or online serving througput.
#
# This script can be run interactively on a compute node:
#     ./go_vllm_bench_serve.sh
# or can be submitted to a Slurm batch system, substituting
# valid project account for <project_account>:.
#     sbatch --account=<project_account> ./go_vllm_bench_serve.sh
#
# Results from the benchmark test are written to:
# "vllm_bench_serve_<id>_subjob.log"
# Here, <id> will be "${SLURM_JOB_ID}" if this is non-null at the time
# of submitting the benchmarking job, or otherwise will be
# date and time in the format YYYY:mm:dd_HH:MM:SS.

# Unset and set Slurm variables for compatibility with srun.
unset SLURM_MEM_PER_CPU
unset SLURM_MEM_PER_NODE
SLURM_EXPORT_ENV="ALL"

# Ensure PROJECT_HOME defined.
if [[ ! -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi

# Generate an API key.
API_KEY=$(pwgen 16 1)

# Start a vLLM server.
VLLM_API_KEY=${API_KEY} ./go_vllm.sh -a -r vllm_serve &

# Wait until server startup has completed.
while ! ss -tunlp | grep -q vllm; do
  sleep 10
done
echo ""
echo "Server detected."
echo ""

if [[ -z "${SLURM_NNODES}" ]]; then
    SLURM_NNODES=1
fi

if [[ "${SLURM_NNODES}" -gt "1" ]]; then
    # Wait here until the ray head node is detected.
export HEAD_NODE_PORT=$(( (SLURM_JOB_ID % 10000) + 50000 ))
export HEAD_NODE_ADDRESS="${HEAD_NODE_IP}:${HEAD_NODE_PORT}"
    until ray status --address=${HEAD_NODE_ADDRESS} >/dev/null 2>&1; do
        sleep 10
    done
    echo ""
    echo "Ray cluster detected."
    echo ""
fi

# Submit a job to run the benchmark test.
TIMESTAMP="$(date +"%Y:%m:%d_%H:%M:%S")"
LOG_FILE="vllm_bench_serve_${SLURM_JOB_ID:-${TIMESTAMP}}_subjob.log"
sbatch --wait --nodes=1 --gres=gpu:1 --reservation=new_image --export=OPENAI_API_KEY=${API_KEY},VLLM_HOST=$(hostname) --output="${LOG_FILE}" ./go_vllm.sh -a -r vllm_bench_serve
