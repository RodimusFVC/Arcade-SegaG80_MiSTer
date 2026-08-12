# Astro Blaster G-80 Sound Board — Implementation Backlog

**Source:** Gremlin dwg. 800-3122 Rev B, sheets 7 & 8 of 8
**Status:** Derived from schematic only — **not yet diffed against the SV source** (file was not attached to the request)
**Purpose:** Track the gap between the analogue board's actual behaviour and the HDL recreation

---

## How to use this

Every item below is derived from a component value or topology I can read on the
schematic. Items are ordered by how likely they are to be the cause of "makes sound
but sounds wrong". Each has an **Acceptance** line you can test against.

Mark each item `CONFIRMED` / `MISSING` / `PARTIAL` once you've checked it against the
RTL. Once the SV is attached I can fill that column in directly and cut the items you
already have.

---

## P0 — Most likely causes of "sounds wrong"

These are the four things that make the board sound like *this* board rather than
generic arcade bleeps. If any one is missing, everything downstream sounds off even
when each individual voice is technically correct.

---

### SND-001 — Master mixer gain ratios (U7 summing amp)

**Priority:** P0 · **Effort:** S

The eleven voices are summed into U7 through *deliberately unequal* resistors, with
R144 = 22K as the feedback. The spread is nearly 47 dB. If the RTL sums voices at
equal or roughly-equal amplitude, the mix will be wrong no matter how good each voice
is — the invader march will dominate and explosions will sound thin.

| Voice | Summing R | Value | Gain (Rf/Rin) | Rel. to Explosions |
|---|---|---|---|---|
| Explosions | R122 | 4.7K | 4.681 | 0.0 dB |
| Asteroids | R121 | 10K | 2.200 | −6.6 dB |
| Sonar | R120 | 220K | 0.100 | −33.4 dB |
| Bonus | R118 | 470K | 0.0468 | −40.0 dB |
| Refill | R119 | 470K | 0.0468 | −40.0 dB |
| Laser-1 | R102 | 470K | 0.0468 | −40.0 dB |
| Laser-2 | R103 | 1M | 0.0220 | −46.6 dB |
| Invader-1 | R98 | 1M | 0.0220 | −46.6 dB |
| Invader-2 | R99 | 1M | 0.0220 | −46.6 dB |
| Invader-3 | R100 | 1M | 0.0220 | −46.6 dB |
| Invader-4 | R101 | 1M | 0.0220 | −46.6 dB |

**Caveat:** these are *gains*, not final levels. The source amplitudes differ hugely —
invader voices come straight off NE555 outputs at ~12 Vpp, while explosions arrive
from an op-amp stage at a fraction of that. The resistors compensate for that. So port
the gains *and* make sure your voice sources are scaled to their real analogue
amplitudes, or apply the compensated net levels instead.

**Acceptance:** With all voices forced on at their nominal amplitudes, the relative
RMS at the mixer output matches the table within ±1 dB.

---

### SND-002 — Laser voices are weighted counter-DAC waveforms, not square waves

**Priority:** P0 · **Effort:** M

Both laser voices run an NE555 into a **CD4024 7-stage binary divider**, then sum five
divider taps through weighted resistors. The result is a stepped, harmonically dense
waveform — not a square wave, and not a clean sawtooth either.

| Voice | 555 | Timing | Divider | Q1 (÷2) | Q2 (÷4) | Q3 (÷8) | Q4 (÷16) | Q6 (÷64) |
|---|---|---|---|---|---|---|---|---|
| Laser-1 | U24 | R139/R140 4.7K, C65 .01 µF | U19 | R132 82K | R131 39K | R130 22K | R105 10K | R104 10K |
| Laser-2 | U20 | R145/R137 4.7K, C68 .0047 µF | U14 | R125 82K | R126 39K | R128 22K | R129 10K | R127 10K |

Three details that are easy to miss:

- **Q5 (÷32) is deliberately skipped** on both. The tap set is Q1, Q2, Q3, Q4, Q6.
  Including Q5 changes the timbre audibly.
- **Weights are inverted vs. pitch** — the lowest-frequency taps get the smallest
  resistors, i.e. the *most* weight. Sub-octave heavy.
- **The CD4024 reset (pin 2) is driven per trigger**, so the waveform restarts at a
  known phase every shot. A free-running counter gives a different attack transient
  each time.

