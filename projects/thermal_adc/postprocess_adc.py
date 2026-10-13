#!/usr/bin/env python3
"""Static metrics (DNL/INL/missing codes/monotonic) from an ngspice wrdata file.

Input : bit_data.txt written by ngspice `wrdata` with `set wr_vecnames` and `set wr_singlescale`
        columns: time D0..D7 vin_diff dac_clk   (course part_4_SAR_ADC convention)
Method: sample the output word at each rising edge of dac_clk (one conversion per edge),
        pair it with vin_diff at that instant, bin by code, take the mean input per code,
        then end-point INL / DNL in LSB.  A slow ramp input is expected.
Exit  : 0 = PASS, 1 = FAIL, 2 = could not evaluate.  Prints one `RESULT:` line.
"""
import argparse, sys
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("data")
ap.add_argument("--bits", default="D0,D1,D2,D3,D4,D5,D6,D7",
                help="column names MSB first (course README says D0 is the MSB: confirm with a known code)")
ap.add_argument("--fs", type=float, default=1.2, help="differential full scale in volts")
ap.add_argument("--thresh", type=float, default=0.6)
ap.add_argument("--max-dnl", type=float, default=0.75)
ap.add_argument("--max-inl", type=float, default=1.0)
a = ap.parse_args()

try:
    with open(a.data) as f:
        names = f.readline().split()
    raw = np.loadtxt(a.data, skiprows=1)
    col = {n: raw[:, i] for i, n in enumerate(names)}
    bits = a.bits.split(",")
    clk, vin = col["dac_clk"], col["vin_diff"]
except Exception as e:
    print(f"RESULT: ERROR cannot read data ({e})"); sys.exit(2)

edges = np.where((clk[:-1] <= a.thresh) & (clk[1:] > a.thresh))[0] + 1
if len(edges) < 64:
    print(f"RESULT: ERROR only {len(edges)} conversions; need a ramp with >= 64"); sys.exit(2)

n = len(bits)
code = sum(((col[b][edges] > a.thresh).astype(int)) << (n - 1 - i) for i, b in enumerate(bits))
v = vin[edges]
lsb = a.fs / 2**n
seen = np.unique(code)
missing = [c for c in range(int(seen.min()), int(seen.max()) + 1) if c not in set(seen)]
mono = bool(np.all(np.diff(code[np.argsort(v)]) >= 0))

# transfer curve: mean input per code, end-point INL, DNL from code widths
mean_v = np.array([v[code == c].mean() for c in seen])
fit = np.polyfit(seen, mean_v, 1)
ideal_step = fit[0]
inl = (mean_v - np.polyval(fit, seen)) / ideal_step
dnl = np.diff(mean_v) / ideal_step - 1 if len(seen) > 1 else np.array([0.0])
max_inl, max_dnl = float(np.abs(inl).max()), float(np.abs(dnl).max())

ok = (not missing) and mono and max_dnl <= a.max_dnl and max_inl <= a.max_inl
print(f"conversions={len(edges)} codes_seen={len(seen)} range={seen.min()}..{seen.max()} "
      f"step={ideal_step*1e3:.3f} mV (ideal LSB {lsb*1e3:.3f} mV)")
print(f"missing_codes={len(missing)} monotonic={mono} max|DNL|={max_dnl:.2f} LSB max|INL|={max_inl:.2f} LSB")
if missing: print("missing:", missing[:20])
print(f"RESULT: {'PASS' if ok else 'FAIL'} DNL={max_dnl:.2f} INL={max_inl:.2f} missing={len(missing)} mono={mono}")
sys.exit(0 if ok else 1)
