# Astro Blaster sound board — remaining voices: Verilog + reference renders

Companion to `astrob_audio.sv`. One section per voice not yet ported (plus the
INV2 correction). Each has: netlist derivation, parameters, a Verilog block
ready to paste, a reference WAV (`astrob_<voice>.wav`) rendered from the same
model, and a confidence tag.

Tags: **[DERIVED]** = parameters computed from schematic part values.
**[APPROX]** = architecture right, constants need tuning against board audio.
**[SKETCH]** = plausible-sounding stand-in; capture board audio before porting.

All blocks assume the existing file's conventions: `clk_sys` = 15.46848 MHz,
async `reset`, per-voice `*_gate` from the port latches, signed 16-bit voice
outputs summed downstream. Add each output to `voice_sum` and rescale so the
worst-case sum stays inside ±32767 (see "Mixer" at the end).

---

## INVADER_2 — correction, not new voice  [DERIVED]

OSC3 (`CLOCK(OSC3, 15.3)`, from R22=470k/C5=0.1µF CD4011) is a **50%-duty
square into U12's active-high RESET** — the counter is *held* at zero half of
every cycle, not pulse-reset. And the tap ladder is Q1–Q4 (÷2..÷16), binary
weighted, MSB on the ÷16 tap: a 16-step sawtooth at ~195 Hz. Board evidence:
every measured peak is an integer multiple of 15.29 Hz; odd-only low
harmonics (45.9/76.5 = 3×/5×, no 30.6) = square gate.

```verilog
// --- replace inv2 reset-pulse + tap block with: ---
localparam [19:0] INV2_GATE_HALF = 20'd505671;      // clk/(2*15.29Hz)
reg  [19:0] inv2_g_cnt;  reg inv2_g_lvl;            // OSC3 50% square
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin inv2_g_cnt <= 20'd0; inv2_g_lvl <= 1'b0; end
    else if (inv2_g_cnt == 20'd0)
         begin inv2_g_cnt <= INV2_GATE_HALF; inv2_g_lvl <= ~inv2_g_lvl; end
    else inv2_g_cnt <= inv2_g_cnt - 20'd1;
end
wire inv2_hold = inv2_g_lvl;                        // high = counter held reset

always @(posedge clk_sys or posedge reset) begin    // existing inv2_div, new hold
    if (reset)                          inv2_div <= 7'd0;
    else if (!inv2_gate || inv2_hold)   inv2_div <= 7'd0;
    else if (inv2_osc_rise)             inv2_div <= inv2_div + 7'd1;
end

wire signed [4:0] inv2_tap_sum =                    // Q1..Q4 binary DAC
    (inv2_div[0] ? 5'sd1 : -5'sd1) +                // Q1  R48 82k
    (inv2_div[1] ? 5'sd2 : -5'sd2) +                // Q2  R49 39k
    (inv2_div[2] ? 5'sd4 : -5'sd4) +                // Q3  R50 22k
    (inv2_div[3] ? 5'sd8 : -5'sd8);                 // Q4  R47 10k (MSB)
// while held, output the reset code (all-low = -15), AC coupling kills the DC
```
Reference: `astrob_invader2.wav`. Zero fitted parameters.

---

## INVADER_3 — FM warble  [DERIVED architecture, APPROX depth]

U17 (R51=10k, R52=68k, C7=0.1µF → 98.8 Hz nominal; 104.9 at V=7.57) with its
CV pin swept by U22-A/B (R24=2.2M relaxation osc) through C12/R54. Measured
warble: cluster spacing ~8.7 Hz normal / ~5.05 Hz warp; center 108.5 / 100.1.
Deviation ±~8% fits the cluster width. Direct warp path: NET_C(W, U30.9).

