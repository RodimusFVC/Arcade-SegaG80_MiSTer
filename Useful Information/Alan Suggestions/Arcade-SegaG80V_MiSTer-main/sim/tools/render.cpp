// Render a Sega G-80 vector RAM snapshot to a PPM using the golden model.
//
//   render <sine-prom> <vram.bin> <out.ppm>
//
// Draws the beam path the X-Y boards would walk, with the 2-bit-per-gun colour
// resolved the same way vfb_color6 does, so the result is what the core should
// put on screen.

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>
#include "segag80v_golden.h"

static const int W = 1024, H = 1024;

static uint8_t lvl(uint8_t v, int l) {
	switch (l) { case 0: return 0; case 1: return (uint8_t)((v*85)>>8);
	             case 2: return (uint8_t)((v*171)>>8); default: return v; }
}

int main(int argc, char **argv) {
	if (argc < 4) { printf("usage: render <sine-prom> <vram.bin> <out.ppm> [phase_clks] [budget]\n"); return 2; }
	uint8_t sintab[1024], vram[4096];
	FILE *f;
	if (!(f = fopen(argv[1], "rb")) || fread(sintab,1,1024,f) != 1024) { printf("bad prom\n"); return 2; }
	fclose(f);
	if (!(f = fopen(argv[2], "rb")) || fread(vram,1,4096,f) != 4096) { printf("bad vram\n"); return 2; }
	fclose(f);

    static uint8_t img[H][W][3];
	memset(img, 0, sizeof img);

	XyConfig cfg;
	if (argc > 4) cfg.phase_clks  = atoi(argv[4]);
	if (argc > 5) cfg.budget_clks = atoi(argv[5]);
	std::vector<VecSample> out;
	sega_xy_golden(vram, sintab, cfg, out);

	long lit = 0;
	for (auto &s : out) {
		if (!s.beam || s.x >= W || s.y >= H) continue;
		int r = lvl(255, (s.colour >> 4) & 3);
		int g = lvl(255, (s.colour >> 2) & 3);
		int b = lvl(255,  s.colour       & 3);
		// Y is flipped for display (games run ORIENTATION_FLIP_Y)
		int yy = H - 1 - s.y;
		uint8_t *px = img[yy][s.x];
		px[0] = (uint8_t)(px[0] > r ? px[0] : r);
		px[1] = (uint8_t)(px[1] > g ? px[1] : g);
		px[2] = (uint8_t)(px[2] > b ? px[2] : b);
		lit++;
	}

	FILE *o = fopen(argv[3], "wb");
	if (!o) { printf("cannot write %s\n", argv[3]); return 2; }
	fprintf(o, "P6\n%d %d\n255\n", W, H);
	fwrite(img, 1, sizeof img, o);
	fclose(o);
	printf("%s: %zu samples, %ld lit pixels -> %s\n", argv[2], out.size(), lit, argv[3]);
	return 0;
}
