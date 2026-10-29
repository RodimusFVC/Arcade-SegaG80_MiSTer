//  Based on MAME segag80r_a.cpp (Aaron Giles, BSD-3-Clause)

`default_nettype none

module monsterb_music #(
    parameter int unsigned CLK_HZ = 15_468_480
)(
    output chip_pool_pkg::tms36xx_i_t tms36xx_0_i,
    input  chip_pool_pkg::tms36xx_o_t tms36xx_0_o,
    input  wire               clk,
    input  wire               reset,

    input  wire               port_a_wr,
    input  wire        [7:0]  port_a_din,

    input  wire        [4:0]  ioctl_addr,
    input  wire        [7:0]  ioctl_data,
    input  wire               ioctl_wr,

    output wire signed [15:0] audio
);

    reg [7:0] prom [0:31];   // POOL-EXCEPTION: 32 bytes, read combinationally (prom_q)
    always @(posedge clk) if (ioctl_wr) prom[ioctl_addr] <= ioctl_data;

    wire [7:0] prom_q = prom[{1'b0, port_a_din[7:4]}];

    assign tms36xx_0_i = '{tune_we: 1'b0, tune: 2'd0, note_we: port_a_wr, note_octave: 2'd0, note: port_a_din[3:0],
                           enable_we: port_a_wr, voice_enable: prom_q[7:2], cfg_b: 1'b0};
    assign audio = tms36xx_0_o.audio;

endmodule

`default_nettype wire