```verilog
localparam [20:0] INV3_TRI_HALF_N = 21'd888993;   // clk/(2*8.7Hz)
localparam [20:0] INV3_TRI_HALF_W = 21'd1531533;  // clk/(2*5.05Hz)
localparam [16:0] INV3_PER_CTR_N  = 17'd71284;    // clk/(2*108.5) center half-period
localparam [16:0] INV3_PER_CTR_W  = 17'd77265;    // clk/(2*100.1)
localparam [16:0] INV3_PER_DEV    = 17'd5700;     // ~8% of center

// triangle LFO (up/down counter), 8-bit output
reg [20:0] inv3_lfo_cnt; reg inv3_lfo_dir; reg [7:0] inv3_lfo;
wire [20:0] inv3_tri_half = warp_active ? INV3_TRI_HALF_W : INV3_TRI_HALF_N;
wire [20:0] inv3_lfo_step = inv3_tri_half >> 8;   // 256 steps per half
reg [20:0] inv3_lfo_pre;
always @(posedge clk_sys or posedge reset) begin
    if (reset || !inv3_gate) begin
        inv3_lfo<=8'd128; inv3_lfo_dir<=1'b0; inv3_lfo_pre<=21'd0;
    end else if (inv3_lfo_pre >= inv3_lfo_step) begin
        inv3_lfo_pre <= 21'd0;
        if (inv3_lfo_dir) begin
            if (inv3_lfo==8'd0)   inv3_lfo_dir<=1'b0; else inv3_lfo<=inv3_lfo-8'd1;
        end else begin
            if (inv3_lfo==8'd255) inv3_lfo_dir<=1'b1; else inv3_lfo<=inv3_lfo+8'd1;
        end
    end else inv3_lfo_pre <= inv3_lfo_pre + 21'd1;
end

wire [16:0] inv3_per_ctr = warp_active ? INV3_PER_CTR_W : INV3_PER_CTR_N;
// half period = center + dev*(lfo-128)/128
// explicit wide product — a self-determined multiply here wraps
// (same bug class caught in sim on INV1's width multiply, 2026-08-09)
wire signed [17:0] inv3_lfo_c = $signed({10'd0, inv3_lfo}) - 18'sd128;
wire signed [35:0] inv3_dev_p = $signed({19'd0, INV3_PER_DEV}) * inv3_lfo_c;
wire signed [17:0] inv3_dev   = inv3_dev_p[24:7];   // >>7
wire [16:0] inv3_half = inv3_per_ctr + inv3_dev[16:0];

reg [16:0] inv3_osc_cnt; reg inv3_osc_out;         // replaces static osc
always @(posedge clk_sys or posedge reset) begin
    if (reset || !inv3_gate) begin inv3_osc_cnt<=17'd0; inv3_osc_out<=1'b0; end
    else if (inv3_osc_cnt==17'd0) begin inv3_osc_cnt<=inv3_half; inv3_osc_out<=~inv3_osc_out; end
    else inv3_osc_cnt <= inv3_osc_cnt - 17'd1;
end
wire signed [15:0] inv3_out = inv3_gate ? (inv3_osc_out ? 16'sd6000 : -16'sd6000) : 16'sd0;
```
Reference: `astrob_invader3.wav` (normal, then warp). Tune `INV3_PER_DEV`
against the board's cluster width; everything else is measured or computed.

---

## INVADER_4 — staircase CV sweep  [DERIVED]

