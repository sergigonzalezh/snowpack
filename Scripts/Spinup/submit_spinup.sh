#!/bin/bash
# Convenient script to submit the spinup job
# Usage: bash submit_spinup.sh

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

echo "========================================="
echo "SNOWPACK Antarctic Spinup Submission"
echo "========================================="
echo ""

# Check if current_snow needs cleaning
n_current=$(ls current_snow/*.sno 2>/dev/null | wc -l)
if [ $n_current -gt 0 ]; then
    echo "WARNING: current_snow directory contains $n_current files"
    echo "These may be from a previous run. Clean before starting fresh."
    echo ""
    read -p "Clean current_snow directory? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f current_snow/*.sno
        echo "Cleaned current_snow directory"
    fi
    echo ""
fi

# Check snow_init
n_init=$(ls snow_init/*.sno 2>/dev/null | wc -l)
echo "Snow initialization files: $n_init"
if [ $n_init -eq 0 ]; then
    echo "ERROR: No snow initialization files found in snow_init/"
    exit 1
fi

# Check first snow_init file
first_sno=$(ls snow_init/*.sno 2>/dev/null | head -1)
n_layers=$(grep "nSnowLayerData" "$first_sno" | awk '{print $NF}')
hs_last=$(grep "HS_Last" "$first_sno" | awk '{print $NF}')
echo "First snow file: $(basename $first_sno)"
echo "  Snow layers: $n_layers"
echo "  Total depth: $hs_last m"
echo ""

# Check smet files
n_smet=$(ls smet/*.smet 2>/dev/null | wc -l)
echo "Meteorological forcing files: $n_smet"
if [ $n_smet -eq 0 ]; then
    echo "ERROR: No smet files found in smet/"
    exit 1
fi
echo ""

# Check execution list
n_exec=$(wc -l < to_exec.lst)
echo "Stations to process: $n_exec"
echo ""

# Estimated time
echo "Estimated runtime: ~24 hours (varies by station)"
echo ""

# Confirm submission
read -p "Submit spinup job to SLURM? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    jobid=$(sbatch job.sbatch | awk '{print $NF}')
    echo ""
    echo "Job submitted: $jobid"
    echo ""
    echo "Monitor with:"
    echo "  squeue -u gsergi"
    echo "  tail -f logs/spinup_${jobid}.out"
    echo "  bash check_progress.sh"
    echo ""
    echo "Check logs:"
    echo "  ls -lth logs/"
    echo "  ls output/*.sno | wc -l"
else
    echo "Submission cancelled"
fi
