# SNOWPACK Mountain Seasonal Snow Spinup Tutorial

A step-by-step guide for running a single-cycle SNOWPACK spinup for mountain regions
with seasonal snow (Pyrenees, Alps, Pamir, etc.), using ERA5-Land reanalysis forcing
at WRF domain gridpoint resolution.

**Author:** Sergi Gonzalez  
**Last Updated:** June 2026  
**Reference case:** Balandrau / Pyrenees (domains d01–d04)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: ERA5-Land Data Download and Conversion](#phase-1-era5-land-data-download-and-conversion)
4. [Phase 2: Create SMET Forcing Files](#phase-2-create-smet-forcing-files)
5. [Phase 3: Create Configuration and Initial Snow Files](#phase-3-create-configuration-and-initial-snow-files)
6. [Phase 4: Run the Spinup](#phase-4-run-the-spinup)
7. [Phase 5: Handle Failed Stations](#phase-5-handle-failed-stations)
8. [Critical Configuration Parameters](#critical-configuration-parameters)
9. [Known Pitfalls](#known-pitfalls)
10. [Quick Reference Cheatsheet](#quick-reference-cheatsheet)

---

## Overview

### Key Differences from the Antarctic Firn Spinup

| Aspect | Antarctic | Mountain (this tutorial) |
|--------|-----------|--------------------------|
| **Snow type** | Firn (50–100 m deep) | Seasonal (0–5 m) |
| **Simulation cycles** | Many (iterative until depth target) | **One single run** |
| **Start state** | Seed snow layer required | Bare ground + 1 soil layer |
| **Start date** | 1980-01-01 (decades) | **1 July** (or 1 September) |
| **End date** | 2024-12-31 | Target date (e.g., 29 December) |
| **Forcing data** | ERA5 (0.25°) | **ERA5-Land (0.1°)** |
| **Grid** | Virtual stations at ERA5 resolution | **Per WRF domain gridpoint** |
| **SNOWPACK variant** | POLAR | **DEFAULT** |
| **Coordinate system** | UPS | **UTM** |
| **Soil model** | SNP_SOIL = FALSE | **SNP_SOIL = TRUE** |
| **TSG (subsurface T)** | 230 K (−43°C) | **280 K (+7°C)** |

### Concept

For mountain regions, snow is seasonal and accumulates only in autumn and winter.
To initialize a CRYOWRF simulation, we only need to know the snow state at the
target start date (e.g., 29 December 2000). Starting from bare ground in summer
(July or September) and running forward a single time is sufficient — no iterative
cycles are needed.

### Workflow

```
ERA5-Land GRIB/NetCDF
    |
    v (make_smet_from_era5land.py)
SMET files per WRF gridpoint
    |  (one per land point in d01, d02, d03, d04)
    v (create_configs_balandrau.sh)
Initial SNO files (bare ground + 1 soil layer)
Per-station ini files
    |
    v (sbatch job_balandrau.sbatch)
Output SNO files (ProfileDate = target date)
    → Ready for CRYOWRF initial conditions
```

### Directory Structure

```
snowpack/Scripts/Spinup/
├── make_smet_from_era5land.py   # Phase 2: ERA5-Land → SMET per WRF gridpoint
├── create_configs_balandrau.sh  # Phase 3: SNO + ini file generation
├── base_balandrau.ini           # SNOWPACK configuration (this tutorial)
├── job_balandrau.sbatch         # Phase 4: main SLURM job
├── job_retry.sbatch             # Phase 5: retry failed stations
├── add_soil_layer.py            # Utility: patch SNO files with soil layer
├── fix_soil_layer.py            # Utility: fix soil layer parameters
├── to_exec.lst                  # Auto-generated: one command per station
├── to_exec_retry.lst            # Auto-generated: only failed stations
├── smet/
│   ├── d01/  (d01_j???_i???.smet)
│   ├── d02/
│   ├── d03/
│   └── d04/
├── cfgfiles/
│   ├── d01/  (d01_j???_i???.ini)
│   └── ...
├── current_snow/
│   ├── d01/  (d01_j???_i???.sno)   # initial state (bare ground)
│   └── ...
├── output/
│   ├── d01/  (d01_j???_i???.sno)   # final state (target date)
│   └── ...
└── log/
    ├── d01/  (d01_j???_i???.log)
    └── ...
```

---

## Prerequisites

### Software

- `snowpack` binary: `/users/gsergi/ALPINE3D/bin/snowpack`
- Python 3 with: `numpy`, `xarray`, `cfgrib` (for GRIB input), `netCDF4`
- GNU Parallel
- SLURM (CSCS Alps): `--uenv=prgenv-gnu/24.11:v2 --view=spack`

### WRF Domain Files

The geo_em.nc files for each domain, containing:
- `LANDMASK` variable (1=land, 0=ocean)  
- `XLAT_M`, `XLONG_M` (grid point coordinates)
- `HGT_M` (WRF terrain height in meters)

```
/capstor/scratch/cscs/gsergi/Balandrau/ScriptsSGH/
├── geo_em.d01.nc
├── geo_em.d02.nc
├── geo_em.d03.nc
└── geo_em.d04.nc
```

### ERA5-Land Data

ERA5-Land 3-hourly data for the simulation period. Variables needed:
- `sp` — surface pressure (Pa)
- `t2m` — 2m temperature (K)
- `d2m` — 2m dew point (K)
- `u10`, `v10` — 10m wind components (m/s)
- `ssrd` — surface solar radiation downwards (J/m², daily accumulated)
- `strd` — surface thermal radiation downwards (J/m², daily accumulated)
- `tp` — total precipitation (m, daily accumulated)

**ERA5-Land accumulation note**: `ssrd`, `strd`, and `tp` are accumulated daily
from 00:00 UTC. You must take 3-hourly differences to get instantaneous fluxes/rates.
The 00:00 UTC step of each day has accumulation = 0 (reset), so the first valid
difference is at 03:00 UTC.

Current data location:
```
/capstor/scratch/cscs/gsergi/DATA_BALANDRAU_SPINUP/
├── Balandrau_spinup_surfaceLand_2000_9.nc   (September)
├── Balandrau_spinup_surfaceLand_2000_10.nc  (October)
├── Balandrau_spinup_surfaceLand_2000_11.nc  (November)
└── Balandrau_spinup_surfaceLand_2000_12.nc  (December)
```

Coverage: 30–50°N, −10–15°E; resolution: 0.1°.

---

## Phase 1: ERA5-Land Data Download and Conversion

### 1.1 Download ERA5-Land from Copernicus CDS

Request 3-hourly data for your simulation period. Use the CDS API:

```python
import cdsapi
c = cdsapi.Client()
c.retrieve(
    'reanalysis-era5-land',
    {
        'variable': ['2m_temperature', '2m_dewpoint_temperature',
                     '10m_u_component_of_wind', '10m_v_component_of_wind',
                     'surface_pressure', 'surface_solar_radiation_downwards',
                     'surface_thermal_radiation_downwards', 'total_precipitation'],
        'year': '2000',
        'month': ['09', '10', '11', '12'],
        'day': [f'{d:02d}' for d in range(1, 32)],
        'time': ['00:00', '03:00', '06:00', '09:00', '12:00',
                 '15:00', '18:00', '21:00'],
        'area': [50, -10, 30, 15],  # N, W, S, E
        'format': 'netcdf',
    },
    'era5land_2000.nc')
```

### 1.2 Convert GRIB to NetCDF (if needed)

ERA5-Land is often delivered as GRIB. Convert with cfgrib/xarray:

```python
import xarray as xr

# GRIB files may have unsupported messages; use errors='ignore'
ds = xr.open_dataset('era5land.grib', engine='cfgrib',
                     backend_kwargs={'errors': 'ignore'})
ds.to_netcdf('era5land.nc')
```

### 1.3 Verify required variables

```bash
python3 - << 'EOF'
import xarray as xr, sys
ds = xr.open_dataset('Balandrau_spinup_surfaceLand_2000_9.nc')
print(ds)
for v in ['sp','t2m','d2m','u10','v10','ssrd','strd','tp']:
    if v not in ds:
        print(f"MISSING: {v}")
    else:
        print(f"OK: {v} shape={ds[v].shape}")
EOF
```

Expected shape: `(days, 8_timesteps, n_lat, n_lon)`.

---

## Phase 2: Create SMET Forcing Files

Working directory: `snowpack/Scripts/Spinup/`

Script: `make_smet_from_era5land.py`

### 2.1 What the script does

For each WRF land gridpoint (identified via `LANDMASK=1` in geo_em.nc):
1. Finds the nearest ERA5-Land grid cell (by lat/lon distance)
2. Applies a **lapse-rate altitude correction** to temperature:
   `ΔTA = −6.5 K/km × (alt_WRF − alt_ERA5-Land)`
   where ERA5-Land altitude is estimated from surface pressure:
   `alt = −8500 × ln(sp / 101325)`
3. Computes 3-hourly differences for accumulated variables (`ssrd`, `strd`, `tp`)
4. Converts units: radiation J/m² → W/m²; precipitation m → kg/m²
5. Derives relative humidity from `t2m` and `d2m` using the Magnus formula
6. Derives wind speed and direction from `u10`, `v10`
7. Writes one SMET file per WRF gridpoint:
   `smet/d01/d01_j000_i059.smet`

### 2.2 Run the script

```bash
cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup/

# Adjust paths at the top of the script if needed
# DATA_DIR: ERA5-Land NetCDF files
# GEO_DIR:  WRF geo_em.nc files
# MONTHS:   months to process (e.g. [9, 10, 11, 12])

python3 make_smet_from_era5land.py
```

Runtime: ~15–30 minutes for 4 domains (103,986 land gridpoints).

### 2.3 Verify output

```bash
ls smet/d01/ | wc -l   # expected: 12,753 for d01 (Pyrenees case)
ls smet/d02/ | wc -l   # expected: 27,672
ls smet/d03/ | wc -l   # expected: 50,650
ls smet/d04/ | wc -l   # expected: 12,911

# Spot-check a file
head -15 smet/d01/d01_j000_i059.smet
```

Expected SMET header:
```
SMET 1.1 ASCII
[HEADER]
station_id  = d01_j000_i059
latitude    = 36.3406
longitude   = 0.7236
altitude    = 94.8
nodata      = -999
tz          = 0
fields      = timestamp TA RH VW DW ISWR ILWR PSUM
[DATA]
2000-09-01T00:00:00 297.040 0.7607 1.667 65.75 -999.000 -999.000 -999.00000
2000-09-01T03:00:00 294.826 0.9068 1.263 74.71 0.000 355.846 0.00000
```

**Important**: The 00:00 UTC timestep will have `-999` for ISWR and PSUM (the
accumulation resets at midnight, so the first valid difference is at 03:00).
This is handled by gap-filling in `base_balandrau.ini` (see Section 8).

---

## Phase 3: Create Configuration and Initial Snow Files

### 3.1 Run the setup script

```bash
cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup/
bash create_configs_balandrau.sh
```

This script:
- Creates `current_snow/d01/.../d04/` (initial SNO files, bare ground + 1 soil layer)
- Creates `cfgfiles/d01/.../d04/` (per-station ini files)
- Creates `output/d01/.../d04/` and `log/d01/.../d04/` directories
- Appends all commands to `to_exec.lst`

Verify counts match:
```bash
wc -l to_exec.lst   # should equal total land gridpoints
```

### 3.2 Initial SNO file format

Each station starts from bare ground with a single 0.5 m soil layer.
This is essential — without soil layers, SNOWPACK has zero thermal mass and
diverges numerically on bare ground.

```
SMET 1.1 ASCII
[HEADER]
station_id       = d01_j000_i059
latitude         = 36.3406
longitude        = 0.7236
altitude         = 94.8
nodata           = -999
ProfileDate      = 2000-09-01T00:00:00
HS_Last          = 0.00
nSoilLayerData   = 1
nSnowLayerData   = 0
SoilAlbedo       = 0.09
BareSoil_z0      = 0.020
fields           = timestamp Layer_Thick T Vol_Frac_I Vol_Frac_W Vol_Frac_V Vol_Frac_S Rho_S Conduc_S HeatCapac_S rg rb dd sp mk mass_hoar ne CDot metamo
[DATA]
2000-09-01T00:00:00 0.50 280.0 0.00 0.00 0.30 0.70 2400.0 2.0 2000.0 1000.0 0.0 0.0 1.0 1 0.0 3 0.0 0.0
```

**Soil layer parameters** (must match values from working PAMIR/Alpine references):

| Field | Value | Notes |
|-------|-------|-------|
| `Layer_Thick` | 0.50 | 50 cm — provides thermal mass |
| `T` | 280.0 | 7°C — matches TSG generator |
| `Vol_Frac_I` | 0.00 | No ice in summer |
| `Vol_Frac_W` | 0.00 | Dry soil (conservative) |
| `Vol_Frac_V` | 0.30 | 30% pore space |
| `Vol_Frac_S` | 0.70 | 70% mineral |
| `Rho_S` | 2400.0 | kg/m³ mineral density |
| `Conduc_S` | 2.0 | W/m/K thermal conductivity |
| `HeatCapac_S` | 2000.0 | J/kg/K **specific** heat (not volumetric!) |
| `rg` | 1000.0 | µm grain radius (soil, not used physically) |
| `sp` | 1.0 | Sphericity = 1 for soil grains |
| `mk` | 1 | Layer marker |
| `ne` | 3 | Elements per layer (important for numerical stability) |

**Critical**: `ne=0` will cause SNOWPACK to report "no soil layers given" even
when `nSoilLayerData=1` is set. Always use `ne>=1`.

### 3.3 Per-station ini file format

```ini
[GENERAL]
IMPORT_BEFORE = ../../base_balandrau.ini

[INPUT]
METEOPATH  = smet/d01/
SNOWPATH   = current_snow/d01/
METEOFILE1 = d01_j000_i059.smet
SNOWFILE1  = d01_j000_i059.sno

[OUTPUT]
METEOPATH  = output/d01/
PROF_WRITE = FALSE
TS_WRITE   = FALSE
```

**Path resolution rules** (MeteoIO asymmetry):
- `IMPORT_BEFORE` is resolved **relative to the ini file location**
  (`cfgfiles/d01/` → `../../base_balandrau.ini` = `Scripts/Spinup/base_balandrau.ini`)
- All other path keys (`METEOPATH`, `SNOWPATH`) are resolved **relative to the
  working directory** where `snowpack` is invoked (`Scripts/Spinup/`)

---

## Phase 4: Run the Spinup

### 4.1 Submit the SLURM job

```bash
cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup/
sbatch job_balandrau.sbatch
```

The job runs all stations in parallel (`parallel -j 128`) on 1 node.

**Expected runtime**: ~15–30 minutes for ~104,000 stations on 128 CPUs.

### 4.2 Monitor progress

```bash
squeue -u $USER

# Once complete, check output counts
for dom in d01 d02 d03 d04; do
  expected=$(ls cfgfiles/${dom}/*.ini | wc -l)
  got=$(ls output/${dom}/*.sno 2>/dev/null | wc -l)
  echo "$dom: $got / $expected"
done
```

### 4.3 Check a sample log

```bash
cat log/d01/d01_j000_i059.log
```

A successful run shows:
```
[i] --> Start SNOWPACK w/ soil layers in RESEARCH mode
[i] Finished initializing station d01_j000_i059
[i] --> Start simulation for d01_j000_i059 on 2000-08-31T23:00:00+00:00
[i] [2000-09-16T00:00:00] --> advanced to 16.09.2000 ...
[i] [2000-10-01T00:00:00] --> advanced to 01.10.2000 ...
...
[i] --> Writing data to sno file(s) for d01_j000_i059 on 2000-12-29T00:00:00
FINISHED running SLF RESEARCH Snowpack Model
```

---

## Phase 5: Handle Failed Stations

A small fraction of stations (~1–6%) may fail. Two types of failures occur:

### Type 1: T_CRAZY threshold exceeded

```
[E] Temperature out of bound at beginning of iteration!
At node n=2 (nN=4, SoilNode=3): T=341.50
```

**Cause**: Hot, dry bare soil in the Mediterranean lowlands can reach surface
temperatures just above T_CRAZY_MAX (340 K = 67°C).

**Fix**: Increase T_CRAZY_MAX in `base_balandrau.ini`:
```ini
T_CRAZY_MAX = 350
```

Or for cold snow nodes after fresh snowfall with clear sky:
```ini
T_CRAZY_MIN = 150
```

### Type 2: All-nodata SMET file

```
[E] d03_j000_i137 missing { TA RH sw_radiation ... } on 2000-09-01T00:00:00
```

**Cause**: The WRF land mask classifies some coastal/estuary pixels as land,
but ERA5-Land has no data for those cells (they are ocean in ERA5-Land).
These stations cannot be fixed — they have no valid input data.

### 5.1 Rebuild the retry list

```bash
cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup/

> to_exec_retry.lst
for dom in d01 d02 d03 d04; do
  comm -23 \
    <(ls cfgfiles/${dom}/ | sed 's/\.ini$//' | sort) \
    <(ls output/${dom}/ 2>/dev/null | sed 's/\.sno$//' | sort) \
    | while read stn; do
        echo "/users/gsergi/ALPINE3D/bin/snowpack -c ./cfgfiles/${dom}/${stn}.ini -e 2000-12-29 > log/${dom}/${stn}.log 2>&1"
      done
done >> to_exec_retry.lst

wc -l to_exec_retry.lst
```

### 5.2 Submit the retry job

```bash
sbatch job_retry.sbatch
```

After retry, verify counts again. Remaining failures are almost certainly
Type 2 (no-data) and cannot be recovered.

---

## Critical Configuration Parameters

### `base_balandrau.ini` key settings

#### Coordinate system (mandatory — this MeteoIO version is strict)

```ini
[INPUT]
COORDSYS   = UTM
COORDPARAM = 31T    # UTM zone + latitude band; 31T covers Pyrenees (0-6°E, 40-48°N)

[OUTPUT]
COORDSYS   = UTM
COORDPARAM = 31T
```

**Valid COORDSYS values**: `LOCAL`, `CH1903`, `CH1903+`, `UTM`, `UPS`, `PROJ`.  
`WGS84` and `LATLON` are **not** valid in this MeteoIO version and will crash.

For other mountain regions:
- Alps (Switzerland): `CH1903+`
- Pamir (47°E): `UTM`, `COORDPARAM = 47S`
- General mid-latitude: `UTM`, select zone covering your domain centre

#### Gap-filling for midnight timestep

ERA5-Land resets accumulations at 00:00 UTC, so ISWR and PSUM are nodata
at midnight. Add extrapolation so MeteoIO fills from the 03:00 data point:

```ini
[INTERPOLATIONS1D]
ISWR::resample1         = nearest
ISWR::arg1::extrapolate = TRUE

PSUM::resample1         = nearest
PSUM::arg1::extrapolate = TRUE

ILWR::resample1         = linear
ILWR::arg1::extrapolate = TRUE
```

#### Soil model

```ini
[SNOWPACK]
SNP_SOIL  = TRUE    # Must be TRUE; bare ground with no soil → T diverges
GEO_HEAT  = 0.06   # W/m², typical geothermal heat flux for mountain terrain
SOIL_FLUX = TRUE
```

#### Temperature bounds (wider than default for Mediterranean stations)

```ini
[SNOWPACKADVANCED]
T_CRAZY_MIN = 150   # K (−123°C): allow cold nights after fresh snowfall
T_CRAZY_MAX = 350   # K (+77°C): allow hot bare soil in Mediterranean lowlands
```

#### ILWR minimum (prevent excessive snow-surface cooling)

```ini
[FILTERS]
ILWR::filter2         = min_max
ILWR::arg2::min       = 150    # W/m² soft minimum (replaces values below)
ILWR::arg2::max       = 400
ILWR::arg2::soft      = TRUE
```

#### Physics settings

```ini
[SNOWPACK]
CALCULATION_STEP_LENGTH = 60      # minutes
VARIANT                 = DEFAULT  # not POLAR
ATMOSPHERIC_STABILITY   = MO_MICHLMAYR
FORCING                 = ATMOS
MEAS_TSS                = FALSE
CHANGE_BC               = FALSE

[SNOWPACKADVANCED]
ALLOW_ADAPTIVE_TIMESTEPPING = TRUE
FORCE_ADD_SNOWFALL          = TRUE
MAX_SIMULATED_HS            = 5    # metres (seasonal snow, not firn)
```

#### Lower boundary temperature

```ini
[GENERATORS]
TSG::generator1     = CST
TSG::arg1::value    = 280.0   # 7°C: typical Pyrenean shallow soil
```

#### Precipitation phase splitting

```ini
[InputEditing]
*::edit1               = CREATE
*::arg1::algorithm     = PRECSPLITTING
*::arg1::param         = PSUM_PH
*::arg1::type          = THRESH
*::arg1::snow          = 274.35   # snow below 1.2°C
```

---

## Known Pitfalls

### 1. `Unknown coordinate system "LATLON"` or `"WGS84"`

MeteoIO (this version) does not accept `LATLON` or `WGS84` as COORDSYS values.
Use `UTM` with an appropriate `COORDPARAM` zone.

### 2. `SNP_SOIL set but no soil layers given`

This occurs when `ne = 0` in the soil data row, even if `nSoilLayerData = 1` is
set in the header. Always set `ne = 3` (or any positive integer) in soil rows.

### 3. `Temperature out of bound` at simulation start

If `nSoilLayerData = 0` (no soil layer), SNOWPACK runs with zero thermal mass
and temperatures diverge immediately. Every SNO file must have at least one soil
layer when `SNP_SOIL = TRUE`.

### 4. METEOFILE1 vs STATION1 (deprecated)

```ini
# WRONG (deprecated, silently ignored in some versions):
STATION1 = d01_j000_i059.smet

# CORRECT:
METEOFILE1 = d01_j000_i059.smet
```

### 5. IMPORT_BEFORE path is relative to the ini file, not to the working dir

If `cfgfiles/d01/d01_j000_i059.ini` imports the base config, the path must be:
```ini
IMPORT_BEFORE = ../../base_balandrau.ini   # relative to cfgfiles/d01/
```
**Not** `base_balandrau.ini` (which would be relative to the working directory).

### 6. WINDOW_SIZE deprecated

Replace `WINDOW_SIZE` in `[INTERPOLATIONS1D]` with `MAX_GAP_SIZE`. The old key
still produces warnings but also sets incorrect defaults in newer MeteoIO.

### 7. Duplicate entries in to_exec.lst

If `create_configs_balandrau.sh` is run more than once, it appends to
`to_exec.lst`. Deduplicate before submitting:
```bash
sort -u to_exec.lst > to_exec_clean.lst && mv to_exec_clean.lst to_exec.lst
wc -l to_exec.lst
```

### 8. ERA5-Land accumulation reset at midnight

For `ssrd`, `strd`, `tp`: ERA5-Land resets the daily accumulation counter at
00:00 UTC. The 3-hourly difference algorithm gives nodata (or zero) at the
00:00 step. Gap-filling with `nearest` + `extrapolate = TRUE` resolves this.

---

## Quick Reference Cheatsheet

### Full spinup from scratch

```bash
cd /capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup/

# Step 1: Create SMET files (ERA5-Land → per WRF gridpoint)
python3 make_smet_from_era5land.py

# Step 2: Create ini and SNO files
bash create_configs_balandrau.sh

# Step 3: Verify to_exec.lst has no duplicates
sort -u to_exec.lst -o to_exec.lst
wc -l to_exec.lst

# Step 4: Submit spinup
sbatch job_balandrau.sbatch

# Step 5: After completion, count results
for dom in d01 d02 d03 d04; do
  echo "$dom: $(ls output/${dom}/*.sno 2>/dev/null | wc -l)"
done

# Step 6: Retry failed stations (adjust T_CRAZY first if needed)
# (edit T_CRAZY_MIN / T_CRAZY_MAX in base_balandrau.ini)
# Build retry list:
> to_exec_retry.lst
for dom in d01 d02 d03 d04; do
  comm -23 \
    <(ls cfgfiles/${dom}/ | sed 's/\.ini$//' | sort) \
    <(ls output/${dom}/ 2>/dev/null | sed 's/\.sno$//' | sort) \
    | sed "s|^|/users/gsergi/ALPINE3D/bin/snowpack -c ./cfgfiles/${dom}/|;s|$|.ini -e 2000-12-29 > log/${dom}/\0.log 2>&1|" \
    >> to_exec_retry.lst
done
sbatch job_retry.sbatch
```

### Adapt to a different mountain region

1. **Download ERA5-Land**: adjust domain bbox and date range
2. **Update `make_smet_from_era5land.py`**: change `DATA_DIR`, `GEO_DIR`, `MONTHS`, `START_DATE`
3. **Update `base_balandrau.ini`**:
   - `COORDPARAM`: choose UTM zone covering your domain (e.g., `47S` for Pamir)
   - `TSG::value`: mean annual ground temperature at ~1 m depth for your region
4. **Update `create_configs_balandrau.sh`**:
   - `END_DATE`: your target date
5. **Update `job_balandrau.sbatch`**:
   - `--account`, `--mail-user`, time limit if needed

### Patch existing SNO files to add soil layer (utility)

If SNO files were created without a soil layer:
```bash
python3 add_soil_layer.py    # adds nSoilLayerData=1 with placeholder row
python3 fix_soil_layer.py    # corrects parameters (ne=3, mk=1, etc.)
```

Or regenerate cleanly by re-running `create_configs_balandrau.sh` after updating it.

---

## File Inventory

| File | Purpose | Commit? |
|------|---------|---------|
| `base_balandrau.ini` | SNOWPACK + MeteoIO configuration | Yes |
| `make_smet_from_era5land.py` | ERA5-Land → per-WRF-gridpoint SMET | Yes |
| `create_configs_balandrau.sh` | Creates SNO + ini + to_exec.lst | Yes |
| `job_balandrau.sbatch` | SLURM submission (128 CPUs, 24h) | Yes |
| `job_retry.sbatch` | SLURM retry for failed stations | Yes |
| `add_soil_layer.py` | Utility: add soil layer to SNO files | Yes |
| `fix_soil_layer.py` | Utility: fix soil layer parameters | Yes |
| `smet/d01–d04/` | Input forcing (103,986 SMET files) | No (data) |
| `cfgfiles/d01–d04/` | Per-station ini files | No (data) |
| `current_snow/d01–d04/` | Initial SNO (bare ground + soil) | No (data) |
| `output/d01–d04/` | Final SNO at target date | No (data) |
| `to_exec.lst` | Execution list | No (generated) |

---

*This tutorial documents the mountain seasonal snow spinup procedure developed for
the CRYOWRF Balandrau (Pyrenees) project, June 2026.*
