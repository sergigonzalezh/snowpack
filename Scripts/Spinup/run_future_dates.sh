#!/bin/bash
#
# Run SNOWPACK for all stations to extract .sno snapshots at FUTURE dates.
#
# The final .sno files (ProfileDate=2024-12-31) are used directly as initial state.
# SNOWPACK runs forward using NEW smet forcing data (from 2025 onward), stopping
# at each requested date to save the .sno state.
#
# Usage:
#   bash run_future_dates.sh <dates_file> <future_smet_dir> [output_dir]
#
#   dates_file:       text file with one date per line in YYYY-MM-DDTHH:MM format
#                     Dates must be after 2024-12-31
#                     They will be sorted chronologically automatically.
#   future_smet_dir:  directory containing .smet files with forcing from 2025 onward
#                     (must cover up to the latest requested date)
#   output_dir:       (optional) directory for results (default: ./future_dates_output)
#
# Example dates_file:
#   2025-06-01T00:00
#   2026-01-01T00:00
#   2030-12-31T18:00
#
# Output structure:
#   <output_dir>/
#   ├── sno_YYYY-MM-DD/    # .sno snapshots for each requested date
#   └── logs/              # per-station logs
#

set -euo pipefail
export TZ=UTC

# ---- Configuration (all paths converted to absolute) ----
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNOWPACK_BIN="/users/gsergi/ALPINE3D/bin/snowpack"
FINAL_SNO_DIR="$(cd "${SCRIPT_DIR}/Results/final_sno" && pwd)"
CFG_DIR="$(cd "${SCRIPT_DIR}/cfgfiles" && pwd)"
BASE_INI="${SCRIPT_DIR}/base.ini"
EXTRACT_INI="${SCRIPT_DIR}/extract_dates.ini"

