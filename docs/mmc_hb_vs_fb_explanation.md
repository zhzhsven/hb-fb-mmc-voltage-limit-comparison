# Technical explanation: 10 kV HB-MMC versus FB-MMC

## Scope

This repository compares switching-level three-phase HB and FB modular
multilevel converters with a common 10 kV DC link. Each converter contains six
arms and ten individually switched submodules per arm. Load phase voltage is
measured from each phase terminal to the floating load star point; terminal
voltage relative to the DC midpoint is logged separately.

## Phase-leg equations

Ignoring arm-reactor drop for the reference derivation,

\[
v_{phase}=\frac{v_l-v_u}{2},\qquad
v_{u,ref}=\frac{V_{dc}}{2}-v_{phase,ref},\qquad
v_{l,ref}=\frac{V_{dc}}{2}+v_{phase,ref}.
\]

The arm-voltage difference creates AC voltage. Arm-voltage sum and the arm
reactors govern circulating current and stored capacitor energy.

## Installed arm voltage

The HB design uses `Vc_ref_HB = Vdc/N = 1 kV`. A half-bridge cell produces only
0 or +Vc, so an HB arm spans 0 to +10 kV. Nonnegative upper and lower arm
references require approximately `abs(v_phase) <= Vdc/2 = 5 kV`.

The FB design uses `Vc_ref_FB = 1.5 kV`, giving an installed range of -15 to
+15 kV. A 7 kV phase peak requires -2 kV in one arm and +12 kV in the other.
Both are feasible with the 15 kV installed arm voltage. An FB topology with
only 1 kV per cell would provide 10 kV positive arm voltage and would remain
insufficient despite its negative-voltage capability.

## Switching states and conventions

Positive arm current flows from submodule port P to N. Upper current is
positive from DC+ toward the phase terminal; lower current is positive from
the phase terminal toward DC-. Thus

\[
i_{phase}=i_u-i_l,\qquad i_{circ}=(i_u+i_l)/2.
\]

The capacitor-current convention is

\[
i_{cap}=s i_{arm},\qquad s\in\{-1,0,+1\}.
\]

HB states:

| State | s | Upper IGBT | Lower IGBT | Cell voltage |
|---|---:|---:|---:|---:|
| Bypass | 0 | on | off | 0 |
| Positive insertion | +1 | off | on | +Vc |

FB states use upper-left, lower-left, upper-right, lower-right devices:

| State | s | UL | LL | UR | LR | Cell voltage |
|---|---:|---:|---:|---:|---:|---:|
| Positive | +1 | on | off | off | on | +Vc |
| Bypass | 0 | off | on | off | on | 0 |
| Negative | -1 | off | on | on | off | -Vc |

Each ideal-switching IGBT and explicit antiparallel diode uses a 1.5 V
threshold drop and 5 mOhm on resistance. The electrical step and commutation
dead time are 5 microseconds.

## Nearest-level modulation and inserted counts

Every 50 microseconds, each arm uses its measured mean capacitor voltage:

\[
k_{HB}=\operatorname{limit}(\operatorname{round}(v_{arm,ref}/\bar V_c),0,N),
\]

\[
k_{FB}=\operatorname{limit}(\operatorname{round}(v_{arm,ref}/\bar V_c),-N,N).
\]

For HB, `k_u + k_l` remains near N=10. Small deviations arise from integer
rounding, arm drop, dead time, and bounded common-mode control.

For FB, the counts are signed. `abs(k)` is the number of active inserted cells,
while `sign(k)` selects positive or negative orientation. The relevant sum is

\[
k_u+k_l\approx V_{dc}/V_{c,FB}=6.67,
\]

not `abs(k_u)+abs(k_l)=N`. In the 7 kV result, individual arms reach -2 while
the opposite arm reaches approximately +8.

## Capacitor balancing and control

If `s*i_arm > 0`, an inserted capacitor is charging and the lowest-voltage
cells are selected. If `s*i_arm < 0`, the highest-voltage cells are selected
for discharge. A rotating tie break and within-arm hysteresis reduce chatter.

The controller also includes load-power feedforward, average capacitor-energy
PI control, circulating-current PI control, upper/lower energy trim,
anti-windup, output limits, and soft start. The FB model uses measured
three-phase load voltage in a slow synchronous fundamental-amplitude loop to
compensate the real dead-time voltage error through actual NLM switching states.

## Results and verification

The six 220 ms cases cover 4, 5, and 7 kV phase-voltage commands. HB visibly
clips the 7 kV command at +/-5 kV. FB produces approximately 6.77 kV peak in
the 220 ms case and approximately 7.00 kV peak in the independent 1.5 s run.
FB uses up to two negative cells and produces state-derived negative arm
voltage near -3 kV.

The 1.5 s final 0.3 s window has approximately 2.06% THD. Capacitor mean stays
near 1.50 kV, full-run capacitor voltage remains between about 1.459 and
1.559 kV, and arm/circulating currents remain bounded. Narrow commutation
spikes and short instantaneous power dips remain visible and are not filtered
from the figures.

Detailed numerical values are in:

- `results/mmc_comparison_metrics.csv`
- `results/mmc_comparison_report.txt`
- `results/submodule_verification.txt`
- `results/FB_7kV_long_1p5s_report.txt`

## Limitations

The model omits semiconductor thermal dynamics, detailed switching loss,
capacitor ESR/ESL, precharge, protection, faults, and insulation coordination.
It is intended to demonstrate MMC voltage capability, modulation, and energy
balancing—not to serve as a hardware-ready converter design.
