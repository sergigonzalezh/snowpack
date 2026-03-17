#!/usr/bin/env python3
"""
Copy nearest-neighbor .sno profiles for stations with numerical instability.

For stations that fail the spinup (e.g. due to extreme temperature crashes),
this script finds the closest completed station (weighted by horizontal distance
and altitude difference) and copies its .sno profile, updating the header
(station_id, latitude, longitude, altitude).

Usage:
    python copy_nearest_profiles.py \
        --failed-list failed_stations.csv \
        --completed-dir Results/final_sno \
        --smet-dir smet \
        --output-dir Results/final_sno \
        --tracking-csv Results/copied_profiles_tracking.csv

The failed_stations.csv should have one station name per line (e.g. VIR_1_36_143).
If not provided, the script reads from to_exec_short_dt.lst and checks which
stations are missing from the output directory.
"""

import argparse
import csv
import glob
import math
import os
import re
import sys


def parse_smet_header(smet_path):
    """Extract lat, lon, alt from a .smet file header."""
    info = {}
    with open(smet_path, "r") as f:
        for line in f:
            if line.strip() == "[DATA]":
                break
            for key in ("latitude", "longitude", "altitude"):
                if line.strip().startswith(key):
                    info[key] = float(line.strip().split("=")[-1].strip())
    return info.get("latitude"), info.get("longitude"), info.get("altitude")


def haversine_km(lat1, lon1, lat2, lon2):
    """Great-circle distance in km."""
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, [lat1, lon1, lat2, lon2])
    dlat = lat2 - lat1
    dlon = lon2 - lon1
    a = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return R * 2 * math.asin(math.sqrt(a))


def weighted_distance(h_km, alt_diff_m, alt_weight=0.04):
    """Combined distance: horizontal (km) + altitude penalty (default 40m = 1km)."""
    return math.sqrt(h_km ** 2 + (alt_diff_m * alt_weight) ** 2)


def copy_sno_with_new_header(src_sno, dst_sno, new_station_id, new_lat, new_lon, new_alt):
    """Copy a .sno file, replacing station_id, latitude, longitude, altitude in header."""
    with open(src_sno, "r") as f:
        lines = f.readlines()

    with open(dst_sno, "w") as f:
        for line in lines:
            stripped = line.strip()
            if stripped.startswith("station_id"):
                f.write(f"station_id       = {new_station_id}\n")
            elif stripped.startswith("latitude"):
                f.write(f"latitude         = {new_lat:.6f}\n")
            elif stripped.startswith("longitude"):
                f.write(f"longitude        = {new_lon:.6f}\n")
            elif stripped.startswith("altitude"):
                f.write(f"altitude         = {new_alt}\n")
            else:
                f.write(line)


def main():
    parser = argparse.ArgumentParser(description="Copy nearest-neighbor .sno profiles")
    parser.add_argument("--failed-list", help="File with failed station names (one per line)")
    parser.add_argument("--completed-dir", default="Results/final_sno",
                        help="Directory with completed .sno files")
    parser.add_argument("--smet-dir", default="smet",
                        help="Directory with .smet files (for coordinates)")
    parser.add_argument("--output-dir", default="Results/final_sno",
                        help="Where to write copied .sno files")
    parser.add_argument("--tracking-csv", default="Results/copied_profiles_tracking.csv",
                        help="Output CSV tracking which profiles were copied")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print matches without copying")
    args = parser.parse_args()

    # Build list of failed stations
    failed_stations = []
    if args.failed_list:
        with open(args.failed_list) as f:
            for line in f:
                stn = line.strip()
                if stn and not stn.startswith("#"):
                    # Handle lines from to_exec.lst format
                    m = re.search(r"cfgfiles/(\S+)\.ini", stn)
                    if m:
                        stn = m.group(1)
                    failed_stations.append(stn)
    else:
        # Auto-detect: stations with .smet but no .sno in completed_dir
        for smet_file in sorted(glob.glob(os.path.join(args.smet_dir, "*.smet"))):
            stn = os.path.basename(smet_file).replace(".smet", "")
            if not os.path.exists(os.path.join(args.completed_dir, f"{stn}.sno")):
                failed_stations.append(stn)

    if not failed_stations:
        print("No failed stations found.")
        return

    print(f"Failed stations: {len(failed_stations)}")

    # Build coordinate database for completed stations
    completed = {}
    for sno_file in glob.glob(os.path.join(args.completed_dir, "*.sno")):
        stn = os.path.basename(sno_file).replace(".sno", "")
        smet_path = os.path.join(args.smet_dir, f"{stn}.smet")
        if os.path.exists(smet_path):
            lat, lon, alt = parse_smet_header(smet_path)
            if lat is not None:
                completed[stn] = (lat, lon, alt, sno_file)

    print(f"Completed stations with coordinates: {len(completed)}")

    # Find nearest neighbor for each failed station
    tracking = []
    for stn in failed_stations:
        smet_path = os.path.join(args.smet_dir, f"{stn}.smet")
        if not os.path.exists(smet_path):
            print(f"WARNING: No .smet for {stn}, skipping")
            continue

        lat, lon, alt = parse_smet_header(smet_path)

        best_stn = None
        best_dist = float("inf")
        best_h_km = 0
        best_alt_diff = 0

        for c_stn, (c_lat, c_lon, c_alt, c_sno) in completed.items():
            h_km = haversine_km(lat, lon, c_lat, c_lon)
            alt_diff = abs(alt - c_alt)
            wd = weighted_distance(h_km, alt_diff)
            if wd < best_dist:
                best_dist = wd
                best_stn = c_stn
                best_h_km = h_km
                best_alt_diff = alt_diff

        if best_stn is None:
            print(f"WARNING: No match for {stn}")
            continue

        c_lat, c_lon, c_alt, c_sno = completed[best_stn]
        dst_sno = os.path.join(args.output_dir, f"{stn}.sno")

        if not args.dry_run:
            copy_sno_with_new_header(c_sno, dst_sno, stn, lat, lon, alt)

        tracking.append({
            "failed_station": stn, "failed_lat": lat, "failed_lon": lon, "failed_alt": alt,
            "source_station": best_stn, "source_lat": c_lat, "source_lon": c_lon, "source_alt": c_alt,
            "horiz_dist_km": round(best_h_km, 2),
            "alt_diff_m": round(best_alt_diff, 1),
            "weighted_dist_km": round(best_dist, 2),
        })

        action = "WOULD COPY" if args.dry_run else "COPIED"
        print(f"  {action}: {stn} <- {best_stn} (dist={best_h_km:.1f}km, alt_diff={best_alt_diff:.0f}m)")

    # Write tracking CSV
    if tracking and not args.dry_run:
        with open(args.tracking_csv, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=tracking[0].keys())
            writer.writeheader()
            writer.writerows(tracking)
        print(f"\nTracking CSV written to {args.tracking_csv}")

    print(f"\nDone: {len(tracking)} stations {'matched' if args.dry_run else 'copied'}")


if __name__ == "__main__":
    main()
