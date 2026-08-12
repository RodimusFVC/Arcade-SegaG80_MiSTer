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
//    0 I_INVADER_1   [REWORKED: PWM model, see block]   0 I_LASER_1
//    1 I_INVADER_2   [REWORKED: duty-gate + Q1-Q4 DAC]  1 I_LASER_2
//    2 I_INVADER_3   [REWORKED: + U22 FM warble]        2 I_SHORT_EXPL
//    3 I_INVADER_4   [REWORKED: + U28 staircase sweep]  3 I_LONG_EXPL
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
//  REVISION 2026-08-09b (this file): V GENERATOR ADDED — $3F bits 4/5
//  (ATTACK_RATE / RATE_RESET) now drive the CD4017 staircase; all four
//  invader pitches step through 10 levels per the R152-R161 ladder. Also:
//  free-run fix (modulators no longer restart on gate). See V GENERATOR
//  block for the warp-polarity open question.
//  PRIOR REVISION 2026-08-09: four invader voices reworked per
//  sideband analysis + netlist re-derivation. Every constant below still
//  bakes in V ~= 7.6V (the attack-rate staircase parked at Q0, which is
//  where all board captures to date were taken). When the V generator is
//  built, route it into the half-period math instead of re-tuning.
//  Reference renders per voice: astrob_*.wav; derivations:
//  AstroBlaster_verilog.md.
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
    //
    // NOTE (unresolved, flagged 2026-08-09): if audio_we is a single-cycle
    // strobe and ce_cpu a separate periodic enable, `audio_we & ce_cpu`
    // can drop writes — a dropped "off" write is a sound that never stops.
    // Verify at integration: count IOWRs to $3E/$3F vs latch updates.
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
    // the whole mix, bit=0 is normal.
    wire mute = latch_3e[5];

    // Invader gates: I_INVADER_n drives a 555 RESET via 7406 open-collector
    // inverter + pull-up (R73/R70/R23/R88). Port bit 0 -> run, 1 -> silent.
    wire inv1_gate = ~latch_3e[0];
    wire inv2_gate = ~latch_3e[1];
    wire inv3_gate = ~latch_3e[2];
    wire inv4_gate = ~latch_3e[3];

    // WARP ("W" = ALIAS(W, I_LO_D7), RAW un-inverted port bit — distinct
    // from "I_WARP" which is the inverted copy feeding the shared V op-amp).
    // Active HIGH. Pure modifier; no standalone voice in the mixer netlist.
    wire warp_active = latch_3e[7];

    //------------------------------------------------------------------------
    // V GENERATOR — NEW 2026-08-09. The attack-rate staircase.
    //
    // Board: I_ATTACK_RATE (LO on $3F bit4 path via U26 7407 OC) releases a
    // CD4011 gate oscillator (U21, R166=1M, C67=0.05u, ~14.3 Hz) which
    // clocks U15 (CD4017, decade, wraps 0..9). I_RATE_RESET ($3F bit5 via
    // U31 7406): bit LOW -> U15.15 pulled to +12V -> counter HELD at 0.
    // Each decoded output drives one ladder resistor (R161 120k .. R152
    // 22k) into U16's summing node; V = U16.7 steps 7.57V .. 4.93V.
    // Every voice CV rides V, so pitch rises through the wave — the
    // level-1 accelerando this file previously lacked (all constants were
    // captured with the staircase stuck at step 0 on the faulty board).
    //
    // Implementation: vstep 0..9 indexes per-voice half-period ROMs,
    // generated from the solved op-amp voltages + 555 CV equations,
    // normalized so step 0 = the existing capture-validated constants
    // (nothing already tuned changes at step 0).
    //
    // ⚠ WARP-POLARITY OPEN QUESTION: the schematic-solved warp path
    // (I_WARP/R164 shifting U16 pin 5) moves V DOWN under warp -> pitch
    // UP, which CONTRADICTS the capture-derived 104.3->90.3 Hz drop this
    // file encodes. Both can't be right; the captures came from the
    // faulty board whose U31 (the warp inverter's package) was suspect.
    // This file keeps the capture-derived warp bases and applies the
    // step tables on top. To resolve: on a WORKING board, capture INV4
    // with warp on at a known step; if pitch rises ~30%, switch the warp
    // tables to the schematic solution (values in project notes).
    //------------------------------------------------------------------------
    wire attack_run  = ~latch_3f[4];   // bit LOW = oscillator released
    wire rate_reset  = ~latch_3f[5];   // bit LOW = counter held at 0

    localparam [19:0] VSTEP_HALF = 20'd540856;   // clk/(2*14.3Hz)
    reg [19:0] vclk_cnt;
    reg        vclk_out, vclk_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            vclk_cnt <= VSTEP_HALF; vclk_out <= 1'b0;
        end else if (!attack_run) begin
            vclk_cnt <= VSTEP_HALF;               // gate osc held (R148 high)
        end else if (vclk_cnt == 20'd0) begin
            vclk_cnt <= VSTEP_HALF; vclk_out <= ~vclk_out;
        end else begin
            vclk_cnt <= vclk_cnt - 20'd1;
        end
    end
    always @(posedge clk_sys) vclk_d <= vclk_out;
    wire vclk_rise = vclk_out & ~vclk_d;

    reg [3:0] vstep;                              // U15 CD4017: 0..9, wraps
    always @(posedge clk_sys or posedge reset) begin
        if (reset)              vstep <= 4'd0;
        else if (rate_reset)    vstep <= 4'd0;
        else if (vclk_rise)     vstep <= (vstep == 4'd9) ? 4'd0 : vstep + 4'd1;
    end

    // ---- per-step half-period ROMs (step 0 == legacy constants) ----
    reg [17:0] rom_i1n, rom_i1w;   // INV1 period (norm/warp)
    reg [15:0] rom_i2;             // INV2 osc half
    reg [16:0] rom_i3n, rom_i3w;   // INV3 center half (norm/warp)
    reg [16:0] rom_i4h, rom_i4l;   // INV4 endpoints (682Hz / 890Hz)
    always @* begin
        case (vstep)
        4'd0: begin rom_i1n=18'd148307; rom_i1w=18'd171299; rom_i2=16'd2481; rom_i3n=17'd71284; rom_i3w=17'd77265; rom_i4h=17'd11340; rom_i4l=17'd8690; end
        4'd1: begin rom_i1n=18'd138564; rom_i1w=18'd160046; rom_i2=16'd2397; rom_i3n=17'd68863; rom_i3w=17'd74641; rom_i4h=17'd10955; rom_i4l=17'd8395; end
        4'd2: begin rom_i1n=18'd129138; rom_i1w=18'd149158; rom_i2=16'd2310; rom_i3n=17'd66359; rom_i3w=17'd71927; rom_i4h=17'd10557; rom_i4l=17'd8090; end
        4'd3: begin rom_i1n=18'd125302; rom_i1w=18'd144728; rom_i2=16'd2276; rom_i3n=17'd65408; rom_i3w=17'd70895; rom_i4h=17'd10405; rom_i4l=17'd7974; end
        4'd4: begin rom_i1n=18'd118276; rom_i1w=18'd136612; rom_i2=16'd2213; rom_i3n=17'd63584; rom_i3w=17'd68919; rom_i4h=17'd10115; rom_i4l=17'd7751; end
        4'd5: begin rom_i1n=18'd109414; rom_i1w=18'd126376; rom_i2=16'd2139; rom_i3n=17'd61443; rom_i3w=17'd66599; rom_i4h=17'd9775;  rom_i4l=17'd7490; end
        4'd6: begin rom_i1n=18'd100707; rom_i1w=18'd116320; rom_i2=16'd2062; rom_i3n=17'd59249; rom_i3w=17'd64220; rom_i4h=17'd9425;  rom_i4l=17'd7223; end
        4'd7: begin rom_i1n=18'd89544;  rom_i1w=18'd103426; rom_i2=16'd1960; rom_i3n=17'd56323; rom_i3w=17'd61049; rom_i4h=17'd8960;  rom_i4l=17'd6866; end
        4'd8: begin rom_i1n=18'd82357;  rom_i1w=18'd95125;  rom_i2=16'd1896; rom_i3n=17'd54474; rom_i3w=17'd59044; rom_i4h=17'd8666;  rom_i4l=17'd6641; end
        default: begin rom_i1n=18'd76855; rom_i1w=18'd88770; rom_i2=16'd1846; rom_i3n=17'd53049; rom_i3w=17'd57500; rom_i4h=17'd8439; rom_i4l=17'd6467; end
        endcase
    end

    //------------------------------------------------------------------------
    // INVADER_1 — REWORKED 2026-08-09. PWM model.
    //
    // Real circuit: U23 555 astable (R85=150k, R86=10k, C38=0.1u) sets a
    // FIXED trigger rate ~104.3 Hz (measured; formula gives 85-104 across
    // plausible CV). U18 555 monostable sets pulse WIDTH; U22-C/D (TL084,
    // R55=2.2M, C21/C22=0.33u relaxation osc, ~2.55 Hz) drives Q8 (2N4403
    // current source) into C37, sweeping U18's width. So: fixed-rate pulse
    // train, duty swept at 2.55 Hz — pulse-width modulation, NOT AM or FM.
    //
    // Evidence: sidebands repeat at fixed ratio across partials 1-3
    // (PWM masquerades as AM while pi*n*dbar is small) with a single-
    // partial anomaly around n=4-5 (sinc-null fingerprint, dbar ~= 0.25).
    // Warp (R57 path from U30.6) moves BOTH carrier (104.3 -> 90.3 Hz,
    // -13.4%) and envelope rate (2.55 -> 1.83 Hz, measured sideband
    // spacings). Old divided-tap model reproduced the harmonic ladder by
    // arithmetic coincidence (6674/64 = 104.3) but had no modulator ->
    // constant tone.
    //
    // Duty sweep dbar=0.25 +/- 0.10 (dbar read off the anomalous partial;
    // dd is the one free parameter — if over-pulsed vs board, reduce
    // INV1_W_SPAN first). Output asymmetric +6000/-2000 so the mean is
    // ~zero at dbar=0.25 (poor man's coupling cap; if a global HP filter
    // is added downstream, switch to symmetric +/-4000).
    // Reference render: inv1_pwm_model.wav.
    //------------------------------------------------------------------------
    localparam [17:0] INV1_PER_NORM     = 18'd148307;  // clk/104.3Hz - 1
    localparam [17:0] INV1_PER_WARP     = 18'd171299;  // clk/90.3Hz  - 1
    // TUNE-REVERT-2026-08-09: Ian's originals below, uncomment to restore
    // localparam [17:0] INV1_W_MIN        = 18'd22246;   // 0.15 * INV1_PER_NORM
    // localparam [17:0] INV1_W_SPAN       = 18'd29661;   // 0.20 * INV1_PER_NORM
    //
    // Depth retuned against ab_wavs/Fixed real_inv1.wav + Original Sounds/
    // Invader 1.wav (two independent cuts, agreeing on depth 0.52-0.53).
    // Ian's span rendered depth 0.25 with the +-1 sideband at -15 dB vs the
    // board's -8. Doubling the swing lands depth 0.53 and the sideband at -8.
    //
    // ⚠️ RATE IS UNCHANGED AND MUST STAY 23695. A 2026-08-09 attempt to move it
    // to 22801 ("2.65 Hz") was WRONG: that rate came from an envelope-FFT with
    // only 0.25-0.33 Hz resolution on a 3-4 s clip. The SIDEBAND SPACING in the
    // audio spectrum is the high-resolution measurement of the same quantity,
    // and it reads 2.54-2.56 Hz on the board and 2.54 Hz at 23695. Changing it
    // pushed spacing to 2.66 and broke a match that was already correct.
    // Measure modulation rate from sideband spacing, never the envelope FFT.
    localparam [15:0] INV1_ENVSTEP_NORM = 16'd23695;   // (clk/2.55Hz)/256 — correct
    localparam [15:0] INV1_ENVSTEP_WARP = 16'd33018;   // (clk/1.83Hz)/256  #unverified,
                                                       // no isolated warp capture exists
    localparam [17:0] INV1_W_MIN        = 18'd7415;    // 0.05 * INV1_PER_NORM
    localparam [17:0] INV1_W_SPAN       = 18'd59323;   // 0.40 * INV1_PER_NORM
                                                       // => duty 0.05..0.45, mean 0.25
                                                       // (was 0.15..0.35): same mean,
                                                       // double the swing

    // V-STEP 2026-08-09: period now comes from the staircase ROM.
    // (INV1_PER_NORM/WARP retained above as documentation of step 0.)
    wire [17:0] inv1_period  = warp_active ? rom_i1w : rom_i1n;
    wire [15:0] inv1_envstep = warp_active ? INV1_ENVSTEP_WARP : INV1_ENVSTEP_NORM;

    // 8-bit sawtooth envelope (U22-C/D + Q8), one ramp per envelope cycle
    reg [15:0] inv1_env_pre;
    reg  [7:0] inv1_env;
    always @(posedge clk_sys or posedge reset) begin
        // FREE-RUN FIX 2026-08-09: U22-C/D is not gated on the board — only
        // the 555 RESET pins are. Clearing this on !gate restarted the march
        // envelope from minimum duty on every gate pulse; with the retuned
        // W_MIN=0.05 that made pulsed-gate games nearly silent (level-1 bug).
        if (reset) begin
            inv1_env <= 8'd0;  inv1_env_pre <= 16'd0;
        end else if (inv1_env_pre >= inv1_envstep) begin
            inv1_env <= inv1_env + 8'd1;   // wraps: sawtooth
            inv1_env_pre <= 16'd0;
        end else begin
            inv1_env_pre <= inv1_env_pre + 16'd1;
        end
    end

    // width latched once per carrier period (matches U18 monostable reload)
    // (product needs 26 bits: 18-bit span * 8-bit env — a self-determined
    //  18-bit multiply here wraps for env > 8; caught in sim 2026-08-09)
    wire [25:0] inv1_w_prod = INV1_W_SPAN * inv1_env;
    wire [17:0] inv1_width  = INV1_W_MIN + inv1_w_prod[25:8];

    reg [17:0] inv1_per_cnt, inv1_wid_cnt;
    always @(posedge clk_sys or posedge reset) begin
        // Async-reset branch must test ONLY `reset` (Quartus 17.0 error 10200);
        // the gate clear is the same values, moved to a sync branch.
        if (reset) begin
            inv1_per_cnt <= 18'd0;
            inv1_wid_cnt <= 18'd0;
        end else if (!inv1_gate) begin
            inv1_per_cnt <= 18'd0;
            inv1_wid_cnt <= 18'd0;
        end else if (inv1_per_cnt == 18'd0) begin
            inv1_per_cnt <= inv1_period;
            inv1_wid_cnt <= inv1_width;
        end else begin
            inv1_per_cnt <= inv1_per_cnt - 18'd1;
            if (inv1_wid_cnt != 18'd0) inv1_wid_cnt <= inv1_wid_cnt - 18'd1;
        end
    end

    wire signed [15:0] inv1_out =
        !inv1_gate            ? 16'sd0   :
        (inv1_wid_cnt != 18'd0) ?  16'sd6000 : -16'sd2000;

    //------------------------------------------------------------------------
    // INVADER_2 — REWORKED 2026-08-09. Duty-gate + Q1-Q4 binary DAC.
    //
    // U13 555 astable (R81=10k, R82=100k, C36=2200pF, ~3117 Hz nominal /
    // ~3312 Hz at V=7.57) clocks U12 CD4024. Two corrections vs the old
    // block:
    //
    // 1) OSC3 (CLOCK(OSC3, 15.3): CD4011 R22=470k/C5=0.1u, ~50% duty) goes
    //    to U12's ACTIVE-HIGH RESET as a LEVEL — the counter is HELD at
    //    zero for half of every 65.4 ms cycle, not pulse-reset. That hold
    //    is the 15.3 Hz "machine-gun" gating. Board evidence: measured
    //    peaks are ALL integer multiples of 15.29 Hz, odd-only at the low
    //    end (45.9=3x, 76.5=5x, no 2x) — the signature of a ~square gate.
    //    (An envelope LUT fits the same data with more parameters; the
    //    hold needs none.)
    //
    // 2) Tap ladder is Q1..Q4 = /2../16 (U12 pins 12/11/9/6 -> R48 82k /
    //    R49 39k / R50 22k / R47 10k), binary weighted with the MSB on the
    //    /16 tap: a 16-step SAWTOOTH at f0/16 ~= 195-207 Hz. Old block
    //    used div[3..6] (one tap right, three octaves slow) with the
    //    weight order inverted — dominant peak landed right by luck,
    //    waveform was a scrambled staircase.
    //
    // Reference render: astrob_invader2.wav. Zero fitted parameters.
    //------------------------------------------------------------------------
    localparam [15:0] INV2_HALF_PERIOD = 16'd2481;    // clk/(2*3117Hz), nominal
    localparam [19:0] INV2_GATE_HALF   = 20'd505671;  // clk/(2*15.29Hz), OSC3

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
            inv2_osc_cnt <= rom_i2;               // V-STEP 2026-08-09
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

    // OSC3 as a 50%-duty LEVEL (was: single-cycle reset pulse)
    reg [19:0] inv2_g_cnt;
    reg        inv2_hold;                 // high = U12 held in reset
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv2_g_cnt <= INV2_GATE_HALF;
            inv2_hold  <= 1'b0;
        // FREE-RUN FIX 2026-08-09: OSC3 free-runs; no phase resync on gate.
        end else if (inv2_g_cnt == 20'd0) begin
            inv2_g_cnt <= INV2_GATE_HALF;
            inv2_hold  <= ~inv2_hold;
        end else begin
            inv2_g_cnt <= inv2_g_cnt - 20'd1;
        end
    end

    reg [6:0] inv2_div;   // CD4024 equivalent (only [3:0] used in the DAC)
    always @(posedge clk_sys or posedge reset) begin
        if (reset)                          inv2_div <= 7'd0;
        else if (!inv2_gate || inv2_hold)   inv2_div <= 7'd0;   // HELD, not pulsed
        else if (inv2_osc_rise)             inv2_div <= inv2_div + 7'd1;
    end

    // Q1..Q4 binary DAC (was: div[3..6] with inverted weights)
    wire signed [4:0] inv2_tap_sum =
        (inv2_div[0] ? 5'sd1 : -5'sd1) +   // Q1  /2   R48 82k  (LSB)
        (inv2_div[1] ? 5'sd2 : -5'sd2) +   // Q2  /4   R49 39k
        (inv2_div[2] ? 5'sd4 : -5'sd4) +   // Q3  /8   R50 22k
        (inv2_div[3] ? 5'sd8 : -5'sd8);    // Q4  /16  R47 10k  (MSB)

    wire signed [15:0] inv2_mix = inv2_tap_sum * 16'sd700;
    wire signed [15:0] inv2_out = inv2_gate ? inv2_mix : 16'sd0;

    //------------------------------------------------------------------------
    // INVADER_3 — REWORKED 2026-08-09. Adds the U22-A/B FM warble.
    //
    // U17 555 (R51=10k, R52=68k, C7=0.1u; 98.8 Hz nominal, 104.9 at
    // V=7.57) with CV swept by U22-A/B (R24=2.2M relaxation osc) through
    // C12/R54 — a real FM warble the old static-square model lacked.
    // Measured: cluster spacing ~8.7 Hz normal / ~5.05 Hz warp (LFO rate);
    // center 108.5 / 100.1 Hz (direct warp path NET_C(W, U30.9) retunes
    // both). Deviation +/-8% of center fits the measured cluster width —
    // this (INV3_PER_DEV) is the one tunable.
    // Reference render: astrob_invader3.wav (normal, then warp).
    //------------------------------------------------------------------------
    localparam [20:0] INV3_TRI_HALF_N = 21'd888993;   // clk/(2*8.7Hz)
    localparam [20:0] INV3_TRI_HALF_W = 21'd1531533;  // clk/(2*5.05Hz)
    localparam [16:0] INV3_PER_CTR_N  = 17'd71284;    // clk/(2*108.5Hz)
    localparam [16:0] INV3_PER_CTR_W  = 17'd77265;    // clk/(2*100.1Hz)
    localparam [16:0] INV3_PER_DEV    = 17'd5700;     // ~8% of center  #unverified

    wire [20:0] inv3_tri_half = warp_active ? INV3_TRI_HALF_W : INV3_TRI_HALF_N;
    wire [20:0] inv3_lfo_step = inv3_tri_half >> 8;   // 256 steps per half-cycle

    // triangle LFO (up/down 8-bit)
    reg [20:0] inv3_lfo_pre;
    reg  [7:0] inv3_lfo;
    reg        inv3_lfo_dir;
    always @(posedge clk_sys or posedge reset) begin
        // Async-reset branch must test ONLY `reset` (Quartus 17.0 error 10200).
        // FREE-RUN FIX 2026-08-09: U22-A/B free-runs on the board (see INV1).
        if (reset) begin
            inv3_lfo <= 8'd128;  inv3_lfo_dir <= 1'b0;  inv3_lfo_pre <= 21'd0;
        end else if (inv3_lfo_pre >= inv3_lfo_step) begin
            inv3_lfo_pre <= 21'd0;
            if (inv3_lfo_dir) begin
                if (inv3_lfo == 8'd0)   inv3_lfo_dir <= 1'b0;
                else                    inv3_lfo <= inv3_lfo - 8'd1;
            end else begin
                if (inv3_lfo == 8'd255) inv3_lfo_dir <= 1'b1;
                else                    inv3_lfo <= inv3_lfo + 8'd1;
            end
        end else begin
            inv3_lfo_pre <= inv3_lfo_pre + 21'd1;
        end
    end

    // V-STEP 2026-08-09: center from staircase ROM (constants above = step 0).
    wire [16:0] inv3_per_ctr = warp_active ? rom_i3w : rom_i3n;
    // half = center + dev*(lfo-128)/128
    wire signed [17:0] inv3_lfo_c = $signed({10'd0, inv3_lfo}) - 18'sd128;
    wire signed [35:0] inv3_dev_p = $signed({19'd0, INV3_PER_DEV}) * inv3_lfo_c;
    wire signed [17:0] inv3_dev   = inv3_dev_p[24:7];   // >>7
    wire [16:0] inv3_half = inv3_per_ctr + inv3_dev[16:0];

    reg [16:0] inv3_osc_cnt;
    reg        inv3_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        // Async-reset branch must test ONLY `reset` (Quartus 17.0 error 10200).
        if (reset) begin
            inv3_osc_cnt <= 17'd0;
            inv3_osc_out <= 1'b0;
        end else if (!inv3_gate) begin
            inv3_osc_cnt <= 17'd0;
            inv3_osc_out <= 1'b0;
        end else if (inv3_osc_cnt == 17'd0) begin
            inv3_osc_cnt <= inv3_half;
            inv3_osc_out <= ~inv3_osc_out;
        end else begin
            inv3_osc_cnt <= inv3_osc_cnt - 17'd1;
        end
    end

    wire signed [15:0] inv3_out = inv3_gate ? (inv3_osc_out ? 16'sd6000 : -16'sd6000) : 16'sd0;

    //------------------------------------------------------------------------
    // INVADER_4 — REWORKED 2026-08-09. "Known gap" (warble) closed.
    //
    // U37 555 free-runs at 68.7 Hz (R89=10k, R90=100k, C39=0.1u; never
    // gated — U37.4 tied to +12V) clocking U28 CD4024, which SELF-RESETS
    // from its own output (U28 pin 2 <- pin 5). Q1..Q4 through R31/R32/
    // R33/R30 (10k/22k/39k/82k) into U38's CV pin: a binary staircase
    // sweeping U38 (R60=10k, R61=100k, C23=0.01u; 687 Hz base). Result:
    // 16-step frequency ramp ~682 -> ~890 Hz. This is why earlier spot
    // measurements disagreed (730 vs 748 vs 771 Hz): all were samples of
    // the sweep at different phases.
    //
    // OPEN QUESTION (self-reset semantics): pin2<-pin5 reset fires when
    // Q5 RISES, i.e. at count 16 -> mod-16, one ramp per cycle, sweep
    // rate 68.7/16 ~= 4.3 Hz. If instead the intended behavior is mod-32
    // (two ramps), rate is ~2.15 Hz. The old comment said "mod-5 ring"
    // which is neither. Modeled as mod-16 here (ring[3:0], wrap = reset);
    // if the board's sweep audibly repeats at ~2 Hz instead of ~4 Hz,
    // change inv4_ring to [4:0] and keep code = ring[3:0].
    // Reference render: astrob_invader4.wav.
    //------------------------------------------------------------------------
    localparam [17:0] INV4_STEP_HALF = 18'd112580;    // clk/(2*68.7Hz), U37
    localparam [16:0] INV4_HALF_LO   = 17'd8690;      // 890 Hz endpoint
    localparam [16:0] INV4_HALF_HI   = 17'd11340;     // 682 Hz endpoint

    reg [17:0] inv4_stp_cnt;
    reg        inv4_stp_out;
    always @(posedge clk_sys or posedge reset) begin  // U37: free-runs, ungated
        if (reset) begin
            inv4_stp_cnt <= INV4_STEP_HALF;
            inv4_stp_out <= 1'b0;
        end else if (inv4_stp_cnt == 18'd0) begin
            inv4_stp_cnt <= INV4_STEP_HALF;
            inv4_stp_out <= ~inv4_stp_out;
        end else begin
            inv4_stp_cnt <= inv4_stp_cnt - 18'd1;
        end
    end

    reg inv4_stp_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) inv4_stp_d <= 1'b0;
        else       inv4_stp_d <= inv4_stp_out;
    end
    wire inv4_stp_rise = inv4_stp_out & ~inv4_stp_d;

    reg [3:0] inv4_ring;                              // U28 mod-16 (see note)
    always @(posedge clk_sys or posedge reset) begin
        if (reset)              inv4_ring <= 4'd0;
        else if (inv4_stp_rise) inv4_ring <= inv4_ring + 4'd1;  // wrap = self-reset
    end
    wire [3:0] inv4_code = inv4_ring;

    // linear interp between endpoints (exact clk/f per code would be a
    // 16-entry ROM; linear is within ~1% here)
    // V-STEP 2026-08-09: endpoints from staircase ROM (constants above = step 0).
    wire [21:0] inv4_span = (rom_i4h - rom_i4l) * inv4_code;
    wire [16:0] inv4_half = rom_i4h - inv4_span[20:4];   // /15 ~= >>4 - ok at this tolerance

    reg [16:0] inv4_osc_cnt;
    reg        inv4_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        // Async-reset branch must test ONLY `reset` (Quartus 17.0 error 10200).
        if (reset) begin
            inv4_osc_cnt <= 17'd0;
            inv4_osc_out <= 1'b0;
        end else if (!inv4_gate) begin
            inv4_osc_cnt <= 17'd0;
            inv4_osc_out <= 1'b0;
        end else if (inv4_osc_cnt == 17'd0) begin
            inv4_osc_cnt <= inv4_half;
            inv4_osc_out <= ~inv4_osc_out;
        end else begin
            inv4_osc_cnt <= inv4_osc_cnt - 17'd1;
        end
    end

    wire signed [15:0] inv4_out = inv4_gate ? (inv4_osc_out ? 16'sd6000 : -16'sd6000) : 16'sd0;

    //------------------------------------------------------------------------
    // Remaining voices — not yet ported, silent for now.
    //   $3E: I_ASTROIDS, I_REFILL
    //   $3F: I_LASER_1, I_LASER_2, I_SHORT_EXPL, I_LONG_EXPL, I_BONUS,
    //        I_SONAR
    //   I_ATTACK_RATE/I_RATE_RESET ($3F bits 4/5) are control inputs to
    //   the not-yet-built V generator (CD4017 ladder + warp-summing
    //   op-amp), not standalone voices.
    //   Verilog blocks + reference renders for all of these are staged in
    //   AstroBlaster_verilog.md (2026-08-09).
    //   Netlist caveats: SONAR depends on randomized part values
    //   (FRND1..10) and its retriggering relies on clipping diodes MAME
    //   skips by default; BONUS shares the clipping-diode caveat. Capture
    //   board audio for both — don't calibrate against any emulator.
    //------------------------------------------------------------------------

    //------------------------------------------------------------------------
    // Mix
    //
    // Headroom (2026-08-09): worst case |sum| = 6000+700*15+6000+6000 =
    // 28500 < 32767 — no clipping with the reworked levels (old levels
    // could hit 37000 and clip, manufacturing even harmonics that
    // contaminated spectral measurements). Keep Σ|max| <= 30000 as voices
    // are added; prefer a global >>1 over per-voice cuts once the count
    // grows. Consider a one-pole HP (~20 Hz) here to stand in for the
    // board's C55 coupling before adding asymmetric/gated voices beyond
    // INV1.
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