**Acceptance:** Spectrum of a single laser shot shows energy at f/2, f/4, f/8, f/16 and
f/64 with amplitude ratios matching 1/82K : 1/39K : 1/22K : 1/10K : 1/10K, and
**no** f/32 component.

---

### SND-003 — Noise voices are heavily low-pass filtered, not white

**Priority:** P0 · **Effort:** M

Both noise voices come off the single **MM5837** (U8) but each has its own filter, and
both corners are *very* low. Gated white noise sounds like "shhh"; these should sound
like "boom" and "rumble".

**Explosions (U16 pair):** noise → Q6 2N4093 JFET VCA → R180/R181 47K into U16 →
R177/R176 47K into second U16 stage with **C78 0.1 µF in feedback** and **C76 .022 µF
+ C77 .0047 µF** shunt. Effective 2-pole low-pass with corners in the ~34 Hz and
~127 Hz region.

**Asteroids (U16 + U7):** noise arrives via R165 1M → Q5 2N4093 JFET VCA → R173/R174/
R175 47K stage → MFB low-pass R172 33K, R150 33K, C70 0.1 µF, C71 .022 µF →
**f₀ ≈ 103 Hz, Q ≈ 1.07** → then R136 1K / C59 .33 µF adds another pole at ≈482 Hz.

**Acceptance:** Explosion spectrum is −3 dB by ~130 Hz and rolling off at ~12 dB/oct
above it. Asteroids peaks at ~100 Hz with a mild resonant bump.

---

### SND-004 — Attack-rate ladder (node V) — the invader tempo escalation

**Priority:** P0 · **Effort:** M

U15 (CD4017) steps through ten diode-isolated resistors into R178 22K, buffered by
U16 (pins 5/6/7) onto **node V**, which is routed to sheet 7 and feeds the CV/timing
of the invader oscillators. This is the "invaders speed up" mechanism. Without it the
march is a fixed tempo and the game loses its whole sense of escalation.

Clock: CD4011 (U21) gated oscillator, R166 1M, C69 .05 µF, gated by `ATTACK RATE`
(U26-2), reset by `RATE RESET` (U31-12).

| Step | Resistor | Value | Node V |
|---|---|---|---|
| Q0 | R161 | 120K | 1.77 V |
| Q1 | R160 | 82K | 2.41 V |
| Q2 | R159 | 62K | 2.99 V |
| Q3 | R155 | 56K | 3.22 V |
| Q4 | R153 | 47K | 3.63 V |
| Q5 | R156 | 39K | 4.11 V |
| Q6 | R158 | 33K | 4.56 V |
| Q7 | R157 | 27K | 5.12 V |
| Q8 | R154 | 24K | 5.45 V |
| Q9 | R152 | 22K | 5.70 V |

Ascending, and the steps get *wider* toward the end — the last few speed-ups are the
most dramatic. `WARP` (U31-6) injects into the same node through R164 10K / R163 10K
with R162 4.7K to +12, overriding the ladder.

**Acceptance:** Ten discrete tempo steps, monotonically increasing, with the Q0→Q9
ratio matching the voltage ratio through your 555 CV model. WARP produces a distinct
rate not equal to any ladder step.

---

## P1 — Voice-level fidelity

---

### SND-005 — Refill: 10-step descending CV sequence

**Priority:** P1 · **Effort:** M

U3 (CD4017) steps a second resistor ladder into R17 10K (pull-up to +12), driving the
timing network of two NE555s (U4, U5). Unlike the attack ladder these outputs are
**push-pull CMOS with no isolating diodes**, so the nine inactive outputs actively pull
the node down — which is why the steps compress rather than spread.

Clock: CD4011 (U9) oscillator, R18 2.7M, C3 0.1 µF. Reset via `REFILL` (U29-10).

| Step | R | Value | Node | Step | R | Value | Node |
|---|---|---|---|---|---|---|---|
| Q0 | R8 | 18K | 5.89 V | Q5 | R6 | 68K | 4.34 V |
| Q1 | R7 | 22K | 5.50 V | Q6 | R10 | 100K | 4.16 V |
| Q2 | R9 | 33K | 4.93 V | Q7 | R11 | 150K | 4.04 V |
| Q3 | R12 | 39K | 4.75 V | Q8 | R15 | 220K | 3.96 V |
| Q4 | R14 | 47K | 4.59 V | Q9 | R13 | 330K | 3.90 V |

