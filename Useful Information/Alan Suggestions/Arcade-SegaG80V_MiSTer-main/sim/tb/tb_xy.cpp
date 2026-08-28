// sega_xy (RTL) vs the MAME-derived golden model.
//
// Drives both with the same vector RAM and sine PROM and requires the emitted
// {x, y, colour, beam} sample streams to be identical, sample for sample.

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <string>
#include <dirent.h>
#include <random>
#include <vector>

#include "Vsega_xy.h"
#include "verilated.h"
#include "segag80v_golden.h"

static const int    VRAM_SIZE   = 4096;
static const int    SIN_SIZE    = 1024;
static const long   MAX_CLOCKS  = 8000000;

struct Rig {
	Vsega_xy *dut;
	uint8_t   vram[VRAM_SIZE];
	uint8_t   sintab[SIN_SIZE];

	Rig() { dut = new Vsega_xy; }
	~Rig() { dut->final(); delete dut; }

	// Runs one frame, collecting samples. Returns false if it never finished.
	bool run(std::vector<VecSample> &out) {
		out.clear();

		dut->clk = 0; dut->ce = 1; dut->reset = 1; dut->frame_start = 0;
		dut->vram_data = 0; dut->sin_data = 0;
		for (int i = 0; i < 4; i++) { tick(); }
		dut->reset = 0;
		tick();

		dut->frame_start = 1;
		tick();
		dut->frame_start = 0;

		for (long c = 0; c < MAX_CLOCKS; c++) {
			tick();
			if (dut->out_valid)
				out.push_back({ (uint16_t)dut->out_x, (uint16_t)dut->out_y,
				                (uint8_t)dut->out_colour, (bool)dut->out_beam });
			if (dut->frame_done) return true;
		}
		return false;
	}

	// One clock. Synchronous-read memories: the address presented before the
	// rising edge is latched, and its data is visible after it.
	void tick() {
		uint16_t va = dut->vram_addr & (VRAM_SIZE - 1);
		uint16_t sa = dut->sin_addr  & (SIN_SIZE  - 1);

		dut->clk = 1;
		dut->eval();

		dut->vram_data = vram[va];
		dut->sin_data  = sintab[sa];
		dut->eval();

		dut->clk = 0;
		dut->eval();
	}
};

// ---------------------------------------------------------------------------
// Display-list builders
// ---------------------------------------------------------------------------

static uint16_t onscreen(std::mt19937 &rng);

// A structured list: symbols at the head of vector RAM, their vector lists in
// the upper half. This is the shape the real games emit.
static void build_structured(uint8_t *vram, std::mt19937 &rng, int nsymbols)
{
	memset(vram, 0, VRAM_SIZE);
	std::uniform_int_distribution<int> byte(0, 255);

	uint16_t vecbase = 0x800;

	for (int s = 0; s < nsymbols; s++) {
		uint16_t h = s * 10;
		if (h + 10 > 0x800) break;

		bool last = (s == nsymbols - 1);
		int  nvec = 1 + (rng() % 6);

		// keep the vector lists inside the upper half
		if (vecbase + nvec * 4 > VRAM_SIZE - 4) break;

		vram[h + 0] = (uint8_t)((last ? 0x80 : 0x00) | ((rng() % 8) ? 0x01 : 0x00));
		uint16_t x = onscreen(rng), y = onscreen(rng);
		vram[h + 1] = x & 0xff;                        // X low
		vram[h + 2] = (x >> 8) & 7;                    // X high (3 bits)
		vram[h + 3] = y & 0xff;                        // Y low
		vram[h + 4] = (y >> 8) & 7;                    // Y high
		vram[h + 5] = vecbase & 0xff;
		vram[h + 6] = (vecbase >> 8) & 0x0f;
		vram[h + 7] = byte(rng);                       // symbol angle low
		vram[h + 8] = rng() % 4;                       // symbol angle high
		vram[h + 9] = 0x20 + (rng() % 0xE0);           // scale

		for (int v = 0; v < nvec; v++) {
			uint16_t a = vecbase + v * 4;
			bool vlast = (v == nvec - 1);
			uint8_t colour = 1 + (rng() % 63);
			vram[a + 0] = (uint8_t)((vlast ? 0x80 : 0x00) | (colour << 1) | 0x01);
			vram[a + 1] = rng() % 64;                  // length
			vram[a + 2] = byte(rng);                   // vector angle low
			vram[a + 3] = rng() % 4;                   // vector angle high
		}
		vecbase += nvec * 4;
	}
}

