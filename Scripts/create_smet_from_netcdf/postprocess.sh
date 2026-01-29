#!/bin/bash

# Retrieve script variables
model=${1:-ERA5}

# Concatenate files into a single timeseries per station across all years
# Find year directories (e.g., ERA5_1980, ERA5_1981, ...)
year_dirs=$(ls -d output/${model}_[0-9][0-9][0-9][0-9] 2>/dev/null | sort)

if [ -z "${year_dirs}" ]; then
	echo "No output files found matching pattern: output/${model}_YYYY"
	exit 1
fi

echo "Found year directories:"
echo "${year_dirs}" | head -5
echo "..."

# Get list of station files from the first year directory
first_dir=$(echo "${year_dirs}" | head -1)
echo "Using ${first_dir} as reference for station list..."

# Count stations
n_stations=$(ls ${first_dir}/*.smet 2>/dev/null | wc -l)
echo "Found ${n_stations} stations to concatenate"

# Create output directory for concatenated files
mkdir -p output/concatenated

# Process each station
count=0
for f in ${first_dir}/*.smet; do
	station=$(basename ${f} .smet)
	count=$((count + 1))

	# Show progress every 1000 stations
	if [ $((count % 1000)) -eq 0 ]; then
		echo "Processing station ${count}/${n_stations}: ${station}"
	fi

	# Concatenate all years for this station
	# Keep header from first file, then append data sections from all files
	first_file=1
	for year_dir in ${year_dirs}; do
		smet_file="${year_dir}/${station}.smet"
		if [ -f "${smet_file}" ]; then
			if [ ${first_file} -eq 1 ]; then
				# First file: keep everything up to and including [DATA]
				awk '{print; if(/\[DATA\]/) exit}' "${smet_file}" > "output/concatenated/${station}.smet"
				# Then append data (lines after [DATA])
				awk 'BEGIN{data=0} {if(data==1) print; if(/\[DATA\]/) data=1}' "${smet_file}" >> "output/concatenated/${station}.smet"
				first_file=0
			else
				# Subsequent files: only append data section (skip header)
				awk 'BEGIN{data=0} {if(data==1) print; if(/\[DATA\]/) data=1}' "${smet_file}" >> "output/concatenated/${station}.smet"
			fi
		fi
	done
done

echo "Concatenation complete: ${count} stations processed"
echo "Output files in: output/concatenated/"

# Zip output .smet files
echo "Creating zip archive..."
cd output/concatenated
zip -q ../smet_forcing.zip *.smet
cd ../..
echo "Done! Archive: output/smet_forcing.zip"
