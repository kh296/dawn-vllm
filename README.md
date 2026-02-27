# Installing and running vLLM on Dawn

## 1. Introduction

This is a demonstration of installing and running vLLM on the
[Dawn supercomputer](https://www.hpc.cam.ac.uk/d-w-n), which is
hosted at the University of Cambridge, and is part
of the [AI Resource Research (AIRR)](https://www.gov.uk/government/publications/ai-research-resource/airr-advanced-supercomputers-for-the-uk).  Dawn has
256 nodes, in the form of [Dell PowerEdge XE9640](https://www.delltechnologies.com/asset/en-us/products/servers/technical-support/poweredge-xe9640-spec-sheet.pdf) servers.  Each node consists of:
- 2 CPUs ([Intel Xeon Platinum 8468](https://www.intel.com/content/www/us/en/products/sku/231735/intel-xeon-platinum-8468-processor-105m-cache-2-10-ghz/specifications.html)), each with 48 cores and 512 GiB RAM;
- 4GPUs ([Intel Data Centre GPU Max 1550](https://www.intel.com/content/www/us/en/products/sku/232873/intel-data-center-gpu-max-1550/specifications.html)),
each with two stacks (or tiles), 1024 compute units, and 128 GiB RAM.

The material collected here is licensed under the
[Apache License, Version 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## 2. Quickstart

The following are minimal instructions for running an example
[vLLM](https://docs.vllm.ai/en/stable/) application
on the [Dawn supercomputer](https://www.hpc.cam.ac.uk/d-w-n).  The example
runs the [offline thoughput benchmark](https://docs.vllm.ai/en/stable/cli/bench/throughput/?h=throughput)for the [Qwen/Qwen3-4B](https://huggingface.co/Qwen/Qwen3-4B) Large Language Model.

Instructions are provided for working on a Dawn login node or on
a Dawn compute node.

### 2.1 On a Dawn login node

- Clone this repository, and move to the `scripts` directory:
  ```
  clone https://github.com/kh296/dawn-vllm
  cd dawn-vllm/scripts
  ```
- Perform software installation by choosing one of the following options:
  - **Option 1**: if you don't have your own `conda` installation,
    submit a Slurm job for the installation as follows:
    ```
    # Substitute for <project_account> a valid project account.
    # Output written to vllm_install.log.
    sbatch --account=<project_account> vllm_install.sh
    ```
  - **Option 2**: if you have your own `conda` installation,
    submit a Slurm job for the installation as follows:
    ```
    # Substitute for <project_account> a valid project account.
    # Substitute for <conda_home> the path to your conda installation.
    # Substitute for <conda_env> the name to be given to the conda
    # environment for this installation.
    # Output written to vllm_install.log.
    sbatch --account=<project_account> vllm_install.sh -c <conda_home> -e <conda_env>
    ```
   From when the Slurm job starts running, installation typically takes
   a little over an hour.

- Once installation has completed, move to the `examples` directory,
  and submit a job to run the example vLLM througput benchmark,
  on a single node or over multiple nodes:
  ```
  # Substitute valid project account for <project_account>.
  # Number of nodes may be set to 1, 2, or 4.
  # Output written to go_vllm.log
  cd ../examples
  sbatch --account=<project_account> --nodes=1 go_vllm.sh
  ```
  The performance summary will be written a few lines before the end of
  the output file, and for running on a single node should be similar to:
  ```
  Throughput: 20.29 requests/s, 23368.39 total tokens/s, 2596.49 output tokens/s
  ```

### 2.2 On a Dawn compute node

Follow the same steps as on a Dawn login node, or execute scripts interactively
rather than submitting as Slurm jobs:

- Clone this repository, and move to the `scripts` directory:
  ```
  clone https://github.com/kh296/dawn-vllm
  cd dawn-vllm/scripts
  ```
- Perform software installation:
  - **Option 1**: if you don't have your own `conda` installation:
    ```
    ./install_vlm.sh
    ```
  - **Option 2**: if you have your own `conda` installation:
    ```
    # Substitute for <conda_home> the path to your conda installation.
    # Substitute for <conda_env> the name to be given to the conda
    # environment for this installaion.
    ./vllm_install.sh -c <conda_home> -e <conda_env>
    ```
- Run the example vLLM througput benchamrk over all allocated nodes:
  ```
  ./go_vllm.sh
  ```

## 3. Further information

### 3.1 Installation

The script [scripts/vllm_install.sh](scripts/vllm_install.sh) follows the
instructions in the [vLLM documentation](https://docs.vllm.ai/en/stable/)
to [build wheel from source for Intel XPU](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/#build-wheel-from-source).

The basic approach is to install Python packages in a virtual environment.  In
[scripts/vllm_install.sh](scripts/vllm_install.sh), the virtual environment
is creating `conda`, but it could be adapted to do this differently, for
example using [python -m venv](https://docs.python.org/3/library/venv.html)
or [uv venv](https://docs.astral.sh/uv/pip/environments/).
instead.

If [scripts/vllm_install.sh](scripts/vllm_install.sh) is run without
specifying a path to an existing `conda` installation (`-c <conda_home>`),
`conda` will be searched for at `~/miniforge3`.  If not found, the
[Miniforge3](https://github.com/conda-forge/miniforge?tab=readme-ov-file#miniforge) flavour of `conda` will be installed at `~/rds/hpc-work/miniforge3`,
and this directory will be linked to `~/miniforge3`.  This takes advantage of
the large user space allocation at `~/rds/hpc-work` (not backed up - see
[Summary of available filesystems](https://docs.hpc.cam.ac.uk/hpc/user-guide/io_management.html?highlight=hpc%20work#summary-of-available-filesystems),
while making the Miniforge3 installation accessible at its default location. 

The name used by [scripts/vllm_install.sh](scripts/vllm_install.sh) for
the `conda` environment to which to install is as specified by the user
(`-e <conda_env>`), or defaults to `vllm`.  Any pre-existing environment
with the same name will be removed.

During installation, the following operations are performed:
- The vLLM repository is cloned:
  ```
  mkdir -rf ../projects/vllm
  git clone https://github.com/vllm-project/vllm.git ../projects/vllm
  ```
- From the top level of the vLLM repository, and from inside the virtual
  environment for installation, a tagged version of vLLM is checked out, then
  the vLLM software is installed:
  ```
  # If not set before running script, VLLM_VERSION defaults to 0.15.1 on Dawn.
  git checkout ${VLLM_VERSION
  python -m pip install -v -r requirements/xpu.txt"
  python -m pip install -v -e . --no-build-isolation
  ```
- A script that can be sourced in a bash shell to set up the environment
  for running vLLM applications is created at `../envs/<conda_env>-setup.sh`.

### 3.2 Example vLLM application

Scripts for the example vLLM application are organised so as to separate
application-specific scripts (in [examples](examples/)),
user-and-system-specific environment setup script (`envs/<conda_env>-setup.sh`,
created during installation), and scripts (in [scripts](scripts/) not
dependent on application, user, or system.

The application-specific scripts are:
- [examples/run_vllm_single.sh](examples/run_vllm_single.sh)
  - task run script; configures and runs an application on a single node;
- [examples/go_vllm.sh](examples/go_vllm.sh)
  - top-level run script; sends the task run script to
    the number of nodes requested.

The task run script may be sent to a single node, or may be sent to the
head node and worker nodes of a
[Ray cluster](https://docs.ray.io/en/latest/cluster/getting-started.html).
The task run script takes care of the following:
  1. on all nodes, it sets up the vLLM run-time environment:
     - sources [scripts/start_task.sh](scripts/start_task.sh);
       - sources [scripts/setup_project.sh](scripts/setup_project.sh),
         which determines the absolute path to the `vllm_dawn` directory,
         and sources `envs/<conda_env>-setup.sh` to set
         environment variables;
       - sources [scripts/setup_slurm.sh](scripts/setup_slurm.sh)
         to ensure that all required Slurm variables are set, and
         to derive from these values for environment variables used
         to manage multi-GPU processing;
       - if not only sent to a single node,
         executes [scripts/setup_ray.sh](scripts/setup_ray.sh) to
         ensure that a [Ray cluster](https://docs.ray.io/en/latest/cluster/getting-started.html) is available for task coordination.
  2. if sent to a single node only, or if on the head node of a Ray
     cluster, executes user code for configuring and launching
     an application; when launched on the head node of a Ray cluster,
     the application will automatically run also on the worker nodes.
  3. if on the head node of a Ray cluster, ensures that the Ray cluster is
     closed down when the application completes:
     - sources [scripts/end_task.sh](scripts/end_task.sh).
  
### 3.3  Device visibility

The scripts here have been set up so that the example vLLM application
will make use of all visible devices on the number of nodes requested.  Prior
to running an application, device visibility can be
defined using the environment variable `ZE_FLAT_DEVICE_HIERARCHY`,
set in `envs/<conda_env>-setup.sh`:
- The two GPU stacks of each Dawn GPU card are made visible as
  two independent devices with (default):
  ```
  export ZE_FLAT_DEVICE_HIERARCY="FLAT"
  ```
- A Dawn GPU card (two stacks combined) is made visible as a single device with:
  ```
  export ZE_FLAT_DEVICE_HIERARCY="COMPOSITE"
  ```
FLAT mode maximises the available compute power, while COMPOSITE mode
maximises the RAM per device at 128 GiB.

For more information about FLAT and COMPOSITE modes, see:
- [Exposing the device herarchy](https://www.intel.com/content/www/us/en/docs/oneapi/optimization-guide-gpu/2024-1/exposing-device-hierarchy.html);
- [Flattening GPU tile hierarchy](https://www.intel.com/content/www/us/en/developer/articles/technical/flattening-gpu-tile-hierarchy.html).

In general, a good starting point for vLLM applications is to use the minimum
number of nodes and FLAT-mode visible devices needed for the Large Language
Model being used.  In the example benchmark througphut, using 1 node gives
better performance than using 2 nodes.

### 3.4 Large Language Models with optimisations for Intel GPUs

Information is available about
[Large Language Models with optimisations for Intel GPUs](https://github.com/intel/intel-extension-for-pytorch?tab=readme-ov-file#ipexllm---large-language-models-llms-optimization).

### 3.5 Installing and running vLLM on other systems

The scripts for installing and running vLLM on Dawn have been designed 
with the intention that they should be easy to adapt for use on other
systems.  As an example of this, the scripts have been adapted so that
the instructions for executing scripts interactively on a Dawn compute
node will work also on a MacBook.  Installation on a MacBook is faster
than on Dawn, which has been useful for some parts of the script
development.  Running the example vLLM througput benchmark on a MacBook
(CPU support only) is many times slower than on Dawn.
