// ---------------------------------------------------------------------------
// sega005_sound.v -- top level for the Sega 005 sound board, drawing 834-0130
//
// Bus side matches the G-80 card-cage interface as seen by the board: a chip
// select plus A0/A1 into the 8255 (U5). In the G-80 I/O map that lands at
// Z80 ports $0C-$0F.
//
// The eight VOL_* parameters stand in for VR1..VR8, the eight 50k trimmers
// along the top of the board -- one per voice. VR9 (500 ohm) is the overall
// output trim and is folded into MASTER_VOL.
// ---------------------------------------------------------------------------

`default_nettype none

module sega005_sound #(
    parameter integer CLK_HZ       = 50_000_000,
    parameter integer AUDIO_HZ     = 48_000,

    // U4 74LS14 oscillator, R134 + VR9 with C9. VR9 is the melody pitch trim:
    // 369 kHz at the slow end, 1.21 MHz at the fast end, 566 kHz centred.
    parameter integer LS161_CLK_HZ = 566_000,
    parameter integer NOISE_HZ     = 40_000,

    // ROM images, one hex byte per line
    parameter         ROM_FILE     = "epr-1286.hex",   // 2716  U16, 2048x8
    parameter         PROM_FILE    = "pr-5001.hex",    // 6331  U8,     32x8

    // The eight 50k trimmers, 0..255. Sheet 8 gives the assignment:
    //   VR1 small expl   VR2 large expl   VR3 missile    VR4 melody
    //   VR5 pistol       VR6 whistle      VR7 bomb drop  VR8 helicopter
    // Every channel reaches the summing node through an identical 51k
    // (R125-R132) and 1uF, so the trimmers alone set the balance.
    parameter [7:0]   VR4_MELODY     = 8'd150,
    parameter [7:0]   VR2_LEXPL      = 8'd200,
    parameter [7:0]   VR1_SEXPL      = 8'd170,
    parameter [7:0]   VR7_BOMB       = 8'd150,
    parameter [7:0]   VR5_SHOOT      = 8'd140,
    parameter [7:0]   VR3_MISSILE    = 8'd150,
    parameter [7:0]   VR8_HELICOPTER = 8'd120,
    parameter [7:0]   VR6_WHISTLE    = 8'd110,

    // U26 summing amp, R118 10k in / R117 47k feedback -> gain 4.7
    parameter [7:0]   MASTER_VOL     = 8'd200
)(
    input  wire        clk,
    input  wire        rst_n,

    // CPU / G-80 bus
    input  wire        cs_n,
    input  wire        wr_n,
    input  wire        rd_n,
    input  wire [1:0]  cpu_addr,
    input  wire [7:0]  cpu_din,
    output wire [7:0]  cpu_dout,

    // Audio
    output reg signed [15:0] audio,      // to your I2S / codec path
    output reg               audio_pwm   // 1-bit sigma-delta, for an RC filter
);

    // -----------------------------------------------------------------------
    // Audio-rate strobe for every filter and envelope on the board
    // -----------------------------------------------------------------------
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
    // U5 -- 8255 PPI
    // -----------------------------------------------------------------------
    wire [7:0] pa, pb, pc;

    i8255_mode0 u5 (
        .clk(clk), .rst_n(rst_n),
        .cs_n(cs_n), .wr_n(wr_n), .rd_n(rd_n),
        .addr(cpu_addr), .din(cpu_din), .dout(cpu_dout),
        .pa(pa), .pb(pb), .pc(pc)
    );

    // -----------------------------------------------------------------------
    // U16 -- 2716 tune ROM, U8 -- 6331 32x8 divisor PROM
    // -----------------------------------------------------------------------
    wire [10:0] rom_addr;
    wire [7:0]  rom_q;
    wire [4:0]  prom_addr;
    wire [7:0]  prom_q;

    rom_sync #(.AW(11), .DEPTH(2048), .INIT_FILE(ROM_FILE))
        u16 (.clk(clk), .addr(rom_addr), .q(rom_q));

    rom_sync #(.AW(5), .DEPTH(32), .INIT_FILE(PROM_FILE))
        u8  (.clk(clk), .addr(prom_addr), .q(prom_q));

    // -----------------------------------------------------------------------
    // Melody chain
    // -----------------------------------------------------------------------
    wire signed [15:0] mel;

    melody_gen #(
        .CLK_HZ(CLK_HZ),
        .AUDIO_HZ(AUDIO_HZ),
        .LS161_CLK_HZ(LS161_CLK_HZ)
    ) melody (
        .clk(clk), .rst_n(rst_n),
        .tick(tick), .pb(pb),
        .rom_addr(rom_addr), .rom_q(rom_q),
        .prom_addr(prom_addr), .prom_q(prom_q),
        .audio(mel)
    );

    // -----------------------------------------------------------------------
    // U13 noise + the seven discrete voices
    // -----------------------------------------------------------------------
    wire signed [17:0] noise1;

    mm5837_noise #(.CLK_HZ(CLK_HZ), .NOISE_HZ(NOISE_HZ))
        u13 (.clk(clk), .rst_n(rst_n), .noise_bit(), .noise_out(noise1));

    wire signed [15:0] lexpl, sexpl, bomb, shoot, missile, heli, whistle;

    fx_bank #(.CLK_HZ(CLK_HZ), .AUDIO_HZ(AUDIO_HZ)) fx (
        .clk(clk), .rst_n(rst_n), .tick(tick),
        .pa(pa), .noise1(noise1),
        .ch_lexpl(lexpl), .ch_sexpl(sexpl), .ch_bomb(bomb),
        .ch_shoot(shoot), .ch_missile(missile),
        .ch_helicopter(heli), .ch_whistle(whistle)
    );

    // -----------------------------------------------------------------------
    // Summing amp (one section of an LM324) with VR1..VR9
    // -----------------------------------------------------------------------
    function signed [24:0] trim;
        input signed [15:0] s;
        input        [7:0]  v;
        reg   signed [24:0] p;
        begin
            p    = s * $signed({1'b0, v});
            trim = p;
        end
    endfunction

    wire signed [28:0] sum = trim(mel,     VR4_MELODY)
                           + trim(lexpl,   VR2_LEXPL)
                           + trim(sexpl,   VR1_SEXPL)
                           + trim(bomb,    VR7_BOMB)
                           + trim(shoot,   VR5_SHOOT)
                           + trim(missile, VR3_MISSILE)
                           + trim(heli,    VR8_HELICOPTER)
                           + trim(whistle, VR6_WHISTLE);

    // >>> 8 undoes the 0..255 trim scaling. The summing amp saturates on
    // loud combinations, exactly as the LM324 stage does on the real board.
    wire signed [28:0] scaled = sum >>> 8;

    reg signed [15:0] mixed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mixed <= 16'sd0;
        else if (scaled >  29'sd32767) mixed <=  16'sd32767;
        else if (scaled < -29'sd32768) mixed <= -16'sd32768;
        else mixed <= scaled[15:0];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) audio <= 16'sd0;
        else        audio <= trim(mixed, MASTER_VOL) >>> 8;
    end

    // -----------------------------------------------------------------------
    // Second-order sigma-delta for a 1-bit output pin
    // -----------------------------------------------------------------------
    reg signed [19:0] sd1, sd2;
    wire signed [19:0] fb = audio_pwm ? 20'sd32767 : -20'sd32767;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sd1 <= 20'sd0;
            sd2 <= 20'sd0;
            audio_pwm <= 1'b0;
        end else begin
            sd1 <= sd1 + ({{4{audio[15]}}, audio} - fb);
            sd2 <= sd2 + (sd1 - fb);
            audio_pwm <= ~sd2[19];
        end
    end

endmodule


// ---------------------------------------------------------------------------
// rom_sync.v -- registered ROM, initialised from a hex file.
// Vivado, Quartus and Yosys all infer block RAM from this.
// ---------------------------------------------------------------------------

module rom_sync #(
    parameter integer AW        = 11,
    parameter integer DEPTH     = 2048,
    parameter         INIT_FILE = ""
)(
    input  wire          clk,
    input  wire [AW-1:0] addr,
    output reg  [7:0]    q
);
    reg [7:0] mem [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always @(posedge clk) q <= mem[addr];
endmodule

`default_nettype wire
