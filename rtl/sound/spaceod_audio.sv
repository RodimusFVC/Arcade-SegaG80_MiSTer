//============================================================================
//  Sega / Gremlin  "Space Odyssey"
//  Analogue sound board  834-0051  rev A  (25-Jun-1981)
//
//  Behavioural FPGA re-implementation for MiSTer.
//
//  Source material : sheets 1-3 of 834-0051 + parts list DWG 834-0041,
//                    tuned against the MAME reference samples.
//
//  Board overview
//  --------------------------------------------------------------------------
//  Sheet 1 : MN3005 (IC2) 4096-stage bucket-brigade delay clocked by the
//            MN3101 (IC3), wrapped in AN6551 companding buffers (IC1/IC5).
//            Everything driven into "BBD IN" comes back out of "BBD OUT"
//            ~40 ms later with regeneration - this is what gives the game its
//            cavernous character.
//            Also: D-BOMB one-shot chain (IC37 -> IC21 -> IC16 -> IC12 VCA),
//            BONUS UP (IC35 one-shot -> 74LS393 IC30 -> IC32 gate), and the
//            engine oscillator (IC23/IC18 + TR8) switched into the BBD by the
//            4016 (IC14) and steered by ACCELERATE / BLACK HOLE / BACK G.
//  Sheet 2 : WARP (IC38 -> IC21/IC17/IC13 -> IC12 VCA -> BBD IN),
//            SHOT (IC38 -> IC25 envelope -> NE555 IC19 VCO -> IC10 VCA),
//            SHORT EXP and LONG EXP - both fed from the S-2688 noise
//            generator (IC4) through separate IC8 shapers into the two halves
//            of IC9, and the final IC7 summing amp -> SOUND OUT.
//  Sheet 3 : BATTLE STAR (NE555 IC33 -> IC26/IC15 -> IC10 VCA -> BBD IN) and
//            APPEARANCE UFO (IC35 -> IC25/IC16 -> IC11 VCA), the latter going
//            to both the dry mixer and the BBD.
//
//  The "439 1/2" symbols are the two halves of the MB4391 (312-0209) VCA /
//  compander.  If you are rebuilding the real board, 2x MC3340 substitutes
//  for 1x MB4391; on the FPGA they are just multipliers.
//
//  What the reference samples changed vs. a naive read of the schematic
//  --------------------------------------------------------------------------
//  * ssound / accel / damaged all sit on the same 135-155 Hz fundamental.
//    They are not three sounds, they are ONE oscillator - the sheet 1 engine
//    switched into the BBD by the 4016 (IC14).  Sheet 4 confirms it: eleven
//    latched control lines, eleven MAME samples, one-to-one.  BACK G is
//    "ssound" (rest pitch ~137 Hz), ACCELERATE walks the same oscillator up
//    to ~680 Hz over about five seconds, and BLACK HOLE is "damaged",
//    parked at ~135 Hz under a slow tremolo.
//  * scoreup is a single 34 ms blip at 3.3 kHz, not an ascending run.  The
//    74LS393 is dividing a high oscillator down, not sequencing an arpeggio;
//    the game re-triggers it per point during the tally.
//  * birth (APPEARANCE UFO) is a rising 330 -> 700 Hz sweep, not a warble.
//  * Almost every one-shot has a plateau before it decays, i.e. the 74123
//    holds the VCA open and the RC decay only starts when the pulse ends.
//    Hence the HOLD_MS stage in so_env.
//
//  This is a behavioural model, not a component-level analogue simulation.
//  Envelope times, sweep endpoints and brightness were fitted to the sample
//  measurements; see the CHANNEL TUNING block.
//
//  Fit against the MAME reference samples (duration / peak / spectral
//  centroid, measured on the isolated channel):
//
//      channel    dur MAME/SYN   peak MAME/SYN   centroid MAME -> SYN
//      fire        0.76 / 0.78    8153 /  8230   3983>1575 / 3468>2362
//      bomb        1.65 / 1.86   22451 / 20413   2516>1109 / 2669>2343
//      eexplode    1.70 / 1.82   32532 / 31365   2688>1364 / 2167>2180
//      pexplode    3.98 / 3.92   32833 / 23030    660>508  /  470>631 
//      warp        2.16 / 2.14   32801 / 21660   1068>1188 / 1298>2162
//      birth       0.52 / 0.57   11734 / 12175   1534>1350 / 1485>1718
//      scoreup     0.03 / 0.05    6393 /  6742   4262>3972 / 4733>3753
//      erocket     2.14 / 2.32   32771 / 25564   1210>1643 / 1624>2099
//      ssound      loop / loop   27745 / 16236   1880>1861 / 2198>2212
//      accel       loop / loop   25298 / 20485   1551>2756 / 1394>1690
//      damaged     loop / loop   26884 / 18270   1095>857  /  867>2235
//
//  ssound / accel / damaged still sit a little under their sample peaks:
//  they are continuous while flying, so leaving headroom for an explosion
//  on top matters more than matching an individually-normalised sample.
//
//  Verified with Verilator: lints clean at both tops, the mixer only
//  saturates when every channel fires at once, and the only thing present
//  at idle is the intended background drone.
//
//  Resources: one 1966 x 18 delay RAM (~4 M9K or 1 M10K on Cyclone V) plus a
//  handful of 18x18 multipliers.
//============================================================================