Descending and **decelerating** — a falling run that flattens out. The two 555s free-run
at roughly 376 Hz (U5: R67 10K, R68 82K, C26 .022 µF) and 312 Hz (U4: R41 10K,
R42 100K, C18 .022 µF) before modulation, so the sound is a beating two-tone warble
stepping downward.

**Note:** confirm the exact injection point — R16 10K feeds down toward R43 470K /
Q7, and R61/R69 470K sit on the 555 CV pins. Worth a quick SPICE pass to settle
whether the ladder lands on CV, on the timing resistor, or both.

**Acceptance:** Ten pitch steps, descending, with intervals narrowing toward the end.

---

### SND-006 — Sonar: four parallel zener-noise bandpass channels

**Priority:** P1 · **Effort:** M

Sheet 7's top-left quadrant is **four identical channels**, which is easy to read as
duplication and collapse into one. Each is a 1N5231 zener avalanche noise source
amplified by U1/U2, then a multiple-feedback bandpass.

Per channel: R(in) 100K, R(Q) 1.5K, R(fb) 330K, C = .01 µF ×2
→ **f₀ ≈ 721 Hz, Q ≈ 7.5, gain 1.65**

Channels: (D1/R1/R2/R3/C1/C2), (D4/R36/R37/R38/C16/C17), (D6/R62/R63/R64/C24/C25),
(D10/R91/R92/R93/C40/C41). All four sum through 68K resistors (R5, R40, R66, R95)
into a Q1/Q2/Q3 transistor VCA with envelope cap C47 4.7 µF / R108 100K, then U7.

Summing four *independent* narrowband noise sources at the same centre frequency
gives a denser, smoother pitched-hiss than one channel at 4× gain. Four uncorrelated
LFSRs will reproduce this; one LFSR fanned out four ways will not.

**Acceptance:** Four independent noise sources, each bandpassed at ~721 Hz with
Q ≈ 7.5, summed equally. Envelope decay τ ≈ R108 × C47 ≈ 0.47 s.

---

### SND-007 — Explosion short vs. long: different one-shot time constants

**Priority:** P1 · **Effort:** S

Two separate triggers with deliberately different envelopes:

- **SHORT EXPL** (U26-10): R169 100K / R185 1M, C81 .05 µF
- **LONG EXPL** (U26-8): R171 100K / R170 2.2M, C82 0.1 µF

The long one-shot's RC is ~4.4× the short's. Envelope storage caps C80 4.7 µF and
C69 4.7 µF discharge through R182 10K / R183 10K with D30/D31 steering, producing
**exponential** decay into the JFET VCA gate — not a linear ramp and not a gate.

**Acceptance:** Two distinct decay lengths at roughly a 4:1 ratio, both exponential.

---

### SND-008 — Invader-2 and Invader-4 have *inverted* DAC weightings

**Priority:** P1 · **Effort:** S

Both run a 555 into a CD4024 and sum four taps — but the weights are reversed, giving
one a bass-heavy timbre and the other a bright one. A shared parameterised module with
one weight table will get one of them wrong.

| Tap | Invader-2 (U12) | Invader-4 (U28) |
|---|---|---|
| Q1 (÷2) | R48 82K | R31 10K |
| Q2 (÷4) | R49 39K | R32 22K |
| Q3 (÷8) | R50 22K | R33 39K |
| Q4 (÷16) | R47 10K | R30 82K |

Invader-2's source 555 is U13 (R81 10K, R82 100K, C36 .0022 µF) with **node V on
pin 5**; its CD4024 reset comes from a CD4011 (U11) oscillator, R22 470K, C5 0.1 µF.
Invader-4's is U37 (R89 10K, R90 100K, C39 0.1 µF), and its DAC output drives a
*further* 555 (U38, R60 10K, R61 100K, R88 100K) before the sum.

**Acceptance:** Invader-2 spectral centroid sits well below Invader-4's.

---

### SND-009 — Invader-1 and Invader-3 are swept-555 pairs, not divider DACs

**Priority:** P1 · **Effort:** M

Different topology again — these two use a rate 555 gating a tone 555 whose pitch is
swept by an op-amp integrator.

**Invader-1:** U22 integrator (R55 2.2M, C21/C22 .33 µF, R56/R57 33K, R58 820K),
gated by node **W** through U30 (7406) → U23 NE555 rate oscillator (R85 150K, R86 10K,
C38 0.1 µF) with node **V** injected via R87 10K → U18 NE555 tone oscillator (R83 1K,
R84 5.6K, R73 100K, C37 0.1 µF, C28 .05 µF) swept by Q8 2N4403.

