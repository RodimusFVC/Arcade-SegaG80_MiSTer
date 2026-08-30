// ---------------------------------------------------------------------------
// melody_gen.v -- Sega 005 sound board (834-0130) melody generator
//
// Reproduces the U3/U9/U16/U8/U7/U15/U14/U32 chain:
//
//   NE555 U3 (astable, R5=15k R4=4k7 C120=1u5)  -> 39.344 Hz tempo clock
//     |   gated/reset by 2716 data bit 5
//     v
//   74LS393 U9 (8-bit ripple counter, async CLR from port B bit 4)
//     |   counter[7:1] = low 7 address bits  (the ">>1" in the schematic)
//     v
//   2716 U16 (EPR-1286), addr = { PB[3:0], counter[7:1] }
//     |   D[4:0] -> PROM address
//     |   D5     -> 555 run/reset
//     |   D6,D7  -> unused / unknown
//     v
//   6331 U8 (32x8 bipolar PROM, PR-5001) -> 8-bit reload value N
//     |
//     v
//   74LS161 x2 (U7,U15) 8-bit counter, reloads N on overflow
//     |   period = 256-N ticks  ->  carry pulse
//     v
//   74LS293 U14, carry drives the QB stage (i.e. +2 per carry)
//     |   QB and QD summed through unequal resistors
//     v
//   MB4391 U32 (VCA) -> melody output
//
// The LS161 clock is a 74LS14 Schmitt relaxation oscillator built from U4,
// R134 (220R) in series with VR9 (500R) and C9 (4700pF). VR9 is therefore the
// melody PITCH TRIM, not a volume control as the BOM description suggests.
//   f = 1 / (0.8 * R * C)
//   R = 220R  -> 1.21 MHz     R = 470R -> 566 kHz     R = 720R -> 369 kHz
//
// The perceived melody pitch is the LS293 QD rate, i.e. carry/8, so
//   f_note = f_osc / (8 * (256 - N))
// which with the pot centred spans roughly 276 Hz to 2 kHz over the useful
// range of N. QB (carry/2) rides on top as a strong fourth harmonic.
//
// Verilog-2001. No vendor primitives.
// ---------------------------------------------------------------------------

