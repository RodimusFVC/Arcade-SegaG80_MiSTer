// vfb_dac_ladder: the Sega G-80 2-bit-per-gun DAC, checked exhaustively.
//
// Reference is the resistor network on X-Y Control drawing 800-0163 sheet 6/6:
// each gun has a 2-bit weighted ladder giving 0, 1/3, 2/3 and full scale.
// Major Havoc's renderer had a level ladder on red only (its {strong, fine}
// pair); this generalises it to all three guns, so it is worth pinning down.

#include <cstdio>
#include <cstdint>
#include "Vvfb_dac_ladder.h"
#include "verilated.h"

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	auto *dut = new Vvfb_dac_ladder;

	long checked = 0;
	int  fails = 0, worst = 0, worst_lvl = 0, worst_v = 0;

	for (int v = 0; v < 1024; v++) {
		for (int sel = 0; sel < 4; sel++) {
			dut->level = v; dut->sel = sel; dut->eval();

			// exact ladder value, rounded down as the fixed-point form does
			int want;
			switch (sel) {
				case 0:  want = 0;         break;
				case 1:  want = v / 3;     break;
				case 2:  want = (2*v) / 3; break;
				default: want = v;         break;
			}
			int got = dut->out;
			int err = got - want;
			if (err < 0) err = -err;
			if (err > worst) { worst = err; worst_lvl = sel; worst_v = v; }

			checked++;
			// the fixed-point thirds must stay within one LSB of exact
			if (err > 1) {
				if (fails < 8)
					printf("FAIL level=%d sel=%d: want %d got %d\n", v, sel, want, got);
				fails++;
			}
			// levels 0 and 3 must be exact
			if ((sel == 0 || sel == 3) && got != want) {
				printf("FAIL level=%d sel=%d must be exact: want %d got %d\n",
				       v, sel, want, got);
				fails++;
			}
		}
	}

	// monotonic in both arguments
	for (int v = 1; v < 1024; v++) {
		for (int sel = 0; sel < 4; sel++) {
			dut->level = v - 1; dut->sel = sel; dut->eval();
			int lo = dut->out;
			dut->level = v; dut->eval();
			if (dut->out < lo) { printf("FAIL not monotonic in level at %d sel %d\n", v, sel); fails++; }
		}
	}
	for (int v = 0; v < 1024; v++) {
		int prev = -1;
		for (int sel = 0; sel < 4; sel++) {
			dut->level = v; dut->sel = sel; dut->eval();
			if ((int)dut->out < prev) { printf("FAIL not monotonic in sel at %d\n", v); fails++; }
			prev = dut->out;
		}
	}

	// spot checks at full scale
	struct { int sel; int want; const char *what; } spot[] = {
		{ 0,    0, "gun off" },
		{ 1,  341, "1/3 scale" },
		{ 2,  682, "2/3 scale" },
		{ 3, 1023, "full scale" },
	};
	for (auto &t : spot) {
		dut->level = 1023; dut->sel = t.sel; dut->eval();
		int err = (int)dut->out - t.want; if (err < 0) err = -err;
		printf("  %-4s %-11s level=1023 -> %4u\n", err <= 1 ? "ok" : "FAIL",
		       t.what, (unsigned)dut->out);
		if (err > 1) fails++;
	}

	dut->final(); delete dut;
	printf("vfb_dac_ladder: %ld checked, %d failed, worst error %d LSB (level=%d sel=%d)\n",
	       checked, fails, worst, worst_v, worst_lvl);
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
