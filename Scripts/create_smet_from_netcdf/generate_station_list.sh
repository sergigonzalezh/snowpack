#!/bin/bash
#
# Generate station_list.lst from existing SMET files in the Spinup folder
# This extracts lat/lon from each SMET header and creates MeteoIO format
#

SMET_DIR="/capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup/smet"
OUTPUT_FILE="/capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/create_smet_from_netcdf/station_list.lst"

echo "[INPUTEDITING]" > ${OUTPUT_FILE}

counter=1
for smet_file in ${SMET_DIR}/*.smet; do
    # Extract station ID from filename (e.g., VIR_1_100_100.smet -> VIR_1_100_100)
    station_id=$(basename ${smet_file} .smet)

    # Extract latitude and longitude from SMET header
    lat=$(grep "^latitude" ${smet_file} | awk -F= '{gsub(/[ \t]/,"",$2); print $2}')
    lon=$(grep "^longitude" ${smet_file} | awk -F= '{gsub(/[ \t]/,"",$2); print $2}')

    # Write to station list in MeteoIO format
    echo "VSTATION${counter} = latlon ${lat} ${lon} 0" >> ${OUTPUT_FILE}
    echo "VID${counter} = ${station_id}" >> ${OUTPUT_FILE}

    counter=$((counter + 1))

    # Progress indicator every 1000 stations
    if [ $((counter % 1000)) -eq 0 ]; then
        echo "Processed ${counter} stations..."
    fi
done

echo "Generated station_list.lst with $((counter - 1)) stations"
