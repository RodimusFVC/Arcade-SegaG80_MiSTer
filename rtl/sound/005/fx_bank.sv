// ---------------------------------------------------------------------------
// fx_bank.v -- the seven analogue voices, built from the component values on
// sound-board schematic sheets 8 and 9 (drawing 834-0130, PDF pages 72-73).
//
// Port A trigger map, read off sheet 7. All ACTIVE LOW.
//
//   PA0  Large Explosion   one shot
//   PA1  Small Explosion   one shot
//   PA2  Drop Bomb         one shot
//   PA3  Shoot / Pistol    one shot
//   PA4  Missile           one shot
//   PA5  Helicopter        level: low = running
//   PA6  Whistle           level: low = running
//   PA7  unused
//
// Signal sources on the real board:
//
//   NOISE 1  U13 MM5837 buffered by U18 (R55 100k in, R56 10k fb)
//   NOISE 2  NOISE 1 through the U23 multiple-feedback section
//            R93 10k, R92 100k, C70/C71 .01u
//              f0 = 1/(2*pi*C*sqrt(R93*R92)) = 503 Hz,  Q = 0.5*sqrt(10) = 1.58
//
// Per-voice filter sections, all the same MFB topology:
//
//   Large expl  U18  R53/R54 15k,  C52/C53 .047u          -> 226 Hz
//   Small expl  U18  R44/R45 10k,  C47/C48 .039u          -> 408 Hz
//   Missile     U23  R91 10k, R86 47k, C67/C68 .01u       -> 734 Hz, Q 1.08
//   Pistol      U25  R62 10k, R63 100k, C55/C56 .022u     -> 229 Hz, Q 1.58
//
// Periodic sources:
//
//   Helicopter  U22 NE555, R97 10k / R98 150k / D9 / C75 .68u
//               t_hi = 0.693*R97*C75 = 4.7 ms
//               t_lo = 0.693*R98*C75 = 70.7 ms   ->  13.3 Hz, 6% duty
//               chops NOISE 2 through Q6 (R96 820R, R95 220R)
//
//   Whistle     U27 NE555, R114 1k / R113 15k / C91 .022u
//               f = 1.44/((R114 + 2*R113)*C91) = 2112 Hz
//               CON pin modulated by the U26 network, R115/R116 22k with
//               C79/C93 2.2u -> about 3.3 Hz, so the whistle warbles
//               gated on/off by U29 CD4016
//
//   Bomb drop   U21 NE555 sweep (R35 330k, R36 1M, C41 3.3u) gating a falling
//               tone; U29 CD4016 passes it to the mixer
//
// Envelope times come from the 74123 one-shots (t = 0.45*R*C) followed by the
// diode/RC networks feeding each MB4391 control pin:
//
//   Large expl  U2  R6 47k  C13 10u -> 0.21 s gate, C25 1u / R14||R15 500k
//   Small expl  U1  C28 .47u / R18 470k   -> tau 0.22 s
//   Missile     U1  C26 1u   / R23 470k   -> tau 0.47 s
//   Pistol      U20 R37 47k C43 10u, C64 10u / R80 10k
//   Helicopter  C46 10u / R40 100k        -> tau 1.0 s
// ---------------------------------------------------------------------------

