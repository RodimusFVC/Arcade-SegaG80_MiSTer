//============================================================================
//  Sega G-80 X-Y video: mode timing, coordinate map, vector renderer
//
//  The equivalent of major_havoc_video.sv, and modelled on it: pick a render
//  target and video timing from the reported HDMI height, generate the raster
//  counters at clk_125, map the beam into the framebuffer, and hand the result
//  to Videodr0me's vfb_top.
//
//  videodr0me_fb scans the framebuffer out at video timing, so the render
//  target has to match the active area of the selected mode. The Sega field is
//  1024 x 832 (832 x 1024 with the axes swapped for Tac/Scan) and is scaled to
//  fit by a shift-add ratio per mode.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_video (
	input  wire        clk_vec,     // vector-generator domain (12.096 MHz)
	input  wire        vec_tick,    // VCL step enable within clk_vec
	input  wire        clk_125,
	input  wire        reset,

	input  wire [11:0] hdmi_height,
	input  wire  [1:0] aspect_ratio,
	input  wire  [2:0] orientation,     // {swap_xy, flip_y, flip_x}

	// vector input from segag80v
	input  wire  [9:0] vec_x,
	input  wire  [9:0] vec_y,
	input  wire  [5:0] vec_colour,
	input  wire        vec_beam,
	input  wire        vec_valid,
	input  wire        frame_done,

	// OSD
	input  wire  [7:0] osd_flash_param,
	input  wire        osd_120hz,
	input  wire  [1:0] osd_buffer_mode,
	input  wire  [2:0] osd_dot_mode,
	input  wire  [2:0] osd_bloom_width,
	input  wire  [2:0] osd_bloom_curve,
	input  wire  [2:0] osd_halo_filter,
	input  wire  [1:0] osd_phosphor_mode,
	input  wire  [1:0] osd_inter_frame_phosphor_mode,
	input  wire  [1:0] osd_halo_spread,
	input  wire  [2:0] osd_halo_curve,
	input  wire  [1:0] osd_halo_knee,
	input  wire        osd_expand_highlights,
	input  wire        osd_color_space,
	input  wire  [2:0] osd_presentation_color,
	input  wire        osd_slot_mask,
	input  wire        osd_slot_mask_rows,
	input  wire        osd_full_bypass,

	output logic [12:0] video_arx,
	output logic [12:0] video_ary,
	output wire         ce_pixel,
	output wire         hblank,
	output wire         vblank,
	output wire   [7:0] video_r,
	output wire   [7:0] video_g,
	output wire   [7:0] video_b,
	output wire         hsync,
	output wire         vsync,
	output wire         mode_is_720p,
	output wire         fifo_full,

	// DDRAM
	output wire         ddram_clk,
	input  wire         ddram_busy,
	output wire   [7:0] ddram_burst_count,
	output wire  [28:0] ddram_address,
	input  wire  [63:0] ddram_data_out,
	input  wire         ddram_data_ready,
	output wire         ddram_read,
	output wire  [63:0] ddram_data_in,
	output wire   [7:0] ddram_byte_enable,
	output wire         ddram_write,

	// SDRAM (halo alignment delay)
	input  wire  [15:0] sdram_data_in,
	output wire  [15:0] sdram_data_out,
	output wire         sdram_data_oe,
	output wire         sdram_cke,
	output wire         sdram_ncs,
	output wire         sdram_nras,
	output wire         sdram_ncas,
	output wire         sdram_nwe,
	output wire   [1:0] sdram_dqm,
	output wire  [12:0] sdram_address,
	output wire   [1:0] sdram_bank
);

	// ------------------------------------------------------------------
	// Mode selection. Timings are the ones asteroids_video.sv uses, which are
	// already known good against MiSTer's scaler; only the render target and
	// the vector scale are Sega-specific.
	//
	// The source field is 1024 x 832 (or 832 x 1024 swapped). scale_num is the
	// numerator of a /32 ratio picked so the scaled field fits the target:
	//
	//   landscape 1024x832        portrait 832x1024
	//     240p  9/32 -> 288x234     7/32 -> 182x224
	//     480p 18/32 -> 576x468    14/32 -> 364x448
	//     720p 26/32 -> 832x676    22/32 -> 572x704
	//    1080p 40/32 -> 1280x1040  32/32 -> 832x1024
	// ------------------------------------------------------------------
	logic [11:0] fb_width  = 12'd640;
	logic [11:0] fb_height = 12'd480;
	logic [11:0] x_center  = 12'd320;
	logic [11:0] y_center  = 12'd240;
	logic  [5:0] scale_num = 6'd18;
	logic [12:0] optimized_arx = 13'h1000 | 13'd640;
	logic [12:0] optimized_ary = 13'h1000 | 13'd480;
	logic [11:0] h_total  = 12'd1019;
	logic [11:0] v_total  = 12'd524;
	logic [11:0] hs_start = 12'd720;
	logic [11:0] hs_end   = 12'd816;
	logic [11:0] vs_start = 12'd490;
	logic [11:0] vs_end   = 12'd492;
	logic is_1080p = 1'b0;
	logic is_480p  = 1'b1;
	logic is_240p  = 1'b0;

	logic [11:0] height_meta;
	logic        rate_meta, rate_sync;
	logic        mode_config_ready = 1'b0;
	logic        mode_ready = 1'b0;
	logic        swap_meta;

	always_ff @(posedge clk_125) begin
		height_meta <= hdmi_height;
		rate_meta   <= osd_120hz;
		rate_sync   <= rate_meta;
		swap_meta   <= orientation[2];
		mode_config_ready <= (height_meta != 12'd0) && (rate_meta == rate_sync);
		mode_ready        <= mode_config_ready;

		if (height_meta != 12'd0) begin
			is_1080p <= (height_meta >= 12'd1080) && (height_meta < 12'd1400);
			is_480p  <= (height_meta >= 12'd480)  && (height_meta < 12'd720);
			is_240p  <= (height_meta < 12'd480);

			if ((height_meta >= 12'd1080) && (height_meta < 12'd1400)) begin
				fb_width  <= 12'd1360; fb_height <= 12'd1080;
				x_center  <= 12'd680;  y_center  <= 12'd540;
				scale_num <= swap_meta ? 6'd32 : 6'd40;
				optimized_arx <= 13'h1000 | 13'd1360;
				optimized_ary <= 13'h1000 | 13'd1080;
				h_total  <= 12'd1903; v_total <= 12'd1124;
				hs_start <= 12'd1600; hs_end  <= 12'd1688;
				vs_start <= 12'd1088; vs_end  <= 12'd1093;
			end else if (height_meta < 12'd480) begin
				fb_width  <= 12'd640; fb_height <= 12'd240;
				x_center  <= 12'd320; y_center  <= 12'd120;
				scale_num <= swap_meta ? 6'd7 : 6'd9;
				optimized_arx <= 13'h1000 | 13'd640;
				optimized_ary <= 13'h1000 | 13'd240;
				h_total  <= 12'd1021; v_total <= 12'd261;
				hs_start <= 12'd720;  hs_end  <= 12'd816;
				vs_start <= 12'd245;  vs_end  <= 12'd248;
			end else if (height_meta < 12'd720) begin
				fb_width  <= 12'd640; fb_height <= 12'd480;
				x_center  <= 12'd320; y_center  <= 12'd240;
				scale_num <= swap_meta ? 6'd14 : 6'd18;
				optimized_arx <= 13'h1000 | 13'd640;
				optimized_ary <= 13'h1000 | 13'd480;
				h_total  <= 12'd1019; v_total <= 12'd524;
				hs_start <= 12'd720;  hs_end  <= 12'd816;
				vs_start <= 12'd490;  vs_end  <= 12'd492;
			end else begin
				fb_width  <= 12'd916; fb_height <= 12'd720;
				x_center  <= 12'd458; y_center  <= 12'd360;
				scale_num <= swap_meta ? 6'd22 : 6'd26;
				optimized_arx <= (height_meta >= 12'd1440) ?
				                 (13'h1000 | 13'd1832) : (13'h1000 | 13'd916);
				optimized_ary <= (height_meta >= 12'd1440) ?
				                 (13'h1000 | 13'd1440) : (13'h1000 | 13'd720);
				h_total  <= 12'd1427; v_total <= 12'd749;
				hs_start <= 12'd1108; hs_end  <= 12'd1196;
				vs_start <= 12'd728;  vs_end  <= 12'd733;
			end
		end
	end

	always_comb begin
		case (aspect_ratio)
			2'd0: begin video_arx = optimized_arx; video_ary = optimized_ary; end
			2'd1: begin video_arx = 13'd0;         video_ary = 13'd0;         end
			default: begin
				video_arx = 13'h1000 | {1'b0, fb_width};
				video_ary = 13'h1000 | {1'b0, fb_height};
			end
		endcase
	end

	assign mode_is_720p = mode_ready && !is_1080p && !is_480p && !is_240p;

	// ------------------------------------------------------------------
	// Raster counters
	// ------------------------------------------------------------------
	logic [10:0] h_counter = 11'd0;
	logic [10:0] v_counter = 11'd0;
	logic  [2:0] clock_divider = 3'd0;
	logic        ce_pixel_r = 1'b0;

	always_ff @(posedge clk_125) begin
		clock_divider <= clock_divider + 3'd1;

		if (!mode_ready)      ce_pixel_r <= 1'b0;
		else if (is_1080p)    ce_pixel_r <= 1'b1;
		else if (is_240p)     ce_pixel_r <= (clock_divider[1:0] == 2'd0);
		else if (is_480p)     ce_pixel_r <= (clock_divider[1:0] == 2'd0);
		else                  ce_pixel_r <= (clock_divider[0] == 1'b0);

		if (reset) begin
			h_counter <= 11'd0;
			v_counter <= 11'd0;
		end else if (ce_pixel_r) begin
			if (h_counter >= h_total[10:0]) begin
				h_counter <= 11'd0;
				v_counter <= (v_counter >= v_total[10:0]) ? 11'd0
				                                          : (v_counter + 11'd1);
			end else begin
				h_counter <= h_counter + 11'd1;
			end
		end
	end

	assign ce_pixel = ce_pixel_r;

	wire raw_hsync  = !((h_counter >= hs_start[10:0]) && (h_counter < hs_end[10:0]));
	wire raw_vsync  = !((v_counter >= vs_start[10:0]) && (v_counter < vs_end[10:0]));
	wire raw_hblank = (h_counter >= fb_width[10:0]);
	wire raw_vblank = (v_counter >= fb_height[10:0]);

	// ------------------------------------------------------------------
	// Coordinate map
	// ------------------------------------------------------------------
	wire [10:0] rast_x, rast_y;
	wire        rast_in_bounds;

	sega_geometry geom (
		.src_x         (vec_x),
		.src_y         (vec_y),
		.orientation   (orientation),
		.scale_num     (scale_num),
		.center_x      (x_center),
		.center_y      (y_center),
		.render_width  (fb_width),
		.render_height (fb_height),
		.raster_x      (rast_x),
		.raster_y      (rast_y),
		.in_bounds     (rast_in_bounds)
	);

	// vec_valid and frame_done are one-VCL-tick pulses that stay asserted for
	// the whole gap between enables, so they are used directly — re-gating them
	// with the vector clock enable would drop every sample.
	logic [10:0] fb_x, fb_y;
	logic  [5:0] fb_c;
	logic        fb_beam, fb_frame_done;

	always_ff @(posedge clk_vec) begin
		if (reset) begin
			fb_x <= 11'd0; fb_y <= 11'd0; fb_c <= 6'd0;
			fb_beam <= 1'b0; fb_frame_done <= 1'b0;
		end else begin
			fb_frame_done <= frame_done;
			if (vec_valid) begin
				fb_x    <= rast_x;
				fb_y    <= rast_y;
				fb_c    <= vec_colour;
				fb_beam <= vec_beam && rast_in_bounds;
			end else begin
				fb_beam <= 1'b0;
			end
		end
	end

	// Sega's beam is either fully on or off — there is no Z-axis intensity
	// channel like Atari's AVG, so full scale is the only meaningful value.
	wire [7:0] fb_z = 8'hFF;

	vfb_top renderer (
		.clk_sys             (clk_125),
		.clk_source          (clk_vec),
		.source_tick         (vec_tick),
		.reset               (reset),
		.video_timing_reset  (~mode_ready),

		.X_VECTOR            (fb_x),
		.Y_VECTOR            (fb_y),
		.Z_VECTOR            (fb_z),
		.COLOR               (fb_c),
		.IS_DOT              (1'b0),
		.BEAM_ON             (fb_beam),

		.DDRAM_CLK           (ddram_clk),
		.DDRAM_BUSY          (ddram_busy),
		.DDRAM_BURSTCNT      (ddram_burst_count),
		.DDRAM_ADDR          (ddram_address),
		.DDRAM_DOUT          (ddram_data_out),
		.DDRAM_DOUT_READY    (ddram_data_ready),
		.DDRAM_RD            (ddram_read),
		.DDRAM_DIN           (ddram_data_in),
		.DDRAM_BE            (ddram_byte_enable),
		.DDRAM_WE            (ddram_write),

		.SDRAM_DQ_IN         (sdram_data_in),
		.SDRAM_DQ_OUT        (sdram_data_out),
		.SDRAM_DQ_OE         (sdram_data_oe),
		.SDRAM_CKE           (sdram_cke),
		.SDRAM_nCS           (sdram_ncs),
		.SDRAM_nRAS          (sdram_nras),
		.SDRAM_nCAS          (sdram_ncas),
		.SDRAM_nWE           (sdram_nwe),
		.SDRAM_DQM           (sdram_dqm),
		.SDRAM_A             (sdram_address),
		.SDRAM_BA            (sdram_bank),

		.RENDER_WIDTH        (fb_width),
		.RENDER_HEIGHT       (fb_height),

		.VGA_R               (video_r),
		.VGA_G               (video_g),
		.VGA_B               (video_b),
		.VGA_HS              (hsync),
		.VGA_VS              (vsync),
		.VGA_HBLANK          (hblank),
		.VGA_VBLANK          (vblank),

		.h_cnt               (h_counter),
		.v_cnt               (v_counter),
		.ce_pix              (ce_pixel_r),
		.hsync               (raw_hsync),
		.vsync               (raw_vsync),
		.hblank              (raw_hblank),
		.vblank              (raw_vblank),

		.FLASH_PARAM         (osd_flash_param),
		.OSD_120HZ           (osd_120hz),
		.FRAME_DONE          (fb_frame_done),
		.BUFFER_MODE         (osd_buffer_mode),
		.DOT_MODE            (osd_dot_mode),
		.FIFO_FULL_LED       (fifo_full),

		.osd_bloom_width     (osd_bloom_width),
		.osd_bloom_curve     (osd_bloom_curve),
		.osd_halo_filter     (osd_halo_filter),
		.osd_phosphor_mode   (osd_phosphor_mode),
		.osd_inter_frame_phosphor_mode (osd_inter_frame_phosphor_mode),
		.osd_halo_spread     (osd_halo_spread),
		.osd_halo_curve      (osd_halo_curve),
		.osd_halo_knee       (osd_halo_knee),
		.osd_expand_highlights (osd_expand_highlights),
		.osd_color_space     (osd_color_space),
		.osd_presentation_color (osd_presentation_color),
		.osd_slot_mask       (osd_slot_mask),
		.osd_slot_mask_rows  (osd_slot_mask_rows),
		.osd_full_bypass     (osd_full_bypass)
	);

endmodule

`default_nettype wire
