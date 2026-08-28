// ============================================================================
// Final CRT presentation stage.
// written 2026 by Videodr0me
//
// This stage runs after primary, bloom, halo, and phosphor processing.
// Its settings affect only the final video output.
//
// Pipeline:
//   C1: optional Amplifone-to-Rec.709 color-space lift, R/G += floor(B/7)
//   C2: presentation color transform
//   C3: orientation-aware slot mask with bright-pixel gap closure
//   C4: final output register
//
// RGB, sync, and blanking remain aligned through every stage.
// ============================================================================

module vfb_final_present (
	input  logic        clk_sys,
	input  logic        reset,
	input  logic        ce_pix,

	input  logic        color_space_amp709,
	input  logic [2:0]  presentation_color,
	input  logic        slot_mask_enable,
	input  logic        slot_mask_rows,

	input  logic [7:0]  VGA_R_IN,
	input  logic [7:0]  VGA_G_IN,
	input  logic [7:0]  VGA_B_IN,
	input  logic        VGA_HS_IN,
	input  logic        VGA_VS_IN,
	input  logic        VGA_HBLANK_IN,
	input  logic        VGA_VBLANK_IN,

	output logic [7:0]  VGA_R_OUT,
	output logic [7:0]  VGA_G_OUT,
	output logic [7:0]  VGA_B_OUT,
	output logic        VGA_HS_OUT,
	output logic        VGA_VS_OUT,
	output logic        VGA_HBLANK_OUT,
	output logic        VGA_VBLANK_OUT
);
	localparam logic [2:0] CHANNEL_ORIGINAL = 3'd0;
	localparam logic [2:0] CHANNEL_RBG      = 3'd1;
	localparam logic [2:0] CHANNEL_GRB      = 3'd2;
	localparam logic [2:0] CHANNEL_GBR      = 3'd3;
	localparam logic [2:0] CHANNEL_BRG      = 3'd4;
	localparam logic [2:0] CHANNEL_BGR      = 3'd5;
	localparam logic [2:0] CHANNEL_BW       = 3'd6;
	localparam logic [2:0] CHANNEL_NEGATIVE = 3'd7;

	logic       color_space_amp709_q = 1'b0;
	logic [2:0] presentation_color_q = CHANNEL_ORIGINAL;
	logic       slot_mask_enable_q = 1'b0;
	logic       slot_mask_rows_q = 1'b0;
	always_ff @(posedge clk_sys) begin
		color_space_amp709_q <= color_space_amp709;
		presentation_color_q <= presentation_color;
		slot_mask_enable_q <= slot_mask_enable;
		slot_mask_rows_q <= slot_mask_rows;
	end

	function automatic [5:0] div7_u8(input logic [7:0] value);
		logic [16:0] product_293;
		begin
			// Exact floor(value / 7) for every 8-bit input:
			// floor(n/7) == (n * 293) >> 11, for n=0..255.
			// 293 = 256 + 32 + 4 + 1, implemented as shift-add.
			product_293 =
				({9'd0, value} << 8) +
				({9'd0, value} << 5) +
				({9'd0, value} << 2) +
				{9'd0, value};
			div7_u8 = product_293[16:11];
		end
	endfunction

	function automatic [7:0] clamp_add_lift(
		input logic [7:0] channel,
		input logic [5:0] lift
	);
		logic [8:0] sum;
		begin
			sum = {1'b0, channel} + {3'b000, lift};
			clamp_add_lift = sum[8] ? 8'hff : sum[7:0];
		end
	endfunction

	function automatic [7:0] scale_14_16(input logic [7:0] channel);
		logic [10:0] scaled;
		begin
			// Exact round(channel * 14 / 16), reduced to
			// floor((channel * 7 + 4) / 8).
			scaled = ({3'd0, channel} << 3) -
			         {3'd0, channel} +
			         11'd4;
			scale_14_16 = scaled[10:3];
		end
	endfunction

	function automatic [7:0] max3_u8(
		input logic [7:0] a,
		input logic [7:0] b,
		input logic [7:0] c
	);
		logic [7:0] ab;
		begin
			ab = (a > b) ? a : b;
			max3_u8 = (ab > c) ? ab : c;
		end
	endfunction

	logic [7:0] cs_r;
	logic [7:0] cs_g;
	logic [7:0] cs_b;
	logic cs_hs;
	logic cs_vs;
	logic cs_hblank;
	logic cs_vblank;

	logic [7:0] ch_r;
	logic [7:0] ch_g;
	logic [7:0] ch_b;
	logic ch_hs;
	logic ch_vs;
	logic ch_hblank;
	logic ch_vblank;

	logic [7:0] selected_r;
	logic [7:0] selected_g;
	logic [7:0] selected_b;
	logic selected_hs;
	logic selected_vs;
	logic selected_hblank;
	logic selected_vblank;

	logic slot_column_parity;
	logic slot_row_parity;
	logic slot_line_active;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			cs_r <= 8'd0;
			cs_g <= 8'd0;
			cs_b <= 8'd0;
			cs_hs <= 1'b1;
			cs_vs <= 1'b1;
			cs_hblank <= 1'b1;
			cs_vblank <= 1'b1;
		end else if (ce_pix) begin
			logic [5:0] blue_lift;

			cs_hs <= VGA_HS_IN;
			cs_vs <= VGA_VS_IN;
			cs_hblank <= VGA_HBLANK_IN;
			cs_vblank <= VGA_VBLANK_IN;
			if (VGA_HBLANK_IN || VGA_VBLANK_IN) begin
				cs_r <= 8'd0;
				cs_g <= 8'd0;
				cs_b <= 8'd0;
			end else if (color_space_amp709_q) begin
				blue_lift = div7_u8(VGA_B_IN);
				cs_r <= clamp_add_lift(VGA_R_IN, blue_lift);
				cs_g <= clamp_add_lift(VGA_G_IN, blue_lift);
				cs_b <= VGA_B_IN;
			end else begin
				cs_r <= VGA_R_IN;
				cs_g <= VGA_G_IN;
				cs_b <= VGA_B_IN;
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			ch_r <= 8'd0;
			ch_g <= 8'd0;
			ch_b <= 8'd0;
			ch_hs <= 1'b1;
			ch_vs <= 1'b1;
			ch_hblank <= 1'b1;
			ch_vblank <= 1'b1;
		end else if (ce_pix) begin
			logic [9:0] grey_sum;
			logic [7:0] grey;

			ch_hs <= cs_hs;
			ch_vs <= cs_vs;
			ch_hblank <= cs_hblank;
			ch_vblank <= cs_vblank;

			grey_sum = {2'd0, cs_r} +
			           {1'd0, cs_g, 1'b0} +
			           {2'd0, cs_b};
			grey = grey_sum[9:2];

			case (presentation_color_q)
				CHANNEL_ORIGINAL: begin ch_r <= cs_r; ch_g <= cs_g; ch_b <= cs_b; end
				CHANNEL_RBG:      begin ch_r <= cs_r; ch_g <= cs_b; ch_b <= cs_g; end
				CHANNEL_GRB:      begin ch_r <= cs_g; ch_g <= cs_r; ch_b <= cs_b; end
				CHANNEL_GBR:      begin ch_r <= cs_g; ch_g <= cs_b; ch_b <= cs_r; end
				CHANNEL_BRG:      begin ch_r <= cs_b; ch_g <= cs_r; ch_b <= cs_g; end
				CHANNEL_BGR:      begin ch_r <= cs_b; ch_g <= cs_g; ch_b <= cs_r; end
				CHANNEL_BW:       begin ch_r <= grey; ch_g <= grey; ch_b <= grey; end
				CHANNEL_NEGATIVE: begin ch_r <= ~cs_r; ch_g <= ~cs_g; ch_b <= ~cs_b; end
				default:          begin ch_r <= cs_r; ch_g <= cs_g; ch_b <= cs_b; end
			endcase
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			selected_r <= 8'd0;
			selected_g <= 8'd0;
			selected_b <= 8'd0;
			selected_hs <= 1'b1;
			selected_vs <= 1'b1;
			selected_hblank <= 1'b1;
			selected_vblank <= 1'b1;
			slot_column_parity <= 1'b0;
			slot_row_parity <= 1'b0;
			slot_line_active <= 1'b0;
		end else if (ce_pix) begin
			logic gap_position;
			logic close_gap;

			selected_hs <= ch_hs;
			selected_vs <= ch_vs;
			selected_hblank <= ch_hblank;
			selected_vblank <= ch_vblank;

			gap_position = slot_mask_enable_q &&
			               (slot_mask_rows_q ? slot_row_parity :
			                                 slot_column_parity);
			close_gap = (max3_u8(ch_r, ch_g, ch_b) >= 8'd200);

			if (ch_hblank || ch_vblank) begin
				selected_r <= 8'd0;
				selected_g <= 8'd0;
				selected_b <= 8'd0;
				slot_column_parity <= 1'b0;
				if (ch_vblank) begin
					slot_row_parity <= 1'b0;
					slot_line_active <= 1'b0;
				end else begin
					if (slot_line_active)
						slot_row_parity <= ~slot_row_parity;
					slot_line_active <= 1'b0;
				end
			end else begin
				if (gap_position && !close_gap) begin
					selected_r <= scale_14_16(ch_r);
					selected_g <= scale_14_16(ch_g);
					selected_b <= scale_14_16(ch_b);
				end else begin
					selected_r <= ch_r;
					selected_g <= ch_g;
					selected_b <= ch_b;
				end
				slot_column_parity <= ~slot_column_parity;
				slot_line_active <= 1'b1;
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			VGA_R_OUT <= 8'd0;
			VGA_G_OUT <= 8'd0;
			VGA_B_OUT <= 8'd0;
			VGA_HS_OUT <= 1'b1;
			VGA_VS_OUT <= 1'b1;
			VGA_HBLANK_OUT <= 1'b1;
			VGA_VBLANK_OUT <= 1'b1;
		end else if (ce_pix) begin
			VGA_R_OUT <= selected_r;
			VGA_G_OUT <= selected_g;
			VGA_B_OUT <= selected_b;
			VGA_HS_OUT <= selected_hs;
			VGA_VS_OUT <= selected_vs;
			VGA_HBLANK_OUT <= selected_hblank;
			VGA_VBLANK_OUT <= selected_vblank;
		end
	end

endmodule