`default_nettype none

// This core is DSP-saturated; keep the board's multipliers in logic.
(* multstyle = "logic" *)
module fx_bank #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer AUDIO_HZ = 48_000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,               // AUDIO_HZ strobe
    input  wire [7:0]         pa,                 // 8255 U5 port A, active low
    input  wire signed [17:0] noise1,             // buffered MM5837
    output wire signed [15:0] ch_lexpl,
    output wire signed [15:0] ch_sexpl,
    output wire signed [15:0] ch_bomb,
    output wire signed [15:0] ch_shoot,
    output wire signed [15:0] ch_missile,
    output wire signed [15:0] ch_helicopter,
    output wire signed [15:0] ch_whistle
);

    localparam [63:0] PU40 = (64'd1 << 40) / CLK_HZ;

    // -----------------------------------------------------------------------
    // Trigger edge detection
    // -----------------------------------------------------------------------
    reg [7:0] pa_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pa_d <= 8'hFF;
        else        pa_d <= pa;

    wire [7:0] fall = pa_d & ~pa;

    wire gate_heli = ~pa[5];
    wire gate_whis = ~pa[6];

    // -----------------------------------------------------------------------
    // NOISE 2 -- U23 MFB section, 503 Hz, Q 1.58
    // -----------------------------------------------------------------------
    wire signed [17:0] noise2;

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(503), .Q_X100(158))
        f_n2 (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise1),
              .lp(), .bp(noise2), .hp());

    // -----------------------------------------------------------------------
    // Envelopes.  DECAY_SHIFT k gives tau = 2^k / AUDIO_HZ
    // -----------------------------------------------------------------------
    wire [15:0] env_lexpl, env_sexpl, env_bomb, env_shoot, env_miss;
    wire [15:0] env_heli,  env_whis;

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(15))  // 0.68 s
        e_lexpl (.clk(clk), .rst_n(rst_n), .trig(fall[0]), .sustain(1'b0), .level(env_lexpl));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(13))  // 0.17 s
        e_sexpl (.clk(clk), .rst_n(rst_n), .trig(fall[1]), .sustain(1'b0), .level(env_sexpl));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(16))  // 1.4 s
        e_bomb  (.clk(clk), .rst_n(rst_n), .trig(fall[2]), .sustain(1'b0), .level(env_bomb));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(12))  // 0.085 s
        e_shoot (.clk(clk), .rst_n(rst_n), .trig(fall[3]), .sustain(1'b0), .level(env_shoot));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(14))  // 0.34 s
        e_miss  (.clk(clk), .rst_n(rst_n), .trig(fall[4]), .sustain(1'b0), .level(env_miss));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(15))  // 0.68 s
        e_heli  (.clk(clk), .rst_n(rst_n), .trig(fall[5]), .sustain(gate_heli), .level(env_heli));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(13))
        e_whis  (.clk(clk), .rst_n(rst_n), .trig(fall[6]), .sustain(gate_whis), .level(env_whis));

    // -----------------------------------------------------------------------
    // Noise-based voices
    // -----------------------------------------------------------------------
    wire signed [17:0] bp_lexpl, bp_sexpl, bp_miss, bp_shoot;

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(226), .Q_X100(158))
        f_lex (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise1),
               .lp(), .bp(bp_lexpl), .hp());

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(408), .Q_X100(105))
        f_sex (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise1),
               .lp(), .bp(bp_sexpl), .hp());

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(734), .Q_X100(108))
        f_mis (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise2),
               .lp(), .bp(bp_miss), .hp());

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(229), .Q_X100(158))
        f_pis (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise2),
               .lp(), .bp(bp_shoot), .hp());

    // -----------------------------------------------------------------------
    // U22 NE555 helicopter chopper: 13.3 Hz, roughly 6% duty
    // -----------------------------------------------------------------------
    localparam [63:0] HELI_T_HI = (64'd47  * AUDIO_HZ) / 64'd10000;   // 4.7 ms
    localparam [63:0] HELI_T_LO = (64'd707 * AUDIO_HZ) / 64'd10000;   // 70.7 ms

    reg [15:0] heli_cnt;
    reg        heli_ph;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            heli_cnt <= 16'd0;
            heli_ph  <= 1'b0;
        end else if (tick) begin
            if (heli_ph) begin
                if (heli_cnt >= HELI_T_HI[15:0]) begin heli_cnt <= 16'd0; heli_ph <= 1'b0; end
                else heli_cnt <= heli_cnt + 16'd1;
            end else begin
                if (heli_cnt >= HELI_T_LO[15:0]) begin heli_cnt <= 16'd0; heli_ph <= 1'b1; end
                else heli_cnt <= heli_cnt + 16'd1;
            end
        end
    end

    // Q6 conducts on the 555 high phase; the RC on its base rounds the edges,
    // so slew the chop gain rather than switching it hard.
    reg [15:0] heli_gain;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) heli_gain <= 16'd0;
        else if (tick) begin
            if (heli_ph) heli_gain <= heli_gain + ((16'hFFFF - heli_gain) >> 4);
            else         heli_gain <= heli_gain - (heli_gain >> 6);
        end
    end

    // -----------------------------------------------------------------------
    // U27 NE555 whistle, 2112 Hz, warbled at 3.3 Hz by the U26 network
    // -----------------------------------------------------------------------
    localparam [31:0] INC_WHIS = ((PU40 * 64'd2112) >> 8);
    localparam [31:0] INC_WLFO = ((PU40 * 64'd33  ) >> 12);   // 3.3 Hz
    localparam [31:0] WHIS_DEV = INC_WHIS / 32'd12;           // vibrato depth

    reg [31:0] ph_whis, ph_wlfo;

    // triangle from the LFO phase, 0..255
    wire [7:0] wlfo_tri = ph_wlfo[31] ? ~ph_wlfo[30:23] : ph_wlfo[30:23];
    wire [31:0] inc_whis = INC_WHIS - (WHIS_DEV >> 1)
                         + ((WHIS_DEV * wlfo_tri) >> 8);   // centred warble

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph_whis <= 32'd0;
            ph_wlfo <= 32'd0;
        end else begin
            ph_whis <= ph_whis + inc_whis;
            ph_wlfo <= ph_wlfo + INC_WLFO;
        end
    end

    // -----------------------------------------------------------------------
    // Bomb drop: falling tone, U24/U25 oscillator swept by Q2, gated by U29.
    // R71 22k / C59 4700p puts the top of the sweep near 1.5 kHz.
    // -----------------------------------------------------------------------
    localparam [31:0] INC_BOMB_HI = ((PU40 * 64'd1540) >> 8);
    localparam [31:0] INC_BOMB_LO = ((PU40 * 64'd190 ) >> 8);

    reg [31:0] ph_bomb, inc_bomb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph_bomb  <= 32'd0;
            inc_bomb <= INC_BOMB_LO;
        end else begin
            if (fall[2]) inc_bomb <= INC_BOMB_HI;
            else if (tick && inc_bomb > INC_BOMB_LO)
                inc_bomb <= inc_bomb - (inc_bomb >> 7);
            ph_bomb <= ph_bomb + inc_bomb;
        end
    end

    // -----------------------------------------------------------------------
    // VCA stage.  MB4391 is a dual VCA: four packages, eight voices.
    // -----------------------------------------------------------------------
    // The products are module-level wires, not function locals, so the
    // multstyle attribute can reach each one individually. Slices are
    // unchanged: [33:18] is the old vca, [33:16] the old vca_wide.
    wire signed [17:0] sq_whis = ph_whis[31] ? 18'sd30000 : -18'sd30000;
    wire signed [17:0] sq_bomb = ph_bomb[31] ? 18'sd28000 : -18'sd28000;

    (* multstyle = "logic" *) wire signed [34:0] p_heli_ch = noise2 * $signed({1'b0, heli_gain});
    wire signed [17:0] heli_ch = p_heli_ch[33:16];

    (* multstyle = "logic" *) wire signed [34:0] p_lexpl = bp_lexpl * $signed({1'b0, env_lexpl});
    (* multstyle = "logic" *) wire signed [34:0] p_sexpl = bp_sexpl * $signed({1'b0, env_sexpl});
    (* multstyle = "logic" *) wire signed [34:0] p_miss  = bp_miss  * $signed({1'b0, env_miss});
    (* multstyle = "logic" *) wire signed [34:0] p_shoot = bp_shoot * $signed({1'b0, env_shoot});
    (* multstyle = "logic" *) wire signed [34:0] p_bomb  = sq_bomb  * $signed({1'b0, env_bomb});
    (* multstyle = "logic" *) wire signed [34:0] p_whis  = sq_whis  * $signed({1'b0, env_whis});
    (* multstyle = "logic" *) wire signed [34:0] p_heli  = heli_ch  * $signed({1'b0, env_heli});

    assign ch_lexpl      = p_lexpl[33:18];
    assign ch_sexpl      = p_sexpl[33:18];
    assign ch_missile    = p_miss[33:18];
    assign ch_shoot      = p_shoot[33:18];
    assign ch_bomb       = p_bomb[33:18];
    assign ch_whistle    = p_whis[33:18];
    assign ch_helicopter = p_heli[33:18];

endmodule

`default_nettype wire
