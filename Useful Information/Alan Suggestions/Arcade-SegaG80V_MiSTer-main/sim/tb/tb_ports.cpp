// CPU-board I/O blocks vs MAME (refs/mame/segag80v.cpp).
//
//   mangled_ports_r   exhaustive over sel, swept over the four source bytes
//   multiply_w/_r     random operand pairs, both result bytes
//   spinner_input_r   random walk, checking the monotonic count and sign bit
//   elim4_input_r     exhaustive over the select latch

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <random>

#include "Vports_wrap.h"
#include "verilated.h"

static Vports_wrap *dut;

static void tick() {
	dut->clk = 1; dut->eval();
	dut->clk = 0; dut->eval();
}

// ---- MAME references ------------------------------------------------------

static uint8_t ref_mangled(int off, uint8_t d7d6, uint8_t d5d4,
                           uint8_t d3d2, uint8_t d1d0) {
	auto BIT = [](uint8_t v, int n) { return (v >> n) & 1; };
	off &= 3;
	return (uint8_t)(
		(BIT(d7d6, off + 0) << 7) | (BIT(d7d6, off + 4) << 6) |
		(BIT(d5d4, off + 0) << 5) | (BIT(d5d4, off + 4) << 4) |
		(BIT(d3d2, off + 0) << 3) | (BIT(d3d2, off + 4) << 2) |
		(BIT(d1d0, off + 0) << 1) | (BIT(d1d0, off + 4) << 0));
}

static uint8_t ref_elim4(uint8_t sel, uint8_t fc, uint8_t coins) {
	uint8_t result = 0;
	if ((sel >> 3) & 1) {
		switch (sel & 7) {
			case 6: result = fc;    break;
			case 7: result = coins; break;
			default: result = 0;    break;
		}
	}
	return (uint8_t)(result ^ 0xFF);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	dut = new Vports_wrap;

	dut->clk = 0; dut->reset = 1;
	dut->mul_wr = 0; dut->mul_rd = 0; dut->spin_stb = 0;
	for (int i = 0; i < 4; i++) tick();
	dut->reset = 0;
	tick();

	long checked = 0;
	int  fails = 0;
	std::mt19937 rng(999);

	// ---- mangled input matrix -------------------------------------------
	for (int trial = 0; trial < 4096; trial++) {
		uint8_t a = rng() & 0xff, b = rng() & 0xff;
		uint8_t c = rng() & 0xff, d = rng() & 0xff;
		for (int sel = 0; sel < 4; sel++) {
			dut->sel = sel;
			dut->d7d6 = a; dut->d5d4 = b; dut->d3d2 = c; dut->d1d0 = d;
			dut->eval();
			uint8_t want = ref_mangled(sel, a, b, c, d);
			checked++;
			if (dut->mangled != want) {
				if (fails < 5)
					printf("FAIL mangled sel=%d %02X %02X %02X %02X: want %02X got %02X\n",
					       sel, a, b, c, d, want, (uint8_t)dut->mangled);
				fails++;
			}
		}
	}

	// ---- eliminator 4-player demux, exhaustive over the select latch -----
	for (int sel = 0; sel < 256; sel++) {
		uint8_t fc = rng() & 0xff, coins = rng() & 0xff;
		dut->e4_sel = sel; dut->fc_in = fc; dut->e4_coins = coins;
		dut->eval();
		uint8_t want = ref_elim4((uint8_t)sel, fc, coins);
		checked++;
		if (dut->e4_dout != want) {
			if (fails < 5)
				printf("FAIL elim4 sel=%02X fc=%02X coins=%02X: want %02X got %02X\n",
				       sel, fc, coins, want, (uint8_t)dut->e4_dout);
			fails++;
		}
	}

	// ---- multiplier ------------------------------------------------------
	for (int trial = 0; trial < 2000; trial++) {
		uint8_t o0 = rng() & 0xff, o1 = rng() & 0xff;

		dut->mul_wr = 1; dut->mul_wr_sel = 0; dut->mul_din = o0; tick();
		dut->mul_wr = 1; dut->mul_wr_sel = 1; dut->mul_din = o1; tick();
		dut->mul_wr = 0;

		uint16_t want = (uint16_t)(o0 * o1);

		dut->eval();
		uint8_t lo = dut->mul_dout;
		dut->mul_rd = 1; tick(); dut->mul_rd = 0;
		dut->eval();
		uint8_t hi = dut->mul_dout;

		checked += 2;
		if (lo != (want & 0xff) || hi != (want >> 8)) {
			if (fails < 5)
				printf("FAIL mult %02X*%02X: want %04X got %02X%02X\n",
				       o0, o1, want, hi, lo);
			fails++;
		}
	}

	// ---- spinner ---------------------------------------------------------
	// MAME: count += abs(delta) on a non-zero sample, sign = delta < 0,
	//       port returns ~((count << 1) | sign) as a byte.
	{
		uint8_t count = 0, sign = 0;
		dut->sel_raw = 0;
		for (int trial = 0; trial < 4000; trial++) {
			int8_t delta = (int8_t)(rng() & 0xff);
			dut->spin_delta = delta;
			dut->spin_stb = 1; tick(); dut->spin_stb = 0;

			if (delta != 0) {
				sign  = (uint8_t)((delta >> 7) & 1);
				count = (uint8_t)(count + (uint8_t)(delta < 0 ? -delta : delta));
			}
			uint8_t want = (uint8_t)~(((count << 1) | sign) & 0xff);

			dut->eval();
			checked++;
			if (dut->spin_dout != want) {
				if (fails < 5)
					printf("FAIL spinner trial %d delta=%d: want %02X got %02X\n",
					       trial, delta, want, (uint8_t)dut->spin_dout);
				fails++;
			}
		}

		// select bit 0 switches the port over to the raw FC inputs
		dut->sel_raw = 1; dut->fc_in = 0x5A; dut->eval();
		checked++;
		if (dut->spin_dout != 0x5A) {
			printf("FAIL spinner raw passthrough: want 5A got %02X\n",
			       (uint8_t)dut->spin_dout);
			fails++;
		}
	}

	dut->final();
	delete dut;

	printf("sega_ports: %ld checked, %d failed\n", checked, fails);
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
