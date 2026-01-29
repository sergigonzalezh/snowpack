#!/bin/bash

#
# For SLURM on CSCS Alps - Single node parallel execution
#
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack
#SBATCH --nodes=1
#SBATCH --account=s1329
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=16
#SBATCH --mem=0

#SBATCH --job-name=smet_creation
#SBATCH --output=./sbatch_out_files/%x.%j.out
#SBATCH --error=./sbatch_out_files/%x.%j.err

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf

echo "Starting SMET extraction at $(date)"
echo "Running years in parallel (4 at a time) on single node..."
echo "Note: Each merged NetCDF is ~12GB, so limiting parallelism to avoid OOM"

# Run commands in parallel, limited to 4 concurrent jobs to avoid OOM
# Each process loads ~12GB NetCDF files, so 4 x 12GB = ~48GB memory needed
cat to_exec.lst | parallel -j 4

echo "Finished SMET extraction at $(date)"
