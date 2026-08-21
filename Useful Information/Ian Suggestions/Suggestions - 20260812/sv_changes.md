# astrob_audio.sv — change log

**Date:** 2026-08-11
**Base:** revision 2026-08-09b (V generator added)
**Scope:** P0 items from `astroblaster_sound_backlog.md`
**Verification:** compiles clean under `iverilog -g2012`; behavioural testbench
(`tb_astrob.sv`) run against both the original and the edited file

---

## Summary

| Backlog | Item | Outcome |
|---|---|---|
| SND-001 | Master mixer gain ratios | **Fixed** — weighted mixer replaces flat sum |
| SND-002 | Counter-DAC waveform weights | **Partially fixed** — INV2 corrected; laser voices still unbuilt |
| SND-003 | Noise-voice low-pass shaping | **Not fixed** — voices unbuilt; see note |
| SND-004 | Attack-rate ladder (node V) | **Verified correct** — no change needed |

Two additional findings are logged at the end rather than acted on, because
they contradict board captures I don't have access to.

---

## Changes made

### 1. Weighted mixer replaces the flat sum — SND-001

**Was:**

```systemverilog
wire signed [17:0] voice_sum = inv1_out + inv2_out + inv3_out + inv4_out;
```

**Now:** eleven explicit Q14 weights derived from U7's summing resistors, with
`R144 = 22k` as the feedback, normalised so EXPLOSIONS = unity.

| Voice | R | Value | Rel. gain | Q14 | dB vs EXPL |
|---|---|---|---|---|---|
| Explosions | R122 | 4.7k | 1.000000 | 16384 | 0.0 |
| Asteroids | R121 | 10k | 0.470000 | 7700 | −6.6 |
| Sonar | R120 | 220k | 0.021364 | 350 | −33.4 |
| Bonus | R118 | 470k | 0.010000 | 164 | −40.0 |
| Refill | R119 | 470k | 0.010000 | 164 | −40.0 |
| Laser-1 | R102 | 470k | 0.010000 | 164 | −40.0 |
| Laser-2 | R103 | 1M | 0.004700 | 77 | −46.6 |
| Invader-1…4 | R98–R101 | 1M | 0.004700 | 77 | −46.6 |

Integer rounding error is under 0.1% on every entry.

The flat sum was only harmless by accident: the four voices built so far all
share the same 1M resistor. The moment EXPLOSIONS (4.7k) or ASTEROIDS (10k)
lands, a flat sum is wrong by 40+ dB in the direction that buries them under
the march.

The seven unported voices are stubbed as `wire signed [15:0] xxx_out = 0` and
already wired into the mixer at their correct weights, so implementing one is
a single-line change and it arrives at the right level immediately.

**One thing to watch:** `MIX_MAKEUP_LOG2` is set to **7** and is marked
temporary. Only the −46.6 dB voices exist right now, so unity scaling would
leave the output near-silent. Set it to **0** the moment EXPLOSIONS or
ASTEROIDS is implemented — one full-scale explosion at makeup 7 wants
`6000 × 16384 >> 7 = 768000`, which is 23× over the clamp.

**Caveat carried into the code comments:** these are the *resistor* gains.
They are correct only if each voice arrives at `VOICE_FS` representing the
same source amplitude. That holds for the four invaders and should hold for
the lasers (all CMOS/555 rail swings). It does **not** automatically hold for
Explosions/Asteroids/Sonar, which reach their summing resistors from op-amp
stages at a fraction of a rail. When those land, measure real Vpp at the
summing resistor and fold the ratio into that voice's full-scale — don't edit
the weights.

---

### 2. Common voice full-scale — SND-001

Added `localparam signed [15:0] VOICE_FS = 16'sd6000`. INV1, INV3 and INV4 now
emit `±VOICE_FS` instead of hard-coded `±6000`.

INV1 keeps its asymmetry (`+VOICE_FS / −VOICE_FS/3`) — that's a waveform
property that nulls DC at mean duty 0.25, not a level, and it's now labelled as
such so a future edit doesn't "fix" it.

