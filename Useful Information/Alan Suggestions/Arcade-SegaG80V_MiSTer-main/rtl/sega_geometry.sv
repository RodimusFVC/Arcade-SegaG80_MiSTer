//============================================================================
//  Sega G-80 vector field -> framebuffer coordinate map
//
//  The X-Y boards produce a 1024 x 1024 coordinate space after clipping, but
//  the monitor only shows part of it vertically. MAME's visible area is
//  x 512..1536, y 608..1440 with the transform in adjust_xy() offsetting Y by
//  (min_y - 512) = 96, so the visible field is:
//
//      x  0..1023            full width
//      y  96..927            832 of the 1024 rows
//
//  Orientation uses MAME's own three flags so the MRA can carry the value
//  straight across:
//
//      bit 0  ORIENTATION_FLIP_X
//      bit 1  ORIENTATION_FLIP_Y
//      bit 2  ORIENTATION_SWAP_XY
//
//  Per game (from refs/mame/segag80v.cpp):
//      Eliminator, Space Fury, Zektor, Star Trek   FLIP_Y            = 3'b010
//      Tac/Scan   (FLIP_X ^ ROT270)                SWAP|FLIP_Y|FLIP_X= 3'b111
//
//  videodr0me_fb scans the framebuffer out directly at video timing, so the
//  render target has to match the active area of the selected video mode. The
//  field is therefore scaled about the raster centre by a shift-add ratio per
//  mode, the same approach asteroids_geometry.sv uses.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_geometry (
	input  wire  [9:0] src_x,        // 0..1023 from the vector generator
	input  wire  [9:0] src_y,
	input  wire  [2:0] orientation,  // {swap_xy, flip_y, flip_x}

	// scale numerator over 32; see sega_video.sv for the per-mode values
	input  wire  [5:0] scale_num,
	input  wire [11:0] center_x,
	input  wire [11:0] center_y,
	input  wire [11:0] render_width,
	input  wire [11:0] render_height,

	output wire [10:0] raster_x,
	output wire [10:0] raster_y,
	output wire        in_bounds
);
	localparam int VIS_Y0 = 96;      // first visible row of the 1024-row field
	localparam int VIS_H  = 832;     // visible rows
	localparam int VIS_W  = 1024;

	wire flip_x  = orientation[0];
	wire flip_y  = orientation[1];
	wire swap_xy = orientation[2];

	// Crop vertically. Rows outside the monitor's window are not drawn; the
	// vector generator has already blanked anything clipped in X.
	wire signed [12:0] cy = $signed({3'b000, src_y}) - 13'sd96;
	wire               y_visible = (cy >= 13'sd0) && (cy < 13'sd832);

	wire [10:0] sx = {1'b0, src_x};
	wire [10:0] sy = cy[10:0];

	// Axis assignment, then flips about the centre of each axis.
	wire [10:0] a_raw = swap_xy ? sy : sx;
	wire [10:0] b_raw = swap_xy ? sx : sy;
	wire [10:0] a_max = swap_xy ? 11'(VIS_H - 1) : 11'(VIS_W - 1);
	wire [10:0] b_max = swap_xy ? 11'(VIS_W - 1) : 11'(VIS_H - 1);

	wire [10:0] a_flip = flip_x ? (a_max - a_raw) : a_raw;
	wire [10:0] b_flip = flip_y ? (b_max - b_raw) : b_raw;

	// Centre, scale by scale_num/32, then re-centre on the raster. Widths are
	// written out explicitly rather than relying on implicit extension, so
	// Quartus and Verilator cannot disagree about the sign handling.
	wire signed [12:0] a_ctr = $signed({2'b00, a_flip}) - $signed({2'b00, a_max[10:1]});
	wire signed [12:0] b_ctr = $signed({2'b00, b_flip}) - $signed({2'b00, b_max[10:1]});

	// a_ctr/b_ctr are signed: sign-extend them, do not zero-extend, or every
	// coordinate left of centre lands on the wrong side of the screen.
	wire signed [19:0] a_prod = $signed({{7{a_ctr[12]}}, a_ctr})
	                          * $signed({14'd0, scale_num});
	wire signed [19:0] b_prod = $signed({{7{b_ctr[12]}}, b_ctr})
	                          * $signed({14'd0, scale_num});

	wire signed [20:0] a_out = $signed({a_prod[19], a_prod}) >>> 5;
	wire signed [20:0] b_out = $signed({b_prod[19], b_prod}) >>> 5;

	wire signed [20:0] a_pos = a_out + $signed({9'd0, center_x});
	wire signed [20:0] b_pos = b_out + $signed({9'd0, center_y});

	wire a_ok = (a_pos >= 21'sd0) && (a_pos < $signed({9'd0, render_width}));
	wire b_ok = (b_pos >= 21'sd0) && (b_pos < $signed({9'd0, render_height}));

	assign raster_x  = a_ok ? a_pos[10:0] : 11'd0;
	assign raster_y  = b_ok ? b_pos[10:0] : 11'd0;
	assign in_bounds = y_visible && a_ok && b_ok;

endmodule

`default_nettype wire
