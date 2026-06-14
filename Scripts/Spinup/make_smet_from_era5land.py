#!/usr/bin/env python3
"""
Create per-WRF-gridpoint SMET files from ERA5-Land NC data for SNOWPACK spinup.

For each of the 4 WRF domains (d01-d04), for each land gridpoint:
  - finds the nearest ERA5-Land grid cell
  - applies a lapse-rate correction to TA  (ΔT = -6.5 K/km × Δalt)
  - writes a SMET file with the WRF lat/lon/altitude in the header

Output: smet/d01/d01_j{j:03d}_i{i:03d}.smet   (and d02, d03, d04)

ERA5-Land variable notes:
  ssrd, strd, tp  – cumulative from 00:00 UTC each day; converted to 3-h averages here.
  t2m, d2m, u10, v10, sp – instantaneous.
"""

import os
import sys
import numpy as np
import netCDF4 as nc
from datetime import datetime, timedelta

# ── paths ──────────────────────────────────────────────────────────────────────
DATA_DIR    = "/capstor/scratch/cscs/gsergi/DATA_BALANDRAU_SPINUP"
GEO_DIR     = "/capstor/scratch/cscs/gsergi/Balandrau/ScriptsSGH"
OUT_BASE    = "/capstor/scratch/cscs/gsergi/Balandrau/snowpack/Scripts/Spinup/smet"
NC_FILES    = [
    os.path.join(DATA_DIR, f"Balandrau_spinup_surfaceLand_2000_{m}.nc")
    for m in [9, 10, 11, 12]
]

START_DATE  = datetime(2000, 9, 1,  0, 0)
END_DATE    = datetime(2000, 12, 29, 21, 0)   # last 3-h step on Dec 29
LAPSE_RATE  = -6.5e-3                          # K/m


# ── helpers ───────────────────────────────────────────────────────────────────

def sat_vap_press(T_K):
    Tc = T_K - 273.15
    return 611.2 * np.exp(17.67 * Tc / (Tc + 243.5))

def wind_speed(u, v):
    return np.sqrt(u**2 + v**2)

def wind_dir(u, v):
    return (np.degrees(np.arctan2(-u, -v))) % 360.0

def alt_from_sp(sp_Pa):
    """Rough altitude (m) from mean surface pressure."""
    return -8500.0 * np.log(np.clip(sp_Pa, 1, None) / 101325.0)


# ── load ERA5-Land into flat time-series arrays ────────────────────────────────

def load_era5land():
    print("Loading ERA5-Land NC files ...", flush=True)

    raw_times  = []
    raw_vars   = {v: [] for v in ["t2m","d2m","u10","v10","sp","ssrd","strd","tp"]}

    for nc_path in NC_FILES:
        ds      = nc.Dataset(nc_path)
        vt_var  = ds.variables["valid_time"]
        vt_base = datetime.strptime(
            vt_var.units.replace("hours since ", ""), "%Y-%m-%d %H:%M:%S")
        vt_data = np.array(vt_var[:])              # (ndays, 8)
        ndays, nstep = vt_data.shape

        raw = {}
        for v in raw_vars:
            raw[v] = np.ma.filled(np.array(ds.variables[v][:]), np.nan)

        for d in range(ndays):
            valid_steps = ~np.all(np.isnan(raw["t2m"][d]), axis=(1, 2))

            # 3-h differences for accumulated variables (cumulative from 00:00 UTC)
            diff_ssrd = np.concatenate(
                [raw["ssrd"][d, [0]], np.diff(raw["ssrd"][d], axis=0)], axis=0)
            diff_strd = np.concatenate(
                [raw["strd"][d, [0]], np.diff(raw["strd"][d], axis=0)], axis=0)
            diff_tp   = np.concatenate(
                [raw["tp"][d, [0]],   np.diff(raw["tp"][d],   axis=0)], axis=0)

            diff_ssrd = np.clip(diff_ssrd, 0, None) / 10800.0   # W/m²
            diff_strd = np.clip(diff_strd, 0, None) / 10800.0   # W/m²
            diff_tp   = np.clip(diff_tp,   0, None) * 1000.0    # m → kg/m²

            for s in range(nstep):
                if not valid_steps[s]:
                    continue
                t = vt_base + timedelta(hours=float(vt_data[d, s]))
                if t < START_DATE or t > END_DATE:
                    continue
                raw_times.append(t)
                for v in ["t2m","d2m","u10","v10","sp"]:
                    raw_vars[v].append(raw[v][d, s])
                raw_vars["ssrd"].append(diff_ssrd[s])
                raw_vars["strd"].append(diff_strd[s])
                raw_vars["tp"].append(diff_tp[s])

        ds.close()
        print(f"  {os.path.basename(nc_path)}: {len(raw_times)} timesteps", flush=True)

    # sort + deduplicate
    order = np.argsort([t.timestamp() for t in raw_times])
    times_sorted = [raw_times[i] for i in order]
    seen, uniq_idx = set(), []
    for k, t in enumerate(times_sorted):
        key = int(t.timestamp())
        if key not in seen:
            seen.add(key)
            uniq_idx.append(order[k])

    times = [raw_times[i] for i in uniq_idx]
    N_t   = len(times)

    data = {}
    for v in raw_vars:
        arr = np.array(raw_vars[v])     # (N_raw, nlat, nlon)
        data[v] = arr[np.array(uniq_idx)]

    print(f"Unique timesteps: {N_t}  ({times[0]} – {times[-1]})", flush=True)
    return times, data


# ── get ERA5-Land lat/lon grid ─────────────────────────────────────────────────

