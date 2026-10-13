# Loop engineering with Claude Code: Pattern A (orchestrator + subagents)

How to make several Claude agents work together in a loop, using the thermal-sensing ADC in
`projects/thermal_adc/` as the worked example. Written 2026-10-13 so the method can be reused
for other blocks (bandgap, PA, PLL ...).

A *loop* here means: **act -> check with an objective signal -> decide -> repeat**, with
stop rules, so Claude can iterate without you in the middle.

```
                    +--------------------------+
                    |  conductor (main session)|   /adc-loop
                    +------------+-------------+
          instruct one change |   ^ result      ^ verdict
                              v   |             |
   +----------------+   +-----------------+   +------------------+
   | adc-builder    |   | adc-verifier    |   | adc-reviewer     |
   | edits design   |   | runs the judge  |   | audits the diff  |
   +--------+-------+   +--------+--------+   +---------+--------+
            |                    |                      |
            +---- shared memory: projects/thermal_adc/PROGRESS.md ----+
                         judge: projects/thermal_adc/check_adc.sh
```

The three roles are separate on purpose: **the agent that changes the design never grades it**.

---

## Step 1. Define each agent as a file

Agents are Markdown files with YAML frontmatter. Project-level agents go in `.claude/agents/`
(user-level, all projects: `~/.claude/agents/`). Each gets one narrow job and only the tools it needs.

| File | Job | Tools | Model | Why |
|---|---|---|---|---|
| `.claude/agents/adc-builder.md` | make ONE change per call | Read, Edit, Write, Bash, Grep, Glob | sonnet | needs to edit; mid-tier is enough |
| `.claude/agents/adc-verifier.md` | run the judge, report verbatim | Read, Bash, Grep (no Edit/Write) | haiku | mechanical, cheap |
| `.claude/agents/adc-reviewer.md` | find ways the pass is fake | Read, Grep, Bash, Glob (no Edit/Write) | inherits | judgment, so stronger model |

Frontmatter fields used: `name` (what you call it), `description` (when to use it; the conductor
reads this to route work), `tools` (allow-list), `model`. Everything below the frontmatter is the
agent's system prompt.

What makes an agent prompt good:
- **Scope in writing:** where it may edit, what is read-only (here `modules/**`, `/opt/tools/**`, the PDK).
- **A forbidden list that blocks cheating:** the builder may not edit the judge or the spec.
- **A fixed return format:** the conductor parses it; the verifier must include verbatim numbers.
- **One change per call:** several simultaneous edits make the next check unreadable.

Restart the session (or reopen `/agents`) after adding files so Claude Code picks them up.

## Step 2. Write the conductor prompt

The conductor is the main session. It calls the subagents by name, passes information between
them (subagents never talk to each other), and applies the stop rules. Saved as a slash command:
`.claude/commands/adc-loop.md`, so the whole procedure is one reusable command.

Skeleton (full text in that file):

```
Goal:   check_adc.sh <tb> -40 27 125 prints CHECK: PASS  AND  reviewer returns APPROVE
Round:  1 verifier -> 2 PASS? -> 4 reviewer
                       FAIL/ERROR? -> 3 builder (verbatim failure + ONE change) -> next round
Stop:   success | max rounds | same FIRST FAILURE 3x | same ERROR stage 2x
Report: outcome, rounds, metrics per temperature, changes, risks, next command
```

The four ingredients every conductor needs (from the loop-engineering checklist):

| Ingredient | In this project |
|---|---|
| Goal | SPEC.md table: 8 bit, DNL <= 0.75, INL <= 1.0 LSB, no missing codes, monotonic, at -40/27/125 C |
| Signal | `check_adc.sh`: xschem netlist -> ngspice batch -> `postprocess_adc.py` |
| State | `PROGRESS.md` (one line per round) + git commits |
| Stop rules | in the conductor prompt, not left to the model's mood |

### The judge matters most

`projects/thermal_adc/check_adc.sh` + `postprocess_adc.py` are deterministic code:

1. **netlist:** `xschem -n -s -q --no_x --rcfile xschemrc` on the testbench
2. **co-sim:** if `sar_logic.v` sits next to the testbench, `ngspice vlnggen` builds `sar_logic.so`
3. **simulate:** `ngspice -b`, per temperature (the `.param temp` / `.temp` line is rewritten)
4. **metrics:** sample the output word at each `dac_clk` rising edge, bin by code, then DNL / INL (end-point) / missing codes / monotonic