**Invader-3:** same shape — D3 1N5231 reference, U22 second half (R25 10K, R24 2.2M,
R26 820K, R28 22K), gated by W via U30 pin 9/8 → U17 NE555 (R51 10K, R52 68K,
C7 0.1 µF).

**Acceptance:** Each note is a descending pitch sweep, not a fixed tone, and the sweep
depth is independent of the march tempo.

---

### SND-010 — Diode soft-clipping in the explosion path

**Priority:** P1 · **Effort:** S

D27 and D28 sit back-to-back at the U16 output stage. On loud explosions the signal
clips softly against ~±0.6 V, adding low-order harmonic grit. Hard digital clipping at
full scale sounds harsher and completely different.

**Acceptance:** Explosion transient shows soft symmetric compression, not flat-topping.

---

### SND-011 — Mute is a JFET shunt with an RC, not a hard gate

**Priority:** P1 · **Effort:** S

`MUTE` (U32-5) → R124 100K → U7 comparator (pins 5/6/7, with R115 100K, R116 470K,
R117 1K, R123 1K) → D13 → gate of **Q4 2N4093**, which shunts the output node through
R135 22K, with R142 1M on the gate. This gives a soft, finite-time fade with residual
bleed-through — not an instant hard mute.

**Acceptance:** Mute engages over a measurable ramp with a small residual floor.

---

### SND-012 — Single shared MM5837 noise source

**Priority:** P1 · **Effort:** S

Explosions and asteroids both tap **U8** — the same physical noise stream, split via
R165 1M. When both fire together the noise is *correlated*, which sums differently
(+6 dB where uncorrelated sources would give +3 dB) and audibly changes a
simultaneous asteroid-hit-plus-explosion.

MM5837 specifics worth matching: 17-bit LFSR, taps at bits 17 and 14, internal clock
nominally ~32–36 kHz but notoriously part-to-part variable. Its spectrum is not flat —
it rolls off above a few kHz, which is part of the character.

**Acceptance:** One LFSR instance feeding both voices' VCAs.

---

### SND-013 — Port decode and latch bit map

**Priority:** P1 · **Effort:** S

Decode: A7–A0 → 74LS30 (U35) + 74LS04 (U36) + 74LS00 (U34), with A0 selecting
**PORT 076** (clocks U32) vs **PORT 077** (clocks U33). Both are 74LS374s on the
shared data bus.

**Port 077 → U33** (confirmed from the schematic):

| Bit | Signal |
|---|---|
| D0 | LASER #1 |
| D1 | LASER #2 |
| D2 | SHORT EXPL |
| D3 | LONG EXPL |
| D4 | ATTACK RATE |
| D5 | RATE RESET |
| D6 | *(via U29 pin 9→8 — trace to confirm)* |
| D7 | SONAR |

**Port 076 → U32** (partially traced — verify before relying on it):

| Bit | Q pin | Routes to |
|---|---|---|
| D0 | 19 | via U31 inverter → invader group |
| D1 | 16 | via U31 inverter → invader group |
| D2 | 15 | via U31 inverter → invader group |
| D3 | 12 | via U31 inverter → invader group |
| D4 | 2 | ASTROIDS (via U30) |
| D5 | 5 | MUTE |
| D6 | 6 | node **W** (invader ramp gate) |
| D7 | 9 | WARP (via U31) |

REFILL and /REFILL (U29-10, U30-3) also originate from this latch — the exact bit
wasn't resolvable at scan resolution.

**Acceptance:** Writing each bit individually to 076/077 triggers exactly the expected
voice, verified against MAME's driver or a real board.

---

### SND-014 — External speech input summing

**Priority:** P1 · **Effort:** S

P1-3 (EXT INPUT) joins through R143 22K at the U7 output node, ahead of the mute
JFET. Per the manual, this is where the Speech Board's output mixes in before the
combined signal goes out on P1-1 to the power-supply amplifier. Confirm whether your
design mutes speech along with the sound board — the topology suggests it does.

**Acceptance:** Speech and sound-board audio sum at the documented ratio; mute
behaviour on the speech path matches hardware.

---

## P2 — Refinement

---

### SND-015 — NE555 non-50% duty cycle

