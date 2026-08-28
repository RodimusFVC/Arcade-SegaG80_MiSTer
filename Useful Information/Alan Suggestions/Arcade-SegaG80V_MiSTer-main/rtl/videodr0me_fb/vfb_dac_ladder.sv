// ============================================================================
// vfb_dac_ladder: per-gun 2-bit DAC level
//
// LOCAL ADDITION to Videodr0me's videodr0me_fb, for the Sega G-80 X-Y core.
//
// Major Havoc carries two red bits {strong, fine} against 1-bit green and
// blue, so only red needed a level ladder and it was inline in vfb_readout.
// The Sega G-80 X-Y Control board drives all three guns from identical 2-bit
// weighted ladders (6.2k/12k with 1N914s, drawing 800-0163 sheet 6/6), giving
//
//     level 0 1 2 3  ->  0, 1/3, 2/3, 1  of full scale
//
// on every channel. Pulled out of vfb_readout so it can be checked
// exhaustively against a model of the resistor network (sim: make color6).
//
// The thirds are (v*683)>>11 and (v*1365)>>11, within one LSB of exact at
// 10 bits.
// ============================================================================

`default_nettype none

module vfb_dac_ladder (
	input  wire  [9:0] level,     // full-scale DAC value for this pixel
	input  wire  [1:0] sel,       // gun level, 0..3
	output logic [9:0] out
);
	logic [20:0] scaled;
	always_comb begin
		scaled = 21'd0;
		unique case (sel)
			2'd0: out = 10'd0;
			2'd1: begin scaled = level * 21'd683;  out = scaled[20:11]; end
			2'd2: begin scaled = level * 21'd1365; out = scaled[20:11]; end
			2'd3: out = level;
		endcase
	end
endmodule

`default_nettype wire
