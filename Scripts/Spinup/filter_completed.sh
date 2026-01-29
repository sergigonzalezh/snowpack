#!/bin/bash
#
# Filter out completed stations from to_exec.lst
# A station is considered complete if its config file contains "final.ini"
#

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

echo "Filtering completed stations from to_exec.lst..."

# Count before
total_before=$(wc -l < to_exec.lst)

# Create new list excluding completed stations
> to_exec.lst.new
completed=0
remaining=0

for f in smet/*.smet; do
    station=$(basename $f .smet)
    if grep -q "final.ini" "cfgfiles/${station}.ini" 2>/dev/null; then
        ((completed++))
    else
        echo "bash spinup.sh \"/users/gsergi/ALPINE3D/bin/snowpack -c cfgfiles/${station}.ini -e 2024-12-31T18:00:00 > log/${station}_NO_EXP.log 2>&1\"" >> to_exec.lst.new
        ((remaining++))
    fi
done

# Replace original with filtered list
mv to_exec.lst.new to_exec.lst

echo "  Total stations: $total_before"
echo "  Already completed (skipped): $completed"
echo "  Remaining to process: $remaining"
echo "Done."
