// Test wrapper: exposes the three CPU-board I/O blocks under one top so a
// single Verilator model can check them all against MAME.

`default_nettype none

module ports_wrap (
	input  wire        clk,
	input  wire        reset,

	// mangled input matrix
	input  wire  [1:0] sel,
	input  wire  [7:0] d7d6,
	input  wire  [7:0] d5d4,
	input  wire  [7:0] d3d2,
	input  wire  [7:0] d1d0,
	output wire  [7:0] mangled,

	// multiplier
	input  wire        mul_wr,
	input  wire        mul_wr_sel,
	input  wire  [7:0] mul_din,
	input  wire        mul_rd,
	output wire  [7:0] mul_dout,

	// spinner
	input  wire signed [7:0] spin_delta,
	input  wire        spin_stb,
	input  wire  [7:0] fc_in,
	input  wire        sel_raw,
	output wire  [7:0] spin_dout,

	// eliminator 4-player demux
	input  wire  [7:0] e4_sel,
	input  wire  [7:0] e4_coins,
	output wire  [7:0] e4_dout
);

	sega_mangled_ports mp (
		.sel(sel), .d7d6(d7d6), .d5d4(d5d4), .d3d2(d3d2), .d1d0(d1d0),
		.dout(mangled)
	);

	sega_multiplier mul (
		.clk(clk), .reset(reset),
		.wr(mul_wr), .wr_sel(mul_wr_sel), .din(mul_din),
		.rd(mul_rd), .dout(mul_dout)
	);

	sega_spinner spin (
		.clk(clk), .reset(reset),
		.delta(spin_delta), .delta_stb(spin_stb),
		.fc_in(fc_in), .sel_raw(sel_raw), .dout(spin_dout)
	);

	sega_elim4_ports e4 (
		.sel(e4_sel), .fc_in(fc_in), .coins_in(e4_coins), .dout(e4_dout)
	);

endmodule

`default_nettype wire
