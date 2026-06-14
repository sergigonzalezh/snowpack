#!/bin/bash
#SBATCH --nodes=1
#SBATCH --account=s1329
#SBATCH --time=04:00:00
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --job-name=bald_retry
#SBATCH --output=logs/retry_%j.out
#SBATCH --error=logs/retry_%j.err
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack

cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup

echo "Starting retry at $(date)"
echo "Total retry jobs: $(wc -l < to_exec_retry.lst)"

cat to_exec_retry.lst | parallel -j 128

echo "Finished at $(date)"
for dom in d01 d02 d03 d04; do
    echo "${dom} SNO files: $(ls output/${dom}/*.sno 2>/dev/null | wc -l)"
done
