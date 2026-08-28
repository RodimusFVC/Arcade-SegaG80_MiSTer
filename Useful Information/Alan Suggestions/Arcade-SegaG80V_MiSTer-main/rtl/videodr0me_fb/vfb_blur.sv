// ============================================================================
// Local 5x5 bloom blur.
// written 2026 by Videodr0me
// ============================================================================

module vfb_blur (
	input  logic        clk_sys,
	input  logic        ce_pix,
	input  logic        reset,

	input  logic [10:0] active_x_in,
	input  logic        hblank_in,
	input  logic        enable,
	input  logic [23:0] rgb_in,

	output logic [10:0] active_x_out,
	output logic        hblank_out,
	output logic [23:0] rgb_out
);

	localparam int BLUR_LATENCY = 7;

	logic [10:0] active_x_d [1:BLUR_LATENCY+1];
	logic        hblank_d [1:BLUR_LATENCY+1];
	logic [23:0] rgb_in_d [1:3];

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			active_x_d[1] <= active_x_in;
			hblank_d[1]   <= hblank_in;
			rgb_in_d[1]   <= rgb_in;
			for (int i=2; i<=BLUR_LATENCY+1; i++) begin
				active_x_d[i] <= active_x_d[i-1];
				hblank_d[i]   <= hblank_d[i-1];
			end
			for (int i=2; i<=3; i++) begin
				rgb_in_d[i]   <= rgb_in_d[i-1];
			end
		end
	end

	// Four 1472-pixel RGB line buffers.
	// The design does not depend on read-during-write behavior.
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] lb_0 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] lb_1 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] lb_2 [0:1471];
	(* ramstyle = "M10K, no_rw_check" *) logic [23:0] lb_3 [0:1471];

	logic clearing;
	logic [10:0] clear_addr;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			clearing <= 1;
			clear_addr <= 0;
		end else if (clearing && ce_pix) begin
			if (clear_addr < 11'd1471) clear_addr <= clear_addr + 11'd1;
			else clearing <= 0;
		end
	end

	logic [23:0] lb_0_ram, lb_1_ram, lb_2_ram, lb_3_ram;
	logic [23:0] lb_0_reg, lb_1_reg, lb_2_reg, lb_3_reg;
	logic [23:0] lb_0_out, lb_1_out, lb_2_out, lb_3_out;

	assign lb_0_out = hblank_d[2] ? 24'd0 : lb_0_ram;
	assign lb_1_out = hblank_d[2] ? 24'd0 : lb_1_ram;
	assign lb_2_out = hblank_d[2] ? 24'd0 : lb_2_ram;
	assign lb_3_out = hblank_d[2] ? 24'd0 : lb_3_ram;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			// Read previous lines.
			lb_0_ram <= clearing ? 24'd0 : lb_0[active_x_d[1]];
			lb_1_ram <= clearing ? 24'd0 : lb_1[active_x_d[1]];
			lb_2_ram <= clearing ? 24'd0 : lb_2[active_x_d[1]];
			lb_3_ram <= clearing ? 24'd0 : lb_3[active_x_d[1]];

			// Shift each line into the next buffer.
			if (!hblank_d[2] || clearing) begin
				lb_0[clearing ? clear_addr : active_x_d[2]] <= clearing ? 24'd0 : rgb_in_d[2];
				lb_1[clearing ? clear_addr : active_x_d[2]] <= clearing ? 24'd0 : lb_0_out;
				lb_2[clearing ? clear_addr : active_x_d[2]] <= clearing ? 24'd0 : lb_1_out;
				lb_3[clearing ? clear_addr : active_x_d[2]] <= clearing ? 24'd0 : lb_2_out;
			end

			// Keep blanked samples at zero.
			lb_0_reg <= lb_0_out;
			lb_1_reg <= lb_1_out;
			lb_2_reg <= lb_2_out;
			lb_3_reg <= lb_3_out;
		end
	end

	logic [23:0] v_blur;
	logic [23:0] h_shift [0:3];
	logic [7:0] h_blur_r, h_blur_g, h_blur_b;

	always_ff @(posedge clk_sys) begin
		if (ce_pix && !clearing) begin

			// Vertical blur.
			if (enable) begin
				v_blur[7:0]   <= 8'( ((13'(rgb_in_d[3][7:0])   + 13'(lb_3_reg[7:0])   + 13'd8) + ((13'(lb_0_reg[7:0])   + 13'(lb_2_reg[7:0]))   << 2) + (13'(lb_1_reg[7:0])   * 13'd6)) >> 4 );
				v_blur[15:8]  <= 8'( ((13'(rgb_in_d[3][15:8])  + 13'(lb_3_reg[15:8])  + 13'd8) + ((13'(lb_0_reg[15:8])  + 13'(lb_2_reg[15:8]))  << 2) + (13'(lb_1_reg[15:8])  * 13'd6)) >> 4 );
				v_blur[23:16] <= 8'( ((13'(rgb_in_d[3][23:16]) + 13'(lb_3_reg[23:16]) + 13'd8) + ((13'(lb_0_reg[23:16]) + 13'(lb_2_reg[23:16])) << 2) + (13'(lb_1_reg[23:16]) * 13'd6)) >> 4 );
			end else begin
				v_blur <= lb_1_reg; // 2-line delayed center pixel
			end

			// Shift horizontal samples.
			h_shift[0] <= v_blur;
			h_shift[1] <= h_shift[0];
			h_shift[2] <= h_shift[1];
			h_shift[3] <= h_shift[2];

			// Horizontal blur.
			if (enable) begin
				h_blur_r <= 8'( ((13'(v_blur[23:16]) + 13'(h_shift[3][23:16]) + 13'd8) + ((13'(h_shift[0][23:16]) + 13'(h_shift[2][23:16])) << 2) + (13'(h_shift[1][23:16]) * 13'd6)) >> 4 );
				h_blur_g <= 8'( ((13'(v_blur[15:8])  + 13'(h_shift[3][15:8])  + 13'd8) + ((13'(h_shift[0][15:8])  + 13'(h_shift[2][15:8]))  << 2) + (13'(h_shift[1][15:8])  * 13'd6)) >> 4 );
				h_blur_b <= 8'( ((13'(v_blur[7:0])   + 13'(h_shift[3][7:0])   + 13'd8) + ((13'(h_shift[0][7:0])   + 13'(h_shift[2][7:0]))   << 2) + (13'(h_shift[1][7:0])   * 13'd6)) >> 4 );
			end else begin
				h_blur_r <= h_shift[1][23:16]; // 2-pixel delayed center pixel
				h_blur_g <= h_shift[1][15:8];
				h_blur_b <= h_shift[1][7:0];
			end

			rgb_out <= {h_blur_r, h_blur_g, h_blur_b};
		end
	end

	assign active_x_out = active_x_d[BLUR_LATENCY+1];
	assign hblank_out   = hblank_d[BLUR_LATENCY+1];

endmodule
