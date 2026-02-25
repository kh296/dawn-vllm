# Script to ensure that Slurm environment variables,
# and variables dervived from these, are set,
# also if outside of a Slurm environment.
#
# The variables specifying number of tasks per node (SLURM_NTASKS_PER_NODE),
# number of tasks (SLURM_NTASKS), and number of CPU cores per node
# (SLURM_CPUS_ON_NODE) are used in setting up task parallelisation
# when this script is to be run on multiple nodes within a ray cluster.
# These numbers depend on the number of nodes allocated, on the
# number of GPUs per node, and on how GPUs are configured.
#
# On Dawn, if a single node is allocated, then it may be allocated with
# 1, 2, 3, or 4 GPUs (but not with 0 GPUs).  If more than one node is
# allocated, all must be allocated with all (4) GPUs.  If GPUs are
# used in "FLAT" mode, the two stacks of each GPU are treated as two
# root devices.  If GPUs are used in "COMPOSITE" mode, the two stacks
# of each GPU are treated as a single root device.  For more information
# about modes for Intel GPUs, see:
# https://www.intel.com/content/www/us/en/docs/oneapi/optimization-guide-gpu/2024-1/exposing-device-hierarchy.html
# https://www.intel.com/content/www/us/en/developer/articles/technical/flattening-gpu-tile-hierarchy.html
#
# The variables specifying node(s) allocated (SLURM_JOB_NODELIST)
# and job id (SLURM_JOB_ID) are used to determine the address and port
# of the head node when running in a ray cluster.
# 
# This script can be sourced in a bash shell:
#     source ./setup_slurm.sh

# Default to 1 node allocated if running outside of Slurm.
if [[ -z "${SLURM_NNODES}" ]]; then
    export SLURM_NNODES=1
fi

# Determine number of root devices per GPU on Dawn.
if [[ -z "${ZE_FLAT_DEVICE_HIERARCHY}" ]]; then
    export ZE_FLAT_DEVICE_HIERARCHY="COMPOSITE"
fi
if [[ "COMPOSITE" == "${ZE_FLAT_DEVICE_HIERARCHY}" ]]; then
    DEVICES_PER_GPU=1
else
    DEVICES_PER_GPU=2
fi

# Determine number of tasks per node, with one task per GPU root device,
# or defaulting to 1 if there are no GPUs.
# Where GPUs are present, set affinity mask to match number of root devices.
if [[ -z "${SLURM_GPUS_ON_NODE}" ]]; then
    export SLURM_NTASKS_PER_NODE=1
else
    export SLURM_NTASKS_PER_NODE=$((${SLURM_GPUS_ON_NODE}*${DEVICES_PER_GPU}))
    if [[ ${SLURM_NTASKS_PER_NODE} -gt 1 ]]; then
        export ZE_AFFINITY_MASK=$(seq -s, 0 $((${SLURM_NTASKS_PER_NODE}-1)))
    else
        export ZE_AFFINITY_MASK=0
    fi
fi

# Determine total number of tasks.
export SLURM_NTASKS=$((${SLURM_NNODES}*${SLURM_NTASKS_PER_NODE}))

# Determine number of CPU cores per task.
if [[ -z "${SLURM_CPUS_ON_NODE}" ]]; then
    export SLURM_CPUS_ON_NODE=1
fi
export SLURM_CPUS_PER_TASK=$((${SLURM_CPUS_ON_NODE}/${SLURM_NTASKS_PER_NODE}))

# Ensure that a value is assigned to SLURM_JOB_NODELIST.
if [[ -z "${SLURM_JOB_NODELIST}" ]]; then
    export SLURM_JOB_NODELIST=$(hostname)
fi

# Ensure that a value is assigned to SLURM_JOB_ID.
if [[ -z "${SLURM_JOB_ID}" ]]; then
    export SLURM_JOB_ID=5100
fi

# Unset and set Slurm variables, for compatibility with srun.
unset SLURM_MEM_PER_CPU
unset SLURM_MEM_PER_NODE
SLURM_EXPORT_ENV="ALL"

# Create list of node names, and identify the head node.
if command -v scontrol 1>/dev/null 2>&1; then
    NODES="$(echo $(scontrol show hostnames ${SLURM_JOB_NODELIST})\
        | sed 's/ /,/g')"
    export HEAD_NODE="${NODES%%,*}"
    export HEAD_NODE_IP=$(getent hosts ${HEAD_NODE} | cut -d" " -f1)
else
    NODES="${SLURM_JOB_NODELIST}"
    export HEAD_NODE="$(hostname)"
    export HEAD_NODE_IP="127.0.0.1"
fi
export IS_HEAD_NODE=$( [[ "$(hostname)" == "${HEAD_NODE}" ]] && echo "true" || echo "false" )

if ${IS_HEAD_NODE}; then
    echo ""
    echo "Node(s) used:"
    echo "${NODES}"
fi

export HEAD_NODE_PORT=$(( (SLURM_JOB_ID % 10000) + 50000 ))
export HEAD_NODE_ADDRESS="${HEAD_NODE_IP}:${HEAD_NODE_PORT}"
