#!/bin/bash
#
# Script to check spinup progress and optionally resubmit incomplete stations
#
# Usage:
#   bash check_progress.sh          # Check progress only
#   bash check_progress.sh resubmit # Check and resubmit incomplete stations
#

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

MIN_DEPTH=10  # Target depth in meters

echo "=============================================="
echo "SPINUP PROGRESS CHECK"
echo "=============================================="
echo ""

# Count total stations
total=$(wc -l < to_exec.lst)
echo "Total stations: ${total}"

# Count completed (output SNO files with depth >= MIN_DEPTH)
completed=0
incomplete_list=""

for sno in output/*.sno 2>/dev/null; do
    if [ -f "$sno" ]; then
        depth=$(awk 'BEGIN {s=0; d=0} {if(d) {s+=$2}; if(/\[DATA\]/) {d=1}} END {print s}' "$sno")
        if (( $(echo "$depth >= $MIN_DEPTH" | bc -l) )); then
            completed=$((completed + 1))
        fi
    fi
done

# Count in-progress (current_snow files)
in_progress=$(ls current_snow/*.sno 2>/dev/null | wc -l)

# Count not started
not_started=$((total - completed - in_progress))
if [ $not_started -lt 0 ]; then
    not_started=0
fi

echo "Completed (depth >= ${MIN_DEPTH}m): ${completed}"
echo "In progress: ${in_progress}"
echo "Not started: ${not_started}"
echo ""

# Show percentage
pct=$(echo "scale=1; $completed * 100 / $total" | bc)
echo "Progress: ${pct}% complete"
echo ""

# Check for errors in recent logs
echo "=== Recent errors (if any) ==="
grep -l "error\|ERROR\|Error" logs/*.err 2>/dev/null | head -5
grep -h "error while loading\|cannot open\|ERROR:" log/*.log 2>/dev/null | sort -u | head -5
echo ""

# If resubmit argument provided, create list of incomplete stations and resubmit
if [ "$1" == "resubmit" ]; then
    echo "=== Creating incomplete stations list ==="

    # Create list of incomplete task IDs
    > incomplete_tasks.lst
    task_id=0

    while IFS= read -r line; do
        task_id=$((task_id + 1))
        # Extract station name from command
        stn=$(echo "$line" | grep -oP 'cfgfiles/\K[^.]+')
        sno_out="output/${stn}.sno"

        if [ -f "$sno_out" ]; then
            depth=$(awk 'BEGIN {s=0; d=0} {if(d) {s+=$2}; if(/\[DATA\]/) {d=1}} END {print s}' "$sno_out")
            if (( $(echo "$depth < $MIN_DEPTH" | bc -l) )); then
                echo "$task_id" >> incomplete_tasks.lst
            fi
        else
            echo "$task_id" >> incomplete_tasks.lst
        fi
    done < to_exec.lst

    n_incomplete=$(wc -l < incomplete_tasks.lst)
    echo "Found ${n_incomplete} incomplete stations"

    if [ $n_incomplete -gt 0 ]; then
        # Create comma-separated list for SLURM array
        array_spec=$(paste -sd, incomplete_tasks.lst)

        # Create resubmit script
        cat > resubmit.sbatch << EOF
#!/bin/bash
#SBATCH --nodes=1
#SBATCH --account=s1329
#SBATCH --time=24:00:00
#SBATCH --partition=normal
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --job-name=spinup_resub
#SBATCH --output=logs/spinup_%A_%a.out
#SBATCH --error=logs/spinup_%A_%a.err
#SBATCH --mail-type=END,FAIL
#SBATCH --mail-user=sergi.gonzalez@slf.ch
#SBATCH --uenv=prgenv-gnu/24.11:v2
#SBATCH --view=spack
#SBATCH --array=${array_spec}

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

if [ -n "\${SLURM_ARRAY_TASK_ID}" ]; then
    command1=\$(sed -n \${SLURM_ARRAY_TASK_ID}p to_exec.lst)
fi

if [ -n "\${command1}" ]; then
    eval \${command1}
    echo \${command1} >> finished.lst
fi
EOF

        echo "Created resubmit.sbatch with ${n_incomplete} tasks"
        echo ""
        echo "To submit: sbatch resubmit.sbatch"
    else
        echo "All stations complete! Nothing to resubmit."
    fi
fi

echo ""
echo "=============================================="
