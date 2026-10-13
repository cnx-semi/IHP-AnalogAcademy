#!/bin/bash
# The loop's judge.  Usage: check_adc.sh <testbench.sch> [temp_C ...]
#   e.g.  check_adc.sh projects/thermal_adc/tb_thermal_adc.sch -40 27 125
# Stages per temperature:  1) xschem netlist  2) ngspice batch  3) postprocess_adc.py
# The testbench must `wrdata bit_data.txt D0..D7 vin_diff dac_clk` (see SPEC.md / course part_4).
# If the testbench folder holds sar_logic.v it is compiled to simulations/sar_logic.so first.
# Runs in a scratch copy under projects/thermal_adc/out/ ; never writes into modules/ or the PDK.
# Final line:  CHECK: PASS | FAIL | ERROR   (plus the first failing stage).
. /opt/tools/analog/env.sh
case ":$PATH:" in *":/opt/tools/bin:"*) ;; *) export PATH=$PATH:/opt/tools/bin ;; esac   # verilator for vlnggen
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TB=$(readlink -f "$1"); shift
TEMPS=${*:-27}
[ -f "$TB" ] || { echo "CHECK: ERROR testbench not found: $TB"; exit 2; }
SRC=$(dirname "$TB"); NAME=$(basename "$TB" .sch)
TIMEOUT=${SIM_TIMEOUT:-1800}
rc=0
for T in $TEMPS; do
  O=$ROOT/projects/thermal_adc/out/${NAME}_T${T}; rm -rf "$O"; mkdir -p "$O"
  cp -r "$SRC"/. "$O"/ 2>/dev/null; rm -rf "$O/out"
  cp "$PDK_ROOT/$PDK/libs.tech/ngspice/.spiceinit" "$O/.spiceinit"
  cd "$O" || exit 2
  # mixed-signal co-sim: the SAR logic is Verilog, ngspice loads it as sar_logic.so (course part_2)
  if [ -f "$SRC/sar_logic.v" ]; then
    mkdir -p simulations
    ( ngspice vlnggen "$SRC/sar_logic.v" > vlnggen.log 2>&1; cp -f sar_logic.so simulations/ 2>/dev/null; cp -f "$SRC/sar_logic.so" simulations/ 2>/dev/null )
    [ -s simulations/sar_logic.so ] || { echo "CHECK: ERROR vlnggen produced no sar_logic.so (see $O/vlnggen.log)"; exit 2; }
  fi
  echo "== T=${T}C  stage 1: netlist"
  xschem -n -s -q --no_x --rcfile xschemrc --netlist_path "$O" "$NAME.sch" > xschem.log 2>&1
  [ -s "$NAME.spice" ] || { echo "CHECK: ERROR netlist failed (see $O/xschem.log)"; tail -5 xschem.log; exit 2; }
  sed -i -E "s/^(\.param temp *= *)[-0-9.]+/\1${T}/I; s/^(\.temp +)[-0-9.]+/\1${T}/I" "$NAME.spice"
  echo "== T=${T}C  stage 2: ngspice (timeout ${TIMEOUT}s)"
  timeout "$TIMEOUT" ngspice -b "$NAME.spice" > ngspice.log 2>&1
  [ -s bit_data.txt ] || { echo "CHECK: ERROR no bit_data.txt (sim failed/timeout, see $O/ngspice.log)"; grep -iE "error|fatal" ngspice.log | head -5; exit 2; }
  echo "== T=${T}C  stage 3: metrics"
  python -I "$ROOT/projects/thermal_adc/postprocess_adc.py" bit_data.txt || rc=1
done
[ $rc -eq 0 ] && echo "CHECK: PASS" || echo "CHECK: FAIL"
exit $rc
