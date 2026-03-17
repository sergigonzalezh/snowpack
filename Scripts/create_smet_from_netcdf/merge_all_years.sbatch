#!/bin/bash
#
# SLURM batch job to merge ERA5 instant and accum NetCDF files for all years
# Single node parallel execution
#
#SBATCH --job-name=merge_era5
#SBATCH --output=logs/merge_%j.out
#SBATCH --error=logs/merge_%j.err
#SBATCH --time=04:00:00
#SBATCH --partition=normal
#SBATCH --account=s1329
#SBATCH --nodes=1
#SBATCH --ntasks=45
#SBATCH --cpus-per-task=1
#SBATCH --mem=0
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sergi.gonzalez@slf.ch
#SBATCH --uenv=netcdf-tools/2024:v1

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf

INPUT_DIR="/capstor/store/cscs/userlab/s1329/DATA_ANT_CLIM/ERA5_3hourly_1980_2024"
OUTPUT_DIR="/capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf/input/ERA5_merged"

echo "Starting ERA5 merge at $(date)"
echo "Running 45 years in parallel on single node..."

# Function to merge one year
merge_year() {
    YEAR=$1

    mkdir -p ${OUTPUT_DIR}/${YEAR}

    INSTANT_FILE="${INPUT_DIR}/${YEAR}/data_stream-oper_stepType-instant.nc"
    ACCUM_FILE="${INPUT_DIR}/${YEAR}/data_stream-oper_stepType-accum.nc"
    OUTPUT_FILE="${OUTPUT_DIR}/${YEAR}/ERA5_${YEAR}.nc"

    # Check input files exist
    if [ ! -f "$INSTANT_FILE" ]; then
        echo "ERROR: Instant file not found: $INSTANT_FILE"
        return 1
    fi

    if [ ! -f "$ACCUM_FILE" ]; then
        echo "ERROR: Accum file not found: $ACCUM_FILE"
        return 1
    fi

    # Check if output already exists
    if [ -f "$OUTPUT_FILE" ]; then
        echo "Output file already exists: $OUTPUT_FILE - Skipping"
        return 0
    fi

    echo "Merging year ${YEAR}..."
    cdo -O merge ${INSTANT_FILE} ${ACCUM_FILE} ${OUTPUT_FILE}

    if [ $? -eq 0 ]; then
        echo "Successfully created: ${OUTPUT_FILE}"
    else
        echo "ERROR: Merge failed for year ${YEAR}"
        return 1
    fi
}

export -f merge_year
export INPUT_DIR OUTPUT_DIR

# Run all years in parallel
seq 1980 2024 | parallel -j 45 merge_year

echo "Finished ERA5 merge at $(date)"
