// ============================================================================
// Vector pixel rasterizer.
// written 2026 by Videodr0me
// Transfers source pixels to the framebuffer clock and adds dot or diagonal
// fill pixels where selected.
// ============================================================================

module vfb_rasterizer #(
	parameter TILE_SIZE = 8,
	parameter FIFO_ADDR_W = 10
) (
	input  logic clk_sys,
	input  logic clk_source,
	input  logic reset,

	// Vector input
	input  logic [10:0] X_VECTOR,
	input  logic [10:0] Y_VECTOR,
	input  logic [7:0]  Z_VECTOR,
	input  logic [5:0]  COLOR,   // RRGGBB, 2 bits per gun
	input  logic        IS_DOT,
	input  logic        BEAM_ON,
	input  logic        FRAME_DONE,
	input  logic [2:0]  DOT_MODE,
	input  logic [11:0] FB_WIDTH,
	input  logic [11:0] FB_HEIGHT,

	// Tile cache output
	output logic        pixel_valid,
	input  logic        pixel_ready,
	output logic [15:0] pixel_tile_id,
	output logic [5:0]  pixel_offset,
	output logic [15:0] pixel_data,
	input  logic [2:0]  draw_idx,         // Pixel draw-time phase
	input  logic [15:0] frame_tick_clks, // Source clocks per draw-index phase
	input  logic [15:0] completed_frame_tick_clks,

	output logic        eof_token,
	output logic [15:0] eof_completed_frame_tick_clks,
	output logic        fifo_full_led,
	output logic        fifo_empty
);

	localparam FIFO_DEPTH = 1 << FIFO_ADDR_W;
	localparam FIFO_PTR_W = FIFO_ADDR_W + 1;
	localparam logic [2:0] DOT_2X  = 3'd0;
	localparam logic [2:0] DOT_25X = 3'd1;
	localparam logic [2:0] DOT_3X  = 3'd2;
	localparam logic [2:0] DOT_1X  = 3'd3;

	logic [2:0] dot_mode_q = DOT_2X;
	always_ff @(posedge clk_sys)
		dot_mode_q <= DOT_MODE;

	function [FIFO_PTR_W-1:0] b2g(input [FIFO_PTR_W-1:0] b);
		b2g = b ^ (b >> 1);
	endfunction

	function [FIFO_PTR_W-1:0] g2b(input [FIFO_PTR_W-1:0] g);
		logic [FIFO_PTR_W-1:0] b;
		begin
			b[FIFO_PTR_W-1] = g[FIFO_PTR_W-1];
			for (int i=FIFO_PTR_W-2; i>=0; i=i-1)
				b[i] = b[i+1] ^ g[i];
			g2b = b;
		end
	endfunction

	// The FIFO lets vector drawing continue while the framebuffer is busy.
	(* ramstyle = "M10K" *) logic [37:0] fifo_mem [0:FIFO_DEPTH-1];

	logic [FIFO_PTR_W-1:0] wr_ptr = 0;
	logic [FIFO_PTR_W-1:0] wr_ptr_g = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr_g = 0;

	logic [FIFO_PTR_W-1:0] wr_ptr_g_sync1 = 0;
	logic [FIFO_PTR_W-1:0] wr_ptr_g_sync2 = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr_g_sync1_12 = 0;
	logic [FIFO_PTR_W-1:0] rd_ptr_g_sync2_12 = 0;

	// Source-clock side
	logic [10:0] last_x = 0;
	logic [10:0] last_y = 0;
	logic        last_beam_on = 0;
	logic        last_frame_done = 0;

	wire push_eof = (FRAME_DONE && !last_frame_done);
	wire push_pix = (BEAM_ON && (X_VECTOR != last_x || Y_VECTOR != last_y || !last_beam_on));
	wire fifo_we  = push_eof || push_pix;

	// LOCAL MODIFICATION for the Sega G-80 X-Y core: the colour field is
	// widened from 4 to 6 bits so all three guns carry a 2-bit level.
	// Sega drives each gun from its own 2-bit resistor ladder, where Major
	// Havoc has 2 bits on red only. See Research/colour-census.md.
	wire [37:0] fifo_din = push_eof ? {
		1'b1, 5'd0, completed_frame_tick_clks, frame_tick_clks
	} : {
		1'b0,              // 37
		IS_DOT,            // 36
		COLOR,             // 35:30 = RRGGBB
		Y_VECTOR,          // 29:19
		X_VECTOR,          // 18:8
		Z_VECTOR           // 7:0
	};

	wire [FIFO_PTR_W-1:0] wr_ptr_next = wr_ptr + 1'b1;
	wire [FIFO_PTR_W-1:0] wr_ptr_g_next = b2g(wr_ptr_next);
	wire fifo_full_12 =
		(wr_ptr_g_next ==
		 {~rd_ptr_g_sync2_12[FIFO_PTR_W-1:FIFO_PTR_W-2],
		   rd_ptr_g_sync2_12[FIFO_PTR_W-3:0]});
	logic [1:0] rst_source_sync = 2'b11;
	always_ff @(posedge clk_source)
		rst_source_sync <= {rst_source_sync[0], reset};
	wire rst_source = rst_source_sync[1];

	// Synchronize the Gray-coded read pointer back to the write domain so a
	// prolonged DDR/cache stall cannot silently overwrite unread entries.
	always_ff @(posedge clk_source) begin
		if (rst_source) begin
			rd_ptr_g_sync1_12 <= 0;
			rd_ptr_g_sync2_12 <= 0;
		end else begin
			rd_ptr_g_sync1_12 <= rd_ptr_g;
			rd_ptr_g_sync2_12 <= rd_ptr_g_sync1_12;
		end
	end

	always_ff @(posedge clk_source) begin
		last_x <= X_VECTOR;
		last_y <= Y_VECTOR;
		last_beam_on <= BEAM_ON;
		last_frame_done <= FRAME_DONE;

		if (rst_source) begin
			wr_ptr <= 0;
			wr_ptr_g <= 0;
		end else if (fifo_we) begin
			if (!fifo_full_12) begin
				fifo_mem[wr_ptr[FIFO_ADDR_W-1:0]] <= fifo_din;
				wr_ptr <= wr_ptr_next;
				wr_ptr_g <= wr_ptr_g_next;
			end
		end
	end

	// Framebuffer-clock side
	always_ff @(posedge clk_sys) begin
		wr_ptr_g_sync1 <= wr_ptr_g;
		wr_ptr_g_sync2 <= wr_ptr_g_sync1;
	end
	assign fifo_empty = (rd_ptr_g == wr_ptr_g_sync2);

	// FIFO high-water LED, held for about 75 ms.
	wire [FIFO_PTR_W-1:0] wr_ptr_bin = g2b(wr_ptr_g_sync2);
	wire [FIFO_PTR_W-1:0] fifo_used = wr_ptr_bin - rd_ptr;
	wire fifo_full_flag = (fifo_used > FIFO_PTR_W'(128));

	logic [23:0] led_timer = 0;
	always_ff @(posedge clk_sys) begin
		if (fifo_full_flag) led_timer <= 24'd9349794;
		else if (led_timer != 0) led_timer <= led_timer - 1'b1;
	end
	assign fifo_full_led = (led_timer != 0);

	logic [1:0] rst_sys_sync = 2'b11;
	always_ff @(posedge clk_sys) rst_sys_sync <= {rst_sys_sync[0], reset};
	wire rst_sys = rst_sys_sync[1];

	// Flow: FIFO -> input register -> expansion stage -> tile cache.
	//
	// The input register holds one FIFO entry. The expansion stage emits the
	// source pixel, then any diagonal fill or enlarged-dot pixels.
	//   B_IDLE      - accept and emit a source pixel
	//   B_CHECK_SUB - choose and emit a diagonal fill pixel
	//   B_DOT_SUB   - emit enlarged-dot pixels

	// Input register
	logic [37:0] a_data;
	logic        a_valid = 0;
	wire         a_ready;

	wire a_fifo_read = !fifo_empty && (!a_valid || a_ready);

	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			a_valid <= 0;
			rd_ptr  <= 0;
			rd_ptr_g <= 0;
		end else begin
			if (a_ready && a_valid) a_valid <= 0;
			if (a_fifo_read) begin
				a_data   <= fifo_mem[rd_ptr[FIFO_ADDR_W-1:0]];
				rd_ptr   <= rd_ptr + 1'b1;
				rd_ptr_g <= b2g(rd_ptr + 1'b1);
				a_valid  <= 1;
			end
		end
	end

	wire [10:0] a_x      = a_data[18:8];
	wire [10:0] a_y      = a_data[29:19];
	wire [7:0]  a_z      = a_data[7:0];
	wire [5:0]  a_c      = a_data[35:30];
	wire        a_is_dot = a_data[36];
	wire        a_eof    = a_data[37];
	wire [2:0]  a_dot    = dot_mode_q;

	// Expansion state
	typedef enum logic [1:0] {
		B_IDLE,
		B_CHECK_SUB,
		B_DOT_SUB
	} b_state_t;

	b_state_t b_state = B_IDLE;

	logic [10:0] s2_out_x;
	logic [10:0] s2_out_y;
	logic [7:0]  s2_out_z;
	logic [5:0]  s2_out_c;
	logic        s2_out_valid = 0;
	logic [15:0] s2_eof_frame_tick_clks = 0;
	logic [15:0] s2_eof_completed_frame_tick_clks = 0;

	wire b_output_free = pixel_ready || !s2_out_valid;
	assign pixel_valid = s2_out_valid;

	// Two possible pixels for filling a diagonal step.
	logic [10:0] pending_sub_x;
	logic [10:0] pending_sub_y;
	logic [7:0]  pending_sub_z;
	logic [5:0]  pending_sub_c;
	logic [10:0] pending_alt_x;
	logic [10:0] pending_alt_y;
	logic        pending_is_xdom;

	// Keep the previous two source positions.
	logic [10:0] hist_x [2];
	logic [10:0] hist_y [2];
	logic [1:0]  hist_count = 0;

	logic [10:0] read_last_x = 0;
	logic [10:0] read_last_y = 0;

	// Enlarged-dot state
	logic [2:0]  dot_idx;
	logic [2:0]  dot_last_idx;
	logic [2:0]  dot_mode;
	logic [7:0]  dot_base_z;
	logic [5:0]  dot_base_c;
	logic [10:0] dot_x, dot_y;
	logic [11:0] dot_candidate_x;
	logic [11:0] dot_candidate_y;
	logic        dot_candidate_valid;

	always_comb begin
		dot_candidate_x = {1'b0, dot_x};
		dot_candidate_y = {1'b0, dot_y};

		case (dot_mode)
		DOT_2X: begin
			case (dot_idx)
				3'd0: dot_candidate_x = {1'b0, dot_x} + 12'd1;
				3'd1: dot_candidate_y = {1'b0, dot_y} + 12'd1;
				default: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
			endcase
		end

		DOT_25X: begin
			case (dot_idx)
				3'd0: dot_candidate_x = {1'b0, dot_x} + 12'd1;
				3'd1: dot_candidate_x = {1'b0, dot_x} + 12'd2;
				3'd2: dot_candidate_y = {1'b0, dot_y} + 12'd1;
				3'd3: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
				default: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd2;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
			endcase
		end

		DOT_3X: begin
			case (dot_idx)
				3'd0: begin
					dot_candidate_x = {1'b0, dot_x} - 12'd1;
					dot_candidate_y = {1'b0, dot_y} - 12'd1;
				end
				3'd1: dot_candidate_y = {1'b0, dot_y} - 12'd1;
				3'd2: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} - 12'd1;
				end
				3'd3: dot_candidate_x = {1'b0, dot_x} - 12'd1;
				3'd4: dot_candidate_x = {1'b0, dot_x} + 12'd1;
				3'd5: begin
					dot_candidate_x = {1'b0, dot_x} - 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
				3'd6: dot_candidate_y = {1'b0, dot_y} + 12'd1;
				default: begin
					dot_candidate_x = {1'b0, dot_x} + 12'd1;
					dot_candidate_y = {1'b0, dot_y} + 12'd1;
				end
			endcase
		end

		default: begin
			dot_candidate_x = {1'b0, dot_x};
			dot_candidate_y = {1'b0, dot_y};
		end
		endcase
	end

	assign dot_candidate_valid = (dot_candidate_x < FB_WIDTH) &&
	                             (dot_candidate_y < FB_HEIGHT);

	// Classify the current step.
	wire [10:0] step_dx = (a_x > read_last_x) ? (a_x - read_last_x)
	                                           : (read_last_x - a_x);
	wire [10:0] step_dy = (a_y > read_last_y) ? (a_y - read_last_y)
	                                           : (read_last_y - a_y);
	wire step_is_diag = (step_dx == 11'd1 && step_dy == 11'd1);
	wire primary_is_dot = a_is_dot && (a_dot < DOT_1X);
	wire is_neighbor  = (step_dx <= 11'd1) && (step_dy <= 11'd1);

	assign a_ready = a_valid && b_output_free && (b_state == B_IDLE);

	always_ff @(posedge clk_sys) begin
		if (rst_sys) begin
			s2_out_valid <= 0;
			eof_token    <= 0;
			s2_eof_frame_tick_clks <= 16'd0;
			s2_eof_completed_frame_tick_clks <= 16'd0;
			b_state      <= B_IDLE;
			hist_count   <= 0;
		end else begin
			if (pixel_ready) begin
				s2_out_valid <= 0;
				eof_token    <= 0;
			end

			case (b_state)
			B_IDLE: begin
				if (a_valid && b_output_free) begin
					if (a_eof) begin
						eof_token    <= 1;
						s2_out_valid <= 1;
						s2_eof_frame_tick_clks <= a_data[15:0];
						s2_eof_completed_frame_tick_clks <= a_data[31:16];
					end else begin
						s2_out_x     <= a_x;
						s2_out_y     <= a_y;
						s2_out_z     <= a_z;
						s2_out_c     <= a_c;
						s2_out_valid <= 1;

						hist_x[1] <= hist_x[0]; hist_y[1] <= hist_y[0];
						hist_x[0] <= a_x;       hist_y[0] <= a_y;
						hist_count <= is_neighbor ? ((hist_count < 2'd2) ? hist_count + 2'd1 : 2'd2) : 2'd1;

						if (primary_is_dot) begin
							b_state      <= B_DOT_SUB;
							dot_mode     <= a_dot;
							dot_idx      <= 3'd0;
							dot_last_idx <= (a_dot == DOT_2X)  ? 3'd2 :
							                (a_dot == DOT_25X) ? 3'd4 : 3'd7;
							dot_base_z   <= a_z;
							dot_base_c   <= a_c;
							dot_x        <= a_x;
							dot_y        <= a_y;
						end else if (step_is_diag) begin
							// Keep both fill choices until the next source pixel.
							if (hist_count >= 2'd2 && hist_x[0] == hist_x[1] && hist_y[0] != hist_y[1]) begin
								// After a vertical step, keep the fill on the new x coordinate.
								pending_sub_x   <= a_x;
								pending_sub_y   <= read_last_y;
								pending_alt_x   <= read_last_x;
								pending_alt_y   <= a_y;
								pending_is_xdom <= 1;
							end else begin
								// Otherwise keep the fill on the new y coordinate.
								pending_sub_x   <= read_last_x;
								pending_sub_y   <= a_y;
								pending_alt_x   <= a_x;
								pending_alt_y   <= read_last_y;
								pending_is_xdom <= 0;
							end
							pending_sub_z <= a_z;
							pending_sub_c <= a_c;
							b_state       <= B_CHECK_SUB;
						end

						read_last_x <= a_x;
						read_last_y <= a_y;
					end
				end
			end

			// If the preferred fill aligns with the next source pixel, use the
			// other corner.
			B_CHECK_SUB: begin
				if (a_valid && b_output_free) begin
					if (!a_eof && (pending_is_xdom ? (a_x == pending_sub_x) : (a_y == pending_sub_y))) begin
						s2_out_x <= pending_alt_x;
						s2_out_y <= pending_alt_y;
					end else begin
						s2_out_x <= pending_sub_x;
						s2_out_y <= pending_sub_y;
					end
					s2_out_z     <= pending_sub_z;
					s2_out_c     <= pending_sub_c;
					s2_out_valid <= 1;
					b_state      <= B_IDLE;
				end
			end

			B_DOT_SUB: begin
				if (b_output_free) begin
					if (dot_candidate_valid) begin
						s2_out_x     <= dot_candidate_x[10:0];
						s2_out_y     <= dot_candidate_y[10:0];
						s2_out_z     <= dot_base_z;
						s2_out_c     <= dot_base_c;
						s2_out_valid <= 1;
					end

					if (dot_idx == dot_last_idx) begin
						b_state <= B_IDLE;
					end else begin
						dot_idx <= dot_idx + 3'd1;
					end
				end
			end
			endcase
		end
	end

	assign pixel_tile_id = {s2_out_y[10:3], s2_out_x[10:3]};
	assign pixel_offset  = {s2_out_y[2:0],  s2_out_x[2:0]};
	// LOCAL MOD: { rgb[5:0], draw_idx[2:0], z[7:1] } — still exactly 16 bits.
	// Sega's beam intensity is binary, so the low Z bit is the cheapest thing
	// to give up; vfb_readout replicates it back on read.
	assign pixel_data    = eof_token ? s2_eof_frame_tick_clks
	                                 : {s2_out_c, draw_idx, s2_out_z[7:1]};
	assign eof_completed_frame_tick_clks = s2_eof_completed_frame_tick_clks;

endmodule
