---
description: Run the builder -> verifier -> reviewer loop on the thermal-sensing ADC (Pattern A orchestrator)
argument-hint: "[testbench.sch] [max_rounds]"
---
You are the CONDUCTOR of a loop that designs the slow thermal-sensing SAR ADC in
`projects/thermal_adc/`. Arguments: `$ARGUMENTS`  (defaults: testbench `projects/thermal_adc/tb_thermal_adc.sch`, 8 rounds).

You coordinate; you do not edit design files yourself. Subagents do not talk to each other:
YOU pass information between them, and `projects/thermal_adc/PROGRESS.md` is the shared memory.

Goal: `check_adc.sh <testbench> -40 27 125` prints `CHECK: PASS` and the reviewer returns APPROVE.

Round 0 (once): read `SPEC.md` and `PROGRESS.md`. If the testbench does not exist yet, call
`adc-builder` to create it by copying `modules/module_3_8_bit_SAR_ADC/part_4_SAR_ADC/SAR_ADC_tb.sch`
and its co-sim pieces into `projects/thermal_adc/`, with a slow ramp and the `wrdata` line.

Each round (max rounds from arguments):
1. Call `adc-verifier` with the testbench path. Quick check (27 C only) while iterating, full
   -40/27/125 once the quick check passes.
2. VERDICT PASS on the full run -> go to step 4.
3. VERDICT FAIL or ERROR -> call `adc-builder` with: the verbatim FIRST FAILURE and EVIDENCE,
   a ONE-change instruction, and the last 5 lines of PROGRESS.md. Then next round.
4. Call `adc-reviewer`. APPROVE -> stop, success. REJECT -> pass its REASONS to `adc-builder`, next round.

Stop rules (whichever comes first):
- success (full PASS + APPROVE)
- max rounds reached
- the same FIRST FAILURE text 3 rounds in a row (no progress): stop, do not try a 4th time
- two ERRORs in a row from the same stage: it is a tooling problem, stop and report

Final report (always): outcome, rounds used, final metrics at each temperature, what changed
(from PROGRESS.md), remaining risks from reviewer NOTES, and the exact next command to continue.
