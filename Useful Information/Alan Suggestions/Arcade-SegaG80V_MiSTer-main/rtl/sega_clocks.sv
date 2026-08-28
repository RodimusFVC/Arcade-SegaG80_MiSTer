//============================================================================
//  Sega G-80 X-Y vector-generator clock
//
//  Structure follows major_havoc_clocks.sv by Videodr0me.
//
//  The G-80 X-Y boards run from a 15.46848 MHz crystal; the machine domain
//  runs at 12.096 MHz and derives the Z80 and VCL rates as fractional enables.
//============================================================================

module sega_clocks
(
	input  logic refclk,
	input  logic reset,
	output logic clk_vec,
	output logic locked
);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("12.096000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) vec_pll (
		.refclk(refclk),
		.rst(reset),
		.outclk(clk_vec),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0)
	);

endmodule
