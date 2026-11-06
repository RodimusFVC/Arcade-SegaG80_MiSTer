//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports. Copy this file to start a board.

module board_template #(
    parameter int RAM_BLOCKS = 5
) (
    input                                                clk,
    input                                                reset,
    input                                                ce,

    output chip_pool_pkg::z80_i_t                        z80_0_i,
    input  chip_pool_pkg::z80_o_t                        z80_0_o,
    output chip_pool_pkg::z80_i_t                        z80_1_i,
    input  chip_pool_pkg::z80_o_t                        z80_1_o,
    output chip_pool_pkg::mcs48_i_t                      mcs48_0_i,
    input  chip_pool_pkg::mcs48_o_t                      mcs48_0_o,
    output chip_pool_pkg::i8035_i_t                      i8035_0_i,
    input  chip_pool_pkg::i8035_o_t                      i8035_0_o,
    output chip_pool_pkg::sp0250_i_t                     sp0250_0_i,
    input  chip_pool_pkg::sp0250_o_t                     sp0250_0_o,
    output chip_pool_pkg::tms36xx_i_t                    tms36xx_0_i,
    input  chip_pool_pkg::tms36xx_o_t                    tms36xx_0_o,
    output chip_pool_pkg::sn76489_i_t [1:0]              sn76489_i,
    input  chip_pool_pkg::sn76489_o_t [1:0]              sn76489_o,

    output ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0]       pr_i,
    input  ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0]       pr_o,

    output      [15:0] rom0_a,  input  [7:0] rom0_d,
    output      [10:0] rom1_a,  input  [7:0] rom1_d,
    output      [12:0] rom2_a,  input  [7:0] rom2_d,
    output      [14:0] rom3_a,  input  [7:0] rom3_d,
    output      [12:0] rom4_a,  input  [7:0] rom4_d,
    output      [12:0] rom5_a,  input  [7:0] rom5_d,
    output      [13:0] rom6_a,  input  [7:0] rom6_d,
    output      [11:0] rom7_a,  input  [5:0][7:0] rom7_d,
    output      [12:0] rom8_a,  input  [7:0] rom8_d,
    output      [10:0] rom9_a,  input  [7:0] rom9_d,
    output       [4:0] rom10_a, input  [7:0] rom10_d,
    output       [9:0] rom11_a, input  [7:0] rom11_d,
    output      [12:0] rom12_a, input  [7:0] rom12_d,

    output               video_hsync, video_vsync,
    output               video_hblank, video_vblank,
    output               ce_pix,
    output         [7:0] video_r, video_g, video_b,
    output signed [15:0] audio_out
);

endmodule
