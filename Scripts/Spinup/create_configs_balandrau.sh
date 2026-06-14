#!/bin/bash
# Create empty SNO files, per-station ini files, and to_exec.lst
# for a single SNOWPACK run (Sept 1 – Dec 29, 2000).
#
# Run this AFTER make_smet_from_era5land.py has finished.
# Submit the run with: sbatch job_balandrau.sbatch

SNOWPACK="/users/gsergi/ALPINE3D/bin/snowpack"
END_DATE="2000-12-29"
BASE_INI="../../base_balandrau.ini"   # relative to cfgfiles/dXX/

for dom in d01 d02 d03 d04; do
    mkdir -p "snow_init/${dom}"
    mkdir -p "cfgfiles/${dom}"
    mkdir -p "output/${dom}"
    mkdir -p "current_snow/${dom}"
    mkdir -p "log/${dom}"
done
mkdir -p logs

> to_exec.lst

total=0
for dom in d01 d02 d03 d04; do
    n=0
    for f in "./smet/${dom}/"*.smet; do
        [ -f "$f" ] || continue
        stn=$(basename "${f}" .smet)

        lat=$(awk '/^latitude/  {print $NF}' "${f}")
        lon=$(awk '/^longitude/ {print $NF}' "${f}")
        alt=$(awk '/^altitude/  {print $NF}' "${f}")
        start=$(awk '/^\[DATA\]/{found=1; next} found{print $1; exit}' "${f}")

        snofile="./current_snow/${dom}/${stn}.sno"
        cfgfile="./cfgfiles/${dom}/${stn}.ini"

        # Empty SNO (no snow, bare ground)
        cat > "${snofile}" << SNOEOF
SMET 1.1 ASCII
[HEADER]
station_id       = ${stn}
station_name     = ${stn}
latitude         = ${lat}
longitude        = ${lon}
altitude         = ${alt}
nodata           = -999
ProfileDate      = ${start}
HS_Last          = 0.00
SlopeAngle       = 0.00
SlopeAzi         = 0.00
nSoilLayerData   = 0
nSnowLayerData   = 0
SoilAlbedo       = 0.09
BareSoil_z0      = 0.020
CanopyHeight     = 0.00
CanopyLeafAreaIndex = 0.00
CanopyDirectThroughfall = 1.00
WindScalingFactor = 1.00
ErosionLevel     = 0
TimeCountDeltaHS = 0.000000
fields           = timestamp Layer_Thick T Vol_Frac_I Vol_Frac_W Vol_Frac_V Vol_Frac_S Rho_S Conduc_S HeatCapac_S rg rb dd sp mk mass_hoar ne CDot metamo
[DATA]
SNOEOF

        # Per-station ini
        # IMPORT_BEFORE: relative to ini file location (cfgfiles/dXX/)
        # METEOPATH/SNOWPATH: relative to working directory (Scripts/Spinup/)
        cat > "${cfgfile}" << INIEOF
[GENERAL]
IMPORT_BEFORE = ../../base_balandrau.ini

[INPUT]
METEOPATH  = smet/${dom}/
SNOWPATH   = current_snow/${dom}/
METEOFILE1 = ${stn}.smet
SNOWFILE1  = ${stn}.sno

[OUTPUT]
METEOPATH  = output/${dom}/
PROF_WRITE = FALSE
TS_WRITE   = FALSE
INIEOF

        echo "${SNOWPACK} -c ${cfgfile} -e ${END_DATE} > log/${dom}/${stn}.log 2>&1" >> to_exec.lst
        n=$((n + 1))
    done
    echo "${dom}: ${n} stations"
    total=$((total + n))
done

echo "Total: ${total} entries in to_exec.lst"
echo "Submit with: sbatch job_balandrau.sbatch"
