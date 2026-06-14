#!/bin/bash
#SBATCH --nodes=1
#SBATCH --account=s1329
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=128
#SBATCH --mem=0
#SBATCH --job-name=balandrau_spinup
#SBATCH --output=logs/balandrau_%j.out
#SBATCH --error=logs/balandrau_%j.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sergi.gonzalez@slf.ch
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack

cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup

mkdir -p logs log/d01 log/d02 log/d03 log/d04

echo "Starting Balandrau spinup at $(date)"
echo "Total jobs: $(wc -l < to_exec.lst)"

cat to_exec.lst | parallel -j 128

echo "Finished at $(date)"
for dom in d01 d02 d03 d04; do
    echo "${dom} SNO files: $(ls output/${dom}/*.sno 2>/dev/null | wc -l)"
done