**Priority:** P2 · **Effort:** S

Standard 555 astables are asymmetric: duty = (Ra+Rb)/(Ra+2Rb). For Invader-2's U13
(Ra 10K, Rb 100K) that's ~52%; for Refill's U5 (Ra 10K, Rb 82K) ~55%. A 50% square
wave has no even harmonics — the real thing does. Small, but it accounts for a
"cleaner than it should be" quality.

---

### SND-016 — 555 CV pin response curve

**Priority:** P2 · **Effort:** M

Several oscillators are frequency-modulated through pin 5, which sets the upper
comparator threshold. The frequency-vs-CV relationship is **non-linear** — roughly
f ∝ 1/ln((Vcc−Vcv)/(Vcc−Vcv/2)) territory. A linear CV→frequency map will get the
ladder endpoints right and everything between them wrong, which shows up as the
tempo escalation feeling evenly spaced instead of accelerating.

---

### SND-017 — Rail limits and headroom

**Priority:** P2 · **Effort:** S

The board runs ±12 V. Voices that clip against the rails in hardware should clip at
the equivalent point in the digital model, not at an arbitrary full-scale. Check the
explosion path in particular — R179/R180/R181 47K around U16 gives enough gain to
reach the rails on a loud hit.

---

### SND-018 — AC coupling corners

**Priority:** P2 · **Effort:** S

Every voice output is AC-coupled and the cap values differ, which means each voice
has its own high-pass corner: C61 4.7 µF (explosions), C60 4.7 µF (asteroids),
C52/C51 .05 µF (lasers), C49 .05 µF (refill), C50 .05 µF (bonus), C58 4.7 µF (main
output), C55 .05 µF (mixer input). The .05 µF ones into ~470K–1M summing resistors put
corners in the single-Hz range, but the mixer-input C55 into the summing node is high
enough to matter for the low-frequency voices.

---

### SND-019 — Bonus voice

**Priority:** P2 · **Effort:** M

Not yet fully traced. Chain runs R45 100K / R44 1M → U10 CD4011 one-shot (C19 .05 µF)
→ D7 → R78 1K → R80 1M / C35 .05 µF → R77 330K / C34 10 µF → R79 150K, R74 47K,
R75 100K → U6 NE555 (C31 .0047 µF, C32 .05 µF) → D8 → C50 .05 µF → BONUS (SUM).
The 10 µF / 330K stage implies a long (~3 s) envelope.

---

## Reference: signal inventory

| Voice | Generator | Shaping | Trigger |
|---|---|---|---|
| Laser-1 | U24 555 → U19 CD4024 DAC | sweep via Q10/R107/C57 | 077 D0 |
| Laser-2 | U20 555 → U14 CD4024 DAC | sweep via Q9/R106/C63 | 077 D1 |
| Short Expl | MM5837 → Q6 JFET VCA | 2-pole LPF + soft clip | 077 D2 |
| Long Expl | MM5837 → Q6 JFET VCA | same, longer envelope | 077 D3 |
| Asteroids | MM5837 → Q5 JFET VCA | MFB LPF ~103 Hz | 076 D4 |
| Sonar | 4× zener noise | 4× BPF 721 Hz Q7.5 → VCA | 077 D7 |
| Refill | U4/U5 555 pair | U3 CD4017 10-step CV | 076 (REFILL) |
| Bonus | U6 555 | long envelope | 076 |
| Invader-1 | U23 → U18 555 pair | U22 integrator sweep | 076 D0 |
| Invader-2 | U13 555 → U12 CD4024 | bass-weighted DAC | 076 D1 |
| Invader-3 | U17 555 pair | U22 integrator sweep | 076 D2 |
| Invader-4 | U37 → U28 → U38 | bright-weighted DAC | 076 D3 |
| *(global)* | U15 CD4017 | node V — tempo ladder | 077 D4/D5 |
| *(global)* | U32-5 | mute (Q4 JFET shunt) | 076 D5 |

---

## Open questions for the next pass

1. Exact injection point of the refill ladder (CV pin vs. timing resistor).
2. U32 D6 / REFILL bit assignment — needs a higher-resolution scan or continuity check.
3. Whether the four sonar channels' zeners were selected/binned, or whether part
   tolerance was relied on for decorrelation.
4. MM5837 clock rate on the actual board — worth measuring if one is available, since
   it sets the noise spectrum and varies significantly between parts.
