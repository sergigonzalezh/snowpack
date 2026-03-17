#!/bin/bash
#SBATCH --job-name=era5_extract
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --partition=normal
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf

# Extract years 1980-1989
for year in 1980 1981 1982 1983 1984 1985 1986 1987 1988 1989; do
    echo "Extracting year ${year}..."
    ./create_forcing.sh ERA5 ${year}
done

echo "Extraction complete!"
