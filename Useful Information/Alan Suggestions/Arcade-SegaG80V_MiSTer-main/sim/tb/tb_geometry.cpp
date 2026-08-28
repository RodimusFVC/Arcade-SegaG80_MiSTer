// sega_geometry: check the vector field lands where it should.
//
// A coordinate-map bug is invisible to every other bench (the vector generator
// and the CPU are both correct either way) but wrecks the picture, so the
// corners, centre and orientation flips are checked explicitly.

#include <cstdio>
#include <cstdint>
#include "Vsega_geometry.h"
#include "verilated.h"

static Vsega_geometry *dut;

struct R { int x, y; bool ok; };

static R map(int sx, int sy, int orient, int scale, int cx, int cy, int w, int h) {
	dut->src_x = sx; dut->src_y = sy; dut->orientation = orient;
	dut->scale_num = scale; dut->center_x = cx; dut->center_y = cy;
	dut->render_width = w; dut->render_height = h;
	dut->eval();
	return { (int)dut->raster_x, (int)dut->raster_y, (bool)dut->in_bounds };
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	dut = new Vsega_geometry;
	int fails = 0;
	auto check = [&](bool c, const char *what) {
		printf("  %-4s %s\n", c ? "ok" : "FAIL", what);
		if (!c) fails++;
	};

	// 480p landscape: 1024x832 field scaled 18/32 into 640x480, centre 320,240
	const int L = 0b010;   // FLIP_Y, the normal Sega orientation

	// Field centre must land on the raster centre (within rounding).
	R c = map(512, 96 + 416, L, 18, 320, 240, 640, 480);
	check(c.ok && abs(c.x - 320) <= 2 && abs(c.y - 240) <= 2,
	      "field centre maps to raster centre");

	// The visible field is y 96..927; rows outside are dropped.
	check(!map(512, 95,  L, 18, 320, 240, 640, 480).ok, "row above the window is cropped");
	check(!map(512, 928, L, 18, 320, 240, 640, 480).ok, "row below the window is cropped");
	check( map(512, 96,  L, 18, 320, 240, 640, 480).ok, "first visible row is kept");
	check( map(512, 927, L, 18, 320, 240, 640, 480).ok, "last visible row is kept");

	// Scaled extents must fit inside the target: 1024*18/32 = 576 wide.
	R left  = map(0,    96 + 416, L, 18, 320, 240, 640, 480);
	R right = map(1023, 96 + 416, L, 18, 320, 240, 640, 480);
	check(left.ok && right.ok, "both horizontal extremes are on screen");
	check(abs((right.x - left.x) - 576) <= 2, "field spans 576 px at 18/32");
	check(left.x > 0 && right.x < 640, "field is inset, not clipped");

	// FLIP_Y must actually invert: low source Y ends up at high raster Y.
	R top    = map(512, 96,  L, 18, 320, 240, 640, 480);
	R bottom = map(512, 927, L, 18, 320, 240, 640, 480);
	check(top.y > bottom.y, "FLIP_Y inverts the vertical axis");

	// Negative-side coordinates must stay left of centre (the sign-extension
	// bug this test was written for put them on the right).
	check(left.x < 320 && right.x > 320, "left of centre stays left of centre");

	// Tac/Scan: SWAP_XY|FLIP_Y|FLIP_X, 832x1024 portrait, 22/32 into 916x720
	const int P = 0b111;
	R pc = map(512, 96 + 416, P, 22, 458, 360, 916, 720);
	check(pc.ok && abs(pc.x - 458) <= 2 && abs(pc.y - 360) <= 2,
	      "swapped-axis centre maps to raster centre");
	R pl = map(0, 96 + 416, P, 22, 458, 360, 916, 720);
	R pr = map(1023, 96 + 416, P, 22, 458, 360, 916, 720);
	check(pl.ok && pr.ok, "swapped-axis extremes are on screen");
	check(abs(pl.x - pr.x) <= 2, "source X does not move raster X when swapped");
	check(abs((pl.y - pr.y)) > 600, "source X drives raster Y when swapped");

	dut->final(); delete dut;
	printf("sega_geometry: %d failed\n", fails);
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
