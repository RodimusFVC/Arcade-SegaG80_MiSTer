// ============================================================================
// Broad, low-resolution halo generator.
// written 2026 by Videodr0me
//
// Reduces each 16x16 source cell to one sample, applies one of four symmetric
// equal-gain eight-tap filters, soft-limits the result, and reconstructs
// full-resolution RGB.
// ============================================================================

module vfb_halo_wide #(
	parameter integer MAX_WIDTH = 1472,
	parameter integer SCALE = 16,
	parameter integer H_DELAY = 80,
	parameter integer RECONSTRUCTION_DELAY_LINES = 71,
	parameter integer COARSE_WIDTH = MAX_WIDTH / SCALE
) (
	input  logic        clk_sys,
	input  logic        reset,
	input  logic        ce_pix,

	input  logic [9:0]  halo_curve_gain,
	input  logic [1:0]  halo_spread_mode,
	input  logic [1:0]  halo_knee_mode,
	input  logic [11:0] active_height,
	input  logic [7:0]  VGA_R_IN,
	input  logic [7:0]  VGA_G_IN,
	input  logic [7:0]  VGA_B_IN,
	input  logic        VGA_HBLANK_IN,
	input  logic        VGA_VBLANK_IN,

	output logic [7:0]  HALO_R_OUT,
	output logic [7:0]  HALO_G_OUT,
	output logic [7:0]  HALO_B_OUT,
	output logic        HALO_VALID_OUT
);

	localparam integer COARSE_W = $clog2(COARSE_WIDTH + 5);
	localparam integer ENERGY_W = 13;
	localparam integer ENERGY_RGB_W = 3 * ENERGY_W;
	localparam integer ENERGY_HISTORY_W = 7 * ENERGY_RGB_W;
	localparam integer SPREAD_SUM_W = 20;
	localparam [3:0] RECON_SAMPLE_X_ADVANCE = 4'd3;
	localparam [3:0] RECON_SAMPLE_Y_ADVANCE = 4'd7;
	localparam [7:0] VERTICAL_CENTER_DELAY_ROWS = 8'd3;
	localparam [7:0] VERTICAL_PREVIOUS_DELAY_ROWS =
		VERTICAL_CENTER_DELAY_ROWS - 8'd1;
	localparam [7:0] RECON_FIRST_ROW = VERTICAL_PREVIOUS_DELAY_ROWS;
	localparam [1:0] RECON_FIRST_BANK = 2'd2;

	logic [9:0] halo_curve_gain_q = 10'd64;
	logic [1:0] halo_spread_mode_q = 2'd0;
	logic [6:0] halo_knee_threshold_q = 7'd0;

	always_ff @(posedge clk_sys) begin
		halo_curve_gain_q <= halo_curve_gain;
		halo_spread_mode_q <= halo_spread_mode;
		case (halo_knee_mode)
			2'd0: begin
				halo_knee_threshold_q <= 7'd16;
			end
			2'd1: begin
				halo_knee_threshold_q <= 7'd32;
			end
			2'd2: begin
				halo_knee_threshold_q <= 7'd64;
			end
			2'd3: begin
				halo_knee_threshold_q <= 7'd24;
			end
			default: begin
				halo_knee_threshold_q <= 7'd16;
			end
		endcase
	end

	initial begin
		if (SCALE != 16)
			$error("vfb_halo_wide currently requires SCALE=16");
		if ((MAX_WIDTH % SCALE) != 0)
			$error("vfb_halo_wide MAX_WIDTH must be divisible by SCALE");
	end

	// Apply an independent square-law curve and gain to each channel.
	function automatic [7:0] square8_value(input logic [7:0] value);
		integer scaled;
		begin
			scaled = (value * value + 127) / 255;
			square8_value = scaled[7:0];
		end
	endfunction

	(* ramstyle = "MLAB" *) logic [7:0] square8_rom_r [0:255];
	(* ramstyle = "MLAB" *) logic [7:0] square8_rom_g [0:255];
	(* ramstyle = "MLAB" *) logic [7:0] square8_rom_b [0:255];

	integer square8_init_i;
	initial begin
		for (square8_init_i = 0;
		     square8_init_i < 256;
		     square8_init_i = square8_init_i + 1) begin
			square8_rom_r[square8_init_i] =
				square8_value(square8_init_i[7:0]);
			square8_rom_g[square8_init_i] =
				square8_value(square8_init_i[7:0]);
			square8_rom_b[square8_init_i] =
				square8_value(square8_init_i[7:0]);
		end
	end

	function automatic [7:0] apply_curve_gain(
		input logic [7:0] squared,
		input logic [9:0] gain
	);
		logic [11:0] scaled;
		logic [8:0] scaled9;
		begin
			case (gain)
				10'd64: begin
					apply_curve_gain = {2'b00, squared[7:2]};
				end
				10'd96: begin
					scaled =
						({4'd0, squared} << 1) +
						{4'd0, squared} + 12'd4;
					apply_curve_gain = {1'b0, scaled[9:3]};
				end
				10'd128: begin
					apply_curve_gain = {1'b0, squared[7:1]};
				end
				10'd192: begin
					scaled =
						({4'd0, squared} << 1) +
						{4'd0, squared} + 12'd2;
					apply_curve_gain = scaled[9:2];
				end
				10'd256: begin
					apply_curve_gain = squared;
				end
				10'd320: begin
					scaled =
						({4'd0, squared} << 2) +
						{4'd0, squared} + 12'd2;
					scaled9 = scaled[10:2];
					apply_curve_gain =
						scaled9[8] ? 8'hff : scaled9[7:0];
				end
				10'd384: begin
					scaled =
						({4'd0, squared} << 1) +
						{4'd0, squared} + 12'd1;
					scaled9 = scaled[9:1];
					apply_curve_gain =
						scaled9[8] ? 8'hff : scaled9[7:0];
				end
				default: begin
					apply_curve_gain =
						squared[7] ? 8'hff :
						{squared[6:0], 1'b0};
				end
			endcase
		end
	endfunction

	logic [7:0] source_in_r_q;
	logic [7:0] source_in_g_q;
	logic [7:0] source_in_b_q;
	logic source_in_hblank_q;
	logic source_in_vblank_q;

	wire [7:0] source_r = apply_curve_gain(
		square8_rom_r[source_in_r_q], halo_curve_gain_q);
	wire [7:0] source_g = apply_curve_gain(
		square8_rom_g[source_in_g_q], halo_curve_gain_q);
	wire [7:0] source_b = apply_curve_gain(
		square8_rom_b[source_in_b_q], halo_curve_gain_q);

	// Register the curved source before 16x16 accumulation.
	logic [7:0] source_r_q;
	logic [7:0] source_g_q;
	logic [7:0] source_b_q;
	logic source_hblank_q;
	logic source_vblank_q;
	logic source_hblank_d;
	logic source_vblank_d;

	// Reduce the source into 16x16 cells.
	logic hblank_d;
	logic [3:0] h_phase;
	logic [3:0] v_phase;
	logic [7:0] reduce_y;
	logic [7:0] reduced_height;
	logic source_epoch;
	wire next_source_epoch = ~source_epoch;
	logic [COARSE_W-1:0] coarse_x;
	logic [COARSE_W-1:0] coarse_width;
	logic [11:0] h_sum_r;
	logic [11:0] h_sum_g;
	logic [11:0] h_sum_b;

	wire line_start = ce_pix && hblank_d && !source_in_hblank_q;
	wire source_line_end =
		ce_pix && !source_hblank_d && source_hblank_q;
	wire source_frame_active_start =
		ce_pix && source_vblank_d && !source_vblank_q;
	wire source_active =
		ce_pix && !source_hblank_q && !source_vblank_q;
	wire normal_group = source_active && (h_phase == 4'd15);

	logic zero_fill_active;
	logic [COARSE_W-1:0] zero_fill_x;
	logic [3:0] zero_fill_phase;
	logic [7:0] zero_fill_y;
	logic zero_fill_epoch;

	logic tail_fill_active;
	logic [COARSE_W-1:0] tail_fill_x;
	logic [3:0] tail_fill_phase;
	logic [7:0] tail_fill_y;
	logic tail_fill_epoch;
	logic [12:0] tail_fill_r;
	logic [12:0] tail_fill_g;
	logic [12:0] tail_fill_b;

	wire next_sample_valid =
		normal_group || tail_fill_active ||
		(ce_pix && zero_fill_active);
	wire [COARSE_W-1:0] next_sample_x =
		tail_fill_active ? tail_fill_x :
		zero_fill_active ? zero_fill_x : coarse_x;
	wire [3:0] next_sample_phase =
		tail_fill_active ? tail_fill_phase :
		zero_fill_active ? zero_fill_phase : v_phase;
	wire [7:0] next_sample_y =
		tail_fill_active ? tail_fill_y :
		zero_fill_active ? zero_fill_y : reduce_y;
	wire next_sample_epoch =
		tail_fill_active ? tail_fill_epoch :
		zero_fill_active ? zero_fill_epoch : source_epoch;
	wire [12:0] next_sample_r =
		tail_fill_active ? tail_fill_r :
		zero_fill_active ? 13'd0 : {1'b0, h_sum_r} + source_r_q;
	wire [12:0] next_sample_g =
		tail_fill_active ? tail_fill_g :
		zero_fill_active ? 13'd0 : {1'b0, h_sum_g} + source_g_q;
	wire [12:0] next_sample_b =
		tail_fill_active ? tail_fill_b :
		zero_fill_active ? 13'd0 : {1'b0, h_sum_b} + source_b_q;

	logic sample_valid;
	logic [COARSE_W-1:0] sample_x;
	logic [3:0] sample_phase;
	logic [7:0] sample_y;
	logic sample_epoch;
	logic [12:0] sample_r;
	logic [12:0] sample_g;
	logic [12:0] sample_b;

	(* ramstyle = "MLAB, no_rw_check" *) logic [15:0] vertical_acc_r [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [15:0] vertical_acc_g [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [15:0] vertical_acc_b [0:COARSE_WIDTH-1];

	logic acc_stage_valid;
	logic [COARSE_W-1:0] acc_stage_x;
	logic [3:0] acc_stage_phase;
	logic [7:0] acc_stage_y;
	logic acc_stage_epoch;
	logic [12:0] acc_stage_r;
	logic [12:0] acc_stage_g;
	logic [12:0] acc_stage_b;
	logic [15:0] acc_stage_sum_r;
	logic [15:0] acc_stage_sum_g;
	logic [15:0] acc_stage_sum_b;

	logic low_valid;
	logic [COARSE_W-1:0] low_x;
	logic [7:0] low_y;
	logic low_epoch;
	logic [ENERGY_RGB_W-1:0] low_rgb;

	logic low_total_valid;
	logic [COARSE_W-1:0] low_total_x;
	logic [7:0] low_total_y;
	logic low_total_epoch;
	logic [16:0] low_total_r;
	logic [16:0] low_total_g;
	logic [16:0] low_total_b;

	logic low_reduce_valid;
	logic [COARSE_W-1:0] low_reduce_x;
	logic [7:0] low_reduce_y;
	logic low_reduce_epoch;
	logic [ENERGY_W-1:0] low_reduce_r;
	logic [ENERGY_W-1:0] low_reduce_g;
	logic [ENERGY_W-1:0] low_reduce_b;

	logic low_pack_valid;
	logic [COARSE_W-1:0] low_pack_x;
	logic [7:0] low_pack_y;
	logic low_pack_epoch;
	logic [ENERGY_W-1:0] low_pack_r;
	logic [ENERGY_W-1:0] low_pack_g;
	logic [ENERGY_W-1:0] low_pack_b;

	logic [1:0] write_bank [0:1];
	logic [7:0] completed_rows [0:1];
	logic [11:0] source_full_line_y;
	logic [11:0] previous_frame_total_lines;
	wire [11:0] source_full_line_for_line =
		source_frame_active_start ? 12'd0 : source_full_line_y;
	wire source_epoch_for_line =
		source_frame_active_start ? next_source_epoch : source_epoch;
	wire reconstruction_uses_previous_epoch =
		(source_full_line_for_line < RECONSTRUCTION_DELAY_LINES);
	wire reconstruction_epoch =
		reconstruction_uses_previous_epoch ?
		~source_epoch_for_line : source_epoch_for_line;
	wire [11:0] reconstruction_line_for_line =
		reconstruction_uses_previous_epoch
			? previous_frame_total_lines + source_full_line_for_line -
			  RECONSTRUCTION_DELAY_LINES
			: source_full_line_for_line - RECONSTRUCTION_DELAY_LINES;
	logic tail_service_active;
	logic [COARSE_W-1:0] tail_service_x;
	logic [7:0] tail_service_y;
	logic [7:0] tail_service_limit_y;
	logic [7:0] tail_service_height;
	logic tail_service_epoch;
	logic [2:0] tail_service_gap;
	logic [7:0] tail_service_first_live_y_q;
	wire [11:0] tail_service_frame_reconstruction_line =
		previous_frame_total_lines - RECONSTRUCTION_DELAY_LINES;
	wire [11:0] tail_service_line_reconstruction_line =
		(source_full_line_y < RECONSTRUCTION_DELAY_LINES)
			? previous_frame_total_lines + source_full_line_y -
			  RECONSTRUCTION_DELAY_LINES
			: source_full_line_y - RECONSTRUCTION_DELAY_LINES;
	wire [7:0] tail_service_frame_first_live_y =
		tail_service_frame_reconstruction_line[11:4] +
		VERTICAL_PREVIOUS_DELAY_ROWS;
	wire [7:0] tail_service_line_first_live_y =
		tail_service_line_reconstruction_line[11:4] +
		VERTICAL_PREVIOUS_DELAY_ROWS;
	logic [7:0] tail_service_frame_first_live_y_q;
	logic [7:0] tail_service_line_first_live_y_q;

	always_ff @(posedge clk_sys) begin
		tail_service_frame_first_live_y_q <=
			tail_service_frame_first_live_y;
		tail_service_line_first_live_y_q <=
			tail_service_line_first_live_y;
	end

	wire tail_service_row_safe =
		(tail_service_y < 8'd3) ||
		((tail_service_y - 8'd3) < tail_service_first_live_y_q);
	wire tail_service_valid =
		tail_service_active && (tail_service_gap == 3'd0) &&
		tail_service_row_safe;
	wire blur_in_valid = tail_service_valid || low_valid;
	wire [COARSE_W-1:0] blur_in_x =
		tail_service_valid ? tail_service_x : low_x;
	wire [7:0] blur_in_y =
		tail_service_valid ? tail_service_y : low_y;
	wire blur_in_epoch =
		tail_service_valid ? tail_service_epoch : low_epoch;
	wire [7:0] blur_in_height =
		tail_service_valid ? tail_service_height : reduced_height;
	wire [ENERGY_RGB_W-1:0] blur_in_rgb =
		tail_service_valid ? '0 : low_rgb;

	function automatic [ENERGY_W-1:0] coarse_source_linear(
		input logic [16:0] total
	);
		logic [16:0] rounded_total;
		begin
			// Keep cell energy linear through both filter directions.
			// The maximum is 8160.
			rounded_total = total + 17'd4;
			coarse_source_linear =
				rounded_total[ENERGY_W+2:3];
		end
	endfunction

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			hblank_d <= 1'b1;
			source_in_r_q <= 8'd0;
			source_in_g_q <= 8'd0;
			source_in_b_q <= 8'd0;
			source_in_hblank_q <= 1'b1;
			source_in_vblank_q <= 1'b1;
			source_r_q <= 8'd0;
			source_g_q <= 8'd0;
			source_b_q <= 8'd0;
			source_hblank_q <= 1'b1;
			source_vblank_q <= 1'b1;
			source_hblank_d <= 1'b1;
			source_vblank_d <= 1'b1;
			h_phase <= 4'd0;
			v_phase <= 4'd0;
			reduce_y <= 8'd0;
			reduced_height <= 8'd0;
			source_epoch <= 1'b0;
			coarse_x <= '0;
			coarse_width <= COARSE_W'(COARSE_WIDTH);
			h_sum_r <= 12'd0;
			h_sum_g <= 12'd0;
			h_sum_b <= 12'd0;
			zero_fill_active <= 1'b0;
			zero_fill_x <= '0;
			zero_fill_phase <= 4'd0;
			zero_fill_y <= 8'd0;
			zero_fill_epoch <= 1'b0;
			tail_fill_active <= 1'b0;
			tail_fill_x <= '0;
			tail_fill_phase <= 4'd0;
			tail_fill_y <= 8'd0;
			tail_fill_epoch <= 1'b0;
			tail_fill_r <= 13'd0;
			tail_fill_g <= 13'd0;
			tail_fill_b <= 13'd0;
			sample_valid <= 1'b0;
			sample_x <= '0;
			sample_phase <= 4'd0;
			sample_y <= 8'd0;
			sample_epoch <= 1'b0;
			sample_r <= 13'd0;
			sample_g <= 13'd0;
			sample_b <= 13'd0;
			acc_stage_valid <= 1'b0;
			acc_stage_x <= '0;
			acc_stage_phase <= 4'd0;
			acc_stage_y <= 8'd0;
			acc_stage_epoch <= 1'b0;
			acc_stage_r <= 13'd0;
			acc_stage_g <= 13'd0;
			acc_stage_b <= 13'd0;
			acc_stage_sum_r <= 16'd0;
			acc_stage_sum_g <= 16'd0;
			acc_stage_sum_b <= 16'd0;
			low_valid <= 1'b0;
			low_x <= '0;
			low_y <= 8'd0;
			low_epoch <= 1'b0;
			low_rgb <= '0;
			low_total_valid <= 1'b0;
			low_total_x <= '0;
			low_total_y <= 8'd0;
			low_total_epoch <= 1'b0;
			low_total_r <= 17'd0;
			low_total_g <= 17'd0;
			low_total_b <= 17'd0;
			low_reduce_valid <= 1'b0;
			low_reduce_x <= '0;
			low_reduce_y <= 8'd0;
			low_reduce_epoch <= 1'b0;
			low_reduce_r <= '0;
			low_reduce_g <= '0;
			low_reduce_b <= '0;
			low_pack_valid <= 1'b0;
			low_pack_x <= '0;
			low_pack_y <= 8'd0;
			low_pack_epoch <= 1'b0;
			low_pack_r <= '0;
			low_pack_g <= '0;
			low_pack_b <= '0;
			tail_service_active <= 1'b0;
			tail_service_x <= '0;
			tail_service_y <= 8'd0;
			tail_service_limit_y <= 8'd0;
			tail_service_height <= 8'd0;
			tail_service_epoch <= 1'b0;
			tail_service_gap <= 3'd0;
			tail_service_first_live_y_q <= 8'd0;
		end else begin
			low_total_valid <= 1'b0;
			low_reduce_valid <= low_total_valid;
			low_pack_valid <= low_reduce_valid;
			low_valid <= low_pack_valid;
			sample_valid <= next_sample_valid;
			acc_stage_valid <= sample_valid;
			if (low_total_valid) begin
				low_reduce_x <= low_total_x;
				low_reduce_y <= low_total_y;
				low_reduce_epoch <= low_total_epoch;
				low_reduce_r <= coarse_source_linear(low_total_r);
				low_reduce_g <= coarse_source_linear(low_total_g);
				low_reduce_b <= coarse_source_linear(low_total_b);
			end
			if (low_reduce_valid) begin
				low_pack_x <= low_reduce_x;
				low_pack_y <= low_reduce_y;
				low_pack_epoch <= low_reduce_epoch;
				low_pack_r <= low_reduce_r;
				low_pack_g <= low_reduce_g;
				low_pack_b <= low_reduce_b;
			end
			if (low_pack_valid) begin
				low_x <= low_pack_x;
				low_y <= low_pack_y;
				low_epoch <= low_pack_epoch;
				low_rgb <= {low_pack_r, low_pack_g, low_pack_b};
			end
			if (next_sample_valid) begin
				sample_x <= next_sample_x;
				sample_phase <= next_sample_phase;
				sample_y <= next_sample_y;
				sample_epoch <= next_sample_epoch;
				sample_r <= next_sample_r;
				sample_g <= next_sample_g;
				sample_b <= next_sample_b;
			end
			if (sample_valid) begin
				acc_stage_x <= sample_x;
				acc_stage_phase <= sample_phase;
				acc_stage_y <= sample_y;
				acc_stage_epoch <= sample_epoch;
				acc_stage_r <= sample_r;
				acc_stage_g <= sample_g;
				acc_stage_b <= sample_b;
				acc_stage_sum_r <= vertical_acc_r[sample_x];
				acc_stage_sum_g <= vertical_acc_g[sample_x];
				acc_stage_sum_b <= vertical_acc_b[sample_x];
			end

			if (ce_pix) begin
				hblank_d <= source_in_hblank_q;
				source_in_r_q <= VGA_R_IN;
				source_in_g_q <= VGA_G_IN;
				source_in_b_q <= VGA_B_IN;
				source_in_hblank_q <= VGA_HBLANK_IN;
				source_in_vblank_q <= VGA_VBLANK_IN;
				source_r_q <= source_r;
				source_g_q <= source_g;
				source_b_q <= source_b;
				source_hblank_q <= source_in_hblank_q;
				source_vblank_q <= source_in_vblank_q;
				source_hblank_d <= source_hblank_q;
				source_vblank_d <= source_vblank_q;
			end

			if (tail_fill_active)
				tail_fill_active <= 1'b0;

			if (tail_service_valid) begin
				if (tail_service_x + 1'b1 >= coarse_width) begin
					tail_service_x <= '0;
					if (tail_service_y + 1'b1 >=
					    tail_service_limit_y) begin
						tail_service_active <= 1'b0;
						tail_service_gap <= 3'd0;
					end else begin
						tail_service_y <=
							tail_service_y + 1'b1;
						tail_service_gap <= 3'd4;
					end
				end else begin
					tail_service_x <= tail_service_x + 1'b1;
				end
			end else if (tail_service_gap != 3'd0) begin
				tail_service_gap <= tail_service_gap - 1'b1;
			end

			if (source_frame_active_start) begin
				logic [7:0] tail_limit_y;

				tail_limit_y =
					reduced_height + VERTICAL_CENTER_DELAY_ROWS;
				tail_service_first_live_y_q <=
					tail_service_frame_first_live_y_q;
				source_epoch <= next_source_epoch;
				reduce_y <= 8'd0;
				zero_fill_active <= 1'b0;
				tail_fill_active <= 1'b0;
				tail_service_x <= '0;
				tail_service_y <= completed_rows[source_epoch];
				tail_service_limit_y <= tail_limit_y;
				tail_service_height <= reduced_height;
				tail_service_epoch <= source_epoch;
				tail_service_gap <= 3'd0;
				tail_service_active <=
					(coarse_width != 0) &&
					(reduced_height != 8'd0) &&
					(completed_rows[source_epoch] <
					 tail_limit_y);
			end else if (line_start) begin
				tail_service_first_live_y_q <=
					tail_service_line_first_live_y_q;
			end

			if (source_frame_active_start)
				v_phase <= 4'd0;

			if (source_active) begin
				if (h_phase == 4'd15) begin
					h_phase <= 4'd0;
					coarse_x <= coarse_x + 1'b1;
					h_sum_r <= 12'd0;
					h_sum_g <= 12'd0;
					h_sum_b <= 12'd0;
				end else begin
					h_phase <= h_phase + 1'b1;
					h_sum_r <= h_sum_r + source_r_q;
					h_sum_g <= h_sum_g + source_g_q;
					h_sum_b <= h_sum_b + source_b_q;
				end
			end

			if (source_line_end) begin
				if (!source_vblank_q &&
				    (coarse_x != 0 || h_phase != 0)) begin
					coarse_width <= coarse_x +
						((h_phase != 0) ? 1'b1 : 1'b0);
					reduced_height <= reduce_y + 8'd1;
				end
				if (!source_vblank_q && h_phase != 0) begin
					tail_fill_active <= 1'b1;
					tail_fill_x <= coarse_x;
					tail_fill_phase <= v_phase;
					tail_fill_y <= reduce_y;
					tail_fill_epoch <= source_epoch;
					tail_fill_r <= {1'b0, h_sum_r};
					tail_fill_g <= {1'b0, h_sum_g};
					tail_fill_b <= {1'b0, h_sum_b};
				end
				h_phase <= 4'd0;
				coarse_x <= '0;
				h_sum_r <= 12'd0;
				h_sum_g <= 12'd0;
				h_sum_b <= 12'd0;
				v_phase <= v_phase + 1'b1;
				if (v_phase == 4'd15)
					reduce_y <= reduce_y + 1'b1;

				// Add black rows during VBLANK so the halo fades below the
				// final visible line.
				if (source_vblank_q && coarse_width != 0) begin
					zero_fill_active <= 1'b1;
					zero_fill_x <= '0;
					zero_fill_phase <= v_phase;
					zero_fill_y <= reduce_y;
					zero_fill_epoch <= source_epoch;
				end
			end

			if (ce_pix && zero_fill_active) begin
				if (zero_fill_x + 1'b1 >= coarse_width) begin
					zero_fill_active <= 1'b0;
					zero_fill_x <= '0;
				end else begin
					zero_fill_x <= zero_fill_x + 1'b1;
				end
			end

			if (acc_stage_valid) begin
				logic [16:0] total_r;
				logic [16:0] total_g;
				logic [16:0] total_b;
				total_r = acc_stage_sum_r + acc_stage_r;
				total_g = acc_stage_sum_g + acc_stage_g;
				total_b = acc_stage_sum_b + acc_stage_b;

				if (acc_stage_phase == 4'd0) begin
					vertical_acc_r[acc_stage_x] <= acc_stage_r;
					vertical_acc_g[acc_stage_x] <= acc_stage_g;
					vertical_acc_b[acc_stage_x] <= acc_stage_b;
				end else if (acc_stage_phase == 4'd15) begin
					vertical_acc_r[acc_stage_x] <= 16'd0;
					vertical_acc_g[acc_stage_x] <= 16'd0;
					vertical_acc_b[acc_stage_x] <= 16'd0;
					low_total_valid <= 1'b1;
					low_total_x <= acc_stage_x;
					low_total_y <= acc_stage_y;
					low_total_epoch <= acc_stage_epoch;
					low_total_r <= total_r;
					low_total_g <= total_g;
					low_total_b <= total_b;
				end else begin
					vertical_acc_r[acc_stage_x] <= total_r[15:0];
					vertical_acc_g[acc_stage_x] <= total_g[15:0];
					vertical_acc_b[acc_stage_x] <= total_b[15:0];
				end
			end
		end
	end

	// Eight-tap filtering at reduced resolution.
	function automatic [SPREAD_SUM_W-1:0] spread8_edge(
		input logic [ENERGY_W-1:0] left,
		input logic [ENERGY_W-1:0] right,
		input logic [1:0] spread_mode
	);
		logic [ENERGY_W:0] pair;
		logic [SPREAD_SUM_W-1:0] pair_ext;
		begin
			pair = {1'b0, left} + {1'b0, right};
			pair_ext = {{(SPREAD_SUM_W-ENERGY_W-1){1'b0}}, pair};
			case (spread_mode)
				2'd0: spread8_edge = pair_ext;
				2'd1: spread8_edge = pair_ext << 2;
				2'd2: spread8_edge = pair_ext << 3;
				default: spread8_edge = '0;
			endcase
		end
	endfunction

	function automatic [SPREAD_SUM_W-1:0] spread8_near(
		input logic [ENERGY_W-1:0] left,
		input logic [ENERGY_W-1:0] right,
		input logic [1:0] spread_mode
	);
		logic [ENERGY_W:0] pair;
		logic [SPREAD_SUM_W-1:0] pair_ext;
		begin
			pair = {1'b0, left} + {1'b0, right};
			pair_ext = {{(SPREAD_SUM_W-ENERGY_W-1){1'b0}}, pair};
			case (spread_mode)
				2'd0:
					spread8_near = (pair_ext << 3) - pair_ext;
				2'd1, 2'd2:
					spread8_near =
						(pair_ext << 3) + (pair_ext << 2);
				default: spread8_near = pair_ext << 2;
			endcase
		end
	endfunction

	function automatic [SPREAD_SUM_W-1:0] spread8_mid(
		input logic [ENERGY_W-1:0] left,
		input logic [ENERGY_W-1:0] right,
		input logic [1:0] spread_mode
	);
		logic [ENERGY_W:0] pair;
		logic [SPREAD_SUM_W-1:0] pair_ext;
		begin
			pair = {1'b0, left} + {1'b0, right};
			pair_ext = {{(SPREAD_SUM_W-ENERGY_W-1){1'b0}}, pair};
			case (spread_mode)
				2'd0:
					spread8_mid =
						(pair_ext << 4) +
						(pair_ext << 2) + pair_ext;
				2'd1:
					spread8_mid =
						(pair_ext << 4) + (pair_ext << 2);
				2'd2:
					spread8_mid = pair_ext << 4;
				default:
					spread8_mid =
						(pair_ext << 4) + (pair_ext << 2);
			endcase
		end
	endfunction

	function automatic [SPREAD_SUM_W-1:0] spread8_center(
		input logic [ENERGY_W-1:0] left,
		input logic [ENERGY_W-1:0] right,
		input logic [1:0] spread_mode
	);
		logic [ENERGY_W:0] pair;
		logic [SPREAD_SUM_W-1:0] pair_ext;
		begin
			pair = {1'b0, left} + {1'b0, right};
			pair_ext = {{(SPREAD_SUM_W-ENERGY_W-1){1'b0}}, pair};
			case (spread_mode)
				2'd0:
					spread8_center =
						(pair_ext << 5) +
						(pair_ext << 1) + pair_ext;
				2'd1, 2'd2:
					spread8_center =
						(pair_ext << 5) - (pair_ext << 2);
				default:
					spread8_center =
						(pair_ext << 5) + (pair_ext << 3);
			endcase
		end
	endfunction

	function automatic logic reduced_y_tap_valid(
		input logic [7:0] y,
		input logic [2:0] tap,
		input logic [7:0] height
	);
		logic [7:0] tap_ext;
		logic [7:0] tap_y;
		begin
			tap_ext = {5'd0, tap};
			if (y < tap_ext) begin
				reduced_y_tap_valid = 1'b0;
			end else begin
				tap_y = y - tap_ext;
				reduced_y_tap_valid = (tap_y < height);
			end
		end
	endfunction

	function automatic [ENERGY_RGB_W-1:0] mask_rgb(
		input logic [ENERGY_RGB_W-1:0] rgb,
		input logic valid
	);
		begin
			mask_rgb = valid ? rgb : '0;
		end
	endfunction

	function automatic [7:0] compress_filtered_energy(
		input logic [ENERGY_W-1:0] energy,
		input logic [6:0] knee_threshold
	);
		logic [13:0] mapped;
		logic [13:0] delta;
		logic [15:0] soft_scaled;
		begin
			if ({6'd0, knee_threshold} >= energy) begin
				mapped = {1'b0, energy};
			end else begin
				delta = {1'b0, energy} -
					{7'd0, knee_threshold};
				soft_scaled =
					({2'd0, delta} << 1) +
					{2'd0, delta} + 16'd4;
				mapped =
					{7'd0, knee_threshold} +
					soft_scaled[15:3];
			end
			compress_filtered_energy =
				(mapped > 14'd255) ? 8'hff : mapped[7:0];
		end
	endfunction

	// Each coarse x position stores the previous seven reduced rows.
	(* ramstyle = "MLAB, no_rw_check" *)
	logic [ENERGY_HISTORY_W-1:0] blur_history_0 [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *)
	logic [ENERGY_HISTORY_W-1:0] blur_history_1 [0:COARSE_WIDTH-1];
	logic blur_feed_valid;
	logic [COARSE_W-1:0] blur_feed_x;
	logic [7:0] blur_feed_y;
	logic [7:0] blur_feed_height;
	logic blur_feed_epoch;
	logic [ENERGY_RGB_W-1:0] blur_feed_rgb;
	logic blur_stage_valid;
	logic blur_stage_safe;
	logic [COARSE_W-1:0] blur_stage_x;
	logic [7:0] blur_stage_y;
	logic blur_stage_epoch;
	logic [ENERGY_RGB_W-1:0] blur_stage_rgb;
	logic [ENERGY_HISTORY_W-1:0] blur_stage_history;
	logic [7:0] blur_stage_tap_valid;
	wire [ENERGY_RGB_W-1:0] blur_row_0 =
		blur_stage_history[ENERGY_RGB_W-1:0];
	wire [ENERGY_RGB_W-1:0] blur_row_1 =
		blur_stage_history[2*ENERGY_RGB_W-1:ENERGY_RGB_W];
	wire [ENERGY_RGB_W-1:0] blur_row_2 =
		blur_stage_history[3*ENERGY_RGB_W-1:2*ENERGY_RGB_W];
	wire [ENERGY_RGB_W-1:0] blur_row_3 =
		blur_stage_history[4*ENERGY_RGB_W-1:3*ENERGY_RGB_W];
	wire [ENERGY_RGB_W-1:0] blur_row_4 =
		blur_stage_history[5*ENERGY_RGB_W-1:4*ENERGY_RGB_W];
	wire [ENERGY_RGB_W-1:0] blur_row_5 =
		blur_stage_history[6*ENERGY_RGB_W-1:5*ENERGY_RGB_W];
	wire [ENERGY_RGB_W-1:0] blur_row_6 =
		blur_stage_history[7*ENERGY_RGB_W-1:6*ENERGY_RGB_W];

	logic vertical_blur_valid;
	logic vertical_blur_safe;
	logic [COARSE_W-1:0] vertical_blur_x;
	logic [7:0] vertical_blur_y;
	logic vertical_blur_epoch;
	logic [ENERGY_RGB_W-1:0] vertical_blur_rgb;
	logic vertical_mask_valid;
	logic vertical_mask_safe;
	logic [COARSE_W-1:0] vertical_mask_x;
	logic [7:0] vertical_mask_y;
	logic vertical_mask_epoch;
	logic [ENERGY_RGB_W-1:0] vertical_tap_0;
	logic [ENERGY_RGB_W-1:0] vertical_tap_1;
	logic [ENERGY_RGB_W-1:0] vertical_tap_2;
	logic [ENERGY_RGB_W-1:0] vertical_tap_3;
	logic [ENERGY_RGB_W-1:0] vertical_tap_4;
	logic [ENERGY_RGB_W-1:0] vertical_tap_5;
	logic [ENERGY_RGB_W-1:0] vertical_tap_6;
	logic [ENERGY_RGB_W-1:0] vertical_tap_7;
	logic vertical_part_valid;
	logic vertical_part_safe;
	logic [COARSE_W-1:0] vertical_part_x;
	logic [7:0] vertical_part_y;
	logic vertical_part_epoch;
	logic [SPREAD_SUM_W-1:0] vertical_part_edge_r;
	logic [SPREAD_SUM_W-1:0] vertical_part_near_r;
	logic [SPREAD_SUM_W-1:0] vertical_part_mid_r;
	logic [SPREAD_SUM_W-1:0] vertical_part_center_r;
	logic [SPREAD_SUM_W-1:0] vertical_part_edge_g;
	logic [SPREAD_SUM_W-1:0] vertical_part_near_g;
	logic [SPREAD_SUM_W-1:0] vertical_part_mid_g;
	logic [SPREAD_SUM_W-1:0] vertical_part_center_g;
	logic [SPREAD_SUM_W-1:0] vertical_part_edge_b;
	logic [SPREAD_SUM_W-1:0] vertical_part_near_b;
	logic [SPREAD_SUM_W-1:0] vertical_part_mid_b;
	logic [SPREAD_SUM_W-1:0] vertical_part_center_b;
	logic vertical_sum_valid;
	logic vertical_sum_safe;
	logic [COARSE_W-1:0] vertical_sum_x;
	logic [7:0] vertical_sum_y;
	logic vertical_sum_epoch;
	logic [SPREAD_SUM_W-1:0] vertical_sum_r;
	logic [SPREAD_SUM_W-1:0] vertical_sum_g;
	logic [SPREAD_SUM_W-1:0] vertical_sum_b;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			blur_feed_valid <= 1'b0;
			blur_feed_x <= '0;
			blur_feed_y <= 8'd0;
			blur_feed_height <= 8'd0;
			blur_feed_epoch <= 1'b0;
			blur_feed_rgb <= '0;
			blur_stage_valid <= 1'b0;
			blur_stage_safe <= 1'b0;
			blur_stage_x <= '0;
			blur_stage_y <= 8'd0;
			blur_stage_epoch <= 1'b0;
			blur_stage_rgb <= '0;
			blur_stage_history <= '0;
			blur_stage_tap_valid <= 8'd0;
			vertical_mask_valid <= 1'b0;
			vertical_mask_safe <= 1'b0;
			vertical_mask_x <= '0;
			vertical_mask_y <= 8'd0;
			vertical_mask_epoch <= 1'b0;
			vertical_tap_0 <= '0;
			vertical_tap_1 <= '0;
			vertical_tap_2 <= '0;
			vertical_tap_3 <= '0;
			vertical_tap_4 <= '0;
			vertical_tap_5 <= '0;
			vertical_tap_6 <= '0;
			vertical_tap_7 <= '0;
			vertical_part_valid <= 1'b0;
			vertical_part_safe <= 1'b0;
			vertical_part_x <= '0;
			vertical_part_y <= 8'd0;
			vertical_part_epoch <= 1'b0;
			vertical_part_edge_r <= '0;
			vertical_part_near_r <= '0;
			vertical_part_mid_r <= '0;
			vertical_part_center_r <= '0;
			vertical_part_edge_g <= '0;
			vertical_part_near_g <= '0;
			vertical_part_mid_g <= '0;
			vertical_part_center_g <= '0;
			vertical_part_edge_b <= '0;
			vertical_part_near_b <= '0;
			vertical_part_mid_b <= '0;
			vertical_part_center_b <= '0;
			vertical_sum_valid <= 1'b0;
			vertical_sum_safe <= 1'b0;
			vertical_sum_x <= '0;
			vertical_sum_y <= 8'd0;
			vertical_sum_epoch <= 1'b0;
			vertical_sum_r <= '0;
			vertical_sum_g <= '0;
			vertical_sum_b <= '0;
			vertical_blur_valid <= 1'b0;
			vertical_blur_safe <= 1'b0;
			vertical_blur_x <= '0;
			vertical_blur_y <= 8'd0;
			vertical_blur_epoch <= 1'b0;
			vertical_blur_rgb <= '0;
		end else begin
			blur_feed_valid <= blur_in_valid;
			if (blur_in_valid) begin
				blur_feed_x <= blur_in_x;
				blur_feed_y <= blur_in_y;
				blur_feed_height <= blur_in_height;
				blur_feed_epoch <= blur_in_epoch;
				blur_feed_rgb <= blur_in_rgb;
			end
			blur_stage_valid <= blur_feed_valid;
			vertical_mask_valid <= blur_stage_valid;
			vertical_part_valid <= vertical_mask_valid;
			vertical_sum_valid <= vertical_part_valid;
			vertical_blur_valid <= vertical_sum_valid;
			if (blur_feed_valid) begin
				blur_stage_safe <= 1'b1;
				blur_stage_x <= blur_feed_x;
				blur_stage_y <= blur_feed_y;
				blur_stage_epoch <= blur_feed_epoch;
				blur_stage_rgb <= blur_feed_rgb;
				blur_stage_tap_valid <= {
					reduced_y_tap_valid(blur_feed_y, 3'd7, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd6, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd5, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd4, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd3, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd2, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd1, blur_feed_height),
					reduced_y_tap_valid(blur_feed_y, 3'd0, blur_feed_height)
				};
				if (blur_feed_epoch)
					blur_stage_history <= blur_history_1[blur_feed_x];
				else
					blur_stage_history <= blur_history_0[blur_feed_x];
			end

			vertical_mask_safe <=
				blur_stage_safe &&
				(|blur_stage_tap_valid);
			vertical_mask_x <= blur_stage_x;
			vertical_mask_y <= blur_stage_y;
			vertical_mask_epoch <= blur_stage_epoch;
			vertical_tap_0 <= mask_rgb(
				blur_stage_rgb, blur_stage_tap_valid[0]);
			vertical_tap_1 <= mask_rgb(
				blur_row_0, blur_stage_tap_valid[1]);
			vertical_tap_2 <= mask_rgb(
				blur_row_1, blur_stage_tap_valid[2]);
			vertical_tap_3 <= mask_rgb(
				blur_row_2, blur_stage_tap_valid[3]);
			vertical_tap_4 <= mask_rgb(
				blur_row_3, blur_stage_tap_valid[4]);
			vertical_tap_5 <= mask_rgb(
				blur_row_4, blur_stage_tap_valid[5]);
			vertical_tap_6 <= mask_rgb(
				blur_row_5, blur_stage_tap_valid[6]);
			vertical_tap_7 <= mask_rgb(
				blur_row_6, blur_stage_tap_valid[7]);

			if (blur_stage_valid) begin
				if (blur_stage_epoch)
					blur_history_1[blur_stage_x] <= {
						blur_stage_history[6*ENERGY_RGB_W-1:0],
						blur_stage_rgb
					};
				else
					blur_history_0[blur_stage_x] <= {
						blur_stage_history[6*ENERGY_RGB_W-1:0],
						blur_stage_rgb
					};
			end

			vertical_part_safe <= vertical_mask_safe;
			vertical_part_x <= vertical_mask_x;
			vertical_part_y <= vertical_mask_y;
			vertical_part_epoch <= vertical_mask_epoch;
			vertical_part_edge_r <=
				spread8_edge(
					vertical_tap_0[3*ENERGY_W-1:2*ENERGY_W],
					vertical_tap_7[3*ENERGY_W-1:2*ENERGY_W],
					halo_spread_mode_q);
			vertical_part_near_r <=
				spread8_near(
					vertical_tap_1[3*ENERGY_W-1:2*ENERGY_W],
					vertical_tap_6[3*ENERGY_W-1:2*ENERGY_W],
					halo_spread_mode_q);
			vertical_part_mid_r <=
				spread8_mid(
					vertical_tap_2[3*ENERGY_W-1:2*ENERGY_W],
					vertical_tap_5[3*ENERGY_W-1:2*ENERGY_W],
					halo_spread_mode_q);
			vertical_part_center_r <=
				spread8_center(
					vertical_tap_3[3*ENERGY_W-1:2*ENERGY_W],
					vertical_tap_4[3*ENERGY_W-1:2*ENERGY_W],
					halo_spread_mode_q);
			vertical_part_edge_g <=
				spread8_edge(
					vertical_tap_0[2*ENERGY_W-1:ENERGY_W],
					vertical_tap_7[2*ENERGY_W-1:ENERGY_W],
					halo_spread_mode_q);
			vertical_part_near_g <=
				spread8_near(
					vertical_tap_1[2*ENERGY_W-1:ENERGY_W],
					vertical_tap_6[2*ENERGY_W-1:ENERGY_W],
					halo_spread_mode_q);
			vertical_part_mid_g <=
				spread8_mid(
					vertical_tap_2[2*ENERGY_W-1:ENERGY_W],
					vertical_tap_5[2*ENERGY_W-1:ENERGY_W],
					halo_spread_mode_q);
			vertical_part_center_g <=
				spread8_center(
					vertical_tap_3[2*ENERGY_W-1:ENERGY_W],
					vertical_tap_4[2*ENERGY_W-1:ENERGY_W],
					halo_spread_mode_q);
			vertical_part_edge_b <=
				spread8_edge(
					vertical_tap_0[ENERGY_W-1:0],
					vertical_tap_7[ENERGY_W-1:0],
					halo_spread_mode_q);
			vertical_part_near_b <=
				spread8_near(
					vertical_tap_1[ENERGY_W-1:0],
					vertical_tap_6[ENERGY_W-1:0],
					halo_spread_mode_q);
			vertical_part_mid_b <=
				spread8_mid(
					vertical_tap_2[ENERGY_W-1:0],
					vertical_tap_5[ENERGY_W-1:0],
					halo_spread_mode_q);
			vertical_part_center_b <=
				spread8_center(
					vertical_tap_3[ENERGY_W-1:0],
					vertical_tap_4[ENERGY_W-1:0],
					halo_spread_mode_q);

			vertical_sum_safe <= vertical_part_safe;
			vertical_sum_x <= vertical_part_x;
			vertical_sum_y <= vertical_part_y;
			vertical_sum_epoch <= vertical_part_epoch;
			vertical_sum_r <=
				vertical_part_edge_r +
				vertical_part_near_r +
				vertical_part_mid_r +
				vertical_part_center_r + SPREAD_SUM_W'(64);
			vertical_sum_g <=
				vertical_part_edge_g +
				vertical_part_near_g +
				vertical_part_mid_g +
				vertical_part_center_g + SPREAD_SUM_W'(64);
			vertical_sum_b <=
				vertical_part_edge_b +
				vertical_part_near_b +
				vertical_part_mid_b +
				vertical_part_center_b + SPREAD_SUM_W'(64);

			vertical_blur_safe <= vertical_sum_safe;
			vertical_blur_x <= vertical_sum_x;
			vertical_blur_y <= vertical_sum_y;
			vertical_blur_epoch <= vertical_sum_epoch;
			vertical_blur_rgb <= {
				vertical_sum_r[SPREAD_SUM_W-1:7],
				vertical_sum_g[SPREAD_SUM_W-1:7],
				vertical_sum_b[SPREAD_SUM_W-1:7]
			};
		end
	end

	logic flush_active;
	logic [2:0] flush_count;
	logic flush_epoch;
	logic [7:0] flush_y;
	logic [COARSE_W-1:0] horizontal_step_x;
	logic horizontal_step_valid;
	logic horizontal_step_epoch;
	logic [7:0] horizontal_step_y;
	logic [ENERGY_RGB_W-1:0] horizontal_step_rgb;
	logic [ENERGY_RGB_W-1:0] h_history [0:6];
	logic [6:0] h_valid_history;
	logic horizontal_row_safe;
	logic [1:0] horizontal_row_bank;
	logic horizontal_row_epoch;
	logic [7:0] horizontal_row_y;
	logic horizontal_mask_valid;
	logic horizontal_mask_row_complete;
	logic [COARSE_W-1:0] horizontal_mask_x;
	logic [1:0] horizontal_mask_bank;
	logic horizontal_mask_epoch;
	logic [7:0] horizontal_mask_y;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_0;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_1;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_2;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_3;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_4;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_5;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_6;
	logic [ENERGY_RGB_W-1:0] horizontal_mask_tap_7;
	logic horizontal_candidate_valid;
	logic horizontal_candidate_row_complete;
	logic [COARSE_W-1:0] horizontal_candidate_x;
	logic [1:0] horizontal_candidate_bank;
	logic horizontal_current_tap_valid;
	logic [6:0] horizontal_candidate_history_valid;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_0;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_1;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_2;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_3;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_4;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_5;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_6;
	logic [ENERGY_RGB_W-1:0] horizontal_candidate_tap_7;
	logic horizontal_part_valid;
	logic horizontal_part_row_complete;
	logic [COARSE_W-1:0] horizontal_part_x;
	logic [1:0] horizontal_part_bank;
	logic horizontal_part_epoch;
	logic [7:0] horizontal_part_y;
	logic [SPREAD_SUM_W-1:0] horizontal_part_edge_r;
	logic [SPREAD_SUM_W-1:0] horizontal_part_near_r;
	logic [SPREAD_SUM_W-1:0] horizontal_part_mid_r;
	logic [SPREAD_SUM_W-1:0] horizontal_part_center_r;
	logic [SPREAD_SUM_W-1:0] horizontal_part_edge_g;
	logic [SPREAD_SUM_W-1:0] horizontal_part_near_g;
	logic [SPREAD_SUM_W-1:0] horizontal_part_mid_g;
	logic [SPREAD_SUM_W-1:0] horizontal_part_center_g;
	logic [SPREAD_SUM_W-1:0] horizontal_part_edge_b;
	logic [SPREAD_SUM_W-1:0] horizontal_part_near_b;
	logic [SPREAD_SUM_W-1:0] horizontal_part_mid_b;
	logic [SPREAD_SUM_W-1:0] horizontal_part_center_b;
	logic horizontal_total_valid;
	logic horizontal_total_row_complete;
	logic [COARSE_W-1:0] horizontal_total_x;
	logic [1:0] horizontal_total_bank;
	logic horizontal_total_epoch;
	logic [7:0] horizontal_total_y;
	logic [SPREAD_SUM_W-1:0] horizontal_outer_pair_r;
	logic [SPREAD_SUM_W-1:0] horizontal_inner_pair_r;
	logic [SPREAD_SUM_W-1:0] horizontal_outer_pair_g;
	logic [SPREAD_SUM_W-1:0] horizontal_inner_pair_g;
	logic [SPREAD_SUM_W-1:0] horizontal_outer_pair_b;
	logic [SPREAD_SUM_W-1:0] horizontal_inner_pair_b;
	wire [SPREAD_SUM_W-1:0] horizontal_combined_r =
		horizontal_outer_pair_r + horizontal_inner_pair_r +
		SPREAD_SUM_W'(64);
	wire [SPREAD_SUM_W-1:0] horizontal_combined_g =
		horizontal_outer_pair_g + horizontal_inner_pair_g +
		SPREAD_SUM_W'(64);
	wire [SPREAD_SUM_W-1:0] horizontal_combined_b =
		horizontal_outer_pair_b + horizontal_inner_pair_b +
		SPREAD_SUM_W'(64);

	always_comb begin
		horizontal_step_valid = vertical_blur_valid || flush_active;
		horizontal_step_x = flush_active
			? coarse_width + (3'd4 - flush_count)
			: vertical_blur_x;
		horizontal_step_epoch = flush_active
			? flush_epoch : vertical_blur_epoch;
		horizontal_step_y = flush_active ? flush_y : vertical_blur_y;
		horizontal_step_rgb = flush_active ? '0 : vertical_blur_rgb;

		horizontal_current_tap_valid =
			(horizontal_step_x < coarse_width);
		horizontal_candidate_history_valid = (horizontal_step_x == 0)
			? 7'd0 : h_valid_history;
		horizontal_candidate_tap_0 = horizontal_step_rgb;
		horizontal_candidate_tap_1 = mask_rgb(
			h_history[0], horizontal_candidate_history_valid[0]);
		horizontal_candidate_tap_2 = mask_rgb(
			h_history[1], horizontal_candidate_history_valid[1]);
		horizontal_candidate_tap_3 = mask_rgb(
			h_history[2], horizontal_candidate_history_valid[2]);
		horizontal_candidate_tap_4 = mask_rgb(
			h_history[3], horizontal_candidate_history_valid[3]);
		horizontal_candidate_tap_5 = mask_rgb(
			h_history[4], horizontal_candidate_history_valid[4]);
		horizontal_candidate_tap_6 = mask_rgb(
			h_history[5], horizontal_candidate_history_valid[5]);
		horizontal_candidate_tap_7 = mask_rgb(
			h_history[6], horizontal_candidate_history_valid[6]);

		horizontal_candidate_x = '0;
		if (horizontal_step_x >= 4)
			horizontal_candidate_x = horizontal_step_x - 3'd4;
		horizontal_candidate_bank = (horizontal_step_x == 0)
			? write_bank[horizontal_step_epoch] : horizontal_row_bank;
		horizontal_candidate_valid =
			horizontal_step_valid &&
			(horizontal_step_x >= 4) &&
			(horizontal_candidate_x < coarse_width) &&
			(horizontal_row_y >= RECON_FIRST_ROW);
		horizontal_candidate_row_complete =
			(horizontal_candidate_x + 1'b1 >= coarse_width) &&
			horizontal_row_safe;
	end

	(* ramstyle = "MLAB, no_rw_check" *) logic [23:0] halo_row_0a [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [23:0] halo_row_1a [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [23:0] halo_row_2a [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [23:0] halo_row_0b [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [23:0] halo_row_1b [0:COARSE_WIDTH-1];
	(* ramstyle = "MLAB, no_rw_check" *) logic [23:0] halo_row_2b [0:COARSE_WIDTH-1];
	logic horizontal_blur_valid;
	logic horizontal_blur_row_complete;
	logic [COARSE_W-1:0] horizontal_blur_x;
	logic [1:0] horizontal_blur_bank;
	logic horizontal_blur_epoch;
	logic [7:0] horizontal_blur_y;
	logic [ENERGY_W-1:0] horizontal_blur_r;
	logic [ENERGY_W-1:0] horizontal_blur_g;
	logic [ENERGY_W-1:0] horizontal_blur_b;
	logic horizontal_write_valid;
	logic horizontal_write_row_complete;
	logic [COARSE_W-1:0] horizontal_write_x;
	logic [23:0] horizontal_write_rgb;
	logic [1:0] horizontal_write_bank;
	logic horizontal_write_epoch;
	logic [7:0] horizontal_write_y;
	function automatic [1:0] bank_for_reduced_y(
		input logic [7:0] y
	);
		logic [2:0] even_bits;
		logic [2:0] odd_bits;
		logic [3:0] folded;
		begin
			even_bits =
				{2'd0, y[0]} + {2'd0, y[2]} +
				{2'd0, y[4]} + {2'd0, y[6]};
			odd_bits =
				{2'd0, y[1]} + {2'd0, y[3]} +
				{2'd0, y[5]} + {2'd0, y[7]};
			folded = {1'b0, even_bits} + {odd_bits, 1'b0};
			if (folded >= 4'd12) folded = folded - 4'd12;
			if (folded >= 4'd6)  folded = folded - 4'd6;
			if (folded >= 4'd3)  folded = folded - 4'd3;
			case (folded[1:0])
				2'd0: bank_for_reduced_y = 2'd0;
				2'd1: bank_for_reduced_y = 2'd1;
				default: bank_for_reduced_y = 2'd2;
			endcase
		end
	endfunction

	function automatic logic row_in_recon_ring(
		input logic [7:0] y,
		input logic [7:0] rows_done
	);
		logic [7:0] oldest_resident;
		begin
			if (y < RECON_FIRST_ROW || y >= rows_done) begin
				row_in_recon_ring = 1'b0;
			end else if (rows_done <= RECON_FIRST_ROW + 8'd3) begin
				row_in_recon_ring = 1'b1;
			end else begin
				oldest_resident = rows_done - 8'd3;
				row_in_recon_ring = (y >= oldest_resident);
			end
		end
	endfunction

	function automatic [7:0] clamp_recon_bottom_y(
		input logic [7:0] y,
		input logic [7:0] rows_done
	);
		begin
			if (y >= rows_done && rows_done > RECON_FIRST_ROW)
				clamp_recon_bottom_y = rows_done - 1'b1;
			else
				clamp_recon_bottom_y = y;
		end
	endfunction

	integer history_i;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			flush_active <= 1'b0;
			flush_count <= 3'd0;
			flush_epoch <= 1'b0;
			flush_y <= 8'd0;
			write_bank[0] <= RECON_FIRST_BANK;
			write_bank[1] <= RECON_FIRST_BANK;
			completed_rows[0] <= 8'd0;
			completed_rows[1] <= 8'd0;
			horizontal_blur_valid <= 1'b0;
			horizontal_blur_row_complete <= 1'b0;
			horizontal_blur_x <= '0;
			horizontal_blur_bank <= 2'd0;
			horizontal_blur_epoch <= 1'b0;
			horizontal_blur_y <= 8'd0;
			horizontal_blur_r <= '0;
			horizontal_blur_g <= '0;
			horizontal_blur_b <= '0;
			horizontal_write_valid <= 1'b0;
			horizontal_write_row_complete <= 1'b0;
			horizontal_write_x <= '0;
			horizontal_write_rgb <= 24'd0;
			horizontal_write_bank <= 2'd0;
			horizontal_write_epoch <= 1'b0;
			horizontal_write_y <= 8'd0;
			horizontal_row_safe <= 1'b0;
			horizontal_row_bank <= 2'd0;
			horizontal_row_epoch <= 1'b0;
			horizontal_row_y <= 8'd0;
			horizontal_mask_valid <= 1'b0;
			horizontal_mask_row_complete <= 1'b0;
			horizontal_mask_x <= '0;
			horizontal_mask_bank <= 2'd0;
			horizontal_mask_epoch <= 1'b0;
			horizontal_mask_y <= 8'd0;
			horizontal_mask_tap_0 <= '0;
			horizontal_mask_tap_1 <= '0;
			horizontal_mask_tap_2 <= '0;
			horizontal_mask_tap_3 <= '0;
			horizontal_mask_tap_4 <= '0;
			horizontal_mask_tap_5 <= '0;
			horizontal_mask_tap_6 <= '0;
			horizontal_mask_tap_7 <= '0;
			horizontal_part_valid <= 1'b0;
			horizontal_part_row_complete <= 1'b0;
			horizontal_part_x <= '0;
			horizontal_part_bank <= 2'd0;
			horizontal_part_epoch <= 1'b0;
			horizontal_part_y <= 8'd0;
			horizontal_part_edge_r <= '0;
			horizontal_part_near_r <= '0;
			horizontal_part_mid_r <= '0;
			horizontal_part_center_r <= '0;
			horizontal_part_edge_g <= '0;
			horizontal_part_near_g <= '0;
			horizontal_part_mid_g <= '0;
			horizontal_part_center_g <= '0;
			horizontal_part_edge_b <= '0;
			horizontal_part_near_b <= '0;
			horizontal_part_mid_b <= '0;
			horizontal_part_center_b <= '0;
			horizontal_total_valid <= 1'b0;
			horizontal_total_row_complete <= 1'b0;
			horizontal_total_x <= '0;
			horizontal_total_bank <= 2'd0;
			horizontal_total_epoch <= 1'b0;
			horizontal_total_y <= 8'd0;
			horizontal_outer_pair_r <= '0;
			horizontal_inner_pair_r <= '0;
			horizontal_outer_pair_g <= '0;
			horizontal_inner_pair_g <= '0;
			horizontal_outer_pair_b <= '0;
			horizontal_inner_pair_b <= '0;
			for (history_i = 0; history_i < 7;
			     history_i = history_i + 1)
				h_history[history_i] <= '0;
			h_valid_history <= 7'd0;
		end else begin
			if (source_frame_active_start) begin
				write_bank[next_source_epoch] <= RECON_FIRST_BANK;
				completed_rows[next_source_epoch] <= 8'd0;
			end

			horizontal_mask_valid <= horizontal_candidate_valid;
			horizontal_mask_row_complete <=
				horizontal_candidate_row_complete;
			horizontal_mask_x <= horizontal_candidate_x;
			horizontal_mask_bank <= horizontal_candidate_bank;
			horizontal_mask_epoch <= horizontal_row_epoch;
			horizontal_mask_y <= horizontal_row_y;
			horizontal_mask_tap_0 <= horizontal_candidate_tap_0;
			horizontal_mask_tap_1 <= horizontal_candidate_tap_1;
			horizontal_mask_tap_2 <= horizontal_candidate_tap_2;
			horizontal_mask_tap_3 <= horizontal_candidate_tap_3;
			horizontal_mask_tap_4 <= horizontal_candidate_tap_4;
			horizontal_mask_tap_5 <= horizontal_candidate_tap_5;
			horizontal_mask_tap_6 <= horizontal_candidate_tap_6;
			horizontal_mask_tap_7 <= horizontal_candidate_tap_7;
			horizontal_part_valid <= horizontal_mask_valid;
			horizontal_total_valid <= horizontal_part_valid;
			horizontal_blur_valid <= horizontal_total_valid;
			horizontal_write_valid <= horizontal_blur_valid;

			if (horizontal_write_valid) begin
				case ({horizontal_write_epoch, horizontal_write_bank})
					3'b000: halo_row_0a[horizontal_write_x] <=
						horizontal_write_rgb;
					3'b001: halo_row_1a[horizontal_write_x] <=
						horizontal_write_rgb;
					3'b010: halo_row_2a[horizontal_write_x] <=
						horizontal_write_rgb;
					3'b100: halo_row_0b[horizontal_write_x] <=
						horizontal_write_rgb;
					3'b101: halo_row_1b[horizontal_write_x] <=
						horizontal_write_rgb;
					default: halo_row_2b[horizontal_write_x] <=
						horizontal_write_rgb;
				endcase

				if (horizontal_write_row_complete) begin
					if (horizontal_write_bank == 2'd2)
						write_bank[horizontal_write_epoch] <=
							2'd0;
					else
						write_bank[horizontal_write_epoch] <=
							horizontal_write_bank + 1'b1;
					completed_rows[horizontal_write_epoch] <=
						horizontal_write_y + 8'd1;
				end
			end

			horizontal_total_row_complete <=
				horizontal_part_row_complete;
			horizontal_total_x <= horizontal_part_x;
			horizontal_total_bank <= horizontal_part_bank;
			horizontal_total_epoch <= horizontal_part_epoch;
			horizontal_total_y <= horizontal_part_y;
			horizontal_outer_pair_r <=
				horizontal_part_edge_r +
				horizontal_part_near_r;
			horizontal_inner_pair_r <=
				horizontal_part_mid_r +
				horizontal_part_center_r;
			horizontal_outer_pair_g <=
				horizontal_part_edge_g +
				horizontal_part_near_g;
			horizontal_inner_pair_g <=
				horizontal_part_mid_g +
				horizontal_part_center_g;
			horizontal_outer_pair_b <=
				horizontal_part_edge_b +
				horizontal_part_near_b;
			horizontal_inner_pair_b <=
				horizontal_part_mid_b +
				horizontal_part_center_b;

			horizontal_blur_row_complete <=
				horizontal_total_row_complete;
			horizontal_blur_x <= horizontal_total_x;
			horizontal_blur_bank <= horizontal_total_bank;
			horizontal_blur_epoch <= horizontal_total_epoch;
			horizontal_blur_y <= horizontal_total_y;
			horizontal_blur_r <=
				horizontal_combined_r[SPREAD_SUM_W-1:7];
			horizontal_blur_g <=
				horizontal_combined_g[SPREAD_SUM_W-1:7];
			horizontal_blur_b <=
				horizontal_combined_b[SPREAD_SUM_W-1:7];

			horizontal_write_row_complete <=
				horizontal_blur_row_complete;
			horizontal_write_x <= horizontal_blur_x;
			horizontal_write_bank <= horizontal_blur_bank;
			horizontal_write_epoch <= horizontal_blur_epoch;
			horizontal_write_y <= horizontal_blur_y;
			horizontal_write_rgb <= {
				compress_filtered_energy(
					horizontal_blur_r,
					halo_knee_threshold_q),
				compress_filtered_energy(
					horizontal_blur_g,
					halo_knee_threshold_q),
				compress_filtered_energy(
					horizontal_blur_b,
					halo_knee_threshold_q)
			};

			horizontal_part_row_complete <=
				horizontal_mask_row_complete;
			horizontal_part_x <= horizontal_mask_x;
			horizontal_part_bank <= horizontal_mask_bank;
			horizontal_part_epoch <= horizontal_mask_epoch;
			horizontal_part_y <= horizontal_mask_y;
			horizontal_part_edge_r <= spread8_edge(
				horizontal_mask_tap_0[3*ENERGY_W-1:2*ENERGY_W],
				horizontal_mask_tap_7[3*ENERGY_W-1:2*ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_near_r <= spread8_near(
				horizontal_mask_tap_1[3*ENERGY_W-1:2*ENERGY_W],
				horizontal_mask_tap_6[3*ENERGY_W-1:2*ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_mid_r <= spread8_mid(
				horizontal_mask_tap_2[3*ENERGY_W-1:2*ENERGY_W],
				horizontal_mask_tap_5[3*ENERGY_W-1:2*ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_center_r <= spread8_center(
				horizontal_mask_tap_3[3*ENERGY_W-1:2*ENERGY_W],
				horizontal_mask_tap_4[3*ENERGY_W-1:2*ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_edge_g <= spread8_edge(
				horizontal_mask_tap_0[2*ENERGY_W-1:ENERGY_W],
				horizontal_mask_tap_7[2*ENERGY_W-1:ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_near_g <= spread8_near(
				horizontal_mask_tap_1[2*ENERGY_W-1:ENERGY_W],
				horizontal_mask_tap_6[2*ENERGY_W-1:ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_mid_g <= spread8_mid(
				horizontal_mask_tap_2[2*ENERGY_W-1:ENERGY_W],
				horizontal_mask_tap_5[2*ENERGY_W-1:ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_center_g <= spread8_center(
				horizontal_mask_tap_3[2*ENERGY_W-1:ENERGY_W],
				horizontal_mask_tap_4[2*ENERGY_W-1:ENERGY_W],
				halo_spread_mode_q);
			horizontal_part_edge_b <= spread8_edge(
				horizontal_mask_tap_0[ENERGY_W-1:0],
				horizontal_mask_tap_7[ENERGY_W-1:0],
				halo_spread_mode_q);
			horizontal_part_near_b <= spread8_near(
				horizontal_mask_tap_1[ENERGY_W-1:0],
				horizontal_mask_tap_6[ENERGY_W-1:0],
				halo_spread_mode_q);
			horizontal_part_mid_b <= spread8_mid(
				horizontal_mask_tap_2[ENERGY_W-1:0],
				horizontal_mask_tap_5[ENERGY_W-1:0],
				halo_spread_mode_q);
			horizontal_part_center_b <= spread8_center(
				horizontal_mask_tap_3[ENERGY_W-1:0],
				horizontal_mask_tap_4[ENERGY_W-1:0],
				halo_spread_mode_q);

			if (vertical_blur_valid &&
			    vertical_blur_x + 1'b1 >= coarse_width) begin
				flush_active <= 1'b1;
				flush_count <= 3'd4;
				flush_epoch <= vertical_blur_epoch;
				flush_y <= vertical_blur_y;
			end else if (flush_active) begin
				if (flush_count == 3'd1) begin
					flush_active <= 1'b0;
					flush_count <= 3'd0;
				end else begin
					flush_count <= flush_count - 1'b1;
				end
			end

			if (horizontal_step_valid) begin
				if (horizontal_step_x == 0) begin
					horizontal_row_safe <= vertical_blur_safe;
					horizontal_row_bank <=
						write_bank[horizontal_step_epoch];
					horizontal_row_epoch <= horizontal_step_epoch;
					horizontal_row_y <= horizontal_step_y;
				end

				h_history[6] <= h_history[5];
				h_history[5] <= h_history[4];
				h_history[4] <= h_history[3];
				h_history[3] <= h_history[2];
				h_history[2] <= h_history[1];
				h_history[1] <= h_history[0];
				h_history[0] <= horizontal_step_rgb;
				if (horizontal_step_x == 0) begin
					h_valid_history <=
						{6'd0, horizontal_current_tap_valid};
				end else begin
					h_valid_history[6] <= h_valid_history[5];
					h_valid_history[5] <= h_valid_history[4];
					h_valid_history[4] <= h_valid_history[3];
					h_valid_history[3] <= h_valid_history[2];
					h_valid_history[2] <= h_valid_history[1];
					h_valid_history[1] <= h_valid_history[0];
					h_valid_history[0] <=
						horizontal_current_tap_valid;
				end
			end
		end
	end

	// Full-resolution bilinear reconstruction.
	// RECON_SAMPLE_*_ADVANCE aligns coarse halo samples with final pixels.
	localparam [11:0] RECONSTRUCTION_PIPELINE_X_ADVANCE = 12'd3;
	localparam [11:0] RECONSTRUCTION_X_ADVANCE =
		RECONSTRUCTION_PIPELINE_X_ADVANCE +
		{8'd0, RECON_SAMPLE_X_ADVANCE};

	logic [1:0] display_latest_bank;
	logic [1:0] display_previous_bank;
	logic display_epoch;
	logic display_latest_row_valid;
	logic display_previous_row_valid;
	logic [4:0] display_v_weight;
	logic wide_active;
	logic [11:0] wide_x;
	logic [23:0] right_latest;
	logic [23:0] right_previous;
	logic line_packet_valid;
	logic [11:0] line_packet_reconstruction_line;
	logic line_packet_epoch;
	logic line_coord_valid;
	logic line_coord_epoch;
	logic [7:0] line_coord_latest_y;
	logic [7:0] line_coord_previous_y;
	logic line_coord_previous_y_valid;
	logic [7:0] line_coord_rows_done;
	logic line_coord_visible;
	logic [4:0] line_coord_v_weight;
	logic line_decode_valid;
	logic line_decode_epoch;
	logic [1:0] line_decode_latest_bank;
	logic [1:0] line_decode_previous_bank;
	logic line_decode_latest_visible;
	logic line_decode_previous_visible;
	logic line_decode_any_row_visible;
	logic [4:0] line_decode_v_weight;
	logic display_line_ready;

	wire [12:0] line_packet_sample_line =
		{1'b0, line_packet_reconstruction_line} +
		{9'd0, RECON_SAMPLE_Y_ADVANCE};
	wire [7:0] line_packet_base_y =
		line_packet_sample_line[11:4];
	wire [7:0] line_packet_latest_y =
		line_packet_base_y + VERTICAL_CENTER_DELAY_ROWS;
	wire [7:0] line_packet_previous_y =
		line_packet_latest_y - 1'b1;
	wire line_packet_previous_y_valid =
		(line_packet_latest_y != 8'd0);
	wire [7:0] line_packet_rows_done =
		completed_rows[line_packet_epoch];
	wire line_packet_visible =
		(line_packet_reconstruction_line < previous_frame_total_lines);
	wire [3:0] line_packet_phase =
		line_packet_sample_line[3:0];
	wire [4:0] line_packet_v_weight =
		{1'b0, line_packet_phase} + 5'd1;

	wire [7:0] line_coord_latest_read_y =
		clamp_recon_bottom_y(
			line_coord_latest_y,
			line_coord_rows_done);
	wire [7:0] line_coord_previous_read_y =
		clamp_recon_bottom_y(
			line_coord_previous_y,
			line_coord_rows_done);
	wire [1:0] line_coord_latest_bank =
		bank_for_reduced_y(line_coord_latest_read_y);
	wire line_coord_latest_visible =
		line_coord_visible &&
		row_in_recon_ring(
			line_coord_latest_read_y,
			line_coord_rows_done);
	wire [1:0] line_coord_previous_bank =
		bank_for_reduced_y(line_coord_previous_read_y);
	wire line_coord_previous_visible =
		(line_coord_visible &&
		 line_coord_previous_y_valid &&
		 row_in_recon_ring(
			line_coord_previous_read_y,
			line_coord_rows_done));
	wire line_coord_any_row_visible =
		line_coord_latest_visible || line_coord_previous_visible;

	function automatic signed [8:0] interp_delta(
		input logic [7:0] left,
		input logic [7:0] right
	);
		begin
			interp_delta =
				$signed({1'b0, right}) - $signed({1'b0, left});
		end
	endfunction

	wire reconstruction_next_step = line_decode_valid || wide_active;
	wire [11:0] reconstruction_next_x =
		line_decode_valid ? RECONSTRUCTION_X_ADVANCE : wide_x;
	wire [4:0] reconstruction_next_v_weight =
		line_decode_valid ? line_decode_v_weight : display_v_weight;
	wire reconstruction_next_rows_valid =
		line_decode_valid ? line_decode_any_row_visible :
		(display_line_ready &&
		 (display_latest_row_valid || display_previous_row_valid));

	logic reconstruction_step_q;
	logic [11:0] reconstruction_x_q;
	logic [4:0] vertical_weight_q;
	logic reconstruction_rows_valid_q;
	logic [23:0] horizontal_latest;
	logic [23:0] horizontal_previous;
	logic horizontal_valid;
	logic signed [8:0] latest_delta_r;
	logic signed [8:0] latest_delta_g;
	logic signed [8:0] latest_delta_b;
	logic signed [8:0] previous_delta_r;
	logic signed [8:0] previous_delta_g;
	logic signed [8:0] previous_delta_b;
	logic signed [13:0] latest_ramp_r;
	logic signed [13:0] latest_ramp_g;
	logic signed [13:0] latest_ramp_b;
	logic signed [13:0] previous_ramp_r;
	logic signed [13:0] previous_ramp_g;
	logic signed [13:0] previous_ramp_b;
	logic vertical_blend_s0_valid;
	logic [4:0] vertical_blend_s0_weight;
	logic [7:0] vertical_blend_s0_prev_r;
	logic [7:0] vertical_blend_s0_prev_g;
	logic [7:0] vertical_blend_s0_prev_b;
	logic signed [8:0] vertical_blend_s0_delta_r;
	logic signed [8:0] vertical_blend_s0_delta_g;
	logic signed [8:0] vertical_blend_s0_delta_b;
	logic vertical_blend_s1_valid;
	logic signed [14:0] vertical_blend_s1_base_r;
	logic signed [14:0] vertical_blend_s1_base_g;
	logic signed [14:0] vertical_blend_s1_base_b;
	logic signed [14:0] vertical_blend_s1_scaled_r;
	logic signed [14:0] vertical_blend_s1_scaled_g;
	logic signed [14:0] vertical_blend_s1_scaled_b;
	logic [23:0] halo_out_rgb;
	logic halo_out_valid;
	logic [23:0] halo_pending_rgb;
	logic halo_pending_valid;
	logic segment_read_valid;
	logic segment_read_in_range;
	logic [COARSE_W-1:0] segment_read_addr;
	logic segment_sample_valid;
	logic segment_latest_sample_valid;
	logic segment_previous_sample_valid;
	logic [23:0] segment_latest_raw;
	logic [23:0] segment_previous_raw;
	logic [23:0] segment_latest_sample;
	logic [23:0] segment_previous_sample;
	logic segment_start_valid;
	logic signed [8:0] segment_latest_delta_r;
	logic signed [8:0] segment_latest_delta_g;
	logic signed [8:0] segment_latest_delta_b;
	logic signed [8:0] segment_previous_delta_r;
	logic signed [8:0] segment_previous_delta_g;
	logic signed [8:0] segment_previous_delta_b;
	logic signed [13:0] segment_latest_start_r;
	logic signed [13:0] segment_latest_start_g;
	logic signed [13:0] segment_latest_start_b;
	logic signed [13:0] segment_previous_start_r;
	logic signed [13:0] segment_previous_start_g;
	logic signed [13:0] segment_previous_start_b;

	function automatic signed [13:0] interp_start_from_delta(
		input logic [7:0] left,
		input logic signed [8:0] delta
	);
		begin
			interp_start_from_delta =
				$signed({1'b0, left, 4'b0000}) +
				{{5{delta[8]}}, delta} +
				14'sd8;
		end
	endfunction

	function automatic signed [13:0] interp_advance(
		input logic signed [13:0] ramp,
		input logic signed [8:0] delta
	);
		begin
			interp_advance = ramp + {{5{delta[8]}}, delta};
		end
	endfunction

	function automatic [7:0] interp_ramp_channel(
		input logic signed [13:0] ramp
	);
		begin
			interp_ramp_channel = ramp[11:4];
		end
	endfunction

	function automatic signed [14:0] vertical_lerp_base(
		input logic [7:0] left
	);
		begin
			vertical_lerp_base = $signed({3'b000, left, 4'b0000});
		end
	endfunction

	function automatic signed [14:0] vertical_lerp_scaled_delta(
		input logic signed [8:0] delta,
		input logic [4:0] weight
	);
		begin
			vertical_lerp_scaled_delta =
				delta * $signed({1'b0, weight});
		end
	endfunction

	function automatic [7:0] vertical_lerp_finish(
		input logic signed [14:0] base,
		input logic signed [14:0] scaled_delta
	);
		logic signed [14:0] rounded;
		begin
			rounded = base + scaled_delta + 15'sd8;
			vertical_lerp_finish = rounded[11:4];
		end
	endfunction

	function automatic [23:0] vertical_lerp_finish_rgb(
		input logic signed [14:0] base_r,
		input logic signed [14:0] base_g,
		input logic signed [14:0] base_b,
		input logic signed [14:0] scaled_r,
		input logic signed [14:0] scaled_g,
		input logic signed [14:0] scaled_b
	);
		begin
			vertical_lerp_finish_rgb = {
				vertical_lerp_finish(base_r, scaled_r),
				vertical_lerp_finish(base_g, scaled_g),
				vertical_lerp_finish(base_b, scaled_b)
			};
		end
	endfunction

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			display_latest_bank <= 2'd0;
			display_previous_bank <= 2'd0;
			display_epoch <= 1'b0;
			display_latest_row_valid <= 1'b0;
			display_previous_row_valid <= 1'b0;
			display_v_weight <= 5'd0;
			wide_active <= 1'b0;
			wide_x <= 12'd0;
			right_latest <= 24'd0;
			right_previous <= 24'd0;
			source_full_line_y <= 12'd0;
			previous_frame_total_lines <= active_height;
			line_packet_valid <= 1'b0;
			line_packet_reconstruction_line <= 12'd0;
			line_packet_epoch <= 1'b0;
			line_coord_valid <= 1'b0;
			line_coord_epoch <= 1'b0;
			line_coord_latest_y <= 8'd0;
			line_coord_previous_y <= 8'd0;
			line_coord_previous_y_valid <= 1'b0;
			line_coord_rows_done <= 8'd0;
			line_coord_visible <= 1'b0;
			line_coord_v_weight <= 5'd0;
			line_decode_valid <= 1'b0;
			line_decode_epoch <= 1'b0;
			line_decode_latest_bank <= 2'd0;
			line_decode_previous_bank <= 2'd0;
			line_decode_latest_visible <= 1'b0;
			line_decode_previous_visible <= 1'b0;
			line_decode_any_row_visible <= 1'b0;
			line_decode_v_weight <= 5'd0;
			display_line_ready <= 1'b0;
			reconstruction_step_q <= 1'b0;
			reconstruction_x_q <= 12'd0;
			vertical_weight_q <= 5'd0;
			reconstruction_rows_valid_q <= 1'b0;
			horizontal_latest <= 24'd0;
			horizontal_previous <= 24'd0;
			horizontal_valid <= 1'b0;
			latest_delta_r <= 9'sd0;
			latest_delta_g <= 9'sd0;
			latest_delta_b <= 9'sd0;
			previous_delta_r <= 9'sd0;
			previous_delta_g <= 9'sd0;
			previous_delta_b <= 9'sd0;
			latest_ramp_r <= 14'sd8;
			latest_ramp_g <= 14'sd8;
			latest_ramp_b <= 14'sd8;
			previous_ramp_r <= 14'sd8;
			previous_ramp_g <= 14'sd8;
			previous_ramp_b <= 14'sd8;
			vertical_blend_s0_valid <= 1'b0;
			vertical_blend_s0_weight <= 5'd0;
			vertical_blend_s0_prev_r <= 8'd0;
			vertical_blend_s0_prev_g <= 8'd0;
			vertical_blend_s0_prev_b <= 8'd0;
			vertical_blend_s0_delta_r <= 9'sd0;
			vertical_blend_s0_delta_g <= 9'sd0;
			vertical_blend_s0_delta_b <= 9'sd0;
			vertical_blend_s1_valid <= 1'b0;
			vertical_blend_s1_base_r <= 15'sd0;
			vertical_blend_s1_base_g <= 15'sd0;
			vertical_blend_s1_base_b <= 15'sd0;
			vertical_blend_s1_scaled_r <= 15'sd0;
			vertical_blend_s1_scaled_g <= 15'sd0;
			vertical_blend_s1_scaled_b <= 15'sd0;
			halo_out_rgb <= 24'd0;
			halo_out_valid <= 1'b0;
			halo_pending_rgb <= 24'd0;
			halo_pending_valid <= 1'b0;
			segment_read_valid <= 1'b0;
			segment_read_in_range <= 1'b0;
			segment_read_addr <= '0;
			segment_sample_valid <= 1'b0;
			segment_latest_sample_valid <= 1'b0;
			segment_previous_sample_valid <= 1'b0;
			segment_latest_raw <= 24'd0;
			segment_previous_raw <= 24'd0;
			segment_latest_sample <= 24'd0;
			segment_previous_sample <= 24'd0;
			segment_start_valid <= 1'b0;
			segment_latest_delta_r <= 9'sd0;
			segment_latest_delta_g <= 9'sd0;
			segment_latest_delta_b <= 9'sd0;
			segment_previous_delta_r <= 9'sd0;
			segment_previous_delta_g <= 9'sd0;
			segment_previous_delta_b <= 9'sd0;
			segment_latest_start_r <= 14'sd8;
			segment_latest_start_g <= 14'sd8;
			segment_latest_start_b <= 14'sd8;
			segment_previous_start_r <= 14'sd8;
			segment_previous_start_g <= 14'sd8;
			segment_previous_start_b <= 14'sd8;
		end else begin
			segment_read_valid <= 1'b0;
			segment_sample_valid <= segment_read_valid;
			segment_latest_sample_valid <=
				segment_read_valid &&
				segment_read_in_range &&
				display_latest_row_valid;
			segment_previous_sample_valid <=
				segment_read_valid &&
				segment_read_in_range &&
				display_previous_row_valid;
			horizontal_valid <=
				reconstruction_step_q && reconstruction_rows_valid_q;
			vertical_blend_s0_valid <= horizontal_valid;
			vertical_blend_s1_valid <= vertical_blend_s0_valid;

			// Horizontal ramps update every clock. horizontal_valid marks the
			// values that belong to visible output.
			horizontal_latest <= {
				interp_ramp_channel(latest_ramp_r),
				interp_ramp_channel(latest_ramp_g),
				interp_ramp_channel(latest_ramp_b)
			};
			horizontal_previous <= {
				interp_ramp_channel(previous_ramp_r),
				interp_ramp_channel(previous_ramp_g),
				interp_ramp_channel(previous_ramp_b)
			};

			// Vertical reconstruction uses the delta form:
			//   prev<<4 + (latest-prev) * w
			// Only valid results can reach the visible halo.
			vertical_blend_s0_weight <= vertical_weight_q;
			vertical_blend_s0_prev_r <= horizontal_previous[23:16];
			vertical_blend_s0_prev_g <= horizontal_previous[15:8];
			vertical_blend_s0_prev_b <= horizontal_previous[7:0];
			vertical_blend_s0_delta_r <=
				interp_delta(horizontal_previous[23:16],
					horizontal_latest[23:16]);
			vertical_blend_s0_delta_g <=
				interp_delta(horizontal_previous[15:8],
					horizontal_latest[15:8]);
			vertical_blend_s0_delta_b <=
				interp_delta(horizontal_previous[7:0],
					horizontal_latest[7:0]);
			vertical_blend_s1_base_r <=
				vertical_lerp_base(vertical_blend_s0_prev_r);
			vertical_blend_s1_base_g <=
				vertical_lerp_base(vertical_blend_s0_prev_g);
			vertical_blend_s1_base_b <=
				vertical_lerp_base(vertical_blend_s0_prev_b);
			vertical_blend_s1_scaled_r <=
				vertical_lerp_scaled_delta(
					vertical_blend_s0_delta_r,
					vertical_blend_s0_weight);
			vertical_blend_s1_scaled_g <=
				vertical_lerp_scaled_delta(
					vertical_blend_s0_delta_g,
					vertical_blend_s0_weight);
			vertical_blend_s1_scaled_b <=
				vertical_lerp_scaled_delta(
					vertical_blend_s0_delta_b,
					vertical_blend_s0_weight);

			// Prepare the next 16-pixel span over the final four pixels:
			//   x+12: register the coarse row address,
			//   x+13: read and register the row RAM outputs,
			//   x+14: compute the next ramp start/delta,
			//   x+15: load that prepared ramp for the following span.
			// This keeps the row-RAM read separate from interpolation setup.
			if (reconstruction_step_q &&
			    reconstruction_x_q[3:0] == 4'd12) begin
				logic [COARSE_W-1:0] prefetch_address;
				logic [COARSE_W-1:0] last_address;

				segment_read_valid <= 1'b1;
				if (coarse_width == '0) begin
					segment_read_addr <= '0;
					segment_read_in_range <= 1'b0;
				end else if (reconstruction_x_q[11:4] < 4) begin
					segment_read_addr <= '0;
					segment_read_in_range <= 1'b1;
				end else begin
					last_address = coarse_width - 1'b1;
					prefetch_address =
						reconstruction_x_q[COARSE_W+3:4] - 3'd4;
					if (prefetch_address >= coarse_width)
						segment_read_addr <= last_address;
					else
						segment_read_addr <= prefetch_address;
					segment_read_in_range <= 1'b1;
				end
			end

			case ({display_epoch, display_latest_bank})
				3'b000: segment_latest_raw <=
					halo_row_0a[segment_read_addr];
				3'b001: segment_latest_raw <=
					halo_row_1a[segment_read_addr];
				3'b010: segment_latest_raw <=
					halo_row_2a[segment_read_addr];
				3'b100: segment_latest_raw <=
					halo_row_0b[segment_read_addr];
				3'b101: segment_latest_raw <=
					halo_row_1b[segment_read_addr];
				default: segment_latest_raw <=
					halo_row_2b[segment_read_addr];
			endcase

			case ({display_epoch, display_previous_bank})
				3'b000: segment_previous_raw <=
					halo_row_0a[segment_read_addr];
				3'b001: segment_previous_raw <=
					halo_row_1a[segment_read_addr];
				3'b010: segment_previous_raw <=
					halo_row_2a[segment_read_addr];
				3'b100: segment_previous_raw <=
					halo_row_0b[segment_read_addr];
				3'b101: segment_previous_raw <=
					halo_row_1b[segment_read_addr];
				default: segment_previous_raw <=
					halo_row_2b[segment_read_addr];
			endcase

			if (segment_sample_valid) begin
				logic [23:0] latest_sample_next;
				logic [23:0] previous_sample_next;
				logic signed [8:0] latest_delta_r_next;
				logic signed [8:0] latest_delta_g_next;
				logic signed [8:0] latest_delta_b_next;
				logic signed [8:0] previous_delta_r_next;
				logic signed [8:0] previous_delta_g_next;
				logic signed [8:0] previous_delta_b_next;

				latest_sample_next =
					segment_latest_sample_valid ?
					segment_latest_raw : 24'd0;
				previous_sample_next =
					segment_previous_sample_valid ?
					segment_previous_raw : 24'd0;
				segment_latest_sample <= latest_sample_next;
				segment_previous_sample <= previous_sample_next;

				latest_delta_r_next =
					interp_delta(right_latest[23:16],
						latest_sample_next[23:16]);
				latest_delta_g_next =
					interp_delta(right_latest[15:8],
						latest_sample_next[15:8]);
				latest_delta_b_next =
					interp_delta(right_latest[7:0],
						latest_sample_next[7:0]);
				previous_delta_r_next =
					interp_delta(right_previous[23:16],
						previous_sample_next[23:16]);
				previous_delta_g_next =
					interp_delta(right_previous[15:8],
						previous_sample_next[15:8]);
				previous_delta_b_next =
					interp_delta(right_previous[7:0],
						previous_sample_next[7:0]);

				segment_latest_delta_r <= latest_delta_r_next;
				segment_latest_delta_g <= latest_delta_g_next;
				segment_latest_delta_b <= latest_delta_b_next;
				segment_previous_delta_r <= previous_delta_r_next;
				segment_previous_delta_g <= previous_delta_g_next;
				segment_previous_delta_b <= previous_delta_b_next;
				segment_latest_start_r <=
					interp_start_from_delta(
						right_latest[23:16],
						latest_delta_r_next);
				segment_latest_start_g <=
					interp_start_from_delta(
						right_latest[15:8],
						latest_delta_g_next);
				segment_latest_start_b <=
					interp_start_from_delta(
						right_latest[7:0],
						latest_delta_b_next);
				segment_previous_start_r <=
					interp_start_from_delta(
						right_previous[23:16],
						previous_delta_r_next);
				segment_previous_start_g <=
					interp_start_from_delta(
						right_previous[15:8],
						previous_delta_g_next);
				segment_previous_start_b <=
					interp_start_from_delta(
						right_previous[7:0],
						previous_delta_b_next);
				segment_start_valid <= 1'b1;
			end

			if (reconstruction_step_q &&
			    reconstruction_x_q[3:0] == 4'd15) begin
				right_latest <= segment_latest_sample;
				right_previous <= segment_previous_sample;
				if (segment_start_valid) begin
					latest_delta_r <= segment_latest_delta_r;
					latest_delta_g <= segment_latest_delta_g;
					latest_delta_b <= segment_latest_delta_b;
					previous_delta_r <= segment_previous_delta_r;
					previous_delta_g <= segment_previous_delta_g;
					previous_delta_b <= segment_previous_delta_b;
					latest_ramp_r <= segment_latest_start_r;
					latest_ramp_g <= segment_latest_start_g;
					latest_ramp_b <= segment_latest_start_b;
					previous_ramp_r <= segment_previous_start_r;
					previous_ramp_g <= segment_previous_start_g;
					previous_ramp_b <= segment_previous_start_b;
				end else begin
					latest_delta_r <= 9'sd0;
					latest_delta_g <= 9'sd0;
					latest_delta_b <= 9'sd0;
					previous_delta_r <= 9'sd0;
					previous_delta_g <= 9'sd0;
					previous_delta_b <= 9'sd0;
					latest_ramp_r <= 14'sd8;
					latest_ramp_g <= 14'sd8;
					latest_ramp_b <= 14'sd8;
					previous_ramp_r <= 14'sd8;
					previous_ramp_g <= 14'sd8;
					previous_ramp_b <= 14'sd8;
				end
				segment_start_valid <= 1'b0;
			end else if (reconstruction_step_q) begin
				latest_ramp_r <=
					interp_advance(latest_ramp_r, latest_delta_r);
				latest_ramp_g <=
					interp_advance(latest_ramp_g, latest_delta_g);
				latest_ramp_b <=
					interp_advance(latest_ramp_b, latest_delta_b);
				previous_ramp_r <=
					interp_advance(previous_ramp_r,
						previous_delta_r);
				previous_ramp_g <=
					interp_advance(previous_ramp_g,
						previous_delta_g);
				previous_ramp_b <=
					interp_advance(previous_ramp_b,
						previous_delta_b);
			end

			if (ce_pix) begin
				line_packet_valid <= line_start;
				if (line_start) begin
					line_packet_reconstruction_line <=
						reconstruction_line_for_line;
					line_packet_epoch <= reconstruction_epoch;
				end
				line_coord_valid <= line_packet_valid;
				if (line_packet_valid) begin
					line_coord_epoch <= line_packet_epoch;
					line_coord_latest_y <= line_packet_latest_y;
					line_coord_previous_y <=
						line_packet_previous_y;
					line_coord_previous_y_valid <=
						line_packet_previous_y_valid;
					line_coord_rows_done <= line_packet_rows_done;
					line_coord_visible <= line_packet_visible;
					line_coord_v_weight <= line_packet_v_weight;
				end
				line_decode_valid <= line_coord_valid;
				if (line_coord_valid) begin
					line_decode_epoch <= line_coord_epoch;
					line_decode_latest_bank <=
						line_coord_latest_bank;
					line_decode_previous_bank <=
						line_coord_previous_bank;
					line_decode_latest_visible <=
						line_coord_latest_visible;
					line_decode_previous_visible <=
						line_coord_previous_visible;
					line_decode_any_row_visible <=
						line_coord_any_row_visible;
					line_decode_v_weight <= line_coord_v_weight;
				end

				if (source_frame_active_start) begin
					previous_frame_total_lines <=
						(source_full_line_y != 12'd0)
							? source_full_line_y
							: active_height;
					source_full_line_y <= 12'd1;
				end else if (line_start) begin
					source_full_line_y <=
						source_full_line_y + 1'b1;
				end

				if (vertical_blend_s1_valid) begin
					halo_out_rgb <= vertical_lerp_finish_rgb(
						vertical_blend_s1_base_r,
						vertical_blend_s1_base_g,
						vertical_blend_s1_base_b,
						vertical_blend_s1_scaled_r,
						vertical_blend_s1_scaled_g,
						vertical_blend_s1_scaled_b);
					halo_out_valid <= 1'b1;
				end else if (halo_pending_valid) begin
					halo_out_rgb <= halo_pending_rgb;
					halo_out_valid <= 1'b1;
				end else begin
					halo_out_rgb <= 24'd0;
					halo_out_valid <= 1'b0;
				end
				halo_pending_valid <= 1'b0;

				reconstruction_step_q <= reconstruction_next_step;
				reconstruction_x_q <= reconstruction_next_x;
				vertical_weight_q <= reconstruction_next_v_weight;
				reconstruction_rows_valid_q <=
					reconstruction_next_rows_valid;

				if (line_decode_valid) begin
					display_epoch <= line_decode_epoch;
					display_latest_bank <=
						line_decode_latest_bank;
					display_previous_bank <=
						line_decode_previous_bank;
					display_latest_row_valid <=
						line_decode_latest_visible;
					display_previous_row_valid <=
						line_decode_previous_visible;
					display_v_weight <= line_decode_v_weight;
					display_line_ready <= 1'b1;
				end

				if (line_start) begin
					display_line_ready <= 1'b0;
					wide_active <= 1'b0;
					right_latest <= 24'd0;
					right_previous <= 24'd0;
					latest_delta_r <= 9'sd0;
					latest_delta_g <= 9'sd0;
					latest_delta_b <= 9'sd0;
					previous_delta_r <= 9'sd0;
					previous_delta_g <= 9'sd0;
					previous_delta_b <= 9'sd0;
					latest_ramp_r <= 14'sd8;
					latest_ramp_g <= 14'sd8;
					latest_ramp_b <= 14'sd8;
					previous_ramp_r <= 14'sd8;
					previous_ramp_g <= 14'sd8;
					previous_ramp_b <= 14'sd8;
					segment_read_valid <= 1'b0;
					segment_read_in_range <= 1'b0;
					segment_sample_valid <= 1'b0;
					segment_start_valid <= 1'b0;
				end else if (line_decode_valid) begin
					wide_active <= 1'b1;
					wide_x <= RECONSTRUCTION_X_ADVANCE + 12'd1;
					right_latest <= 24'd0;
					right_previous <= 24'd0;
					latest_delta_r <= 9'sd0;
					latest_delta_g <= 9'sd0;
					latest_delta_b <= 9'sd0;
					previous_delta_r <= 9'sd0;
					previous_delta_g <= 9'sd0;
					previous_delta_b <= 9'sd0;
					latest_ramp_r <= 14'sd8;
					latest_ramp_g <= 14'sd8;
					latest_ramp_b <= 14'sd8;
					previous_ramp_r <= 14'sd8;
					previous_ramp_g <= 14'sd8;
					previous_ramp_b <= 14'sd8;
					segment_read_valid <= 1'b0;
					segment_read_in_range <= 1'b0;
					segment_sample_valid <= 1'b0;
					segment_start_valid <= 1'b0;
				end else if (wide_active) begin
					if (wide_x == MAX_WIDTH + H_DELAY - 1)
						wide_active <= 1'b0;
					else
						wide_x <= wide_x + 1'b1;
				end

			end else begin
				if (vertical_blend_s1_valid) begin
					halo_pending_rgb <= vertical_lerp_finish_rgb(
						vertical_blend_s1_base_r,
						vertical_blend_s1_base_g,
						vertical_blend_s1_base_b,
						vertical_blend_s1_scaled_r,
						vertical_blend_s1_scaled_g,
						vertical_blend_s1_scaled_b);
					halo_pending_valid <= 1'b1;
				end
				reconstruction_step_q <= 1'b0;
			end
		end
	end

	always_comb begin
		HALO_R_OUT = halo_out_valid ? halo_out_rgb[23:16] : 8'd0;
		HALO_G_OUT = halo_out_valid ? halo_out_rgb[15:8] : 8'd0;
		HALO_B_OUT = halo_out_valid ? halo_out_rgb[7:0] : 8'd0;
		HALO_VALID_OUT = halo_out_valid;
	end

endmodule
