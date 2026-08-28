`timescale 1ns / 1ps

// ============================================================================
// Sparse inter-frame phosphor compositor.
// written 2026 by Videodr0me
//
// A completed raw frame is blended in place with the newest accumulator.
// The target buffer cannot be shown until every required tile is finished.
// ============================================================================

module vfb_phosphor_compositor #(
	parameter integer BUFFER_COUNT = 5,
	parameter integer BUF_IDX_W = 3,
	parameter integer TILEMAP_ADDR_W = 15
) (
	input  logic clk_sys,
	input  logic reset,

	input  logic [11:0] render_width,
	input  logic [11:0] render_height,
	input  logic [1:0]  intra_frame_mode,
	input  logic [1:0]  inter_frame_mode,

	input  logic                 compose_req,
	input  logic [BUF_IDX_W-1:0] compose_source_buf,
	input  logic [BUF_IDX_W-1:0] compose_target_buf,
	input  logic                 compose_has_source,
	input  logic                 compose_source_is_composed,
	output logic                 compose_done,

	input  logic [2:0]  raw_reference_draw_idx,
	input  logic [31:0] raw_age_map,
	input  logic [3:0]  raw_frame_age,
	input  logic        raw_metadata_ready,

	output logic [TILEMAP_ADDR_W-1:0] tilemap_addr,
	output logic                      tilemap_we,
	output logic [BUF_IDX_W-1:0]      tilemap_buf,
	output logic                      tilemap_din,
	input  logic [BUFFER_COUNT-1:0]   tilemap_dout,

	output logic        read_ready,
	input  logic        read_grant,
	output logic [28:0] read_addr,
	output logic [7:0]  read_burstcnt,
	input  logic [63:0] read_data,
	input  logic        read_data_valid,

	output logic        write_ready,
	input  logic        write_grant,
	input  logic        write_done,
	output logic [28:0] write_addr,
	output logic [7:0]  write_burstcnt,
	output logic [63:0] write_data,
	output logic [7:0]  write_be,
	input  logic        write_advance
);

	import vfb_layout_pkg::*;

	logic [1:0] intra_frame_mode_q = 2'd0;
	logic [1:0] inter_frame_mode_q = 2'd0;
	always_ff @(posedge clk_sys) begin
		intra_frame_mode_q <= intra_frame_mode;
		inter_frame_mode_q <= inter_frame_mode;
	end

	function automatic [15:0] inter_decay_factors(
		input logic [1:0] mode,
		input logic [3:0] age
	);
		begin
			case ({mode, age})
				{2'd1, 4'd0}:  inter_decay_factors = {8'd255, 8'd255};
				{2'd1, 4'd1}:  inter_decay_factors = {8'd227, 8'd242};
				{2'd1, 4'd2}:  inter_decay_factors = {8'd205, 8'd230};
				{2'd1, 4'd3}:  inter_decay_factors = {8'd187, 8'd218};
				{2'd1, 4'd4}:  inter_decay_factors = {8'd172, 8'd206};
				{2'd1, 4'd5}:  inter_decay_factors = {8'd158, 8'd196};
				{2'd1, 4'd6}:  inter_decay_factors = {8'd148, 8'd186};
				{2'd1, 4'd7}:  inter_decay_factors = {8'd138, 8'd175};
				{2'd1, 4'd8}:  inter_decay_factors = {8'd128, 8'd165};
				{2'd1, 4'd9}:  inter_decay_factors = {8'd121, 8'd157};
				{2'd1, 4'd10}: inter_decay_factors = {8'd114, 8'd148};
				{2'd1, 4'd11}: inter_decay_factors = {8'd107, 8'd140};
				{2'd1, 4'd12}: inter_decay_factors = {8'd100, 8'd132};
				{2'd1, 4'd13}: inter_decay_factors = {8'd94, 8'd125};
				{2'd1, 4'd14}: inter_decay_factors = {8'd88, 8'd117};
				{2'd1, 4'd15}: inter_decay_factors = {8'd82, 8'd111};
				{2'd2, 4'd0}:  inter_decay_factors = {8'd255, 8'd255};
				{2'd2, 4'd1}:  inter_decay_factors = {8'd234, 8'd245};
				{2'd2, 4'd2}:  inter_decay_factors = {8'd217, 8'd236};
				{2'd2, 4'd3}:  inter_decay_factors = {8'd203, 8'd227};
				{2'd2, 4'd4}:  inter_decay_factors = {8'd191, 8'd218};
				{2'd2, 4'd5}:  inter_decay_factors = {8'd180, 8'd210};
				{2'd2, 4'd6}:  inter_decay_factors = {8'd172, 8'd202};
				{2'd2, 4'd7}:  inter_decay_factors = {8'd164, 8'd194};
				{2'd2, 4'd8}:  inter_decay_factors = {8'd156, 8'd186};
				{2'd2, 4'd9}:  inter_decay_factors = {8'd150, 8'd179};
				{2'd2, 4'd10}: inter_decay_factors = {8'd144, 8'd172};
				{2'd2, 4'd11}: inter_decay_factors = {8'd138, 8'd166};
				{2'd2, 4'd12}: inter_decay_factors = {8'd132, 8'd159};
				{2'd2, 4'd13}: inter_decay_factors = {8'd127, 8'd153};
				{2'd2, 4'd14}: inter_decay_factors = {8'd122, 8'd147};
				{2'd2, 4'd15}: inter_decay_factors = {8'd117, 8'd142};
				{2'd3, 4'd0}:  inter_decay_factors = {8'd255, 8'd255};
				{2'd3, 4'd1}:  inter_decay_factors = {8'd241, 8'd248};
				{2'd3, 4'd2}:  inter_decay_factors = {8'd229, 8'd242};
				{2'd3, 4'd3}:  inter_decay_factors = {8'd219, 8'd236};
				{2'd3, 4'd4}:  inter_decay_factors = {8'd210, 8'd230};
				{2'd3, 4'd5}:  inter_decay_factors = {8'd202, 8'd224};
				{2'd3, 4'd6}:  inter_decay_factors = {8'd196, 8'd218};
				{2'd3, 4'd7}:  inter_decay_factors = {8'd190, 8'd213};
				{2'd3, 4'd8}:  inter_decay_factors = {8'd184, 8'd207};
				{2'd3, 4'd9}:  inter_decay_factors = {8'd179, 8'd201};
				{2'd3, 4'd10}: inter_decay_factors = {8'd174, 8'd196};
				{2'd3, 4'd11}: inter_decay_factors = {8'd169, 8'd192};
				{2'd3, 4'd12}: inter_decay_factors = {8'd164, 8'd186};
				{2'd3, 4'd13}: inter_decay_factors = {8'd160, 8'd181};
				{2'd3, 4'd14}: inter_decay_factors = {8'd156, 8'd177};
				{2'd3, 4'd15}: inter_decay_factors = {8'd152, 8'd173};
				default: inter_decay_factors = {8'd255, 8'd255};
			endcase
		end
	endfunction

	function automatic [7:0] decay_factor(
		input logic [1:0] mode,
		input logic [3:0] age
	);
		begin
			case ({mode, age})
				{2'd1, 4'd0}:  decay_factor = 8'd255;
				{2'd1, 4'd1}:  decay_factor = 8'd252;
				{2'd1, 4'd2}:  decay_factor = 8'd250;
				{2'd1, 4'd3}:  decay_factor = 8'd247;
				{2'd1, 4'd4}:  decay_factor = 8'd245;
				{2'd1, 4'd5}:  decay_factor = 8'd243;
				{2'd1, 4'd6}:  decay_factor = 8'd240;
				{2'd1, 4'd7}:  decay_factor = 8'd238;
				{2'd1, 4'd8}:  decay_factor = 8'd235;
				{2'd1, 4'd9}:  decay_factor = 8'd233;
				{2'd1, 4'd10}: decay_factor = 8'd231;
				{2'd1, 4'd11}: decay_factor = 8'd228;
				{2'd1, 4'd12}: decay_factor = 8'd226;
				{2'd1, 4'd13}: decay_factor = 8'd224;
				{2'd1, 4'd14}: decay_factor = 8'd222;
				{2'd1, 4'd15}: decay_factor = 8'd219;
				{2'd2, 4'd0}:  decay_factor = 8'd255;
				{2'd2, 4'd1}:  decay_factor = 8'd245;
				{2'd2, 4'd2}:  decay_factor = 8'd235;
				{2'd2, 4'd3}:  decay_factor = 8'd226;
				{2'd2, 4'd4}:  decay_factor = 8'd217;
				{2'd2, 4'd5}:  decay_factor = 8'd208;
				{2'd2, 4'd6}:  decay_factor = 8'd200;
				{2'd2, 4'd7}:  decay_factor = 8'd192;
				{2'd2, 4'd8}:  decay_factor = 8'd184;
				{2'd2, 4'd9}:  decay_factor = 8'd177;
				{2'd2, 4'd10}: decay_factor = 8'd170;
				{2'd2, 4'd11}: decay_factor = 8'd163;
				{2'd2, 4'd12}: decay_factor = 8'd156;
				{2'd2, 4'd13}: decay_factor = 8'd150;
				{2'd2, 4'd14}: decay_factor = 8'd144;
				{2'd2, 4'd15}: decay_factor = 8'd138;
				{2'd3, 4'd0}:  decay_factor = 8'd255;
				{2'd3, 4'd1}:  decay_factor = 8'd250;
				{2'd3, 4'd2}:  decay_factor = 8'd245;
				{2'd3, 4'd3}:  decay_factor = 8'd240;
				{2'd3, 4'd4}:  decay_factor = 8'd235;
				{2'd3, 4'd5}:  decay_factor = 8'd230;
				{2'd3, 4'd6}:  decay_factor = 8'd225;
				{2'd3, 4'd7}:  decay_factor = 8'd221;
				{2'd3, 4'd8}:  decay_factor = 8'd216;
				{2'd3, 4'd9}:  decay_factor = 8'd212;
				{2'd3, 4'd10}: decay_factor = 8'd208;
				{2'd3, 4'd11}: decay_factor = 8'd204;
				{2'd3, 4'd12}: decay_factor = 8'd200;
				{2'd3, 4'd13}: decay_factor = 8'd196;
				{2'd3, 4'd14}: decay_factor = 8'd192;
				{2'd3, 4'd15}: decay_factor = 8'd188;
				default: decay_factor = 8'd255;
			endcase
		end
	endfunction

	typedef enum logic [4:0] {
		COMP_IDLE,
		COMP_WAIT_METADATA,
		COMP_MAP_ISSUE,
		COMP_MAP_WAIT,
		COMP_MAP_DECIDE,
		COMP_OLD_REQUEST,
		COMP_OLD_RECEIVE,
		COMP_RAW_REQUEST,
		COMP_RAW_RECEIVE,
		COMP_PIXEL_PRIME,
		COMP_PIXEL_LOAD,
		COMP_PIXEL_RAW,
		COMP_PIXEL_OLD,
		COMP_PIXEL_BLEND,
		COMP_PIXEL_STORE,
		COMP_PIXEL_DRAIN,
		COMP_WRITE_REQUEST,
		COMP_WRITE_WAIT,
		COMP_MAP_COMMIT,
		COMP_NEXT_TILE,
		COMP_WAIT_REQUEST_LOW
	} comp_state_t;

	comp_state_t state;
	logic [BUF_IDX_W-1:0] source_buf_q;
	logic [BUF_IDX_W-1:0] target_buf_q;
	logic                 has_source_q;
	logic                 source_is_composed_q;
	logic [1:0]           intra_mode_q;
	logic [1:0]           inter_mode_q;
	logic [2:0]           reference_draw_idx_q;
	logic [31:0]          age_map_q;
	logic [7:0]           fresh_decay_factor_q;
	logic [7:0]           tail_decay_factor_q;

	logic [7:0] tile_x;
	logic [7:0] tile_y;
	logic [7:0] tile_columns;
	logic [7:0] tile_rows;
	logic       source_tile_dirty;
	logic       raw_tile_dirty;
	logic       tile_nonzero;

	logic [63:0] source_tile [0:15];
	logic [63:0] raw_tile [0:15];
	logic [63:0] composed_tile [0:15];
	logic [3:0] read_beat;
	logic [3:0] write_beat;
	logic [5:0] pixel_index;
	logic [5:0] lookahead_pixel_index;

	logic [5:0] raw_color_q;
	logic [8:0] raw_intensity_q;
	logic [7:0] raw_factor_q;
	logic       raw_bypass_q;
	logic [16:0] raw_product_q;
	logic [5:0] old_color_q;
	logic [8:0] old_intensity_q;
	logic [7:0] old_factor_q;
	logic [16:0] old_product_q;
	logic [15:0] next_raw_pixel_q;
	logic [15:0] next_old_pixel_q;
	logic [7:0] next_raw_factor_q;
	logic [7:0] next_old_factor_q;
	logic [9:0] blend_energy_q;
	logic [5:0] blend_color_q;   // LOCAL MOD: 6-bit RRGGBB
	logic       blend_fresh_q;
	logic [15:0] pending_pixel_q;
	logic [3:0]  pending_word_q;
	logic [1:0]  pending_lane_q;
	logic        pending_nonzero_q;
	logic        pending_write_q;

	wire [15:0] current_tile_id = {tile_y, tile_x};
	wire [28:0] source_tile_addr = vfb_buffer_base(source_buf_q)
		+ ({13'd0, current_tile_id} << 4);
	wire [28:0] target_tile_addr = vfb_buffer_base(target_buf_q)
		+ ({13'd0, current_tile_id} << 4);

	wire [63:0] raw_word = raw_tile[pixel_index[5:2]];
	wire [63:0] old_word = source_tile[pixel_index[5:2]];
	wire [5:0] pixel_bit_offset = {pixel_index[1:0], 4'b0000};
	wire [15:0] raw_pixel = raw_word[pixel_bit_offset +: 16];
	wire [15:0] old_pixel = old_word[pixel_bit_offset +: 16];
	wire [15:0] selected_inter_factors =
		inter_decay_factors(inter_mode_q, raw_frame_age);
	wire [63:0] next_raw_word = raw_tile[lookahead_pixel_index[5:2]];
	wire [63:0] next_old_word = source_tile[lookahead_pixel_index[5:2]];
	wire [5:0] next_pixel_bit_offset =
		{lookahead_pixel_index[1:0], 4'b0000};
	wire [15:0] next_raw_pixel =
		next_raw_word[next_pixel_bit_offset +: 16];
	wire [15:0] next_old_pixel =
		next_old_word[next_pixel_bit_offset +: 16];
	wire [2:0] staged_raw_age_delta =
		reference_draw_idx_q - next_raw_pixel_q[9:7];
	wire [4:0] staged_raw_age_offset = {staged_raw_age_delta, 2'b00};
	wire [3:0] staged_raw_pixel_age = raw_tile_dirty
		? age_map_q[staged_raw_age_offset +: 4] : 4'd0;
	wire [7:0] staged_raw_factor =
		decay_factor(intra_mode_q, staged_raw_pixel_age);
	wire [8:0] raw_energy = raw_bypass_q
		? raw_intensity_q : raw_product_q[16:8];
	wire [8:0] old_energy = old_product_q[16:8];
	wire       raw_present = (raw_energy != 9'd0);
	wire       old_present = (old_energy != 9'd0);
	wire [8:0] blend_hi = (raw_energy >= old_energy) ? raw_energy : old_energy;
	wire [8:0] blend_lo = (raw_energy >= old_energy) ? old_energy : raw_energy;
	wire [9:0] blend_overlap = {1'b0, blend_hi} + {5'b00000, blend_lo[8:4]};
	wire [9:0] selected_blend_energy =
		(raw_present && old_present) ? blend_overlap :
		raw_present ? {1'b0, raw_energy} :
		old_present ? {1'b0, old_energy} :
		10'd0;
	wire [5:0] selected_blend_color =
		raw_present ? raw_color_q :
		old_present ? old_color_q :
		4'd0;
	wire [8:0] stored_energy = blend_energy_q[9]
		? 9'd511 : blend_energy_q[8:0];
	// LOCAL MOD: { rgb[5:0], fresh, energy[8:0] } — still exactly 16 bits.
	wire [15:0] stored_pixel =
		{blend_color_q, blend_fresh_q, stored_energy};
	wire [5:0] pending_bit_offset = {pending_lane_q, 4'b0000};

	assign read_burstcnt = 8'd16;
	assign write_burstcnt = 8'd16;
	assign write_data = composed_tile[write_beat];
	assign write_be = 8'hff;
	assign tilemap_we = (state == COMP_MAP_COMMIT);
	assign tilemap_buf = target_buf_q;
	assign tilemap_din = tile_nonzero;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			state <= COMP_IDLE;
			compose_done <= 1'b0;
			read_ready <= 1'b0;
			read_addr <= 29'd0;
			write_ready <= 1'b0;
			write_addr <= 29'd0;
			tilemap_addr <= '0;
			source_buf_q <= '0;
			target_buf_q <= '0;
			has_source_q <= 1'b0;
			source_is_composed_q <= 1'b0;
			intra_mode_q <= 2'd0;
			inter_mode_q <= 2'd0;
			reference_draw_idx_q <= 3'd0;
			age_map_q <= 32'd0;
			fresh_decay_factor_q <= 8'd255;
			tail_decay_factor_q <= 8'd255;
			tile_x <= 8'd0;
			tile_y <= 8'd0;
			tile_columns <= 8'd0;
			tile_rows <= 8'd0;
			source_tile_dirty <= 1'b0;
			raw_tile_dirty <= 1'b0;
			tile_nonzero <= 1'b0;
			read_beat <= 4'd0;
			write_beat <= 4'd0;
			pixel_index <= 6'd0;
			lookahead_pixel_index <= 6'd0;
			raw_color_q <= 6'd0;
			raw_intensity_q <= 9'd0;
			raw_factor_q <= 8'd0;
			raw_bypass_q <= 1'b0;
			raw_product_q <= 17'd0;
			old_color_q <= 6'd0;
			old_intensity_q <= 9'd0;
			old_factor_q <= 8'd0;
			old_product_q <= 17'd0;
			next_raw_pixel_q <= 16'd0;
			next_old_pixel_q <= 16'd0;
			next_raw_factor_q <= 8'd0;
			next_old_factor_q <= 8'd0;
			blend_energy_q <= 10'd0;
			blend_color_q <= 6'd0;
			blend_fresh_q <= 1'b0;
			pending_write_q <= 1'b0;
		end else begin
			compose_done <= 1'b0;
			pending_write_q <= 1'b0;

			if (pending_write_q) begin
				composed_tile[pending_word_q][pending_bit_offset +: 16]
					<= pending_pixel_q;
				tile_nonzero <= tile_nonzero | pending_nonzero_q;
			end

			case (state)
				COMP_IDLE: begin
					if (compose_req) begin
						source_buf_q <= compose_source_buf;
						target_buf_q <= compose_target_buf;
						has_source_q <= compose_has_source;
						source_is_composed_q <= compose_source_is_composed;
						intra_mode_q <= intra_frame_mode_q;
						inter_mode_q <= inter_frame_mode_q;
						tile_columns <=
							8'(vfb_tile_columns(render_width));
						tile_rows <=
							8'(vfb_tile_rows(render_height));
						tile_x <= 8'd0;
						tile_y <= 8'd0;
						tilemap_addr <= '0;
						state <= COMP_WAIT_METADATA;
					end
				end

				COMP_WAIT_METADATA: begin
					if (raw_metadata_ready) begin
						reference_draw_idx_q <= raw_reference_draw_idx;
						age_map_q <= raw_age_map;
						fresh_decay_factor_q <= selected_inter_factors[15:8];
						tail_decay_factor_q <= selected_inter_factors[7:0];
						state <= COMP_MAP_ISSUE;
					end
				end

				COMP_MAP_ISSUE: begin
					state <= COMP_MAP_WAIT;
				end

				COMP_MAP_WAIT: begin
					source_tile_dirty <= has_source_q && tilemap_dout[source_buf_q];
					raw_tile_dirty <= tilemap_dout[target_buf_q];
					state <= COMP_MAP_DECIDE;
				end

				COMP_MAP_DECIDE: begin
					if (source_tile_dirty) begin
						read_addr <= source_tile_addr;
						read_ready <= 1'b1;
						state <= COMP_OLD_REQUEST;
					end else if (raw_tile_dirty) begin
						read_addr <= target_tile_addr;
						read_ready <= 1'b1;
						state <= COMP_RAW_REQUEST;
					end else begin
						state <= COMP_NEXT_TILE;
					end
				end

				COMP_OLD_REQUEST: begin
					if (read_grant) begin
						read_ready <= 1'b0;
						read_beat <= 4'd0;
						state <= COMP_OLD_RECEIVE;
					end
				end

				COMP_OLD_RECEIVE: begin
					if (read_data_valid) begin
						source_tile[read_beat] <= read_data;
						if (read_beat == 4'd15) begin
							if (raw_tile_dirty) begin
								read_addr <= target_tile_addr;
								read_ready <= 1'b1;
								state <= COMP_RAW_REQUEST;
							end else begin
								pixel_index <= 6'd0;
								tile_nonzero <= 1'b0;
								state <= COMP_PIXEL_PRIME;
							end
						end else begin
							read_beat <= read_beat + 4'd1;
						end
					end
				end

				COMP_RAW_REQUEST: begin
					if (read_grant) begin
						read_ready <= 1'b0;
						read_beat <= 4'd0;
						state <= COMP_RAW_RECEIVE;
					end
				end

				COMP_RAW_RECEIVE: begin
					if (read_data_valid) begin
						raw_tile[read_beat] <= read_data;
						if (read_beat == 4'd15) begin
							pixel_index <= 6'd0;
							tile_nonzero <= 1'b0;
							state <= COMP_PIXEL_PRIME;
						end else begin
							read_beat <= read_beat + 4'd1;
						end
					end
				end

				COMP_PIXEL_PRIME: begin
					next_raw_pixel_q <= raw_tile_dirty ? raw_pixel : 16'd0;
					next_old_pixel_q <= source_tile_dirty ? old_pixel : 16'd0;
					lookahead_pixel_index <= 6'd1;
					state <= COMP_PIXEL_LOAD;
				end

				COMP_PIXEL_LOAD: begin
					raw_color_q <= next_raw_pixel_q[15:10];
					raw_intensity_q <= next_raw_pixel_q[8:0];
					raw_factor_q <= staged_raw_factor;
					raw_bypass_q <= (intra_mode_q == 2'd0);
					old_color_q <= next_old_pixel_q[15:10];
					old_intensity_q <= next_old_pixel_q[8:0];
					old_factor_q <= (!source_is_composed_q || next_old_pixel_q[11])
						? fresh_decay_factor_q : tail_decay_factor_q;
					state <= COMP_PIXEL_RAW;
				end

				COMP_PIXEL_RAW: begin
					raw_product_q <= raw_intensity_q * raw_factor_q;
					if (pixel_index != 6'd63) begin
						next_raw_pixel_q <= raw_tile_dirty
							? next_raw_pixel : 16'd0;
						next_old_pixel_q <= source_tile_dirty
							? next_old_pixel : 16'd0;
					end
					state <= COMP_PIXEL_OLD;
				end

				COMP_PIXEL_OLD: begin
					old_product_q <= old_intensity_q * old_factor_q;
					if (pixel_index != 6'd63) begin
						next_raw_factor_q <= staged_raw_factor;
						next_old_factor_q <=
							(!source_is_composed_q || next_old_pixel_q[11])
							? fresh_decay_factor_q : tail_decay_factor_q;
					end
					state <= COMP_PIXEL_BLEND;
				end

				COMP_PIXEL_BLEND: begin
					blend_energy_q <= selected_blend_energy;
					blend_color_q <= selected_blend_color;
					blend_fresh_q <= raw_present;
					state <= COMP_PIXEL_STORE;
				end

				COMP_PIXEL_STORE: begin
					pending_pixel_q <= stored_pixel;
					pending_word_q <= pixel_index[5:2];
					pending_lane_q <= pixel_index[1:0];
					pending_nonzero_q <= (stored_energy != 9'd0);
					pending_write_q <= 1'b1;
					if (pixel_index == 6'd63) begin
						state <= COMP_PIXEL_DRAIN;
					end else begin
						pixel_index <= pixel_index + 6'd1;
						lookahead_pixel_index <=
							lookahead_pixel_index + 6'd1;
						raw_color_q <= next_raw_pixel_q[15:10];
						raw_intensity_q <= next_raw_pixel_q[8:0];
						raw_factor_q <= next_raw_factor_q;
						raw_bypass_q <= (intra_mode_q == 2'd0);
						old_color_q <= next_old_pixel_q[15:10];
						old_intensity_q <= next_old_pixel_q[8:0];
						old_factor_q <= next_old_factor_q;
						state <= COMP_PIXEL_RAW;
					end
				end

				COMP_PIXEL_DRAIN: begin
					write_addr <= target_tile_addr;
					write_ready <= 1'b1;
					write_beat <= 4'd0;
					state <= COMP_WRITE_REQUEST;
				end

				COMP_WRITE_REQUEST: begin
					if (write_grant) begin
						write_ready <= 1'b0;
						if (write_advance && write_beat != 4'd15)
							write_beat <= write_beat + 4'd1;
						state <= COMP_WRITE_WAIT;
					end
				end

				COMP_WRITE_WAIT: begin
					if (write_advance && write_beat != 4'd15)
						write_beat <= write_beat + 4'd1;
					if (write_done)
						state <= COMP_MAP_COMMIT;
				end

				COMP_MAP_COMMIT: begin
					state <= COMP_NEXT_TILE;
				end

				COMP_NEXT_TILE: begin
					if ((tile_x + 8'd1 >= tile_columns) &&
					    (tile_y + 8'd1 >= tile_rows)) begin
						compose_done <= 1'b1;
						state <= COMP_WAIT_REQUEST_LOW;
					end else if (tile_x + 8'd1 >= tile_columns) begin
						tile_x <= 8'd0;
						tile_y <= tile_y + 8'd1;
						tilemap_addr <=
							vfb_tile_row_addr(tile_y + 8'd1);
						state <= COMP_MAP_ISSUE;
					end else begin
						tile_x <= tile_x + 8'd1;
						tilemap_addr <= tilemap_addr + 15'd1;
						state <= COMP_MAP_ISSUE;
					end
				end

				COMP_WAIT_REQUEST_LOW: begin
					if (!compose_req)
						state <= COMP_IDLE;
				end

				default: state <= COMP_IDLE;
			endcase
		end
	end

endmodule
