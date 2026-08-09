//============================================================================
//
//  Astro Blaster audio — nl_astrob.cpp netlist port (in progress)
//
//  MAME emulates this board with a full SPICE-style netlist
//  (Useful Information/mame/nl_astrob.cpp, 1218 lines) of discrete analog
//  circuitry: NE555 timers, an MM5837 noise generator, CD4017/CD4024
//  counters, and passive resistor mixing. There is no sound chip.
//  See Claude/astrob_audio_board_notes_2026-07-26.md for the full scope
//  and the three-route decision (this file implements the "port the
//  netlist to RTL" route).
//
//  Each voice is a digital approximation of its analog stage (RC decay ->
//  leaky counter, 555 astable -> period counter, etc.), not a literal
//  SPICE solve. Building voice-by-voice; status below. Parameters marked
//  #unverified are schematic-derived best guesses per user direction
//  2026-07-26 ("tune later, best shot for now") — expect ear/HW tuning.
//
//  Port $3E (LO) bit -> signal   | Port $3F (HI) bit -> signal
//    0 I_INVADER_1   [DONE]        0 I_LASER_1
//    1 I_INVADER_2   [DONE]        1 I_LASER_2
//    2 I_INVADER_3   [DONE]        2 I_SHORT_EXPL
//    3 I_INVADER_4   [DONE]        3 I_LONG_EXPL
//    4 I_ASTROIDS                  4 I_ATTACK_RATE [DONE] V-generator clock
//    5 I_MUTE        [DONE]        5 I_RATE_RESET  [DONE] V-generator reset
//    6 I_REFILL                    6 I_BONUS
//    7 I_WARP        [DONE, modifier only, no standalone sound]  7 I_SONAR
//  (verified against nl_astrob.cpp ALIAS lines directly — NOT the older
//  segag80r_a.cpp discrete-component driver a previous placeholder
//  borrowed its trigger/decay assumptions and bit mapping from; that
//  mapping was wrong, e.g. it fired "laser" off LO bit7/WARP)
//
//  clk_sys = 15.468480 MHz (SegaG80 core system clock).
//
//============================================================================

