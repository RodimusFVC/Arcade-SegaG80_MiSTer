// Golden model of the GI SP0250 LPC synthesiser.
//
// Transcribed from MAME's sound/sp0250.cpp (Olivier Galibert, BSD-3-Clause).
// The arithmetic is unchanged, including the int16 wrap in the lattice filter,
// which the RTL has to reproduce bit for bit.
//
// The Sega speech board (drawing 800-0294) clocks it at 3.12 MHz. Output is one
// 7-bit DAC sample per next() call at clock / 2 / (4 * 39) = 10 kHz.

#pragma once

#include <cstdint>

class Sp0250Golden {
public:
	Sp0250Golden() { reset(); }

	void reset();

	// Host writes a byte into the 15-byte frame FIFO.
	void write(uint8_t data);

	// DRQ is high while the FIFO has room.
	bool drq() const { return fifo_pos_ != 15; }

	// One output sample, in [-64, 63].
	int8_t next();

public:
	uint8_t dbg_fifo_pos() const { return fifo_pos_; }
	uint8_t dbg_repeat() const { return repeat_; }
	uint8_t dbg_rcount() const { return rcount_; }
	uint8_t dbg_pcount() const { return pcount_; }
	int16_t dbg_amp() const { return amp_; }

private:
	struct Filter {
		int16_t F, B, z1, z2;
		void reset() { z1 = z2 = 0; }
		int16_t apply(int16_t in) {
			int16_t z0 = (int16_t)(in + ((z1 * F) >> 8) + ((z2 * B) >> 9));
			z2 = z1;
			z1 = z0;
			return z0;
		}
	};

	void load_values();

	Filter   filter_[6];
	bool     voiced_;
	int16_t  amp_;
	uint16_t lfsr_;
	uint8_t  pitch_, pcount_, repeat_, rcount_;
	uint8_t  fifo_[15];
	uint8_t  fifo_pos_;
};

// exposed for the RTL's coefficient ROM to be generated from the same table
uint16_t sp0250_amp(uint8_t v);
int16_t  sp0250_coef(uint8_t v);