---

### 3. INV2 normalised from ±10500 to ±VOICE_FS — SND-001

INV2 was leaving its block at ±10500 while INV1/3/4 left at ±6000 — 4.9 dB hot
against three voices that share an identical 1M summing resistor and therefore
must arrive equal.

Folded into the DAC weights below rather than added as a separate scaling
stage, so it costs nothing.

---

### 4. INV2 DAC weights corrected to true conductances — SND-002

**Was:** idealised binary `1 : 2 : 4 : 8`.
**Now:** the actual tap conductances.

| Tap | Resistor | 1/R ratio | Old | New constant |
|---|---|---|---|---|
| Q1 (÷2) | R48 82k | 1.0000 | 1 | 399 |
| Q2 (÷4) | R49 39k | 2.1026 | 2 | 839 |
| Q3 (÷8) | R50 22k | 3.7273 | 4 | 1488 |
| Q4 (÷16) | R47 10k | 8.2000 | 8 | 3274 |

Q3 was 7.3% too heavy and Q4 2.5% too light. Constants are pre-scaled so the
four sum to exactly 6000, which lands the normalisation for free with no
runtime divide. Ratio error vs. true conductance is under 0.1% per tap.

Effect on the 16-step staircase: step heights shift by up to **3.77% of full
scale**, largest at codes 4–5 and 10–11. The endpoints and the midpoint are
unchanged, so the fundamental is unaffected — this moves harmonic content, not
pitch.

The same correction will be needed for the laser voices. Their tap set is
82k/39k/22k/10k/10k on **Q1, Q2, Q3, Q4, Q6** — note Q5 is skipped on the
board, so ÷32 must be absent from the sum. This is now noted in the code at
the INV2 block.

---

### 5. Warp polarity parameterised — SND-004 follow-on

The file carried an open question: the schematic says warp raises pitch, the
board captures say it drops (104.3 → 90.3 Hz).

I solved the warp path independently. U16 pin 5 sits at
`12 × (1/4.7k) / ((1/4.7k) + (1/10k)) = 8.163 V` with the 7406 off, and
`6.186 V` when R164 pulls it low — a **1.98 V drop**, so V drops and pitch
rises. That lands on the schematic side.

Worth noting: the suspect package on the capture board, **U31, is the warp
inverter**. A warp-specific fault is a more economical explanation than a
wrong schematic. That's circumstantial, not proof.

So I did **not** change the behaviour. Default is still capture-derived and
nothing audible has moved. Instead:

```systemverilog
localparam WARP_SCHEMATIC   = 1'b0;      // 0 = capture, 1 = schematic
localparam [12:0] WARP_RATIO_Q12 = 13'd2927;   // 0.7147
```

Under branch 1 the warp tables are bypassed and the normal tables are scaled by
one constant: the −1.977 V pin-5 drop referred through the stage's
non-inverting gain (1 + 0.671) is a −3.304 V shift on V, i.e. 7.570 → 4.266 at
step 0, which the 555 CV model turns into a half-period ratio of 0.7147
(pitch +39.9%).

The A/B test on a working board is now a single-bit change.

---

### 6. Header revision block updated

---

## Verified, not changed

### SND-004 — the V generator is correct

I re-derived the attack-rate staircase from the schematic without reference to
the existing ROM, and it agrees.

Solving R152–R161 straight off sheet 7 (diode-isolated CD4017 outputs into
R178 22k) gives a **raw** ladder node of 1.77 V at step 0 rising to 5.70 V at
step 9 — ascending, which initially looks like it contradicts the file's
descending 7.57 → 4.93 V. It doesn't: running the raw ladder through an
inverting U16 stage of gain −0.671 with a +8.755 V offset reproduces both
endpoints **to within 0.02 V**.

Feeding that through a standard 555 CV model and comparing against `rom_i2`:

