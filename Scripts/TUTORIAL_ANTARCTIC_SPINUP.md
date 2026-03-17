# SNOWPACK Antarctic Firn Spinup Tutorial

A comprehensive step-by-step guide for running SNOWPACK firn spinup simulations
for Antarctica using ERA5 reanalysis forcing data.

**Author:** Sergi Gonzalez
**Last Updated:** March 2026
**Repository:** SNOWPACK Antarctic Climate Simulations

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: ERA5 Data Preparation](#phase-1-era5-data-preparation)
4. [Phase 2: SNOWPACK Spinup](#phase-2-snowpack-spinup)
5. [Phase 3: Extract .sno Snapshots at Specific Dates](#phase-3-extract-sno-snapshots-at-specific-dates)
6. [Monitoring and Validation](#monitoring-and-validation)
7. [Critical Configuration Parameters](#critical-configuration-parameters)
8. [Troubleshooting](#troubleshooting)
9. [Quick Reference Cheatsheet](#quick-reference-cheatsheet)
10. [Appendix: File Formats](#appendix-file-formats)

---

## Overview

### What is a Firn Spinup?

A firn spinup is a model initialization procedure that builds a realistic firn column
(compacted snow layers) by running the model repeatedly over the same time period.
In Antarctica, firn can be 50-100+ meters deep, requiring multiple simulation cycles
to develop a realistic vertical profile.

### Workflow Summary

```
ERA5 NetCDF  -->  .smet forcing  -->  Spinup  -->  final .sno (2024-12-31)
                                                         |
                                          +--------------+--------------+
                                          |                             |
                                    Past dates                    Future dates
                                  (1980-2024)                     (2025+)
                                  time-shift back,              use as-is,
                                  run with existing smet        run with new smet
```

### Key Components

| Component | Description |
|-----------|-------------|
| **MeteoIO** | Data processing library that extracts and converts ERA5 data |
| **SNOWPACK** | Snow/firn physics model |
| **Virtual Stations** | Grid points where simulations are performed |
| **SMET Files** | Meteorological forcing data format |
| **SNO Files** | Snow profile initialization/output format |

### Directory Structure

```
snowpack/Scripts/
├── create_smet_from_netcdf/    # Phase 1: Data preparation
│   ├── io_files/               # MeteoIO configuration files
│   │   ├── base.ini            # Base configuration
│   │   └── ERA5.ini            # ERA5-specific settings
│   ├── station_list.lst        # Virtual station definitions
│   ├── create_forcing.sh       # Main extraction script
│   ├── merge_nc_files.sh       # Merge instant+accum NetCDF
│   ├── merge_all_years.sbatch  # SLURM job for merging all years
│   ├── setup.sh                # Generates execution list
│   ├── postprocess.sh          # Concatenates yearly files
│   └── job.sbatch              # SLURM submission script
│
└── Spinup/                     # Phase 2-3: SNOWPACK spinup & date extraction
    ├── base.ini                # Main SNOWPACK configuration
    ├── spinup.ini              # Spinup phase settings (no output)
    ├── final.ini               # Final simulation settings (with output)
    ├── spinup.sh               # Spinup orchestration script
    ├── spinup.rc               # Runtime configuration
    ├── check_spinup.awk        # Convergence checker
    ├── generate_seed_sno.sh    # Creates initial snow files
    ├── update_station_configs.sh # Generates station configs
    ├── copy_nearest_profiles.py  # Nearest-neighbor fix for unstable stations
    ├── smet/                   # Input forcing (.smet files, 1980-2024)
    ├── cfgfiles/               # Per-station .ini configs
    ├── Results/
    │   ├── final_sno/          # Final .sno files (ProfileDate=2024-12-31)
    │   ├── pro_files/          # Profile output (.pro)
    │   ├── output_smet/        # Model output time series (.smet)
    │   └── copied_profiles_tracking.csv
    ├── run_past_dates.sh       # Script for past date extraction
    ├── run_future_dates.sh     # Script for future date extraction
    └── job_extract_dates.sbatch
```

---

## Prerequisites

### Software Requirements

1. **SNOWPACK/MeteoIO** compiled binaries:
   - `snowpack` — Main simulation executable
   - `meteoio_timeseries` — Data extraction utility
   - Binary location: `/users/gsergi/ALPINE3D/bin/`

2. **CSCS Alps Environment**:
   ```bash
   # SLURM header for SNOWPACK jobs
   #SBATCH --uenv=prgenv-gnu/24.11:v2
   #SBATCH --view=spack

   # For NetCDF merging
   #SBATCH --uenv=netcdf-tools/2024:v1
   ```

3. **GNU Parallel** for batch processing

### Data Requirements

1. **ERA5 Reanalysis Data** (NetCDF format), two files per year:
   - `data_stream-oper_stepType-instant.nc` — t2m, d2m, u10, v10, sp
   - `data_stream-oper_stepType-accum.nc` — ssrd, strd, tp

2. **DEM File** (NetCDF): Antarctic topography for altitude extraction

Current data location:
```
/capstor/store/cscs/userlab/s1329/DATA_ANT_CLIM/ERA5_3hourly_1980_2024/
├── 1980/
│   ├── data_stream-oper_stepType-instant.nc
│   └── data_stream-oper_stepType-accum.nc
├── 1981/
│   └── ...
└── 2024/

DEM: /capstor/store/cscs/userlab/s1329/DATA_ANT_CLIM/ERA5_DEM.nc
```

---

## Phase 1: ERA5 Data Preparation

Working directory: `snowpack/Scripts/create_smet_from_netcdf/`

### 1.1 Merge NetCDF files (instant + accumulated)

MeteoIO cannot read from multiple file patterns, so merge them per year:

```bash
cd snowpack/Scripts/create_smet_from_netcdf/

# Edit merge_all_years.sbatch if needed (year range, paths)
sbatch merge_all_years.sbatch
```

This uses CDO to merge instant and accumulated variables into a single file per year
in `input/ERA5_merged/<YEAR>/ERA5_<YEAR>.nc`.

**Environment**: `--uenv=netcdf-tools/2024:v1`

Verify the merged files contain all required variables:
```bash
ncdump -h input/ERA5_merged/1980/ERA5_1980.nc | grep -E "t2m|d2m|u10|v10|sp|ssrd|strd|tp"
```

### 1.2 Configure station locations

Edit `station_list.lst` to define virtual station locations:
```ini
[INPUTEDITING]
VSTATION1 = latlon -84.750000 -135.000000 0
VID1 = VIR_1_100_100
VSTATION2 = latlon -78.500000 44.750000 0
VID2 = VIR_1_150_150
...
```

Each station extracts the nearest ERA5 grid point (GRID_EXTRACT strategy).
**Naming Convention:** `VIR_1_XXX_YYY` where XXX and YYY are grid indices.

### 1.3 Configure ERA5.ini

Key settings to verify in `io_files/ERA5.ini`:

```ini
[INPUT]
METEOPATH  = /path/to/ERA5_merged/
GRID2DPATH = /path/to/ERA5_merged/
DEMFILE    = /path/to/ERA5_DEM.nc

# Variable mappings (must match NetCDF variable names)
NETCDF_VAR::TA   = t2m
NETCDF_VAR::TD   = d2m
NETCDF_VAR::U    = u10
NETCDF_VAR::V    = v10
NETCDF_VAR::ISWR = ssrd
NETCDF_VAR::ILWR = strd
NETCDF_VAR::PSUM = tp
NETCDF_VAR::P    = sp

# Dimension names
NETCDF_DIM::LONGITUDE = longitude
NETCDF_DIM::LATITUDE  = latitude
NETCDF_DIM::TIME      = valid_time

[INPUTEDITING]
RESAMPLING_STRATEGY = GRID_EXTRACT
VSTATIONS_REFRESH_RATE   = 21600    # 6 hours
VSTATIONS_REFRESH_OFFSET = 3600
Virtual_parameters = TA RH VW DW ISWR ILWR PSUM P
```

### 1.4 Generate execution list and run extraction

```bash
# Edit setup.sh: year_start=1980, year_end=2024, model="ERA5"
bash setup.sh
sbatch job.sbatch
```

**Important**: Each merged NetCDF is ~12 GB. The job runs 4 years in parallel
(`parallel -j 4`) to avoid OOM. Output goes to `output/ERA5_<YEAR>/`.

### 1.5 Postprocess (concatenate yearly files)

```bash
bash postprocess.sh ERA5
```

This concatenates per-year `.smet` files into continuous time series in
`output/concatenated/` and creates `output/smet_forcing.zip`.

Copy the concatenated files to the Spinup directory:
```bash
cp output/concatenated/*.smet ../Spinup/smet/
```

### 1.6 Adding new years (e.g. for future runs)

To extend forcing with new ERA5 data (e.g., year 2025):

```bash
cd snowpack/Scripts/create_smet_from_netcdf/

# 1. Download ERA5 data for 2025 to the same directory structure
#    (instant + accum .nc files in a 2025/ subfolder)

# 2. Merge the new year
bash merge_nc_files.sh 2025

# 3. Extract smet for that year only
export OUTPUTINTERVAL=0
bash create_forcing.sh ERA5 2025

# 4. Append to existing smet files
for f in output/ERA5_2025/*.smet; do
    stn=$(basename "$f" .smet)
    # Append data section (skip header) to existing concatenated file
    awk 'BEGIN{d=0} {if(d) print; if(/\[DATA\]/) d=1}' "$f" >> ../Spinup/smet/${stn}.smet
done
```

---

## Phase 2: SNOWPACK Spinup

Working directory: `snowpack/Scripts/Spinup/`

### 2.1 Create seed snow files

**Critical**: SNOWPACK requires a seed snow layer to accumulate precipitation.
Starting from bare ground (`nSnowLayerData=0`) does not work.

```bash
bash generate_seed_sno.sh
```

This creates `.sno` files with a 10cm seed layer. Temperature by altitude:
- < 1000m: 250 K (-23°C)
- 1000-2000m: 240 K (-33°C)
- > 2000m: 230 K (-43°C)

Seed layer parameters:
- `Layer_Thick`: 0.10 m
- `Vol_Frac_I`: 0.35 (ice fraction)
- `Vol_Frac_V`: 0.65 (void fraction)

### 2.2 Generate station config files

```bash
bash update_station_configs.sh
```

Creates individual `.ini` files in `cfgfiles/`:
```ini
[GENERAL]
IMPORT_BEFORE = ../base.ini
IMPORT_AFTER  = ../spinup.ini    # Changed to ../final.ini for last run

[INPUT]
STATION1  = VIR_1_100_100.smet
SNOWFILE1 = VIR_1_100_100.sno

[OUTPUT]
EXPERIMENT = NO_EXP
```

### 2.3 Key configuration (base.ini)

#### ERA5 Input Corrections
```ini
[InputEditing]
; Exclude invalid PSUM_PH (ERA5 uses WMO codes 0-9, not 0-1 fraction)
*::edit1 = EXCLUDE
*::arg1::params = PSUM_PH

; Create correct PSUM_PH from temperature
*::edit2 = CREATE
*::arg2::algorithm = PRECSPLITTING
*::arg2::param     = PSUM_PH
*::arg2::type      = THRESH
*::arg2::snow      = 274.35    ; Snow threshold: 1.2°C

; Copy VW to VW_DRIFT for drift calculations
*::edit3      = COPY
*::arg3::dest = VW_DRIFT
*::arg3::src  = VW
```

#### Radiation and Wind Corrections
```ini
[FILTERS]
; ERA5 radiation is hourly accumulated J/m²
; MeteoIO divides by 6hr (21600s) assuming 6-hourly accumulation
; Multiply by 6 to correct the unit conversion
ILWR::filter1      = mult
ILWR::arg1::type   = CST
ILWR::arg1::cst    = 6

ISWR::filter1      = mult
ISWR::arg1::type   = CST
ISWR::arg1::cst    = 6

; Scale down ERA5 winds by 50% (often overestimated in Antarctica)
VW::filter1        = mult
VW::arg1::type     = CST
VW::arg1::cst      = 0.5
```

#### Ground Temperature and Physics
```ini
[GENERATORS]
; TSG (ground surface temperature) - lower boundary condition
TSG::generator1     = CST
TSG::arg1::value    = 230.0   ; -43°C typical Antarctic subsurface

[SNOWPACK]
CALCULATION_STEP_LENGTH = 60    ; minutes (reduce to 15 for unstable stations)
VARIANT             = POLAR     ; Antarctic-specific parameterizations
FORCING             = ATMOS
SNP_SOIL            = FALSE     ; No soil layers during spinup
GEO_HEAT            = 0.0       ; Zero geothermal heat flux

[SNOWPACKADVANCED]
ALLOW_ADAPTIVE_TIMESTEPPING = TRUE
FORCE_ADD_SNOWFALL  = TRUE
SNOW_EROSION        = NONE      ; Disable during spinup
MAX_SIMULATED_HS    = 15        ; Maximum simulated height (meters)
WIND_SCALING_FACTOR = 0.3       ; Additional wind scaling
```

### 2.4 How the spinup works

The `spinup.sh` script orchestrates iterative simulations:

1. Read initial `.sno` file (10cm seed layer)
2. Run 45-year simulation (1980-2024)
3. Check snow depth against `min_sim_depth` (15m, set in `spinup.rc`)
4. If depth < 15m:
   - Time-shift output `.sno` back to 1980-01-01
   - Run another 45-year cycle
   - Repeat until depth >= 15m
5. When depth >= 15m, switch to `final.ini` and run final simulation with output

### 2.5 Run the spinup

```bash
cd Scripts/Spinup
sbatch job.sbatch
```

The job filters out already-completed stations and runs remaining ones in parallel
(128 concurrent). Monitor progress with:
```bash
bash status.sh
```

#### Typical runtime

| Station Type | Accumulation Rate | Cycles Needed | Approx. Time |
|--------------|-------------------|---------------|--------------|
| Coastal (<1000m) | ~3m/cycle | 5 cycles | 2-3 hours |
| Plateau (>3000m) | ~0.3m/cycle | 50+ cycles | 24+ hours |

### 2.6 Spinup results (current state)

- **18,988 stations** completed successfully
- **12 stations** completed with reduced timestep (15 min instead of 60 min)
- **31 stations** had persistent numerical instability — nearest-neighbor profiles
  copied (tracked in `Results/copied_profiles_tracking.csv`)

### 2.7 Handling numerically unstable stations

Some stations near the Antarctic Peninsula (lat ~-66 to -73, lon ~-61 to -65)
crash even with 15 min timestep. These are typically at low altitude with
thin/intermittent snow cover.

**Solution**: Copy the profile from the nearest completed station (weighted by
horizontal distance and altitude difference):

```bash
# Auto-detect missing stations and copy nearest neighbor
python copy_nearest_profiles.py

# Or provide explicit list and preview matches first
python copy_nearest_profiles.py --failed-list failed_stations.txt --dry-run
python copy_nearest_profiles.py --failed-list failed_stations.txt
```

The script writes `Results/copied_profiles_tracking.csv` with the source-target
mapping, horizontal distance, and altitude difference for each copied station.

---

## Phase 3: Extract .sno Snapshots at Specific Dates

### 3.1 Past dates (1980-2024)

Use when you need CRYOWRF initialization at a historical date.

**How it works**: The final `.sno` files (ProfileDate=2024-12-31) are time-shifted
back to 1980-01-01 and SNOWPACK runs forward using the existing forcing, stopping
at each requested date.

```bash
cd snowpack/Scripts/Spinup/

# 1. Create a dates file (one date per line)
cat > my_past_dates.txt << 'EOF'
2000-01-01T00:00
2010-01-01T00:00
2020-01-01T00:00
EOF

# 2. Setup (creates dirs, station list, execution list)
bash run_past_dates.sh my_past_dates.txt ./past_output

# 3. Submit the job
sbatch job_extract_dates.sbatch ./past_output/to_exec.lst

# 4. Results:
#    past_output/sno_2000-01-01/  (18,988 .sno files)
#    past_output/sno_2010-01-01/
#    past_output/sno_2020-01-01/
```

**Performance note**: Multiple dates are chained sequentially per station
(run to date1, save, continue to date2, ...) so forcing is processed only once.

### 3.2 Future dates (2025+)

Use when you need CRYOWRF initialization at a future date using new forcing.

**How it works**: The final `.sno` files are used directly as initial state
(already at 2024-12-31). SNOWPACK runs forward with new forcing data.

**Prerequisites**: You need `.smet` forcing files covering 2025 to your target
date. See [Phase 1 Section 1.6](#16-adding-new-years-eg-for-future-runs).

```bash
cd snowpack/Scripts/Spinup/

# 1. Create a dates file
cat > my_future_dates.txt << 'EOF'
2025-06-01T00:00
2026-01-01T00:00
EOF

# 2. Setup (point to directory with future .smet files)
bash run_future_dates.sh my_future_dates.txt /path/to/future_smet/ ./future_output

# 3. Submit the job
sbatch job_extract_dates.sbatch ./future_output/to_exec.lst

# 4. Results:
#    future_output/sno_2025-06-01/
#    future_output/sno_2026-01-01/
```

### 3.3 Output structure

Each `sno_YYYY-MM-DD/` folder contains one `.sno` file per station, ready to be
used as CRYOWRF initial conditions. The `.sno` files contain:
- Snow/firn layer stratigraphy (density, temperature, grain size, etc.)
- ProfileDate matching the requested date
- Station metadata (lat, lon, altitude)

---

## Monitoring and Validation

### Check progress during spinup

```bash
bash status.sh

# Example output:
# | Status         | Count  | %     |
# |----------------|--------|-------|
# | Completed      |  18928 | 99.7% |
# | In progress    |     17 | 0.1%  |
# | Not started    |     43 | 0.2%  |
```

### Expected results

Snow depths after spinup:

| Location | Altitude | Expected Depth |
|----------|----------|----------------|
| Coastal | ~600m | 15-50m |
| Mid-altitude | ~2000m | 15-25m |
| High plateau | ~3500m | 15-20m |

1-year accumulation test:

| Station | Latitude | Altitude | ΔSWE (kg/m²) | Final HS (cm) |
|---------|----------|----------|--------------|---------------|
| VIR_1_100_100 | -84.75°S | 636 m | ~197 | ~68 |
| VIR_1_120_120 | -88.75°S | 2914 m | ~34 | ~24 |
| VIR_1_150_150 | -78.50°S | 3673 m | ~18 | ~17 |

### Energy balance diagnostics

If you ran with output enabled, verify:

| Variable | Expected Range | Common Error |
|----------|---------------|--------------|
| ILWR | 100-170 W/m² | ~18 W/m² (missing x6 multiplier) |
| ISWR | 0-400 W/m² | ~60 W/m² (missing x6 multiplier) |
| Qs (sensible heat) | -10 to +50 W/m² | >1000 W/m² (TSG mismatch) |
| Ql (latent heat) | -5 to +1 W/m² | |

### Validation notebook

A Jupyter notebook for visual validation is available at:
`Spinup/Results/validate_spinup.ipynb`

It parses all `.sno` files and generates Antarctic maps of:
- Surface temperature
- Snow height
- Average density
- Bottom temperature
- Altitude

---

## Critical Configuration Parameters

### Parameters That MUST Be Verified

| Parameter | Location | Correct Value | Common Error |
|-----------|----------|---------------|--------------|
| `ILWR::cst` | base.ini [FILTERS] | `6` | Missing → ILWR ~18 W/m² |
| `ISWR::cst` | base.ini [FILTERS] | `6` | Missing → ISWR too low |
| `PSUM_PH` | base.ini [InputEditing] | EXCLUDE + CREATE | Raw ERA5 WMO codes |
| `TSG::value` | base.ini [GENERATORS] | `230.0` | Too warm → extreme fluxes |
| `VARIANT` | base.ini [SNOWPACK] | `POLAR` | Default Alpine settings |
| `nSnowLayerData` | .sno seed files | `1` | `0` → no accumulation |
| `min_sim_depth` | spinup.rc | `15` | Too low → incomplete spinup |
| `MAX_SIMULATED_HS` | base.ini | `15` | < min_sim_depth → never completes |

### ERA5 Unit Conversions

| Variable | ERA5 Units | MeteoIO Expects | Correction |
|----------|------------|-----------------|------------|
| `ssrd/strd` | J/m² (hourly accum) | W/m² | x6 multiplier in FILTERS |
| `tp` | m (hourly accum) | mm/h | Automatic |
| `ptype` | WMO codes (0-9) | Fraction (0-1) | PRECSPLITTING via InputEditing |

---

## Troubleshooting

### No snow accumulation (HS = 0)
- **Cause**: Missing seed snow layer in `.sno` file (`nSnowLayerData=0`)
- **Fix**: Regenerate seed files with 10cm initial layer: `bash generate_seed_sno.sh`

### Extremely low radiation (ILWR ~18 W/m²)
- **Cause**: Missing x6 multiplier for ERA5 radiation
- **Fix**: Add `ILWR::filter1 = mult` with `cst = 6` in base.ini

### Invalid PSUM_PH (value = 5)
- **Cause**: ERA5 `ptype` uses WMO codes, not 0-1 fraction
- **Fix**: Use InputEditing to EXCLUDE and CREATE with PRECSPLITTING

### Extreme heat fluxes (>1000 W/m²)
- **Cause**: TSG (ground temperature) mismatch with air temperature
- **Fix**: Set `TSG::generator1 = CST` with `value = 230.0`

### Spinup never completes
- **Cause**: `MAX_SIMULATED_HS` too close to `min_sim_depth`
- **Fix**: Ensure `MAX_SIMULATED_HS` >= `min_sim_depth`

### Numerical instability (temperature crash)
- **Cause**: Thin/intermittent snow at coastal stations, timestep too large
- **Fix 1**: Reduce `CALCULATION_STEP_LENGTH` to 15 min (create `spinup_short_dt.ini`)
- **Fix 2**: If still unstable, copy nearest-neighbor profile: `python copy_nearest_profiles.py`

### Disk quota exceeded (inode limit)
- **Cause**: SNOWPACK creates dated backup `.sno` files at every `BACKUP_DAYS_BETWEEN`
- **Fix**: Delete intermediate backups: `find output/ -name "*.sno[0-9]*" -delete`
- Also delete `.haz` files if not needed: `find output/ -name "*.haz*" -delete`

---

## Quick Reference Cheatsheet

### "I need .sno files for date X in the past"
```bash
echo "YYYY-MM-DDTHH:MM" > dates.txt
bash run_past_dates.sh dates.txt ./output_dir
sbatch job_extract_dates.sbatch ./output_dir/to_exec.lst
```

### "I need .sno files for a future date"
```bash
# First: create smet forcing up to that date (see Phase 1, Section 1.6)
echo "YYYY-MM-DDTHH:MM" > dates.txt
bash run_future_dates.sh dates.txt /path/to/future_smet/ ./output_dir
sbatch job_extract_dates.sbatch ./output_dir/to_exec.lst
```

### "I need to redo the spinup for some stations"
```bash
bash spinup.sh "/users/gsergi/ALPINE3D/bin/snowpack -c cfgfiles/STATION.ini -e 2024-12-31T18:00:00 > log/STATION.log 2>&1"
```

### "I need to extend forcing with a new year of ERA5 data"
```bash
cd Scripts/create_smet_from_netcdf/
bash merge_nc_files.sh YYYY
bash create_forcing.sh ERA5 YYYY
for f in output/ERA5_YYYY/*.smet; do
    stn=$(basename "$f" .smet)
    awk 'BEGIN{d=0} {if(d) print; if(/\[DATA\]/) d=1}' "$f" >> ../Spinup/smet/${stn}.smet
done
```

### Full spinup from scratch
```bash
cd Scripts/create_smet_from_netcdf/
bash setup.sh && sbatch job.sbatch
bash postprocess.sh ERA5
cp output/concatenated/*.smet ../Spinup/smet/

cd ../Spinup/
bash generate_seed_sno.sh
bash update_station_configs.sh
sbatch job.sbatch
bash status.sh
```

---

## File Inventory

| File | Purpose | Git tracked |
|------|---------|-------------|
| `base.ini` | Main SNOWPACK config (ERA5 corrections, physics) | Yes |
| `spinup.ini` | Spinup settings (no output) | Yes |
| `final.ini` | Final run settings (with output) | Yes |
| `spinup.sh` | Iterative spinup script | Yes |
| `spinup.rc` | Spinup parameters (min_sim_depth, paths) | Yes |
| `check_spinup.awk` | Convergence checker | Yes |
| `generate_seed_sno.sh` | Creates initial 10cm .sno files | Yes |
| `update_station_configs.sh` | Generates per-station .ini | Yes |
| `status.sh` | Progress monitoring | Yes |
| `copy_nearest_profiles.py` | Nearest-neighbor fix for unstable stations | No |
| `run_past_dates.sh` | Past date extraction | No |
| `run_future_dates.sh` | Future date extraction | No |
| `job_extract_dates.sbatch` | SLURM job for date extraction | No |
| `Results/final_sno/` | 18,988 final .sno files | No (data) |
| `Results/pro_files/` | 13,634 .pro files | No (data) |
| `Results/output_smet/` | 18,981 output time series | No (data) |
| `smet/` | 18,988 input forcing files | No (data) |
| `cfgfiles/` | 18,988 per-station configs | No (data) |

### Pre-run checklist

- [ ] SMET files in `smet/` directory
- [ ] Seed .sno files created (`nSnowLayerData=1`, 10cm layer)
- [ ] Station config files in `cfgfiles/`
- [ ] `base.ini` with correct filters (x6 radiation) and generators (TSG=230)
- [ ] `spinup.ini` with `TS_WRITE=FALSE`, `PROF_WRITE=FALSE`
- [ ] `spinup.rc` with `min_sim_depth=15`

---

## References

- SNOWPACK Documentation: https://snowpack.slf.ch/
- MeteoIO Documentation: https://meteoio.slf.ch/
- ERA5 Documentation: https://cds.climate.copernicus.eu/

---

*This tutorial documents the Antarctic firn spinup procedure developed for the CRYOWRF Antarctic Climate project.*
