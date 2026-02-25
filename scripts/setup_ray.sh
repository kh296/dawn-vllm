#!/bin/bash -l

# Script for initiating, or adding to, a ray cluster.
# This script can be run on multiple nodes of an allocation,
# via srun or a script run via srun.

# Ensure PROJECT_HOME defined.
if [[ -d "${PROJECT_HOME}" ]]; then
    PROJECT_HOME=$(cd $(dirname "${BASH_SOURCE[0]}")/..; pwd)
    if [[ ${PROJECT_HOME} == /var/spool/* ]]; then
        PROJECT_HOME=$(dirname $(pwd))
    fi
fi


if ! type ray >/dev/null 2>&1; then
    source ${PROJECT_HOME}/scripts/setup_project.sh $1
fi
set --

if [[ -z "${IS_HEAD_NODE}" ]]; then
    source ${PROJECT_HOME}/scripts/setup_slurm.sh
fi

T2=${SECONDS}

if [[ -z "${CPUS_PER_GPU}" ]]; then
    CPUS_PER_GPU=8;
fi
NUM_CPUS=$(( ${SLURM_NTASKS_PER_NODE} * ${CPUS_PER_GPU} ))
if [ ${SLURM_CPUS_ON_NODE} -lt ${NUM_CPUS} ]; then
    NUM_CPUS=${SLURM_CPUS_ON_NODE}
fi

# Initiate a ray cluster by starting the head node.
if ${IS_HEAD_NODE}; then
    echo ""
    echo "Ensuring no active ray cluster:"
    CMD=(ray stop)
    echo "${CMD[@]}"
    "${CMD[@]}"

    echo ""
    echo "Starting ray head node on ${HEAD_NODE}:"
    CMD=(ray start -v --head --node-ip-address=${HEAD_NODE_IP} --port=${HEAD_NODE_PORT}  --num-gpus=${SLURM_NTASKS_PER_NODE} --num-cpus=${NUM_CPUS} --disable-usage-stats --block)
   echo "${CMD[@]} &"
   "${CMD[@]}" &
fi

# Wait here until the ray head node is detected.
until ray status --address=${HEAD_NODE_ADDRESS} >/dev/null 2>&1; do
    sleep 2
done

# Add a worker node to the ray cluster.
if ${IS_HEAD_NODE}; then
    echo ""
    echo "Ray head node running on ${HEAD_NODE}."
    echo ""
else
    echo ""
    echo "Starting ray worker node on $(hostname):"
    CMD=(ray start -v --address=${HEAD_NODE_ADDRESS} --num-gpus=${SLURM_NTASKS_PER_NODE} --num-cpus=${NUM_CPUS} --block)
    echo "${CMD[@]} &"
    "${CMD[@]}" &
fi

# Wait here until all allocated nodes have been added to the ray cluster.
while true; do
    RAY_STATUS=$(ray status --address=${HEAD_NODE_ADDRESS} 2>/dev/null)
    if [[ "${RAY_STATUS}" == *"Node status"* ]]; then
        RAY_NODES="$(echo ${RAY_STATUS} | grep -o 'node_' | wc -l)"
        if [ "${RAY_NODES}" -eq "${SLURM_NNODES}" ]; then
            break
        fi
            sleep 2 
    fi
done

if ${IS_HEAD_NODE}; then
    echo ""
    echo "Worker nodes added to ray cluster."
    echo ""
    echo "Checking ray status:"
    CMD=(ray status)
    echo "${CMD[@]}"
    "${CMD[@]}"

    echo ""
    echo "Time for setting up ray cluster: $((${SECONDS}-${T2})) seconds"
fi

# If not running on a head node, wait until worker processes are stopped,
# and then exit.
if ! ${IS_HEAD_NODE}; then
    wait 
    echo "Ray worker $(hostname) exiting."
    exit
fi