| step | solved V | model (norm.) | ROM (norm.) | error |
|---|---|---|---|---|
| 0 | 7.570 | 1.0000 | 1.0000 | 0.00% |
| 1 | 7.137 | 0.9487 | 0.9661 | −1.81% |
| 2 | 6.752 | 0.9077 | 0.9311 | −2.51% |
| 3 | 6.597 | 0.8925 | 0.9174 | −2.72% |
| 4 | 6.316 | 0.8659 | 0.8920 | −2.92% |
| 5 | 5.996 | 0.8378 | 0.8622 | −2.82% |
| 6 | 5.695 | 0.8132 | 0.8311 | −2.16% |
| 7 | 5.320 | 0.7846 | 0.7900 | −0.69% |
| 8 | 5.096 | 0.7685 | 0.7642 | +0.56% |
| 9 | 4.930 | 0.7570 | 0.7441 | +1.74% |

Two independent derivations landing within ±3% at every step is confirmation.
**The `#unverified` flag on the staircase can come off.** The residual bow is
within the difference between CV models and isn't worth chasing without a
board capture.

---

## Findings logged, not acted on

### F-1 — INV4's DAC taps read as bit-reversed on the schematic

The code models INV4 as a monotonic 16-step frequency ramp (682 → 890 Hz),
linearly interpolated from a mod-16 ring counter. That assumes the DAC's MSB
sits on the **slowest** tap, as it does on INV2.

Reading sheet 8, U28's ladder is:

| Tap | INV2 (U12) | INV4 (U28) |
|---|---|---|
| Q1 (÷2) | R48 82k | **R31 10k** |
| Q2 (÷4) | R49 39k | R32 22k |
| Q3 (÷8) | R50 22k | R33 39k |
| Q4 (÷16) | R47 10k | **R30 82k** |

INV4's heaviest weight is on Q1, the **fastest** tap — the reverse of INV2. If
that's right, the U38 CV isn't a slow 4.3 Hz ramp at all; it's a ~34 Hz warble
with slow fine structure, which is a completely different sound.

I have a 300 dpi scan; you have `astrob_invader4.wav` off the board showing a
sweep. **The capture wins** — I haven't touched the model. But the two can't
both be right, so it's worth one look at `nl_astrob.cpp`'s U28 net names to
settle which of us misread. If the netlist agrees with the scan, the reference
render may be showing the mod-16 wrap rate rather than a genuine ramp.

### F-2 — my backlog's port map was wrong; the file's is right

Backlog item SND-013 guessed U32 D6 → node W and D7 → WARP as separate bits,
and flagged the U32 half as unverified. The file has W and I_WARP as the raw
and inverted copies of the **same** bit 7, with bit 6 as REFILL, sourced from
netlist ALIAS lines.

Netlist-verified beats scan-read. The backlog is wrong, not the SV.
(The $3F/U33 half matched exactly, and 076/077 octal = $3E/$3F, so the two
documents agree on ports.)

---

## Not addressed — voices still unbuilt

SND-002 (lasers) and SND-003 (explosions, asteroids) are backlog P0 because
they're audible gaps, but they're **new voice work, not fixes** — there's no
existing code to correct. I've deliberately not written them speculatively:
your process derives each voice from `nl_astrob.cpp` and validates it against
board captures, and 400 lines of schematic-estimated RTL would cut across that
and need re-deriving anyway.

What's in place for when you write them: correct mixer weights, the stub wires,
the Q5-skip note on the laser tap set, and these from the schematic solve —

- **MM5837**: 17-bit LFSR, taps 17 and 14, internal clock ~32–36 kHz and
  notoriously part-variable. One instance feeds *both* explosions and
  asteroids (split via R165 1M), so the noise is correlated when they overlap.
- **Explosions**: 2-pole low-pass, corners ≈34 Hz and ≈127 Hz, plus D27/D28
  back-to-back soft clipping at ≈±0.6 V.
- **Asteroids**: MFB low-pass, f₀ ≈ 103 Hz, Q ≈ 1.07, then R136 1k / C59 0.33 µF
  adds a pole at ≈482 Hz.