U37 free-runs at 68.7 Hz (R89=10k, R90=100k, C39=0.1µF) clocking U28
(CD4024). U28 self-resets from its own Q5 (pin 2←pin 5): **mod-32**. Q1–Q4
through R31/32/33/30 (10k/22k/39k/82k → weights 8/4/2/1, Q1=MSB weight-wise
since R31 is smallest) into U38's CV pin. U38 base 687 Hz (R60=10k, R61=100k,
C23=0.01µF). Result: 16-step frequency staircase, two ramps per 32-count,
sweep rate 68.7/32 ≈ 2.15 Hz, spanning ~682–890 Hz (matches measured spread;
your 771 Hz was the sweep's average, your 730/748 were samples of it).

```verilog
localparam [17:0] INV4_STEP_HALF = 18'd112580;    // clk/(2*68.7Hz) U37 osc
reg [17:0] inv4_stp_cnt; reg inv4_stp_out;
always @(posedge clk_sys or posedge reset) begin  // U37 (never gated on board)
    if (reset) begin inv4_stp_cnt<=18'd0; inv4_stp_out<=1'b0; end
    else if (inv4_stp_cnt==18'd0) begin inv4_stp_cnt<=INV4_STEP_HALF; inv4_stp_out<=~inv4_stp_out; end
    else inv4_stp_cnt <= inv4_stp_cnt - 18'd1;
end
reg inv4_stp_d; always @(posedge clk_sys) inv4_stp_d<=inv4_stp_out;
wire inv4_stp_rise = inv4_stp_out & ~inv4_stp_d;

// OPEN QUESTION: pin2<-pin5 self-reset fires when Q5 RISES (count 16)
// -> mod-16, one ramp/cycle, sweep ~4.3 Hz. If the board's sweep repeats
// at ~2 Hz instead, it's effectively mod-32: widen to reg [4:0] and keep
// code = ring[3:0]. Modeled mod-16 here (matches revised .sv).
reg [3:0] inv4_ring;                              // U28 mod-16 (see note)
always @(posedge clk_sys or posedge reset) begin
    if (reset) inv4_ring<=4'd0;
    else if (inv4_stp_rise) inv4_ring<=inv4_ring+4'd1;   // wrap = self-reset
end
wire [3:0] inv4_code = inv4_ring;                 // Q1..Q4 binary ramp

// half-period from code: 682 Hz (code 0) .. 890 Hz (code 15)
// half = clk/(2*f); precompute endpoints, linear interp is close enough
localparam [16:0] INV4_HALF_LO = 17'd8690;        // 890 Hz
localparam [16:0] INV4_HALF_HI = 17'd11340;       // 682 Hz
wire [16:0] inv4_half = INV4_HALF_HI - (((INV4_HALF_HI-INV4_HALF_LO)*inv4_code)/15);

reg [16:0] inv4_osc_cnt; reg inv4_osc_out;
always @(posedge clk_sys or posedge reset) begin
    if (reset || !inv4_gate) begin inv4_osc_cnt<=17'd0; inv4_osc_out<=1'b0; end
    else if (inv4_osc_cnt==17'd0) begin inv4_osc_cnt<=inv4_half; inv4_osc_out<=~inv4_osc_out; end
    else inv4_osc_cnt <= inv4_osc_cnt - 17'd1;
end
wire signed [15:0] inv4_out = inv4_gate ? (inv4_osc_out ? 16'sd6000 : -16'sd6000) : 16'sd0;
```
Reference: `astrob_invader4.wav`. Replaces the static-771 Hz model; the
"known gap" comment can be deleted.

---

## LASER_1 / LASER_2 — swept VCO into 5-tap sub-octave stack  [APPROX]

Trigger (U25 CD4011 one-shot) charges C57 (L1) / C53 (L2) through
R138=2.2M / R147; the envelope, buffered by Q10/Q9 (2N4403 emitter follower),
drives the 555 CV: **frequency starts high and falls** as CV rises. U24/U20
output clocks U19/U14 (CD4024); five taps (÷2..÷32) resistor-summed. MAME
replaces both VCOs with fitted polynomials (HLE_LASER_*_VCO) — read the
schematic, not those coefficients. Computed U24 base: 10.2 kHz at nominal CV,
24 kHz at CV=2V, 6.6 kHz at CV=10V. L2 runs faster (C68=.0047µF → ~21.8 kHz
nominal) with a shorter envelope.

```verilog
// LASER_1 — retriggerable one-shot; freq decays exponentially (RC), /2../32 stack
localparam [23:0] L1_ENV_TAU  = 24'd2784326;   // ~0.18 s in clk cycles (2.2M*C57 shaped)
localparam [15:0] L1_F0_HALF  = 16'd859;       // 9 kHz start (half-period)
localparam [15:0] L1_F1_HALF  = 16'd8594;      // 900 Hz floor
// 16-bit envelope phase: env goes 0->65535 over ~5*tau; freq = interp(F0..F1, 1-exp)
// Cheap RTL exponential: env += (65535-env) >> k every fixed tick.
reg [15:0] l1_env; reg [11:0] l1_tick;
wire l1_trig = hi_wr_strobe & ~audio_din[0] & latch_3f[0];  // falling edge of bit
always @(posedge clk_sys or posedge reset) begin
    if (reset)            begin l1_env<=16'hFFFF; l1_tick<=12'd0; end
    else if (l1_trig)     begin l1_env<=16'd0;    l1_tick<=12'd0; end   // retrigger
    else if (l1_tick==12'd3777) begin                    // tick ~4.1kHz
        l1_tick<=12'd0;
        l1_env <= l1_env + ((16'hFFFF - l1_env) >> 6);   // exp approach, tau≈0.18s
    end else l1_tick<=l1_tick+12'd1;
end
wire [15:0] l1_half = L1_F0_HALF + (((L1_F1_HALF-L1_F0_HALF) * l1_env) >> 16);

reg [15:0] l1_osc_cnt; reg l1_osc;   reg l1_osc_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin l1_osc_cnt<=16'd0; l1_osc<=1'b0; end
    else if (l1_osc_cnt==16'd0) begin l1_osc_cnt<=l1_half; l1_osc<=~l1_osc; end
    else l1_osc_cnt<=l1_osc_cnt-16'd1;
end
always @(posedge clk_sys) l1_osc_d<=l1_osc;
reg [5:0] l1_div;
always @(posedge clk_sys or posedge reset) begin
    if (reset) l1_div<=6'd0;
    else if (l1_osc & ~l1_osc_d) l1_div<=l1_div+6'd1;
end
wire signed [5:0] l1_tap =
    (l1_div[0]?6'sd8:-6'sd8)+(l1_div[1]?6'sd6:-6'sd6)+(l1_div[2]?6'sd4:-6'sd4)+
    (l1_div[3]?6'sd3:-6'sd3)+(l1_div[4]?6'sd2:-6'sd2);
// amplitude envelope: reuse (65535-l1_env) as decay.
// WIDTH FIX (2026-08-09): 17-bit * 6-bit signed product needs 23 bits;
// self-determined it wraps (same class as the INV1 sim-caught bug).
wire signed [16:0] l1_amp   = $signed({1'b0, 16'hFFFF - l1_env});
wire signed [22:0] l1_prod  = l1_amp * l1_tap;
wire signed [15:0] l1_out   = l1_prod[22:7];
```
LASER_2: same block, `L2_F0_HALF≈483` (16 kHz), `L2_F1_HALF≈5524` (1.4 kHz),
env shift `>>5` (tau≈0.10 s). References: `astrob_laser1.wav`,
`astrob_laser2.wav`. `hi_wr_strobe` = write strobe to $3F; add it next to the
latch process. Start/floor freqs and tap weights are the tunables.

---

## EXPLOSIONS (short + long) — MM5837 noise, two envelopes, one filter  [APPROX]

U8 (MM5837) → C72 → Q5/Q6 JFET VCAs → U16 filter → EXPLOSIONS node. Short and
long differ only in envelope (U27 one-shots; long uses U21/C74/R165 for a
longer decay). Model: 17-bit LFSR noise, exponential decay (~0.12 s short /
~0.55 s long), one-pole LP ~900 Hz.

```verilog
reg [16:0] lfsr;                                    // MM5837-style
wire fb = lfsr[16] ^ lfsr[13];
reg [8:0] nz_div;
always @(posedge clk_sys or posedge reset) begin    // clock LFSR ~60kHz
    if (reset) begin lfsr<=17'h1; nz_div<=9'd0; end
    else if (nz_div==9'd257) begin nz_div<=9'd0; lfsr<={lfsr[15:0],fb}; end
    else nz_div<=nz_div+9'd1;
end
wire signed [15:0] nz = lfsr[0] ? 16'sd8000 : -16'sd8000;

// two exponential decay envelopes, both 16-bit, retriggered by their
// port-bit falling edges (same env block pattern as LASER_1: tick ~4.1kHz,
// short: env -= env>>5 per tick (tau~0.12s); long: env -= env>>7 (~0.55s)):
reg [15:0] env_s, env_l;                            // build per LASER pattern
// WIDTH FIX (2026-08-09): 17-bit sum * 16-bit noise needs 33 bits;
// the original one-liner self-determined at 17 bits and wrapped.
wire        [16:0] expl_env  = {1'b0,env_s} + {1'b0,env_l};
wire signed [33:0] expl_prod = $signed({1'b0, expl_env}) * nz;
wire signed [15:0] expl_pre  = expl_prod[32:17];
reg  signed [15:0] lp_acc;
always @(posedge clk_sys) lp_acc <= lp_acc + ((expl_pre - lp_acc) >>> 8);  // ~900Hz @ clk
wire signed [15:0] expl_out = lp_acc;
```
References: `astrob_expl_short.wav`, `astrob_expl_long.wav`. Envelope taus and
LP corner are the tunables; the noise source and topology are solid.

---

## ASTROIDS — filtered noise, slow amplitude wobble  [SKETCH]

Same MM5837 through Q5's VCA and U7's filter; the netlist shows a static
resistor network (R174/R175/R173) so the "rumble" character comes mostly from
heavy LP filtering. Rendered as ~350 Hz LP noise with a mild 1.1 Hz amplitude
wobble. **Capture board audio before porting** — the wobble rate/depth is a
guess. Reference: `astrob_astroids.wav`. RTL: reuse the LFSR, second LP at
~350 Hz, optional slow triangle on amplitude.

---

## REFILL — CD4017 rising-pitch ladder  [DERIVED architecture, APPROX freqs]

U3 (CD4017) stepped by OSC1 (2.664 Hz; R18=2.7M/C3=0.1µF). Ten outputs
through R8/R7/R9/R12/R14/R6/R10/R11/R15/R13 (18k..330k) sum into Q7's base,
setting U5's rate (U5: R67=10k/R68=82k/C26=.022µF ≈ 377 Hz nominal), chopped
by OSC2 (15.307 Hz) via U9 and mixed with U4 (312 Hz nominal). Net effect: a
chirping tone that **steps up in pitch ~2.7×/s** — the "fuel filling" sound.

```verilog
localparam [22:0] RF_STEP_HALF = 23'd2903244;   // clk/(2*2.664Hz) OSC1
localparam [19:0] RF_CHOP_HALF = 20'd505200;    // clk/(2*15.307Hz) OSC2
// step counter 0..9 (CD4017), reset when !refill_gate (U3.15 tied to I_REFILL)
// freq table: 10 entries, rising; from ladder R ratios (placeholder linear map)
reg [3:0] rf_step;   // advance on OSC1 edge, wrap at 10
wire [16:0] RF_HALF [0:9];   // fill from freq map ~300..1000 Hz
// tone osc at RF_HALF[rf_step], output gated by OSC2 square, decay-free
```
(Ladder-to-frequency mapping is monotonic by R value but the absolute Hz
depend on Q7's bias — tune the 10-entry table by ear against `astrob_refill.wav`
and board audio. Table ROM beats arithmetic here.)

---

## BONUS — 1.5 kHz ping train  [DERIVED]

U6 (R74=4.7k, R75=100k, C31=.0047µF → **1500 Hz**) gated by OSC4 (7.19 Hz;
R80=1M/C35=0.1µF) through R79, with a one-shot decay via U10/C19/D7. Model:
1.5 kHz square, 7.19 Hz 50% gate, overall exponential decay ~1.2 s from
trigger. Reference: `astrob_bonus.wav`. RTL: tone osc (half-period 5156) +
gate osc (half-period 1075751) + retriggerable envelope, same pattern as
LASER's env block.

---

## SONAR — four detuned relaxation oscillators  [SKETCH — MAME's is broken too]

Four identical LM3900-section oscillators (U1/U2) whose behavior depends on
resistor tolerance (`FRND1..10` in the netlist — literally randomized part
values), summed into Q3/Q2/U7. nl_astrob.cpp's own header flags SONAR
triggering as not-right in MAME; **do not treat any emulator as ground truth
here — capture the board.** Rendered as four squares at 790/801/813/826 Hz
with a ping envelope. Reference: `astrob_sonar.wav`. RTL when ready: four
oscillators with slightly different half-periods (prime-ish offsets so they
never lock), shared retriggerable decay.

---

## Integration traps (found in simulation, 2026-08-09)

1. **Power-up mute.** Latches reset to `FF`; bit 5 of $3E is I_MUTE,
   active HIGH — the board powers up muted. Any test that clears only a
   voice bit produces silence. Clear bit 5 explicitly.
2. **Warp rides along.** Bit 7 of $3E is warp, active HIGH. `8'hDE` to
   enable INV1 leaves warp asserted — voice runs at the warp frequency.
   Test vectors for $3E must set bits 5 and 7 deliberately.
3. **`audio_we & ce_cpu` may drop writes** if `audio_we` is a one-cycle
   strobe and `ce_cpu` a separate enable. A dropped "off" write = a sound
   that never stops. Count IOWRs vs latch updates at integration.
4. **Verilog width rule (review checklist for every block here):** any
   `A*B` on the RHS self-determines at max(width(A),width(B)) — it does
   NOT widen to the LHS in compound expressions. This wrapped INV1's
   width multiply (caught in sim: duty pinned at 0.15) and latently the
   LASER and EXPLOSIONS multiplies (fixed above). Pattern: assign the
   product to an explicitly full-width wire first, then slice.

## V generator + mixer note

I_ATTACK_RATE steps U15 (CD4017) through the R152..R161 ladder into U16 → V;
I_RATE_RESET holds U15; warp offsets U16's reference. Once built, feed V into
INV1/2/3/4 as a half-period scale factor (multiply by V-derived 8-bit factor,
same style as INV3's LFO math). Until then the per-voice constants above bake
in V≈7.6 (stuck-at-Q0), which matches all measurements taken so far — i.e.
your captures were taken with the staircase at step 0, so expect all four
invaders to read sharp once V steps during real gameplay.

Mixer: 11 voices at the levels above can sum past ±32767. Scale each voice so
Σ|max| ≤ 30000, or better: add the one-pole HP (the board's C55 coupling)
then a single ÷2. The renders here all include a 20 Hz HP — match it in RTL
or DC offsets from the asymmetric/gated waveforms will eat headroom.
