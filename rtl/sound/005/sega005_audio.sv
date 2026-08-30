// ---------------------------------------------------------------------------
// sega005_audio.sv -- top level for the Sega 005 sound board, drawing 834-0130
//
// Bus side matches the G-80 card-cage interface as seen by the board: a chip
// select plus A0/A1 into the 8255 (U5). In the G-80 I/O map that lands at
// Z80 ports $0C-$0F, so $0C = port A (the seven effect triggers) and
// $0D = port B (the melody generator).
//
// MAME emulates only port B's melody chain (segag80r_a.cpp sega005_sound_device)
// and plays the seven effects as WAV samples. Everything here is synthesized
// from the schematic instead, so no sample data is needed.
//
// The eight VOL_* parameters stand in for VR1..VR8, the eight 50k trimmers
// along the top of the board -- one per voice. VR9 (500 ohm) is the overall
// output trim and is folded into MASTER_VOL.
//
// The 2716 melody ROM (U16) and the 6331 divisor PROM (U8) are loaded from
// the MRA over ioctl, not from a hex file.
// ---------------------------------------------------------------------------

`default_nettype none

// This core is DSP-saturated; keep the board's multipliers in logic.
(* multstyle = "logic" *)
module sega005_sound #(
    parameter integer CLK_HZ       = 15_468_480,
    parameter integer AUDIO_HZ     = 48_000,

    // U4 74LS14 oscillator, R134 + VR9 with C9. VR9 is the melody pitch trim:
    // 369 kHz at the slow end, 1.21 MHz at the fast end, 566 kHz centred.
    parameter integer LS161_CLK_HZ = 566_000,
    parameter integer NOISE_HZ     = 40_000,

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
    input  wire        reset,          // active high, core convention

    // i8255 (U5) write side, decoded in SegaG80_CPU as ports $0C-$0F.
    // 005 never reads the PPI, so no read path is wired.
    input  wire        ppi_wr,         // one clk_sys pulse per Z80 OUT
    input  wire [1:0]  ppi_addr,
    input  wire [7:0]  ppi_din,

    // epr-1286.sound-16 at ioctl index 5, 6331.sound-u8 at index 10
    input  wire [24:0] ioctl_addr,
    input  wire [7:0]  ioctl_data,
    input  wire        ioctl_wr,
    input  wire        sel_rom,
    input  wire        sel_prom,

    output reg signed [15:0] audio
);

    wire rst_n = ~reset;

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
    // U5 -- 8255 PPI. cs/wr are already decoded upstream; rd is tied off.
    // -----------------------------------------------------------------------
    wire [7:0] pa, pb, pc;

    i8255_mode0 u5 (
        .clk(clk), .rst_n(rst_n),
        .cs_n(~ppi_wr), .wr_n(~ppi_wr), .rd_n(1'b1),
        .addr(ppi_addr), .din(ppi_din), .dout(),
        .pa(pa), .pb(pb), .pc(pc)
    );

    // -----------------------------------------------------------------------
    // U16 -- 2716 tune ROM, U8 -- 6331 32x8 divisor PROM.
    // Both reads stay registered: prom_addr comes from rom_q, so the melody
    // chain is written against a two-cycle lookup.
    // -----------------------------------------------------------------------
    wire [10:0] rom_addr;
    wire [4:0]  prom_addr;
    reg  [7:0]  rom_q, prom_q;

    reg [7:0] tune_rom [0:2047];
    reg [7:0] div_prom [0:31];

    always @(posedge clk) begin
        if (ioctl_wr & sel_rom)  tune_rom[ioctl_addr[10:0]] <= ioctl_data;
        if (ioctl_wr & sel_prom) div_prom[ioctl_addr[4:0]]  <= ioctl_data;
        rom_q  <= tune_rom[rom_addr];
        prom_q <= div_prom[prom_addr];
    end

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
    // Each trim is its own module-level wire so the multstyle attribute can
    // reach it. Constant coefficients, so these fold to shift-add in logic.
    (* multstyle = "logic" *) wire signed [24:0] t_mel     = mel     * $signed({1'b0, VR4_MELODY});
    (* multstyle = "logic" *) wire signed [24:0] t_lexpl   = lexpl   * $signed({1'b0, VR2_LEXPL});
    (* multstyle = "logic" *) wire signed [24:0] t_sexpl   = sexpl   * $signed({1'b0, VR1_SEXPL});
    (* multstyle = "logic" *) wire signed [24:0] t_bomb    = bomb    * $signed({1'b0, VR7_BOMB});
    (* multstyle = "logic" *) wire signed [24:0] t_shoot   = shoot   * $signed({1'b0, VR5_SHOOT});
    (* multstyle = "logic" *) wire signed [24:0] t_missile = missile * $signed({1'b0, VR3_MISSILE});
    (* multstyle = "logic" *) wire signed [24:0] t_heli    = heli    * $signed({1'b0, VR8_HELICOPTER});
    (* multstyle = "logic" *) wire signed [24:0] t_whistle = whistle * $signed({1'b0, VR6_WHISTLE});

    wire signed [28:0] sum = t_mel + t_lexpl + t_sexpl + t_bomb
                           + t_shoot + t_missile + t_heli + t_whistle;

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

    (* multstyle = "logic" *) wire signed [24:0] t_master = mixed * $signed({1'b0, MASTER_VOL});

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) audio <= 16'sd0;
        else        audio <= t_master >>> 8;
    end

endmodule

`default_nettype wire
