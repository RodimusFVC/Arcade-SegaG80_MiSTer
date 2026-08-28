// MAME reference for the Sega G-80 security chips, shared by the scrambler
// unit test and the CPU integration test.
//
// Verbatim logic from refs/mame/segag80_m.cpp (Aaron Giles / MB).

#pragma once

#include <cstdint>

static inline uint8_t sref_permA(uint32_t b) { return (uint8_t)b; }

static inline uint8_t sref_permB(uint32_t b) {
	uint32_t i = b & 0x03;
	i += ((b & 0x80) >> 1);
	i += ((b & 0x60) >> 3);
	i += ((~b) & 0x10);
	i += ((b & 0x08) << 2);
	i += ((b & 0x04) << 5);
	return (uint8_t)(i & 0xFF);
}

static inline uint8_t sref_permC(uint32_t b) {
	uint32_t i = b & 0x03;
	i += ((b & 0x80) >> 4);
	i += (((~b) & 0x40) >> 1);
	i += ((b & 0x20) >> 1);
	i += ((b & 0x10) >> 2);
	i += ((b & 0x08) << 3);
	i += ((b & 0x04) << 5);
	return (uint8_t)(i & 0xFF);
}

static inline uint8_t sref_permD(uint32_t b) {
	uint32_t i = b & 0x23;
	i += ((b & 0xC0) >> 4);
	i += ((b & 0x10) << 2);
	i += ((b & 0x08) << 1);
	i += (((~b) & 0x04) << 5);
	return (uint8_t)(i & 0xFF);
}

static inline uint8_t sref62(uint32_t pc, uint8_t lo) {
	switch (pc & 0x03) {
		case 0x00: return sref_permD(lo);
		case 0x01: return sref_permC(lo);
		case 0x02: return sref_permB(lo);
		default:   return sref_permA(lo);
	}
}
static inline uint8_t sref63(uint32_t pc, uint8_t lo) {
	switch (pc & 0x09) {
		case 0x00: return sref_permD(lo);
		case 0x01: return sref_permC(lo);
		case 0x08: return sref_permB(lo);
		default:   return sref_permA(lo);
	}
}
static inline uint8_t sref64(uint32_t pc, uint8_t lo) {
	switch (pc & 0x03) {
		case 0x00: return sref_permA(lo);
		case 0x01: return sref_permB(lo);
		case 0x02: return sref_permC(lo);
		default:   return sref_permD(lo);
	}
}
static inline uint8_t sref70(uint32_t pc, uint8_t lo) {
	switch (pc & 0x09) {
		case 0x00: return sref_permB(lo);
		case 0x01: return sref_permA(lo);
		case 0x08: return sref_permD(lo);
		default:   return sref_permC(lo);
	}
}
static inline uint8_t sref76(uint32_t pc, uint8_t lo) {
	switch (pc & 0x09) {
		case 0x00: return sref_permA(lo);
		case 0x01: return sref_permB(lo);
		case 0x08: return sref_permC(lo);
		default:   return sref_permD(lo);
	}
}
static inline uint8_t sref82(uint32_t pc, uint8_t lo) {
	switch (pc & 0x11) {
		case 0x00: return sref_permA(lo);
		case 0x01: return sref_permB(lo);
		case 0x10: return sref_permC(lo);
		default:   return sref_permD(lo);
	}
}

// chip ids match sega_security_pkg in rtl/sega_security.sv
static inline uint8_t sref_scramble(int chip, uint32_t pc, uint8_t lo) {
	switch (chip) {
		case 1: return sref62(pc, lo);
		case 2: return sref63(pc, lo);
		case 3: return sref64(pc, lo);
		case 4: return sref70(pc, lo);
		case 5: return sref76(pc, lo);
		case 6: return sref82(pc, lo);
		default: return lo;
	}
}
