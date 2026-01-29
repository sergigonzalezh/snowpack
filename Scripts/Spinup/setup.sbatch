#!/bin/bash
#SBATCH --job-name=spinup_setup
#SBATCH --output=logs/setup_%j.out
#SBATCH --error=logs/setup_%j.err
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --account=s1329
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sergi.gonzalez@slf.ch

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

echo "Starting setup at $(date)"
echo "Creating SNO and config files from SMET files..."

# Run the setup script
bash run_snowpack.sh

echo "Setup complete at $(date)"
echo "SNO files created: $(ls snow_init/ | wc -l)"
echo "Config files created: $(ls cfgfiles/ | wc -l)"
echo "Execution list: $(wc -l < to_exec.lst) jobs"
