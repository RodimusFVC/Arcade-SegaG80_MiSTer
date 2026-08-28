// ============================================================================
// Decoder for the line-local RLE16 word format.
// written 2026 by Videodr0me
//
// A nonzero high nibble is a compact color run:
//   CCCC LLLLLLLL NNNN
//   CCCC = {strong red, fine red, green, blue}
//   L     = channel level
//   N     = count-1, for counts 1..16
//
// With fine red clear, selected channels decode directly to L. With fine red
// set, F=round(13*L/64), M=L-F, red is F or L according to the red bits, and
// selected green/blue channels decode to M.
//
// High nibble 0000 identifies these special forms:
//   0000 00 NNNNNNNNNN: black, count 1..1024
//   0000 01 NNNNNNNNNN: repeat previous RGB, count 1..1024
//   0000 10 RRRRRRRR NN: literal word 0, count 1..4
//                        word 1 is GGGGGGGG BBBBBBBB
//   0000 11 MMM SSSSSSS: one 232-ceiling spill pixel
//                        MMM selects channels at 232; others use S (0..64)
//
// Complete one- or two-word codes enter a small run FIFO.
// ============================================================================

module vfb_rle_decoder (
	input  logic        clk_sys,
	input  logic        reset,

	input  logic        token_valid,
	output logic        token_ready,
	input  logic [31:0] token_data,
	input  logic        token_eol,

	input  logic        advance,
	output logic [23:0] rgb_out,
	output logic        pixel_valid,
	output logic        line_done,
	output logic        underflow
);

	localparam integer RUN_FIFO_DEPTH = 16;
	localparam integer RUN_FIFO_AW = 4;
	localparam logic [7:0] SPILL_MAIN_CEIL = 8'd232;

	logic [23:0] previous_rgb;

	logic [23:0] fifo_rgb [0:RUN_FIFO_DEPTH-1];
	logic [12:0] fifo_count [0:RUN_FIFO_DEPTH-1];
	logic fifo_eol [0:RUN_FIFO_DEPTH-1];
	logic [RUN_FIFO_AW-1:0] fifo_wr_ptr;
	logic [RUN_FIFO_AW-1:0] fifo_rd_ptr;
	logic [RUN_FIFO_AW:0] fifo_used;

	logic [23:0] run_rgb;
	logic [12:0] run_remaining;
	logic run_eol;

	function automatic [23:0] compact_rgb(
		input logic [3:0] color,
		input logic [7:0] level
	);
		logic [12:0] fine_scaled;
		logic [7:0] fine_level;
		logic [7:0] main_level;
		begin
			fine_scaled =
				({5'd0, level} << 3) +
				({5'd0, level} << 2) +
				{5'd0, level} + 13'd32;
			fine_level = fine_scaled[12:6];
			main_level = level - fine_level;

			if (color[2]) begin
				compact_rgb = {
					color[3] ? level : fine_level,
					color[1] ? main_level : 8'd0,
					color[0] ? main_level : 8'd0
				};
			end else begin
				compact_rgb = {
					color[3] ? level : 8'd0,
					color[1] ? level : 8'd0,
					color[0] ? level : 8'd0
				};
			end
		end
	endfunction

	function automatic [23:0] spill_rgb(
		input logic [2:0] mask,
		input logic [6:0] spill
	);
		begin
			spill_rgb = {
				mask[2] ? SPILL_MAIN_CEIL : {1'b0, spill},
				mask[1] ? SPILL_MAIN_CEIL : {1'b0, spill},
				mask[0] ? SPILL_MAIN_CEIL : {1'b0, spill}
			};
		end
	endfunction

	function automatic [12:0] count_short(input logic [3:0] count_m1);
		count_short = {9'd0, count_m1} + 13'd1;
	endfunction

	function automatic [12:0] count_literal(input logic [1:0] count_m1);
		count_literal = {11'd0, count_m1} + 13'd1;
	endfunction

	function automatic [12:0] count_long(input logic [9:0] count_m1);
		count_long = {3'd0, count_m1} + 13'd1;
	endfunction

	wire fifo_full = (fifo_used == RUN_FIFO_DEPTH);
	wire fifo_empty = (fifo_used == 0);
	wire consume_current = advance && (run_remaining != 0);
	wire consume_fifo = advance && (run_remaining == 0) && !fifo_empty;
	wire fifo_pop = consume_fifo;
	logic fifo_push;
	logic [23:0] fifo_push_rgb;
	logic [12:0] fifo_push_count;
	logic fifo_push_eol;

	// When this FIFO is full, leave the source word in place until one run
	// finishes. Input resumes on the following clock.
	assign token_ready = !fifo_full;

	always_comb begin
		fifo_push = 1'b0;
		fifo_push_rgb = 24'd0;
		fifo_push_count = 13'd0;
		fifo_push_eol = 1'b0;

		if (token_valid && token_ready) begin
			if (token_data[15:12] != 4'h0) begin
				fifo_push = 1'b1;
				fifo_push_rgb =
					compact_rgb(token_data[15:12],
					            token_data[11:4]);
				fifo_push_count =
					count_short(token_data[3:0]);
				fifo_push_eol = token_eol;
			end else begin
				case (token_data[11:10])
					2'b00: begin
						fifo_push = 1'b1;
						fifo_push_rgb = 24'd0;
						fifo_push_count =
							count_long(token_data[9:0]);
						fifo_push_eol = token_eol;
					end

					2'b01: begin
						fifo_push = 1'b1;
						fifo_push_rgb = previous_rgb;
						fifo_push_count =
							count_long(token_data[9:0]);
						fifo_push_eol = token_eol;
					end

					2'b10: begin
						fifo_push = 1'b1;
						fifo_push_rgb = {
							token_data[9:2],
							token_data[31:24],
							token_data[23:16]
						};
						fifo_push_count =
							count_literal(token_data[1:0]);
						fifo_push_eol = token_eol;
					end

					2'b11: begin
						fifo_push = 1'b1;
						fifo_push_rgb =
							spill_rgb(token_data[9:7],
							          token_data[6:0]);
						fifo_push_count = 13'd1;
						fifo_push_eol = token_eol;
					end
				endcase
			end
		end
	end

	always_comb begin
		if (run_remaining != 0)
			rgb_out = run_rgb;
		else if (!fifo_empty)
			rgb_out = fifo_rgb[fifo_rd_ptr];
		else
			rgb_out = 24'd0;
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			previous_rgb <= 24'd0;
			fifo_wr_ptr <= '0;
			fifo_rd_ptr <= '0;
			fifo_used <= '0;
			run_rgb <= 24'd0;
			run_remaining <= 13'd0;
			run_eol <= 1'b0;
			pixel_valid <= 1'b0;
			line_done <= 1'b0;
			underflow <= 1'b0;
		end else begin
			pixel_valid <= 1'b0;
			line_done <= 1'b0;

			if (token_valid && token_ready) begin
				if (fifo_push) begin
					fifo_rgb[fifo_wr_ptr] <= fifo_push_rgb;
					fifo_count[fifo_wr_ptr] <= fifo_push_count;
					fifo_eol[fifo_wr_ptr] <= fifo_push_eol;
					fifo_wr_ptr <= fifo_wr_ptr + 1'b1;
					if (fifo_push_eol)
						previous_rgb <= 24'd0;
					else
						previous_rgb <= fifo_push_rgb;
				end
			end

			if (consume_current) begin
				pixel_valid <= 1'b1;
				if (run_remaining == 13'd1) begin
					if (run_eol)
						line_done <= 1'b1;
					run_remaining <= 13'd0;
				end else begin
					run_remaining <= run_remaining - 13'd1;
				end
			end else if (consume_fifo) begin
				pixel_valid <= 1'b1;
				run_rgb <= fifo_rgb[fifo_rd_ptr];
				run_eol <= fifo_eol[fifo_rd_ptr];
				if (fifo_count[fifo_rd_ptr] == 13'd1) begin
					run_remaining <= 13'd0;
					if (fifo_eol[fifo_rd_ptr])
						line_done <= 1'b1;
				end else begin
					run_remaining <= fifo_count[fifo_rd_ptr] - 13'd1;
				end
				fifo_rd_ptr <= fifo_rd_ptr + 1'b1;
			end else if (advance) begin
				underflow <= 1'b1;
			end

			case ({fifo_push, fifo_pop})
				2'b10: fifo_used <= fifo_used + 1'b1;
				2'b01: fifo_used <= fifo_used - 1'b1;
				default: fifo_used <= fifo_used;
			endcase
		end
	end

endmodule
