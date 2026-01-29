#!/bin/bash
#
# Update all station config files for production spinup
# This ensures each config imports base.ini and spinup.ini correctly
#
# Usage: bash update_station_configs.sh
#

SMET_DIR="./smet"
CFG_DIR="./cfgfiles"

echo "Updating station config files..."
echo "Source SMET: ${SMET_DIR}"
echo "Output CFG: ${CFG_DIR}"

# Create output directory if needed
mkdir -p "${CFG_DIR}"

# Count files
total=$(ls ${SMET_DIR}/*.smet 2>/dev/null | wc -l)
count=0

for smet_file in ${SMET_DIR}/*.smet; do
    # Extract filename without path and extension
    filename=$(basename "${smet_file}" .smet)
    cfg_file="${CFG_DIR}/${filename}.ini"

    # Write the config file
    cat > "${cfg_file}" << EOF
[GENERAL]
IMPORT_BEFORE		=	../base.ini
IMPORT_AFTER		=	../spinup.ini
[INPUT]
STATION1		=	${filename}.smet
SNOWFILE1		=	${filename}.sno
[OUTPUT]
PROF_WRITE		=       FALSE
TS_WRITE		=       FALSE
EXPERIMENT		=	NO_EXP
EOF

    ((count++))

    # Progress update every 1000 files
    if (( count % 1000 == 0 )); then
        echo "  Processed ${count}/${total} files..."
    fi
done

echo "Done! Updated ${count} config files in ${CFG_DIR}"
