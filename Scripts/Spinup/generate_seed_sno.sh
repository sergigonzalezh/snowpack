#!/bin/bash
#
# Generate seed .sno files for all stations
# Each file has a 10cm initial snow layer to allow proper accumulation
#
# Usage: bash generate_seed_sno.sh
#

SMET_DIR="./smet"
SNO_DIR="./current_snow"
PROFILE_DATE="1980-01-01T00:00:00"

# Default snow layer parameters
LAYER_THICK="0.10"      # 10 cm seed layer
INIT_TEMP="230.0"       # -43°C (cold plateau default)
VOL_FRAC_I="0.35"       # Ice fraction
VOL_FRAC_V="0.65"       # Void fraction

echo "Generating seed .sno files..."
echo "Source: ${SMET_DIR}"
echo "Output: ${SNO_DIR}"

# Create output directory if needed
mkdir -p "${SNO_DIR}"

# Count files
total=$(ls ${SMET_DIR}/*.smet 2>/dev/null | wc -l)
count=0

for smet_file in ${SMET_DIR}/*.smet; do
    # Extract filename without path and extension
    filename=$(basename "${smet_file}" .smet)
    sno_file="${SNO_DIR}/${filename}.sno"

    # Extract header info from SMET file
    station_id=$(grep "^station_id" "${smet_file}" | head -1 | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    station_name=$(grep "^station_name" "${smet_file}" | head -1 | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    latitude=$(grep "^latitude" "${smet_file}" | head -1 | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    longitude=$(grep "^longitude" "${smet_file}" | head -1 | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')
    altitude=$(grep "^altitude" "${smet_file}" | head -1 | awk -F'=' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')

    # Adjust initial temperature based on altitude
    # Higher altitudes = colder
    if (( $(echo "${altitude} < 1000" | bc -l) )); then
        temp="250.0"  # -23°C for low elevations
    elif (( $(echo "${altitude} < 2000" | bc -l) )); then
        temp="240.0"  # -33°C for mid elevations
    else
        temp="230.0"  # -43°C for high plateau
    fi

    # Write the .sno file
    cat > "${sno_file}" << EOF
SMET 1.1 ASCII
[HEADER]
station_id       = ${station_id}
station_name     = ${station_name}
latitude         = ${latitude}
longitude        = ${longitude}
altitude         = ${altitude}
nodata           = -999
tz               = 0
slope_angle      = 0
slope_azi        = 0
ProfileDate      = ${PROFILE_DATE}
HS_Last          = ${LAYER_THICK}
SlopeAngle       = 0.00
SlopeAzi         = 0.00
nSoilLayerData   = 0
nSnowLayerData   = 1
SoilAlbedo       = 0.09
BareSoil_z0      = 0.020
CanopyHeight     = 0.000
CanopyLeafAreaIndex = 0.000000
CanopyDirectThroughfall = 1.00
WindScalingFactor = 1.00
ErosionLevel     = 0
TimeCountDeltaHS = 0.000000
fields           = timestamp Layer_Thick  T  Vol_Frac_I  Vol_Frac_W  Vol_Frac_V  Vol_Frac_S Rho_S Conduc_S HeatCapac_S  rg  rb  dd  sp  mk mass_hoar ne CDot metamo
[DATA]
${PROFILE_DATE} ${LAYER_THICK} ${temp} ${VOL_FRAC_I} 0.0 ${VOL_FRAC_V} 0.0 0.0 0.0 0.0 1.0 0.5 0.0 0.0 1 0.0 1 0.0 0.0
EOF

    ((count++))

    # Progress update every 1000 files
    if (( count % 1000 == 0 )); then
        echo "  Processed ${count}/${total} files..."
    fi
done

echo "Done! Generated ${count} seed .sno files in ${SNO_DIR}"