- **Short vs long explosion**: RC ratio ≈4.4:1 (R185 1M/C81 0.05 µF vs
  R170 2.2M/C82 0.1 µF), exponential decay, not linear.

---

## Test results

`tb_astrob.sv` — same testbench run against both files:

| Check | Original | Edited |
|---|---|---|
| Silent at power-up | PASS | PASS |
| Mix peaks | +20500 / −24500 | +10018 / −12032 |
| INV2 output range | ±10500 | ±6000 |
| V staircase advances | PASS | PASS |
| Mute silences output | PASS | PASS |

Output is ~6 dB quieter than before and now has 2.7× headroom to the clamp
rather than 1.3×. If that's too quiet on hardware, raise `MIX_MAKEUP_LOG2`
to 8 — but remember it has to come back to 0 when the loud voices land.

The testbench is included alongside the source; it's a smoke test for levels
and gating, not a spectral check.


---

# 2026-08-11b — Frequency audit against nl_astrob.cpp

**Trigger:** MAME netlist supplied; every frequency-setting constant compared.
**Verification:** both toolchains compile clean; 8 s/voice Verilator render;
per-cycle zero-crossing analysis.

## Confirmed correct by the netlist (no change)

- **Mixer weights** (SND-001 fix): R98–R122 values match line for line. MAME
  doesn't emulate the final amp (R144 is commented out) and sums passively —
  ratios are set by the input resistors either way, so the weights stand.
- **INV2 DAC conductances** (SND-002 fix): netlist line 1103–1107 ties
  Q1/Q2/Q3/Q4 → 82k/39k/22k/10k into a passive sum node. Exactly as corrected.
- **V ladder output values**: the netlist reveals R178 22k is the *feedback*
  of an inverting summing amp (line 943/949), not a load to ground as my
  backlog described. Solving the true topology: V = Vref − (Rf/Rq)(11.4 − Vref)
  with Vref = 8.163 V reproduces the file's 7.570/4.927 V **to three
  decimals**. Right values, now for the exactly right reason.
- **CD4017 pin→resistor pairing**: all ten diode/resistor pairs match.
- **OSC3**: MAME hard-codes it as CLOCK(OSC3, 15.3) driving U12's reset as a
  level — confirms both the 15.29 Hz constant and the hold-not-pulse model.
- **INV4 self-reset**: line 1122, U28.2 ← U28.5 (Q5) — mod-16 confirmed,
  closing that block's open question.
- **Warp topology**: I_WARP = U31.6, a real 7406 OC into R164 — the netlist
  implements the schematic polarity (warp → V down → pitch up). Note MAME is
  schematic-derived, so this confirms my solve of what the schematic says but
  cannot adjudicate schematic-vs-capture. Default branch still capture.

## Fixed

### 1. V-staircase ROMs were 3.0–3.8× too steep

The netlist routes V into each 555 through a 10k resistor (R87→U23.5,
R71→U13.5, R53→U17.5) into pin 5's internal divider — Thevenin ≈3.33k to 8 V.
Only ~¼ of V's swing reaches the CV pin: CV = (V + 24)/4. The ROMs had been
generated with V applied to pin 5 directly.

Step 0 anchors are untouched; every other step is now anchor × netlist-exact
period ratio. Total staircase pitch rise, before → after:

| Voice | Old (SV) | New (netlist) |
|---|---|---|
| INV1 rate | +93.0% | **+17.9%** |
| INV2 | +34.4% | **+9.1%** |
| INV3 | +34.4% | **+9.3%** |

The accelerando is much subtler than the old tables — if that sounds too
subtle in-game, the thing to re-examine is the CV model, not the ratios: both
derivations agree on the network now.

### 2. INV4 CV model replaced (closes F-1)

Netlist lines 1123–1127 settle it: heaviest weight on Q1 (10k), lightest on
Q4 (82k) — mirror-image of INV2 — **plus** R34 4.7k coupling V directly into
the same node, the strongest single conductance there, which the old model
lacked entirely.

