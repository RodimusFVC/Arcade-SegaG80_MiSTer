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
