// ============================================================================
// Tile-based sparse vector framebuffer and CRT effect pipeline.
// written 2026 by Videodr0me
// ============================================================================

module vfb_top (
	input         clk_sys,
	input         clk_source,
	input         source_tick,
	input         reset,
	input         video_timing_reset, // Resyncs readout, filters, and output without resetting the framebuffer.

	// Vector input
	input  [10:0] X_VECTOR,
	input  [10:0] Y_VECTOR,
	input  [7:0]  Z_VECTOR,
	input  [5:0]  COLOR,   // LOCAL MOD: 6-bit RRGGBB, 2 bits per gun
	input         IS_DOT,
	input         BEAM_ON,

	// Framebuffer DDRAM
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	// Compressed primary delay
	input  [15:0] SDRAM_DQ_IN,
	output [15:0] SDRAM_DQ_OUT,
	output        SDRAM_DQ_OE,
	output        SDRAM_CKE,
	output        SDRAM_nCS,
	output        SDRAM_nRAS,
	output        SDRAM_nCAS,
	output        SDRAM_nWE,
	output  [1:0] SDRAM_DQM,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,

	// Raster dimensions
	input [11:0]  RENDER_WIDTH,
	input [11:0]  RENDER_HEIGHT,

	// Video timing and output
	output logic [7:0]  VGA_R,
	output logic [7:0]  VGA_G,
	output logic [7:0]  VGA_B,
	output logic        VGA_HS,
	output logic        VGA_VS,
	output logic        VGA_HBLANK,
	output logic        VGA_VBLANK,

	input  [10:0] h_cnt,
	input  [10:0] v_cnt,
	input         ce_pix,
	input         hsync,
	input         vsync,
	input         hblank,
	input         vblank,

	// Frame, buffer, and CRT controls
	input  [7:0]  FLASH_PARAM,
	input         OSD_120HZ,
	input         FRAME_DONE,
	input   [1:0] BUFFER_MODE,
	input   [2:0] DOT_MODE,
	output        FIFO_FULL_LED,

	input  [2:0]  osd_bloom_width,
	input  [2:0]  osd_bloom_curve,
	input         osd_expand_highlights,
	input  [2:0]  osd_halo_filter,
	input  [2:0]  osd_halo_curve,
	input  [1:0]  osd_halo_knee,
	input  [1:0]  osd_phosphor_mode,    // 0=Off, 1=LUT A, 2=LUT B, 3=LUT C
	input  [1:0]  osd_inter_frame_phosphor_mode,
	input  [1:0]  osd_halo_spread,
	input         osd_color_space,
	input  [2:0]  osd_presentation_color,
	input         osd_slot_mask,
	input         osd_slot_mask_rows,
	input         osd_full_bypass
);

	import vfb_layout_pkg::*;

	localparam TILE_SIZE = VFB_TILE_SIZE;
	localparam CACHE_COUNT = 4; // Four cache slots in this integration.
	localparam BUFFER_COUNT = VFB_BUFFER_COUNT;
	localparam BUF_IDX_W = 3;
	localparam TILEMAP_ADDR_W = 15;

	// Rasterizer and tile cache
	logic        pixel_valid;
	logic        pixel_ready;
	logic [15:0] pixel_tile_id;
	logic [5:0]  pixel_offset;
	logic [15:0] pixel_data;
	wire rasterizer_fifo_full_led;


	// Readout and DDRAM arbiter
	wire        readout_ready;
	wire        readout_grant;
	wire [15:0] readout_tile_id;
	wire [63:0] readout_data;
	wire        readout_data_valid;
	wire        flush_done_arbiter;

	// End-of-frame timing
	wire        eof_token;
	wire        eof_token_popped;
	wire [15:0] eof_frame_tick_clks_popped;
	wire [15:0] eof_elapsed_frame_tick_clks_popped;
	wire [15:0] eof_completed_frame_tick_clks;

	// VBLANK display request
	wire        vbl_swap_req;

	wire [BUF_IDX_W-1:0] buf_display;
	wire [BUF_IDX_W-1:0] buf_draw;
	wire        arbiter_idle;
	wire        arbiter_reset_busy;

	// Reset framebuffer and DDRAM clients.
	assign DDRAM_CLK = clk_sys;

	logic        osd_120hz_vid = 1'b0;
	logic [1:0]  buffer_mode_vid = 2'd0;
	logic [2:0]  dot_mode_vid = 3'd0;
	logic [1:0]  inter_frame_mode_vid = 2'd0;
	logic [1:0]  osd_halo_knee_vid = 2'd0;
	logic [2:0]  osd_bloom_width_vid = 3'd0;
	logic [1:0]  osd_phosphor_mode_vid = 2'd0;
	logic [1:0]  osd_halo_spread_vid = 2'd0;
	logic        osd_color_space_vid = 1'b0;
	logic [2:0]  osd_presentation_color_vid = 3'd0;
	logic        osd_slot_mask_vid = 1'b0;
	logic        osd_slot_mask_rows_vid = 1'b0;
	logic        osd_full_bypass_vid = 1'b0;
	logic        osd_expand_highlights_vid = 1'b0;

	wire fb_reset_request = reset;
	wire fb_client_reset = fb_reset_request | arbiter_reset_busy;

	logic filter_reset_q = 1'b1;
	always_ff @(posedge clk_sys)
		filter_reset_q <= fb_reset_request | video_timing_reset;

	// Measure frame timing in source clocks and store each frame's draw duration.
	wire [2:0]  draw_idx;
	wire [15:0] active_frame_tick_clks;
	wire [15:0] completed_frame_tick_clks;
	wire [2:0]  readout_draw_idx;
	wire [31:0] readout_age_map;
	wire                 compose_req;
	wire                 compose_done;
	wire [BUF_IDX_W-1:0] compose_source_buf;
	wire [BUF_IDX_W-1:0] compose_target_buf;
	wire                 compose_has_source;
	wire                 compose_source_is_composed;
	wire                 raw_frame_dropped;
	wire [BUF_IDX_W-1:0] raw_frame_dropped_buf;
	wire [2:0]           compose_draw_idx;
	wire [31:0]          compose_age_map;
	wire [3:0]           compose_frame_age;
	wire                 compose_metadata_ready;

	vfb_phosphor_timing #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) phosphor_timing_inst (
		.clk_source(clk_source),
		.source_tick(source_tick),
		.clk_sys(clk_sys),
		.reset_source(reset),
		.reset_sys(fb_client_reset),
		.frame_done(FRAME_DONE),

		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.eof_elapsed_frame_tick_clks_popped(eof_elapsed_frame_tick_clks_popped),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.vbl_swap_req(vbl_swap_req),
		.presentation_120hz(osd_120hz_vid),
		.BUFFER_MODE(buffer_mode_vid),
		.compose_req(compose_req),
		.compose_buf(compose_target_buf),
		.raw_frame_dropped(raw_frame_dropped),
		.raw_frame_dropped_buf(raw_frame_dropped_buf),
		.compose_draw_idx(compose_draw_idx),
		.compose_age_map(compose_age_map),
		.compose_frame_age(compose_frame_age),
		.compose_metadata_ready(compose_metadata_ready),

		.draw_idx(draw_idx),
		.active_frame_tick_clks(active_frame_tick_clks),
		.completed_frame_tick_clks(completed_frame_tick_clks),
		.readout_draw_idx(readout_draw_idx),
		.readout_age_map(readout_age_map)
	);

	vfb_rasterizer #(
		.TILE_SIZE(TILE_SIZE)
	) rasterizer_inst (
		.clk_sys(clk_sys),
		.clk_source(clk_source),
		.reset(fb_client_reset),

		// Vector input
		.X_VECTOR(X_VECTOR),
		.Y_VECTOR(Y_VECTOR),
		.Z_VECTOR(Z_VECTOR),
		.COLOR(COLOR),
		.IS_DOT(IS_DOT),
		.BEAM_ON(BEAM_ON),
		.FRAME_DONE(FRAME_DONE),
		.DOT_MODE(dot_mode_vid),
		.FB_WIDTH(RENDER_WIDTH),
		.FB_HEIGHT(RENDER_HEIGHT),

		// Tile cache output
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),
		.draw_idx(draw_idx),
		.frame_tick_clks(active_frame_tick_clks),
		.completed_frame_tick_clks(completed_frame_tick_clks),


		.eof_token(eof_token),
		.eof_completed_frame_tick_clks(eof_completed_frame_tick_clks),
		.fifo_full_led(rasterizer_fifo_full_led),
		.fifo_empty()
	);

	// Internal connections
	wire        fill_ready, fill_grant;
	wire [28:0] fill_addr;
	wire [7:0]  fill_burstcnt;
	wire [63:0] fill_data;
	wire        fill_data_valid;

	wire        flush_ready, flush_grant, flush_done, flush_advance;
	wire [28:0] flush_addr;
	wire [7:0]  flush_burstcnt;
	wire [63:0] flush_din;
	wire [7:0]  flush_be;

	wire [14:0] display_tile_addr;
	wire        display_tile_dirty;

	wire flush_req;
	wire clear_req;
	wire [BUF_IDX_W-1:0] clear_buf_idx;
	wire clear_done;
	wire has_draw_buf;
	wire display_valid;
	wire display_is_composed;
	wire [TILEMAP_ADDR_W-1:0] compose_tilemap_addr;
	wire compose_tilemap_we;
	wire [BUF_IDX_W-1:0] compose_tilemap_buf;
	wire compose_tilemap_din;
	wire [BUFFER_COUNT-1:0] compose_tilemap_dout;

	wire [28:0] display_buf_base = vfb_buffer_base(buf_display);

	vfb_buffer_controller #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) buffer_controller_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.BUFFER_MODE(buffer_mode_vid),
		.inter_frame_mode(inter_frame_mode_vid),

		.eof_token_popped(eof_token_popped),
		.vbl_swap_req(vbl_swap_req),

		.flush_req(flush_req),
		.flush_done(flush_done),

		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.compose_req(compose_req),
		.compose_source_buf(compose_source_buf),
		.compose_target_buf(compose_target_buf),
		.compose_has_source(compose_has_source),
		.compose_source_is_composed(compose_source_is_composed),
		.compose_done(compose_done),

		.buf_draw(buf_draw),
		.buf_display_out(buf_display),
		.display_valid(display_valid),
		.display_is_composed(display_is_composed),

		.has_draw_buf(has_draw_buf),
		.raw_frame_dropped(raw_frame_dropped),
		.raw_frame_dropped_buf(raw_frame_dropped_buf)
	);

	assign FIFO_FULL_LED = rasterizer_fifo_full_led;

	vfb_tile_cache_manager #(
		.TILE_SIZE(TILE_SIZE),
		.CACHE_COUNT(CACHE_COUNT),
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W)
	) cache_manager_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),

		.FB_HEIGHT(RENDER_HEIGHT),

		// Rasterizer
		.pixel_valid(pixel_valid),
		.pixel_ready(pixel_ready),
		.pixel_tile_id(pixel_tile_id),
		.pixel_offset(pixel_offset),
		.pixel_data(pixel_data),

		.eof_token(eof_token),
		.eof_completed_frame_tick_clks(eof_completed_frame_tick_clks),

		// Buffer controller
		.eof_token_popped(eof_token_popped),
		.eof_frame_tick_clks_popped(eof_frame_tick_clks_popped),
		.eof_elapsed_frame_tick_clks_popped(eof_elapsed_frame_tick_clks_popped),
		.flush_req(flush_req),
		.flush_done(flush_done),
		.clear_req(clear_req),
		.clear_buf_idx(clear_buf_idx),
		.clear_done(clear_done),
		.buf_draw(buf_draw),
		.buf_display(buf_display),
		.display_valid(display_valid),
		.has_draw_buf(has_draw_buf),

		// DDRAM arbiter
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done_in(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),

		.display_tile_addr(display_tile_addr),
		.display_tile_dirty(display_tile_dirty),
		.compose_tilemap_addr(compose_tilemap_addr),
		.compose_tilemap_we(compose_tilemap_we),
		.compose_tilemap_buf(compose_tilemap_buf),
		.compose_tilemap_din(compose_tilemap_din),
		.compose_tilemap_dout(compose_tilemap_dout)
	);

	wire [28:0] readout_addr = display_buf_base + ({13'd0, readout_tile_id} << 4);
	wire [8:0] readout_burstcnt;

	wire        compose_read_ready;
	wire        compose_read_grant;
	wire [28:0] compose_read_addr;
	wire [7:0]  compose_read_burstcnt;
	wire [63:0] compose_read_data;
	wire        compose_read_data_valid;
	wire        compose_write_ready;
	wire        compose_write_grant;
	wire        compose_write_done;
	wire [28:0] compose_write_addr;
	wire [7:0]  compose_write_burstcnt;
	wire [63:0] compose_write_data;
	wire [7:0]  compose_write_be;
	wire        compose_write_advance;

	vfb_phosphor_compositor #(
		.BUFFER_COUNT(BUFFER_COUNT),
		.BUF_IDX_W(BUF_IDX_W),
		.TILEMAP_ADDR_W(TILEMAP_ADDR_W)
	) phosphor_compositor_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset),
		.render_width(RENDER_WIDTH),
		.render_height(RENDER_HEIGHT),
		.intra_frame_mode(osd_phosphor_mode_vid),
		.inter_frame_mode(inter_frame_mode_vid),
		.compose_req(compose_req),
		.compose_source_buf(compose_source_buf),
		.compose_target_buf(compose_target_buf),
		.compose_has_source(compose_has_source),
		.compose_source_is_composed(compose_source_is_composed),
		.compose_done(compose_done),
		.raw_reference_draw_idx(compose_draw_idx),
		.raw_age_map(compose_age_map),
		.raw_frame_age(compose_frame_age),
		.raw_metadata_ready(compose_metadata_ready),
		.tilemap_addr(compose_tilemap_addr),
		.tilemap_we(compose_tilemap_we),
		.tilemap_buf(compose_tilemap_buf),
		.tilemap_din(compose_tilemap_din),
		.tilemap_dout(compose_tilemap_dout),
		.read_ready(compose_read_ready),
		.read_grant(compose_read_grant),
		.read_addr(compose_read_addr),
		.read_burstcnt(compose_read_burstcnt),
		.read_data(compose_read_data),
		.read_data_valid(compose_read_data_valid),
		.write_ready(compose_write_ready),
		.write_grant(compose_write_grant),
		.write_done(compose_write_done),
		.write_addr(compose_write_addr),
		.write_burstcnt(compose_write_burstcnt),
		.write_data(compose_write_data),
		.write_be(compose_write_be),
		.write_advance(compose_write_advance)
	);

	vfb_ddr_arbiter ddr_arbiter_inst (
		.clk_sys(clk_sys),
		.rst_sys(fb_reset_request),

		// DDRAM Avalon-MM
		.DDRAM_BUSY(DDRAM_BUSY),
		.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
		.DDRAM_ADDR(DDRAM_ADDR),
		.DDRAM_RD(DDRAM_RD),
		.DDRAM_WE(DDRAM_WE),
		.DDRAM_DIN(DDRAM_DIN),
		.DDRAM_BE(DDRAM_BE),
		.DDRAM_DOUT(DDRAM_DOUT),
		.DDRAM_DOUT_READY(DDRAM_DOUT_READY),

		// Readout
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_addr(readout_addr),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		// Fill
		.fill_ready(fill_ready),
		.fill_grant(fill_grant),
		.fill_addr(fill_addr),
		.fill_burstcnt(fill_burstcnt),
		.fill_data(fill_data),
		.fill_data_valid(fill_data_valid),

		// Flush
		.flush_ready(flush_ready),
		.flush_grant(flush_grant),
		.flush_done(flush_done_arbiter),
		.flush_addr(flush_addr),
		.flush_burstcnt(flush_burstcnt),
		.flush_din(flush_din),
		.flush_be(flush_be),
		.flush_advance(flush_advance),
		.compose_read_ready(compose_read_ready),
		.compose_read_grant(compose_read_grant),
		.compose_read_addr(compose_read_addr),
		.compose_read_burstcnt(compose_read_burstcnt),
		.compose_read_data(compose_read_data),
		.compose_read_data_valid(compose_read_data_valid),
		.compose_write_ready(compose_write_ready),
		.compose_write_grant(compose_write_grant),
		.compose_write_done(compose_write_done),
		.compose_write_addr(compose_write_addr),
		.compose_write_burstcnt(compose_write_burstcnt),
		.compose_write_data(compose_write_data),
		.compose_write_be(compose_write_be),
		.compose_write_advance(compose_write_advance),

		.arbiter_idle(arbiter_idle),
		.reset_busy(arbiter_reset_busy)
	);

	wire [7:0] raw_vga_r;
	wire [7:0] raw_vga_g;
	wire [7:0] raw_vga_b;
	wire       raw_vga_hs;
	wire       raw_vga_vs;
	wire       raw_vga_hblank;
	wire       raw_vga_vblank;

	// Synchronize menu options.
	wire [33:0] osd_control_in = {
		OSD_120HZ,                       // [33]
		BUFFER_MODE,                     // [32:31]
		DOT_MODE,                        // [30:28]
		osd_inter_frame_phosphor_mode,   // [27:26]
		osd_halo_knee,                   // [25:24]
		osd_halo_curve,
		osd_expand_highlights,
		osd_full_bypass,
		osd_slot_mask_rows,
		osd_slot_mask,
		osd_presentation_color,
		osd_color_space,
		osd_halo_spread,
		osd_phosphor_mode,
		osd_halo_filter,
		osd_bloom_curve,
		osd_bloom_width
	};

	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [33:0] osd_control_meta = '0;
	(* altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
	logic [33:0] osd_control_sync = '0;
	logic [33:0] osd_control_sync_d = '0;
	logic [33:0] osd_control_stable = '0;
	logic [9:0]  bloom_curve_gain = 10'd64;
	logic [9:0]  halo_curve_gain = 10'd64;
	logic [7:0]  halo_filter = 8'd0;

	function automatic [9:0] decode_curve_gain(
		input logic [2:0] sel
	);
		begin
			decode_curve_gain =
				(sel == 3'd0) ? 10'd64  : // Minimal
				(sel == 3'd1) ? 10'd96  : // Min+
				(sel == 3'd2) ? 10'd128 : // Mild
				(sel == 3'd3) ? 10'd192 : // Mild+
				(sel == 3'd4) ? 10'd256 : // Moderate
				(sel == 3'd5) ? 10'd320 : // Mod+
				(sel == 3'd6) ? 10'd384 : // Strong-
				                  10'd512 ; // Strong
		end
	endfunction

	function automatic [7:0] decode_halo_filter(
		input logic [2:0] sel
	);
		begin
			decode_halo_filter =
				(sel == 3'd0) ? 8'd0  : // Off
				(sel == 3'd1) ? 8'd8  : // 0.25x
				(sel == 3'd2) ? 8'd11 : // 0.33x
				(sel == 3'd3) ? 8'd16 : // 0.5x
				(sel == 3'd4) ? 8'd24 : // 0.75x
				(sel == 3'd5) ? 8'd32 : // 1.0x
				(sel == 3'd6) ? 8'd40 : // 1.25x
				                  8'd48 ; // 1.5x
		end
	endfunction

	always_ff @(posedge clk_sys) begin
		osd_control_meta <= osd_control_in;
		osd_control_sync <= osd_control_meta;
		osd_control_sync_d <= osd_control_sync;
		if (osd_control_sync == osd_control_sync_d)
			osd_control_stable <= osd_control_sync;

		osd_bloom_width_vid <= osd_control_stable[2:0];
		bloom_curve_gain <=
			decode_curve_gain(osd_control_stable[5:3]);
		halo_filter <= decode_halo_filter(osd_control_stable[8:6]);
		osd_phosphor_mode_vid <= osd_control_stable[10:9];
		osd_halo_spread_vid <= osd_control_stable[12:11];
		osd_color_space_vid <= osd_control_stable[13];
		osd_presentation_color_vid <= osd_control_stable[16:14];
		osd_slot_mask_vid <= osd_control_stable[17];
		osd_slot_mask_rows_vid <= osd_control_stable[18];
		osd_full_bypass_vid <= osd_control_stable[19];
		osd_expand_highlights_vid <= osd_control_stable[20];
		halo_curve_gain <=
			decode_curve_gain(osd_control_stable[23:21]);
		osd_halo_knee_vid <= osd_control_stable[25:24];
		inter_frame_mode_vid <= osd_control_stable[27:26];
		dot_mode_vid <= osd_control_stable[30:28];
		buffer_mode_vid <= osd_control_stable[32:31];
		osd_120hz_vid <= osd_control_stable[33];
	end

	vfb_readout #(
		.TILE_SIZE(TILE_SIZE)
	) readout_inst (
		.clk_sys(clk_sys),
		.reset(fb_client_reset | video_timing_reset),

		// DDRAM arbiter interface
		.readout_ready(readout_ready),
		.readout_grant(readout_grant),
		.readout_tile_id(readout_tile_id),
		.readout_burstcnt(readout_burstcnt),
		.readout_data(readout_data),
		.readout_data_valid(readout_data_valid),

		.vbl_swap_req(vbl_swap_req),

		// Readout output
		.VGA_R(raw_vga_r),
		.VGA_G(raw_vga_g),
		.VGA_B(raw_vga_b),
		.VGA_HS(raw_vga_hs),
		.VGA_VS(raw_vga_vs),
		.VGA_HBLANK(raw_vga_hblank),
		.VGA_VBLANK(raw_vga_vblank),

		.display_tile_addr(display_tile_addr),
		.display_tile_dirty(display_tile_dirty),

		.h_cnt(h_cnt),
		.v_cnt(v_cnt),
		.ce_pix(ce_pix),
		.hsync(hsync),
		.vsync(vsync),
		.hblank(hblank),
		.vblank(vblank),

		.RENDER_WIDTH(RENDER_WIDTH),
		.RENDER_HEIGHT(RENDER_HEIGHT),
		.FLASH_PARAM({FLASH_PARAM, FLASH_PARAM, FLASH_PARAM}),
		.draw_idx(readout_draw_idx),
		.phosphor_age_map(readout_age_map),
		.osd_phosphor_mode(osd_phosphor_mode_vid),
		.expand_highlights(osd_expand_highlights_vid),
		.display_is_composed(display_is_composed)
	);

	wire [7:0] filtered_vga_r;
	wire [7:0] filtered_vga_g;
	wire [7:0] filtered_vga_b;
	wire       filtered_vga_hs;
	wire       filtered_vga_vs;
	wire       filtered_vga_hblank;
	wire       filtered_vga_vblank;
	logic      full_bypass_active = 1'b0;

	vfb_halo_pipeline filter_inst (
		.clk_sys(clk_sys),
		.ce_pix(ce_pix),
		.reset(filter_reset_q),

		.osd_bloom_width(osd_bloom_width_vid),
		.bloom_curve_gain(bloom_curve_gain),
		.halo_curve_gain(halo_curve_gain),
		.halo_filter(halo_filter),
		.halo_spread_mode(osd_halo_spread_vid),
		.halo_knee_mode(osd_halo_knee_vid),
		.active_height(RENDER_HEIGHT),
		.color_space_amp709(osd_color_space_vid),
		.presentation_color(osd_presentation_color_vid),
		.slot_mask_enable(osd_slot_mask_vid),
		.slot_mask_rows(osd_slot_mask_rows_vid),

		.VGA_R_IN(raw_vga_r),
		.VGA_G_IN(raw_vga_g),
		.VGA_B_IN(raw_vga_b),
		.VGA_HS_IN(raw_vga_hs),
		.VGA_VS_IN(raw_vga_vs),
		.VGA_HBLANK_IN(raw_vga_hblank),
		.VGA_VBLANK_IN(raw_vga_vblank),

		.VGA_R_OUT(filtered_vga_r),
		.VGA_G_OUT(filtered_vga_g),
		.VGA_B_OUT(filtered_vga_b),
		.VGA_HS_OUT(filtered_vga_hs),
		.VGA_VS_OUT(filtered_vga_vs),
		.VGA_HBLANK_OUT(filtered_vga_hblank),
		.VGA_VBLANK_OUT(filtered_vga_vblank),

		.sdram_data_in(SDRAM_DQ_IN),
		.sdram_data_out(SDRAM_DQ_OUT),
		.sdram_data_oe(SDRAM_DQ_OE),
		.sdram_cke(SDRAM_CKE),
		.sdram_cs(SDRAM_nCS),
		.sdram_ras(SDRAM_nRAS),
		.sdram_cas(SDRAM_nCAS),
		.sdram_we(SDRAM_nWE),
		.sdram_dqm(SDRAM_DQM),
		.sdram_addr(SDRAM_A),
		.sdram_ba(SDRAM_BA),
		.sdram_overflow(),
		.sdram_underflow(),
		.sdram_init_done()
	);

	// Full bypass selects the unfiltered readout.
	always_ff @(posedge clk_sys) begin
		if (fb_client_reset | video_timing_reset) begin
			full_bypass_active <= 1'b0;
			VGA_R <= 8'd0;
			VGA_G <= 8'd0;
			VGA_B <= 8'd0;
			VGA_HS <= 1'b1;
			VGA_VS <= 1'b1;
			VGA_HBLANK <= 1'b1;
			VGA_VBLANK <= 1'b1;
		end else begin
			if ((osd_full_bypass_vid != full_bypass_active) &&
			    (osd_full_bypass_vid ? raw_vga_vblank :
			                           filtered_vga_vblank))
				full_bypass_active <= osd_full_bypass_vid;

			if (ce_pix && full_bypass_active) begin
				VGA_R <= raw_vga_r;
				VGA_G <= raw_vga_g;
				VGA_B <= raw_vga_b;
				VGA_HS <= raw_vga_hs;
				VGA_VS <= raw_vga_vs;
				VGA_HBLANK <= raw_vga_hblank;
				VGA_VBLANK <= raw_vga_vblank;
			end else if (ce_pix) begin
				VGA_R <= filtered_vga_r;
				VGA_G <= filtered_vga_g;
				VGA_B <= filtered_vga_b;
				VGA_HS <= filtered_vga_hs;
				VGA_VS <= filtered_vga_vs;
				VGA_HBLANK <= filtered_vga_hblank;
				VGA_VBLANK <= filtered_vga_vblank;
			end
		end
	end

endmodule
