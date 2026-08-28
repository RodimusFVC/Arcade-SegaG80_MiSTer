// usb_timer (RTL) vs the MAME-derived 8253 model.
//
// The timer is an exact integer state machine, so this demands identical
// outputs on every clock: same register writes, same gates, same edges.

#include <cstdio>
#include <cstdint>
#include <random>
#include "Vusb_timer.h"
#include "verilated.h"
#include "usb_timer_golden.h"

static Vusb_timer *dut;
static void tick() { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	dut = new Vusb_timer;
	UsbTimerGolden ref;

	dut->clk = 0; dut->reset = 1; dut->wr = 0;
	dut->addr = 0; dut->din = 0; dut->ch_clk = 0; dut->ch_gate = 0;
	for (int i = 0; i < 4; i++) tick();
	dut->reset = 0;
	ref.reset();

	std::mt19937 rng(20250804);
	long checked = 0, clocks = 0, writes = 0;
	int  fails = 0;
	int  edges[3] = {0, 0, 0};
	int  last_out[3] = {-1, -1, -1};

	for (long c = 0; c < 2000000; c++) {
		// occasional register programming, weighted towards the modes the
		// board actually uses (1 and 3) but not exclusively
		dut->wr = 0;
		if ((rng() % 400) == 0) {
			uint8_t off = (uint8_t)(rng() % 4);
			uint8_t data;
			if (off == 3) {
				uint8_t chan = (uint8_t)(rng() % 4);              // 3 = read-back
				uint8_t lm   = (uint8_t)(1 + rng() % 3);          // latch modes 1..3
				uint8_t cm   = (rng() % 2) ? 1 : 3;               // clock mode 1 or 3
				if ((rng() % 8) == 0) cm = (uint8_t)(rng() % 8);  // and the rest
				data = (uint8_t)((chan << 6) | (lm << 4) | (cm << 1) | (rng() & 1));
			} else {
				data = (uint8_t)(rng() & 0xff);
			}
			dut->wr = 1; dut->addr = off; dut->din = data;
			ref.write(off, data);
			writes++;
		}

		// gates and per-channel clock enables
		uint8_t gate = (uint8_t)(rng() & 7);
		uint8_t cclk = 0;
		for (int i = 0; i < 3; i++) if ((rng() % 3) == 0) cclk |= (uint8_t)(1 << i);
		dut->ch_gate = gate;
		dut->ch_clk  = cclk;
		for (int i = 0; i < 3; i++) ref.set_gate(i, (gate >> i) & 1);

		tick();

		for (int i = 0; i < 3; i++) if (cclk & (1 << i)) { ref.clock(i); clocks++; }

		int got = dut->out;
		for (int i = 0; i < 3; i++) {
			int w = ref.out(i), g = (got >> i) & 1;
			checked++;
			if (w != g) {
				if (fails < 6)
					printf("FAIL clock %ld ch%d: want %d got %d\n", c, i, w, g);
				fails++;
			}
			if (last_out[i] >= 0 && w != last_out[i]) edges[i]++;
			last_out[i] = w;
		}
	}

	printf("usb_timer: %ld output comparisons, %ld channel clocks, %ld writes, %d failed\n",
	       checked, clocks, writes, fails);
	printf("  coverage: output transitions ch0=%d ch1=%d ch2=%d\n",
	       edges[0], edges[1], edges[2]);

	// A pass means nothing if the timers never toggled.
	for (int i = 0; i < 3; i++)
		if (edges[i] < 50) { printf("  FAIL channel %d barely toggled\n", i); fails++; }

	dut->final();
	delete dut;
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
