#!/bin/bash

#
# SLURM job to extract .sno snapshots at specific dates
# Adjust EXEC_LIST and NCPUS before submitting
#
#SBATCH --nodes=1
#SBATCH --account=s1329
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --job-name=extract_dates
#SBATCH --output=logs/extract_dates_%j.out
#SBATCH --error=logs/extract_dates_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sergi.gonzalez@slf.ch
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack

# ---- Set this to the output dir from run_past_dates.sh or run_future_dates.sh ----
EXEC_LIST="${1:?ERROR: provide path to to_exec.lst as argument}"
NCPUS="${SLURM_CPUS_PER_TASK:-128}"

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup
mkdir -p logs

TOTAL=$(wc -l < "${EXEC_LIST}")
echo "Starting ${TOTAL} stations with ${NCPUS} cores at $(date)"

cat "${EXEC_LIST}" | parallel -j "${NCPUS}"

echo "Finished at $(date)"
