#include "sp0250_golden.h"

// Internal ROM to the chip, cf. the SP0250 manual. Verbatim from MAME.
static const uint16_t COEFS[128] = {
	  0,   9,  17,  25,  33,  41,  49,  57,  65,  73,  81,  89,  97, 105, 113, 121,
	129, 137, 145, 153, 161, 169, 177, 185, 193, 201, 203, 217, 225, 233, 241, 249,
	257, 265, 273, 281, 289, 297, 301, 305, 309, 313, 317, 321, 325, 329, 333, 337,
	341, 345, 349, 353, 357, 361, 365, 369, 373, 377, 381, 385, 389, 393, 397, 401,
	405, 409, 413, 417, 421, 425, 427, 429, 431, 433, 435, 437, 439, 441, 443, 445,
	447, 449, 451, 453, 455, 457, 459, 461, 463, 465, 467, 469, 471, 473, 475, 477,
	479, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495,
	496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511
};

uint16_t sp0250_amp(uint8_t v) {
	return (uint16_t)((v & 0x1f) << (v >> 5));
}

int16_t sp0250_coef(uint8_t v) {
	int16_t res = (int16_t)COEFS[v & 0x7f];
	if (!(v & 0x80)) res = (int16_t)-res;
	return res;
}

void Sp0250Golden::reset() {
	for (auto &f : filter_) { f.F = 0; f.B = 0; f.z1 = 0; f.z2 = 0; }
	voiced_ = false;
	amp_ = 0;
	lfsr_ = 0x7fff;
	pitch_ = pcount_ = repeat_ = rcount_ = 0;
	for (auto &b : fifo_) b = 0;
	fifo_pos_ = 0;
	load_values();
}

void Sp0250Golden::load_values() {
	filter_[0].B = sp0250_coef(fifo_[ 0]);
	filter_[0].F = sp0250_coef(fifo_[ 1]);
	amp_         = (int16_t)sp0250_amp(fifo_[ 2]);
	filter_[1].B = sp0250_coef(fifo_[ 3]);
	filter_[1].F = sp0250_coef(fifo_[ 4]);
	pitch_       =           fifo_[ 5];
	filter_[2].B = sp0250_coef(fifo_[ 6]);
	filter_[2].F = sp0250_coef(fifo_[ 7]);
	repeat_      =           fifo_[ 8] & 0x3f;
	voiced_      =          (fifo_[ 8] & 0x40) != 0;
	filter_[3].B = sp0250_coef(fifo_[ 9]);
	filter_[3].F = sp0250_coef(fifo_[10]);
	filter_[4].B = sp0250_coef(fifo_[11]);
	filter_[4].F = sp0250_coef(fifo_[12]);
	filter_[5].B = sp0250_coef(fifo_[13]);
	filter_[5].F = sp0250_coef(fifo_[14]);
	fifo_pos_ = 0;
	pcount_ = 0;
	rcount_ = 0;
	for (auto &f : filter_) f.reset();
}

void Sp0250Golden::write(uint8_t data) {
	if (fifo_pos_ != 15)
		fifo_[fifo_pos_++] = data;
	// overflow is silently dropped, as in MAME
}

int8_t Sp0250Golden::next() {
	if (rcount_ >= repeat_) {
		if (fifo_pos_ == 15) {
			load_values();
		} else {
			// The chip executes "NOPs" with a repeat count of 1 and unchanged
			// pitch while waiting for input.
			repeat_ = 1;
			pcount_ = 0;
			rcount_ = 0;
		}
	}

	// 15-bit LFSR, clocked every cycle regardless of voiced/unvoiced
	lfsr_ ^= (uint16_t)((lfsr_ ^ (lfsr_ >> 1)) << 15);
	lfsr_ >>= 1;

	int16_t z0;
	if (voiced_) z0 = (pcount_ == 0) ? amp_ : 0;
	else         z0 = (lfsr_ & 1) ? amp_ : (int16_t)-amp_;

	for (auto &f : filter_) z0 = f.apply(z0);

	// 13-bit amp reduced to 7 bits; filter effects may occasionally clip
	int dac = z0 >> 6;
	if (dac < -64) dac = -64;
	if (dac >  63) dac =  63;

	if (pcount_++ == pitch_) {
		pcount_ = 0;
		rcount_++;
	}
	return (int8_t)dac;
}
