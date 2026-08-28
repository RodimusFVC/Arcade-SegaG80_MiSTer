// ============================================================================
// RGB24 line-local RLE16 encoder.
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
// selected green/blue channels decode to M. The encoder uses this form only
// when decoding it reproduces the input RGB exactly.
//
// High nibble 0000 identifies these special forms:
//   0000 00 NNNNNNNNNN: black, count 1..1024
//   0000 01 NNNNNNNNNN: repeat previous RGB, count 1..1024
//   0000 10 RRRRRRRR NN: literal word 0, count 1..4
//                        word 1 is GGGGGGGG BBBBBBBB
//   0000 11 MMM SSSSSSS: one 232-ceiling spill pixel
//                        MMM selects channels at 232; others use S (0..64)
//
// The previous decoded RGB resets to black at each line boundary, so every
// line is independent. Each output entry contains one compact word or both
// literal words. token_eol marks the final real word of the line.
// ============================================================================

module vfb_rle_encoder (
	input  logic        clk_sys,
	input  logic        reset,

	input  logic        pixel_valid,
	input  logic [23:0] rgb_in,
	input  logic        line_end,

	output logic        token_valid,
	input  logic        token_ready,
	output logic [31:0] token_data,
	output logic [1:0]  token_words,
	output logic        token_eol,

	output logic        overflow
);

	localparam integer RUN_FIFO_DEPTH = 16;
	localparam integer RUN_FIFO_AW = 4;
	localparam integer RUN_DESCRIPTOR_WIDTH = 2 + 24;
	localparam integer RUN_FIFO_WIDTH = 1 + 13 + RUN_DESCRIPTOR_WIDTH;
	localparam logic [7:0] SPILL_MAIN_CEIL = 8'd232;

	typedef enum logic [1:0] {
		RUN_BLACK,
		RUN_COMPACT,
		RUN_SPILL,
		RUN_LITERAL
	} run_kind_t;

	typedef enum logic [2:0] {
		EMIT_IDLE,
		EMIT_BLACK,
		EMIT_COMPACT,
		EMIT_SPILL,
		EMIT_LITERAL,
		EMIT_REPEAT
	} emit_state_t;

	logic        run_valid;
	logic [23:0] run_rgb;
	logic [12:0] run_count;
	logic        input_pixel_valid;
	logic [23:0] input_rgb;
	logic        input_line_end;

	// Registers separate run detection from a full output FIFO.
	(* ramstyle = "logic" *) logic [RUN_FIFO_WIDTH-1:0] run_fifo_entry [0:RUN_FIFO_DEPTH-1];
	logic [RUN_FIFO_AW:0] run_fifo_used;
	logic [RUN_FIFO_AW-1:0] run_fifo_rd_ptr;
	logic [RUN_FIFO_AW-1:0] run_fifo_wr_ptr;
	logic                         pending_valid;
	logic [RUN_FIFO_WIDTH-1:0]    pending_entry;
	logic                         prefetch_valid;
	logic [RUN_FIFO_WIDTH-1:0]    prefetch_entry;

	emit_state_t emit_state;
	logic [23:0] emit_payload;
	logic [12:0] emit_count;
	logic [12:0] emit_repeat_remaining;
	logic        emit_eol;
	logic [1:0]  emit_literal_count_m1;

	function automatic logic is_black(input logic [23:0] rgb);
		is_black = (rgb == 24'd0);
	endfunction

	function automatic logic [9:0] fine_level_for(
		input logic [7:0] level
	);
		logic [12:0] scaled;
		begin
			scaled =
				({5'd0, level} << 3) +
				({5'd0, level} << 2) +
				{5'd0, level} + 13'd32;
			fine_level_for = {2'd0, scaled[12:6]};
		end
	endfunction

	// Return {valid, color[3:0], level[7:0]}. Every candidate is decoded again
	// and accepted only when it reproduces the input RGB exactly.
	function automatic logic [12:0] compact_encoding(
		input logic [23:0] rgb
	);
		logic [7:0] r;
		logic [7:0] g;
		logic [7:0] b;
		logic [7:0] level;
		logic [7:0] main_ref;
		logic [9:0] fine_level;
		logic [9:0] main_level;
		logic [8:0] summed_level;
		logic [3:0] color;
		logic       direct_valid;
		logic       mismatch;
		begin
			r = rgb[23:16];
			g = rgb[15:8];
			b = rgb[7:0];
			compact_encoding = 13'd0;
			direct_valid = 1'b0;
			mismatch = 1'b0;
			level = 8'd0;

			if (r != 0) begin
				level = r;
				direct_valid = 1'b1;
			end
			if (g != 0) begin
				if (!direct_valid) begin
					level = g;
					direct_valid = 1'b1;
				end else if (g != level)
					mismatch = 1'b1;
			end
			if (b != 0) begin
				if (!direct_valid) begin
					level = b;
					direct_valid = 1'b1;
				end else if (b != level)
					mismatch = 1'b1;
			end

			if (direct_valid && !mismatch) begin
				color = {
					(r != 8'd0),
					1'b0,
					(g != 8'd0),
					(b != 8'd0)
				};
				compact_encoding = {1'b1, color, level};
			end else begin
				// Strong+fine red: red carries total L directly.
				fine_level = fine_level_for(r);
				main_level = {2'd0, r} - fine_level;
				if ((r != 8'd0) &&
				    ((g == 8'd0) || ({2'd0, g} == main_level)) &&
				    ((b == 8'd0) || ({2'd0, b} == main_level))) begin
					color = {
						1'b1,
						1'b1,
						(g != 8'd0),
						(b != 8'd0)
					};
					compact_encoding = {1'b1, color, r};
				end else begin
					// Fine-only red: a selected main channel makes
					// L exactly recoverable as fine+main.
					main_ref = (g != 8'd0) ? g : b;
					summed_level = {1'b0, r} +
					               {1'b0, main_ref};
					fine_level = fine_level_for(
						summed_level[7:0]);
					main_level =
						{1'b0, summed_level} - fine_level;
					if ((main_ref != 8'd0) &&
					    !summed_level[8] &&
					    ({2'd0, r} == fine_level) &&
					    ({2'd0, main_ref} == main_level) &&
					    ((g == 8'd0) || (g == main_ref)) &&
					    ((b == 8'd0) || (b == main_ref))) begin
						color = {
							1'b0,
							1'b1,
							(g != 8'd0),
							(b != 8'd0)
						};
						compact_encoding = {
							1'b1,
							color,
							summed_level[7:0]
						};
					end
				end
			end
		end
	endfunction

	function automatic [2:0] spill_main_mask(input logic [23:0] rgb);
		spill_main_mask = {
			(rgb[23:16] == SPILL_MAIN_CEIL),
			(rgb[15:8]  == SPILL_MAIN_CEIL),
			(rgb[7:0]   == SPILL_MAIN_CEIL)
		};
	endfunction

	function automatic [6:0] spill_intensity(input logic [23:0] rgb);
		begin
			if (rgb[23:16] != SPILL_MAIN_CEIL)
				spill_intensity = rgb[22:16];
			else if (rgb[15:8] != SPILL_MAIN_CEIL)
				spill_intensity = rgb[14:8];
			else
				spill_intensity = rgb[6:0];
		end
	endfunction

	function automatic logic is_main_ceiling_spill(input logic [23:0] rgb);
		logic [2:0] mask;
		logic [7:0] spill;
		logic       valid;
		logic       mismatch;
		begin
			mask = spill_main_mask(rgb);
			valid = 1'b0;
			mismatch = 1'b0;
			spill = 8'd0;

			if (mask != 3'b000 && mask != 3'b111) begin
				if (rgb[23:16] != SPILL_MAIN_CEIL) begin
					spill = rgb[23:16];
					valid = 1'b1;
				end
				if (rgb[15:8] != SPILL_MAIN_CEIL) begin
					if (!valid) begin
						spill = rgb[15:8];
						valid = 1'b1;
					end else if (rgb[15:8] != spill)
						mismatch = 1'b1;
				end
				if (rgb[7:0] != SPILL_MAIN_CEIL) begin
					if (!valid) begin
						spill = rgb[7:0];
						valid = 1'b1;
					end else if (rgb[7:0] != spill)
						mismatch = 1'b1;
				end
			end

			is_main_ceiling_spill =
				(mask != 3'b000) && (mask != 3'b111) &&
				valid && !mismatch && (spill <= 8'd64);
		end
	endfunction

	// Classify each completed run before storing it. Output then uses only
	// registered type and color values.
	function automatic logic [RUN_DESCRIPTOR_WIDTH-1:0] classify_run(
		input logic [23:0] rgb
	);
		logic [12:0] compact;
		begin
			compact = compact_encoding(rgb);
			if (is_black(rgb))
				classify_run = {RUN_BLACK, 24'd0};
			else if (compact[12])
				classify_run = {
					RUN_COMPACT,
					12'd0,
					compact[11:0]
				};
			else if (is_main_ceiling_spill(rgb))
				classify_run = {
					RUN_SPILL,
					14'd0,
					spill_main_mask(rgb),
					spill_intensity(rgb)
				};
			else
				classify_run = {RUN_LITERAL, rgb};
		end
	endfunction

	function automatic [9:0] count_m1_10(input logic [12:0] count);
		count_m1_10 = count[9:0] - 10'd1;
	endfunction

	function automatic [3:0] count_m1_4(input logic [4:0] count);
		count_m1_4 = count[3:0] - 4'd1;
	endfunction

	function automatic [1:0] count_m1_2(input logic [2:0] count);
		count_m1_2 = count[1:0] - 2'd1;
	endfunction

	wire emit_can_write = !token_valid || token_ready;
	wire emit_busy = (emit_state != EMIT_IDLE);
	wire emit_finishes_now =
		emit_can_write &&
		((emit_state == EMIT_BLACK && emit_repeat_remaining <= 13'd1024) ||
		 (emit_state == EMIT_COMPACT &&
		  emit_repeat_remaining == 13'd0) ||
		 (emit_state == EMIT_SPILL &&
		  emit_repeat_remaining == 13'd0) ||
		 (emit_state == EMIT_LITERAL &&
		  emit_repeat_remaining == 13'd0) ||
		 (emit_state == EMIT_REPEAT &&
		  emit_repeat_remaining <= 13'd1024));
	wire emit_available_for_new = !emit_busy || emit_finishes_now;
	wire [4:0] compact_first_count =
		(emit_count > 13'd16) ? 5'd1 : {1'b0, emit_count[3:0]};

	wire run_fifo_empty = (run_fifo_used == 0);
	wire run_fifo_full = (run_fifo_used == RUN_FIFO_DEPTH);
	wire run_fifo_pop = !prefetch_valid && !run_fifo_empty;
	wire [RUN_FIFO_WIDTH-1:0] run_fifo_head =
		run_fifo_entry[run_fifo_rd_ptr];
	wire start_prefetch = emit_available_for_new && prefetch_valid;
	wire start_fifo_head =
		emit_available_for_new && !prefetch_valid && run_fifo_pop;
	wire run_fifo_can_push = !run_fifo_full || run_fifo_pop;
	wire run_fifo_push = pending_valid && run_fifo_can_push;
	wire pixel_extends_run =
		input_pixel_valid && run_valid && input_rgb == run_rgb &&
		run_count < 13'd4096;
	wire pixel_finishes_run =
		input_pixel_valid && run_valid && !pixel_extends_run;
	wire line_finishes_run = input_line_end && run_valid;
	wire [RUN_FIFO_WIDTH-1:0] completed_run_entry = {
		line_finishes_run,
		run_count,
		classify_run(run_rgb)
	};
	wire run_close_request =
		pixel_finishes_run || line_finishes_run;
	wire pending_ready = !pending_valid || run_fifo_can_push;
	wire run_close_accept = run_close_request && pending_ready;

	wire start_emit = start_prefetch || start_fifo_head;
	wire [RUN_FIFO_WIDTH-1:0] start_entry =
		prefetch_valid ? prefetch_entry : run_fifo_head;
	wire        start_eol = start_entry[39];
	wire [12:0] start_count = start_entry[38:26];
	wire [1:0]  start_kind = start_entry[25:24];
	wire [23:0] start_payload = start_entry[23:0];
	wire [2:0] start_literal_count =
		(start_count > 13'd4) ? 3'd1 : {1'b0, start_count[1:0]};

	emit_state_t start_state;
	logic [12:0] start_repeat_remaining;
	always_comb begin
		start_state = EMIT_LITERAL;
		start_repeat_remaining =
			(start_count > 13'd4) ? start_count - 13'd1 : 13'd0;
		case (start_kind)
			RUN_BLACK: begin
				start_state = EMIT_BLACK;
				start_repeat_remaining = start_count;
			end
			RUN_COMPACT: begin
				start_state = EMIT_COMPACT;
				start_repeat_remaining =
					(start_count > 13'd16) ?
						start_count - 13'd1 : 13'd0;
			end
			RUN_SPILL: begin
				start_state = EMIT_SPILL;
				start_repeat_remaining = start_count - 13'd1;
			end
			default: begin
				start_state = EMIT_LITERAL;
			end
		endcase
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			token_valid <= 1'b0;
			token_data <= 32'd0;
			token_words <= 2'd0;
			token_eol <= 1'b0;
			run_valid <= 1'b0;
			run_rgb <= 24'd0;
			run_count <= 13'd0;
			input_pixel_valid <= 1'b0;
			input_rgb <= 24'd0;
			input_line_end <= 1'b0;
			run_fifo_used <= '0;
			run_fifo_rd_ptr <= '0;
			run_fifo_wr_ptr <= '0;
			pending_valid <= 1'b0;
			pending_entry <= '0;
			prefetch_valid <= 1'b0;
			prefetch_entry <= '0;
			emit_state <= EMIT_IDLE;
			emit_payload <= 24'd0;
			emit_count <= 13'd0;
			emit_repeat_remaining <= 13'd0;
			emit_eol <= 1'b0;
			emit_literal_count_m1 <= 2'd0;
			overflow <= 1'b0;
		end else begin
			input_pixel_valid <= pixel_valid;
			input_rgb <= rgb_in;
			input_line_end <= line_end;

			if (token_valid && token_ready)
				token_valid <= 1'b0;

			if (emit_busy && emit_can_write) begin
				token_valid <= 1'b1;
				case (emit_state)
					EMIT_BLACK: begin
						token_words <= 2'd1;
						if (emit_repeat_remaining > 13'd1024) begin
							token_data <= {16'd0, 4'h0, 2'b00, 10'h3ff};
							token_eol <= 1'b0;
							emit_repeat_remaining <=
								emit_repeat_remaining - 13'd1024;
						end else begin
							token_data <= {16'd0,
								4'h0,
								2'b00,
								count_m1_10(emit_repeat_remaining)
							};
							token_eol <= emit_eol;
							emit_state <= EMIT_IDLE;
						end
					end

					EMIT_COMPACT: begin
						token_words <= 2'd1;
						token_data <= {16'd0,
							emit_payload[11:8],
							emit_payload[7:0],
							count_m1_4(compact_first_count)
						};
						token_eol <=
							(emit_repeat_remaining == 13'd0) &&
							emit_eol;
						if (emit_repeat_remaining != 13'd0)
							emit_state <= EMIT_REPEAT;
						else
							emit_state <= EMIT_IDLE;
					end

					EMIT_SPILL: begin
						token_words <= 2'd1;
						token_data <= {16'd0,
							4'h0,
							2'b11,
							emit_payload[9:7],
							emit_payload[6:0]
						};
						token_eol <=
							(emit_repeat_remaining == 13'd0) &&
							emit_eol;
						if (emit_repeat_remaining != 13'd0)
							emit_state <= EMIT_REPEAT;
						else
							emit_state <= EMIT_IDLE;
					end

					EMIT_LITERAL: begin
						token_data <= {
							emit_payload[15:0],
							4'h0, 2'b10,
							emit_payload[23:16],
							emit_literal_count_m1
						};
						token_words <= 2'd2;
						token_eol <=
							(emit_repeat_remaining == 13'd0) &&
							emit_eol;
						if (emit_repeat_remaining != 13'd0)
							emit_state <= EMIT_REPEAT;
						else
							emit_state <= EMIT_IDLE;
					end

					EMIT_REPEAT: begin
						token_words <= 2'd1;
						if (emit_repeat_remaining > 13'd1024) begin
							token_data <= {16'd0, 4'h0, 2'b01, 10'h3ff};
							token_eol <= 1'b0;
							emit_repeat_remaining <=
								emit_repeat_remaining - 13'd1024;
						end else begin
							token_data <= {16'd0,
								4'h0,
								2'b01,
								count_m1_10(emit_repeat_remaining)
							};
							token_eol <= emit_eol;
							emit_state <= EMIT_IDLE;
						end
					end

					default: begin
						token_valid <= 1'b0;
						token_data <= 32'd0;
						token_words <= 2'd0;
						token_eol <= 1'b0;
						emit_state <= EMIT_IDLE;
					end
				endcase
			end

			if (start_emit) begin
				emit_payload <= start_payload;
				emit_count <= start_count;
				emit_eol <= start_eol;
				emit_literal_count_m1 <=
					count_m1_2(start_literal_count);
				emit_state <= start_state;
				emit_repeat_remaining <= start_repeat_remaining;
			end

			if (start_prefetch)
				prefetch_valid <= 1'b0;

			if (run_fifo_pop) begin
				if (!start_fifo_head) begin
					prefetch_entry <= run_fifo_head;
					prefetch_valid <= 1'b1;
				end
				run_fifo_rd_ptr <= run_fifo_rd_ptr + 1'b1;
			end
			if (run_fifo_push) begin
				run_fifo_entry[run_fifo_wr_ptr] <= pending_entry;
				run_fifo_wr_ptr <= run_fifo_wr_ptr + 1'b1;
			end

			case ({run_fifo_push, run_fifo_pop})
				2'b10: run_fifo_used <= run_fifo_used + 1'b1;
				2'b01: run_fifo_used <= run_fifo_used - 1'b1;
				default: run_fifo_used <= run_fifo_used;
			endcase

			if (run_fifo_push)
				pending_valid <= 1'b0;
			if (run_close_request) begin
				if (pending_ready) begin
					pending_entry <= completed_run_entry;
					pending_valid <= 1'b1;
				end else begin
					overflow <= 1'b1;
				end
			end

			if (line_finishes_run) begin
				if (run_close_accept) begin
					run_valid <= 1'b0;
					run_count <= 13'd0;
				end
			end

			if (input_pixel_valid) begin
				if (!run_valid) begin
					run_valid <= 1'b1;
					run_rgb <= input_rgb;
					run_count <= 13'd1;
				end else if (pixel_extends_run) begin
					run_count <= run_count + 13'd1;
				end else begin
					run_rgb <= input_rgb;
					run_count <= 13'd1;
					run_valid <= 1'b1;
				end
			end
		end
	end

endmodule
