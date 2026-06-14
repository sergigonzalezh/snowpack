#!/usr/bin/env python3
"""Fix soil layer parameters in already-patched SNO files.

Corrects values to match working PAMIR example:
  rg=1000, sp=1.0, mk=1, ne=3, HeatCapac_S=2000 J/kg/K (specific heat)
  Vol_Frac_V=0.30, Vol_Frac_S=0.70, Rho_S=2400, Conduc_S=2.0
"""
import os, re, glob

BASE = os.path.dirname(os.path.abspath(__file__))

SOIL_FMT = (
    "{ts} 0.50 280.0 "
    "0.00 0.00 0.30 0.70 "
    "2400.0 2.0 2000.0 "
    "1000.0 0.0 0.0 1.0 1 0.0 3 0.0 0.0"
)

# Matches any timestamp-starting soil data line we previously wrote
OLD_PAT = re.compile(
    r"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}) 0\.50 280\.0 .*$",
    re.MULTILINE
)

fixed = 0
for dom in ("d01", "d02", "d03", "d04"):
    pattern = os.path.join(BASE, "current_snow", dom, "*.sno")
    for path in sorted(glob.glob(pattern)):
        with open(path) as f:
            txt = f.read()

        m = OLD_PAT.search(txt)
        if not m:
            continue  # already fixed or different format

        ts = m.group(1)
        new_row = SOIL_FMT.format(ts=ts)
        txt = OLD_PAT.sub(new_row, txt)

        with open(path, "w") as f:
            f.write(txt)
        fixed += 1

print(f"Fixed {fixed} SNO files.")
