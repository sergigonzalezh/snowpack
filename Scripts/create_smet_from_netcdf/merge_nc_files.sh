#!/bin/bash
#
# Merge ERA5 instant and accum NetCDF files into a single file per year
# This is needed because MeteoIO cannot read from multiple file patterns
#
# Usage: uenv run prgenv-gnu/24.11:v2 -- bash merge_nc_files.sh <year>
# Note: CDO is available in prgenv-gnu environment
#

INPUT_DIR="/capstor/store/cscs/userlab/s1329/DATA_ANT_CLIM/ERA5_3hourly_1980_2024"
OUTPUT_DIR="/capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf/input/ERA5_merged"

# Get year from argument
YEAR=$1

if [ -z "$YEAR" ]; then
    echo "Usage: $0 <year>"
    exit 1
fi

echo "Merging ERA5 files for year ${YEAR}..."

# Create output directory
mkdir -p ${OUTPUT_DIR}/${YEAR}

# Input files
INSTANT_FILE="${INPUT_DIR}/${YEAR}/data_stream-oper_stepType-instant.nc"
ACCUM_FILE="${INPUT_DIR}/${YEAR}/data_stream-oper_stepType-accum.nc"
OUTPUT_FILE="${OUTPUT_DIR}/${YEAR}/ERA5_${YEAR}.nc"

# Check input files exist
if [ ! -f "$INSTANT_FILE" ]; then
    echo "ERROR: Instant file not found: $INSTANT_FILE"
    exit 1
fi

if [ ! -f "$ACCUM_FILE" ]; then
    echo "ERROR: Accum file not found: $ACCUM_FILE"
    exit 1
fi

# Check if output already exists
if [ -f "$OUTPUT_FILE" ]; then
    echo "Output file already exists: $OUTPUT_FILE"
    echo "Skipping..."
    exit 0
fi

# Merge using CDO (Climate Data Operators)
echo "Merging ${INSTANT_FILE} and ${ACCUM_FILE}..."
cdo -O merge ${INSTANT_FILE} ${ACCUM_FILE} ${OUTPUT_FILE}

if [ $? -eq 0 ]; then
    echo "Successfully created: ${OUTPUT_FILE}"
    # Show variables in merged file
    echo "Variables in merged file:"
    ncdump -h ${OUTPUT_FILE} | grep "float\|double" | grep -v "latitude\|longitude"
else
    echo "ERROR: Merge failed for year ${YEAR}"
    exit 1
fi