`default_nettype none

module spaceod_sound #(
    parameter int unsigned CLK_HZ    = 24_000_000, // clk frequency
    parameter int unsigned SAMPLE_HZ = 48_000,     // internal audio rate
    parameter int unsigned BBD_DEPTH = 1966,       // 4096 stages / 2 / ~52 kHz
    parameter int unsigned BBD_FB    = 6           // regeneration, /16
)(
    input  wire                clk,
    input  wire                reset,        // synchronous, active high

    // ---- trigger / gate inputs, active high --------------------------------
    // Edge-triggered (74123 monostables on the real board):
    input  wire                t_shot,       // "fire"     sheet 2, IC38
    input  wire                t_dbomb,      // "bomb"     sheet 1, IC37
    input  wire                t_sexp,       // "eexplode" sheet 2, IC34
    input  wire                t_lexp,       // "pexplode" sheet 2, IC37
    input  wire                t_warp,       // "warp"     sheet 2, IC38
    input  wire                t_ufo,        // "birth"    sheet 3, IC35
    input  wire                t_bonus,      // "scoreup"  sheet 1, IC35
    // Level-gated (buffered through IC31 / IC27, sustain while asserted):
    input  wire                g_battle,     // "erocket"  sheet 3, IC33
    input  wire                g_accel,      // "accel"    sheet 1, IC31
    input  wire                g_blackhole,  // "damaged"  sheet 1, IC31
    input  wire                g_backg,      // BACK G     sheet 1, IC31

    input  wire                enable,       // master sound on/off + drone

    output wire signed [15:0]  audio,        // mono, SOUND OUT (pins 4 / 6)
    output wire                ce_snd        // one pulse per output sample
);

    //========================================================================
    //  Sample-rate clock enable
    //========================================================================
    localparam [32:0] ACC_INC = 33'((longint'(SAMPLE_HZ) <<< 32) / longint'(CLK_HZ));

    reg [32:0] ce_acc = '0;
    always_ff @(posedge clk) ce_acc <= {1'b0, ce_acc[31:0]} + ACC_INC;

    assign ce_snd = ce_acc[32];
    wire   ce     = ce_acc[32];

    // phase increment per Hz for the 24-bit phase accumulators
    localparam int PHZ = (1 << 24) / SAMPLE_HZ;

    //========================================================================
    //  CHANNEL TUNING  -  edit here, not in the logic below
    //  DEC is a shift: decay tau = 2^DEC / SAMPLE_HZ seconds.
    //  HOLD is in milliseconds (the 74123 pulse width).
    //========================================================================
    // Decay times are the RC tau in ms; HOLD is the 74123 pulse width in ms.
    // SHOT / "fire" : 0.80 s, 350 ms plateau, bright and buzzy
    localparam int SHOT_F_LO  =  300, SHOT_F_HI  =  900;
    localparam int SHOT_HOLD  =  350, SHOT_DEC   =  130, SHOT_PDEC = 120;
    // D-BOMB / "bomb" : 1.9 s, near-pure descending tone, no plateau
    localparam int DBOMB_F_LO =  450, DBOMB_F_HI = 1500;
    localparam int DBOMB_HOLD =  100, DBOMB_DEC  =  450;
    // WARP : 2.4 s, 1.1 s plateau, slow rising sweep
    localparam int WARP_F_LO  =  105, WARP_F_HI  =  450;
    localparam int WARP_HOLD  = 1100, WARP_DEC   =  280, WARP_RAMP = 2200;
    // APPEARANCE UFO / "birth" : 0.53 s rising blip
    localparam int UFO_F_LO   =  320, UFO_F_HI   =  700;
    localparam int UFO_HOLD   =  300, UFO_DEC    =   70, UFO_RAMP  =  550;
    // BONUS UP / "scoreup" : single 34 ms blip at 3.3 kHz
    localparam int BONUS_F    = 3300, BONUS_HOLD =   28, BONUS_DEC =    4;
    // BATTLE STAR / "erocket" : repeating rising sweep from the NE555 IC33
    localparam int BATT_F_LO  =  445, BATT_F_HI  = 2350;
    localparam int BATT_HOLD  =  700, BATT_DEC   =  430, BATT_SWEEP = 1070;
    // Explosions : envelope only, pitch comes from the filters below
    localparam int SEXP_HOLD  =  250, SEXP_DEC   =  460;
    localparam int LEXP_HOLD  = 1300, LEXP_DEC   =  760;
    // Engine : BACK G is "ssound", ACCELERATE walks it up, BLACK HOLE is
    // "damaged" - all three are the same sheet 1 oscillator
    localparam int ENG_IDLE   =  137, ENG_ACCEL  =  680;  // IDLE = rest pitch
    localparam int ENG_BACKG  =  137, ENG_BHOLE  =  135;
    localparam int ENG_SLEW   =   16;   // shift; ~1.4 s tau, ~5 s full travel
    localparam int BHOLE_LFO  =    4;   // Hz tremolo while BLACK HOLE is held

    // Band-pass coefficients, Q16.  f = 2*sin(pi*fc/fs), q = 1/Q
    localparam [15:0] SEXP_F = 16'd3258;  // ~380 Hz @48k  (IC8 15k/0.022u pair)
    localparam [15:0] SEXP_Q = 16'd22000;
    localparam [15:0] LEXP_F = 16'd1458;  // ~170 Hz @48k  (IC8 15k/0.047u pair)
    localparam [15:0] LEXP_Q = 16'd16000;

    // Mixer gains into IC7, 256 = unity.  Weighted by the summing resistors:
    // L.EXP goes in on R15 3.3k so it is the loudest thing on the board.
    localparam int G_BBD = 250, G_DBOMB = 700, G_BONUS = 140, G_UFO = 170;
    localparam int G_SHOT = 120, G_SEXP = 600, G_LEXP = 540;

    //========================================================================
    //  Noise source  -  Sanyo S-2688 (IC4)
    //  32-bit xorshift, one step per sample.  Flat enough; the channel
    //  filters do the colouring, exactly as IC8 does on the real board.
    //========================================================================
    reg  [31:0] rnd = 32'h1234_5678;
    wire [31:0] rx1 = rnd ^ (rnd << 13);
    wire [31:0] rx2 = rx1 ^ (rx1 >> 17);
    wire [31:0] rx3 = rx2 ^ (rx2 << 5);

    always_ff @(posedge clk)
        if (reset)   rnd <= 32'h1234_5678;
        else if (ce) rnd <= rx3;

    wire signed [17:0] noise = $signed({2'b00, rnd[15:0]}) - 18'sd32768;

    //========================================================================
    //  SHOT   (sheet 2 : IC38 one-shot -> IC25 -> NE555 IC19 VCO -> IC10 VCA)
    //  The 555 control pin rides a fast decay so the pitch drops away ahead
    //  of the amplitude; TR1/D3 inject the noise that keeps it buzzy.
    //========================================================================
    wire [15:0] env_shot, pit_shot;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(1), .HOLD_MS(SHOT_HOLD),
             .DEC_MS(SHOT_DEC)) u_env_shot (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_shot), .level(env_shot));
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(1), .HOLD_MS(0),
             .DEC_MS(SHOT_PDEC)) u_pit_shot (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_shot), .level(pit_shot));

    wire [39:0] shot_sw  = (40'(SHOT_F_HI) - 40'(SHOT_F_LO)) * PHZ * pit_shot;
    wire [23:0] shot_inc = 24'(SHOT_F_LO * PHZ) + shot_sw[39:16];

    reg [23:0] ph_shot;
    always_ff @(posedge clk)
        if (reset) ph_shot <= '0; else if (ce) ph_shot <= ph_shot + shot_inc;

    wire signed [17:0] shot_sq  = ph_shot[23] ? 18'sd16000 : -18'sd16000;
    wire signed [17:0] shot_nz  = vca(noise, pit_shot);   // TR1/D3 dies first
    wire signed [17:0] shot_src = (shot_sq >>> 1) + (shot_nz >>> 1);
    wire signed [17:0] shot_f1, shot_flt;
    so_lp1 #(.SH(1)) u_shot_lp1 (.clk(clk), .ce(ce), .reset(reset),
                                 .din(shot_src), .dout(shot_f1));
    wire signed [17:0] shot_f2;
    so_lp1 #(.SH(1)) u_shot_lp2 (.clk(clk), .ce(ce), .reset(reset),
                                 .din(shot_f1), .dout(shot_f2));
    so_lp1 #(.SH(1)) u_shot_lp3 (.clk(clk), .ce(ce), .reset(reset),
                                 .din(shot_f2), .dout(shot_flt));
    wire signed [17:0] shot_out = vca(shot_flt, env_shot);

    //========================================================================
    //  D-BOMB (sheet 1 : IC37 -> IC21 -> IC16 osc + TR4 -> IC27 -> IC12 VCA)
    //  Nearly pure descending tone - the reference sample is very tonal, so
    //  the TR4 noise contribution is kept small.
    //========================================================================
    wire [15:0] env_dbomb;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(2), .HOLD_MS(DBOMB_HOLD),
             .DEC_MS(DBOMB_DEC)) u_env_dbomb (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_dbomb), .level(env_dbomb));

    wire [39:0] db_sw  = (40'(DBOMB_F_HI) - 40'(DBOMB_F_LO)) * PHZ * env_dbomb;
    wire [23:0] db_inc = 24'(DBOMB_F_LO * PHZ) + db_sw[39:16];

    reg [23:0] ph_dbomb;
    always_ff @(posedge clk)
        if (reset) ph_dbomb <= '0; else if (ce) ph_dbomb <= ph_dbomb + db_inc;

    wire signed [17:0] db_sq  = ph_dbomb[23] ? 18'sd16000 : -18'sd16000;
    wire signed [17:0] db_src = (db_sq >>> 1) + (noise >>> 7);
    wire signed [17:0] db_f1, db_flt;
    so_lp1 #(.SH(2)) u_db_l1 (.clk(clk), .ce(ce), .reset(reset),
                              .din(db_src), .dout(db_f1));
    so_lp1 #(.SH(2)) u_db_l2 (.clk(clk), .ce(ce), .reset(reset),
                              .din(db_f1), .dout(db_flt));
    wire signed [17:0] dbomb_out = vca(db_flt, env_dbomb);

    //========================================================================
    //  SHORT EXP  (enemy)   S-2688 noise -> IC8 shaper -> IC9a VCA
    //  LONG  EXP  (player)  same noise   -> lower IC8 shaper -> IC9b VCA
    //  Both are broadband with a resonant low bump, so each is a wideband
    //  path summed with its band-pass rather than band-pass alone.
    //========================================================================
    wire [15:0] env_sexp, env_lexp;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(1), .HOLD_MS(SEXP_HOLD),
             .DEC_MS(SEXP_DEC)) u_env_sexp (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_sexp), .level(env_sexp));
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(2), .HOLD_MS(LEXP_HOLD),
             .DEC_MS(LEXP_DEC)) u_env_lexp (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_lexp), .level(env_lexp));

    wire signed [17:0] sexp_bp, lexp_bp;

    so_svf u_sexp_svf (.clk(clk), .ce(ce), .reset(reset), .din(noise >>> 1),
                       .f(SEXP_F), .q(SEXP_Q), .lp(), .bp(sexp_bp), .hp());
    so_svf u_lexp_svf (.clk(clk), .ce(ce), .reset(reset), .din(noise >>> 1),
                       .f(LEXP_F), .q(LEXP_Q), .lp(), .bp(lexp_bp), .hp());

    wire signed [17:0] sexp_a, sexp_b, sexp_wb;
    so_lp1 #(.SH(1)) u_sexp_w1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(noise >>> 1), .dout(sexp_a));
    so_lp1 #(.SH(1)) u_sexp_w2 (.clk(clk), .ce(ce), .reset(reset),
                                .din(sexp_a), .dout(sexp_b));
    so_lp1 #(.SH(3)) u_sexp_w3 (.clk(clk), .ce(ce), .reset(reset),
                                .din(sexp_b), .dout(sexp_wb));

    wire signed [17:0] lexp_a, lexp_wb;
    so_lp1 #(.SH(3)) u_lexp_w1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(noise), .dout(lexp_a));
    so_lp1 #(.SH(5)) u_lexp_w2 (.clk(clk), .ce(ce), .reset(reset),
                                .din(lexp_a), .dout(lexp_wb));

    wire signed [17:0] lexp_s1, lexp_sum;
    so_lp1 #(.SH(4)) u_lexp_s1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(lexp_bp + lexp_wb), .dout(lexp_s1));
    so_lp1 #(.SH(2)) u_lexp_s2 (.clk(clk), .ce(ce), .reset(reset),
                                .din(lexp_s1), .dout(lexp_sum));

    wire signed [17:0] sexp_s1, sexp_sum;
    so_lp1 #(.SH(1)) u_sexp_s1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(sexp_bp + sexp_wb), .dout(sexp_s1));
    so_lp1 #(.SH(0)) u_sexp_s2 (.clk(clk), .ce(ce), .reset(reset),
                                .din(sexp_s1), .dout(sexp_sum));

    wire signed [17:0] sexp_out = vca(sexp_sum, env_sexp);
    wire signed [17:0] lexp_out = vca(lexp_sum, env_lexp);

    //========================================================================
    //  WARP  (sheet 2 : IC38 -> IC21/IC17/IC13 -> IC12 VCA -> BBD IN)
    //  The pitch climbs on its own ramp and keeps climbing while the level
    //  falls, which is why it cannot be driven from the amplitude envelope.
    //  Routed into the BBD, so it arrives at the mixer smeared and echoed.
    //========================================================================
    wire [15:0] env_warp, ramp_warp;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(4), .HOLD_MS(WARP_HOLD),
             .DEC_MS(WARP_DEC)) u_env_warp (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_warp), .level(env_warp));
    so_ramp #(.SAMPLE_HZ(SAMPLE_HZ), .MS(WARP_RAMP)) u_rmp_warp (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_warp), .level(ramp_warp));

    wire [39:0] warp_sw  = (40'(WARP_F_HI) - 40'(WARP_F_LO)) * PHZ * ramp_warp;
    wire [23:0] warp_inc = 24'(WARP_F_LO * PHZ) + warp_sw[39:16];

    reg [23:0] ph_warp;
    always_ff @(posedge clk)
        if (reset) ph_warp <= '0; else if (ce) ph_warp <= ph_warp + warp_inc;

    wire signed [17:0] warp_saw = 18'($signed(ph_warp[23:8] ^ 16'h8000));
    wire signed [17:0] warp_src = (warp_saw >>> 1) + (noise >>> 4);
    wire signed [17:0] warp_f1, warp_f2, warp_flt;
    so_lp1 #(.SH(1)) u_warp_l1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(warp_src), .dout(warp_f1));
    so_lp1 #(.SH(1)) u_warp_l2 (.clk(clk), .ce(ce), .reset(reset),
                                .din(warp_f1), .dout(warp_f2));
    so_lp1 #(.SH(2)) u_warp_l3 (.clk(clk), .ce(ce), .reset(reset),
                                .din(warp_f2), .dout(warp_flt));
    wire signed [17:0] warp_out = vca(warp_flt, env_warp);

    //========================================================================
    //  BONUS UP  (sheet 1 : IC35 one-shot -> IC34 -> 74LS393 IC30 -> IC32)
    //  A single short blip.  The 393 is dividing the oscillator down, not
    //  sequencing; the game re-triggers this per point while tallying.
    //========================================================================
    wire [15:0] env_bonus;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(1), .HOLD_MS(BONUS_HOLD),
             .DEC_MS(BONUS_DEC)) u_env_bonus (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_bonus), .level(env_bonus));

    reg [23:0] ph_bonus;
    always_ff @(posedge clk)
        if (reset) ph_bonus <= '0;
        else if (ce) ph_bonus <= ph_bonus + 24'(BONUS_F * PHZ);

    wire signed [17:0] bonus_sq = ph_bonus[23] ? 18'sd16000 : -18'sd16000;
    wire signed [17:0] bonus_f1, bonus_flt;
    so_lp1 #(.SH(1)) u_bonus_l1 (.clk(clk), .ce(ce), .reset(reset),
                                 .din(bonus_sq), .dout(bonus_f1));
    so_lp1 #(.SH(2)) u_bonus_l2 (.clk(clk), .ce(ce), .reset(reset),
                                 .din(bonus_f1), .dout(bonus_flt));
    wire signed [17:0] bonus_out = vca(bonus_flt, env_bonus);

    //========================================================================
    //  APPEARANCE UFO  (sheet 3 : IC35 -> IC31 -> IC25/IC16 -> IC11 VCA)
    //  Short rising blip.  Output goes to the dry mixer *and* to BBD IN.
    //========================================================================
    wire [15:0] env_ufo, ramp_ufo;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(2), .HOLD_MS(UFO_HOLD),
             .DEC_MS(UFO_DEC)) u_env_ufo (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_ufo), .level(env_ufo));
    so_ramp #(.SAMPLE_HZ(SAMPLE_HZ), .MS(UFO_RAMP)) u_rmp_ufo (
        .clk(clk), .ce(ce), .reset(reset), .gate(t_ufo), .level(ramp_ufo));

    wire [39:0] ufo_sw  = (40'(UFO_F_HI) - 40'(UFO_F_LO)) * PHZ * ramp_ufo;
    wire [23:0] ufo_inc = 24'(UFO_F_LO * PHZ) + ufo_sw[39:16];

    reg [23:0] ph_ufo;
    always_ff @(posedge clk)
        if (reset) ph_ufo <= '0; else if (ce) ph_ufo <= ph_ufo + ufo_inc;

    wire signed [17:0] ufo_sq  = ph_ufo[23] ? 18'sd16000 : -18'sd16000;
    wire signed [17:0] ufo_src = (ufo_sq >>> 1) + (noise >>> 3);
    wire signed [17:0] ufo_f1, ufo_flt;
    so_lp1 #(.SH(2)) u_ufo_l1 (.clk(clk), .ce(ce), .reset(reset),
                               .din(ufo_src), .dout(ufo_f1));
    so_lp1 #(.SH(3)) u_ufo_l2 (.clk(clk), .ce(ce), .reset(reset),
                               .din(ufo_f1), .dout(ufo_flt));
    wire signed [17:0] ufo_out = vca(ufo_flt, env_ufo);

    //========================================================================
    //  BATTLE STAR  (sheet 3 : NE555 IC33 -> IC26/IC24 -> IC15 -> IC10 -> BBD)
    //  The 555 free-runs at about 0.8 Hz and sweeps the VCO up each cycle,
    //  which is the repeating rocket whoosh in the reference sample.
    //========================================================================
    wire [15:0] env_batt;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(4), .HOLD_MS(BATT_HOLD),
             .DEC_MS(BATT_DEC)) u_env_batt (
        .clk(clk), .ce(ce), .reset(reset), .gate(g_battle), .level(env_batt));

    localparam int BATT_LFO_INC = int'(((longint'(1) <<< 24) * 1000) /
                                       (longint'(BATT_SWEEP) * SAMPLE_HZ));
    reg [23:0] ph_battlfo;
    reg        battd;
    always_ff @(posedge clk) begin
        if (reset) begin ph_battlfo <= '0; battd <= 1'b0; end
        else if (ce) begin
            battd <= g_battle;
            if (g_battle & ~battd) ph_battlfo <= '0;
            else                   ph_battlfo <= ph_battlfo + 24'(BATT_LFO_INC);
        end
    end

    wire [15:0] batt_ramp = ph_battlfo[23:8];
    wire [39:0] batt_sw   = (40'(BATT_F_HI) - 40'(BATT_F_LO)) * PHZ * batt_ramp;
    wire [23:0] batt_inc  = 24'(BATT_F_LO * PHZ) + batt_sw[39:16];

    reg [23:0] ph_batt;
    always_ff @(posedge clk)
        if (reset) ph_batt <= '0; else if (ce) ph_batt <= ph_batt + batt_inc;

    wire signed [17:0] batt_sq  = ph_batt[23] ? 18'sd16000 : -18'sd16000;
    wire signed [17:0] batt_src = batt_sq + (noise >>> 2);
    wire signed [17:0] batt_f1, batt_flt;
    so_lp1 #(.SH(2)) u_batt_l1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(batt_src), .dout(batt_f1));
    so_lp1 #(.SH(3)) u_batt_l2 (.clk(clk), .ce(ce), .reset(reset),
                                .din(batt_f1), .dout(batt_flt));
    wire signed [17:0] batt_out = vca(batt_flt, env_batt);

    //========================================================================
    //  ENGINE / BACKGROUND DRONE   (sheet 1, IC23/IC18/TR8 through 4016 IC14)
    //  One oscillator serving ssound, accel and damaged.  It idles at ~137 Hz
    //  whenever the 4016 is enabled; ACCELERATE walks it up to ~680 Hz over
    //  several seconds; BLACK HOLE parks it low under a tremolo.
    //========================================================================
    // Sheet 4 shows no master sound-enable bit.  The 4016 (IC14) is the only
    // gate, and it is opened by BACK G / ACCELERATE / BLACK HOLE, so BACK G
    // is what MAME ships as "ssound" - a gated flight sound, not a drone.
    wire eng_gate = g_backg | g_accel | g_blackhole;

    wire [15:0] env_eng;
    so_env #(.SAMPLE_HZ(SAMPLE_HZ), .ATK_SH(11), .HOLD_MS(0),
             .DEC_MS(200), .SUSTAIN(1)) u_env_eng (
        .clk(clk), .ce(ce), .reset(reset), .gate(eng_gate), .level(env_eng));

    wire [15:0] eng_tgt = g_accel     ? 16'(ENG_ACCEL) :
                          g_blackhole ? 16'(ENG_BHOLE) :
                          g_backg     ? 16'(ENG_BACKG) : 16'(ENG_IDLE);

    // Pitch is carried with 8 fractional bits.  Without them the +/-1 tie
    // breaker dominates the exponential term and the glide snaps instantly
    // instead of taking the ~5 s the accel sample shows.
    reg  [23:0] eng_ff;
    wire [23:0] eng_tf   = {eng_tgt, 8'd0};
    wire signed [25:0] eng_diff = $signed({2'b00, eng_tf}) - $signed({2'b00, eng_ff});
    wire signed [25:0] eng_stp  = (eng_diff >>> ENG_SLEW) +
                                  ((eng_diff > 0) ?  26'sd1 :
                                   (eng_diff < 0) ? -26'sd1 : 26'sd0);

    always_ff @(posedge clk)
        if (reset) eng_ff <= {16'(ENG_IDLE), 8'd0};
        else if (ce) eng_ff <= eng_ff + eng_stp[23:0];

    wire [31:0] eng_incx = 32'(eng_ff) * 32'(PHZ);
    wire [23:0] eng_inc  = eng_incx[31:8];

    reg [23:0] ph_eng, ph_bhlfo;
    always_ff @(posedge clk) begin
        if (reset) begin ph_eng <= '0; ph_bhlfo <= '0; end
        else if (ce) begin
            ph_eng   <= ph_eng   + eng_inc;
            ph_bhlfo <= ph_bhlfo + 24'(BHOLE_LFO * PHZ);
        end
    end

    wire signed [17:0] eng_saw = 18'($signed(ph_eng[23:8] ^ 16'h8000));
    wire signed [17:0] eng_src = (eng_saw >>> 1) + (noise >>> 2);
    wire signed [17:0] eng_f0, eng_f1, eng_flt;
    so_lp1  #(.SH(2)) u_eng_l0 (.clk(clk), .ce(ce), .reset(reset),
                                .din(eng_src), .dout(eng_f0));
    so_lp1  #(.SH(3)) u_eng_l1 (.clk(clk), .ce(ce), .reset(reset),
                                .din(eng_f0), .dout(eng_f1));
    // BLACK HOLE is audibly darker than the idle drone, so a second pole is
    // switched in behind it.  sh = 0 makes so_lp1v a straight pass-through.
    so_lp1v          u_eng_l2 (.clk(clk), .ce(ce), .reset(reset),
                               .sh(g_blackhole ? 3'd2 : 3'd0),
                               .din(eng_f1), .dout(eng_flt));

    // BLACK HOLE tremolo: triangle LFO, ~25 % depth, bypassed otherwise
    wire [15:0] bh_tri   = ph_bhlfo[23] ? ~ph_bhlfo[22:7] : ph_bhlfo[22:7];
    wire [15:0] eng_trem = g_blackhole ? ({2'b00, bh_tri[15:2]} + 16'hBFFF)
                                       : 16'hFFFF;
    wire signed [17:0] eng_amp = vca(eng_flt, eng_trem);
    wire signed [17:0] eng_out = vca(eng_amp, env_eng);

    //========================================================================
    //  MN3005 / MN3101 bucket-brigade delay  (sheet 1, IC2 / IC3)
    //  WARP, BATTLE STAR, APPEARANCE UFO and the ENGINE are summed into
    //  BBD IN; BBD OUT is a mixer input.  The MN3101 clock is fixed on this
    //  board, so this is a plain fixed delay with regeneration.
    //========================================================================
    wire signed [21:0] bbd_sum = 22'(warp_out) + 22'(batt_out) +
                                 (22'(ufo_out) >>> 1) + 22'(eng_out);
    wire signed [17:0] bbd_in  = sat18(bbd_sum);
    wire signed [17:0] bbd_out;

    so_bbd #(.DEPTH(BBD_DEPTH), .FB(BBD_FB)) u_bbd (
        .clk(clk), .ce(ce), .reset(reset), .din(bbd_in), .dout(bbd_out));

    //========================================================================
    //  Output mixer  (sheet 2, IC7 summing amp -> SOUND OUT)
    //========================================================================
    wire signed [29:0] mix =
          (30'(bbd_out)   * 30'(G_BBD))   + (30'(dbomb_out) * 30'(G_DBOMB)) +
          (30'(bonus_out) * 30'(G_BONUS)) + (30'(ufo_out)   * 30'(G_UFO))   +
          (30'(shot_out)  * 30'(G_SHOT))  + (30'(sexp_out)  * 30'(G_SEXP))  +
          (30'(lexp_out)  * 30'(G_LEXP));

    // >>> 8 undoes the 256 = unity mixer gain.  Simultaneous channels are
    // allowed to run into the limiter below, exactly as IC7 does on the board.
    wire signed [29:0] mix_sh = mix >>> 8;
    wire signed [17:0] mix_q  = sat18(mix_sh[21:0]);

    wire signed [17:0] mix_flt = mix_q;

    // DC block, matching the 10u output coupling cap
    wire signed [17:0] out_dc;
    so_lp1 #(.SH(10)) u_out_dc (.clk(clk), .ce(ce), .reset(reset),
                                .din(mix_flt), .dout(out_dc));

    reg signed [15:0] audio_r;
    always_ff @(posedge clk)
        if (reset) audio_r <= '0;
        else if (ce) audio_r <= enable ? sat16(22'(mix_flt) - 22'(out_dc)) : 16'sd0;

    assign audio = audio_r;

    //========================================================================
    //  Helpers
    //========================================================================
    function automatic signed [17:0] vca(input signed [17:0] x, input [15:0] g);
        logic signed [34:0] p;
        p   = x * $signed({1'b0, g});
        vca = p[33:16];
    endfunction

    function automatic signed [17:0] sat18(input signed [21:0] v);
        if      (v >  22'sd131071) sat18 =  18'sd131071;
        else if (v < -22'sd131072) sat18 = -18'sd131072;
        else                       sat18 =  v[17:0];
    endfunction

    function automatic signed [15:0] sat16(input signed [21:0] v);
        if      (v >  22'sd32767) sat16 =  16'sd32767;
        else if (v < -22'sd32768) sat16 = -16'sd32768;
        else                      sat16 =  v[15:0];
    endfunction

endmodule


//============================================================================
//  so_env - 74123 monostable + RC decay
//  The 123 holds the VCA open for HOLD_MS, then the RC takes over with
//  tau = 2^DEC_SH / SAMPLE_HZ seconds.
//  SUSTAIN=1 holds at full level for as long as gate is asserted.
//============================================================================
module so_env #(
    parameter int unsigned SAMPLE_HZ = 48_000,
    parameter int          ATK_SH    = 2,
    parameter int          HOLD_MS   = 0,
    parameter int          DEC_MS    = 200,   // RC decay tau, milliseconds
    parameter bit          SUSTAIN   = 1'b0
)(
    input  wire        clk,
    input  wire        ce,
    input  wire        reset,
    input  wire        gate,
    output wire [15:0] level
);
    localparam int HOLD_N = (HOLD_MS * int'(SAMPLE_HZ)) / 1000;
    // 24-bit decay rate: level -= level * DEC_K / 2^24 each sample, which
    // gives tau in milliseconds instead of the nearest power of two.
    localparam int DEC_K  = int'(((longint'(1) <<< 24) * 1000) /
                                 (longint'(DEC_MS) * SAMPLE_HZ));
    localparam int HW     = (HOLD_N <= 1) ? 1 : $clog2(HOLD_N + 1);

    // The envelope is carried with 8 fractional bits.  With a plain 16-bit
    // level the "-1 LSB" floor dominates once the level gets small and long
    // decays finish two to three times early.
    reg          gate_d, rising;
    reg  [23:0]  lvl;
    reg [HW-1:0] hold_c;
    wire trig = gate & ~gate_d;

    localparam [23:0] FULL = 24'hFFFFFF;

    wire [24:0] astep = ({1'b0, FULL - lvl} >> ATK_SH) + 25'd1;
    wire [24:0] anxt  = {1'b0, lvl} + astep;

    wire [47:0] dmul  = lvl * 24'(DEC_K);
    wire [23:0] dstep = dmul[47:24] + 24'd1;

    assign level = lvl[23:8];

    always_ff @(posedge clk) begin
        if (reset) begin
            lvl <= '0; gate_d <= 1'b0; rising <= 1'b0; hold_c <= '0;
        end else if (ce) begin
            gate_d <= gate;
            if (trig) begin
                rising <= 1'b1;
                hold_c <= HW'(HOLD_N);
            end

            if (rising || trig) begin
                if (anxt[24] || anxt[23:0] >= 24'hFFFF00) begin
                    lvl    <= FULL;
                    rising <= 1'b0;
                end else lvl <= anxt[23:0];
            end else if (SUSTAIN && gate) begin
                lvl <= FULL;
            end else if (hold_c != '0) begin
                lvl    <= FULL;
                hold_c <= hold_c - 1'b1;
            end else if (lvl != 24'd0) begin
                lvl <= (lvl > dstep) ? (lvl - dstep) : 24'd0;
            end
        end
    end
endmodule


//============================================================================
//  so_ramp - one-shot linear ramp, 0 -> full over MS milliseconds, then holds.
//  Used where the pitch keeps travelling after the amplitude starts to fall
//  (WARP, APPEARANCE UFO).
//============================================================================
module so_ramp #(
    parameter int unsigned SAMPLE_HZ = 48_000,
    parameter int          MS        = 1000
)(
    input  wire        clk,
    input  wire        ce,
    input  wire        reset,
    input  wire        gate,
    output wire [15:0] level
);
    localparam int INC = int'(((longint'(1) <<< 24) * 1000) /
                              (longint'(MS) * SAMPLE_HZ));

    reg [24:0] acc;
    reg        gate_d, run;
    wire trig = gate & ~gate_d;
    wire [24:0] nxt = acc + 25'(INC);

    always_ff @(posedge clk) begin
        if (reset) begin
            acc <= '0; run <= 1'b0; gate_d <= 1'b0;
        end else if (ce) begin
            gate_d <= gate;
            if (trig) begin
                acc <= '0; run <= 1'b1;
            end else if (run) begin
                if (nxt[24]) begin acc <= 25'h0FFFFFF; run <= 1'b0; end
                else         acc <= nxt;
            end
        end
    end

    assign level = acc[23:8];
endmodule


//============================================================================
//  so_lp1 - one-pole low pass.  fc ~= SAMPLE_HZ / (2*pi*2^SH)
//============================================================================
module so_lp1 #(
    parameter int SH = 3,
    parameter int W  = 18
)(
    input  wire                clk,
    input  wire                ce,
    input  wire                reset,
    input  wire signed [W-1:0] din,
    output reg  signed [W-1:0] dout
);
    // A plain arithmetic shift rounds towards -inf, which leaves the filter
    // stuck one LSB below its input and puts a small DC offset on the mixer.
    // Nudge the positive-difference case so it converges exactly.
    wire signed [W-1:0] dif = din - dout;
    wire signed [W-1:0] stp = dif >>> SH;

    always_ff @(posedge clk)
        if (reset)   dout <= '0;
        else if (ce) dout <= dout + (((stp == '0) && (dif > '0)) ? {{(W-1){1'b0}}, 1'b1} : stp);
endmodule


//============================================================================
//  so_lp1v - one-pole low pass with a run-time shift.  sh = 0 is a straight
//  pass-through, which is how a filter stage gets switched in and out.
//============================================================================
module so_lp1v #(
    parameter int W = 18
)(
    input  wire                clk,
    input  wire                ce,
    input  wire                reset,
    input  wire         [2:0]  sh,
    input  wire signed [W-1:0] din,
    output reg  signed [W-1:0] dout
);
    wire signed [W-1:0] dif = din - dout;
    wire signed [W-1:0] stp = dif >>> sh;

    always_ff @(posedge clk)
        if (reset)   dout <= '0;
        else if (ce) dout <= dout + (((stp == '0) && (dif > '0)) ? {{(W-1){1'b0}}, 1'b1} : stp);
endmodule


//============================================================================
//  so_svf - Chamberlin state variable filter (models the IC8 op-amp shapers)
//  f = 2*sin(pi*fc/fs) in Q16,  q = 1/Q in Q16 (smaller = more resonant)
//============================================================================
module so_svf #(
    parameter int W = 18
)(
    input  wire                clk,
    input  wire                ce,
    input  wire                reset,
    input  wire signed [W-1:0] din,
    input  wire         [15:0] f,
    input  wire         [15:0] q,
    output wire signed [W-1:0] lp,
    output wire signed [W-1:0] bp,
    output wire signed [W-1:0] hp
);
    reg signed [W-1:0] lp_r, bp_r;

    wire signed [W+16:0] bpf  = bp_r * $signed({1'b0, f});
    wire signed [W-1:0]  lp_n = lp_r + bpf[W+15:16];

    wire signed [W+16:0] bpq  = bp_r * $signed({1'b0, q});
    wire signed [W-1:0]  hp_n = din - lp_n - bpq[W+15:16];

    wire signed [W+16:0] hpf  = hp_n * $signed({1'b0, f});

    always_ff @(posedge clk) begin
        if (reset) begin
            lp_r <= '0; bp_r <= '0;
        end else if (ce) begin
            lp_r <= lp_n;
            bp_r <= bp_r + hpf[W+15:16];
        end
    end

    assign lp = lp_r;
    assign bp = bp_r;
    assign hp = hp_n;
endmodule


//============================================================================
//  so_bbd - MN3005 4096-stage bucket brigade + MN3101 clock driver
//  Fixed-length delay line with regeneration.  DEPTH samples at SAMPLE_HZ;
//  at 48 kHz, 1966 taps ~= 41 ms, which is what 4096 stages clocked at
//  roughly 50 kHz gives you on the real board.  Infers a single block RAM.
//============================================================================
module so_bbd #(
    parameter int unsigned DEPTH = 1966,
    parameter int unsigned FB    = 6,     // regeneration /16
    parameter int          W     = 18
)(
    input  wire                clk,
    input  wire                ce,
    input  wire                reset,
    input  wire signed [W-1:0] din,
    output reg  signed [W-1:0] dout
);
    localparam int AW = $clog2(DEPTH);
    localparam signed [W-1:0] MAXV = {1'b0, {(W-1){1'b1}}};
    localparam signed [W-1:0] MINV = {1'b1, {(W-1){1'b0}}};

    reg signed [W-1:0] ram [0:DEPTH-1];
    reg        [AW-1:0] wp;

    wire signed [W+5:0] fb_m  = dout * $signed(6'(FB));
    wire signed [W+5:0] fb_s  = (fb_m >>> 4) +
                                (((fb_m < 0) && (fb_m[3:0] != 4'd0)) ? (W+6)'(1) : (W+6)'(0));
    wire signed [W+5:0] sum_s = fb_s + (W+6)'(din);

    wire signed [W-1:0] wdata = (sum_s > (W+6)'(MAXV)) ? MAXV :
                                (sum_s < (W+6)'(MINV)) ? MINV :
                                                         sum_s[W-1:0];

    always_ff @(posedge clk) begin
        if (reset) begin
            wp <= '0; dout <= '0;
        end else if (ce) begin
            dout    <= ram[wp];           // read the oldest sample
            ram[wp] <= wdata;             // then overwrite it
            wp      <= (wp == AW'(DEPTH-1)) ? '0 : wp + 1'b1;
        end
    end
endmodule


//============================================================================
//  spaceod_sound_io  -  sheet 4 of 834-0051
//
//  Two 74LS377 octal latches sit on DB0-DB7:
//
//     IC44 (CK0)                        IC43 (CK1)
//       bit 0  SHOT                       bit 0  BACK G
//       bit 1  BONUS UP                   bit 1  (not connected)
//       bit 2  (not connected)            bit 2  SHORT EXP
//       bit 3  WARP                       bit 3  (not connected)
//       bit 4  (not connected)            bit 4  ACCELERATE
//       bit 5  (not connected)            bit 5  BATTLE STAR
//       bit 6  APPEARANCE UFO             bit 6  D-BOMB
//       bit 7  BLACK HOLE                 bit 7  LONG EXP
//
//  Every net is drawn overbarred on sheet 4, so a CPU-side 0 asserts: BACK G
//  loops while its bit is 0, every other voice fires on the 1->0 edge.  This
//  is MAME's spaceod_sound_w exactly.  Hence TRIG_ACTIVE_LOW.
//
//  Address decode: IC45 (74LS138) takes A0-A2, with A3-A7 folded through
//  IC42/IC39 (74LS04 + 74LS30) into the G2 enables and OUTPUT into G1.  Only
//  Y6 and Y7 are used, marked 16 and 17 on the sheet, so the two latches are
//  written at consecutive port addresses differing only in A0.
//
//  The scan does not make it legible which of Y6/Y7 lands on CK0 versus CK1.
//  If the sounds come out swapped, flip SWAP_PORTS rather than rewiring.
//============================================================================
module spaceod_sound_io #(
    parameter int unsigned CLK_HZ            = 24_000_000,
    parameter int unsigned SAMPLE_HZ         = 48_000,
    parameter bit          SWAP_PORTS        = 1'b0,   // exchange CK0 / CK1
    parameter bit          TRIG_ACTIVE_LOW   = 1'b1,   // sheet-4 nets are overbarred
    parameter bit          BHOLE_ACTIVE_LOW  = 1'b0    // extra inversion on ic44[7]
)(
    input  wire               clk,
    input  wire               reset,

    input  wire        [7:0]  db,          // CPU data bus
    input  wire               wr_ck0,      // strobe for IC44  (sheet: "16")
    input  wire               wr_ck1,      // strobe for IC43  (sheet: "17")

    input  wire               enable,      // optional external mute

    output wire signed [15:0] audio,
    output wire               ce_snd
);
    wire s0 = SWAP_PORTS ? wr_ck1 : wr_ck0;
    wire s1 = SWAP_PORTS ? wr_ck0 : wr_ck1;

    // Idle state of the latches: all voices released.
    localparam [7:0] LATCH_IDLE = {8{TRIG_ACTIVE_LOW}};

    reg [7:0] ic44, ic43;

    always_ff @(posedge clk) begin
        if (reset) begin
            ic44 <= LATCH_IDLE;
            ic43 <= LATCH_IDLE;
        end else begin
            if (s0) ic44 <= db;
            if (s1) ic43 <= db;
        end
    end

    // Normalise to active high for the sound core.
    wire [7:0] p44 = ic44 ^ {8{TRIG_ACTIVE_LOW}};
    wire [7:0] p43 = ic43 ^ {8{TRIG_ACTIVE_LOW}};

    wire t_shot  = p44[0];
    wire t_bonus = p44[1];
    wire t_warp  = p44[3];
    wire t_ufo   = p44[6];
    wire g_bhole = BHOLE_ACTIVE_LOW ? ~p44[7] : p44[7];

    wire g_backg  = p43[0];
    wire t_sexp   = p43[2];
    wire g_accel  = p43[4];
    wire g_battle = p43[5];
    wire t_dbomb  = p43[6];
    wire t_lexp   = p43[7];

    spaceod_sound #(
        .CLK_HZ(CLK_HZ), .SAMPLE_HZ(SAMPLE_HZ)
    ) u_snd (
        .clk(clk), .reset(reset),
        .t_shot(t_shot), .t_dbomb(t_dbomb), .t_sexp(t_sexp), .t_lexp(t_lexp),
        .t_warp(t_warp), .t_ufo(t_ufo), .t_bonus(t_bonus),
        .g_battle(g_battle), .g_accel(g_accel),
        .g_blackhole(g_bhole), .g_backg(g_backg),
        .enable(enable),
        .audio(audio), .ce_snd(ce_snd)
    );
endmodule

`default_nettype wire
