# SNOWPACK Antarctica Spinup Procedure

This document describes the complete procedure for running SNOWPACK spinup simulations
for Antarctic climate simulations using ERA5 forcing data.

## Overview

The spinup procedure consists of three main phases:
1. **ERA5 Data Extraction** - Extract ERA5 reanalysis data and create SMET forcing files
2. **Initial Snow File Creation** - Create seed snow layers for each station
3. **SNOWPACK Spinup** - Run multi-year spinup simulations

---

## Phase 1: ERA5 Data Extraction (create_smet_from_netcdf)

### Directory Structure
```
Scripts/create_smet_from_netcdf/
├── io_files/ERA5.ini      # MeteoIO configuration for ERA5
├── station_list.lst       # List of virtual stations (lat, lon, name)
├── create_forcing.sh      # Main extraction script
├── setup.sh               # Workflow setup
├── job.sbatch             # SLURM job submission
├── postprocess.sh         # Concatenate yearly files
└── output/                # Output SMET files
```

### Procedure

1. **Define station locations** in `station_list.lst`:
   ```
   # Format: latitude longitude station_name
   -84.75 -135.0 VIR_1_100_100
   -88.75 44.75 VIR_1_120_120
   ```

2. **Configure ERA5.ini** with correct paths:
   - `GRID2DPATH` - Path to ERA5 NetCDF files
   - `DEMFILE` - Path to DEM file
   - `VSTATIONS_REFRESH_RATE` - Output interval (21600s = 6 hours)

3. **Run setup and extraction**:
   ```bash
   bash setup.sh
   sbatch job.sbatch
   ```

4. **Postprocess to create continuous time series**:
   ```bash
   bash postprocess.sh ERA5
   ```

5. **Copy SMET files to Spinup directory**:
   ```bash
   cp output/smet_forcing/*.smet ../Spinup/smet/
   ```

### ERA5 Data Notes

- ERA5 radiation data (strd, ssrd) is accumulated hourly in J/m²
- MeteoIO divides by 6 hours (21600s) assuming 6-hourly accumulation
- **Correction**: Apply x6 multiplier to ILWR and ISWR in base.ini filters
- ERA5 precipitation phase uses WMO codes (0-9), not 0-1 scale
- **Correction**: Use InputEditing to EXCLUDE PSUM_PH and CREATE from temperature

---

## Phase 2: Initial Snow File Creation

### Key Finding
SNOWPACK requires a seed snow layer to properly accumulate precipitation.
Starting from bare ground (nSnowLayerData=0) does not work correctly.

### Create Seed Snow Files

For each station, create a `.sno` file with a 10cm seed layer:

```
SMET 1.1 ASCII
[HEADER]
station_id       = VIR_1_XXX_XXX
station_name     = Virtual_Station_XXXX
latitude         = -XX.XXXXXX
longitude        = XX.XXXXXX
altitude         = XXXX.X
nodata           = -999
tz               = 0
ProfileDate      = 1980-01-01T00:00:00
HS_Last          = 0.10
nSoilLayerData   = 0
nSnowLayerData   = 1
SoilAlbedo       = 0.09
BareSoil_z0      = 0.020
fields           = timestamp Layer_Thick T Vol_Frac_I Vol_Frac_W Vol_Frac_V Vol_Frac_S Rho_S Conduc_S HeatCapac_S rg rb dd sp mk mass_hoar ne CDot metamo
[DATA]
1980-01-01T00:00:00 0.10 230.0 0.35 0.0 0.65 0.0 0.0 0.0 0.0 1.0 0.5 0.0 0.0 1 0.0 1 0.0 0.0
```

### Seed Layer Parameters
- `Layer_Thick`: 0.10 m (10 cm)
- `T`: 230.0 K (-43°C) for high plateau, 250.0 K (-23°C) for lower elevations
- `Vol_Frac_I`: 0.35 (ice fraction)
- `Vol_Frac_V`: 0.65 (void fraction)

### Script to Generate Seed Files
Use `generate_seed_sno.sh` to create seed files for all stations.

---

## Phase 3: SNOWPACK Configuration

### Directory Structure
```
Scripts/Spinup/
├── base.ini               # Main SNOWPACK configuration
├── spinup.ini             # Spinup-specific settings (disables output)
├── cfgfiles/              # Station-specific config files
├── smet/                  # Input SMET forcing files
├── snow_init/             # Initial .sno files (empty)
├── current_snow/          # Current .sno files (with seed layers)
└── output/                # Simulation output
```

### base.ini Key Settings

#### Input Processing (fixes ERA5 issues)
```ini
[InputEditing]
; Exclude invalid PSUM_PH (WMO codes) from ERA5
*::edit1 = EXCLUDE
*::arg1::params = PSUM_PH

; Create correct PSUM_PH from temperature
*::edit2 = CREATE
*::arg2::algorithm = PRECSPLITTING
*::arg2::param = PSUM_PH
*::arg2::type = THRESH
*::arg2::snow = 274.35

; Copy VW to VW_DRIFT
*::edit3 = COPY
*::arg3::dest = VW_DRIFT
*::arg3::src = VW
```

