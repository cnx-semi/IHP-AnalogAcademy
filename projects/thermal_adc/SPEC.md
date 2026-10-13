# Thermal-sensing ADC: spec (the loop's definition of "done")

Slow SAR ADC that digitizes an on-die temperature sensor voltage (PTAT / bandgap-temp node,
see `modules/module_1_bandgap_reference`). Reuses the course SAR blocks in
`modules/module_3_8_bit_SAR_ADC` (comparator, SAR logic, C-DAC, switches). Speed is irrelevant;
accuracy and temperature robustness matter.

> Values marked (assumed) are starting points chosen for a thermal sensor. Edit them before
> the first loop run; the verifier reads the numbers from `check_adc.sh` args, not from prose.

| Item | Target | Status |
|---|---|---|
| Resolution | 8 bit (~0.65 C/LSB over -40..125 C) | (assumed) |
| Input | differential, full scale = `FS_V` below | (assumed, confirm vs sensor swing) |
| Conversion rate | >= 1 kS/s (sensor changes in ms; slower than the course's 12.7 kHz demo is fine) | (assumed) |
| Supply | 1.2 V | course default |
| Static: DNL | max abs <= 0.75 LSB | (assumed) |
| Static: INL | max abs <= 1.0 LSB (end-point fit) | (assumed) |
| Codes | no missing codes, monotonic | required |
| Temperature | all of the above at -40, 27, 125 C | required (it is a thermal sensor) |
| Power | report only (no pass/fail in v1) | informational |

FS_V (differential full scale, volts): 1.2   (assumed: course testbench drives +/-0.6 V diff)

## Scope rules for agents
- Edit only inside `projects/thermal_adc/`.
- `modules/**`, `/opt/tools/**`, and the PDK are READ-ONLY. Copy a course schematic into
  `projects/thermal_adc/` and change the copy.
- `check_adc.sh` and `postprocess_adc.py` are the judge: builder must not edit them.