# ---- Parse arguments ----
if [ $# -lt 2 ]; then
    echo "Usage: bash run_future_dates.sh <dates_file> <future_smet_dir> [output_dir]"
    echo ""
    echo "  dates_file:      one date per line, YYYY-MM-DDTHH:MM (after 2024-12-31)"
    echo "  future_smet_dir: dir with .smet forcing from 2025 onward"
    echo "  output_dir:      output directory (default: ./future_dates_output)"
    exit 1
fi

DATES_FILE="$1"
FUTURE_SMET_DIR="$(readlink -f "$2")"
OUTPUT_DIR="$(readlink -f "${3:-./future_dates_output}")"

if [ ! -f "${DATES_FILE}" ]; then
    echo "ERROR: dates file not found: ${DATES_FILE}"
    exit 1
fi
if [ ! -d "${FUTURE_SMET_DIR}" ]; then
    echo "ERROR: future smet directory not found: ${FUTURE_SMET_DIR}"
    exit 1
fi

# Sort dates chronologically
DATES=($(sort "${DATES_FILE}"))
echo "Dates to extract: ${DATES[@]}"

# ---- Setup directories ----
WORK_SNOW="${OUTPUT_DIR}/current_snow"
WORK_OUTPUT="${OUTPUT_DIR}/output"
LOG_DIR="${OUTPUT_DIR}/logs"
mkdir -p "${WORK_SNOW}" "${WORK_OUTPUT}" "${LOG_DIR}"

for d in "${DATES[@]}"; do
    date_label=$(echo "$d" | cut -c1-10)
    mkdir -p "${OUTPUT_DIR}/sno_${date_label}"
done

# ---- Generate station list ----
STATION_LIST="${OUTPUT_DIR}/stations.lst"
ls "${FINAL_SNO_DIR}"/*.sno | xargs -n1 basename | sed 's/\.sno$//' > "${STATION_LIST}"
TOTAL=$(wc -l < "${STATION_LIST}")
echo "Total stations: ${TOTAL}"

# ---- Create run script for a single station ----
RUN_SINGLE="${OUTPUT_DIR}/run_single_station.sh"
cat > "${RUN_SINGLE}" << 'SCRIPTEOF'
#!/bin/bash
set -euo pipefail
export TZ=UTC

STATION="$1"
SNOWPACK_BIN="$2"
FINAL_SNO_DIR="$3"
FUTURE_SMET_DIR="$4"
CFG_DIR="$5"
BASE_INI="$6"
EXTRACT_INI="$7"
OUTPUT_DIR="$8"
shift 8
DATES=("$@")

WORK_SNOW="${OUTPUT_DIR}/current_snow"
WORK_OUTPUT="${OUTPUT_DIR}/output"
LOG_DIR="${OUTPUT_DIR}/logs"

# Use final .sno directly (no time-shift needed, already at 2024-12-31)
cp "${FINAL_SNO_DIR}/${STATION}.sno" "${WORK_SNOW}/${STATION}.sno"

# Create a temporary .ini pointing to future smet data
TMP_INI="${OUTPUT_DIR}/tmp_cfgfiles/${STATION}.ini"
mkdir -p "${OUTPUT_DIR}/tmp_cfgfiles"
cat > "${TMP_INI}" << EOF
[GENERAL]
IMPORT_BEFORE = ${BASE_INI}
IMPORT_AFTER = ${EXTRACT_INI}
[INPUT]
STATION1 = ${STATION}.smet
SNOWFILE1 = ${STATION}.sno
METEOPATH = ${FUTURE_SMET_DIR}
SNOWPATH = ${WORK_SNOW}
[OUTPUT]
METEOPATH = ${WORK_OUTPUT}
EXPERIMENT = NO_EXP
EOF

# Run sequentially to each date
prev_end=""
for d in "${DATES[@]}"; do
    date_label=$(echo "$d" | cut -c1-10)

    # If not the first date, use previous output as input
    if [ -n "${prev_end}" ] && [ -f "${WORK_OUTPUT}/${STATION}.sno" ]; then
        cp "${WORK_OUTPUT}/${STATION}.sno" "${WORK_SNOW}/${STATION}.sno"
    fi

    # Run SNOWPACK to this date
    ${SNOWPACK_BIN} -c "${TMP_INI}" -e "${d}" > "${LOG_DIR}/${STATION}_${date_label}.log" 2>&1

    # Save the .sno snapshot
    if [ -f "${WORK_OUTPUT}/${STATION}.sno" ]; then
        cp "${WORK_OUTPUT}/${STATION}.sno" "${OUTPUT_DIR}/sno_${date_label}/${STATION}.sno"
    else
        echo "WARNING: no .sno output for ${STATION} at ${d}" >> "${LOG_DIR}/${STATION}_${date_label}.log"
    fi

    prev_end="${d}"
done

# Cleanup working files for this station
rm -f "${WORK_SNOW}/${STATION}.sno"
rm -f "${WORK_OUTPUT}/${STATION}.sno"
rm -f "${WORK_OUTPUT}/${STATION}.smet"
rm -f "${WORK_OUTPUT}/${STATION}_NO_EXP"*
rm -f "${TMP_INI}"
SCRIPTEOF
chmod +x "${RUN_SINGLE}"

# ---- Generate parallel execution list ----
EXEC_LIST="${OUTPUT_DIR}/to_exec.lst"
> "${EXEC_LIST}"
while read -r stn; do
    echo "bash ${RUN_SINGLE} ${stn} ${SNOWPACK_BIN} ${FINAL_SNO_DIR} ${FUTURE_SMET_DIR} ${CFG_DIR} ${BASE_INI} ${EXTRACT_INI} ${OUTPUT_DIR} ${DATES[*]}" >> "${EXEC_LIST}"
done < "${STATION_LIST}"

echo ""
echo "============================================"
echo "Setup complete. To run, submit the job:"
echo "  sbatch ${OUTPUT_DIR}/job_future_dates.sbatch"
echo ""
echo "Or run directly with:"
echo "  cat ${EXEC_LIST} | parallel -j \$(nproc)"
echo "============================================"
