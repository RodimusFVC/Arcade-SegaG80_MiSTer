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
//    4 I_ASTROIDS                  4 I_ATTACK_RATE (V-generator input, not built)
//    5 I_MUTE        [DONE]        5 I_RATE_RESET  (V-generator input, not built)
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

    localparam [15:0] INV2_HALF_PERIOD = 16'd2481;   // clk_sys/(2*3117Hz), nominal

    reg [15:0] inv2_osc_cnt;
    reg        inv2_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv2_osc_cnt <= INV2_HALF_PERIOD;
            inv2_osc_out <= 1'b0;
        end else if (!inv2_gate) begin
            inv2_osc_cnt <= INV2_HALF_PERIOD;
            inv2_osc_out <= 1'b0;
        end else if (inv2_osc_cnt == 16'd0) begin
            inv2_osc_cnt <= INV2_HALF_PERIOD;
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
    // integers (R47=10k:8, R49=39k:2, R50=22k:4, R48=82k:1). Range -15..+15.
    wire signed [4:0] inv2_tap_sum =
        (inv2_div[3] ? 5'sd8 : -5'sd8) +
        (inv2_div[4] ? 5'sd2 : -5'sd2) +
        (inv2_div[5] ? 5'sd4 : -5'sd4) +
        (inv2_div[6] ? 5'sd1 : -5'sd1);

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

    wire [15:0] inv1_half_period = warp_active ? INV1_HALF_PERIOD_WARP : INV1_HALF_PERIOD_NORM;

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

    // Same tap weights as INVADER_2 (reused for consistency -- both are
    // approximated architectures, not per-voice-derived resistor ratios).
    wire signed [4:0] inv1_tap_sum =
        (inv1_div[3] ? 5'sd8 : -5'sd8) +
        (inv1_div[4] ? 5'sd2 : -5'sd2) +
        (inv1_div[5] ? 5'sd4 : -5'sd4) +
        (inv1_div[6] ? 5'sd1 : -5'sd1);

    wire signed [15:0] inv1_mix = inv1_tap_sum * 16'sd700;
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

    wire [16:0] inv3_half_period = warp_active ? INV3_HALF_PERIOD_WARP : INV3_HALF_PERIOD_NORM;

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
    // KNOWN GAP: that slow-warble modulation is NOT modeled here -- too
    // analog-dependent to derive without simulation. Measured "Invader 4"
    // test audio (Claude/astrob_wav_markers_2026-07-26.md, 02:29.375-
    // 02:33.700: 681.7/726.5/736.5/766.3/776.2/786.2/806.1/890.7 Hz, much
    // higher register than Invaders 1-3) is consistent with a warbling
    // oscillator's peak frequency drifting across the ~4.3s hold rather
    // than a static multi-tap stack. Modeled as a single gated oscillator
    // at ~771 Hz (average of the measured peaks) -- right register,
    // missing the warble.
    //
    // No direct WARP path in the netlist for this voice (only the
    // shared-V path, like INVADER_2) -- measured warp shift ("Warp
    // Invader 4": 664.5-814.2 Hz average ~745 Hz, ~3.4% lower) is inside
    // likely measurement noise. Not modeled; same voice used regardless
    // of I_WARP, consistent with INVADER_2's treatment.
    //------------------------------------------------------------------------
    localparam [13:0] INV4_HALF_PERIOD = 14'd10028;  // clk_sys/(2*771Hz)

    reg [13:0] inv4_osc_cnt;
    reg        inv4_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv4_osc_cnt <= INV4_HALF_PERIOD;
            inv4_osc_out <= 1'b0;
        end else if (!inv4_gate) begin
            inv4_osc_cnt <= INV4_HALF_PERIOD;
            inv4_osc_out <= 1'b0;
        end else if (inv4_osc_cnt == 14'd0) begin
            inv4_osc_cnt <= INV4_HALF_PERIOD;
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
    //   I_ATTACK_RATE/I_RATE_RESET ($3F bits 4/5) are control inputs to
    //   the not-yet-built V generator (CD4017 ladder + warp-summing
    //   op-amp), not standalone voices -- see astrob_audio_board_notes.
    //   MAME's own nl_astrob.cpp header documents SONAR/BONUS triggering
    //   as broken in MAME itself — don't treat MAME audio as ground truth
    //   for those two when they're eventually built.
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
