// ---------------------------------------------------------------------------
// monsterb_fx.v -- Monster Bash discrete effects, sound board 834-0316 sheet 5.
//
// Two effects hang off the 8255 port B latch at $0D, both active-low edge
// triggered (MAME segag80r_a.cpp sound_b_w: fire on the 1->0 transition).
// MAME does not emulate either one -- it plays zap.wav / jumpdown.wav samples.
//
// MB4391 (Sega 312-0209) is a dual VCA; as in 005 and Space Odyssey it is a
// multiplier here.  The board inverts the control sense through U3 because the
// part opens on a FALLING control voltage; that inversion is folded away.
//
// SHOT signal path, as drawn:
//
//   PB0 -> U27-A 74123 (R110 47K, C58 1uF)      0.45*R*C = 21 ms gate
//       -> D7, C26 10uF || R53 150K             envelope
//       -> U10 follower, which fans out two ways:
//            (a) U3 (R33/R35 51K, R34 22K, R36 33K) -> U4-A control pin
//            (b) R37 15K / R40 3.5K -> Q1 base
//
//   U8 555 (R28 33K, R29 22K, C40 1uF) = 18.7 Hz, output pin 3 UNUSED.
//   U10 buffers C40 itself, so the modulator is the capacitor ramp.
//   That ramp drives U9 pin 5, and because a 555's charge time tracks the
//   control voltage while its discharge time does not, U9's PITCH and DUTY
//   move together:
//
//       C40 ramp low  (CV 1.67 V):  1447 Hz, 10.7% duty
//       C40 ramp high (CV 3.33 V):  1182 Hz, 27.0% duty
//
//   U3 is a bridged-T around an inverting stage: R30 12K in, R32 4.7K feedback,
//   C24/C23 0.039uF from the summing node to the output with their midpoint
//   shunted to ground.  That shunt is R41 100R in series with R42 1.5K, and
//   Q1 shorts out R42.  So the envelope SWITCHES THE FILTER:
//
//       Q1 on  (attack, 100R):   f0 5835 Hz, Q 3.29   3rd harmonic +2.3 dB
//       Q1 off (tail,  1.6K):    f0 1230 Hz, Q 0.57   3rd harmonic -6.1 dB
//
//   This is what makes the shot bright on the attack and dull as it decays;
//   it is not a fixed bandpass.
//
// DIVE, as drawn:
//   PB1 -> U27-B 74123 (R112 47K, C60 1uF) -> D21, R74 330R, C43 1uF,
//          R72/R73 200K -> U11 follower -> U11 inverting stage (R71 2.2K,
//          R68 12K, +6V biased) -> D4/D5 MA150 clipper (R76 15K, R75 10K,
//          C44 47uF) -> Q2 2SC45B (R66 2.2K, R67 10K) current source ->
//          U10 relaxation oscillator (C42 0.01uF integrator, R59 100K /
//          R60 51K / R61 10K comparator) -> R54 100K / R55 5.1K -> U4-B.
// ---------------------------------------------------------------------------