The tone is therefore not a smooth 682→890 Hz ramp: it zigzags between ~596
and ~900 Hz, dominated by a ±2.0 V alternation at fosc/2 ≈ 34.4 Hz, repeating
at 68.7/16 = 4.29 Hz. The old model's own evidence supports this: the
scattered spot measurements it explained away (730/748/771 Hz) sit on the new
table's interior values (716/737/764/784) — they were samples of the zigzag.

Implemented as a 10-step × 16-code half-period ROM (netlist-absolute — the
old endpoints were an interpretation of ambiguous data, so there was no
capture anchor to preserve). Verified by per-cycle zero-crossing analysis:
all 16 table frequencies appear in the render, 26 of 27 measured clusters
within 10 Hz of a table entry (the stragglers are cycles straddling a code
change). **Flagged for ear check against real hardware** — this is the one
change that audibly alters a voice at step 0.

### 3. Warp schematic-branch constants recomputed

The previous single Q12 (2927, pitch +39.9%) had the same pin-5-divider
omission. Replaced with per-voice constants: INV1 +15.5%, INV2 +8.0%,
INV3 +8.2%, INV4 +7.4% (Q12 = 3545/3793/3787/3815, step-0 anchored).

Also extended to INV2 and INV4, which had no warp path at all — the netlist
says warp must reach all four voices via V. Capture branch (default)
unchanged: no isolated warp captures exist for those two.

**Known approximation, documented in-code:** the true warp shift grows with
vstep (stage gain 1+Rf/Rq rises as the ladder R falls; V hits ~1.0 V at
step 9 under warp). Constants are exact at step 0 only. If the schematic
branch is ever promoted to default, regenerate as full per-step warp tables.

## Absolute base frequencies — divergences noted, deliberately not changed

Netlist-nominal vs the SV's capture-anchored constants: INV1 ~88 vs 104.3 Hz,
INV3 ~101 vs 108.5 Hz, INV2 ~3170 vs 3117 Hz. The file's stated policy is
that board captures beat nominal component math (real 555s and 5% parts
drift), and the netlist — built from the same schematic — can't overrule a
capture. Anchors kept.

## Deliverables refreshed

WAV set re-rendered from the corrected RTL. INV1/2/3 are bit-identical in
character at step 0 (anchors unchanged, verified: 104.24/198.86/108.74 Hz);
`astrob_inv4.wav` now carries the zigzag.


---

# 2026-08-12 — Warp polarity resolved; schematic branch deleted

**Trigger:** hardware confirmation from the user — warp always lowers pitch /
slows; it never raises frequency.
**Verification:** all eight normal/warp voice renders bit-identical before and
after the deletion (pure dead-code removal).

## Resolution

The capture-derived warp behaviour (INV1 104.3→90.3 Hz, INV3 108.5→100.1 Hz,
INV2/INV4 unshifted) was correct all along and is now the sole behaviour. The
`WARP_SCHEMATIC` parameter, its four per-voice Q12 constants, and the warp
muxes added to INV2/INV4 on 2026-08-11 are removed, per the code's own
resolution instruction ("if pitch drops → leave it 0 and delete this note").

`astrob_warp_compare_SCHEMATIC.wav` is withdrawn from the deliverables — it
renders behaviour now known to be wrong. `astrob_warp_compare.wav` (the
default branch) stands as the reference.

## Why the schematic solve was wrong — a warning left in the code

Both my node solve and the MAME netlist topology genuinely do predict pitch
UP under warp (I_WARP pulls U16 pin 5 down through R164 → V drops → CV drops
→ 555s speed up). Hardware says down. The code now carries a prominent note
so the next person who re-derives this doesn't "fix" it back, with two
candidate reconciliations, both unproven:

- **Bit polarity.** Every other signal on this board is active-low. If warp
  is too, then W=1 is the *idle* state: I_WARP sits low during normal play,
  and warp *releases* the pin-5 pulldown — V rises, pitch falls. Same parts,
  opposite sense, matches hardware. If ever confirmed, it has a knock-on
  consequence flagged in the code: the baseline 7.57–4.93 V table would
  belong to the warp state, and normal-play V would sit lower.
