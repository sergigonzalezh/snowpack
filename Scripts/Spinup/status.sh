#!/bin/bash
#
# Check spinup progress
#

cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup

total=18988
completed=$(grep -l "final.ini" cfgfiles/*.ini 2>/dev/null | wc -l)
output_count=$(ls output/*.sno 2>/dev/null | wc -l)
in_progress=$((output_count - completed))
not_started=$((total - output_count))

pct_completed=$(awk "BEGIN{printf \"%.1f\", $completed*100/$total}")
pct_progress=$(awk "BEGIN{printf \"%.1f\", $in_progress*100/$total}")
pct_not_started=$(awk "BEGIN{printf \"%.1f\", $not_started*100/$total}")

echo "| Status         | Count  | %     |"
echo "|----------------|--------|-------|"
echo "| ✅ Completed    | $(printf '%6d' $completed) | ${pct_completed}% |"
echo "| 🔄 In progress  | $(printf '%6d' $in_progress) | ${pct_progress}% |"
echo "| ⏳ Not started  | $(printf '%6d' $not_started) | ${pct_not_started}% |"
