# SNOWPACK Antarctic Firn Spinup Tutorial

A comprehensive step-by-step guide for running SNOWPACK firn spinup simulations for Antarctica using ERA5 reanalysis forcing data.

**Author:** Sergi Gonzalez
**Last Updated:** January 2025
**Repository:** SNOWPACK Antarctic Climate Simulations

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: ERA5 Data Preparation](#phase-1-era5-data-preparation)
4. [Phase 2: SMET File Generation](#phase-2-smet-file-generation)
5. [Phase 3: Spinup Configuration](#phase-3-spinup-configuration)
6. [Phase 4: Running the Spinup](#phase-4-running-the-spinup)
7. [Phase 5: Monitoring and Validation](#phase-5-monitoring-and-validation)
8. [Critical Configuration Parameters](#critical-configuration-parameters)
9. [Troubleshooting](#troubleshooting)
10. [Appendix: File Formats](#appendix-file-formats)

---

## Overview

### What is a Firn Spinup?

A firn spinup is a model initialization procedure that builds a realistic firn column (compacted snow layers) by running the model repeatedly over the same time period. In Antarctica, firn can be 50-100+ meters deep, requiring multiple simulation cycles to develop a realistic vertical profile.

### Workflow Summary

```
ERA5 NetCDF Data → SMET Forcing Files → SNOWPACK Spinup → Firn Profiles
     (Phase 1)         (Phase 2)           (Phase 3-4)       (Output)
```

### Key Components

| Component | Description |
|-----------|-------------|
| **MeteoIO** | Data processing library that extracts and converts ERA5 data |
| **SNOWPACK** | Snow/firn physics model |
| **Virtual Stations** | Grid points where simulations are performed |
| **SMET Files** | Meteorological forcing data format |
| **SNO Files** | Snow profile initialization/output format |

---

## Prerequisites

### Software Requirements

1. **SNOWPACK/MeteoIO** compiled binaries:
   - `snowpack` - Main simulation executable
   - `meteoio_timeseries` - Data extraction utility

2. **CSCS Alps Environment** (or equivalent HPC):
   ```bash
   # Load the required environment
   uenv run prgenv-gnu/24.11:v2 --view=spack -- bash -c "your_command"
   ```

3. **GNU Parallel** for batch processing

### Data Requirements

1. **ERA5 Reanalysis Data** (NetCDF format):
   - `t2m` - 2-meter temperature
   - `d2m` - 2-meter dewpoint temperature
   - `u10`, `v10` - 10-meter wind components
   - `sp` - Surface pressure
   - `ssrd` - Surface solar radiation downwards (accumulated)
   - `strd` - Surface thermal radiation downwards (accumulated)
   - `tp` - Total precipitation (accumulated)

2. **DEM File** (NetCDF format):
   - Antarctic topography for altitude extraction

### Directory Structure

```
snowpack/Scripts/
├── create_smet_from_netcdf/    # Phase 1-2: Data preparation
│   ├── io_files/               # MeteoIO configuration files
│   │   ├── base.ini            # Base configuration
│   │   └── ERA5.ini            # ERA5-specific settings
│   ├── station_list.lst        # Virtual station definitions
│   ├── create_forcing.sh       # Main extraction script
│   ├── setup.sh                # Generates execution list
│   ├── postprocess.sh          # Concatenates yearly files
│   └── job.sbatch              # SLURM submission script
│
└── Spinup/                     # Phase 3-4: SNOWPACK spinup
    ├── base.ini                # Main SNOWPACK configuration
    ├── spinup.ini              # Spinup phase settings
    ├── final.ini               # Final simulation settings
    ├── spinup.rc               # Runtime configuration
    ├── spinup.sh               # Spinup orchestration script
    ├── generate_seed_sno.sh    # Creates initial snow files
    ├── update_station_configs.sh # Generates station configs
    ├── filter_completed.sh     # Filters completed stations
    └── job.sbatch              # SLURM submission script
```

---

## Phase 1: ERA5 Data Preparation

### Step 1.1: Organize ERA5 NetCDF Files

ERA5 data should be organized by year:

```
input/ERA5_merged/
├── ERA5_1980.nc
├── ERA5_1981.nc
├── ...
└── ERA5_2024.nc
```

**Important:** Each NetCDF file should contain ALL required variables merged together. If you have separate files for instantaneous and accumulated variables, merge them first:

```bash
# Example merge command (using CDO)
cdo merge ERA5_instant_1980.nc ERA5_accum_1980.nc ERA5_merged_1980.nc
```

### Step 1.2: Verify NetCDF Structure

Check that your files have the correct variable names:

```bash
ncdump -h ERA5_1980.nc | grep -E "t2m|d2m|u10|v10|sp|ssrd|strd|tp"
```

Expected output:
```
float t2m(valid_time, latitude, longitude) ;
float d2m(valid_time, latitude, longitude) ;
float u10(valid_time, latitude, longitude) ;
float v10(valid_time, latitude, longitude) ;
float sp(valid_time, latitude, longitude) ;
float ssrd(valid_time, latitude, longitude) ;
float strd(valid_time, latitude, longitude) ;
float tp(valid_time, latitude, longitude) ;
```

---

## Phase 2: SMET File Generation

### Step 2.1: Define Virtual Stations

Edit `station_list.lst` to define your simulation grid points:

```ini
[INPUT]
COORDSYS    = PROJ
COORDPARAM  = 3031    # Antarctic Polar Stereographic

# Format: STATIONX = latitude longitude station_name
STATION1 = -84.75 -135.0 VIR_1_100_100
STATION2 = -84.75 -133.25 VIR_1_100_101
STATION3 = -84.75 -131.50 VIR_1_100_102
# ... add all stations
```

**Naming Convention:** `VIR_1_XXX_YYY` where XXX and YYY are grid indices.

### Step 2.2: Configure ERA5.ini

**Critical settings to verify:**

```ini
[INPUT]
# Paths to your ERA5 data
METEOPATH  = /path/to/ERA5_merged/
GRID2DPATH = /path/to/ERA5_merged/
DEMFILE    = /path/to/ERA5_DEM.nc

# Variable mappings (must match your NetCDF variable names)
NETCDF_VAR::TA   = t2m
NETCDF_VAR::TD   = d2m
NETCDF_VAR::U    = u10
NETCDF_VAR::V    = v10
NETCDF_VAR::ISWR = ssrd
NETCDF_VAR::ILWR = strd
NETCDF_VAR::PSUM = tp
NETCDF_VAR::P    = sp

# Dimension names (must match your NetCDF dimensions)
NETCDF_DIM::LONGITUDE = longitude
NETCDF_DIM::LATITUDE  = latitude
NETCDF_DIM::TIME      = valid_time

[INPUTEDITING]
# Extraction strategy
RESAMPLING_STRATEGY = GRID_EXTRACT

# Output interval (21600s = 6 hours)
VSTATIONS_REFRESH_RATE   = 21600
VSTATIONS_REFRESH_OFFSET = 3600

# Variables to extract from grid
Virtual_parameters = TA RH VW DW ISWR ILWR PSUM P

# Generate precipitation phase from temperature
PSUM_PH::create              = PRECSPLITTING
PSUM_PH::PRECSPLITTING::type = THRESH
PSUM_PH::PRECSPLITTING::snow = 274.35   # Snow below 1.2°C
```

### Step 2.3: Generate Execution List

```bash
cd Scripts/create_smet_from_netcdf
bash setup.sh
```

This creates `to_exec.lst` with commands for each year.

### Step 2.4: Run Extraction

```bash
# Submit SLURM job
sbatch job.sbatch

# Or run interactively for testing
bash create_forcing.sh ERA5 1980
```

### Step 2.5: Concatenate Yearly Files

After all years are processed:

```bash
bash postprocess.sh ERA5
```

This creates continuous SMET files in `output/concatenated/`.

### Step 2.6: Copy to Spinup Directory

```bash
cp output/concatenated/*.smet ../Spinup/smet/
```

---

## Phase 3: Spinup Configuration

### Step 3.1: Configure base.ini

This is the **most critical file**. Key sections explained:

#### Input Processing (ERA5 Corrections)

```ini
[InputEditing]
; ERA5 PSUM_PH uses WMO codes (0-9), not 0-1 fraction
; Must EXCLUDE the invalid values and CREATE new ones
*::edit1 = EXCLUDE
*::arg1::params = PSUM_PH

*::edit2 = CREATE
*::arg2::algorithm = PRECSPLITTING
*::arg2::param     = PSUM_PH
*::arg2::type      = THRESH
*::arg2::snow      = 274.35    ; Snow threshold: 1.2°C

; Copy wind for drift calculations
*::edit3      = COPY
*::arg3::dest = VW_DRIFT
*::arg3::src  = VW
```

#### Radiation Corrections

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

; Scale down ERA5 winds (often overestimated in Antarctica)
VW::filter1        = mult
VW::arg1::type     = CST
VW::arg1::cst      = 0.5
```

#### Temperature Filters

```ini
[FILTERS]
; Antarctic temperature range
TA::filter1        = min_max
TA::arg1::min      = 190    ; -83°C minimum
TA::arg1::max      = 280    ; +7°C maximum
TA::arg1::soft     = FALSE
```

#### Ground Temperature Generator

```ini
[GENERATORS]
; TSG (ground surface temperature) - lower boundary condition
; Use cold constant appropriate for Antarctic interior
TSG::generator1     = CST
TSG::arg1::value    = 230.0   ; -43°C typical subsurface
```

#### SNOWPACK Physics Settings

```ini
[SNOWPACK]
VARIANT             = POLAR     ; Antarctic-specific parameterizations
FORCING             = ATMOS     ; Atmospheric forcing
SNP_SOIL            = FALSE     ; No soil layers during spinup
GEO_HEAT            = 0.0       ; Zero geothermal heat flux

[SNOWPACKADVANCED]
FORCE_ADD_SNOWFALL  = TRUE      ; Ensure precipitation creates snow
SNOW_EROSION        = NONE      ; Disable erosion during spinup
MAX_SIMULATED_HS    = 15        ; Maximum simulated height (meters)
WIND_SCALING_FACTOR = 0.3       ; Additional wind scaling
```

### Step 3.2: Configure spinup.rc

```ini
# Path to SNOWPACK binary
which_snowpack="/users/gsergi/ALPINE3D/bin/snowpack"

# Minimum depth before spinup is complete (meters)
min_sim_depth=15

# Check script for additional completion criteria
checkscript="check_spinup.awk"

# Directory for initial snow files
snow_init_dir="./snow_init/"
```

### Step 3.3: Generate Seed Snow Files

**Critical Discovery:** SNOWPACK requires an initial snow layer to accumulate precipitation. Starting from bare ground does not work.

```bash
bash generate_seed_sno.sh
```

This creates `.sno` files with a 10cm seed layer:

```
SMET 1.1 ASCII
[HEADER]
station_id       = VIR_1_100_100
latitude         = -84.750000
longitude        = -135.000000
altitude         = 635.8
ProfileDate      = 1980-01-01T00:00:00
HS_Last          = 0.10
nSnowLayerData   = 1
[DATA]
1980-01-01T00:00:00 0.10 250.0 0.35 0.0 0.65 ...
```

**Temperature by altitude:**
- < 1000m: 250K (-23°C)
- 1000-2000m: 240K (-33°C)
- > 2000m: 230K (-43°C)

### Step 3.4: Generate Station Config Files

```bash
bash update_station_configs.sh
```

Creates individual `.ini` files in `cfgfiles/`:

```ini
[GENERAL]
IMPORT_BEFORE = ../base.ini
IMPORT_AFTER  = ../spinup.ini

[INPUT]
STATION1  = VIR_1_100_100.smet
SNOWFILE1 = VIR_1_100_100.sno

[OUTPUT]
EXPERIMENT = NO_EXP
```

---

## Phase 4: Running the Spinup

### Step 4.1: How Spinup Works

The `spinup.sh` script orchestrates iterative simulations:

1. Read initial `.sno` file (10cm seed layer)
2. Run 45-year simulation (1980-2024)
3. Check snow depth against `min_sim_depth` (15m)
4. If depth < 15m:
   - Time-shift output back to 1980-01-01
   - Run another 45-year cycle
   - Repeat until depth ≥ 15m
5. When complete, switch to `final.ini` and run final simulation

### Step 4.2: Submit Spinup Job

```bash
cd Scripts/Spinup
sbatch job.sbatch
```

The job will:
1. Filter out already-completed stations (`filter_completed.sh`)
2. Run remaining stations in parallel (128 concurrent)
3. Each station runs until it reaches 15m depth

### Step 4.3: Typical Runtime

| Station Type | Accumulation Rate | Cycles Needed | Approx. Time |
|--------------|-------------------|---------------|--------------|
| Coastal (<1000m) | ~3m/cycle | 5 cycles | 2-3 hours |
| Plateau (>3000m) | ~0.3m/cycle | 50+ cycles | 24+ hours |

**Note:** High-altitude interior stations have very low accumulation and require many more cycles.

---

## Phase 5: Monitoring and Validation

### Step 5.1: Check Progress

```bash
# Count completed stations
grep -l "final.ini" cfgfiles/*.ini | wc -l

# Count output files
ls output/*.sno | wc -l

# Check specific station depth
grep HS_Last output/VIR_1_100_100.sno
```

### Step 5.2: Validate Results

Expected snow depths after spinup:

| Location | Altitude | Expected Depth |
|----------|----------|----------------|
| Coastal | ~600m | 15-50m |
| Mid-altitude | ~2000m | 15-25m |
| High plateau | ~3500m | 15-20m |

### Step 5.3: Check Energy Balance

If you ran with output enabled, verify:

```
ILWR: 100-170 W/m² (NOT ~18 W/m²)
ISWR: 0-400 W/m² (seasonal variation)
Qs:   -10 to +50 W/m² (sensible heat)
Ql:   -5 to +1 W/m² (latent heat)
```

---

## Critical Configuration Parameters

### Parameters That MUST Be Verified

| Parameter | Location | Correct Value | Common Error |
|-----------|----------|---------------|--------------|
| `ILWR::cst` | base.ini [FILTERS] | `6` | Missing multiplier → 18 W/m² |
| `ISWR::cst` | base.ini [FILTERS] | `6` | Missing multiplier |
| `PSUM_PH` | base.ini [InputEditing] | EXCLUDE + CREATE | Using raw ERA5 WMO codes |
| `TSG::value` | base.ini [GENERATORS] | `230.0` | Too warm → unrealistic fluxes |
| `VARIANT` | base.ini [SNOWPACK] | `POLAR` | Using default Alpine settings |
| `nSnowLayerData` | .sno files | `1` | `0` → no accumulation |
| `min_sim_depth` | spinup.rc | `15` | Too low → incomplete spinup |

### ERA5 Unit Conversions

| Variable | ERA5 Units | MeteoIO Expects | Correction |
|----------|------------|-----------------|------------|
| `ssrd/strd` | J/m² (hourly accum) | W/m² | ×6 multiplier |
| `tp` | m (hourly accum) | mm/h | Automatic |
| `ptype` | WMO codes (0-9) | Fraction (0-1) | PRECSPLITTING |

---

## Troubleshooting

### Problem: No Snow Accumulation (HS = 0)

**Cause:** Missing seed snow layer in `.sno` file.

**Solution:**
```bash
# Regenerate seed files with 10cm initial layer
bash generate_seed_sno.sh
# Ensure nSnowLayerData = 1 in .sno files
```

### Problem: Extremely Low Radiation (~18 W/m²)

**Cause:** Missing ×6 multiplier for ERA5 radiation.

**Solution:** Add to base.ini:
```ini
ILWR::filter1 = mult
ILWR::arg1::type = CST
ILWR::arg1::cst = 6
```

### Problem: Invalid PSUM_PH (value = 5)

**Cause:** ERA5 `ptype` uses WMO codes, not 0-1 fraction.

**Solution:** Use InputEditing to exclude and recreate:
```ini
[InputEditing]
*::edit1 = EXCLUDE
*::arg1::params = PSUM_PH

*::edit2 = CREATE
*::arg2::algorithm = PRECSPLITTING
*::arg2::param = PSUM_PH
*::arg2::type = THRESH
*::arg2::snow = 274.35
```

### Problem: Extreme Heat Fluxes (>1000 W/m²)

**Cause:** TSG (ground temperature) mismatch with air temperature.

**Solution:**
```ini
[GENERATORS]
TSG::generator1 = CST
TSG::arg1::value = 230.0   ; Match typical Antarctic subsurface
```

### Problem: Spinup Never Completes

**Cause:** `MAX_SIMULATED_HS` too close to `min_sim_depth`.

**Solution:** Ensure `MAX_SIMULATED_HS` ≥ `min_sim_depth` + 2m

---

## Appendix: File Formats

### SMET File Format (Meteorological Forcing)

```
SMET 1.1 ASCII
[HEADER]
station_id = VIR_1_100_100
latitude   = -84.750000
longitude  = -135.000000
altitude   = 635.8
nodata     = -999
fields     = timestamp TA RH VW DW ISWR ILWR PSUM PSUM_PH P

[DATA]
1980-01-01T00:00:00 245.3 0.65 5.2 180.0 0.0 108.5 0.0 1.0 98500.0
1980-01-01T06:00:00 244.8 0.68 4.8 175.0 0.0 106.2 0.1 1.0 98450.0
```

### SNO File Format (Snow Profile)

```
SMET 1.1 ASCII
[HEADER]
station_id     = VIR_1_100_100
ProfileDate    = 1980-01-01T00:00:00
HS_Last        = 0.10
nSnowLayerData = 1
fields         = timestamp Layer_Thick T Vol_Frac_I Vol_Frac_W Vol_Frac_V ...

[DATA]
1980-01-01T00:00:00 0.10 250.0 0.35 0.0 0.65 0.0 0.0 0.0 0.0 1.0 0.5 0.0 0.0 1 0.0 1 0.0 0.0
```

---

## Quick Reference Commands

```bash
# Generate SMET files from ERA5
cd Scripts/create_smet_from_netcdf
bash setup.sh && sbatch job.sbatch
bash postprocess.sh ERA5

# Set up spinup
cd Scripts/Spinup
bash generate_seed_sno.sh
bash update_station_configs.sh

# Run spinup
sbatch job.sbatch

# Check progress
grep -l "final.ini" cfgfiles/*.ini | wc -l   # Completed
ls output/*.sno | wc -l                       # With output

# Check specific station
grep HS_Last output/VIR_1_100_100.sno
```

---

## References

- SNOWPACK Documentation: https://snowpack.slf.ch/
- MeteoIO Documentation: https://meteoio.slf.ch/
- ERA5 Documentation: https://cds.climate.copernicus.eu/

---

*This tutorial documents the Antarctic firn spinup procedure developed for the CRYOWRF Antarctic Climate project.*