module astrob_audio (
    input                     clk_sys,
    input                     reset,

    // Z80 writes to ports $3E (addr=0) / $3F (addr=1)
    input                     audio_we,
    input                     audio_addr,     // 0 = $3E, 1 = $3F
    input               [7:0] audio_din,
    input                     ce_cpu,

    output reg signed  [15:0] audio_out
);

    //------------------------------------------------------------------------
    // Port latches — level state. Most voices on this board are gated
    // directly by a 555's RESET pin (sustained gate), not one-shot
    // triggered; see INVADER_2 below. Reset to all-1s = every active-low
    // gate defaults OFF at power-up.
    //------------------------------------------------------------------------
    reg [7:0] latch_3e, latch_3f;

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            latch_3e <= 8'hFF;
            latch_3f <= 8'hFF;
        end else if (audio_we & ce_cpu) begin
            if (audio_addr == 1'b0) latch_3e <= audio_din;
            else                    latch_3f <= audio_din;
        end
    end

    // I_MUTE = I_LO_D5 directly (no inverting buffer in its path) — active
    // HIGH, per nl_astrob.cpp's MUTEFUNC ("if(A0>2.5,0,A1)"): bit=1 silences
    // the whole mix, bit=0 is normal. The old placeholder had no mute path
    // ("no dedicated SOUND_ON bit" was wrong — I_MUTE genuinely exists).
    wire mute = latch_3e[5];

    //------------------------------------------------------------------------
    // V GENERATOR — U15 CD4017 attack-rate ladder (Sheet 7, middle-bottom).
    // BUILT 2026-07-30. This is the pitch envelope for the ENTIRE invader
    // family: "V" feeds every invader 555's CONTROL VOLTAGE pin, so without
    // it each invader is a flat drone that just holds while its gate is low.
    // Schematic 800-3122 sheet 7 confirms V landing at all four voices:
    // U13.5 (INV2), the U23/U18 pair (INV1), U17 via R53/R54 (INV3), and the
    // U37/U38 section (INV4) — matching nl_astrob.cpp.
    //
    // Circuit: I_ATTACK_RATE clocks U15 (CD4017 decade counter) through a
    // U21 CD4011 pulse shaper; I_RATE_RESET clears it. Exactly one of Q0..Q9
    // is high at a time, each diode-OR'd (D14-D23) through its own resistor
    // into U16's inverting summing node, with R178 (22k) as feedback:
    //
    //   Q0..Q9 -> R161/R160/R159/R155/R153/R156/R158/R157/R154/R152
    //           = 120k 82k 62k 56k 47k 39k 33k 27k 24k 22k   (monotonic!)
    //
    // Lower tap resistance -> more current into the summing node -> lower V
    // -> the 555 charges to a lower threshold -> HIGHER frequency. So pumping
    // ATTACK RATE walks the invader pitch UP in ten discrete steps, and
    // RATE_RESET drops it back to the bottom. That is the classic escalating
    // invader march, and it is the single biggest thing missing from the
    // sustained-drone the voices produce today.
    //
    // ✅ MEASURED, NOT DERIVED. The step table below comes from the real
    // board: "Attack Rate" segment of Useful Information/astrob.wav
    // (167.5s-177.0s, labeled in Claude/astrob_wav_markers_2026-07-26.md as
    // "discrete step changes ... consistent with the CD4017 advancing").
    // Harmonic-sum pitch tracking over that window resolves exactly TEN
    // levels, monotonically rising, then a hard reset back to level 0:
    //
    //   Q0..Q9 f0 = 104.10 106.60 109.60 110.70 113.50
    //               116.90 120.50 126.00 130.40 133.50 Hz   (span 1.2824x)
    //
    // Cross-check: solving the 555 control-voltage equation against the
    // netlist resistor values above predicts a 1.3335x span — within 4% of
    // measurement, using an assumed diode drop. Mechanism confirmed; the
    // MEASURED numbers are what's used here.
    //
    // Stored as Q0-normalized PERIOD multipliers in 1.15 fixed point, so each
    // voice keeps its own already-validated base frequency (which was
    // captured at the reset state = Q0) and is simply scaled.
    //
    // #unverified — one voice's ladder is applied to all four. The real span
    // differs slightly per voice because a 555's discharge phase is
    // V-independent, so each voice's R_A/R_B/C mix weights the effect a
    // little differently. Deriving that per-voice needs the analog solve we
    // deliberately aren't doing; one shared ladder is far closer to the board
    // than today's no-ladder-at-all.
    //------------------------------------------------------------------------

    // I_RATE_RESET = ALIAS(U31.12): 7406 INVERTING open-collector + R96 10k
    // pull-up into U15 pin 15 (RESET, active HIGH on a CD4017).
    //   port bit 0 -> buffer off -> pull-up wins -> pin 15 HIGH -> held at Q0
    //   port bit 1 -> buffer pulls low        -> reset released -> counter runs
    wire v_rate_reset = ~latch_3f[5];

    // I_ATTACK_RATE = ALIAS(U26.2): 7407 NON-inverting open-collector, so it
    // follows port bit 4 directly, then through U21 (CD4011) + R148/R166/C67
    // as an edge-triggered pulse shaper into U15 pin 14 (CLOCK).
    // #unverified: the shaper's output edge polarity isn't derivable without
    // an analog solve. Modeled as advance-on-rising-edge of the raw port bit;
    // if the ramp lands one step out of phase, flip this edge.
    // Resets to 1'b1, NOT 1'b0: latch_3f powers up as 8'hFF, so bit 4 already
    // reads high out of reset. Initializing this to 0 manufactures a phantom
    // rising edge on the first clock and the ladder starts life on Q1 instead
    // of Q0 — caught in Verilator (verilator/vgen), every step was off by one.
    reg  attack_rate_d;
    wire v_clk = latch_3f[4] & ~attack_rate_d;

    // U15 pin 13 (CLOCK INHIBIT) is tied to GND, so the counter is never
    // gated and genuinely wraps Q9 -> Q0 rather than saturating.
    reg [3:0] v_step;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            v_step        <= 4'd0;
            attack_rate_d <= 1'b1;   // match latch_3f[4]'s 8'hFF power-up value
        end else begin
            attack_rate_d <= latch_3f[4];
            if (v_rate_reset)   v_step <= 4'd0;
            else if (v_clk)     v_step <= (v_step == 4'd9) ? 4'd0 : v_step + 4'd1;
        end
    end

    // Period multiplier, Q0-normalized, 1.15 fixed point (32768 = 1.0).
    reg [15:0] v_mult;
    always @(*) begin
        case (v_step)
            4'd0:    v_mult = 16'd32768;   // 104.10 Hz  (reset state)
            4'd1:    v_mult = 16'd32000;   // 106.60 Hz
            4'd2:    v_mult = 16'd31124;   // 109.60 Hz
            4'd3:    v_mult = 16'd30814;   // 110.70 Hz
            4'd4:    v_mult = 16'd30054;   // 113.50 Hz
            4'd5:    v_mult = 16'd29180;   // 116.90 Hz
            4'd6:    v_mult = 16'd28308;   // 120.50 Hz
            4'd7:    v_mult = 16'd27073;   // 126.00 Hz
            4'd8:    v_mult = 16'd26159;   // 130.40 Hz
            4'd9:    v_mult = 16'd25552;   // 133.50 Hz
            default: v_mult = 16'd32768;
        endcase
    end

    //------------------------------------------------------------------------
    // INVADER_2 (nl_astrob.cpp Sheet 8, middle) — DONE, VALIDATED against
    // real captured audio 2026-07-26 (Claude/astrob_wav_markers_2026-07-26.md,
    // isolated "Invader 2" test-mode segment, 02:11.380-02:15.895).
    //
    // I_INVADER_2 (ALIAS = U31.4, a 7406 open-collector inverter with a
    // 100k pull-up to +12V) drives U13's 555 RESET pin directly. Traced
    // through the buffer's inverting + open-collector polarity: raw port
    // bit 0 -> RESET released -> oscillator runs continuously. Bit 1 ->
    // RESET held -> silent immediately. SUSTAINED GATE, not a one-shot —
    // a different interaction model than the old placeholder assumed for
    // every voice.
    //
    // U13 astable: R_A=R81(10k) VCC->discharge, R_B=R82(100k)
    // discharge->threshold, C=C36(2200pF).
    //   f = 1.44 / ((R_A + 2*R_B) * C) = ~3117 Hz nominal.
    // U13's output clocks a CD4024 ripple counter (U12); OSC3 (15.3 Hz,
    // value given directly in the netlist comment) periodically resets it,
    // and four counter-stage taps are resistor-summed (R47=10k, R48=82k,
    // R49=39k, R50=22k) for timbre.
    //
    // VALIDATION RESULT: measured "Invader 2" peaks are 45.9/76.5/107.1/
    // 183.5/198.8/214.1/382.6/397.9 Hz. Back-computing the 555 base rate
    // from this model's own bit3/4/5 taps (base/16, base/32, base/64)
    // against the three cleanest peaks gives ~3181/3427/2938 Hz -- all
    // within ~10% of the 3117 Hz formula estimate, i.e. the architecture
    // (base oscillator + this exact tap spacing) predicts the right
    // sub-harmonic structure. Not pin-exact-confirmed against a CD4024
    // datasheet, but no longer a blind guess either -- keeping bits
    // 3/4/5/6 and the 3117 Hz nominal as-is; the gap is inside measurement
    // noise, not a real error.
    //
    // CORRECTED REASONING (previous version of this comment was wrong):
    // earlier text here claimed V-modulation would make real pitch
    // "LOWER than 3117 Hz nominal" by implication of a large shift. That
    // compared the PRE-divider 555 rate to the POST-divider audible
    // output -- apples to oranges. Once divided by this model's own taps,
    // 3117 Hz already lands in the measured range; V's actual effect is
    // apparently much smaller than feared. "V" (R71 -> U13 pin 5 CONTROL
    // VOLTAGE, from the attack-rate/rate-reset subsystem, U15 CD4017 +
    // resistor ladder) is still NOT modeled -- deferred until that
    // subsystem is built -- but don't assume it needs a big correction
    // when it lands.
    //
    // WARP NOTE (corrected -- see below): user reports "Warp Invader 2" is
    // perceptually the SAME tone as plain Invader 2, just "duller", not a
    // separate sound layered in. Confirmed why: I_WARP feeds R164 into
    // U16 pin 5, the SAME op-amp (U16) whose pin 6 sums the CD4017
    // attack-rate resistor ladder, producing "V" at U16.7. "V" feeds every
    // invader's 555 control-voltage pin (this one via R71). So warp
    // retunes ALL FOUR invaders through the shared V signal -- no direct
    // per-voice wire needed for the effect to be real. (Initial read of
    // this data wrongly concluded "no wire in INVADER_2's own netlist
    // section = separate sound" -- checked the wrong thing; V is the
    // path.) Consequence: once the V generator (CD4017 ladder + this
    // warp-summing op-amp) is built once, all four invaders inherit
    // correct warp behavior automatically. The "Warp Invader N" measured
    // peaks in astrob_wav_markers_2026-07-26.md are valid ground truth for
    // V-with-warp-engaged, not contaminated data -- useful for calibrating
    // U16's mixing ratio when V gets built.
    //------------------------------------------------------------------------

    wire inv2_gate = ~latch_3e[1];

    // Base = V-ladder step Q0 (the RATE_RESET state the wav capture was made
    // in); scaled by v_mult for steps Q1..Q9 — see V GENERATOR above.
    localparam [15:0] INV2_HALF_PERIOD = 16'd2481;   // clk_sys/(2*3117Hz), nominal

    wire [31:0] inv2_hp_scaled  = INV2_HALF_PERIOD * v_mult;
    wire [15:0] inv2_half_period = inv2_hp_scaled[30:15];

    reg [15:0] inv2_osc_cnt;
    reg        inv2_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv2_osc_cnt <= INV2_HALF_PERIOD;
            inv2_osc_out <= 1'b0;
        end else if (!inv2_gate) begin
            inv2_osc_cnt <= inv2_half_period;
            inv2_osc_out <= 1'b0;
        end else if (inv2_osc_cnt == 16'd0) begin
            inv2_osc_cnt <= inv2_half_period;
            inv2_osc_out <= ~inv2_osc_out;
        end else begin
            inv2_osc_cnt <= inv2_osc_cnt - 16'd1;
        end
    end

    reg inv2_osc_out_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) inv2_osc_out_d <= 1'b0;
        else       inv2_osc_out_d <= inv2_osc_out;
    end
    wire inv2_osc_rise = inv2_osc_out & ~inv2_osc_out_d;

    localparam [20:0] INV2_RESET_PERIOD = 21'd1011011;  // clk_sys/15.3Hz (OSC3)

    reg [20:0] inv2_reset_cnt;
    wire       inv2_reset_pulse = (inv2_reset_cnt == 21'd0);
    always @(posedge clk_sys or posedge reset) begin
        if (reset)                      inv2_reset_cnt <= INV2_RESET_PERIOD;
        else if (!inv2_gate)            inv2_reset_cnt <= INV2_RESET_PERIOD;
        else if (inv2_reset_pulse)      inv2_reset_cnt <= INV2_RESET_PERIOD;
        else                            inv2_reset_cnt <= inv2_reset_cnt - 21'd1;
    end

    reg [6:0] inv2_div;   // CD4024 7-stage ripple counter equivalent
    always @(posedge clk_sys or posedge reset) begin
        if (reset)                             inv2_div <= 7'd0;
        else if (!inv2_gate || inv2_reset_pulse) inv2_div <= 7'd0;
        else if (inv2_osc_rise)                inv2_div <= inv2_div + 7'd1;
    end

    // Weighted bipolar sum of 4 tap bits, weights ~ 1/R rounded to small
    // integers (R47=10k:8, R50=22k:4, R49=39k:2, R48=82k:1). Range -15..+15.
    //
    // ⛔ TAP REMAP TRIED AND REJECTED 2026-07-30 — DO NOT REDO IT NAIVELY.
    // A sweep of all 840 assignments of these weights onto 4 of the 7 counter
    // stages, scored by spectral RMS against the real "Invader 2" capture,
    // confidently recommended w8->Q5, w4->Q6 (unanimous across two runs, RMS
    // 21.9 -> 14.5 dB). It is WRONG, and the metric is why: it compared full
    // log-spectra including the noise floor between harmonics. The real
    // capture has a noise floor; a synthetic voice does not. So the score
    // rewarded whichever mapping produced the DENSEST harmonic comb (heavy
    // weights on slow stages) simply because that fills the gaps — not
    // because it sounds more alike.
    //
    // The direct evidence says the opposite and outranks the fit: the real
    // voice's perceived fundamental is 199.0 Hz ~= base/16 = 3117/16 = 194.8,
    // and the perceived fundamental follows the HEAVIEST tap. That puts w8 on
    // Q3 (divide-by-16) — the mapping already here. Rendering the remapped RTL
    // confirmed it: f0 fell to 76.5 Hz against the real 199.0 Hz, i.e. audibly
    // the wrong pitch, in exchange for a better-looking RMS number.
    //
    // If this is ever revisited: score against harmonic amplitudes at
    // multiples of the measured f0, or add a matched noise floor to the
    // synthetic — and require the perceived f0 to land on 199 Hz. The stage
    // assignment for the two LIGHT taps is still genuinely unknown; the fit
    // couldn't resolve them either (Q0/Q1/Q2 near-tied).
    //------------------------------------------------------------------------
    // CD4024 tap ladder — rebuilt as a true binary DAC 2026-08-08.
    //
    // U12 is a weighted-resistor DAC on Q1-Q4: R47 10k / R50 22k / R49 39k /
    // R48 82k => weights 8/4/2/1. In a ripple counter Q1 is FASTEST, so a
    // binary ramp needs the MSB on the SLOWEST of the four and the LSB on the
    // fastest. That reconstructs a sawtooth at the MSB rate with a full
    // harmonic series; the old mapping put the 3 light taps on stages SLOWER
    // than the MSB, which is not a binary count at all -- a scrambled
    // staircase, not a ramp.
    //
    // ⚠️ This is NOT the 2026-07-30 remap that was tried and REJECTED. That one
    // moved the HEAVY taps onto slow stages (w8->Q5, w4->Q6) and collapsed f0
    // from 199 Hz to 76.5 Hz. This keeps w8 exactly where it is, on div[3] =
    // base/16 = 194.8 Hz vs the real voice's measured f0 199.0 Hz, so the one
    // load-bearing pitch constraint is untouched. Only the three LIGHT taps
    // move -- the ones the 840-way sweep could never resolve (Q0/Q1/Q2/Q3
    // near-tied) and which are therefore not being over-fitted, just placed
    // where the circuit topology says they go.
    //
    // Same shape already validated on INVADER_1 (w8->div[5] slowest ...
    // w1->div[2] fastest), where it fixed that voice's dominant partial.
    //------------------------------------------------------------------------
    // DIAG-REVERT-2026-08-08: original scrambled ladder below, uncomment to restore
    // wire signed [4:0] inv2_tap_sum =
    //     (inv2_div[3] ? 5'sd8 : -5'sd8) +
    //     (inv2_div[4] ? 5'sd2 : -5'sd2) +
    //     (inv2_div[5] ? 5'sd4 : -5'sd4) +
    //     (inv2_div[6] ? 5'sd1 : -5'sd1);
    wire signed [4:0] inv2_tap_sum =
        (inv2_div[3] ? 5'sd8 : -5'sd8) +   // Q4, R47 10k (MSB) - base/16 = 194.8 Hz
        (inv2_div[2] ? 5'sd4 : -5'sd4) +   // Q3, R50 22k
        (inv2_div[1] ? 5'sd2 : -5'sd2) +   // Q2, R49 39k
        (inv2_div[0] ? 5'sd1 : -5'sd1);    // Q1, R48 82k (LSB)

    wire signed [15:0] inv2_mix = inv2_tap_sum * 16'sd700;
    wire signed [15:0] inv2_out = inv2_gate ? inv2_mix : 16'sd0;

    // Gate signals for the other three invaders. Same pull-up +
    // inverting-open-collector-buffer pattern confirmed for every
    // I_INVADER_n in nl_astrob.cpp (all four share chip U31 in the ALIAS
    // list, each with its own pull-up: R73/R70/R23/R88) — bit=0 -> run,
    // bit=1 -> silent, identical to INVADER_2 above.
    wire inv1_gate = ~latch_3e[0];
    wire inv3_gate = ~latch_3e[2];
    wire inv4_gate = ~latch_3e[3];

    // WARP ("W" = ALIAS(W, I_LO_D7), the RAW un-inverted port bit per
    // nl_astrob.cpp — NOT the same signal as "I_WARP" a few lines later in
    // the netlist, which is I_LO_D7 inverted through U31 and feeds the
    // shared V op-amp instead). Active HIGH. No standalone "WARP" sound
    // exists in the mixer net list (checked: only SONAR/LASER_1/LASER_2/
    // REFILL/EXPLOSIONS/ASTROIDS/V) — warp is purely a modifier on other
    // voices, not its own voice.
    wire warp_active = latch_3e[7];

    //------------------------------------------------------------------------
    // INVADER_1 (nl_astrob.cpp Sheet 8, middle-top) — DONE, APPROXIMATED
    // (not a literal port). Real circuit is TWO cascaded 555s (U23
    // free-running, retriggering a shaped monostable-ish U18 through a
    // transistor network, Q8) — too analog-dependent to derive with
    // confidence without simulation.
    //
    // Modeled instead as the SAME divided-tap architecture validated for
    // INVADER_2, fit directly to the measured "Invader 1" test-mode audio
    // (Claude/astrob_wav_markers_2026-07-26.md, 02:01.295-02:06.385):
    // peaks 99.2/101.6/104.3/106.7/109.4/208.6/312.7/417.0 Hz.
    // Back-computed base from this model's own bit3/4/5 taps (base/16,
    // base/32, base/64): 6672/6675/6675 Hz -- tightly self-consistent,
    // using 6674 Hz.
    //
    // HAS a direct WARP path in the real circuit (NET_C(W, U30.5)) on top
    // of the shared-V effect every invader gets -- matches a clearly
    // measurable shift in "Warp Invader 1" (86.8/88.6/90.3/92.2/94.1/
    // 180.8/271.1/361.6 Hz, back-computed base ~5784 Hz, ~13.4% lower).
    // Modeled as a discrete base-frequency switch on I_WARP, not a
    // continuous function of V (V generator not built yet). No periodic
    // counter-reset here (unlike INVADER_2's OSC3) -- this divider doesn't
    // correspond to a real counter chip, so there's no real reset
    // mechanism to match; it free-runs while gated.
    //------------------------------------------------------------------------
    localparam [15:0] INV1_HALF_PERIOD_NORM = 16'd1159;  // clk_sys/(2*6674Hz)
    localparam [15:0] INV1_HALF_PERIOD_WARP = 16'd1337;  // clk_sys/(2*5784Hz), ~13.4% lower

    // Warp picks the base, then the shared V ladder scales it. The two
    // compose multiplicatively here; on the real board warp shifts U16's
    // reference so it biases the whole ladder. Keeping the measured-and-fit
    // per-voice warp switch rather than folding warp into V — that path's
    // sign is still unresolved (see NOTE at end of file).
    wire [15:0] inv1_half_period_base = warp_active ? INV1_HALF_PERIOD_WARP : INV1_HALF_PERIOD_NORM;

    wire [31:0] inv1_hp_scaled   = inv1_half_period_base * v_mult;
    wire [15:0] inv1_half_period = inv1_hp_scaled[30:15];

    reg [15:0] inv1_osc_cnt;
    reg        inv1_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv1_osc_cnt <= INV1_HALF_PERIOD_NORM;
            inv1_osc_out <= 1'b0;
        end else if (!inv1_gate) begin
            inv1_osc_cnt <= inv1_half_period;
            inv1_osc_out <= 1'b0;
        end else if (inv1_osc_cnt == 16'd0) begin
            inv1_osc_cnt <= inv1_half_period;
            inv1_osc_out <= ~inv1_osc_out;
        end else begin
            inv1_osc_cnt <= inv1_osc_cnt - 16'd1;
        end
    end

    reg inv1_osc_out_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) inv1_osc_out_d <= 1'b0;
        else       inv1_osc_out_d <= inv1_osc_out;
    end
    wire inv1_osc_rise = inv1_osc_out & ~inv1_osc_out_d;

    reg [6:0] inv1_div;
    always @(posedge clk_sys or posedge reset) begin
        if (reset)                inv1_div <= 7'd0;
        else if (!inv1_gate)      inv1_div <= 7'd0;
        else if (inv1_osc_rise)   inv1_div <= inv1_div + 7'd1;
    end

    // TAPS REASSIGNED 2026-07-30. Was w8->div[3], which put the dominant
    // partial at base/16 = 417 Hz. Measured against the board capture, the
    // real voice's dominant partial is 104.4 Hz and ours was 416.7 Hz — a
    // factor of almost exactly 4, i.e. the heaviest tap was two stages too
    // fast. The measured peak list for the real voice (99.2/101.6/104.3/
    // 106.7/109.4/208.6/312.7/417.0 Hz) contains 104.3, 208.6 and 417.0
    // outright, and those ARE div[5], div[4] and div[3] of this 6674 Hz base.
    // So weights descend across ascending speed, dominant on div[5]:
    wire signed [4:0] inv1_tap_sum =
        (inv1_div[5] ? 5'sd8 : -5'sd8) +   // base/64  = 104.3 Hz (dominant)
        (inv1_div[4] ? 5'sd4 : -5'sd4) +   // base/32  = 208.6 Hz
        (inv1_div[3] ? 5'sd2 : -5'sd2) +   // base/16  = 417.0 Hz
        (inv1_div[2] ? 5'sd1 : -5'sd1);    // base/8   = 834.3 Hz

    //------------------------------------------------------------------------
    // INVADER_1 RETRIGGER ENVELOPE — the "WooWooWoo", built 2026-07-30.
    //
    // User listened to the isolated captures and reported the real voice goes
    // "WooWooWooWooWoo" while ours was a flat "Wooooooo". They were right, and
    // it matches the real topology: U23 free-runs and RETRIGGERS the shaped
    // monostable U18 through Q8 — a repeating burst, not a sustained tone. The
    // old model had no modulator at all (measured env_mod 0.015), because it
    // borrowed INVADER_2's divided-tap architecture wholesale.
    //
    // Measured off ab_wavs/real_inv1.wav, band-limited to 80-130 Hz so
    // broadband content can't bias the envelope, and excluding the clip's
    // ~1.25 s of quiet lead-in (that lead-in is what made an earlier pass
    // report a spurious 0.73 Hz — it biased the slow end of the FFT):
    //   rate  = 2.56 Hz (one every 390 ms), 2nd harmonic at 5.13 Hz present
    //           so the shape is pulse-like, not sinusoidal
    //   depth = 93% (78% swing on the folded median)
    //
    // The 16 gains below ARE the measured folded envelope, normalised to its
    // own peak. Free-running and NOT gated, matching U23 on the real board.
    //------------------------------------------------------------------------
    localparam [19:0] INV1_ENV_STEP = 20'd377648;  // clk_sys/(2.56Hz * 16)

    reg [19:0] inv1_env_cnt;
    reg [3:0]  inv1_env_idx;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv1_env_cnt <= INV1_ENV_STEP;
            inv1_env_idx <= 4'd0;
        end else if (inv1_env_cnt == 20'd0) begin
            inv1_env_cnt <= INV1_ENV_STEP;
            inv1_env_idx <= inv1_env_idx + 4'd1;
        end else begin
            inv1_env_cnt <= inv1_env_cnt - 20'd1;
        end
    end

    reg [7:0] inv1_env;
    always @(*) begin
        case (inv1_env_idx)
            4'd0:  inv1_env = 8'd224;
            4'd1:  inv1_env = 8'd223;
            4'd2:  inv1_env = 8'd221;
            4'd3:  inv1_env = 8'd229;
            4'd4:  inv1_env = 8'd224;
            4'd5:  inv1_env = 8'd215;
            4'd6:  inv1_env = 8'd222;
            4'd7:  inv1_env = 8'd252;
            4'd8:  inv1_env = 8'd232;
            4'd9:  inv1_env = 8'd146;   // burst decays
            4'd10: inv1_env = 8'd73;
            4'd11: inv1_env = 8'd57;    // quietest point of the "Woo"
            4'd12: inv1_env = 8'd97;
            4'd13: inv1_env = 8'd170;   // retrigger
            4'd14: inv1_env = 8'd232;
            4'd15: inv1_env = 8'd255;
            default: inv1_env = 8'd224;
        endcase
    end

    wire signed [15:0] inv1_mix_raw = inv1_tap_sum * 16'sd700;
    wire signed [24:0] inv1_mix_env = inv1_mix_raw * $signed({1'b0, inv1_env});
    wire signed [15:0] inv1_mix     = inv1_mix_env[23:8];
    wire signed [15:0] inv1_out = inv1_gate ? inv1_mix : 16'sd0;

    //------------------------------------------------------------------------
    // INVADER_3 (nl_astrob.cpp Sheet 8, top-right) — DONE, VALIDATED.
    // Real circuit is a single 555 (U17) through a shared TL084 filter
    // stage (U22, also used by INVADER_1) -- genuinely simpler than
    // INVADER_1/2 (no CD4024/divider/cascade at all).
    //
    // Measured "Invader 3" test audio (Claude/astrob_wav_markers_2026-07-26.md,
    // 02:20.410-02:24.870): 99.5/108.5/109.2/117.1/307.5/316.2/333.8/342.7
    // Hz. This is a fundamental cluster (~99.5-117.1) plus its natural 3rd
    // harmonic (~307.5-342.7, ratio ~3x) -- exactly what a plain
    // square-wave oscillator produces on its own via odd harmonics, no
    // divider/tap-mixing needed to explain it, consistent with the
    // simpler real circuit. Modeled as a single gated square-wave
    // oscillator at ~108.5 Hz (cluster center).
    //
    // HAS a direct WARP path (NET_C(W, U30.9)), matching a measurable
    // shift in "Warp Invader 3" (90.1/95.2/100.1/105.2/110.3/285.5/300.6/
    // 315.9 Hz, ~100.1 Hz center, ~7.7% lower). Modeled as a discrete
    // base-frequency switch, same approach as INVADER_1.
    //------------------------------------------------------------------------
    localparam [16:0] INV3_HALF_PERIOD_NORM = 17'd71285;  // clk_sys/(2*108.5Hz)
    localparam [16:0] INV3_HALF_PERIOD_WARP = 17'd77266;  // clk_sys/(2*100.1Hz), ~7.7% lower

    //------------------------------------------------------------------------
    // INVADER_3 FM WARBLE — added 2026-08-08.
    //
    // The "fundamental cluster" described above is NOT a cluster: it is an FM
    // SIDEBAND COMB, and the comb spacing is the modulation rate. Measured off
    // ab_wavs/real_inv3.wav (48 kHz, 4.46 s, 0.046 Hz bins):
    //   fundamental : 99.6 / 108.4 / 117.2 / 126.0 Hz   dB rel -7 / 0 / -7 / -21
    //   3rd harmonic: 298.6 307.4 316.3 325.3 333.9 342.7 351.6, spacing ~8.8
    //   => carrier 108.4 Hz, modulation rate 8.8 Hz
    //
    // It is FM, not AM, confirmed three ways:
    //   J1/J0 = -7 dB  -> beta ~ 0.82
    //   J2/J0 = -21 dB -> beta ~ 0.80
    //   at 3x the harmonic the CARRIER (325.3) collapses to -24 dB while its
    //   sidebands dominate. Deviation triples at 3x so beta3 = 2.40, and the
    //   first Bessel null of J0 is 2.405. AM cannot null a carrier.
    // => peak deviation = beta * f_mod = 0.8 * 8.8 = ~7.0 Hz (6.46% of carrier).
    //
    // Topology (external analysis, 2026-08-08): U22 sections A+B (R24 2.2M,
    // C8/C9 0.1uF) form a slow relaxation oscillator sweeping U17's CV pin
    // through C12/R54. A relaxation oscillator's cap voltage is a TRIANGLE,
    // rounded by the RC -- hence a triangle modulator here, not a LUT.
    //
    // WARP: rate drops to 5.05 Hz (header peak list 90.1/95.2/100.1/105.2/110.3,
    // spacing ~5.05, carrier 100.1). Deviation held at the same FRACTION of
    // carrier (6.46%), which raises beta to ~1.28 and predicts the stronger 2nd
    // sidebands that list shows. #unverified -- no isolated warp capture exists.
    //------------------------------------------------------------------------
    // 32-bit phase accumulator: inc = f_mod * 2^32 / 15468480
    localparam [31:0] INV3_FM_INC_NORM = 32'd2443;   //  8.798 Hz
    localparam [31:0] INV3_FM_INC_WARP = 32'd1402;   //  5.049 Hz
    // half-period at the LOW-frequency end of the swing, and span across it.
    // Deviation trimmed 2026-08-08 against the real capture: span 36 (+-7.0 Hz)
    // rendered 1st sidebands at -9 dB vs the board's -7, i.e. beta_eff ~0.68 not
    // 0.82 -- a TRIANGLE modulator spreads shallower than the sine the Bessel
    // maths assumes, so it needs ~21% more deviation to hit the same sideband
    // depth. +-8.5 Hz (7.84% of carrier); warp holds the same FRACTION.
    // ...then both endpoints trimmed 0.46% to correct a SYSTEMATIC flat carrier:
    // the triangle sweeps HALF-PERIOD linearly, which is not symmetric in
    // FREQUENCY, so the time-average frequency sits below the mean of the two
    // endpoints (harmonic-mean effect). Rendered 107.9 Hz vs the board's 108.4.
    localparam [16:0] INV3_FM_HP_LO_NORM = 17'd77060; // 100.4 Hz endpoint
    localparam [16:0] INV3_FM_HP_LO_WARP = 17'd83454; //  92.7 Hz endpoint
    localparam [7:0]  INV3_FM_SPAN_NORM  = 8'd44;     // *255 -> 66197 = 116.8 Hz
    localparam [7:0]  INV3_FM_SPAN_WARP  = 8'd48;     // *255 -> 71600 = 108.0 Hz

    wire [31:0] inv3_fm_inc   = warp_active ? INV3_FM_INC_WARP   : INV3_FM_INC_NORM;
    wire [16:0] inv3_fm_hp_lo = warp_active ? INV3_FM_HP_LO_WARP : INV3_FM_HP_LO_NORM;
    wire [7:0]  inv3_fm_span  = warp_active ? INV3_FM_SPAN_WARP  : INV3_FM_SPAN_NORM;

    reg [31:0] inv3_fm_phase;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) inv3_fm_phase <= 32'd0;
        else       inv3_fm_phase <= inv3_fm_phase + inv3_fm_inc;
    end

    // triangle 0..255 from the accumulator (free-running, like U22 on the board)
    wire [7:0] inv3_fm_ramp = inv3_fm_phase[30:23];
    wire [7:0] inv3_fm_tri  = inv3_fm_phase[31] ? ~inv3_fm_ramp : inv3_fm_ramp;
    wire [15:0] inv3_fm_off = inv3_fm_tri * inv3_fm_span;

    // DIAG-REVERT-2026-08-08: original static base below, uncomment to restore
    // wire [16:0] inv3_half_period_base = warp_active ? INV3_HALF_PERIOD_WARP : INV3_HALF_PERIOD_NORM;
    wire [16:0] inv3_half_period_base = inv3_fm_hp_lo - {1'b0, inv3_fm_off};

    wire [32:0] inv3_hp_scaled   = inv3_half_period_base * v_mult;
    wire [16:0] inv3_half_period = inv3_hp_scaled[31:15];

    reg [16:0] inv3_osc_cnt;
    reg        inv3_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv3_osc_cnt <= INV3_HALF_PERIOD_NORM;
            inv3_osc_out <= 1'b0;
        end else if (!inv3_gate) begin
            inv3_osc_cnt <= inv3_half_period;
            inv3_osc_out <= 1'b0;
        end else if (inv3_osc_cnt == 17'd0) begin
            inv3_osc_cnt <= inv3_half_period;
            inv3_osc_out <= ~inv3_osc_out;
        end else begin
            inv3_osc_cnt <= inv3_osc_cnt - 17'd1;
        end
    end

    wire signed [15:0] inv3_out = inv3_gate ? (inv3_osc_out ? 16'sd8000 : -16'sd8000) : 16'sd0;

    //------------------------------------------------------------------------
    // INVADER_4 (nl_astrob.cpp Sheet 8, middle-bottom) — DONE, APPROXIMATED
    // (known gap, see below). Real circuit: U37 free-runs continuously
    // (never gated) and clocks a CD4024 (U28) that self-resets via its own
    // Q5 output (a mod-5 ring, NOT an external periodic reset like
    // INVADER_2's OSC3). The divided output feeds U38's CONTROL VOLTAGE
    // pin (U38.5), not directly into the audio mix like INVADER_2's taps
    // -- U38 is the actual GATED/audible oscillator (I_INVADER_4 resets
    // U38.4), slowly warbled by U37/U28's output rather than harmonically
    // stacked with it.
    //
    // (Was a KNOWN GAP: the warble is now built, see below. The old model was
    // a single gated oscillator at ~771 Hz -- the average of the measured
    // peaks 681.7...890.7 Hz -- which put it in the right register but made it
    // a motionless tone. Averaging the peaks was the mistake: that spread
    // wasn't measurement scatter, it WAS the warble.)
    //
    // No direct WARP path in the netlist for this voice (only the
    // shared-V path, like INVADER_2) -- measured warp shift ("Warp
    // Invader 4": 664.5-814.2 Hz average ~745 Hz, ~3.4% lower) is inside
    // likely measurement noise. Not modeled; same voice used regardless
    // of I_WARP, consistent with INVADER_2's treatment.
    //------------------------------------------------------------------------
    // WARBLE BUILT 2026-07-30 — this was the "KNOWN GAP" above. U37 free-runs
    // (never gated) clocking U28, whose output drives U38's CONTROL VOLTAGE.
    // Recovered the modulator's actual SHAPE from the board capture rather
    // than inferring it from harmonic ratios: took the instantaneous-frequency
    // track of the isolated "Invader 4" segment and folded it over the
    // modulation period. Result is NOT the staircase/sawtooth the harmonics
    // suggested — it's a clean TWO-LEVEL square at 39.79 Hz alternating
    // between ~704 Hz and ~886 Hz (the apparent ramps between the two plateaus
    // are analysis smearing: a 16 ms window can't resolve edges on a 25 ms
    // period). That's a single CD4024 tap square-waving the control pin.
    // Reproduce with verilator/vgen/fm_shape.py.
    //
    // The old fixed 771 Hz sat near the middle of this and never moved, which
    // is why a held gate sounded like a steady beep: measured env_mod on the
    // real voice is 0.389, ours was 0.000.
    localparam [17:0] INV4_WARBLE_HALF = 18'd194376;  // clk_sys/(2*39.79Hz)
    localparam [13:0] INV4_HP_LO_PITCH = 14'd10986;   // 704 Hz plateau
    localparam [13:0] INV4_HP_HI_PITCH = 14'd8729;    // 886 Hz plateau

    reg [17:0] inv4_warble_cnt;
    reg        inv4_warble;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv4_warble_cnt <= INV4_WARBLE_HALF;
            inv4_warble     <= 1'b0;
        end else if (inv4_warble_cnt == 18'd0) begin
            inv4_warble_cnt <= INV4_WARBLE_HALF;
            inv4_warble     <= ~inv4_warble;   // U37/U28 free-run: NOT gated
        end else begin
            inv4_warble_cnt <= inv4_warble_cnt - 18'd1;
        end
    end

    wire [13:0] inv4_half_period_base =
        inv4_warble ? INV4_HP_HI_PITCH : INV4_HP_LO_PITCH;

    wire [29:0] inv4_hp_scaled   = inv4_half_period_base * v_mult;
    wire [13:0] inv4_half_period = inv4_hp_scaled[28:15];

    reg [13:0] inv4_osc_cnt;
    reg        inv4_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv4_osc_cnt <= INV4_HP_LO_PITCH;
            inv4_osc_out <= 1'b0;
        end else if (!inv4_gate) begin
            inv4_osc_cnt <= inv4_half_period;
            inv4_osc_out <= 1'b0;
        end else if (inv4_osc_cnt == 14'd0) begin
            inv4_osc_cnt <= inv4_half_period;
            inv4_osc_out <= ~inv4_osc_out;
        end else begin
            inv4_osc_cnt <= inv4_osc_cnt - 14'd1;
        end
    end

    wire signed [15:0] inv4_out = inv4_gate ? (inv4_osc_out ? 16'sd8000 : -16'sd8000) : 16'sd0;

    //------------------------------------------------------------------------
    // Remaining voices — not yet ported, silent for now.
    //   $3E: I_ASTROIDS, I_REFILL
    //   $3F: I_LASER_1, I_LASER_2, I_SHORT_EXPL, I_LONG_EXPL, I_BONUS,
    //        I_SONAR
    //   ($3F bits 4/5, I_ATTACK_RATE/I_RATE_RESET, are NOT voices — they
    //   drive the V generator, which is now built at the top of this file.)
    //   MAME's own nl_astrob.cpp header documents SONAR/BONUS triggering
    //   as broken in MAME itself — don't treat MAME audio as ground truth
    //   for those two when they're eventually built.
    //
    // NOTE — unresolved warp-via-V sign (does NOT block anything above).
    // On the schematic, I_WARP sums through R164 (10k) into U16 pin 5,
    // shifting the ladder's reference from ~8.16 V toward ~6.19 V, which by
    // the 555 control-voltage equation should RAISE invader pitch. But the
    // measured "Warp Invader" captures show pitch going DOWN (INV1 -13.4%,
    // INV3 -7.7%). Those two voices also have their own direct W paths
    // (U30.5 / U30.9) which is what the per-voice warp switches above are
    // fit to, so the discrepancy is confined to the shared-V leg and the
    // fitted behavior is the one that matches real audio. Leaving warp out
    // of the V generator until that sign is settled — do not "fix" the
    // per-voice switches to match the derivation without new measurements.
    //------------------------------------------------------------------------

    //------------------------------------------------------------------------
    // Mix
    //------------------------------------------------------------------------
    wire signed [17:0] voice_sum = inv1_out + inv2_out + inv3_out + inv4_out;
    wire signed [15:0] voice_sum_clamped =
        (voice_sum >  18'sd32767) ?  16'sd32767 :
        (voice_sum < -18'sd32768) ? -16'sd32768 :
                                     voice_sum[15:0];

    always @(posedge clk_sys or posedge reset) begin
        if (reset)
            audio_out <= 16'sd0;
        else
            audio_out <= mute ? 16'sd0 : voice_sum_clamped;
    end

endmodule