- **The direct W paths dominate.** R57 (INV1) and R28 (INV3) inject W into
  the sweep integrators directly; the V-path analysis may simply be a red
  herring for what's audible.

Either way: down is ground truth. Do not reintroduce a pitch-up branch
without a board capture proving it.

## Unchanged

Default-branch behaviour, all frequency tables, mixer weights, and the
INV4 zigzag ROM. INV2/INV4 remain unshifted under warp — no isolated
captures exist for them, and the resolved rule gives no derivable shift
to apply.


---

# 2026-08-12b — Five new voices: lasers, explosions, asteroids, refill

**Trigger:** "add missing sounds e.g. laser and enemy laser."
**Sources:** nl_astrob.cpp exclusively — no board captures exist for any of
these five voices, so every constant here is netlist-nominal. **Flag all
five for ear check against real hardware**; the step-0 capture-anchor
policy that protects the invader voices does not yet protect these.

## LASER_1 / LASER_2 ($3F bits 0/1) — netlist lines 752–853

Per laser: CD4011 half-monostable (2.2 MΩ × 0.1 µF → 152 ms pulse) gates a
swept VCO into a CD4024 divider; five taps (Q1,Q2,Q3,Q4,Q6 — **Q5 skipped**)
sum through 82k/39k/22k/10k/10k, normalised to weights 258/543/962/2119/2118.
The sweep cap charges toward 12 V with τ 280 ms while the pulse is live and
is diode-dumped back to 0.6 V at pulse **end** — so a fast retrigger restarts
the pulse but *continues* the sweep from where it was, which is board-true
(the netlist's clipping-diode comment is about exactly this path). The VCO
half-period is MAME's own calibrated HLE quintic (VARCLOCK polynomials,
lines 779/831), baked into 64-entry ROMs indexed by sweep-cap voltage in
1/8 V steps, including the Q10/Q9 PNP follower (+0.65 V) and the ~8 V clamp
from the parked 555's pin-5 divider. Audible result: bright hiss-zap
falling as the VCO sweeps ~350k→13.5k Hz (L1) / ~500k→29k Hz (L2); L2 is
the ~2× brighter of the pair. Verified in sim: 152 ms active window,
monotonically falling zero-cross density, retrigger path exercised.

## SHORT/LONG EXPLOSIONS ($3F bits 2/3) — netlist lines 953–1010

Two one-shots share **one** storage cap (C80 4.7 µF) and one JFET noise VCA:
short = 35 ms pulse with fast attack (τ ≈ 22 ms, via R184 4.7k), long =
152 ms pulse with slower attack (τ ≈ 47 ms, via R183 10k); common decay
τ ≈ 150 ms. Then the U16 two-pole LPF: 47k/47k, C78 0.1µ feedback,
C76+C77 26.7n shunt → **f0 65.6 Hz, Q 0.97**, implemented as a fixed-point
Chamberlin SVF at the 60.4 kHz tick rate. D27/D28 are modelled as the
±VOICE_FS output clamp: a full short shot clips ~6% of its samples, a long
shot ~40% during sustain — that clipped grit is the intended D27/D28
character (SND-010); EXPL_GAIN_LOG2 (currently 2) is the tuning knob if
hardware says otherwise. Verified: short shot 253 ms above 20% envelope,
long 390 ms — durations distinct and matching RC theory; 25 dB/decade-ish
rolloff above f0.

## ASTEROIDS ($3E bit 4) — netlist lines 1014–1029

Level-gated (no one-shot): continuous filtered rumble while held. MFB LPF
33k/33k, 0.1µ/22n → f0 102.8 Hz Q 1.07 (SVF), then the R136/C59 pole at
482 Hz. A ~1 ms envelope slew stands in for the un-capacitored gate to
avoid a click the board's AC coupling would have softened.

## REFILL ($3E bit 6) — netlist lines 856–903

