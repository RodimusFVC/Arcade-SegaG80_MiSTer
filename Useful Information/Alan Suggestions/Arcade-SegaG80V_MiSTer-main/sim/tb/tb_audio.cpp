// Audio capture: run a real game through the whole machine and write WAVs.
//
// This exists so the sound boards can be listened to before a Quartus build.
// It instantiates segag80v — CPU, X-Y boards, AY, speech board and Universal
// Sound Board — feeds it a real ROM image, drops a coin, presses start, and
// records every audio source separately at 48 kHz.
//
// clk_vec is 12.096 MHz and 12096000 / 48000 = 252 exactly, so no resampling
// is needed: one output sample every 252 clocks.
//
// For the Universal Sound Board it also runs MAME's double-precision analog
// chain from the same stimulus, tapped out of the RTL, and writes that as a
// second file. That is the honest A/B — the digital half is bit-exact against
// MAME, so any audible difference between those two files is entirely down to
// the fixed-point filter approximation.
//
//   ./Vsegag80v <rom> <game-id> <seconds> <out-prefix>
//
// game-id matches sega_game_pkg: 0 elim2, 1 elim4, 2 spacfury, 3 zektor,
// 4 tacscan, 5 startrek.

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <vector>
#include <map>
#include <string>
#include "Vaudio_wrap.h"
#include "verilated.h"
#include "usb_filter_golden.h"

static const int  CLK_HZ      = 12096000;
static const int  SAMPLE_HZ   = 48000;
static const int  CLKS_PER_SAMPLE = CLK_HZ / SAMPLE_HZ;   // 252, exact
static const int  ROM_SIZE    = 0x10C00;

// ---------------------------------------------------------------------------
// Per-game configuration. Mirrors sega_game_cfg in rtl/sega_game_pkg.sv and the
// start-button positions in rtl/sega_inputs.sv.
// ---------------------------------------------------------------------------
// Everything about wiring now comes from sega_game_cfg and sega_inputs inside
// the harness; all this table carries is MAME's DIP defaults and which boards
// are fitted (so the bench knows which files are worth writing).
//
// The SW1 defaults matter: bit 1 of D3D2 is Demo Sounds and MAME defaults it to
// 0 = On. Holding that byte at 0xFF turns off the attract sound entirely.
struct GameCfg {
	const char *name;
	int  usb, speech, ay, disc;
	uint8_t dsw1, dsw2;
};
static const GameCfg GAMES[6] = {
	{ "elim2",    0, 0, 0, 1, 0x45, 0x33 },
	{ "elim4",    0, 0, 0, 1, 0x45, 0x00 },
	{ "spacfury", 0, 1, 0, 1, 0x8D, 0x33 },
	{ "zektor",   0, 1, 1, 1, 0x8D, 0x33 },
	{ "tacscan",  1, 0, 0, 0, 0x8D, 0x33 },
	{ "startrek", 1, 1, 0, 0, 0x8D, 0x33 },
};

// ---------------------------------------------------------------------------
static void write_wav(const std::string &path, const std::vector<int16_t> &pcm) {
	FILE *f = fopen(path.c_str(), "wb");
	if (!f) { printf("cannot write %s\n", path.c_str()); return; }
	uint32_t data_bytes = (uint32_t)(pcm.size() * 2);
	uint32_t byte_rate  = SAMPLE_HZ * 2;
	auto u32 = [&](uint32_t v) { fwrite(&v, 4, 1, f); };
	auto u16 = [&](uint16_t v) { fwrite(&v, 2, 1, f); };
	fwrite("RIFF", 1, 4, f); u32(36 + data_bytes); fwrite("WAVE", 1, 4, f);
	fwrite("fmt ", 1, 4, f); u32(16); u16(1); u16(1);
	u32(SAMPLE_HZ); u32(byte_rate); u16(2); u16(16);
	fwrite("data", 1, 4, f); u32(data_bytes);
	fwrite(pcm.data(), 2, pcm.size(), f);
	fclose(f);
}

static double peak_dbfs(const std::vector<int16_t> &pcm, int &peak_out) {
	int peak = 0;
	for (int16_t s : pcm) if (abs(s) > peak) peak = abs(s);
	peak_out = peak;
	return peak ? 20.0 * log10((double)peak / 32768.0) : -999.0;
}

