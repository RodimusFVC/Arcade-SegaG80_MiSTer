// Exhaustive check of sega_security_scramble against MAME's reference
// implementation (refs/mame/segag80_m.cpp).
//
// Only pc[0] and pc[1]/pc[3]/pc[4] can affect the result, so sweeping the low
// 8 bits of the PC over all 256 values is exhaustive, not a sample.

#include <cstdio>
#include <cstdint>
#include "Vsega_security_scramble.h"
#include "verilated.h"

// ---- MAME reference (verbatim logic from segag80_m.cpp) --------------------

static uint8_t permA(uint32_t b) { return (uint8_t)b; }

static uint8_t permB(uint32_t b) {
	uint32_t i = b & 0x03;
	i += ((b & 0x80) >> 1);
	i += ((b & 0x60) >> 3);
	i += ((~b) & 0x10);
	i += ((b & 0x08) << 2);
	i += ((b & 0x04) << 5);
	return (uint8_t)(i & 0xFF);
}

static uint8_t permC(uint32_t b) {
	uint32_t i = b & 0x03;
	i += ((b & 0x80) >> 4);
	i += (((~b) & 0x40) >> 1);
	i += ((b & 0x20) >> 1);
	i += ((b & 0x10) >> 2);
	i += ((b & 0x08) << 3);
	i += ((b & 0x04) << 5);
	return (uint8_t)(i & 0xFF);
}

static uint8_t permD(uint32_t b) {
	uint32_t i = b & 0x23;
	i += ((b & 0xC0) >> 4);
	i += ((b & 0x10) << 2);
	i += ((b & 0x08) << 1);
	i += (((~b) & 0x04) << 5);
	return (uint8_t)(i & 0xFF);
}

static uint8_t ref62(uint32_t pc, uint8_t lo) {
	switch (pc & 0x03) {
		case 0x00: return permD(lo);
		case 0x01: return permC(lo);
		case 0x02: return permB(lo);
		default:   return permA(lo);
	}
}
static uint8_t ref63(uint32_t pc, uint8_t lo) {
	switch (pc & 0x09) {
		case 0x00: return permD(lo);
		case 0x01: return permC(lo);
		case 0x08: return permB(lo);
		default:   return permA(lo);
	}
}
static uint8_t ref64(uint32_t pc, uint8_t lo) {
	switch (pc & 0x03) {
		case 0x00: return permA(lo);
		case 0x01: return permB(lo);
		case 0x02: return permC(lo);
		default:   return permD(lo);
	}
}
static uint8_t ref70(uint32_t pc, uint8_t lo) {
	switch (pc & 0x09) {
		case 0x00: return permB(lo);
		case 0x01: return permA(lo);
		case 0x08: return permD(lo);
		default:   return permC(lo);
	}
}
static uint8_t ref76(uint32_t pc, uint8_t lo) {
	switch (pc & 0x09) {
		case 0x00: return permA(lo);
		case 0x01: return permB(lo);
		case 0x08: return permC(lo);
		default:   return permD(lo);
	}
}
static uint8_t ref82(uint32_t pc, uint8_t lo) {
	switch (pc & 0x11) {
		case 0x00: return permA(lo);
		case 0x01: return permB(lo);
		case 0x10: return permC(lo);
		default:   return permD(lo);
	}
}

struct ChipDef { const char *name; int id; uint8_t (*fn)(uint32_t, uint8_t); };

static const ChipDef CHIPS[] = {
	{ "none",     0, nullptr },
	{ "315-0062", 1, ref62 },
	{ "315-0063", 2, ref63 },
	{ "315-0064", 3, ref64 },
	{ "315-0070", 4, ref70 },
	{ "315-0076", 5, ref76 },
	{ "315-0082", 6, ref82 },
};

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	auto *dut = new Vsega_security_scramble;

	long checked = 0, failed = 0;

	for (const auto &chip : CHIPS) {
		for (uint32_t pc = 0; pc < 256; pc++) {
			for (uint32_t lo = 0; lo < 256; lo++) {
				dut->chip    = chip.id;
				dut->op_pc   = pc;
				dut->addr_lo = lo;
				dut->eval();

				uint8_t want = chip.fn ? chip.fn(pc, (uint8_t)lo) : (uint8_t)lo;
				uint8_t got  = dut->addr_lo_scrambled;

				checked++;
				if (want != got) {
					if (failed < 10)
						printf("FAIL %s pc=%02X lo=%02X: want %02X got %02X\n",
						       chip.name, pc, lo, want, got);
					failed++;
				}
			}
		}
	}

	dut->final();
	delete dut;

	printf("sega_security_scramble: %ld checked, %ld failed\n", checked, failed);
	if (failed) { printf("RESULT: FAIL\n"); return 1; }
	printf("RESULT: PASS\n");
	return 0;
}