Resolves the backlog's open question #1: the CD4017 ladder feeds R16 10k
into Q7 (2N4403 emitter follower) whose emitter drives **both** 555 CV pins.
CV = ladder + 0.65 V = 6.54 → 4.55 V over steps Q0..Q9 — and since lower
CV makes a 555 run *faster*, the warble **rises** in pitch over the run
(the backlog's "descending staircase" guess was wrong). The two 555s do
not beat; they **alternate** at OSC2 = 15.307 Hz (U4 reset driven by OSC2
directly, U5 by its inverse): U5 455→559 Hz, U4 376→461 Hz. Step clock
OSC1 = 2.664 Hz (both MAME hard-clocks), counter wraps 0..9 while held.
Output modelled at ±VOICE_FS/2 (the mix node swings 0..6 V — two equal
470k into the coupling cap). Idle: /REFILL's open-collector shunt =
output forced 0, counter reset.

## Shared infrastructure

60.42 kHz DSP tick (clk/256) for envelopes, noise, and filters; tone
counters and VCOs stay at full clk. MM5837 as a 17-bit LFSR (taps 17,14)
clocked per tick — inside the part's real 48–112 kHz spread (MAME
underclocks it to 12 kHz for speed; we don't need to). **One** LFSR feeds
both explosions and asteroids because the board couples U8.3 onto both
JFET gates through C72 — the two noise voices are deliberately correlated.

## Three bugs found and fixed during sim bring-up

1. **Multiply-width wrap:** the SVF products (24×16) evaluated inside a
   24-bit expression context truncated and railed the filters to DC — the
   very trap the INV1 block documents. All products now go through explicit
   40-bit wires before shifting.
2. **Integer decay stall:** `env - (env>>13)` sticks at 8191 once the shift
   rounds to zero, leaving a permanent clamped rumble after the first
   explosion. Fixed with a −1 decrement floor (both noise envelopes).
3. **Fixed-point limit cycle:** with zero input the truncated SVF products
   sustain a ~150-LSB orbit (measured ~1000 counts post-mix). States are
   zeroed while the driving envelope is zero — inaudible by construction.

## Mixer

`MIX_MAKEUP_LOG2` dropped **7 → 1, permanent**, exactly as the old warning
comment demanded: worst realistic peak (explosion 12000 + asteroids 5640 +
everything else < 1000) ≈ 18 600, inside the clamp with ~1.75× margin. The
regression tb's invader-peak band updated to match (≈ ±225 — the invader
march genuinely is ~35 dB below an explosion through this mixer, which is
what the board's 1M-vs-4.7k summing resistors intend).

## Still unported

**SONAR and BONUS only.** Deliberately deferred: MAME's own netlist header
says both fail to trigger after the first few seconds even in MAME, SONAR
depends on ten randomised part values (FRND1..10), and both need the
clipping diodes MAME skips by default. Per project policy: calibrate these
against board captures, not any emulator.

## Deliverables

`astrob_audio.sv` (revision 2026-08-12b), `tb_astrob.sv` (retargeted),
`sim_all.cpp` (six-voice render harness), audition WAVs (per-voice
normalised): `astrob_laser1/laser2/sexpl/lexpl/astro/refill.wav` and the
combined `astrob_new_voices.wav`. Note the audition files are per-voice
normalised — through the real mixer the relative levels are
explosions ≫ asteroids ≫ laser1/refill > laser2/invaders.


---

# 2026-08-12c — Sonar + bonus: the board is complete

**Trigger:** "Do both — sonar capture from MAME attached." All sixteen latch
functions are now implemented; no stubs remain.

## SONAR ($3F bit 7) — MAME-capture calibrated, netlist lines 637–750

The circuit: four op-amp state-variable oscillators (U1/U2 LM324 pairs,
diode-limited to near-sine — the capture's 2nd harmonic sits at −39 dB)
summing into a Q2/Q3 differential VCA whose tail current, shaped by
C47 4.7µ (R117 1k attack / R108 100k decay), is the ping envelope.
Nominally all four oscillators run at the SAME frequency — the sound
exists only because real part tolerances detune them, which is exactly why
this voice could never be derived from the schematic and why MAME injects
FRND randomised values.

Calibration from the supplied gameplay capture (the file also contains
invader-march rumble at 48–118 Hz; the ping itself sits at t≈0.84 s):
four lines at **469.15 / 471.63 / 473.56 / 480.93 Hz**, relative levels
−12.7 / −0.5 / 0 / −2.0 dB (Goertzel-verified in the render to within
~1 dB), pairwise beats at 2.5/1.9/7.4/9.3 Hz matching the capture's 6.7
and 10 Hz envelope-modulation lines. Decay τ 478 ms measured — and the
nominal R108·C47 = 470 ms agrees, a satisfying cross-check. Attack: the
pure envelope is tuned to 98 ms 10→90% (capture read 96 ms), but note the
apparent per-ping attack swings 60–270 ms with beat phase at trigger, in
capture and model alike — it is not a stable measurement. Oscillator reset
phases are staggered because the board's oscillators free-run; coherent
starts audibly sharpen early pings.

Implementation: four 24-bit phase accumulators at the 60.4 kHz tick, one
64-entry quarter-wave sine LUT, capture-derived weights 468/1907/2020/1605
(sum 6000), envelope-multiplied through an explicit 34-bit product.

**Provenance warning, marked in the code:** these four frequencies encode
MAME's random seed, not a real board. A hardware capture supersedes this
block wholesale — keep the envelope, replace the increments and weights.

## BONUS ($3F bit 6) — "the deedle", netlist-nominal, lines 1134–1168

The circuit turned out prettier than expected: the trigger one-shot
(R44 1M × C19 .05µ = 34.7 ms) dumps C34 (10 µF, hung from the +12 rail)
through D7/R78 1k, and C34 then *recovers* through R77 330k with
**τ = 3.47 s — that recovery is the envelope**, self-gating the output
through the D8 half-wave stage (at rest the swing collapses to zero, which
is how the voice silences itself with the 555 free-running). The tone: U6
555 (4.7k/100k/4.7n) at ~1500 Hz with OSC4 (7.19 Hz, MAME hard clock)
injecting into the pin-7 node through R79 150k — the pitch alternates
**1501 / 1448 Hz at 7.19 Hz**. A ~1500 Hz tone warbling seven times a
second under a three-second fade is, indeed, a deedle. Peak swing ~10 V of
the 12 V rail → amplitude 4800 (5/6 VOICE_FS). Verified: alternation
sequence 1450/1500 exact, decay τ 3.38 s. No capture exists — flag for
ear check like the other netlist-nominal voices.

## Bug found and fixed: envelope quantisation

At 17-bit envelope width the bonus decay term `(env·5)>>20` is
**identically zero** (61440·5 < 2²⁰), so the envelope decayed linearly via
the −1 floor in ~1 s instead of exponentially in 3.5 s; sonar's `(env·9)>>18`
suffered milder quantisation (measured τ 386 ms vs 482 intended). Both
envelopes now run as 24-bit accumulators (value = top 17 bits, seven
fractional bits), which restores clean exponentials: sonar τ 512 ms
measured, bonus τ 3.38 s.

## Status

**All sixteen latch functions of the Astro Blaster sound board are now
implemented.** Provenance by voice: capture-anchored (board): INV1-4 +
warp variants. MAME-capture calibrated: SONAR. Netlist-nominal, ear-check
pending: LASER_1/2, SHORT/LONG_EXPL, ASTEROIDS, REFILL, BONUS. The speech
board (SP0250) is separate hardware and out of scope.

## Deliverables

`astrob_audio.sv` (revision 2026-08-12c), `sim_all.cpp` (eight-voice
harness), `astrob_sonar.wav` (2 s: ping + retrigger), `astrob_bonus.wav`
(4 s: full deedle fade), regenerated `astrob_new_voices.wav` (all eight
new voices in sequence, per-voice normalised).