`default_nettype none

// This core is DSP-saturated; keep the board's multipliers in logic.
(* multstyle = "logic" *)
module monsterb_fx #(
    parameter integer CLK_HZ           = 15_468_480,
    parameter integer AUDIO_HZ         = 48_000,
    parameter integer SHOT_HOLD_MS     = 21,     // 74123 U27-A gate
    parameter integer SHOT_DECAY_SHIFT = 13,     // tau = 2^k / AUDIO_HZ
    parameter integer SHOT_LFO_MHZ     = 18700,  // U8, milli-Hz
    parameter integer SHOT_VCO_LO_HZ   = 1182,   // U9 with the C40 ramp high
    parameter integer SHOT_VCO_HI_HZ   = 1447,   // U9 with the C40 ramp low
    parameter integer SHOT_DUTY_LO_PCT = 11,     // duty tracks the same ramp
    parameter integer SHOT_DUTY_HI_PCT = 27,
    parameter integer SHOT_BP_OFF_HZ   = 1230,   // U3 with Q1 off  (R41+R42)
    parameter integer SHOT_BP_ON_HZ    = 2451,   // U3 with Q1 partly on (~500R)
    parameter integer SHOT_BP_OFF_Q100 = 57,
    parameter integer SHOT_BP_ON_Q100  = 131,
    parameter integer SHOT_Q1_TH_PCT   = 60,     // envelope at which Q1 starts
    parameter integer SHOT_ATT_NUM     = 13,     // R38+R39 over R39
    parameter integer SHOT_ATT_DEN     = 1,
    parameter integer SHOT_GAIN_LOG2   = 3       // makeup for the divider
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire         [7:0] port_b,     // $0D latch, active low
    output wire signed [15:0] ch_shot,
    output wire signed [15:0] ch_dive
);

    localparam [63:0] ATICK = (64'd0 + CLK_HZ) / AUDIO_HZ - 64'd1;

    reg [31:0] adiv;
    reg        tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adiv <= 32'd0;
            tick <= 1'b0;
        end else if (adiv >= ATICK[31:0]) begin
            adiv <= 32'd0;
            tick <= 1'b1;
        end else begin
            adiv <= adiv + 32'd1;
            tick <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // Trigger edge detection -- both effects fire on the falling edge
    // -----------------------------------------------------------------------
    reg [7:0] pb_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pb_d <= 8'hFF;
        else        pb_d <= port_b;

    wire [7:0] fall = pb_d & ~port_b;

    // -----------------------------------------------------------------------
    // SHOT envelope -- 74123 gate holds it up, then C26/R53 decays
    // -----------------------------------------------------------------------
    localparam [63:0] SHOT_HOLD_T = (64'd0 + SHOT_HOLD_MS * AUDIO_HZ) / 64'd1000;

    reg [15:0] env_shot;
    reg [15:0] hold_shot;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            env_shot  <= 16'd0;
            hold_shot <= 16'd0;
        end else if (fall[0]) begin
            env_shot  <= 16'hFFFF;
            hold_shot <= SHOT_HOLD_T[15:0];
        end else if (tick) begin
            if (hold_shot != 16'd0)
                hold_shot <= hold_shot - 16'd1;
            else if (env_shot > (16'd1 << SHOT_DECAY_SHIFT))
                env_shot <= env_shot - (env_shot >> SHOT_DECAY_SHIFT);
            else
                env_shot <= 16'd0;
        end
    end

    // -----------------------------------------------------------------------
    // U8 -- free-running 555; U10 buffers C40, so the modulator is its ramp
    // -----------------------------------------------------------------------
    localparam [63:0] LFO_INC = ((64'd1 << 32) * SHOT_LFO_MHZ) / (64'd1000 * AUDIO_HZ);

    reg [31:0] ph_lfo;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)     ph_lfo <= 32'd0;
        else if (tick)  ph_lfo <= ph_lfo + LFO_INC[31:0];

    // Triangle, 0 = C40 ramp low, 65535 = C40 ramp high.
    wire [15:0] ramp = ph_lfo[31] ? ~ph_lfo[30:15] : ph_lfo[30:15];

    // -----------------------------------------------------------------------
    // U9 -- 555 VCO.  Charge time tracks pin 5, discharge time does not, so
    // the ramp moves pitch and duty together.
    // -----------------------------------------------------------------------
    localparam [63:0] VCO_INC_HI = ((64'd1 << 32) * SHOT_VCO_HI_HZ) / AUDIO_HZ;
    localparam [63:0] VCO_INC_LO = ((64'd1 << 32) * SHOT_VCO_LO_HZ) / AUDIO_HZ;
    localparam [63:0] DUTY_LO    = ((64'd1 << 32) * SHOT_DUTY_LO_PCT) / 64'd100;
    localparam [63:0] DUTY_HI    = ((64'd1 << 32) * SHOT_DUTY_HI_PCT) / 64'd100;

    (* multstyle = "logic" *) wire [47:0] p_inc =
        (VCO_INC_HI[31:0] - VCO_INC_LO[31:0]) * ramp;
    (* multstyle = "logic" *) wire [47:0] p_duty =
        (DUTY_HI[31:0] - DUTY_LO[31:0]) * ramp;

    wire [31:0] inc_vco  = VCO_INC_HI[31:0] - p_inc[47:16];
    wire [31:0] duty_vco = DUTY_LO[31:0]    + p_duty[47:16];

    reg [31:0] ph_vco;
    always @(posedge clk or negedge rst_n)
        if (!rst_n)     ph_vco <= 32'd0;
        else if (tick)  ph_vco <= ph_vco + inc_vco;

    wire signed [17:0] sq_shot = (ph_vco < duty_vco) ? 18'sd30000 : -18'sd30000;

    // -----------------------------------------------------------------------
    // Q1 -- shorts R42, switching the U3 shunt leg from 1.6K to 100R
    // -----------------------------------------------------------------------
    localparam [63:0] Q1_TH    = (64'd65535 * SHOT_Q1_TH_PCT) / 64'd100;
    localparam [63:0] Q1_RECIP = (64'd1 << 32) / (64'd65535 - Q1_TH);

    wire [15:0] q1_ex = (env_shot > Q1_TH[15:0]) ? (env_shot - Q1_TH[15:0]) : 16'd0;

    (* multstyle = "logic" *) wire [47:0] p_q1 = q1_ex * Q1_RECIP[31:0];

    wire [15:0] q1_on = (p_q1[47:16] > 32'd65535) ? 16'hFFFF : p_q1[31:16];

    // -----------------------------------------------------------------------
    // U3 -- bridged-T bandpass, corner and Q interpolated by Q1's conduction
    // -----------------------------------------------------------------------
    localparam [63:0] F_OFF = (64'd411775 * SHOT_BP_OFF_HZ) / AUDIO_HZ;
    localparam [63:0] F_ON  = (64'd411775 * SHOT_BP_ON_HZ)  / AUDIO_HZ;
    localparam [63:0] Q_OFF = 64'd6553600 / SHOT_BP_OFF_Q100;
    localparam [63:0] Q_ON  = 64'd6553600 / SHOT_BP_ON_Q100;

    (* multstyle = "logic" *) wire [47:0] p_f = (F_ON[31:0] - F_OFF[31:0]) * q1_on;
    (* multstyle = "logic" *) wire [47:0] p_q = (Q_OFF[31:0] - Q_ON[31:0]) * q1_on;

    wire [17:0] f_coef = F_OFF[17:0] + p_f[33:16];
    wire [19:0] q_coef = Q_OFF[19:0] - p_q[35:16];

    wire signed [17:0] bp_shot;

    svf_var f_shot (
        .clk(clk), .rst_n(rst_n), .tick(tick),
        .f_coef(f_coef), .q_coef(q_coef),
        .in(sq_shot), .lp(), .bp(bp_shot), .hp()
    );

    // -----------------------------------------------------------------------
    // C28 / R38 12K / R39 1K divider, then the U4-A MB4391 VCA
    // -----------------------------------------------------------------------
    localparam [63:0] ATT = (64'd65536 * SHOT_ATT_DEN) / (64'd0 + SHOT_ATT_NUM);

    (* multstyle = "logic" *) wire signed [35:0] p_att =
        bp_shot * $signed({1'b0, ATT[17:0]});

    wire signed [17:0] att_shot = p_att[33:16];

    (* multstyle = "logic" *) wire signed [34:0] p_shot =
        att_shot * $signed({1'b0, env_shot});

    wire signed [38:0] p_gain = {{4{p_shot[34]}}, p_shot} <<< SHOT_GAIN_LOG2;

    function signed [15:0] sat16;
        input signed [17:0] x;
        begin
            if      (x >  18'sd32767) sat16 =  16'sd32767;
            else if (x < -18'sd32768) sat16 = -16'sd32768;
            else                      sat16 = x[15:0];
        end
    endfunction

    assign ch_shot = sat16(p_gain[35:18]);

    // DIVE chain not yet implemented; the U4-B leg is silent.
    assign ch_dive = 16'sd0;

endmodule

`default_nettype wire