// The visible field is raw 0x200..0x5FF on each axis: below 0x200 or above
// 0x5FF the (v & 0x600) window test clips. Placing symbols here makes most
// samples beam-on, the way a real game's display list behaves.
static uint16_t onscreen(std::mt19937 &rng)
{
	return (uint16_t)(0x200 + (rng() % 0x400));
}

// A list far larger than one 40 Hz frame can draw, to exercise budget
// exhaustion — the path that depends on the disputed phase-clock charge.
static void build_oversized(uint8_t *vram, std::mt19937 &rng)
{
	memset(vram, 0, VRAM_SIZE);
	std::uniform_int_distribution<int> byte(0, 255);

	const int nsym = 200;                 // 200 * 10 = 2000 bytes of headers
	uint16_t vecbase = 0x800;

	for (int s = 0; s < nsym; s++) {
		uint16_t h = s * 10;
		uint16_t x = onscreen(rng), y = onscreen(rng);

		// no terminator anywhere: only the budget can stop this
		vram[h + 0] = 0x01;
		vram[h + 1] = x & 0xff;
		vram[h + 2] = (x >> 8) & 7;
		vram[h + 3] = y & 0xff;
		vram[h + 4] = (y >> 8) & 7;
		vram[h + 5] = vecbase & 0xff;
		vram[h + 6] = (vecbase >> 8) & 0x0f;
		vram[h + 7] = byte(rng);
		vram[h + 8] = rng() % 4;
		vram[h + 9] = 0xff;                // maximum scale
	}

	// one shared vector list: 4 long vectors, so each symbol costs ~2000 steps
	for (int v = 0; v < 4; v++) {
		uint16_t a = vecbase + v * 4;
		vram[a + 0] = (uint8_t)((v == 3 ? 0x80 : 0x00) | (0x3f << 1) | 0x01);
		vram[a + 1] = 0xff;                // length 255 * scale 255 >> 7 = 508
		vram[a + 2] = byte(rng);
		vram[a + 3] = rng() % 4;
	}
}

// Pure noise: exercises wrapping, budget exhaustion, degenerate lengths and
// lists that point at themselves.
static void build_random(uint8_t *vram, std::mt19937 &rng)
{
	for (int i = 0; i < VRAM_SIZE; i++) vram[i] = (uint8_t)(rng() & 0xff);
}

// ---------------------------------------------------------------------------

