//  Melody chain based on MAME segag80r_a.cpp (Aaron Giles, BSD-3-Clause); voices from the board schematic

`default_nettype none

(* multstyle = "logic" *)
module sega005_sound #(
    parameter integer CLK_HZ       = 15_468_480,
    parameter integer AUDIO_HZ     = 48_000,

    parameter integer LS161_CLK_HZ = 566_000,
    parameter integer NOISE_HZ     = 40_000,

    parameter [7:0]   VR4_MELODY     = 8'd150,
    parameter [7:0]   VR2_LEXPL      = 8'd200,
    parameter [7:0]   VR1_SEXPL      = 8'd170,
    parameter [7:0]   VR7_BOMB       = 8'd150,
    parameter [7:0]   VR5_SHOOT      = 8'd140,
    parameter [7:0]   VR3_MISSILE    = 8'd150,
    parameter [7:0]   VR8_HELICOPTER = 8'd120,
    parameter [7:0]   VR6_WHISTLE    = 8'd110,

    parameter [7:0]   MASTER_VOL     = 8'd200
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        ppi_wr,
    input  wire [1:0]  ppi_addr,
    input  wire [7:0]  ppi_din,

    output wire [10:0] rom9_a,
    input  wire [7:0]  rom9_d,
    output wire [4:0]  rom10_a,
    input  wire [7:0]  rom10_d,

    output reg signed [15:0] audio
);

    wire rst_n = ~reset;

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

    wire [7:0] pa, pb, pc;

    i8255_mode0 u5 (
        .clk(clk), .rst_n(rst_n),
        .cs_n(~ppi_wr), .wr_n(~ppi_wr), .rd_n(1'b1),
        .addr(ppi_addr), .din(ppi_din), .dout(),
        .pa(pa), .pb(pb), .pc(pc)
    );

    wire [10:0] rom_addr;
    wire [4:0]  prom_addr;
    wire [7:0]  rom_q  = rom9_d;
    wire [7:0]  prom_q = rom10_d;
    assign rom9_a  = rom_addr;
    assign rom10_a = prom_addr;

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
