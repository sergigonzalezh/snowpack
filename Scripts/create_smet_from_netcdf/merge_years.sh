#!/bin/bash
#
# Merge multi-year SMET files into single files for each station
# This concatenates the [DATA] sections while keeping the header
#

OUTPUT_DIR="/capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf/output"
MERGED_DIR="/capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup/smet"

# List of stations to merge
STATIONS="VIR_1_100_100 VIR_1_150_150"

for station in ${STATIONS}; do
    echo "Merging ${station}..."

    # Get header from first year (1980)
    first_file="${OUTPUT_DIR}/ERA5_1980/${station}.smet"
    if [ ! -f "${first_file}" ]; then
        echo "  ERROR: ${first_file} not found!"
        continue
    fi

    # Extract header (everything up to and including [DATA])
    sed -n '1,/\[DATA\]/p' "${first_file}" > "${MERGED_DIR}/${station}.smet"

    # Append data from all years
    for year in 1980 1981 1982 1983 1984 1985 1986 1987 1988 1989; do
        smet_file="${OUTPUT_DIR}/ERA5_${year}/${station}.smet"
        if [ -f "${smet_file}" ]; then
            # Extract data (everything after [DATA])
            sed -n '/\[DATA\]/,$p' "${smet_file}" | tail -n +2 >> "${MERGED_DIR}/${station}.smet"
            echo "  Added ${year}"
        else
            echo "  WARNING: ${smet_file} not found!"
        fi
    done
done

echo "Merge complete!"
