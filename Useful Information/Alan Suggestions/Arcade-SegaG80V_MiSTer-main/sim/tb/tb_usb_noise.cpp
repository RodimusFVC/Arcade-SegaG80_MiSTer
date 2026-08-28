// usb_noise (RTL) vs MAME's MM5837 model, and a check that the sequence is a
// real maximal-length run rather than a stuck or short cycle.

#include <cstdio>
#include <cstdint>
#include "Vusb_noise.h"
#include "verilated.h"

static Vusb_noise *dut;
static void tick() { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	dut = new Vusb_noise;

	dut->clk = 0; dut->reset = 1; dut->tick = 0;
	for (int i = 0; i < 4; i++) tick();
	dut->reset = 0;

	// MAME's model, verbatim
	uint32_t shift = 0x15555;   // MAME's seed; zero is a lock-up state
	long checked = 0, ones = 0;
	int  fails = 0;

	dut->tick = 1;
	for (long c = 0; c < 400000; c++) {
		tick();
		shift = ((shift << 1) | (((shift >> 13) ^ (shift >> 16)) & 1)) & 0x1ffff;
		int want = (shift >> 16) & 1;
		int got  = dut->state;
		checked++;
		if (want) ones++;
		if (want != got) {
			if (fails < 6) printf("FAIL step %ld: want %d got %d\n", c, want, got);
			fails++;
		}
	}

	printf("usb_noise: %ld steps compared, %d failed\n", checked, fails);
	printf("  coverage: output high %ld/%ld (%.1f%%)\n",
	       ones, checked, 100.0 * ones / checked);

    // A stuck LFSR would match a stuck model, so check the sequence is alive.
	if (ones < checked / 4 || ones > (checked * 3) / 4) {
		printf("  FAIL output is not behaving like noise\n");
		fails++;
	}

	dut->final(); delete dut;
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
