#!/usr/bin/env python3
"""Add a single 0.5 m soil layer to all existing SNO files for Balandrau spinup.

Soil parameters for alpine terrain:
  - Vol_Frac_I=0, Vol_Frac_W=0.10, Vol_Frac_V=0.15, Vol_Frac_S=0.75 (sum=1)
  - Rho_S=2650 kg/m3, Conduc_S=2.2 W/m/K, HeatCapac_S=2.35e6 J/m3/K
  - T = 280 K (7 C, matches TSG generator)
"""
import os, re, glob

BASE = os.path.dirname(os.path.abspath(__file__))

SOIL_THICK  = 0.50
SOIL_T      = 280.0
SOIL_FMT = (
    "{ts} {thick:.2f} {T:.1f} "
    "0.00 0.10 0.15 0.75 "
    "2650.0 2.2 2350000.0 "
    "0.0 0.0 0.0 0.0 0 0.0 0 0.0 0.0"
)

fixed = 0
for dom in ("d01", "d02", "d03", "d04"):
    pattern = os.path.join(BASE, "current_snow", dom, "*.sno")
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            txt = f.read()

        # Only patch files that haven't been patched yet
        if "nSoilLayerData   = 1" in txt:
            continue

        m = re.search(r"ProfileDate\s*=\s*(\S+)", txt)
        if not m:
            print(f"WARNING: no ProfileDate in {path}")
            continue
        ts = m.group(1)

        soil_row = SOIL_FMT.format(ts=ts, thick=SOIL_THICK, T=SOIL_T)

        txt = txt.replace("nSoilLayerData   = 0", "nSoilLayerData   = 1")
        txt = txt.replace("[DATA]\n", f"[DATA]\n{soil_row}\n")

        with open(path, "w") as f:
            f.write(txt)
        fixed += 1

print(f"Patched {fixed} SNO files with a soil layer.")
