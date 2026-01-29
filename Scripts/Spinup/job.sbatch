#!/bin/bash

#
# For SLURM - CSCS Alps
# Single node parallel execution for spinup
#
#SBATCH --nodes=1
#SBATCH --account=s1329
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --job-name=spinup
#SBATCH --output=logs/spinup_%j.out
#SBATCH --error=logs/spinup_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sergi.gonzalez@slf.ch
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack

# Change to working directory
cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

echo "Starting spinup at $(date)"

# Filter out already completed stations before running
echo "Filtering completed stations..."
bash filter_completed.sh

echo "Running stations in parallel (128 at a time) on single node..."

# Run spinup tasks in parallel
# Each SNOWPACK run is relatively light, so we can run 128 in parallel
cat to_exec.lst | parallel -j 128

echo "Finished spinup at $(date)"