It was validated on synthetic data (an ideal 8-bit ramp passes with DNL 0.04 / INL 0.05 LSB; a ramp
with code 100 removed fails) and on the course's own testbenches (stages 1-2 run). It has **not**
yet been run on a finished thermal ADC testbench because that testbench does not exist until round 0.

## Step 3. Run it

```bash
cd /home/attapon/cnx-semi/IHP-AnalogAcademy
git add projects/thermal_adc .claude && git commit -m "thermal ADC: baseline judge + agents"   # reviewer diffs against this
claude                                         # new session so the agents load
/adc-loop projects/thermal_adc/tb_thermal_adc.sch 8
```

Or unattended, with the loop in your own script so the model can never skip a step
(Pattern B, for overnight runs):

```bash
claude -p "/adc-loop projects/thermal_adc/tb_thermal_adc.sch 8" --permission-mode acceptEdits
```

Before the first real run:
1. Read `projects/thermal_adc/SPEC.md` and confirm the **(assumed)** numbers, especially
   `FS_V` (full scale vs. the real sensor swing).
2. Run the judge once by hand on a known-good testbench so you trust the signal before automating.
3. Use a git worktree or branch for the builder if you want to throw the attempt away
   (the conductor can call the builder with worktree isolation).

## Rules of thumb

- **Judge in code, not opinion.** If "pass" depends on a model saying so, the loop will drift.
- **Separate do from judge.** Builder / verifier / reviewer are different agents with different tools.
- **Read-only judges.** Verifier and reviewer have no Edit/Write tool, so they cannot "fix" a failure into a pass.
- **One change per round**, verbatim failure in, short return out.
- **State outside the context:** `PROGRESS.md` and commits survive context summarization.
- **Stop rules are mandatory:** success, round cap, no-progress (same failure 3x), tooling-error cap.
- **Watch for gaming:** the reviewer exists for weakened thresholds, narrowed temperature sweeps,
  narrow ramps that hide missing codes, ideal elements standing in for real ones.
- **Cheap models for mechanical roles**, stronger ones for builder-quality edits and review.
- **Harder guarantees:** put the check in a Stop hook (`/update-config`) or script the loop (Pattern B/C).

## Known gotchas in this repo (found while building the example)

- The course SAR testbench needs `adc_bridge1.sym` / `dac_bridge1.sym` (from
  `part_2_digital_comps/algorithm/xschem/`) and a Verilator-built `sar_logic.so`
  (`ngspice vlnggen sar_logic.v`, needs `/opt/tools/bin` on PATH). Without them ngspice reports
  `adc_bridge1 IS MISSING` and `no such vector D0`. The judge builds the `.so` for you.
- `*.raw`, `*.txt`, `*.log`, `*.so` are git-ignored by the repo's `.gitignore`.
- The course notebook `part_4_SAR_ADC/scripting/plot_adc.ipynb` lists the bit columns as
  `['D0',...,'D6','D0']` (last entry repeats `D0`; looks like it should be `D7`) and the README says
  D0 is the MSB. `postprocess_adc.py` takes `--bits` MSB-first, default `D0..D7`; confirm with one
  known input code before trusting INL numbers.
- Toolchain: `source /opt/tools/analog/env.sh` (own shell, not the Croc digital flow).
- `modules/**`, `/opt/tools/**` and the PDK are read-only for the loop.

## Files in this example

| Path | Role |
|---|---|
| `.claude/agents/adc-builder.md` | builder agent |
| `.claude/agents/adc-verifier.md` | verifier agent |
| `.claude/agents/adc-reviewer.md` | reviewer agent |
| `.claude/commands/adc-loop.md` | conductor (`/adc-loop`) |
| `projects/thermal_adc/SPEC.md` | goal and scope rules |
| `projects/thermal_adc/check_adc.sh` | judge, stages 1-3 per temperature |
| `projects/thermal_adc/postprocess_adc.py` | DNL/INL/missing-code metrics |
| `projects/thermal_adc/PROGRESS.md` | shared loop memory |

## Adapting to another block

1. Write the SPEC table (numbers, temperatures/corners, scope).
2. Write the judge so it prints one `PASS`/`FAIL`/`ERROR` line; test it on a known-good and a known-bad case.
3. Copy the three agent files, change the paths, the source blocks and the reviewer's reject list.
4. Copy `/adc-loop`, change the goal and the stop numbers.
5. Run once by hand, then run the loop with a small round cap (3-5).
