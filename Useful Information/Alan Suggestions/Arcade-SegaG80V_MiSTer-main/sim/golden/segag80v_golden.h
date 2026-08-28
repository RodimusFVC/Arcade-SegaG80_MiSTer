// Golden model of the Sega G-80 X-Y vector generator.
//
// Transcribed from MAME's segag80v_state::sega_generate_vector_list()
// (refs/mame/segag80v_v.cpp, Aaron Giles, BSD-3-Clause). The arithmetic is
// unchanged; the only deliberate difference is the *granularity of the output*:
//
//   MAME emits a compressed endpoint list (add_point on clip transitions),
//   because its renderer draws lines. The MiSTer renderer plots points and the
//   Sega DDA moves the beam by at most one count per clock, so this model emits
//   one sample per DDA step instead. The sample stream is therefore the exact
//   beam path, which is what the RTL produces and what videodr0me_fb consumes.
//
// Emission contract (RTL must match exactly):
//   1. per drawn symbol: one sample at the symbol origin, beam OFF (a "move")
//   2. per vector: `length` samples, one after each DDA step
//   3. per vector with length == 0: one sample at the current position (a dot)
//   beam = beam_ena && !clipped, where beam_ena = attrib[0] && colour6 != 0

#pragma once

#include <cstdint>
#include <vector>

struct VecSample {
	uint16_t x;       // 0..1023, after the XOR/clip transform
	uint16_t y;       // 0..1023
	uint8_t  colour;  // 6-bit RRGGBB, = (attrib >> 1) & 0x3F
	bool     beam;    // beam on at this position
};

struct XyConfig {
	// VCL clocks charged per 16-phase-generator slot. MAME charges
	// 1/U51_CLOCK == 16 VCL periods per phase; reading U51/U50 on
	// XY_Timing_800-0161 sheet 7/7 suggests it may be 1. Unresolved — see
	// docs/01-hardware-reference.md §2.
	int phase_clks = 16;

	// VCL clocks in one 40 Hz frame: 2578080 / 40.
	int budget_clks = 64452;
};

// Walk the display list in `vram` (4 KB) using the sine table in `sintab`
// (1 KB; A0 is grounded on the board so only even entries are read).
void sega_xy_golden(const uint8_t *vram,
                    const uint8_t *sintab,
                    const XyConfig &cfg,
                    std::vector<VecSample> &out);

// Build the sine/cosine PROM the way the real s-c.xyt-u39 is programmed, for
// tests that do not have the real dump. Entry n (even byte 2n) holds the
// magnitude of the step for angle n over 512 angles per turn.
void sega_xy_make_sintab(uint8_t *sintab /* 1024 bytes */);