// Peak-normalise to -3 dBFS so quiet boards are actually audible in headphones.
static std::vector<int16_t> normalise(const std::vector<int16_t> &pcm) {
	int peak = 0;
	for (int16_t s : pcm) if (abs(s) > peak) peak = abs(s);
	std::vector<int16_t> out(pcm.size());
	if (!peak) return out;
	double g = 23197.0 / peak;                 // -3 dBFS
	for (size_t i = 0; i < pcm.size(); i++) {
		double v = pcm[i] * g;
		if (v >  32767) v =  32767;
		if (v < -32768) v = -32768;
		out[i] = (int16_t)lrint(v);
	}
	return out;
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 5) {
		printf("usage: tb_audio <rom> <game-id 0-5> <seconds> <out-prefix>\n");
		return 2;
	}
	const char *rompath = argv[1];
	int   gid     = atoi(argv[2]);
	double secs   = atof(argv[3]);
	std::string prefix = argv[4];
	if (gid < 0 || gid > 5) { printf("game-id must be 0..5\n"); return 2; }
	const GameCfg &G = GAMES[gid];

	static uint8_t rom[ROM_SIZE];
	FILE *f = fopen(rompath, "rb");
	if (!f) { printf("cannot open %s\n", rompath); return 2; }
	size_t got = fread(rom, 1, ROM_SIZE, f);
	fclose(f);
	printf("=== %s (%s), %.1f s ===\n", G.name, rompath, secs);
	printf("  ROM image %zu bytes, SW1 %02X SW2 %02X, usb %d, speech %d\n",
	       got, G.dsw1, G.dsw2, G.usb, G.speech);

	auto *dut = new Vaudio_wrap;
	UsbFilterGolden ref;

	auto tick = [&]() {
		dut->clk = 1; dut->eval();
		dut->clk = 0; dut->eval();
	};

	// ---- reset and idle inputs ------------------------------------------
	dut->clk = 0; dut->reset = 1;
	dut->game = gid;
	dut->dsw1 = G.dsw1; dut->dsw2 = G.dsw2;
	dut->joy1 = 0; dut->joy2 = 0;
	dut->rom_wr = 0; dut->rom_addr = 0; dut->rom_data = 0;
	for (int i = 0; i < 8; i++) tick();

	// ---- ROM download, the way the MRA stream does it --------------------
	for (int a = 0; a < ROM_SIZE; a++) {
		dut->rom_wr = 1; dut->rom_addr = a; dut->rom_data = rom[a];
		tick();
	}
	dut->rom_wr = 0;
	tick();
	dut->reset = 0;

	// ---- run -------------------------------------------------------------
	long total = (long)(secs * CLK_HZ);
	std::vector<int16_t> w_mix, w_ay, w_speech, w_usb, w_usb_mame, w_disc;

	// The board is idle in attract mode on some games, so drop a coin and hit
	// start. Times are in seconds of emulated machine time.
	// Late enough that the game has finished its self-test and reached
	// attract mode; dropping a coin during the test does nothing.
	// The coin must be held long enough to pass debounce but released before
	// the game's wait-for-release loop times out: Space Fury counts down from
	// 231 tries at ~0.67 ms each and rejects the coin if fewer than 31 tries
	// elapsed (too short) or the loop ran out at ~155 ms (stuck coin). 100 ms
	// sits in the middle. Holding it 250 ms, as this bench first did, is
	// rejected outright.
	const double COIN_AT = 8.0, COIN_FOR = 0.10;
	const double START_AT = 8.4, START_FOR = 0.25;

	long    sub = 0;
	double  usb_mame_peak = 0;
	int16_t usb_last_mame = 0;
	int    tmr[3][3] = {{0}}, env[3][3] = {{0}}, cfg[3] = {0, 0, 0};
	long   usb_ticks = 0;

	// Liveness. Without these, "peak 0" cannot be told apart from a machine
	// that never ran at all.
	long frames = 0, ay_writes = 0, sp_data = 0, sp_ctrl = 0, usb_writes = 0;
	long beam_on = 0;
	long coin_pulses = 0;
	bool p_coin = false, p_cff = false, p_irq = false, p_snd = false;
	std::map<int,long> lov, hiv;
	long irqs = 0;
	bool p_done = false, p_ay = false, p_spd = false, p_spc = false, p_usb = false;
	// speech board internals
	std::set<int> sp_pc;
	long sp_frames = 0, sp_dac_nz = 0, sp_drq_edges = 0, sp_t0_edges = 0;
	int  sp_dac_peak = 0;
	bool p_drq = false, p_t0 = false;
	long sp_reads = 0;
	std::set<int> sp_daddr;
	std::vector<int> pctrace;

	for (long c = 0; c < total; c++) {
		double t = (double)c / CLK_HZ;

		// MiSTer joystick bits: 8 = start1, 10 = coin
		// Two coins, then press start once a second for the rest of the run.
		// A single short press is easy for a game to miss between polls.
		uint32_t j = 0;
		if ((t >= COIN_AT && t < COIN_AT + COIN_FOR) ||
		    (t >= COIN_AT + 0.5 && t < COIN_AT + 0.5 + COIN_FOR)) j |= 1u << 10;
		// Start is pulsed at 5 Hz, 50% duty, the same pattern the boot bench
		// uses. A single long press is not enough: the games sample START at
		// specific points and want to see it released between presses.
		if (t >= START_AT) {
			double ph = (t - START_AT) * 5.0;
			if ((long)ph & 1) j |= 1u << 8;
		}
		dut->joy1 = j;

		tick();

		if (dut->dbg_coin_ff && !p_cff)
			printf("    t=%7.3f  coin flip-flop SET (%d)\n", t, dut->dbg_coin_ff);
		p_cff = (dut->dbg_coin_ff != 0);
		if (dut->dbg_irq && !p_irq) { irqs++; if (t > 7.9 && t < 8.6)
			printf("    t=%7.3f  IRQ asserted\n", t); }
		p_irq = dut->dbg_irq;
		if (dut->coin_counter && !p_coin) {
			coin_pulses++;
			printf("    t=%7.3f  coin counter pulse\n", t);
		}
		p_coin = dut->coin_counter;
		if (dut->frame_done && !p_done) frames++;
		p_done = dut->frame_done;
		if (dut->vec_valid && dut->vec_beam) beam_on++;
		if (dut->ay_wr && !p_ay)             ay_writes++;
		p_ay = dut->ay_wr;
		// $38 and $3B are levels held for the whole I/O cycle; count and log
		// the trailing edge, which is where the board latches
		if (!dut->speech_data_wr && p_spd) {
			sp_data++;
			if (sp_data <= 60)
				printf("    t=%7.3f  speech DATA <- %02X\n", t, dut->snd_data);
		}
		p_spd = dut->speech_data_wr;
		if (!dut->speech_ctrl_wr && p_spc) {
			sp_ctrl++;
			if (sp_ctrl <= 24)
				printf("    t=%7.3f  speech CTRL <- %02X\n", t, dut->snd_data);
		}
		p_spc = dut->speech_ctrl_wr;
		if (!dut->snd_wr && p_snd) {
			if (dut->snd_sel & 1) hiv[dut->snd_data]++; else lov[dut->snd_data]++;
		}
		p_snd = dut->snd_wr;
		if (dut->usb_data_wr && !p_usb)      usb_writes++;
		p_usb = dut->usb_data_wr;

		if (G.speech) {
			// handshake trace: every change, in the window where the game
			// actually asks for speech
			static int lt0 = -1, lp1 = -1, lin = -1;
			int ct0 = dut->dbg_sp_t0, cp1 = (dut->dbg_sp_p1 >> 7) & 1,
			    cin = dut->dbg_sp_int_n;
			if (t > 0.04 && t < 0.30 && (ct0 != lt0 || cp1 != lp1 || cin != lin)) {
				printf("    t=%12.6f ms  T0=%d P1.7=%d INTn=%d\n", t*1000.0, ct0, cp1, cin);
				lt0 = ct0; lp1 = cp1; lin = cin;
			}
			if (!dut->dbg_sp_rd_n) {
				sp_reads++;
				sp_daddr.insert((int)dut->dbg_sp_data_addr);
			}
			sp_pc.insert((int)dut->dbg_sp_prog_addr);
			// fetch-sequence trace: prog_addr only changes at ALE, so logging
			// changes gives the fetch order including operand bytes
			{
				static int last_pa = -1;
				int pa = (int)dut->dbg_sp_prog_addr;
				if (pa != last_pa) {
					if (t > 0.15 && (long)pctrace.size() < 4000) pctrace.push_back(pa);
					last_pa = pa;
				}
			}
			if (dut->dbg_sp_wr) sp_frames++;
			if (dut->dbg_sp_drq && !p_drq) sp_drq_edges++;
			p_drq = dut->dbg_sp_drq;
			if (dut->dbg_sp_t0 && !p_t0)   sp_t0_edges++;
			p_t0 = dut->dbg_sp_t0;
			int d = (int)(int8_t)dut->dbg_sp_dac;
			if (d) sp_dac_nz++;
			if (abs(d) > sp_dac_peak) sp_dac_peak = abs(d);
		}

		// Run MAME's chain from the RTL's own stimulus, one step per 2 MHz
		// tick, so both models see byte-identical input.
		if (G.usb && dut->dbg_usb_tick) {
			uint32_t tm = dut->dbg_usb_tmr;
			for (int g = 0; g < 3; g++)
				for (int ch = 0; ch < 3; ch++) tmr[g][ch] = (tm >> (g * 3 + ch)) & 1;
			// dbg_env is 72 bits as three 32-bit words; every envelope byte
			// starts on a byte boundary at bit (g*3+ch)*8, so none straddles
			// a word and a plain shift is enough
			for (int g = 0; g < 3; g++) {
				for (int ch = 0; ch < 3; ch++) {
					int bit = (g * 3 + ch) * 8;
					env[g][ch] = (int)((dut->dbg_usb_env[bit / 32] >> (bit % 32)) & 0xFF);
				}
				cfg[g] = (dut->dbg_usb_cfg >> g) & 1;
			}
			double v = ref.step(dut->dbg_usb_noise, tmr, env, cfg);
			if (fabs(v) > usb_mame_peak) usb_mame_peak = fabs(v);
			// same scaling the RTL uses: MAME's nominal 1.0 -> 8192
			double s = v * 8192.0;
			if (s >  32767) s =  32767;
			if (s < -32768) s = -32768;
			usb_last_mame = (int16_t)lrint(s);
			usb_ticks++;
		}

		if (++sub == CLKS_PER_SAMPLE) {
			sub = 0;
			int16_t ay = (int16_t)dut->audio_ay;         // signed, DC-blocked
			int16_t sp = (int16_t)dut->audio_speech;
			int16_t ub = (int16_t)dut->audio_usb;
			int16_t dc = (int16_t)dut->audio_discrete;
			// the same mix Arcade-SegaG80V.sv sends to AUDIO_L/R
			int mix = ay + sp + ub + dc;
			if (mix >  32767) mix =  32767;
			if (mix < -32768) mix = -32768;

			w_mix.push_back((int16_t)mix);
			w_ay.push_back(ay);
			w_speech.push_back(sp);
			w_usb.push_back(ub);
			w_usb_mame.push_back(usb_last_mame);
			w_disc.push_back(dc);
		}
	}

	// ---- write -----------------------------------------------------------
	struct Out { const char *suffix; std::vector<int16_t> *pcm; bool want; };
	Out outs[] = {
		{ "mix",      &w_mix,      true },
		{ "ay",       &w_ay,       G.ay != 0 },
		{ "speech",   &w_speech,   G.speech != 0 },
		{ "usb",      &w_usb,      G.usb != 0 },
		{ "usb_mame", &w_usb_mame, G.usb != 0 },
		{ "discrete", &w_disc,     G.disc != 0 },
	};

	printf("  %ld samples at %d Hz (%.1f s)\n", (long)w_mix.size(), SAMPLE_HZ,
	       (double)w_mix.size() / SAMPLE_HZ);
	printf("  machine: %ld frames drawn, %ld beam-on samples\n", frames, beam_on);
	{
		printf("  $3E (LO) values: ");
		for (auto &k : lov) printf("%02X x%ld  ", k.first, k.second);
		printf("\n  $3F (HI) values: ");
		for (auto &k : hiv) printf("%02X x%ld  ", k.first, k.second);
		printf("\n");
	}
	printf("  coin counter pulses: %ld, IRQ assertions %ld\n", coin_pulses, irqs);
	printf("  writes:  AY %ld, speech data %ld ctrl %ld, USB %ld\n",
	       ay_writes, sp_data, sp_ctrl, usb_writes);
	if (G.speech && !pctrace.empty()) {
		FILE *tf = fopen("audio/pctrace.txt", "w");
		for (int a : pctrace) fprintf(tf, "%03X\n", a);
		fclose(tf);
		printf("  wrote %zu fetch addresses to audio/pctrace.txt\n", pctrace.size());
	}
	if (G.speech) {
		printf("  8035 program addresses touched:");
		int n = 0;
		for (int a : sp_pc) { if (n++ % 16 == 0) printf("\n   "); printf(" %03X", a); }
		printf("\n");
	}
	if (G.speech)
		printf("  speech board: 8035 touched %zu of 2048 program addresses, "
		       "%ld SP0250 writes, %ld DRQ edges, %ld T0 edges, "
		       "DAC peak %d over %ld non-zero\n",
		       sp_pc.size(), sp_frames, sp_drq_edges, sp_t0_edges,
		       sp_dac_peak, sp_dac_nz);
	if (G.speech)
		printf("  speech data ROM: %ld MOVX read clocks, %zu distinct addresses\n",
		       sp_reads, sp_daddr.size());
	if (G.usb) printf("  USB: %ld stream ticks, MAME-model peak %.3f\n",
	                  usb_ticks, usb_mame_peak);

	for (auto &o : outs) {
		if (!o.want) continue;
		int peak;
		double db = peak_dbfs(*o.pcm, peak);
		std::string p = prefix + "_" + o.suffix + ".wav";
		write_wav(p, *o.pcm);
		printf("  %-28s peak %6d  %7.1f dBFS\n", (p + ":").c_str(), peak, db);
		if (peak && db < -12.0) {
			std::string pn = prefix + "_" + o.suffix + "_norm.wav";
			write_wav(pn, normalise(*o.pcm));
			printf("  %-28s normalised to -3 dBFS for listening\n", (pn + ":").c_str());
		}
	}

	dut->final();
	delete dut;
	return 0;
}
