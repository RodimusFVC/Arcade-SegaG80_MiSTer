// Boot a real Sega G-80 game ROM through the CPU board + X-Y boards.
//
// This is the end-to-end check: ROM fetch through wait states, the Z80 running
// real game code, the security chip scrambling its RAM writes, the 40 Hz EDGINT
// chain, the display list the game actually builds, and the beam path the X-Y
// boards walk from it.
//
//   tb_boot <rom> <chip-id> [frames]
//
// Environment:
//   DUMPVRAM=<path>  write the captured display list
//   SNAPAT=0|1|2     capture it when drawing starts (default), when drawing
//                    ends, or continuously (last value wins)
//   TRACE=<n>        print the first n distinct ROM addresses fetched
//
// Note on edge detection: vec_valid, frame_done and edgint stay asserted for
// the whole gap between VCL clock enables rather than for a single clock, so
// everything here counts rising edges.

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <set>
#include <map>
#include <vector>

#include "Vboot_wrap.h"
#include "verilated.h"

// The full image is 0x10C00 (program, sin PROM, speech CPU, speech data).
// This bench drives only the CPU and X-Y boards, so it needs the first 0xC400.
static const int ROM_SIZE  = 0x10C00;
static const int ROM_NEEDED = 0xC400;

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	if (argc < 3) { printf("usage: tb_boot <rom> <chip-id> [frames] [usb] [fc-mode]\n"); return 2; }

	const char *rompath = argv[1];
	int chip   = atoi(argv[2]);
	int frames = (argc > 3) ? atoi(argv[3]) : 3;
	int usb    = (argc > 4) ? atoi(argv[4]) : 0;
	int fc     = (argc > 5) ? atoi(argv[5]) : 0;

	static uint8_t rom[ROM_SIZE];
	FILE *f = fopen(rompath, "rb");
	if (!f) { printf("cannot open %s\n", rompath); return 2; }
	size_t got = fread(rom, 1, ROM_SIZE, f);
	fclose(f);
	if (got < ROM_NEEDED) {
		printf("%s is %zu bytes, need at least %d\n", rompath, got, ROM_NEEDED);
		return 2;
	}

	const int   snap_at  = getenv("SNAPAT") ? atoi(getenv("SNAPAT")) : 0;
	const long  trace_n  = getenv("TRACE")  ? atol(getenv("TRACE"))  : 0;
	const char *dumpvram = getenv("DUMPVRAM");
	// COINAT=<frame> drops a coin (and then presses start) so the attract
	// screen's CREDITS counter can be checked in a rendered snapshot.
	const int coinat = getenv("COINAT") ? atoi(getenv("COINAT")) : -1;
	// LOGWRITES=<path>: record the first N post-scramble vector-RAM writes so
	// the stream can be diffed against MAME's (tools/tap_vram.lua).
	const char *logwrites = getenv("LOGWRITES");
	const long  logn = getenv("LOGN") ? atol(getenv("LOGN")) : 400;
	FILE *wl = logwrites ? fopen(logwrites, "w") : nullptr;
	long wlcount = 0;
	uint16_t prev_wr_addr = 0xFFFF; uint8_t prev_wr_data = 0; bool in_wr = false;

	auto *dut = new Vboot_wrap;

	dut->clk = 0; dut->reset = 1;
	dut->cfg_chip = chip; dut->cfg_usb = usb; dut->cfg_fc = fc;
	// every switch input is active low, so idle is all ones
	dut->in_d7d6 = 0xFF; dut->in_d5d4 = 0xFF;
	dut->in_d3d2 = 0xFF; dut->in_d1d0 = 0x33;   // DIPs: 1 coin / 1 credit
	dut->in_fc = fc == 1 ? 0x00 : 0xFF; dut->in_coins = 0xFF;
	dut->coin_a = 1; dut->coin_b = 1; dut->service = 1;
	dut->prom_wr = 0; dut->prom_addr = 0; dut->prom_data = 0;
	dut->rom_data = 0;

	auto tick = [&]() {
		dut->rom_data = rom[dut->rom_addr & 0xFFFF];
		dut->eval();
		dut->clk = 1; dut->eval();
		dut->clk = 0; dut->eval();
	};

	for (int i = 0; i < 8; i++) tick();

	// load the sin/cos PROM the way the MRA stream would
	for (int a = 0; a < 1024; a++) {
		dut->prom_wr = 1; dut->prom_addr = a; dut->prom_data = rom[0xC000 + a];
		tick();
	}
	dut->prom_wr = 0;
	tick();
	dut->reset = 0;

	// ---- run ------------------------------------------------------------
	static uint8_t shadow[4096], snapshot[4096];
	memset(shadow, 0, sizeof shadow);
	memset(snapshot, 0, sizeof snapshot);

	long clocks = 0, vram_writes = 0, beam_on = 0, samples = 0, edgints = 0;
	int  frames_done = 0;
	// Universal Sound Board activity. usb_peak stays at zero unless the game
	// uploaded a program, released the 8035 from reset and it drove the DACs.
	long usb_nonzero = 0, usb_uploads = 0;
	int  usb_peak = 0;
	bool in_usb_wr = false;
	std::set<uint16_t> usb_touched;
	std::set<uint16_t> rom_pages, vram_touched;
	std::set<uint8_t>  colours;
	std::vector<uint16_t> trace;
	uint16_t last_addr = 0xFFFF;

	bool in_io_rd = false;
	int  io_logged = 0;
	std::map<int,long> f8vals;
	bool fc_start_seen = false, credit_consumed = false;
	bool f8_was_low = false;
	uint16_t last_pc_seen = 0xFFFF;
	bool in_wram_wr = false;
	int  wram_logged = 0;
	std::set<uint16_t> f8pc;
	bool prev_valid = false, prev_done = false, prev_edg = false;
	const long MAX_CLOCKS = 12000000L * frames / 40 + 4000000L;

	for (long c = 0; c < MAX_CLOCKS && frames_done < frames; c++) {
		if (coinat >= 0) {
			// coin held for ~4 frames, then START1 pressed repeatedly
			int cfor = getenv("COINFOR") ? atoi(getenv("COINFOR")) : 4;
			int cev  = getenv("COINEVERY") ? atoi(getenv("COINEVERY")) : 0;
			bool cn;
			if (cev > 0 && frames_done >= coinat)
				cn = (((frames_done - coinat) % cev) < cfor);
			else
				cn = (frames_done >= coinat && frames_done < coinat + cfor);
			dut->coin_a = cn ? 0 : 1;
			bool st = !getenv("NOSTART") && (frames_done >= coinat + 8) && ((frames_done / 4) & 1);
			if (fc == 1) dut->in_fc = st ? 0x01 : 0x00;
			else         dut->in_d5d4 = st ? (uint8_t)(0xFF & ~0x02) : 0xFF;
		}
		tick();
		clocks++;

		{
			int a = (int)(int16_t)dut->usb_audio_o;
			if (a) usb_nonzero++;
			if (abs(a) > usb_peak) usb_peak = abs(a);
			// usb_wr is a level for the whole write cycle, like vram_wr
			if (dut->usb_wr_o && !in_usb_wr) {
				usb_uploads++;
				usb_touched.insert((uint16_t)dut->usb_addr_o);
			}
			in_usb_wr = dut->usb_wr_o;
		}

		// log I/O reads of the input matrix around the coin, once per cycle
		if (dut->io_rd_o && !in_io_rd && dut->io_port_o == 0xF8)
			f8vals[dut->io_dout_o]++;
		// where do the coin/credit counter writes actually land?
		if (coinat >= 0 && dut->wram_wr_o && !in_wram_wr) {
			uint16_t raw = dut->wram_raw_o, scr = dut->wram_scr_o;
			if (frames_done >= coinat + 8 && raw == 0xC80B && dut->wram_data_o == 0)
				credit_consumed = true;
			if (raw == 0xC80B && wram_logged < 40) {
				printf("    frame %3d  write %04X -> lands at %04X  data %02X%s\n",
				       frames_done, raw, scr, dut->wram_data_o,
				       raw == scr ? "" : "   <<< MOVED");
				wram_logged++;
			}
		}
		in_wram_wr = dut->wram_wr_o;

		// which branch does the coin debounce take?
		if (coinat >= 0) {
			uint16_t pc = dut->dbg_op_addr;
			if (pc != last_pc_seen) {
				if (pc == 0x00A4) printf("    frame %3d  debounce exited -> 00A4\n", frames_done);
				if (pc == 0x00A9) printf("    frame %3d  CREDIT  (CALL 010A)\n", frames_done);
				if (pc == 0x00DA) printf("    frame %3d  REJECTED (JR NC 00DA)\n", frames_done);
				last_pc_seen = pc;
			}
		}
		// where is the Z80 when it reads the coin, and does it act on it?
		if (coinat >= 0 && dut->io_rd_o && !in_io_rd && dut->io_port_o == 0xF8) {
			bool low = !(dut->io_dout_o & 0x80);
			if (low != f8_was_low) {
				printf("    frame %3d  $F8 bit7 %s at PC=%04X\n",
				       frames_done, low ? "LOW (coin)" : "high", dut->dbg_op_addr);
				f8_was_low = low;
			}
			if (low && f8pc.size() < 12) f8pc.insert(dut->dbg_op_addr);
		}
		if (coinat >= 0 && dut->io_rd_o && !in_io_rd &&
		    dut->io_port_o >= 0xF8 && frames_done >= coinat - 1 &&
		    frames_done <= coinat + 20 && io_logged < 400) {
			printf("    frame %3d  IN $%02X -> %02X\n",
			       frames_done, dut->io_port_o, dut->io_dout_o);
			io_logged++;
		}
		if (dut->io_rd_o && !in_io_rd && dut->io_port_o == 0xFC &&
		    (dut->io_dout_o & 1))
			fc_start_seen = true;
		in_io_rd = dut->io_rd_o;

		rom_pages.insert((uint16_t)(dut->rom_addr >> 8));
		if (trace_n && dut->rom_addr != last_addr) {
			if ((long)trace.size() < trace_n) trace.push_back(dut->rom_addr);
			last_addr = dut->rom_addr;
		}

		// vram_wr is a level held for the whole (wait-stated) write cycle, so
		// log one entry per cycle, not per clock
		if (wl && dut->vram_wr_o && !in_wr && wlcount < logn) {
			fprintf(wl, "%04X %02X %04X\n", (unsigned)dut->vram_addr_o,
			        (unsigned)dut->vram_din_o, (unsigned)dut->dbg_op_addr);
			wlcount++;
			if (wlcount == logn) { fclose(wl); wl = nullptr; }
		}
		in_wr = dut->vram_wr_o;

		if (dut->vram_wr_o) {
			vram_writes++;
			vram_touched.insert((uint16_t)dut->vram_addr_o);
			shadow[dut->vram_addr_o & 0xFFF] = dut->vram_din_o;
		}

		if (dut->vec_valid_o && !prev_valid) {
			samples++;
			if (dut->vec_beam_o) {
				beam_on++;
				colours.insert((uint8_t)dut->vec_colour_o);
			}
		}
		prev_valid = dut->vec_valid_o;

		// drawing starts
		if (dut->edgint_o && !prev_edg) {
			edgints++;
			if (snap_at == 0) memcpy(snapshot, shadow, sizeof snapshot);
		}
		prev_edg = dut->edgint_o;

		// drawing ends
		if (dut->frame_done_o && !prev_done) {
			frames_done++;
			if (snap_at == 1) memcpy(snapshot, shadow, sizeof snapshot);
		}
		prev_done = dut->frame_done_o;

		if (snap_at == 2) memcpy(snapshot, shadow, sizeof snapshot);
	}

	if (trace_n) {
		printf("first %zu ROM addresses fetched:\n ", trace.size());
		for (size_t i = 0; i < trace.size(); i++)
			printf(" %04X%s", trace[i], (i % 12 == 11) ? "\n " : "");
		printf("\n");
	}

	if (dumpvram) {
		FILE *o = fopen(dumpvram, "wb");
		if (o) {
			fwrite(snapshot, 1, sizeof snapshot, o);
			fclose(o);
			long nz = 0;
			for (int i = 0; i < 4096; i++) if (snapshot[i]) nz++;
			printf("wrote display list to %s (%ld non-zero bytes)\n", dumpvram, nz);
		}
	}

	printf("\n=== %s ===\n", rompath);
	printf("  clocks              %ld  (%d frames requested, %d completed)\n",
	       clocks, frames, frames_done);
	printf("  EDGINT pulses       %ld\n", edgints);
	printf("  ROM pages fetched   %zu of 192\n", rom_pages.size());
	printf("  vector RAM writes   %ld  (%zu distinct addresses)\n",
	       vram_writes, vram_touched.size());
	printf("  beam samples        %ld  (%ld with beam on)\n", samples, beam_on);
	printf("  PCs reading $F8 while coin low:");
	for (auto a : f8pc) printf(" %04X", a);
	printf("\n  $F8 read values seen: ");
	for (auto &kv : f8vals) printf("%02X x%ld  ", kv.first, kv.second);
	printf("\n");
	printf("  distinct colours    %zu\n", colours.size());
	if (usb)
		printf("  USB board           %ld program writes (%zu addresses), "
		       "audio peak %d over %ld non-zero samples\n",
		       usb_uploads, usb_touched.size(), usb_peak, usb_nonzero);

	int fails = 0;
	auto check = [&](bool ok, const char *what) {
		printf("  %-4s %s\n", ok ? "ok" : "FAIL", what);
		if (!ok) fails++;
	};

	check(rom_pages.size() > 16,    "CPU fetched from a spread of ROM pages (it is executing)");
	check(edgints >= frames,        "40 Hz EDGINT chain is running");
	check(vram_writes > 100,        "game wrote a display list into vector RAM");
	check(vram_touched.size() > 50, "display list spans many addresses");
	check(frames_done >= frames,    "vector generator completed the requested frames");
	check(beam_on > 1000,           "vector generator drew a substantial picture");
	check(colours.size() >= 2,      "more than one colour used");
	if (coinat >= 0 && !getenv("NOSTART")) {
		if (fc == 1)
			check(fc_start_seen, "spinner-game Start reached the CPU through $FC");
		check(credit_consumed, "Start consumed the inserted credit");
	}

	// For the two USB games this is what stops the board being dead weight:
	// the 8035 only makes noise if the Z80 uploaded its program through the
	// scrambled $D000 window, dropped /LOAD, and the timers and DACs ran.
	if (usb) {
		check(usb_touched.size() > 256, "Z80 uploaded an 8035 program through $D000");
		check(usb_nonzero > 1000,       "Universal Sound Board produced audio");
	}

	dut->final();
	delete dut;

	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
