// usb_filter (RTL) vs MAME's double-precision analog chain.
//
// This one is deliberately NOT a bit-exact comparison. MAME's chain is itself
// an approximation of the PCB ("just an approximation to the pink noise filter
// ... but it sounds pretty close") and runs in doubles; the RTL is Q8.24 with
// power-of-two coefficients. So the bench asks the questions that actually
// matter for a filter: does it track the reference in shape (correlation),
// magnitude (RMS ratio) and level (peak), and does it stay bounded?
//
// It also checks coverage, because a filter comparison that passes on silence
// proves nothing: both config modes, both gate speeds and real output swing
// are all required.

#include <cstdio>
#include <cstdint>
#include <cmath>
#include <random>
#include "Vusb_filter.h"
#include "verilated.h"
#include "usb_filter_golden.h"

static Vusb_filter *dut;
static void tick_clk() { dut->clk = 1; dut->eval(); dut->clk = 0; dut->eval(); }

// CLK_HZ 12.096 MHz / 2 MHz stream rate
static const int CLKS_PER_TICK = 6;

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	dut = new Vusb_filter;
	UsbFilterGolden ref;

	dut->clk = 0; dut->reset = 1; dut->tick = 0; dut->noise_in = 0;
	dut->tmr0 = dut->tmr1 = dut->tmr2 = 0;
	dut->env0_0 = dut->env0_1 = dut->env0_2 = 0;
	dut->env1_0 = dut->env1_1 = dut->env1_2 = 0;
	dut->env2_0 = dut->env2_1 = dut->env2_2 = 0;
	dut->cfg = 0;
	for (int i = 0; i < 8; i++) tick_clk();
	dut->reset = 0;
	ref.reset();

	std::mt19937 rng(20250804);

	// stimulus state
	uint32_t noise_shift = 0x15555;
	int      noise_sub = 0, noise_state = 0;
	int      tmr[3][3] = {{0}}, env[3][3] = {{0}}, cfg[3] = {0, 0, 0};
	int      period[3][3];
	int      phase[3][3] = {{0}};
	for (int g = 0; g < 3; g++)
		for (int c = 0; c < 3; c++) period[g][c] = 20 + (int)(rng() % 400);

	// statistics
	double sum_gg = 0, sum_rr = 0, sum_gr = 0, sum_g = 0, sum_r = 0;
	double peak_g = 0, peak_r = 0, peak_err = 0;
	long   n = 0;
	int    cfg_seen[2] = {0, 0}, fast_seen[2] = {0, 0};
	long   saturated = 0;
	int    fails = 0;

	const long SAMPLES = 400000;
	for (long s = 0; s < SAMPLES; s++) {
		// MM5837 at 2 MHz / 20
		if (noise_sub-- == 0) {
			noise_shift = ((noise_shift << 1)
			            | (((noise_shift >> 13) ^ (noise_shift >> 16)) & 1)) & 0x1ffff;
			noise_state = (noise_shift >> 16) & 1;
			noise_sub += 20;
		}

		// square waves on every 8253 channel, and envelopes/config that
		// change slowly the way the 8035 program would drive them
		for (int g = 0; g < 3; g++)
			for (int c = 0; c < 3; c++)
				if (++phase[g][c] >= period[g][c]) { phase[g][c] = 0; tmr[g][c] ^= 1; }

		if ((s % 5000) == 0) {
			for (int g = 0; g < 3; g++) {
				for (int c = 0; c < 3; c++) {
					env[g][c] = (int)(rng() % 256);
					period[g][c] = 20 + (int)(rng() % 400);
				}
				cfg[g] = (int)(rng() & 1);
			}
		}

		for (int g = 0; g < 3; g++) { cfg_seen[cfg[g]]++; fast_seen[tmr[g][2]]++; }

		// drive the RTL
		dut->noise_in = noise_state;
		dut->tmr0 = (tmr[0][2] << 2) | (tmr[0][1] << 1) | tmr[0][0];
		dut->tmr1 = (tmr[1][2] << 2) | (tmr[1][1] << 1) | tmr[1][0];
		dut->tmr2 = (tmr[2][2] << 2) | (tmr[2][1] << 1) | tmr[2][0];
		dut->env0_0 = env[0][0]; dut->env0_1 = env[0][1]; dut->env0_2 = env[0][2];
		dut->env1_0 = env[1][0]; dut->env1_1 = env[1][1]; dut->env1_2 = env[1][2];
		dut->env2_0 = env[2][0]; dut->env2_1 = env[2][1]; dut->env2_2 = env[2][2];
		dut->cfg = (cfg[2] << 2) | (cfg[1] << 1) | cfg[0];

		dut->tick = 1; tick_clk(); dut->tick = 0;
		for (int i = 1; i < CLKS_PER_TICK; i++) tick_clk();

		// the RTL carries 12 dB of headroom: MAME's nominal 1.0 is 8192 counts
		int16_t raw  = (int16_t)dut->audio;
		double  want = ref.step(noise_state, tmr, env, cfg);
		double  got  = (double)raw / 8192.0;
		if (raw == 32767 || raw == -32768) saturated++;

		// let both settle before scoring; the final CR filter has a 0.5 s
		// time constant, so early samples are dominated by its DC transient
		if (s > 50000) {
			sum_gg += want * want;
			sum_rr += got * got;
			sum_gr += want * got;
			sum_g  += want;
			sum_r  += got;
			if (std::fabs(want) > peak_g)          peak_g = std::fabs(want);
			if (std::fabs(got)  > peak_r)          peak_r = std::fabs(got);
			if (std::fabs(want - got) > peak_err)  peak_err = std::fabs(want - got);
			n++;
		}

		if (!std::isfinite(want)) { printf("golden went non-finite at %ld\n", s); fails++; break; }
	}

	double mean_g = sum_g / n, mean_r = sum_r / n;
	double var_g  = sum_gg / n - mean_g * mean_g;
	double var_r  = sum_rr / n - mean_r * mean_r;
	double cov    = sum_gr / n - mean_g * mean_r;
	double corr   = cov / std::sqrt(var_g * var_r);
	double rms_g  = std::sqrt(sum_gg / n), rms_r = std::sqrt(sum_rr / n);

	printf("usb_filter: %ld samples scored\n", n);
	printf("  golden  rms %.5f  peak %.5f  mean %+.5f\n", rms_g, peak_g, mean_g);
	printf("  rtl     rms %.5f  peak %.5f  mean %+.5f\n", rms_r, peak_r, mean_r);
	printf("  correlation %.5f   rms ratio %.4f   peak abs error %.5f\n",
	       corr, rms_r / rms_g, peak_err);
	printf("  saturated samples %ld   headroom used %.2f of 4.0\n", saturated, peak_r);
	printf("  coverage: config0 %d config1 %d  gate-slow %d gate-fast %d\n",
	       cfg_seen[0], cfg_seen[1], fast_seen[0], fast_seen[1]);

	// The RTL must follow the reference in shape and magnitude. These bounds
	// are loose because the reference is not authoritative, but they are far
	// tighter than anything a broken filter would pass.
	if (corr < 0.98)                       { printf("  FAIL correlation too low\n");  fails++; }
	if (rms_r / rms_g < 0.90 || rms_r / rms_g > 1.10)
	                                       { printf("  FAIL rms ratio out of band\n"); fails++; }
	if (rms_r < 1e-4)                      { printf("  FAIL rtl output is silent\n"); fails++; }
	if (saturated)                         { printf("  FAIL rtl saturated %ld samples\n", saturated); fails++; }

	// A pass on a degenerate stimulus proves nothing.
	if (cfg_seen[0] < 10000 || cfg_seen[1] < 10000)
		{ printf("  FAIL both envelope configs not exercised\n"); fails++; }
	if (fast_seen[0] < 10000 || fast_seen[1] < 10000)
		{ printf("  FAIL both gate filter speeds not exercised\n"); fails++; }

	dut->final();
	delete dut;
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