#### Radiation Corrections (x6 multiplier)
```ini
[FILTERS]
; ERA5 strd/ssrd is hourly accumulated J/m², MeteoIO divides by 6hr
; Multiply by 6 to correct
ILWR::filter1 = mult
ILWR::arg1::type = CST
ILWR::arg1::cst = 6

ISWR::filter1 = mult
ISWR::arg1::type = CST
ISWR::arg1::cst = 6

; Scale down ERA5 winds by 50%
VW::filter1 = mult
VW::arg1::type = CST
VW::arg1::cst = 0.5
```

#### Ground Temperature Generator
```ini
[GENERATORS]
; TSG constant for Antarctic subsurface (~-43°C)
TSG::generator1 = CST
TSG::arg1::value = 230.0
```

#### SNOWPACK Settings
```ini
[SNOWPACK]
VARIANT = POLAR              ; Antarctic-specific parameterizations
SNP_SOIL = FALSE            ; No soil layers during spinup
GEO_HEAT = 0.0              ; Zero geothermal heat flux
FORCING = ATMOS             ; Atmospheric forcing

[SNOWPACKADVANCED]
FORCE_ADD_SNOWFALL = TRUE   ; Ensure precipitation creates snow
SNOW_EROSION = NONE         ; Disable snow erosion during spinup
```

### Station Config Files

Each station has a config file in `cfgfiles/`:
```ini
[GENERAL]
IMPORT_BEFORE = ../base.ini
; For spinup: IMPORT_AFTER = ../spinup.ini (disables TS output)

[INPUT]
STATION1 = VIR_1_XXX_XXX.smet
SNOWFILE1 = VIR_1_XXX_XXX.sno

[OUTPUT]
EXPERIMENT = NO_EXP
```

---

## Phase 4: Running the Spinup

### Environment Setup
```bash
# Load uenv environment (CSCS Alps)
uenv run prgenv-gnu/24.11:v2 --view=spack -- bash -c "..."
```

### Single Station Test
```bash
cd /capstor/scratch/cscs/gsergi/CRYOWRF_ANT_CLIM/snowpack/Scripts/Spinup
uenv run prgenv-gnu/24.11:v2 --view=spack -- bash -c \
  "/users/gsergi/ALPINE3D/bin/snowpack -c cfgfiles/VIR_1_XXX_XXX.ini -b 1980-01-01 -e 1981-01-01"
```

### Mass Spinup (all stations)

1. **Generate seed .sno files** for all stations
2. **Submit SLURM job array**:
   ```bash
   sbatch job.sbatch
   ```

### Spinup Duration
- Recommended: 45 years (1980-2024) for full spinup
- Alternative: 10-year cycles repeated until equilibrium

---

## Validation and Results

### Expected Results (1-year test)

| Station | Latitude | Altitude | ΔSWE (kg/m²) | Final HS (cm) |
|---------|----------|----------|--------------|---------------|
| VIR_1_100_100 | -84.75°S | 636 m | ~197 | ~68 |
| VIR_1_120_120 | -88.75°S | 2914 m | ~34 | ~24 |
| VIR_1_150_150 | -78.50°S | 3673 m | ~18 | ~17 |

### Key Diagnostics
- Check MS_Sublimation in time series (should be small negative)
- Check Qs (sensible heat): typically -10 to +50 W/m²
- Check Ql (latent heat): typically -5 to +1 W/m²
- Check ILWR: should be ~100-170 W/m² (not ~18 W/m²)

---

## Troubleshooting

### No snow accumulation (HS=0)
- **Cause**: Missing seed snow layer
- **Fix**: Create .sno file with 10cm initial layer

### Extremely high heat fluxes (>1000 W/m²)
- **Cause**: Temperature mismatch between TSG and air temperature
- **Fix**: Set TSG generator to realistic cold value (230K)

### Low radiation values (ILWR ~18 W/m²)
- **Cause**: ERA5 units not corrected
- **Fix**: Apply x6 multiplier to ILWR and ISWR filters

### PSUM_PH invalid (value=5)
- **Cause**: ERA5 uses WMO codes, not 0-1 scale
- **Fix**: Use InputEditing EXCLUDE + CREATE with PRECSPLITTING

---

## File Checklist

Before running spinup:
- [ ] SMET files in `smet/` directory
- [ ] Seed .sno files in `current_snow/` (10cm layer, nSnowLayerData=1)
- [ ] Station config files in `cfgfiles/`
- [ ] base.ini with correct filters and generators
- [ ] spinup.ini with TS_WRITE=FALSE for production

---

## Contact

For issues with this procedure, check logs in:
- `log/` - SNOWPACK output logs
- `output/` - Simulation results
