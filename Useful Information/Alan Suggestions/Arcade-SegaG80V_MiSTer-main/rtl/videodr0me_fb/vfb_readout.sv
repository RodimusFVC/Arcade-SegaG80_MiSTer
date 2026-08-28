// ============================================================================
// Framebuffer readout and phosphor-decay stage.
// written 2026 by Videodr0me
// Operates in the renderer/video clock domain.
// Reads tile rows from DDRAM, converts them back to pixels, and applies
// phosphor decay and the hit-flash background.
// ============================================================================

module vfb_readout #(
	parameter TILE_SIZE = 8,
	parameter MAX_BURST_TILES = 15
) (
	input  logic clk_sys,
	input  logic reset,

	// DDRAM read interface
	output logic        readout_ready,
	input  logic        readout_grant,
	output logic [15:0] readout_tile_id,
	output logic [8:0]  readout_burstcnt,
	input  logic [63:0] readout_data,
	input  logic        readout_data_valid,

	output logic        vbl_swap_req,

	// Video output
	output logic [7:0]  VGA_R,
	output logic [7:0]  VGA_G,
	output logic [7:0]  VGA_B,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  logic [10:0] h_cnt,
	input  logic [10:0] v_cnt,
	input  logic        ce_pix,
	input  logic        hsync,
	input  logic        vsync,
	input  logic        hblank,
	input  logic        vblank,

	input  logic [23:0] FLASH_PARAM,
	input  logic [11:0] RENDER_WIDTH,
	input  logic [11:0] RENDER_HEIGHT,

	input  logic [2:0]  draw_idx,           // Phosphor persistence draw index
	input  logic [31:0] phosphor_age_map,   // Eight packed physical-age entries
	input  logic [1:0]  osd_phosphor_mode,  // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  logic        expand_highlights,
	input  logic        display_is_composed,

	output logic [14:0] display_tile_addr,
	input  logic        display_tile_dirty
);

	import vfb_layout_pkg::*;

	// Two alternating tile-row buffers hold 184 active tiles and one blanking
	// guard tile. Each row is split between 2K and 1K banks.
	localparam ROW_TILES = 185;
	localparam ROW_LOW_WORDS = 2048;
	localparam ROW_HIGH_WORDS = 1024;

	logic [1:0] phosphor_mode_control_q = 2'd0;
	logic       expand_highlights_control_q = 1'b0;
	always_ff @(posedge clk_sys) begin
		phosphor_mode_control_q <= osd_phosphor_mode;
		expand_highlights_control_q <= expand_highlights;
	end

	(* ramstyle = "M10K" *) logic [63:0] buffer_0_low [0:ROW_LOW_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_0_high [0:ROW_HIGH_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_1_low [0:ROW_LOW_WORDS-1];
	(* ramstyle = "M10K" *) logic [63:0] buffer_1_high [0:ROW_HIGH_WORDS-1];

	logic buf_state;

	// Register timing before tile addressing and edge detection.
	logic [10:0] h_cnt_r, v_cnt_r;
	logic        hsync_r, vsync_r, hblank_r, vblank_r;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			// Restart edge detection from blanking.
			h_cnt_r  <= 0;
			v_cnt_r  <= 0;
			hsync_r  <= 0;
			vsync_r  <= 0;
			hblank_r <= 1;
			vblank_r <= 1;
		end else begin
			h_cnt_r  <= h_cnt;
			v_cnt_r  <= v_cnt;
			hsync_r  <= hsync;
			vsync_r  <= vsync;
			hblank_r <= hblank;
			vblank_r <= vblank;
		end
	end

	// Detect line and VBLANK edges.
	logic [10:0] prev_h_cnt;
	logic        prev_hblank_r;
	logic start_prefetch_row0;
	logic advance_row;
	logic [7:0] advance_fetch_y;

	typedef enum logic [2:0] {
		IDLE,
		SCAN_WAIT,
		SCAN_DECIDE,
		ZERO_DATA,
		BURST_REQ,
		BURST_WAIT,
		BURST_DATA
	} fetch_state_t;
	fetch_state_t fetch_state = IDLE;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			prev_h_cnt <= 0;
			prev_hblank_r <= 1;
			start_prefetch_row0 <= 0;
			advance_row <= 0;
			advance_fetch_y <= 0;
			vbl_swap_req <= 0;
		end else begin
			prev_h_cnt <= h_cnt_r;
			prev_hblank_r <= hblank_r;

			start_prefetch_row0 <= 0;
			advance_row <= 0;
			vbl_swap_req <= 0;

			// Start a new output line.
			if (h_cnt_r == 0 && prev_h_cnt != 0) begin
				if (v_cnt_r == RENDER_HEIGHT) begin
					// VBLANK starts: prepare row 0.
					start_prefetch_row0 <= 1;
					vbl_swap_req <= 1;
				end
			end

			// Switch rows during blanking after local line 7.
			if (!prev_hblank_r && hblank_r) begin
				if ((v_cnt_r + 11'd1) < RENDER_HEIGHT &&
				    v_cnt_r[2:0] == 3'd7) begin
					if (fetch_state == IDLE) begin
						advance_row <= 1;
						advance_fetch_y <= v_cnt_r[10:3] + 8'd2;
					end
				end
			end
		end
	end

	// Fill the row buffers.

	// Tile-grid dimensions change only with the video mode.
	logic [8:0] render_tile_cols;  // ceil(RENDER_WIDTH / 8)
	logic [8:0] render_tile_rows;  // ceil(RENDER_HEIGHT / 8)
	always_ff @(posedge clk_sys) begin
		render_tile_cols <= vfb_tile_columns(RENDER_WIDTH);
		render_tile_rows <= vfb_tile_rows(RENDER_HEIGHT);
	end

	logic [7:0] fetch_tile_x;
	logic [7:0] target_fetch_y;
	logic [14:0] fetch_tile_addr;
	logic       row0_prefetch_active;

	logic [7:0] run_start_x;
	logic [4:0] run_length;     // Dirty tiles in the pending burst
	logic [4:0] zero_word_cnt;  // 0 to 15 for inline zeroing
	logic [8:0] burst_beat_cnt; // Accepted beats in the active burst

	assign display_tile_addr = fetch_tile_addr;

	wire row_end = ({4'd0, fetch_tile_x} + 12'd1 >= {3'd0, render_tile_cols});
	wire row_done = ({4'd0, fetch_tile_x} >= {3'd0, render_tile_cols});

	// Row-buffer write pipeline
	logic        bram_we_r;
	logic        bram_buf_r;
	logic [11:0] bram_addr_r;
	logic [63:0] bram_data_r;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			fetch_state <= IDLE;
			readout_ready <= 0;
			buf_state <= 0;
			bram_we_r <= 0;
			fetch_tile_addr <= 0;
			row0_prefetch_active <= 0;
		end else begin
			// At VBLANK, abandon an incomplete fetch and restart at row 0.
			if (start_prefetch_row0) begin
				buf_state <= 0; // Reset rolling buffer
				target_fetch_y <= 0;
				fetch_tile_x <= 0;
				fetch_tile_addr <= 0;
				run_length <= 0;
				fetch_state <= SCAN_WAIT;
				readout_ready <= 0; // Cancel any pending request.
				row0_prefetch_active <= 1;
			end else begin
				case (fetch_state)
					IDLE: begin
						if (advance_row) begin
							buf_state <= ~buf_state;
							target_fetch_y <= advance_fetch_y;
							// Fetch only if the following row is visible.
							if ({1'b0, advance_fetch_y} < render_tile_rows) begin
								fetch_tile_x <= 0;
								fetch_tile_addr <=
									vfb_tile_row_addr(advance_fetch_y);
								run_length <= 0;
								fetch_state <= SCAN_WAIT;
							end
						end
					end

				SCAN_WAIT: begin
					// Wait one cycle for the synchronous tilemap query.
					fetch_state <= SCAN_DECIDE;
				end

				SCAN_DECIDE: begin
					if (display_tile_dirty) begin
						if (run_length == 0) run_start_x <= fetch_tile_x;

						if (row_end) begin
							// End of row: request the run including this tile.
							run_length <= run_length + 5'd1;
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= BURST_REQ;
						end else if (run_length + 5'd1 == MAX_BURST_TILES[4:0]) begin
							// The run reached its burst limit.
							run_length <= run_length + 5'd1;
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= BURST_REQ;
						end else begin
							// Continue along the row.
							run_length <= run_length + 5'd1;
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= SCAN_WAIT;
						end
					end else begin
						if (run_length > 0) begin
							// Request the dirty run before checking this clean tile.
							fetch_state <= BURST_REQ;
						end else begin
							// No dirty run: clear this tile locally.
							zero_word_cnt <= 0;
							fetch_state <= ZERO_DATA;
						end
					end
				end

				ZERO_DATA: begin
					if (zero_word_cnt == 5'd15) begin
						if (row_end) begin
							if (row0_prefetch_active) begin
								row0_prefetch_active <= 0;
								buf_state <= ~buf_state;
								target_fetch_y <= 8'd1;
								if (render_tile_rows > 9'd1) begin
									fetch_tile_x <= 0;
									fetch_tile_addr <=
										vfb_tile_row_addr(8'd1);
									run_length <= 0;
									fetch_state <= SCAN_WAIT;
								end else begin
									fetch_state <= IDLE;
								end
							end else begin
								fetch_state <= IDLE;
							end
						end else begin
							fetch_tile_x <= fetch_tile_x + 8'd1;
							fetch_tile_addr <= fetch_tile_addr + 15'd1;
							fetch_state <= SCAN_WAIT;
						end
					end else begin
						zero_word_cnt <= zero_word_cnt + 5'd1;
					end
				end

				BURST_REQ: begin
					readout_ready <= 1;
					readout_tile_id <= {target_fetch_y, run_start_x};
					readout_burstcnt <= {4'd0, run_length} << 4; // run_length * 16
					burst_beat_cnt <= 0;
					fetch_state <= BURST_WAIT;
				end

				BURST_WAIT: begin
					if (readout_grant) begin
						readout_ready <= 0;
						fetch_state <= BURST_DATA;
					end
				end

				BURST_DATA: begin
					if (readout_data_valid) begin
						if (burst_beat_cnt + 9'd1 == readout_burstcnt) begin
							run_length <= 0;
							if (row_done) begin
								if (row0_prefetch_active) begin
									row0_prefetch_active <= 0;
									buf_state <= ~buf_state;
									target_fetch_y <= 8'd1;
									if (render_tile_rows > 9'd1) begin
										fetch_tile_x <= 0;
										fetch_tile_addr <=
											vfb_tile_row_addr(8'd1);
										run_length <= 0;
										fetch_state <= SCAN_WAIT;
									end else begin
										fetch_state <= IDLE;
									end
								end else begin
									fetch_state <= IDLE;
								end
							end else begin
								fetch_state <= SCAN_WAIT;
							end
						end else begin
							burst_beat_cnt <= burst_beat_cnt + 9'd1;
						end
					end
				end
				endcase
			end

			// Write the prepared row-buffer word.
			bram_we_r <= 0;
			if (fetch_state == BURST_DATA && readout_data_valid) begin
				bram_we_r   <= 1;
				bram_buf_r  <= ~buf_state;
				bram_addr_r <= {run_start_x + burst_beat_cnt[8:4], burst_beat_cnt[3:0]};
				bram_data_r <= readout_data;
			end else if (fetch_state == ZERO_DATA) begin
				bram_we_r   <= 1;
				bram_buf_r  <= ~buf_state;
				bram_addr_r <= {fetch_tile_x, zero_word_cnt[3:0]};
				bram_data_r <= 64'd0;
			end

			if (bram_we_r) begin
				if (bram_buf_r == 0) begin
					if (!bram_addr_r[11])
						buffer_0_low[bram_addr_r[10:0]] <= bram_data_r;
					else
						buffer_0_high[bram_addr_r[9:0]] <= bram_data_r;
				end else begin
					if (!bram_addr_r[11])
						buffer_1_low[bram_addr_r[10:0]] <= bram_data_r;
					else
						buffer_1_high[bram_addr_r[9:0]] <= bram_data_r;
				end
			end
		end
	end

	// Convert tile words back to pixels.
	// RGB and sync/blank follow the same nine-ce_pix path to the output register.
	// LOCAL MOD: 10, not Havoc's 9.
	//
	// The sync/blank shift register is tapped at [READ_ADVANCE-2], so it
	// delays sync by READ_ADVANCE-1 pixel enables to match the depth of the
	// pixel datapath. The Sega colour path adds one stage over Havoc's (the
	// shoulder add is registered ahead of the per-gun ladder, to keep the
	// 125 MHz path short), making the datapath 11 stages deep instead of 10.
	// Without this the picture sits one pixel right of its own blanking.
	localparam READ_ADVANCE = 10;

	logic [READ_ADVANCE-1:0] hs_pipe, vs_pipe, hb_pipe, vb_pipe;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			hs_pipe <= {READ_ADVANCE{1'b1}};
			vs_pipe <= {READ_ADVANCE{1'b1}};
			hb_pipe <= {READ_ADVANCE{1'b1}};
			vb_pipe <= {READ_ADVANCE{1'b1}};
		end else if (ce_pix) begin
			hs_pipe <= {hs_pipe[READ_ADVANCE-2:0], hsync_r};
			vs_pipe <= {vs_pipe[READ_ADVANCE-2:0], vsync_r};
			hb_pipe <= {hb_pipe[READ_ADVANCE-2:0], hblank_r};
			vb_pipe <= {vb_pipe[READ_ADVANCE-2:0], vblank_r};
		end
	end

	wire vga_hs_pre     = hs_pipe[READ_ADVANCE-2];
	wire vga_vs_pre     = vs_pipe[READ_ADVANCE-2];
	wire vga_hblank_pre = hb_pipe[READ_ADVANCE-2];
	wire vga_vblank_pre = vb_pipe[READ_ADVANCE-2];

	// Pixel read addresses
	wire [7:0] cur_tile_x = h_cnt_r[10:3];
	wire [5:0] cur_offset = {v_cnt_r[2:0], h_cnt_r[2:0]};
	wire [7:0] safe_tile_x =
		(hblank_r || cur_tile_x >= ROW_TILES) ? 8'(ROW_TILES-1) : cur_tile_x;
	wire [13:0] read_addr = {safe_tile_x, cur_offset}; // [13:2] = word addr, [1:0] = pixel sel
	wire [11:0] read_word_addr = read_addr[13:2];
	logic [1:0] pixel_sel_d1;
	logic [1:0] pixel_sel_d2;
	logic       buf_state_d1;
	logic       word_bank_d1;
	logic [63:0] raw_word_0_low, raw_word_0_high;
	logic [63:0] raw_word_1_low, raw_word_1_high;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			pixel_sel_d1 <= read_addr[1:0];
			buf_state_d1 <= buf_state;
			word_bank_d1 <= read_word_addr[11];
			raw_word_0_low <= buffer_0_low[read_word_addr[10:0]];
			raw_word_0_high <= buffer_0_high[read_word_addr[9:0]];
			raw_word_1_low <= buffer_1_low[read_word_addr[10:0]];
			raw_word_1_high <= buffer_1_high[read_word_addr[9:0]];
		end
	end

	logic [63:0] raw_word;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			pixel_sel_d2 <= pixel_sel_d1;
			case ({buf_state_d1, word_bank_d1})
				2'b00: raw_word <= raw_word_0_low;
				2'b01: raw_word <= raw_word_0_high;
				2'b10: raw_word <= raw_word_1_low;
				2'b11: raw_word <= raw_word_1_high;
			endcase
		end
	end

	logic [15:0] raw_pixel;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			case (pixel_sel_d2)
				2'b00: raw_pixel <= raw_word[15:0];
				2'b01: raw_pixel <= raw_word[31:16];
				2'b10: raw_pixel <= raw_word[47:32];
				2'b11: raw_pixel <= raw_word[63:48];
			endcase
		end
	end

	// Phosphor decay and RGB conversion

	// Decode the pixel and select its decay factor.
	// LOCAL MOD: 6-bit colour. Two pixel layouts share the 16 bits, told apart
	// by display_is_composed exactly as before:
	//   rasterised { rgb[5:0], draw_idx[2:0], z[7:1] }
	//   composed   { rgb[5:0], fresh,         energy[8:0] }
	wire [5:0] pixel_color_comb = raw_pixel[15:10];
	wire [8:0] pixel_int_comb = display_is_composed
	                          ? raw_pixel[8:0]
	                          : {1'b0, raw_pixel[6:0], raw_pixel[6]};

	// Map the stored draw-time phase to physical age.
	wire [2:0] pixel_draw_idx = raw_pixel[9:7];
	wire [2:0] pixel_age_raw = draw_idx - pixel_draw_idx;
	wire [4:0] pixel_age_map_offset = {pixel_age_raw, 2'b00};
	wire [3:0] pixel_age = phosphor_age_map[pixel_age_map_offset +: 4];

	// Approximate 8-bit exponential factors for nominal bases 0.99, 0.96,
	// and 0.98 across 16 ages.
	reg [7:0] decay_factor_comb;
	always_comb begin
		case ({phosphor_mode_control_q, pixel_age})
			// LUT A (mode 1, base 0.99)
			{2'd1, 4'd0}:  decay_factor_comb = 8'd255;
			{2'd1, 4'd1}:  decay_factor_comb = 8'd252;
			{2'd1, 4'd2}:  decay_factor_comb = 8'd250;
			{2'd1, 4'd3}:  decay_factor_comb = 8'd247;
			{2'd1, 4'd4}:  decay_factor_comb = 8'd245;
			{2'd1, 4'd5}:  decay_factor_comb = 8'd243;
			{2'd1, 4'd6}:  decay_factor_comb = 8'd240;
			{2'd1, 4'd7}:  decay_factor_comb = 8'd238;
			{2'd1, 4'd8}:  decay_factor_comb = 8'd235;
			{2'd1, 4'd9}:  decay_factor_comb = 8'd233;
			{2'd1, 4'd10}: decay_factor_comb = 8'd231;
			{2'd1, 4'd11}: decay_factor_comb = 8'd228;
			{2'd1, 4'd12}: decay_factor_comb = 8'd226;
			{2'd1, 4'd13}: decay_factor_comb = 8'd224;
			{2'd1, 4'd14}: decay_factor_comb = 8'd222;
			{2'd1, 4'd15}: decay_factor_comb = 8'd219;
			// LUT B (mode 2, base 0.96)
			{2'd2, 4'd0}:  decay_factor_comb = 8'd255;
			{2'd2, 4'd1}:  decay_factor_comb = 8'd245;
			{2'd2, 4'd2}:  decay_factor_comb = 8'd235;
			{2'd2, 4'd3}:  decay_factor_comb = 8'd226;
			{2'd2, 4'd4}:  decay_factor_comb = 8'd217;
			{2'd2, 4'd5}:  decay_factor_comb = 8'd208;
			{2'd2, 4'd6}:  decay_factor_comb = 8'd200;
			{2'd2, 4'd7}:  decay_factor_comb = 8'd192;
			{2'd2, 4'd8}:  decay_factor_comb = 8'd184;
			{2'd2, 4'd9}:  decay_factor_comb = 8'd177;
			{2'd2, 4'd10}: decay_factor_comb = 8'd170;
			{2'd2, 4'd11}: decay_factor_comb = 8'd163;
			{2'd2, 4'd12}: decay_factor_comb = 8'd156;
			{2'd2, 4'd13}: decay_factor_comb = 8'd150;
			{2'd2, 4'd14}: decay_factor_comb = 8'd144;
			{2'd2, 4'd15}: decay_factor_comb = 8'd138;
			// LUT C (mode 3, base 0.98)
			{2'd3, 4'd0}:  decay_factor_comb = 8'd255;
			{2'd3, 4'd1}:  decay_factor_comb = 8'd250;
			{2'd3, 4'd2}:  decay_factor_comb = 8'd245;
			{2'd3, 4'd3}:  decay_factor_comb = 8'd240;
			{2'd3, 4'd4}:  decay_factor_comb = 8'd235;
			{2'd3, 4'd5}:  decay_factor_comb = 8'd230;
			{2'd3, 4'd6}:  decay_factor_comb = 8'd225;
			{2'd3, 4'd7}:  decay_factor_comb = 8'd221;
			{2'd3, 4'd8}:  decay_factor_comb = 8'd216;
			{2'd3, 4'd9}:  decay_factor_comb = 8'd212;
			{2'd3, 4'd10}: decay_factor_comb = 8'd208;
			{2'd3, 4'd11}: decay_factor_comb = 8'd204;
			{2'd3, 4'd12}: decay_factor_comb = 8'd200;
			{2'd3, 4'd13}: decay_factor_comb = 8'd196;
			{2'd3, 4'd14}: decay_factor_comb = 8'd192;
			{2'd3, 4'd15}: decay_factor_comb = 8'd188;
			// Off mode is selected in the following stage.
			default: decay_factor_comb = 8'd255;
		endcase
	end

	// Register the decay factor with the decoded pixel.
	logic [7:0] decay_factor_r;
	logic [8:0] pixel_int_r;
	logic [5:0] pixel_color_r;
	logic [1:0] phosphor_mode_r;
	logic       display_composed_r;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			decay_factor_r <= decay_factor_comb;
			pixel_int_r    <= pixel_int_comb;
			pixel_color_r  <= pixel_color_comb;
			phosphor_mode_r <= phosphor_mode_control_q;
			display_composed_r <= display_is_composed;
		end
	end

	// Apply decay or pass the intensity unchanged.
	wire [16:0] decayed_full = pixel_int_r * decay_factor_r;  // 9x8 = 17 bits
	wire [8:0]  decayed_int  = decayed_full[16:8];            // >>8

	// Off mode keeps the original intensity.
	wire [8:0] final_int_comb =
		(display_composed_r || (phosphor_mode_r == 2'd0))
			? pixel_int_r : decayed_int;

	// Register intensity before crossing-energy conversion.
	logic [8:0] final_int;
	logic [5:0] pixel_color;
	logic       stored_overrange;
	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			final_int <= final_int_comb;
			pixel_color <= pixel_color_r;
			stored_overrange <= pixel_int_r[8];
		end
	end

	// Major Havoc's nominal z=240 is the full-scale DAC reference.
	localparam logic [9:0] OVERFLOW_SPILL_BASE = 10'd232;
	localparam logic [9:0] OVERFLOW_SPILL_CAP = 10'd64;

	logic [9:0] native_r;
	logic [9:0] native_g;
	logic [9:0] native_b;
	logic [9:0] selected_r;
	logic [9:0] selected_g;
	logic [9:0] selected_b;
	logic [9:0] capped_r;
	logic [9:0] capped_g;
	logic [9:0] capped_b;
	logic [9:0] excess_r;
	logic [9:0] excess_g;
	logic [9:0] excess_b;
	logic [9:0] excess_sum;
	logic [9:0] spill_full;
	logic [9:0] spill_half;
	logic [7:0] out_r_int;
	logic [7:0] out_g_int;
	logic [7:0] out_b_int;

	// SP-252 sheet 9A uses 5.6K main-color branches and a 22K fine-red
	// branch. The 13/64 and 51/64 split gives exactly 52/203 at z=240.
	function automatic logic [9:0] calibrated_dac_level(
		input logic [8:0] level
	);
		logic [13:0] scaled;
		begin
			scaled =
				({5'd0, level} << 4) +
				{5'd0, level} + 14'd8;
			calibrated_dac_level = scaled[13:4];
		end
	endfunction

	function automatic logic [9:0] fine_dac_level(
		input logic [9:0] level
	);
		logic [13:0] scaled;
		begin
			scaled =
				({4'd0, level} << 3) +
				({4'd0, level} << 2) +
				{4'd0, level} + 14'd32;
			fine_dac_level = scaled[13:6];
		end
	endfunction

	function automatic logic [7:0] clamp_dac_level(
		input logic [9:0] level
	);
		begin
			clamp_dac_level =
				(level > 10'd255) ? 8'd255 : level[7:0];
		end
	endfunction

	// Register calibrated intensity before resistor weighting and Bright-mode
	// expansion.
	logic [9:0] dac_total_q;
	logic [5:0] dac_color_q;
	logic       dac_overrange_q;
	logic       dac_active_q;
	logic       expand_highlights_q;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			dac_total_q <= calibrated_dac_level(final_int);
			dac_color_q <= pixel_color;
			dac_overrange_q <= stored_overrange;
			dac_active_q <= (final_int != 9'd0) &&
			                (pixel_color != 6'b000000);
			expand_highlights_q <= expand_highlights_control_q;
		end
	end

	logic [9:0] fine_level_comb;
	logic [9:0] main_level_comb;
	logic [9:0] shoulder_room_comb;
	logic [9:0] shoulder_comb;
	always_comb begin
		fine_level_comb = fine_dac_level(dac_total_q);
		main_level_comb = dac_total_q - fine_level_comb;
		shoulder_room_comb = (dac_total_q > 10'd203)
			? dac_total_q - 10'd203 : 10'd0;
		shoulder_comb = (shoulder_room_comb > fine_level_comb)
			? fine_level_comb : shoulder_room_comb;
	end

	// Register resistor-weighted levels before Bright-mode expansion and
	// channel selection.
	logic [9:0] dac_total_split_q;
	logic [9:0] fine_level_q;
	logic [9:0] main_level_q;
	logic [9:0] shoulder_q;
	logic [5:0] dac_color_split_q;
	logic       dac_overrange_split_q;
	logic       dac_active_split_q;
	logic       expand_highlights_split_q;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			dac_total_split_q <= dac_total_q;
			fine_level_q <= fine_level_comb;
			main_level_q <= main_level_comb;
			shoulder_q <= shoulder_comb;
			dac_color_split_q <= dac_color_q;
			dac_overrange_split_q <= dac_overrange_q;
			dac_active_split_q <= dac_active_q;
			expand_highlights_split_q <= expand_highlights_q;
		end
	end

	// LOCAL MOD: per-gun 2-bit level selection.
	//
	// Major Havoc has two red bits {strong, fine} against 1-bit green and
	// blue, so only red had a level ladder. The Sega G-80 X-Y Control board
	// drives all three guns from identical 2-bit weighted ladders (6.2k/12k
	// with 1N914s, drawing 800-0163 sheet 6/6), giving levels
	//     0, 1/3, 2/3, 1  of full scale
	// on every channel. dac_level() is the shared ladder; the red-only
	// fine/main split is gone and fine_level_q is no longer used here.
	//
	// The 3-bit presence mask below still drives the overrange spill case
	// unchanged: a channel is "lit" when its level is non-zero.

	// Register the Bright-mode shoulder addition separately from the ladder.
	// At 125 MHz the add followed by the 2-bit resistor weighting is the
	// critical path. Carry the pixel metadata through the same stage.
	logic [9:0] dac_total_ladder_q;
	logic [9:0] expanded_main_q;
	logic [5:0] dac_color_ladder_q;
	logic       dac_overrange_ladder_q;
	logic       dac_active_ladder_q;
	logic       expand_highlights_ladder_q;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			dac_total_ladder_q <= dac_total_split_q;
			expanded_main_q <= dac_total_split_q + shoulder_q;
			dac_color_ladder_q <= dac_color_split_q;
			dac_overrange_ladder_q <= dac_overrange_split_q;
			dac_active_ladder_q <= dac_active_split_q;
			expand_highlights_ladder_q <= expand_highlights_split_q;
		end
	end

	wire [2:0] pixel_rgb_comb = {
		|dac_color_ladder_q[5:4],
		|dac_color_ladder_q[3:2],
		|dac_color_ladder_q[1:0]
	};

	// The ladder itself lives in vfb_dac_ladder so it can be unit-tested.
	wire [9:0] native_r_w, native_g_w, native_b_w;
	wire [9:0] sel_r_w, sel_g_w, sel_b_w;

	vfb_dac_ladder lr (.level(dac_total_ladder_q), .sel(dac_color_ladder_q[5:4]), .out(native_r_w));
	vfb_dac_ladder lg (.level(dac_total_ladder_q), .sel(dac_color_ladder_q[3:2]), .out(native_g_w));
	vfb_dac_ladder lb (.level(dac_total_ladder_q), .sel(dac_color_ladder_q[1:0]), .out(native_b_w));
	vfb_dac_ladder sr (.level(expanded_main_q),    .sel(dac_color_ladder_q[5:4]), .out(sel_r_w));
	vfb_dac_ladder sg (.level(expanded_main_q),    .sel(dac_color_ladder_q[3:2]), .out(sel_g_w));
	vfb_dac_ladder sb (.level(expanded_main_q),    .sel(dac_color_ladder_q[1:0]), .out(sel_b_w));

	always_comb begin
		native_r = native_r_w;
		native_g = native_g_w;
		native_b = native_b_w;

		// expand_highlights lifts the shoulder into the level, as before
		selected_r = sel_r_w;
		selected_g = sel_g_w;
		selected_b = sel_b_w;

		if (!expand_highlights_ladder_q || dac_overrange_ladder_q) begin
			selected_r = native_r;
			selected_g = native_g;
			selected_b = native_b;
		end

	end

	// Register channel levels before crossing-energy conversion.
	(* preserve, dont_retime *) logic [9:0] native_r_q;
	(* preserve, dont_retime *) logic [9:0] native_g_q;
	(* preserve, dont_retime *) logic [9:0] native_b_q;
	(* preserve, dont_retime *) logic [9:0] selected_r_q;
	(* preserve, dont_retime *) logic [9:0] selected_g_q;
	(* preserve, dont_retime *) logic [9:0] selected_b_q;
	logic [2:0] pixel_rgb_q;
	logic       stored_overrange_q;
	logic       pixel_active_q;

	always_ff @(posedge clk_sys) begin
		if (ce_pix) begin
			native_r_q <= native_r;
			native_g_q <= native_g;
			native_b_q <= native_b;
			selected_r_q <= selected_r;
			selected_g_q <= selected_g;
			selected_b_q <= selected_b;
			pixel_rgb_q <= pixel_rgb_comb;
			stored_overrange_q <= dac_overrange_ladder_q;
			pixel_active_q <= dac_active_ladder_q;
		end
	end

	always_comb begin
		capped_r = (native_r_q > OVERFLOW_SPILL_BASE)
			? OVERFLOW_SPILL_BASE : native_r_q;
		capped_g = (native_g_q > OVERFLOW_SPILL_BASE)
			? OVERFLOW_SPILL_BASE : native_g_q;
		capped_b = (native_b_q > OVERFLOW_SPILL_BASE)
			? OVERFLOW_SPILL_BASE : native_b_q;
		excess_r = (native_r_q > OVERFLOW_SPILL_BASE)
			? native_r_q - OVERFLOW_SPILL_BASE : 10'd0;
		excess_g = (native_g_q > OVERFLOW_SPILL_BASE)
			? native_g_q - OVERFLOW_SPILL_BASE : 10'd0;
		excess_b = (native_b_q > OVERFLOW_SPILL_BASE)
			? native_b_q - OVERFLOW_SPILL_BASE : 10'd0;
		excess_sum = excess_r + excess_g + excess_b;
		spill_full = (excess_sum > OVERFLOW_SPILL_CAP)
			? OVERFLOW_SPILL_CAP : excess_sum;
		spill_half = ((excess_sum >> 1) > OVERFLOW_SPILL_CAP)
			? OVERFLOW_SPILL_CAP : (excess_sum >> 1);
	end

	always_comb begin
		out_r_int = 8'd0;
		out_g_int = 8'd0;
		out_b_int = 8'd0;

		if (!stored_overrange_q) begin
			out_r_int = clamp_dac_level(selected_r_q);
			out_g_int = clamp_dac_level(selected_g_q);
			out_b_int = clamp_dac_level(selected_b_q);
		end else begin
			unique case (pixel_rgb_q)
				3'b001: begin
					out_r_int = clamp_dac_level(spill_half);
					out_g_int = clamp_dac_level(spill_half);
					out_b_int = clamp_dac_level(capped_b);
				end
				3'b010: begin
					out_r_int = clamp_dac_level(spill_half);
					out_g_int = clamp_dac_level(capped_g);
					out_b_int = clamp_dac_level(spill_half);
				end
				3'b011: begin
					out_r_int = clamp_dac_level(spill_full);
					out_g_int = clamp_dac_level(capped_g);
					out_b_int = clamp_dac_level(capped_b);
				end
				3'b100: begin
					out_r_int = clamp_dac_level(capped_r);
					out_g_int = clamp_dac_level(spill_half);
					out_b_int = clamp_dac_level(spill_half);
				end
				3'b101: begin
					out_r_int = clamp_dac_level(capped_r);
					out_g_int = clamp_dac_level(spill_full);
					out_b_int = clamp_dac_level(capped_b);
				end
				3'b110: begin
					out_r_int = clamp_dac_level(capped_r);
					out_g_int = clamp_dac_level(capped_g);
					out_b_int = clamp_dac_level(spill_full);
				end
				3'b111: begin
					out_r_int = clamp_dac_level(native_r_q);
					out_g_int = clamp_dac_level(native_g_q);
					out_b_int = clamp_dac_level(native_b_q);
				end
				default: begin
					out_r_int = 8'd0;
					out_g_int = 8'd0;
					out_b_int = 8'd0;
				end
			endcase
		end
	end

	// Register the final output.
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			VGA_R <= 8'd0;
			VGA_G <= 8'd0;
			VGA_B <= 8'd0;
			VGA_HS <= 1'b1;
			VGA_VS <= 1'b1;
			VGA_HBLANK <= 1'b1;
			VGA_VBLANK <= 1'b1;
		end else if (ce_pix) begin
			VGA_HS <= vga_hs_pre;
			VGA_VS <= vga_vs_pre;
			VGA_HBLANK <= vga_hblank_pre;
			VGA_VBLANK <= vga_vblank_pre;

			if (~vga_hblank_pre && ~vga_vblank_pre) begin
				if (!pixel_active_q) begin
					// Flash effect for background pixels.
					VGA_R <= FLASH_PARAM[23:16];
					VGA_G <= FLASH_PARAM[15:8];
					VGA_B <= FLASH_PARAM[7:0];
				end else begin
					VGA_R <= out_r_int;
					VGA_G <= out_g_int;
					VGA_B <= out_b_int;
				end
			end else begin
				VGA_R <= 8'd0;
				VGA_G <= 8'd0;
				VGA_B <= 8'd0;
			end
		end
	end

endmodule
