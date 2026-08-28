`timescale 1ns / 1ps

// ============================================================================
// Sparse framebuffer ownership controller.
// written 2026 by Videodr0me
//
// Raw frames follow CLEAN -> DRAWING -> DRAWN. With inter-frame decay off,
// a DRAWN frame can be shown at the selected boundary. With decay enabled,
// each raw frame is composed before it can be shown.
// ============================================================================

module vfb_buffer_controller #(
	parameter integer BUFFER_COUNT = 5,
	parameter integer BUF_IDX_W = 3
) (
	input  logic clk_sys,
	input  logic reset,

	// 0 = EOF + VBL, 1 = VBL only, 2 = EOF only
	input  logic [1:0] BUFFER_MODE,
	input  logic [1:0] inter_frame_mode,

	input  logic eof_token_popped,
	input  logic vbl_swap_req,

	output logic flush_req,
	input  logic flush_done,

	output logic                 clear_req,
	output logic [BUF_IDX_W-1:0] clear_buf_idx,
	input  logic                 clear_done,

	output logic                 compose_req,
	output logic [BUF_IDX_W-1:0] compose_source_buf,
	output logic [BUF_IDX_W-1:0] compose_target_buf,
	output logic                 compose_has_source,
	output logic                 compose_source_is_composed,
	input  logic                 compose_done,

	output logic [BUF_IDX_W-1:0] buf_draw,
	output logic [BUF_IDX_W-1:0] buf_display_out,
	output logic                 display_valid,
	output logic                 display_is_composed,
	output logic                 has_draw_buf,
	output logic                 raw_frame_dropped,
	output logic [BUF_IDX_W-1:0] raw_frame_dropped_buf
);

	typedef enum logic [3:0] {
		ST_DISPLAY,
		ST_DRAWING,
		ST_DRAWN,
		ST_COMPOSING,
		ST_COMPOSED,
		ST_DIRTY,
		ST_CLEARING,
		ST_CLEAN
	} buf_state_t;

	buf_state_t buf_state [0:BUFFER_COUNT-1];
	logic [BUFFER_COUNT-1:0] completion_order [0:BUFFER_COUNT-1];
	logic       buffer_is_composed [0:BUFFER_COUNT-1];

	logic                 accumulator_valid;
	logic [BUF_IDX_W-1:0] accumulator_buf;
	logic                 compose_active;
	logic                 inter_enabled_q;
	logic [1:0]           buffer_mode_q = 2'd0;
	logic [1:0]           inter_frame_mode_q = 2'd0;

	always_ff @(posedge clk_sys) begin
		buffer_mode_q <= BUFFER_MODE;
		inter_frame_mode_q <= inter_frame_mode;
	end

	logic                 has_display;
	logic                 has_drawing;
	logic                 has_drawn;
	logic                 has_dirty;
	logic                 has_clean;
	logic [BUFFER_COUNT-1:0] drawn_mask;
	logic [BUFFER_COUNT-1:0] drawn_by_age;
	logic [BUFFER_COUNT-1:0] drawn_at_age [0:BUFFER_COUNT-1];
	logic [BUFFER_COUNT-1:0] oldest_drawn_onehot;
	logic [BUFFER_COUNT-1:0] newest_drawn_onehot;
	logic [BUF_IDX_W-1:0] display_idx;
	logic [BUF_IDX_W-1:0] oldest_drawn_idx;
	logic [BUF_IDX_W-1:0] dirty_idx;
	logic [BUF_IDX_W-1:0] clean_idx;
	logic                 dirty_found;
	logic                 clean_found;

	function automatic logic [BUFFER_COUNT-1:0] index_to_onehot(
		input logic [BUF_IDX_W-1:0] index
	);
		begin
			index_to_onehot = '0;
			index_to_onehot[index] = 1'b1;
		end
	endfunction

	function automatic logic [BUF_IDX_W-1:0] onehot_to_index(
		input logic [BUFFER_COUNT-1:0] onehot
	);
		begin
			onehot_to_index = '0;
			for (int i = 0; i < BUFFER_COUNT; i++) begin
				if (onehot[i])
					onehot_to_index = BUF_IDX_W'(i);
			end
		end
	endfunction

	always_comb begin
		has_display = 1'b0;
		has_drawing = 1'b0;
		has_drawn = 1'b0;
		has_dirty = 1'b0;
		has_clean = 1'b0;
		drawn_mask = '0;
		display_idx = '0;
		dirty_idx = '0;
		clean_idx = '0;
		dirty_found = 1'b0;
		clean_found = 1'b0;

		for (int i = 0; i < BUFFER_COUNT; i++) begin
			if (buf_state[i] == ST_DISPLAY) begin
				has_display = 1'b1;
				display_idx = BUF_IDX_W'(i);
			end

			if (buf_state[i] == ST_DRAWING)
				has_drawing = 1'b1;

			if (buf_state[i] == ST_DRAWN) begin
				has_drawn = 1'b1;
				drawn_mask[i] = 1'b1;
			end

			if (buf_state[i] == ST_DIRTY) begin
				has_dirty = 1'b1;
				if (!dirty_found) begin
					dirty_found = 1'b1;
					dirty_idx = BUF_IDX_W'(i);
				end
			end

			if (buf_state[i] == ST_CLEAN) begin
				has_clean = 1'b1;
				if (!clean_found) begin
					clean_found = 1'b1;
					clean_idx = BUF_IDX_W'(i);
				end
			end
		end
	end

	always_comb begin
		for (int age = 0; age < BUFFER_COUNT; age++) begin
			drawn_at_age[age] = completion_order[age] & drawn_mask;
			drawn_by_age[age] = |drawn_at_age[age];
		end

		oldest_drawn_onehot =
			drawn_at_age[0] |
			({BUFFER_COUNT{~drawn_by_age[0]}} &
			 drawn_at_age[1]) |
			({BUFFER_COUNT{~(|drawn_by_age[1:0])}} &
			 drawn_at_age[2]) |
			({BUFFER_COUNT{~(|drawn_by_age[2:0])}} &
			 drawn_at_age[3]) |
			({BUFFER_COUNT{~(|drawn_by_age[3:0])}} &
			 drawn_at_age[4]);

		newest_drawn_onehot =
			drawn_at_age[4] |
			({BUFFER_COUNT{~drawn_by_age[4]}} &
			 drawn_at_age[3]) |
			({BUFFER_COUNT{~(|drawn_by_age[4:3])}} &
			 drawn_at_age[2]) |
			({BUFFER_COUNT{~(|drawn_by_age[4:2])}} &
			 drawn_at_age[1]) |
			({BUFFER_COUNT{~(|drawn_by_age[4:1])}} &
			 drawn_at_age[0]);

		oldest_drawn_idx = onehot_to_index(oldest_drawn_onehot);
	end

	logic [BUF_IDX_W-1:0] internal_buf_draw;
	logic [BUF_IDX_W-1:0] buf_display_reg;
	logic                 has_draw_buf_reg;
	logic                 display_valid_reg;
	logic                 display_composed_reg;

	assign buf_draw = internal_buf_draw;
	assign buf_display_out = buf_display_reg;
	assign has_draw_buf = has_draw_buf_reg;
	assign display_valid = display_valid_reg;
	assign display_is_composed = display_composed_reg;
	assign compose_req = compose_active;

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			buf_display_reg <= '0;
			has_draw_buf_reg <= 1'b0;
			display_valid_reg <= 1'b0;
			display_composed_reg <= 1'b0;
		end else begin
			buf_display_reg <= display_idx;
			has_draw_buf_reg <= has_drawing;
			display_valid_reg <= has_display;
			display_composed_reg <= buffer_is_composed[display_idx];
		end
	end

	logic flush_in_progress;
	logic flush_pending;

	wire inter_enabled = (inter_frame_mode_q != 2'd0);
	wire inter_enable_rise = inter_enabled && !inter_enabled_q;
	wire inter_enable_fall = !inter_enabled && inter_enabled_q;
	wire evt_flush_complete = flush_in_progress && flush_done;
	wire select_vbl_promote_raw = vbl_swap_req &&
	                              (buffer_mode_q == 2'd0) &&
	                              !inter_enabled;
	wire evt_vbl_promote_raw = select_vbl_promote_raw && has_drawn;
	wire evt_vbl_promote_composed = vbl_swap_req && (buffer_mode_q != 2'd2) &&
	                                inter_enabled && accumulator_valid &&
	                                (buf_state[accumulator_buf] == ST_COMPOSED);
	wire select_compose_start = inter_enabled && !inter_enable_rise &&
	                            !compose_active;
	wire evt_compose_start = select_compose_start && has_drawn;
	wire evt_compose_complete = compose_active && compose_done;
	wire evt_assign_draw = !has_drawing && has_clean && !flush_in_progress;
	wire evt_clear_complete = clear_req && clear_done;
	wire evt_clear_start = !clear_req && has_dirty;
	wire select_drop_raw = inter_enabled && compose_active && !has_drawing &&
	                       !has_clean && !has_dirty && !clear_req;
	wire evt_drop_raw = select_drop_raw && has_drawn;

	logic [BUFFER_COUNT-1:0] completed_buffer_onehot;
	logic [BUFFER_COUNT-1:0] completed_order_position;
	always_comb begin
		completed_buffer_onehot = index_to_onehot(internal_buf_draw);
		for (int age = 0; age < BUFFER_COUNT; age++)
			completed_order_position[age] =
				|(completion_order[age] & completed_buffer_onehot);
	end

	always_ff @(posedge clk_sys) begin
		if (reset) begin
			buf_state[0] <= ST_DISPLAY;
			buf_state[1] <= ST_DRAWING;
			for (int i = 2; i < BUFFER_COUNT; i++)
				buf_state[i] <= ST_DIRTY;

			for (int i = 0; i < BUFFER_COUNT; i++) begin
				completion_order[i] <= index_to_onehot(BUF_IDX_W'(i));
				buffer_is_composed[i] <= 1'b0;
			end

			internal_buf_draw <= BUF_IDX_W'(1);
			flush_req <= 1'b0;
			flush_in_progress <= 1'b0;
			flush_pending <= 1'b0;
			clear_req <= 1'b0;
			clear_buf_idx <= '0;
			compose_active <= 1'b0;
			compose_source_buf <= '0;
			compose_target_buf <= '0;
			compose_has_source <= 1'b0;
			compose_source_is_composed <= 1'b0;
			accumulator_valid <= 1'b0;
			accumulator_buf <= '0;
			inter_enabled_q <= inter_enabled;
			raw_frame_dropped <= 1'b0;
			raw_frame_dropped_buf <= '0;
		end else begin
			inter_enabled_q <= inter_enabled;
			raw_frame_dropped <= evt_drop_raw;
			if (evt_drop_raw)
				raw_frame_dropped_buf <= oldest_drawn_idx;

			if (buffer_mode_q == 2'd1) begin
				if (vbl_swap_req && has_drawing)
					flush_pending <= 1'b1;
			end else if (eof_token_popped && has_drawing) begin
				flush_pending <= 1'b1;
			end

			if (evt_flush_complete) begin
				flush_req <= 1'b0;
				flush_in_progress <= 1'b0;
			end else if (!flush_in_progress && flush_pending) begin
				flush_req <= 1'b1;
				flush_in_progress <= 1'b1;
				flush_pending <= 1'b0;
			end

			for (int i = 0; i < BUFFER_COUNT; i++) begin
				if (evt_compose_complete &&
				    (BUF_IDX_W'(i) == compose_target_buf)) begin
					if (!inter_enabled)
						buf_state[i] <= ST_DRAWN;
					else
						buf_state[i] <= (buffer_mode_q == 2'd2)
						              ? ST_DISPLAY : ST_COMPOSED;
				end else if (evt_compose_complete &&
				             inter_enabled &&
				             (buffer_mode_q == 2'd2) &&
				             (buf_state[i] == ST_DISPLAY)) begin
					buf_state[i] <= ST_DIRTY;
				end else if (evt_compose_complete && compose_has_source &&
				             (BUF_IDX_W'(i) == compose_source_buf) &&
				             (buf_state[i] == ST_COMPOSED) &&
				             !evt_vbl_promote_composed) begin
					buf_state[i] <= ST_DIRTY;
				end else if (inter_enable_fall &&
				             (buf_state[i] == ST_COMPOSED)) begin
					buf_state[i] <= ST_DRAWN;
				end else if (evt_vbl_promote_composed &&
				             (BUF_IDX_W'(i) == accumulator_buf)) begin
					buf_state[i] <= ST_DISPLAY;
				end else if (evt_vbl_promote_composed &&
				             (buf_state[i] == ST_DISPLAY)) begin
					buf_state[i] <= ST_DIRTY;
				end else if (select_vbl_promote_raw &&
				             newest_drawn_onehot[i]) begin
					buf_state[i] <= ST_DISPLAY;
				end else if (evt_vbl_promote_raw &&
				             (buf_state[i] == ST_DISPLAY)) begin
					buf_state[i] <= ST_DIRTY;
				end else if (evt_flush_complete &&
				             (BUF_IDX_W'(i) == internal_buf_draw)) begin
					buf_state[i] <= inter_enabled ? ST_DRAWN :
					                ((buffer_mode_q == 2'd0) ? ST_DRAWN : ST_DISPLAY);
				end else if (evt_flush_complete && !inter_enabled &&
				             (buffer_mode_q != 2'd0) &&
				             (buf_state[i] == ST_DISPLAY)) begin
					buf_state[i] <= ST_DIRTY;
				end else if (select_compose_start &&
				             oldest_drawn_onehot[i]) begin
					buf_state[i] <= ST_COMPOSING;
				end else if (!inter_enabled && (buf_state[i] == ST_DRAWN) &&
				             ((buffer_mode_q != 2'd0) || evt_flush_complete ||
				              evt_vbl_promote_raw)) begin
					buf_state[i] <= ST_DIRTY;
				end else if (select_drop_raw &&
				             oldest_drawn_onehot[i]) begin
					buf_state[i] <= ST_DIRTY;
				end else if (evt_assign_draw &&
				             (BUF_IDX_W'(i) == clean_idx)) begin
					buf_state[i] <= ST_DRAWING;
				end else if (evt_clear_complete &&
				             (BUF_IDX_W'(i) == clear_buf_idx)) begin
					buf_state[i] <= ST_CLEAN;
				end else if (evt_clear_start &&
				             (BUF_IDX_W'(i) == dirty_idx)) begin
					buf_state[i] <= ST_CLEARING;
				end
			end

			if (evt_flush_complete) begin
				case (completed_order_position)
					5'b00001: begin
						completion_order[0] <= completion_order[1];
						completion_order[1] <= completion_order[2];
						completion_order[2] <= completion_order[3];
						completion_order[3] <= completion_order[4];
						completion_order[4] <= completed_buffer_onehot;
					end
					5'b00010: begin
						completion_order[1] <= completion_order[2];
						completion_order[2] <= completion_order[3];
						completion_order[3] <= completion_order[4];
						completion_order[4] <= completed_buffer_onehot;
					end
					5'b00100: begin
						completion_order[2] <= completion_order[3];
						completion_order[3] <= completion_order[4];
						completion_order[4] <= completed_buffer_onehot;
					end
					5'b01000: begin
						completion_order[3] <= completion_order[4];
						completion_order[4] <= completed_buffer_onehot;
					end
					default: begin
					end
				endcase
			end

			if (evt_compose_start) begin
				compose_active <= 1'b1;
				compose_target_buf <= oldest_drawn_idx;
				compose_source_buf <= accumulator_buf;
				compose_has_source <= accumulator_valid;
				compose_source_is_composed <= accumulator_valid &&
					buffer_is_composed[accumulator_buf];
			end else if (evt_compose_complete) begin
				compose_active <= 1'b0;
			end

			if (evt_compose_complete) begin
				accumulator_valid <= inter_enabled;
				if (inter_enabled)
					accumulator_buf <= compose_target_buf;
			end else if (inter_enable_rise) begin
				accumulator_valid <= has_display;
				accumulator_buf <= display_idx;
			end else if (inter_enable_fall) begin
				accumulator_valid <= 1'b0;
			end

			if (evt_compose_complete)
				buffer_is_composed[compose_target_buf] <= 1'b1;
			if (evt_assign_draw)
				buffer_is_composed[clean_idx] <= 1'b0;
			if (evt_clear_complete)
				buffer_is_composed[clear_buf_idx] <= 1'b0;

			if (evt_assign_draw)
				internal_buf_draw <= clean_idx;

			if (evt_clear_complete) begin
				clear_req <= 1'b0;
			end else if (evt_clear_start) begin
				clear_req <= 1'b1;
				clear_buf_idx <= dirty_idx;
			end
		end
	end

endmodule
