// segag80v_cpu integration test: runs hand-assembled Z80 code through the
// real tv80 core and checks the memory map, the security chip in situ, the
// I/O read path and the interrupt chain.
//
// The security chip is what makes this worth doing as an integration test
// rather than a unit test: it depends on the Z80's actual opcode-fetch timing,
// so it can only be verified with a CPU driving it.
//
// Prints the total clock count so `make cpu` can check that wait states are
// inserted uniformly per memory cycle.

#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "Vsegag80v_cpu.h"
#include "verilated.h"
#include "sega_security_ref.h"

static const int CHIP = 6;   // 315-0082 (Zektor): selects on pc[4] and pc[0]

// Input sources for the $F8..$FB matrix, chosen so every bit position differs.
static const uint8_t IN_D5D4 = 0x96;
static const uint8_t IN_D3D2 = 0x3C;
static const uint8_t IN_D1D0 = 0xE1;
static const uint8_t IN_D7D6 = 0x00;   // coin/service/DRAW are merged in by the RTL

static uint8_t rom[0x10000];

struct Write { uint16_t addr; uint8_t data; };

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);

	// ---- program -------------------------------------------------------
	memset(rom, 0xFF, sizeof rom);
	uint8_t prog[] = {
		/* 0000 */ 0xED, 0x56,              // IM 1
		/* 0002 */ 0x3E, 0xAA,              // LD A,$AA
		/* 0004 */ 0x32, 0x00, 0xE0,        // LD ($E000),A   <- scrambled, pc=0004
		/* 0007 */ 0x3E, 0x55,              // LD A,$55
		/* 0009 */ 0x32, 0x34, 0xE1,        // LD ($E134),A   <- scrambled, pc=0009
		/* 000C */ 0x3E, 0x5A,              // LD A,$5A
		/* 000E */ 0x32, 0x78, 0xE2,        // LD ($E278),A   <- scrambled, pc=000E
		/* 0011 */ 0x21, 0x34, 0xE3,        // LD HL,$E334
		/* 0014 */ 0x36, 0x99,              // LD (HL),$99    <- NOT scrambled
		/* 0016 */ 0xDB, 0xF8,              // IN A,($F8)
		/* 0018 */ 0x32, 0x00, 0xE4,        // LD ($E400),A   <- scrambled, pc=0018
		/* 001B */ 0x31, 0xF0, 0xCF,        // LD SP,$CFF0
		/* 001E */ 0xFB,                    // EI
		/* 001F */ 0x18, 0xFE               // JR $-2
	};
	memcpy(rom, prog, sizeof prog);

	uint8_t isr[] = {
		/* 0038 */ 0x3E, 0xC3,              // LD A,$C3
		/* 003A */ 0x32, 0x00, 0xE5,        // LD ($E500),A   <- scrambled, pc=003A
		/* 003D */ 0xFB,                    // EI
		/* 003E */ 0xED, 0x4D               // RETI
	};
	memcpy(rom + 0x38, isr, sizeof isr);

	// ---- expectations --------------------------------------------------
	auto vaddr = [](uint16_t cpu_addr, uint32_t pc, bool scrambled) -> uint16_t {
		uint8_t lo = scrambled ? sref_scramble(CHIP, pc, cpu_addr & 0xFF)
		                       : (cpu_addr & 0xFF);
		return (uint16_t)(((cpu_addr >> 8) & 0x0F) << 8 | lo);
	};

	// what IN A,($F8) should return: sel = 0.
	//
	// The CPU merges the live switch lines into the source bytes at the bit
	// positions the D7D6 / D5D4 port definitions use:
	//   D7D6: bit 0 = COIN1, bit 4 = COIN2, bit 5 = DRAW
	//   D5D4: bit 0 = SERVICE
	auto BIT = [](uint8_t v, int n) { return (v >> n) & 1; };
	const int draw = 1, coin_a = 1, coin_b = 1, service = 1;   // idle (active low)
	uint8_t d7d6_live = (uint8_t)((IN_D7D6 & 0xC0) | (draw << 5) | (coin_b << 4)
	                              | (IN_D7D6 & 0x0E) | coin_a);
	uint8_t d5d4_live = (uint8_t)((IN_D5D4 & 0xFE) | service);
	uint8_t expect_in =
		(uint8_t)((BIT(d7d6_live,0)<<7) | (BIT(d7d6_live,4)<<6) |
		          (BIT(d5d4_live,0)<<5) | (BIT(d5d4_live,4)<<4) |
		          (BIT(IN_D3D2,0)<<3)   | (BIT(IN_D3D2,4)<<2)   |
		          (BIT(IN_D1D0,0)<<1)   | (BIT(IN_D1D0,4)<<0));

	std::vector<Write> expected = {
		{ vaddr(0xE000, 0x0004, true ), 0xAA },
		{ vaddr(0xE134, 0x0009, true ), 0x55 },
		{ vaddr(0xE278, 0x000E, true ), 0x5A },
		{ vaddr(0xE334, 0x0000, false), 0x99 },
		{ vaddr(0xE400, 0x0018, true ), expect_in },
		{ vaddr(0xE500, 0x003A, true ), 0xC3 },   // from the ISR
	};

	// ---- run -----------------------------------------------------------
	auto *dut = new Vsegag80v_cpu;

	dut->clk = 0; dut->ce_cpu = 1; dut->reset = 1;
	dut->cfg_chip = CHIP; dut->cfg_usb = 0; dut->cfg_fc = 0;
	dut->in_d7d6 = IN_D7D6; dut->in_d5d4 = IN_D5D4;
	dut->in_d3d2 = IN_D3D2; dut->in_d1d0 = IN_D1D0;
	dut->in_fc = 0x00; dut->in_coins = 0x00;
	dut->spin_delta = 0; dut->spin_stb = 0;
	dut->draw_flag = 1; dut->edgint = 0;
	dut->coin_a = 1; dut->coin_b = 1; dut->service = 1;   // idle = high
	dut->vram_dout = 0; dut->usb_dout = 0; dut->usb_status = 0;
	dut->rom_data = 0;

	std::vector<Write> seen;
	long clocks = 0;
	bool prev_vram_wr = false;
	bool irq_fired = false;

	auto step = [&]() {
		dut->rom_data = rom[dut->rom_addr];
		dut->eval();
		dut->clk = 1; dut->eval();
		dut->clk = 0; dut->eval();
		clocks++;

		bool w = dut->vram_wr;
		if (w && !prev_vram_wr)
			seen.push_back({ (uint16_t)dut->vram_addr, (uint8_t)dut->vram_din });
		prev_vram_wr = w;
	};

	for (int i = 0; i < 8; i++) step();
	dut->reset = 0;

	// run the mainline, then raise EDGINT once the CPU is in its idle loop
	long trigger_at = 0;
	for (long c = 0; c < 200000; c++) {
		step();
		if (seen.size() >= 5 && !irq_fired && trigger_at == 0)
			trigger_at = clocks + 20;
		if (trigger_at && clocks == trigger_at) { dut->edgint = 1; irq_fired = true; }
		if (trigger_at && clocks == trigger_at + 4) dut->edgint = 0;
		if (seen.size() >= expected.size()) break;
	}

	// ---- check ---------------------------------------------------------
	int fails = 0;
	printf("segag80v_cpu: %zu vector-RAM writes observed in %ld clocks\n",
	       seen.size(), clocks);

	if (seen.size() != expected.size()) {
		printf("  expected %zu writes, saw %zu\n", expected.size(), seen.size());
		fails++;
	}
	size_t n = seen.size() < expected.size() ? seen.size() : expected.size();
	static const char *what[] = {
		"scrambled write $E000", "scrambled write $E134", "scrambled write $E278",
		"unscrambled LD (HL)",   "IN ($F8) then write",   "ISR write (interrupt)"
	};
	for (size_t i = 0; i < n; i++) {
		if (seen[i].addr != expected[i].addr || seen[i].data != expected[i].data) {
			printf("  FAIL %s: want addr %03X data %02X, got addr %03X data %02X\n",
			       what[i], expected[i].addr, expected[i].data,
			       seen[i].addr, seen[i].data);
			fails++;
		} else {
			printf("  ok   %s -> addr %03X data %02X\n",
			       what[i], seen[i].addr, seen[i].data);
		}
	}
	if (!irq_fired) { printf("  FAIL EDGINT was never raised\n"); fails++; }

	dut->final();
	delete dut;

	printf("CLOCKS=%ld\n", clocks);
	if (fails) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