`default_nettype none

module melody_gen #(
    parameter integer CLK_HZ        = 50_000_000,

    // NE555 U3 astable rate in millihertz.
    // f = 1.44 / ((R5 + 2*R4) * C120) = 1.44 / ((15k + 9k4) * 1.5uF) = 39.344 Hz
    parameter integer TEMPO_MILLIHZ = 39_344,

    // U4 74LS14 relaxation oscillator, R = R134 + VR9, C = C9.
    // 369 kHz .. 1.21 MHz over the pot range; 566 kHz is the centre.
    parameter integer LS161_CLK_HZ  = 566_000,

    // 1 = take counter[7:1] as the ROM address (matches the schematic).
    // 0 = take counter[6:0] (matches MAME, which runs the tune 2x fast).
    parameter integer DIV2_ADDR     = 1,

    // MAME treats a reload value of 0xFF as filtered out by the following RC.
    parameter integer SKIP_FF       = 1,

    // LS293 QB feeds the summing node through R34 (27k), QD through R50 (15k),
    // so the weights go as 1/27k : 1/15k = 0.556 : 1. QD, the fundamental,
    // dominates and QB adds the fourth harmonic.
    parameter signed [17:0] W_QB    = 18'sd14000,
    parameter signed [17:0] W_QD    = 18'sd25200,

    // Output shaping: C33 (.1u) into R135 (10k) is a 159 Hz high pass,
    // R135 with C34 (.01u) is a 1592 Hz low pass.
    parameter integer HP_HZ         = 159,
    parameter integer LP_HZ         = 1592,

    // U2 74123 melody gate, t = 0.45 * R7 * C14 = 0.45 * 47k * 3.3u = 0.70 s,
    // retriggered by every 555 pulse, so the VCA stays open while the tune
    // runs and fades out after it stops.
    parameter integer GATE_MS       = 700,
    parameter integer AUDIO_HZ      = 48_000
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               tick,        // AUDIO_HZ strobe
    input  wire [7:0]         pb,          // 8255 U5 port B

    output wire [10:0]        rom_addr,    // 2716 U16
    input  wire [7:0]         rom_q,
    output wire [4:0]         prom_addr,   // 6331 U8
    input  wire [7:0]         prom_q,

    output wire signed [15:0] audio
);

    localparam [63:0] TEMPO_DIV = ((64'd1000 * CLK_HZ) / TEMPO_MILLIHZ) - 64'd1;

    // Phase-accumulator step for the LS161 clock, so the pitch is not
    // quantised by an integer clock divide.
    localparam [63:0] INC161 = ((64'd0 + LS161_CLK_HZ) << 32) / CLK_HZ;

    // -----------------------------------------------------------------------
    // Port B decode
    // -----------------------------------------------------------------------
    wire        pb_hold   = pb[4];   // 1 = hold LS393 (and the divider) at 0
    wire        pb_auto   = pb[5];   // 1 = 555 clocks the LS393, 0 = manual
    wire        pb_mclk   = pb[6];   // manual clock, active on 0->1
    wire [3:0]  pb_page   = pb[3:0]; // upper 4 bits of the 2716 address

    // -----------------------------------------------------------------------
    // NE555 U3 -- tempo oscillator, held in reset while 2716 D5 is low
    // -----------------------------------------------------------------------
    wire        tempo_run = rom_q[5];
    reg [31:0]  tempo_cnt;
    reg         tempo_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tempo_cnt  <= 32'd0;
            tempo_tick <= 1'b0;
        end else if (!tempo_run) begin
            tempo_cnt  <= 32'd0;      // 555 RESET pin asserted
            tempo_tick <= 1'b0;
        end else if (tempo_cnt >= TEMPO_DIV[31:0]) begin
            tempo_cnt  <= 32'd0;
            tempo_tick <= 1'b1;
        end else begin
            tempo_cnt  <= tempo_cnt + 32'd1;
            tempo_tick <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // 74LS393 U9 -- sequence address counter
    // -----------------------------------------------------------------------
    reg [7:0] seq_cnt;
    reg       mclk_d;
    wire      mclk_rise = pb_mclk & ~mclk_d;
    wire      seq_clk   = pb_auto ? tempo_tick : mclk_rise;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq_cnt <= 8'd0;
            mclk_d  <= 1'b0;
        end else begin
            mclk_d <= pb_mclk;
            if (pb_hold)         seq_cnt <= 8'd0;   // async CLR, level held
            else if (seq_clk)    seq_cnt <= seq_cnt + 8'd1;
        end
    end

    assign rom_addr  = (DIV2_ADDR != 0) ? {pb_page, seq_cnt[7:1]}
                                        : {pb_page, seq_cnt[6:0]};
    assign prom_addr = rom_q[4:0];

    // -----------------------------------------------------------------------
    // 74LS161 x2 (U7,U15) -- reload-on-overflow divider, period = 256-N
    // -----------------------------------------------------------------------
    reg [32:0] acc161;
    wire       tick161 = acc161[32];

    reg [7:0]  q161;
    reg        carry;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc161 <= 33'd0;
            q161   <= 8'd0;
            carry  <= 1'b0;
        end else begin
            carry  <= 1'b0;
            acc161 <= {1'b0, acc161[31:0]} + INC161[32:0];

            if (pb_hold) begin
                q161 <= prom_q;
            end else if (tick161) begin
                if (q161 == 8'hFF) begin
                    q161  <= prom_q;
                    carry <= (SKIP_FF != 0) ? (prom_q != 8'hFF) : 1'b1;
                end else begin
                    q161 <= q161 + 8'd1;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // 74LS293 U14 -- carry clocks the QB stage, so QB=bit0, QC=bit1, QD=bit2
    // of a 3-bit counter running off the carry pulse.
    // -----------------------------------------------------------------------
    reg [2:0] q293;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          q293 <= 3'd0;
        else if (pb_hold)    q293 <= 3'd0;
        else if (carry)      q293 <= q293 + 3'd1;
    end

    wire qb = q293[0];
    wire qd = q293[2];

    // -----------------------------------------------------------------------
    // Resistive summing node, then C33/R135/C34, then the U32 VCA
    // -----------------------------------------------------------------------
    wire signed [17:0] raw = (qb ? W_QB : -W_QB) + (qd ? W_QD : -W_QD);

    wire signed [17:0] shaped_lp, shaped_hp;

    // 159 Hz high pass
    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(HP_HZ), .Q_X100(71))
        f_hp (.clk(clk), .rst_n(rst_n), .tick(tick), .in(raw),
              .lp(), .bp(), .hp(shaped_hp));

    // 1592 Hz low pass
    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(LP_HZ), .Q_X100(71))
        f_lp (.clk(clk), .rst_n(rst_n), .tick(tick), .in(shaped_hp),
              .lp(shaped_lp), .bp(), .hp());

    // -----------------------------------------------------------------------
    // U2 74123 gate + C27/R10/R11 into the U32 control pin
    // -----------------------------------------------------------------------
    localparam [63:0] GATE_N = (64'd0 + GATE_MS) * AUDIO_HZ / 64'd1000;

    reg [23:0] gate_cnt;
    wire       gate_on = (gate_cnt != 24'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            gate_cnt <= 24'd0;
        else if (tempo_tick)   gate_cnt <= GATE_N[23:0];   // retriggerable
        else if (tick && gate_on) gate_cnt <= gate_cnt - 24'd1;
    end

    reg [15:0] mel_env;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mel_env <= 16'd0;
        else if (tick) begin
            if (gate_on) mel_env <= mel_env + ((16'hFFFF - mel_env) >> 5);
            else         mel_env <= mel_env - (mel_env >> 15);   // tau 0.68 s
        end
    end

    function signed [15:0] vca;
        input signed [17:0] s;
        input        [15:0] g;
        reg signed [34:0] p;
        begin
            p   = s * $signed({1'b0, g});
            vca = p[33:18];
        end
    endfunction

    assign audio = vca(shaped_lp, mel_env);

endmodule

`default_nettype wire