static int compare(const char *name,
                   const std::vector<VecSample> &want,
                   const std::vector<VecSample> &got)
{
	size_t n = want.size() < got.size() ? want.size() : got.size();
	for (size_t i = 0; i < n; i++) {
		const VecSample &a = want[i], &b = got[i];
		if (a.x != b.x || a.y != b.y || a.colour != b.colour || a.beam != b.beam) {
			printf("  %s: sample %zu differs\n", name, i);
			printf("    golden x=%4u y=%4u c=%02X beam=%d\n",
			       a.x, a.y, a.colour, a.beam);
			printf("    rtl    x=%4u y=%4u c=%02X beam=%d\n",
			       b.x, b.y, b.colour, b.beam);
			return 1;
		}
	}
	if (want.size() != got.size()) {
		printf("  %s: length differs — golden %zu, rtl %zu\n",
		       name, want.size(), got.size());
		return 1;
	}
	return 0;
}

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);

	Rig rig;

	// Prefer the real sin/cos PROM dump; fall back to the synthesised table.
	bool real_prom = false;
	if (FILE *f = fopen("roms/s-c.xyt-u39", "rb")) {
		real_prom = fread(rig.sintab, 1, SIN_SIZE, f) == SIN_SIZE;
		fclose(f);
	}
	if (!real_prom) sega_xy_make_sintab(rig.sintab);
	printf("sega_xy: sine PROM = %s\n",
	       real_prom ? "real (roms/s-c.xyt-u39)" : "synthesised");

	// Real vector RAM captured from MAME by tools/dump_vram.lua, if present.
	std::vector<std::string> real_dumps;
	for (const char *g : { "elim2", "elim4", "spacfury",
	                       "zektor", "tacscan", "startrek" }) {
		std::string dir = std::string("vramdumps/") + g;
		if (DIR *d = opendir(dir.c_str())) {
			int taken = 0;
			while (struct dirent *e = readdir(d)) {
				std::string n = e->d_name;
				if (n.size() > 4 && n.substr(n.size() - 4) == ".bin" && taken < 8) {
					real_dumps.push_back(dir + "/" + n);
					taken++;
				}
			}
			closedir(d);
		}
	}
	printf("sega_xy: %zu real vector-RAM snapshots\n", real_dumps.size());

	XyConfig cfg;   // defaults: PHASE_CLKS = 16, BUDGET_CLKS = 64452
	if (argc > 1) cfg.phase_clks = atoi(argv[1]);
	printf("sega_xy: phase_clks = %d, budget_clks = %d\n",
	       cfg.phase_clks, cfg.budget_clks);

	std::mt19937 rng(12345);

	int fails = 0, cases = 0;
	long total_samples = 0;
	// coverage: a passing test is only meaningful if it reached these paths
	long cov_beam_on = 0, cov_clipped = 0, cov_dots = 0, cov_budget_end = 0;
	long biggest = 0;

	enum Kind { STRUCTURED, RANDOM, OVERSIZED, REALDUMP };
	struct Case { const char *name; Kind kind; int nsym; };
	std::vector<Case> plan;
	for (int i = 0; i < 24; i++) plan.push_back({ "structured", STRUCTURED, 1 + (i % 12) });
	for (int i = 0; i < 12; i++) plan.push_back({ "random",     RANDOM,     0 });
	for (int i = 0; i <  6; i++) plan.push_back({ "oversized",  OVERSIZED,  0 });
	for (size_t i = 0; i < real_dumps.size(); i++)
		plan.push_back({ "real", REALDUMP, (int)i });

	for (auto &c : plan) {
		switch (c.kind) {
			case STRUCTURED: build_structured(rig.vram, rng, c.nsym); break;
			case RANDOM:     build_random(rig.vram, rng);             break;
			case OVERSIZED:  build_oversized(rig.vram, rng);          break;
			case REALDUMP: {
				FILE *f = fopen(real_dumps[c.nsym].c_str(), "rb");
				if (!f) continue;
				if (fread(rig.vram, 1, VRAM_SIZE, f) != VRAM_SIZE) { fclose(f); continue; }
				fclose(f);
				break;
			}
		}

		std::vector<VecSample> want, got;
		sega_xy_golden(rig.vram, rig.sintab, cfg, want);

		if (!rig.run(got)) {
			printf("  %s case %d: RTL never asserted frame_done\n", c.name, cases);
			fails++;
			cases++;
			continue;
		}

		char label[64];
		snprintf(label, sizeof label, "%s case %d", c.name, cases);
		fails += compare(label, want, got);
		total_samples += (long)want.size();
		if ((long)want.size() > biggest) biggest = (long)want.size();

		// A sample sitting exactly on a clip rail with the beam off, while the
		// vector had a colour, means the clip logic fired.
		for (size_t i = 1; i < want.size(); i++) {
			const VecSample &s2 = want[i];
			if (s2.beam) cov_beam_on++;
			else if (s2.colour != 0 &&
			         (s2.x == 0 || s2.x == 1023 || s2.y == 0 || s2.y == 1023))
				cov_clipped++;
			if (s2.colour != 0 && want[i-1].colour != s2.colour) cov_dots++;
		}
		// the budget ran out if the list did not end on its own terminator
		{
			XyConfig big = cfg; big.budget_clks = cfg.budget_clks * 4;
			std::vector<VecSample> longer;
			sega_xy_golden(rig.vram, rig.sintab, big, longer);
			if (longer.size() > want.size()) cov_budget_end++;
		}
		cases++;
	}

	printf("sega_xy: %d cases, %ld golden samples, %d failed\n",
	       cases, total_samples, fails);
	printf("  coverage: beam-on %ld, clipped %ld, colour changes %ld,"
	       " budget-limited cases %ld, largest frame %ld samples\n",
	       cov_beam_on, cov_clipped, cov_dots, cov_budget_end, biggest);
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
