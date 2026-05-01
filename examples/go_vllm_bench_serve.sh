#!/bin/bash -l
#SBATCH --job-name=vllm_bench_serve # create a short name for the job
#SBATCH --output=%x_%j.log      # job output file
#SBATCH --partition=pvc9        # cluster partition to be used
#SBATCH --nodes=1               # number of nodes
#SBATCH --gres=gpu:4            # number of allocated gpus per node
#SBATCH --time=04:00:00         # total run time limit (HH:MM:SS)

# Script for starting a vLLM server on one or multiple nodes,
# and for then running server benchmarking.
#
# This script can be run interactively on a compute node:
# ./go_vllm_bench_serve.sh [<options>]
# or can be submitted to a Slurm batch system, substituting
# valid project account for <project_account>:
# sbatch --account=<project_account> ./go_vllm_bench_serve.sh [<options>]
#
# For information about options, from a compute node or login node use:
# ./go_vllm.sh -h
#
# Results from benchmarking are written to:
# "vllm_bench_serve_<id>_subjob.log"
# Here, <id> will be "${SLURM_JOB_ID}" if this is non-null at the time
# of starting the benchmarking, or otherwise will be
# date and time in the format YYYY:mm:dd_HH:MM:SS.

T1=${SECONDS}

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

# Ensure that help in ../scripts/setup_project.sh refers to this script.
if [[ " $* " == *" -h "* ]]; then
    export SETUP_LAUNCH="$(basename $0)"
    export SETUP_INFO=\
"    Start vLLM server on one or multiple nodes, then run server benchmarking."
    export NO_RUN_OPTION="true"
    export EXTRA_OPTS=\
"    -s : Run benchmarking in a subjob, on a different node from the server."
    export EXTRA_OPTS_USAGE=" [-s]"
    source ${PROJECT_HOME}/scripts/setup_project.sh -h
    exit 0
fi

# Determine whether benchmark is to be run in a subjob (-s option) or directly.
FILTERED_ARGS=()
SUBMIT_SUBJOB="false"
for ARG in "$@"; do
    if [[ "-s" == "${ARG}" ]]; then
        SUBMIT_SUBJOB="true"
    else
        FILTERED_ARGS+=("${ARG}")
    fi
done
set -- "${FILTERED_ARGS[@]}"

# Generate an API key.
API_KEY=$(pwgen 16 1)

# Start a vLLM server.
VLLM_API_KEY=${API_KEY} ./go_vllm.sh $@ -r vllm_serve &

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

echo "Server setup time: $((${SECONDS}-${T1})) seconds"
echo ""

# Run the benchmark test, in a subjob (option -s) or directly.
TIMESTAMP="$(date +"%Y:%m:%d_%H:%M:%S")"
LOG_FILE="vllm_bench_serve_${SLURM_JOB_ID:-${TIMESTAMP}}_subjob.log"
if [[ "true" == "${SUBMIT_SUBJOB}" ]]; then
    CMD="sbatch --wait --nodes=1 --gres=gpu:1 --exclude=$(hostname) --export=OPENAI_API_KEY=${API_KEY},VLLM_HOST=$(hostname) --output=${LOG_FILE} ${PROJECT_HOME}examples//go_vllm.sh $@ -r vllm_bench_serve"
    CMD_TO_ECHO=$(echo "${CMD}" | sed 's/--export=[^ ]* //')
    echo "Submitting batch job to run benchmark test:"
else
    CMD="OPENAI_API_KEY=${API_KEY} VLLM_HOST=$(hostname) ${PROJECT_HOME}/examples/go_vllm.sh $@ -r vllm_bench_serve 1>${LOG_FILE} 2>&1"
    CMD_TO_ECHO=$(echo "${CMD}" | sed -E 's/(OPENAI_API_KEY|VLLM_HOST)=[^ ]* //g')
    echo "Running benchmark test:"
fi
echo "${CMD_TO_ECHO}"
#eval "${CMD}"

echo ""
echo "Job time: $((${SECONDS}-${T1})) seconds"
