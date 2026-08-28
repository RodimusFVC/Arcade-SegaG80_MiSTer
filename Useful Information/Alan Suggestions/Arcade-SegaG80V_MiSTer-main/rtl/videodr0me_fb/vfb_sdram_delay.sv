// ============================================================================
// RLE-compressed scanline delay in the MiSTer SDRAM.
// written 2026 by Videodr0me
//
// Active RGB is encoded into independent 8 KiB line slots. Readout follows the
// current horizontal timing and uses sync and blanking from the matching line.
// ============================================================================

module vfb_sdram_delay #(
	parameter integer SDRAM_MHZ  = 125,
	parameter integer DELAY_LINES = 64,
	parameter integer SLOT_COUNT = 128,
	parameter integer SLOT_BYTES = 8192,
	parameter integer FIFO_DEPTH = 256,
	parameter integer READ_FIFO_DEPTH = 512,
	parameter integer SLOT_W = $clog2(SLOT_COUNT),
	parameter integer FIFO_AW = $clog2(FIFO_DEPTH),
	parameter integer READ_FIFO_AW = $clog2(READ_FIFO_DEPTH)
) (
	input  logic        clk_sys,
	input  logic        reset,
	input  logic        ce_pix,

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
	output logic        VGA_VBLANK_OUT,

	input  logic [15:0] sdram_data_in,
	output logic [15:0] sdram_data_out,
	output logic        sdram_data_oe,
	output logic        sdram_cke,
	output logic        sdram_cs,
	output logic        sdram_ras,
	output logic        sdram_cas,
	output logic        sdram_we,
	output logic [1:0]  sdram_dqm,
	output logic [12:0] sdram_addr,
	output logic [1:0]  sdram_ba,

	output logic        overflow,
	output logic        underflow,
	output logic        init_done
);

	localparam integer MAX_WORDS = SLOT_BYTES / 2;
	localparam integer MAX_PAIRS = SLOT_BYTES / 4;
	localparam integer WORD_W = $clog2(MAX_WORDS);
	localparam integer PAIR_W = $clog2(MAX_PAIRS);
	localparam integer WRITE_FIFO_W = 1 + SLOT_W + PAIR_W + 32;
	// READ_FIFO_DEPTH counts 16-bit words. Each FIFO entry stores one 32-bit
	// SDRAM response.
	localparam integer READ_PAIR_FIFO_DEPTH = READ_FIFO_DEPTH / 2;
	localparam integer READ_PAIR_FIFO_AW = $clog2(READ_PAIR_FIFO_DEPTH);
	localparam integer READ_FIFO_W = 34;
	localparam integer READ_DESC_DEPTH = 4;
	localparam integer READ_DESC_AW = $clog2(READ_DESC_DEPTH);
	localparam [5:0] ARB_QUOTA = 6'd32;
	localparam integer WRITE_URGENT_LEVEL =
		(FIFO_DEPTH > 128) ? (FIFO_DEPTH - 64) : (FIFO_DEPTH - 8);
	localparam integer READ_URGENT_LEVEL =
		(READ_PAIR_FIFO_DEPTH > 128) ? 64 :
		(READ_PAIR_FIFO_DEPTH / 4);
	localparam integer WRITE_READY_MARGIN =
		(FIFO_DEPTH > 16) ? 8 :
		(FIFO_DEPTH > 8)  ? 4 : 1;

	initial begin
		if ((SLOT_COUNT & (SLOT_COUNT - 1)) != 0)
			$error("vfb_sdram_delay SLOT_COUNT must be a power of two");
		if ((FIFO_DEPTH & (FIFO_DEPTH - 1)) != 0)
			$error("vfb_sdram_delay FIFO_DEPTH must be a power of two");
		if ((READ_FIFO_DEPTH & (READ_FIFO_DEPTH - 1)) != 0)
			$error("vfb_sdram_delay READ_FIFO_DEPTH must be a power of two");
		if (READ_FIFO_DEPTH < 4)
			$error("vfb_sdram_delay READ_FIFO_DEPTH must be at least four");
		if ((READ_DESC_DEPTH & (READ_DESC_DEPTH - 1)) != 0)
			$error("vfb_sdram_delay READ_DESC_DEPTH must be a power of two");
		if (DELAY_LINES >= SLOT_COUNT)
			$error("vfb_sdram_delay DELAY_LINES must be below SLOT_COUNT");
	end

	// Detect lines and encode RGB.
	logic hblank_d;
	logic line_had_pixels;
	logic line_vsync;
	logic line_vblank;
	logic [15:0] line_sequence;
	logic [SLOT_W-1:0] encode_slot;
	logic [WORD_W-1:0] encode_word_index;

	wire active_pixel =
		ce_pix && !VGA_HBLANK_IN && !VGA_VBLANK_IN;
	wire line_start =
		ce_pix && hblank_d && !VGA_HBLANK_IN;
	wire line_end =
		ce_pix && !hblank_d && VGA_HBLANK_IN;

	always_ff @(posedge clk_sys) begin
		if (reset)
			hblank_d <= 1'b1;
		else if (ce_pix)
			hblank_d <= VGA_HBLANK_IN;
	end

	logic        enc_token_valid;
	logic        enc_token_ready;
	logic [31:0] enc_token_data;
	logic [1:0]  enc_token_words;
	logic        enc_token_eol;
	logic        enc_overflow;

	vfb_rle_encoder encoder (
		.clk_sys(clk_sys),
		.reset(reset),
		.pixel_valid(active_pixel),
		.rgb_in({VGA_R_IN, VGA_G_IN, VGA_B_IN}),
		.line_end(line_end),
		.token_valid(enc_token_valid),
		.token_ready(enc_token_ready),
		.token_data(enc_token_data),
		.token_words(enc_token_words),
		.token_eol(enc_token_eol),
		.overflow(enc_overflow)
	);

	// Each queued 32-bit word carries its line slot and word index, so writing
	// can begin before the line ends.
	logic write_fifo_full;
	logic write_fifo_empty;
	logic [WRITE_FIFO_W-1:0] write_fifo_data;
	logic [FIFO_AW:0] write_fifo_used;
	logic pack_pending_valid;
	logic [15:0] pack_pending_word;
	logic [PAIR_W-1:0] pack_pending_pair_index;
	logic [SLOT_W-1:0] pack_pending_slot;
	logic pack_pending_eol;
	logic write_fifo_room_q;
	logic encoder_fifo_room_q;
	logic write_pair_valid_q;
	logic [WRITE_FIFO_W-1:0] write_pair_data_q;
	wire pack_flush_eol = pack_pending_valid && pack_pending_eol;
	wire enc_packet_writes_pair =
		pack_pending_valid || (enc_token_words == 2'd2) || enc_token_eol;
	wire enc_packet_accept = enc_token_valid && enc_token_ready;
	wire pack_flush_accept = pack_flush_eol && encoder_fifo_room_q;
	wire write_pair_accept =
		pack_flush_accept ||
		(enc_packet_accept && enc_packet_writes_pair);
	wire write_fifo_push = write_pair_valid_q;
	logic [31:0] write_fifo_pair_data;
	logic [PAIR_W-1:0] write_fifo_pair_index;
	logic [SLOT_W-1:0] write_fifo_pair_slot;
	logic write_fifo_pair_eol;
	wire [WRITE_FIFO_W-1:0] write_pair_data = {
		write_fifo_pair_eol,
		write_fifo_pair_slot,
		write_fifo_pair_index,
		write_fifo_pair_data
	};
	wire [WORD_W:0] encoded_words_after_packet =
		{1'b0, encode_word_index} +
		{{(WORD_W-1){1'b0}}, enc_token_words};
	wire write_fifo_pop;
	logic write_head_valid;
	logic write_head_eol;
	logic [SLOT_W-1:0] write_head_slot;
	logic [PAIR_W-1:0] write_head_index;
	logic [31:0] write_head_data;
	wire write_head_consume;

	always_comb begin
		write_fifo_pair_data = 32'd0;
		write_fifo_pair_index = encode_word_index[WORD_W-1:1];
		write_fifo_pair_slot = encode_slot;
		write_fifo_pair_eol = 1'b0;

		if (pack_flush_eol) begin
			write_fifo_pair_data = {16'd0, pack_pending_word};
			write_fifo_pair_index = pack_pending_pair_index;
			write_fifo_pair_slot = pack_pending_slot;
			write_fifo_pair_eol = 1'b1;
		end else if (pack_pending_valid) begin
			write_fifo_pair_data = {
				enc_token_data[15:0],
				pack_pending_word
			};
			write_fifo_pair_index = pack_pending_pair_index;
			write_fifo_pair_slot = pack_pending_slot;
			write_fifo_pair_eol =
				enc_token_eol && (enc_token_words == 2'd1);
		end else if (enc_token_words == 2'd2) begin
			write_fifo_pair_data = enc_token_data;
			write_fifo_pair_eol = enc_token_eol;
		end else begin
			write_fifo_pair_data = {16'd0, enc_token_data[15:0]};
			write_fifo_pair_eol = enc_token_eol;
		end
	end

	assign enc_token_ready =
		!pack_flush_eol &&
		(!enc_packet_writes_pair || encoder_fifo_room_q);

	vfb_sync_fifo #(
		.WIDTH(WRITE_FIFO_W),
		.DEPTH(FIFO_DEPTH)
	) write_fifo (
		.clk_sys(clk_sys),
		.reset(reset),
		.wr_en(write_fifo_push),
		.wr_data(write_pair_data_q),
		.full(write_fifo_full),
		.rd_en(write_fifo_pop),
		.rd_data(write_fifo_data),
		.empty(write_fifo_empty),
		.used(write_fifo_used)
	);

	// Register available-space checks and reserve room for accepted encoder
	// data that has not reached the FIFO yet.
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			write_fifo_room_q <= 1'b0;
			encoder_fifo_room_q <= 1'b0;
			write_pair_valid_q <= 1'b0;
		end else begin
			write_fifo_room_q <=
				(write_fifo_used < (FIFO_DEPTH - WRITE_READY_MARGIN));
			encoder_fifo_room_q <= write_fifo_room_q;
			write_pair_valid_q <= write_pair_accept;
			if (write_pair_accept)
				write_pair_data_q <= write_pair_data;
		end
	end

	assign write_fifo_pop =
		!write_fifo_empty && (!write_head_valid || write_head_consume);

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			write_head_valid <= 1'b0;
			write_head_eol <= 1'b0;
			write_head_slot <= '0;
			write_head_index <= '0;
			write_head_data <= 32'd0;
		end else begin
			if (write_fifo_pop) begin
				write_head_valid <= 1'b1;
				write_head_eol <= write_fifo_data[WRITE_FIFO_W-1];
				write_head_slot <=
					write_fifo_data[WRITE_FIFO_W-2 -: SLOT_W];
				write_head_index <= write_fifo_data[31+PAIR_W:32];
				write_head_data <= write_fifo_data[31:0];
			end else if (write_head_consume) begin
				write_head_valid <= 1'b0;
			end
		end
	end

	// Line descriptors
	logic [WORD_W:0] descriptor_words [0:SLOT_COUNT-1];
	logic descriptor_vsync [0:SLOT_COUNT-1];
	logic descriptor_vblank [0:SLOT_COUNT-1];
	logic descriptor_valid [0:SLOT_COUNT-1];
	logic descriptor_written [0:SLOT_COUNT-1];

	logic finalize_pending;
	logic [SLOT_W-1:0] finalize_slot;
	logic finalize_vsync;
	logic finalize_vblank;
	logic blank_finalize_pending;
	logic [SLOT_W-1:0] blank_finalize_slot;
	logic blank_finalize_vsync;
	logic blank_finalize_vblank;
	logic descriptor_lookup_pending;
	logic descriptor_lookup_warmed;
	logic [SLOT_W-1:0] descriptor_lookup_slot;
	logic descriptor_apply_pending;
	logic descriptor_apply_warmed;
	logic [SLOT_W-1:0] descriptor_apply_slot;
	logic [WORD_W:0] descriptor_apply_words;
	logic descriptor_apply_vsync;
	logic descriptor_apply_vblank;
	logic descriptor_apply_valid;
	logic descriptor_apply_written;

	// Read preparation runs one line ahead. A line selected after line N is
	// stored in prefetch_line, moved to pending_line at the next line start,
	// and shown at the following line start. SDRAM therefore has one full line
	// to prepare the data.
	logic prefetch_line_valid;
	logic prefetch_line_vsync;
	logic prefetch_line_vblank;
	logic pending_line_valid;
	logic pending_line_vsync;
	logic pending_line_vblank;
	logic output_line_valid;
	logic output_line_vsync;
	logic output_line_vblank;

	logic [15:0] delayed_sequence;
	always_comb
		delayed_sequence = line_sequence + 16'd2 - 16'(DELAY_LINES);
	wire [SLOT_W-1:0] delayed_slot = delayed_sequence[SLOT_W-1:0];
	logic delay_warmed_r;
	wire delay_warmed_now =
		(line_sequence + 16'd2 >= 16'(DELAY_LINES));
	wire delay_warmed =
		delay_warmed_r || delay_warmed_now;

	// Read compressed data and decode it.
	logic read_fifo_full;
	logic read_fifo_empty;
	logic [READ_FIFO_W-1:0] read_fifo_data;
	logic [READ_PAIR_FIFO_AW:0] read_fifo_used;
	logic read_fifo_push;
	logic read_fifo_pop;
	logic [READ_FIFO_W-1:0] read_fifo_write_data;

	vfb_sync_fifo #(
		.WIDTH(READ_FIFO_W),
		.DEPTH(READ_PAIR_FIFO_DEPTH)
	) read_fifo (
		.clk_sys(clk_sys),
		.reset(reset),
		.wr_en(read_fifo_push),
		.wr_data(read_fifo_write_data),
		.full(read_fifo_full),
		.rd_en(read_fifo_pop),
		.rd_data(read_fifo_data),
		.empty(read_fifo_empty),
		.used(read_fifo_used)
	);

	logic read_active;
	logic [SLOT_W-1:0] read_slot;
	logic [WORD_W:0] read_word_count;
	logic [PAIR_W:0] read_pair_count;
	logic [PAIR_W:0] read_issue_index;
	logic [PAIR_W:0] read_response_index;
	logic [READ_FIFO_AW:0] read_outstanding;

	logic [SLOT_W-1:0] read_desc_slot [0:READ_DESC_DEPTH-1];
	logic [WORD_W:0] read_desc_words [0:READ_DESC_DEPTH-1];
	logic [READ_DESC_AW-1:0] read_desc_wr_ptr;
	logic [READ_DESC_AW-1:0] read_desc_rd_ptr;
	logic [READ_DESC_AW:0] read_desc_used;

	wire read_engine_idle =
		!read_active && (read_outstanding == 0);
	wire descriptor_apply_ok =
		descriptor_apply_pending &&
		descriptor_apply_warmed &&
		descriptor_apply_valid &&
		descriptor_apply_written;
	wire descriptor_apply_read_needed =
		descriptor_apply_ok && (descriptor_apply_words != 0);
	wire read_desc_pop =
		read_engine_idle && (read_desc_used != 0);
	wire [READ_DESC_AW:0] read_desc_used_after_pop =
		read_desc_used - {{READ_DESC_AW{1'b0}}, read_desc_pop};
	wire read_desc_can_push =
		(read_desc_used_after_pop < READ_DESC_DEPTH);
	wire read_desc_push =
		descriptor_apply_read_needed &&
		!(read_engine_idle && (read_desc_used == 0)) &&
		read_desc_can_push;
	wire read_desc_overflow =
		descriptor_apply_read_needed &&
		!(read_engine_idle && (read_desc_used == 0)) &&
		!read_desc_can_push;
	wire read_start_direct =
		descriptor_apply_read_needed && read_engine_idle &&
		(read_desc_used == 0);
	wire read_start_queued = read_desc_pop;
	wire read_start = read_start_direct || read_start_queued;
	wire [SLOT_W-1:0] read_start_slot =
		read_start_queued ? read_desc_slot[read_desc_rd_ptr]
		                  : descriptor_apply_slot;
	wire [WORD_W:0] read_start_words =
		read_start_queued ? read_desc_words[read_desc_rd_ptr]
		                  : descriptor_apply_words;

	logic [23:0] decoded_rgb;
	logic decoded_valid;
	logic decoded_line_done;
	logic decoder_underflow;
	logic decoder_token_ready;
	// Four 16-bit words cover two SDRAM responses, so both words of a literal
	// remain available when they cross a 32-bit boundary.
	logic [63:0] decoder_words;
	logic [3:0] decoder_word_eol;
	logic [2:0] decoder_word_count;
	logic [63:0] decoder_words_next;
	logic [3:0] decoder_word_eol_next;
	logic [2:0] decoder_word_count_next;

	wire decoder_word_is_literal =
		(decoder_words[15:12] == 4'h0) &&
		(decoder_words[11:10] == 2'b10);
	wire [1:0] decoder_packet_words =
		decoder_word_is_literal ? 2'd2 : 2'd1;
	wire decoder_token_valid =
		(decoder_word_count != 0) &&
		(!decoder_word_is_literal || (decoder_word_count >= 2));
	wire decoder_token_accept =
		decoder_token_valid && decoder_token_ready;
	wire decoder_token_eol =
		(decoder_packet_words == 2'd2)
			? decoder_word_eol[1]
			: decoder_word_eol[0];

	wire read_pair_high_valid = read_fifo_data[32];
	wire read_pair_eol = read_fifo_data[33];
	wire [2:0] read_pair_words =
		read_pair_high_valid ? 3'd2 : 3'd1;
	wire [2:0] decoder_words_after_accept =
		decoder_word_count -
		(decoder_token_accept
			? {1'b0, decoder_packet_words}
			: 3'd0);

	assign read_fifo_pop =
		!read_fifo_empty &&
		(decoder_words_after_accept + read_pair_words <= 3'd4);

	always_comb begin
		decoder_words_next = decoder_words;
		decoder_word_eol_next = decoder_word_eol;
		decoder_word_count_next = decoder_word_count;

		if (decoder_token_accept) begin
			if (decoder_packet_words == 2'd2) begin
				decoder_words_next = {32'd0, decoder_words[63:32]};
				decoder_word_eol_next =
					{2'b00, decoder_word_eol[3:2]};
				decoder_word_count_next =
					decoder_word_count - 2'd2;
			end else begin
				decoder_words_next = {16'd0, decoder_words[63:16]};
				decoder_word_eol_next =
					{1'b0, decoder_word_eol[3:1]};
				decoder_word_count_next =
					decoder_word_count - 1'b1;
			end
		end

		if (read_fifo_pop) begin
			case (decoder_word_count_next)
				3'd0: begin
					decoder_words_next[15:0] =
						read_fifo_data[15:0];
					decoder_word_eol_next[0] =
						read_pair_eol && !read_pair_high_valid;
					if (read_pair_high_valid) begin
						decoder_words_next[31:16] =
							read_fifo_data[31:16];
						decoder_word_eol_next[1] =
							read_pair_eol;
					end
				end

				3'd1: begin
					decoder_words_next[31:16] =
						read_fifo_data[15:0];
					decoder_word_eol_next[1] =
						read_pair_eol && !read_pair_high_valid;
					if (read_pair_high_valid) begin
						decoder_words_next[47:32] =
							read_fifo_data[31:16];
						decoder_word_eol_next[2] =
							read_pair_eol;
					end
				end

				3'd2: begin
					decoder_words_next[47:32] =
						read_fifo_data[15:0];
					decoder_word_eol_next[2] =
						read_pair_eol && !read_pair_high_valid;
					if (read_pair_high_valid) begin
						decoder_words_next[63:48] =
							read_fifo_data[31:16];
						decoder_word_eol_next[3] =
							read_pair_eol;
					end
				end

				default: begin
					decoder_words_next[63:48] =
						read_fifo_data[15:0];
					decoder_word_eol_next[3] = read_pair_eol;
				end
			endcase
			decoder_word_count_next =
				decoder_word_count_next + read_pair_words;
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			decoder_words <= 64'd0;
			decoder_word_eol <= 4'd0;
			decoder_word_count <= 3'd0;
		end else begin
			decoder_words <= decoder_words_next;
			decoder_word_eol <= decoder_word_eol_next;
			decoder_word_count <= decoder_word_count_next;
		end
	end

	// Select the pending line at line start and hold its timing through the line.
	wire current_line_valid =
		line_start ? pending_line_valid : output_line_valid;
	wire current_line_vsync =
		line_start ? pending_line_vsync : output_line_vsync;
	wire current_line_vblank =
		line_start ? pending_line_vblank : output_line_vblank;
	wire decoder_advance =
		ce_pix && !VGA_HBLANK_IN && !current_line_vblank;

	vfb_rle_decoder decoder (
		.clk_sys(clk_sys),
		.reset(reset),
		.token_valid(decoder_token_valid),
		.token_ready(decoder_token_ready),
		.token_data(decoder_words[31:0]),
		.token_eol(decoder_token_eol),
		.advance(decoder_advance),
		.rgb_out(decoded_rgb),
		.pixel_valid(decoded_valid),
		.line_done(decoded_line_done),
		.underflow(decoder_underflow)
	);

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
			// Present the current decoded pixel before advancing the decoder.
			if (current_line_valid && !VGA_HBLANK_IN &&
			    !current_line_vblank) begin
				VGA_R_OUT <= decoded_rgb[23:16];
				VGA_G_OUT <= decoded_rgb[15:8];
				VGA_B_OUT <= decoded_rgb[7:0];
			end else begin
				VGA_R_OUT <= 8'd0;
				VGA_G_OUT <= 8'd0;
				VGA_B_OUT <= 8'd0;
			end
			VGA_HS_OUT <= VGA_HS_IN;
			VGA_HBLANK_OUT <= VGA_HBLANK_IN;
			VGA_VS_OUT <= current_line_vsync;
			VGA_VBLANK_OUT <= current_line_vblank;
		end
	end

	// Open-row SDRAM controller and read/write scheduler
	logic        mem_req_valid;
	logic        mem_req_write;
	logic [31:0] mem_req_addr;
	logic [31:0] mem_req_wdata;
	logic        mem_req_ready;
	logic        mem_rsp_valid;
	logic [31:0] mem_rsp_rdata;

	logic        issue_valid;
	logic        issue_read;
	logic        issue_write;
	logic [31:0] issue_addr;
	logic [31:0] issue_wdata;
	logic        issue_write_eol;
	logic [SLOT_W-1:0] issue_write_slot;
	logic        issue_load;

	vfb_sdram_core #(
		.SDRAM_MHZ(SDRAM_MHZ)
	) sdram_controller (
		.clk_sys(clk_sys),
		.reset(reset),
		.req_valid(mem_req_valid),
		.req_write(mem_req_write),
		.req_addr(mem_req_addr),
		.req_wdata(mem_req_wdata),
		.req_be(4'hf),
		.req_ready(mem_req_ready),
		.rsp_valid(mem_rsp_valid),
		.rsp_rdata(mem_rsp_rdata),
		.init_done(init_done),
		.sdram_data_in(sdram_data_in),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(sdram_cke),
		.sdram_cs(sdram_cs),
		.sdram_ras(sdram_ras),
		.sdram_cas(sdram_cas),
		.sdram_we(sdram_we),
		.sdram_dqm(sdram_dqm),
		.sdram_addr(sdram_addr),
		.sdram_ba(sdram_ba)
	);

	wire [READ_FIFO_AW+1:0] read_reserved =
		(READ_FIFO_AW + 2)'(read_fifo_used) +
		(READ_FIFO_AW + 2)'(read_outstanding);
	wire read_available =
		read_active &&
		(read_issue_index < read_pair_count) &&
		(read_reserved < READ_PAIR_FIFO_DEPTH - 2);
	wire write_available = write_head_valid;
	wire read_more_after =
		(read_issue_index + 1'b1 < read_pair_count) &&
		(read_reserved + 1'b1 < READ_PAIR_FIFO_DEPTH - 2);
	wire write_more_after = write_head_valid || !write_fifo_empty;
	wire write_urgent = (write_fifo_used >= WRITE_URGENT_LEVEL);
	wire read_urgent =
		read_active && (read_reserved <= READ_URGENT_LEVEL);
	wire read_preferred =
		read_available &&
		(!write_available || read_urgent || !write_urgent);

	logic arb_locked;
	logic arb_read;
	logic [5:0] arb_remaining;
	logic read_available_q;
	logic write_available_q;
	logic read_preferred_q;
	logic read_more_after_q;
	logic write_more_after_q;

	wire arb_read_effective =
		(arb_locked && read_preferred_q) ? 1'b1 : arb_read;
	wire selected_available =
		arb_read_effective ? read_available_q : write_available_q;
	assign mem_req_valid = issue_valid;
	assign mem_req_write = issue_write;
	assign mem_req_addr = issue_addr;
	assign mem_req_wdata = issue_wdata;

	assign issue_load =
		!issue_valid && init_done && arb_locked && selected_available;

	wire issue_accepted = mem_req_ready && issue_valid;
	wire read_request_accepted = issue_accepted && issue_read;
	wire write_request_accepted = issue_accepted && issue_write;
	// Queue another request of the same type while its quota remains, avoiding
	// an idle clock between accesses to the same row.
	wire issue_chain_read =
		read_request_accepted && (arb_remaining > 1) &&
		read_more_after_q;
	wire issue_chain_write =
		write_request_accepted && (arb_remaining > 1) &&
		write_head_valid;
	wire [PAIR_W:0] chained_read_index =
		read_issue_index + {{PAIR_W{1'b0}}, 1'b1};

	assign write_head_consume =
		(issue_load && !arb_read_effective) || issue_chain_write;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			read_available_q <= 1'b0;
			write_available_q <= 1'b0;
			read_preferred_q <= 1'b0;
			read_more_after_q <= 1'b0;
			write_more_after_q <= 1'b0;
		end else begin
			read_available_q <= read_available;
			write_available_q <= write_available;
			read_preferred_q <= read_preferred;
			read_more_after_q <= read_more_after;
			write_more_after_q <= write_more_after;
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			issue_valid <= 1'b0;
			issue_read  <= 1'b0;
			issue_write <= 1'b0;
			issue_addr  <= 32'd0;
			issue_wdata <= 32'd0;
			issue_write_eol <= 1'b0;
			issue_write_slot <= '0;
		end else if (issue_chain_read) begin
			issue_valid <= 1'b1;
			issue_read  <= 1'b1;
			issue_write <= 1'b0;
			issue_addr <=
				({{(32-SLOT_W){1'b0}}, read_slot} << 13) +
				({{(32-PAIR_W){1'b0}},
				  chained_read_index[PAIR_W-1:0]} << 2);
		end else if (issue_chain_write) begin
			issue_valid <= 1'b1;
			issue_read  <= 1'b0;
			issue_write <= 1'b1;
			issue_write_eol <= write_head_eol;
			issue_write_slot <= write_head_slot;
			issue_wdata <= write_head_data;
			issue_addr <=
				({{(32-SLOT_W){1'b0}}, write_head_slot} << 13) +
				({{(32-PAIR_W){1'b0}}, write_head_index} << 2);
		end else if (issue_accepted) begin
			issue_valid <= 1'b0;
		end else if (!issue_valid) begin
			issue_valid <= issue_load;
			issue_read  <= issue_load && arb_read_effective;
			issue_write <= issue_load && !arb_read_effective;
			if (issue_load) begin
				issue_write_eol <=
					!arb_read_effective && write_head_eol;
				issue_write_slot <= write_head_slot;
				issue_wdata <= write_head_data;
				if (arb_read_effective)
					issue_addr <=
						({{(32-SLOT_W){1'b0}}, read_slot} << 13) +
						({{(32-PAIR_W){1'b0}},
						  read_issue_index[PAIR_W-1:0]} << 2);
				else
					issue_addr <=
						({{(32-SLOT_W){1'b0}}, write_head_slot} << 13) +
						({{(32-PAIR_W){1'b0}},
						  write_head_index} << 2);
			end
		end
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			arb_locked    <= 1'b0;
			arb_read      <= 1'b0;
			arb_remaining <= ARB_QUOTA;
		end else if (!arb_locked) begin
			if (read_available_q || write_available_q) begin
				arb_locked <= 1'b1;
				arb_read <= read_preferred_q;
				arb_remaining <= ARB_QUOTA;
			end
		end else if (!selected_available) begin
			arb_locked <= 1'b0;
		end else if (issue_accepted) begin
			if (arb_remaining > 1 &&
			    (arb_read_effective
			     ? read_more_after_q
			     : write_more_after_q)) begin
				arb_remaining <= arb_remaining - 1'b1;
				arb_read <= arb_read_effective;
			end else if (arb_read_effective && write_available_q &&
			             !read_preferred_q) begin
				arb_read <= 1'b0;
				arb_remaining <= ARB_QUOTA;
			end else if (!arb_read_effective && read_available_q &&
			             read_preferred_q) begin
				arb_read <= 1'b1;
				arb_remaining <= ARB_QUOTA;
			end else if (arb_read_effective
			             ? read_more_after_q
			             : write_more_after_q) begin
				arb_read <= arb_read_effective;
				arb_remaining <= ARB_QUOTA;
			end else begin
				arb_locked <= 1'b0;
			end
		end
	end

	// Read responses remain 32 bits through the FIFO. The line word count
	// suppresses the unused high halfword on odd-length lines.
	wire [WORD_W:0] read_response_word_base =
		{read_response_index, 1'b0};
	wire read_low_real =
		mem_rsp_valid && (read_response_word_base < read_word_count);
	wire read_high_real =
		mem_rsp_valid && (read_response_word_base + 1'b1 < read_word_count);
	wire read_low_eol =
		(read_response_word_base + 1'b1 == read_word_count);
	wire read_high_real_eol =
		(read_response_word_base + 2'd2 == read_word_count);
	wire read_response_eol = read_low_eol || read_high_real_eol;

	assign read_fifo_push = read_low_real && !read_fifo_full;
	assign read_fifo_write_data = {
		read_response_eol,
		read_high_real,
		mem_rsp_rdata
	};

	integer slot_i;
	always_ff @(posedge clk_sys) begin
		if (reset) begin
			line_had_pixels   <= 1'b0;
			line_vsync        <= 1'b1;
			line_vblank       <= 1'b1;
			line_sequence     <= 16'd0;
			delay_warmed_r    <= 1'b0;
			encode_slot       <= '0;
			encode_word_index <= '0;
			pack_pending_valid <= 1'b0;
			pack_pending_word <= 16'd0;
			pack_pending_pair_index <= '0;
			pack_pending_slot <= '0;
			pack_pending_eol <= 1'b0;
			finalize_pending  <= 1'b0;
			finalize_slot     <= '0;
			finalize_vsync    <= 1'b1;
			finalize_vblank   <= 1'b1;
			blank_finalize_pending <= 1'b0;
			blank_finalize_slot <= '0;
			blank_finalize_vsync <= 1'b1;
			blank_finalize_vblank <= 1'b1;
			descriptor_lookup_pending <= 1'b0;
			descriptor_lookup_warmed <= 1'b0;
			descriptor_lookup_slot <= '0;
			descriptor_apply_pending <= 1'b0;
			descriptor_apply_warmed <= 1'b0;
			descriptor_apply_slot <= '0;
			descriptor_apply_words <= '0;
			descriptor_apply_vsync <= 1'b1;
			descriptor_apply_vblank <= 1'b1;
			descriptor_apply_valid <= 1'b0;
			descriptor_apply_written <= 1'b0;
			prefetch_line_valid <= 1'b0;
			prefetch_line_vsync <= 1'b1;
			prefetch_line_vblank <= 1'b1;
			pending_line_valid <= 1'b0;
			pending_line_vsync <= 1'b1;
			pending_line_vblank <= 1'b1;
			output_line_valid <= 1'b0;
			output_line_vsync <= 1'b1;
			output_line_vblank <= 1'b1;
			read_active       <= 1'b0;
			read_slot         <= '0;
			read_word_count   <= '0;
			read_pair_count   <= '0;
			read_issue_index  <= '0;
			read_response_index <= '0;
			read_outstanding  <= '0;
			read_desc_wr_ptr  <= '0;
			read_desc_rd_ptr  <= '0;
			read_desc_used    <= '0;
			overflow          <= 1'b0;
			underflow         <= 1'b0;
			for (slot_i = 0; slot_i < SLOT_COUNT; slot_i = slot_i + 1) begin
				descriptor_words[slot_i] <= '0;
				descriptor_vsync[slot_i] <= 1'b1;
				descriptor_vblank[slot_i] <= 1'b1;
				descriptor_valid[slot_i] <= 1'b0;
				descriptor_written[slot_i] <= 1'b0;
			end
		end else begin
			// Record an empty line one clock after detecting it, keeping video
			// timing logic out of the descriptor RAM write path.
			if (blank_finalize_pending) begin
				descriptor_words[blank_finalize_slot] <= '0;
				descriptor_vsync[blank_finalize_slot] <=
					blank_finalize_vsync;
				descriptor_vblank[blank_finalize_slot] <=
					blank_finalize_vblank;
				descriptor_valid[blank_finalize_slot] <= 1'b1;
				descriptor_written[blank_finalize_slot] <= 1'b1;
				blank_finalize_pending <= 1'b0;
				encode_slot <= blank_finalize_slot + 1'b1;
				encode_word_index <= '0;
				pack_pending_valid <= 1'b0;
				pack_pending_eol <= 1'b0;
			end

			if (line_start) begin
				line_had_pixels <= 1'b0;
				line_vsync  <= VGA_VS_IN;
				line_vblank <= VGA_VBLANK_IN;
				output_line_valid <= pending_line_valid;
				output_line_vsync <= pending_line_vsync;
				output_line_vblank <= pending_line_vblank;
				pending_line_valid <= prefetch_line_valid;
				pending_line_vsync <= prefetch_line_vsync;
				pending_line_vblank <= prefetch_line_vblank;
				prefetch_line_valid <= 1'b0;
				prefetch_line_vsync <= 1'b1;
				prefetch_line_vblank <= 1'b1;
			end

			if (active_pixel)
				line_had_pixels <= 1'b1;

			if (pack_flush_accept) begin
				pack_pending_valid <= 1'b0;
				pack_pending_eol <= 1'b0;
			end else if (enc_packet_accept) begin
				if ((encoded_words_after_packet > MAX_WORDS) ||
				    ((encoded_words_after_packet == MAX_WORDS) &&
				     !enc_token_eol))
					overflow <= 1'b1;

				case ({pack_pending_valid,
				       enc_token_words == 2'd2})
					2'b00: begin
						pack_pending_valid <= !enc_token_eol;
						pack_pending_word <= enc_token_data[15:0];
						pack_pending_pair_index <=
							encode_word_index[WORD_W-1:1];
						pack_pending_slot <= encode_slot;
						pack_pending_eol <= 1'b0;
					end

					2'b01: begin
						pack_pending_valid <= 1'b0;
						pack_pending_eol <= 1'b0;
					end

					2'b10: begin
						pack_pending_valid <= 1'b0;
						pack_pending_eol <= 1'b0;
					end

					default: begin
						pack_pending_valid <= 1'b1;
						pack_pending_word <= enc_token_data[31:16];
						pack_pending_pair_index <=
							pack_pending_pair_index + 1'b1;
						pack_pending_slot <= encode_slot;
						pack_pending_eol <= enc_token_eol;
					end
				endcase

				if (enc_token_eol) begin
					descriptor_words[finalize_slot] <=
						encoded_words_after_packet;
					descriptor_vsync[finalize_slot] <= finalize_vsync;
					descriptor_vblank[finalize_slot] <= finalize_vblank;
					descriptor_valid[finalize_slot] <= 1'b1;
					descriptor_written[finalize_slot] <= 1'b0;
					finalize_pending <= 1'b0;
					encode_slot <= encode_slot + 1'b1;
					encode_word_index <= '0;
				end else begin
					encode_word_index <=
						encoded_words_after_packet[WORD_W-1:0];
				end
			end

			if (write_request_accepted && issue_write_eol)
				descriptor_written[issue_write_slot] <= 1'b1;

			if (descriptor_lookup_pending) begin
				descriptor_lookup_pending <= 1'b0;
				descriptor_apply_pending <= 1'b1;
				descriptor_apply_warmed <= descriptor_lookup_warmed;
				descriptor_apply_slot <= descriptor_lookup_slot;
				descriptor_apply_words <=
					descriptor_words[descriptor_lookup_slot];
				descriptor_apply_vsync <=
					descriptor_vsync[descriptor_lookup_slot];
				descriptor_apply_vblank <=
					descriptor_vblank[descriptor_lookup_slot];
				descriptor_apply_valid <=
					descriptor_valid[descriptor_lookup_slot];
				descriptor_apply_written <=
					descriptor_written[descriptor_lookup_slot];
			end

			if (descriptor_apply_pending) begin
				descriptor_apply_pending <= 1'b0;
				if (descriptor_apply_warmed &&
				    descriptor_apply_valid &&
				    descriptor_apply_written) begin
					prefetch_line_valid <= 1'b1;
					prefetch_line_vsync <= descriptor_apply_vsync;
					prefetch_line_vblank <= descriptor_apply_vblank;
				end else if (descriptor_apply_warmed) begin
					prefetch_line_valid <= 1'b0;
					prefetch_line_vsync <= 1'b1;
					prefetch_line_vblank <= 1'b1;
					underflow <= 1'b1;
				end
			end

			if (read_desc_push) begin
				read_desc_slot[read_desc_wr_ptr] <=
					descriptor_apply_slot;
				read_desc_words[read_desc_wr_ptr] <=
					descriptor_apply_words;
				read_desc_wr_ptr <= read_desc_wr_ptr + 1'b1;
			end
			if (read_desc_pop)
				read_desc_rd_ptr <= read_desc_rd_ptr + 1'b1;
			case ({read_desc_push, read_desc_pop})
				2'b10: read_desc_used <= read_desc_used + 1'b1;
				2'b01: read_desc_used <= read_desc_used - 1'b1;
				default: read_desc_used <= read_desc_used;
			endcase
			if (read_desc_overflow)
				underflow <= 1'b1;

			if (read_start) begin
				read_slot <= read_start_slot;
				read_word_count <= read_start_words;
				// Number of 32-bit SDR reads needed for the 16-bit RLE words:
				// ceil(words / 2), explicitly sized to avoid implicit truncation.
				read_pair_count <=
					read_start_words[WORD_W:1] +
					{{PAIR_W{1'b0}}, read_start_words[0]};
				read_issue_index <= '0;
				read_response_index <= '0;
				read_active <= 1'b1;
			end

			if (line_end) begin
				line_sequence <= line_sequence + 1'b1;
				delay_warmed_r <= delay_warmed;

				if (line_had_pixels) begin
					finalize_pending <= 1'b1;
					finalize_slot <= encode_slot;
					finalize_vsync <= line_vsync;
					finalize_vblank <= line_vblank;
				end else begin
					blank_finalize_pending <= 1'b1;
					blank_finalize_slot <= encode_slot;
					blank_finalize_vsync <= line_vsync;
					blank_finalize_vblank <= line_vblank;
				end

				descriptor_lookup_pending <= 1'b1;
				descriptor_lookup_warmed <= delay_warmed;
				descriptor_lookup_slot <= delayed_slot;
			end

			if (read_request_accepted)
				read_issue_index <= read_issue_index + 1'b1;

			case ({read_request_accepted, mem_rsp_valid})
				2'b10: read_outstanding <= read_outstanding + 1'b1;
				2'b01: read_outstanding <= read_outstanding - 1'b1;
				default: read_outstanding <= read_outstanding;
			endcase

			if (mem_rsp_valid) begin
				if (read_fifo_full && read_low_real)
					overflow <= 1'b1;
				read_response_index <= read_response_index + 1'b1;
				if (read_response_index + 1'b1 == read_pair_count)
					read_active <= 1'b0;
			end

			if (enc_overflow)
				overflow <= 1'b1;
			if (decoder_underflow && output_line_valid)
				underflow <= 1'b1;
			if (finalize_pending && line_start)
				overflow <= 1'b1;
			if (blank_finalize_pending && line_end)
				overflow <= 1'b1;
		end
	end

endmodule