def get_era5l_grid():
    ds  = nc.Dataset(NC_FILES[0])
    lat = np.array(ds.variables["latitude"][:])   # decreasing (50 → 30)
    lon = np.array(ds.variables["longitude"][:])  # increasing (−10 → 15)
    ds.close()
    return lat, lon


# ── write one SMET file ────────────────────────────────────────────────────────

def write_smet(path, stn_id, lat, lon, alt, times, ta, rh, vw, dw, iswr, ilwr, psum):
    lines = [
        "SMET 1.1 ASCII\n",
        "[HEADER]\n",
        f"station_id       = {stn_id}\n",
        f"station_name     = {stn_id}\n",
        f"latitude         = {lat:.4f}\n",
        f"longitude        = {lon:.4f}\n",
        f"altitude         = {alt:.1f}\n",
        "nodata           = -999\n",
        "tz               = 0\n",
        "fields           = timestamp TA RH VW DW ISWR ILWR PSUM\n",
        "[DATA]\n",
    ]
    for k in range(len(times)):
        ts  = times[k].strftime("%Y-%m-%dT%H:%M:%S")
        ta_v    = -999 if np.isnan(ta[k])   else ta[k]
        rh_v    = -999 if np.isnan(rh[k])   else rh[k]
        vw_v    = -999 if np.isnan(vw[k])   else vw[k]
        dw_v    = -999 if np.isnan(dw[k])   else dw[k]
        iswr_v  = -999 if np.isnan(iswr[k]) else iswr[k]
        ilwr_v  = -999 if np.isnan(ilwr[k]) else ilwr[k]
        psum_v  = -999 if np.isnan(psum[k]) else psum[k]
        lines.append(
            f"{ts} {ta_v:.3f} {rh_v:.4f} {vw_v:.3f} "
            f"{dw_v:.2f} {iswr_v:.3f} {ilwr_v:.3f} {psum_v:.5f}\n"
        )
    with open(path, "w") as f:
        f.writelines(lines)


# ── main ───────────────────────────────────────────────────────────────────────

def main():
    times, data = load_era5land()
    e5_lat, e5_lon = get_era5l_grid()
    N_t = len(times)

    # altitude from mean surface pressure for each ERA5-L cell
    e5_alt = alt_from_sp(np.nanmean(data["sp"], axis=0))  # (nlat, nlon)

    for dom in [1, 2, 3, 4]:
        dom_tag   = f"d0{dom}"
        out_dir   = os.path.join(OUT_BASE, dom_tag)
        os.makedirs(out_dir, exist_ok=True)

        geo_path = os.path.join(GEO_DIR, f"geo_em.{dom_tag}.nc")
        ds_geo   = nc.Dataset(geo_path)
        wrf_lat  = ds_geo.variables["XLAT_M"][0]   # (ny, nx)
        wrf_lon  = ds_geo.variables["XLONG_M"][0]
        wrf_hgt  = ds_geo.variables["HGT_M"][0]
        landmask = ds_geo.variables["LANDMASK"][0]
        ds_geo.close()

        ny, nx     = wrf_lat.shape
        land_j, land_i = np.where(landmask == 1)
        n_land     = len(land_j)
        print(f"\n{dom_tag}: {n_land} land gridpoints, writing to {out_dir}", flush=True)

        # vectorised nearest-ERA5L lookup
        # e5_lat is decreasing → flip before searchsorted
        j_era5 = np.clip(
            np.round((e5_lat[0] - wrf_lat[land_j, land_i]) / 0.1).astype(int),
            0, len(e5_lat) - 1
        )
        i_era5 = np.clip(
            np.round((wrf_lon[land_j, land_i] - e5_lon[0]) / 0.1).astype(int),
            0, len(e5_lon) - 1
        )

        n_written = 0
        for k in range(n_land):
            j_w  = land_j[k]
            i_w  = land_i[k]
            j_e  = j_era5[k]
            i_e  = i_era5[k]

            lat_w = float(wrf_lat[j_w, i_w])
            lon_w = float(wrf_lon[j_w, i_w])
            alt_w = float(wrf_hgt[j_w, i_w])

            # altitude correction to TA
            dalt  = alt_w - e5_alt[j_e, i_e]
            ta_raw = data["t2m"][:, j_e, i_e]
            ta_corr = ta_raw + LAPSE_RATE * dalt

            rh   = np.clip(
                sat_vap_press(data["d2m"][:, j_e, i_e]) / sat_vap_press(ta_raw),
                0.01, 1.0)
            vw   = wind_speed(data["u10"][:, j_e, i_e], data["v10"][:, j_e, i_e])
            dw   = wind_dir(data["u10"][:, j_e, i_e], data["v10"][:, j_e, i_e])
            iswr = data["ssrd"][:, j_e, i_e]
            ilwr = data["strd"][:, j_e, i_e]
            psum = data["tp"][:, j_e, i_e]

            stn_id  = f"{dom_tag}_j{j_w:03d}_i{i_w:03d}"
            outpath = os.path.join(out_dir, stn_id + ".smet")

            write_smet(outpath, stn_id, lat_w, lon_w, alt_w,
                       times, ta_corr, rh, vw, dw, iswr, ilwr, psum)

            n_written += 1
            if n_written % 5000 == 0:
                print(f"  {dom_tag}: {n_written}/{n_land} written ...", flush=True)

        print(f"  {dom_tag}: done ({n_written} files)", flush=True)

    print("\nAll domains complete.", flush=True)


if __name__ == "__main__":
    main()
