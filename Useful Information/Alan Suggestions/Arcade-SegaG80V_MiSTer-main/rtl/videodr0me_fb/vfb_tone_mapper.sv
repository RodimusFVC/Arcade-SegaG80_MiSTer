//============================================================================
//  Vector intensity tone mapping
//
//  Written 2026 by Videodr0me
//============================================================================

module vfb_tone_mapper
(
	input  logic       clk_source,
	input  logic       reset,
	input  logic       beam_on,
	input  logic [7:0] raw_intensity,
	input  logic [1:0] tone_mapping,
	output logic [7:0] mapped_intensity
);

	logic beam_on_q = 1'b0;

	logic [8:0] base_intensity;
	logic [8:0] inertia_intensity;
	logic [7:0] conditioned_intensity;
	logic [16:0] linear_1_product;
	logic [16:0] linear_2_product;
	logic [7:0] linear_1_intensity;
	logic [7:0] linear_2_intensity;

	always_ff @(posedge clk_source) begin
		if (reset)
			beam_on_q <= 1'b0;
		else
			beam_on_q <= beam_on;
	end

	always_comb begin
		base_intensity = {1'b0, raw_intensity};
		inertia_intensity = (beam_on && !beam_on_q) ?
		                    base_intensity + (base_intensity >> 2) :
		                    base_intensity;
		conditioned_intensity = (inertia_intensity > 9'd255) ?
		                        8'd255 : inertia_intensity[7:0];

		linear_1_product = conditioned_intensity * 17'd311;
		linear_2_product = conditioned_intensity * 17'd389;
		linear_1_intensity = (conditioned_intensity >= 8'd210) ?
		                     8'd255 : linear_1_product[15:8];
		linear_2_intensity = (conditioned_intensity >= 8'd168) ?
		                     8'd255 : linear_2_product[15:8];

		case (tone_mapping)
			2'd0: mapped_intensity = linear_1_intensity;
			2'd1: mapped_intensity = linear_2_intensity;
			// Bright keeps the native intensity here. Color-aware expansion
			// happens after framebuffer readout.
			2'd2: mapped_intensity = conditioned_intensity;
			default: mapped_intensity = conditioned_intensity;
		endcase
	end

endmodule
