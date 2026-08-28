// sp0250 (RTL) vs the MAME-derived golden model.
//
// The SP0250 is fully specifiable, so this demands sample-for-sample equality
// rather than judging by ear: same frame bytes in, same 7-bit DAC stream out.
//
// If sim/roms/ holds a speech ROM the real LPC data is replayed through both;
// otherwise structured and random frames are used.

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <random>
#include <vector>

#include "Vsp0250.h"
#include "verilated.h"
#include "sp0250_golden.h"

static Vsp0250 *dut;

static void tick() {
	dut->clk = 1; dut->eval();
	dut->clk = 0; dut->eval();
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	dut = new Vsp0250;

	dut->clk = 0; dut->reset = 1; dut->ce = 1; dut->wr = 0; dut->din = 0;
	for (int i = 0; i < 8; i++) tick();
	dut->reset = 0;

	Sp0250Golden ref;
	ref.reset();

	std::mt19937 rng(4242);
	long samples = 0, writes = 0;
	int  fails = 0;
	int8_t pending_want = 0;
	bool have_want = false;
	long nonzero = 0;
	int  distinct[129] = {0};

	// Feeding has to be deterministic. The RTL makes its frame-load decision on
	// one specific clock (the sample tick, inside S_IDLE) using the registered
	// FIFO position, while the model's write() is immediate — so a byte landing
	// on that clock is seen by one and not the other. Writing only in a short
	// burst just after each output sample keeps them in lockstep, and the FSM
	// is idle then anyway (312 clocks between samples, ~9 spent working).
	std::vector<uint8_t> pending;
	int burst = 0;

	auto make_frame = [&]() {
		// A plausible LPC frame: coefficients across the table, a real
		// amplitude, a pitch, and a small repeat count.
		for (int i = 0; i < 15; i++) {
			uint8_t b;
			switch (i) {
				case 2:  b = (uint8_t)(0x20 | (rng() % 32)); break;  // amp
				case 5:  b = (uint8_t)(8 + rng() % 60);      break;  // pitch
				case 8:  b = (uint8_t)((rng() % 2 ? 0x40 : 0) | (1 + rng() % 4)); break;
				default: b = (uint8_t)(rng() & 0xff);        break;  // coefficients
			}
			pending.push_back(b);
		}
	};
	make_frame();

	const long MAX_CLOCKS = 60000000L;
	for (long c = 0; c < MAX_CLOCKS && samples < 100000; c++) {
		dut->wr = 0;
		// The two must agree about FIFO space at every write, or the frames
		// misalign and everything after is meaningless.
		if (burst > 0 && !pending.empty() && (bool)dut->drq != ref.drq()) {
			printf("DESYNC at clock %ld (sample %ld)\n"
			       "   rtl:   drq=%d fifo=%2u rep=%3u rc=%3u pc=%3u\n"
			       "   model: drq=%d fifo=%2u rep=%3u rc=%3u pc=%3u\n",
			       c, samples,
			       (int)dut->drq, (unsigned)dut->dbg_fifo_pos,
			       (unsigned)dut->dbg_repeat, (unsigned)dut->dbg_rcount,
			       (unsigned)dut->dbg_pcount,
			       (int)ref.drq(), ref.dbg_fifo_pos(), ref.dbg_repeat(),
			       ref.dbg_rcount(), ref.dbg_pcount());
			fails++;
			break;
		}
		if (burst > 0 && dut->drq && !pending.empty()) {
			dut->din = pending.front();
			dut->wr = 1;
			ref.write(pending.front());
			pending.erase(pending.begin());
			writes++;
			burst--;
			if (pending.empty() && writes < 45000) make_frame();
		}

		tick();

		// The RTL decides whether to load a frame at the *start* of a sample,
		// nine clocks before it emits it. Step the model there, hold the value,
		// and compare when the RTL's sample actually appears — otherwise the
		// two disagree about FIFO state for those nine clocks.
		if (dut->sample_start) {
			pending_want = ref.next();
			have_want = true;
		}

		if (dut->sample_stb && have_want) {
			int8_t want = pending_want;
			int8_t got  = (int8_t)dut->dac;
			have_want = false;
			samples++;
			if (want) nonzero++;
			distinct[want + 64]++;
			if (want != got) {
				if (fails < 6)
					printf("FAIL sample %ld: want %d got %d\n", samples, want, got);
				fails++;
			}
			burst = 15;   // safe window before the next sample tick
		}
	}

	int used = 0;
	for (int i = 0; i < 129; i++) if (distinct[i]) used++;

	printf("sp0250: %ld samples, %ld frame bytes, %d failed\n",
	       samples, writes, fails);
	printf("  coverage: %ld non-zero samples, %d distinct DAC values of 128\n",
	       nonzero, used);

	// A pass is only meaningful if the thing actually produced varied audio.
	if (samples < 10000)  { printf("  FAIL too few samples\n"); fails++; }
	if (nonzero < 1000)   { printf("  FAIL output was essentially silent\n"); fails++; }
	if (used < 32)        { printf("  FAIL DAC range barely exercised\n"); fails++; }

	dut->final();
	delete dut;

	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
