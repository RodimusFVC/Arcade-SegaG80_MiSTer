#include "segag80v_golden.h"

#include <cmath>

// ---------------------------------------------------------------------------
// adjust_xy — verbatim from MAME segag80v_v.cpp
//
// Note it masks the raw counter to 11 bits: the 12th bit (0x800), which the
// symbol header replicates from bit 2 of the high byte, participates in the
// counter arithmetic but not in the screen transform.
// ---------------------------------------------------------------------------
static bool adjust_xy(int rawx, int rawy, int &outx, int &outy)
{
	bool clipped = false;

	outx = (rawx & 0x7ff) ^ 0x200;
	outy = (rawy & 0x7ff) ^ 0x200;

	if      ((outx & 0x600) == 0x200) { outx = 0x000; clipped = true; }
	else if ((outx & 0x600) == 0x400) { outx = 0x3ff; clipped = true; }
	else                                outx &= 0x3ff;

	if      ((outy & 0x600) == 0x200) { outy = 0x000; clipped = true; }
	else if ((outy & 0x600) == 0x400) { outy = 0x3ff; clipped = true; }
	else                                outy &= 0x3ff;

	return clipped;
}


void sega_xy_golden(const uint8_t *vram,
                    const uint8_t *sintab,
                    const XyConfig &cfg,
                    std::vector<VecSample> &out)
{
	out.clear();

	int      time_remaining = cfg.budget_clks;
	uint16_t symaddr        = 0;

	// symbol loop
	while (time_remaining > 0) {
		// phase 0: draw flag
		uint8_t draw = vram[symaddr++ & 0xfff];

		// phases 1-2: X, with bit 2 of the high nibble replicated into bit 11
		uint16_t curx = vram[symaddr++ & 0xfff];
		curx |= (vram[symaddr++ & 0xfff] & 7) << 8;
		curx |= (curx << 1) & 0x800;

		// phases 3-4: Y, same replication
		uint16_t cury = vram[symaddr++ & 0xfff];
		cury |= (vram[symaddr++ & 0xfff] & 7) << 8;
		cury |= (cury << 1) & 0x800;

		// phases 5-6: vector list address
		uint16_t vecaddr = vram[symaddr++ & 0xfff];
		vecaddr |= (vram[symaddr++ & 0xfff] & 0xf) << 8;

		// phases 7-8: symbol angle
		uint16_t symangle = vram[symaddr++ & 0xfff];
		symangle |= (vram[symaddr++ & 0xfff] & 3) << 8;

		// phase 9: scale
		uint8_t scale = vram[symaddr++ & 0xfff];

		time_remaining -= 10 * cfg.phase_clks;

		if (draw & 1) {
			// (1) move to the symbol origin, beam off
			int adjx, adjy;
			bool clipped = adjust_xy(curx, cury, adjx, adjy);
			out.push_back({ (uint16_t)adjx, (uint16_t)adjy, 0, false });

			// vector loop
			while (time_remaining > 0) {
				// phase 10: attribute
				uint8_t attrib = vram[vecaddr++ & 0xfff];

				// phase 11: length x scale via the 25LS14 at U8, 9 MSBs kept
				uint16_t length = (vram[vecaddr++ & 0xfff] * scale) >> 7;

				// phases 12-13: vector angle
				uint16_t vecangle = vram[vecaddr++ & 0xfff];
				vecangle |= (vram[vecaddr++ & 0xfff] & 3) << 8;

				// sin/cos PROM at U39; A0 grounded, so index is angle * 2.
				// The +0x100 on the Y lookup is what separates cos from sin.
				uint16_t deltax = sintab[((vecangle + symangle)         & 0x1ff) << 1];
				uint16_t deltay = sintab[((vecangle + symangle + 0x100) & 0x1ff) << 1];

				time_remaining -= 4 * cfg.phase_clks;

				uint8_t colour   = (attrib >> 1) & 0x3f;
				bool    beam_ena = (attrib & 1) && (colour != 0);

				bool xneg = ((vecangle + symangle)         & 0x200) != 0;
				bool yneg = ((vecangle + symangle + 0x100) & 0x200) != 0;

				clipped = adjust_xy(curx, cury, adjx, adjy);

				uint16_t xaccum = 0, yaccum = 0;
				uint16_t remaining = length;

				if (remaining == 0) {
					// (3) zero-length vector draws a dot at the current spot
					out.push_back({ (uint16_t)adjx, (uint16_t)adjy, colour,
					                beam_ena && !clipped });
				}

				// (2) one sample per DDA step
				while (remaining-- != 0 && time_remaining > 0) {
					// X accumulator: adders U44/U45. Bit 7 of the PROM value is
					// fed back as a carry-in to round small steps down and
					// large steps up.
					xaccum += deltax + (deltax >> 7);
					if (!xneg) curx += xaccum >> 8;
					else       curx -= xaccum >> 8;
					xaccum &= 0xff;

					// Y accumulator: adders U46/U47
					yaccum += deltay + (deltay >> 7);
					if (!yneg) cury += yaccum >> 8;
					else       cury -= yaccum >> 8;
					yaccum &= 0xff;

					clipped = adjust_xy(curx, cury, adjx, adjy);
					out.push_back({ (uint16_t)adjx, (uint16_t)adjy, colour,
					                beam_ena && !clipped });

					time_remaining -= 1;
				}

				// attribute bit 7 ends the symbol; U52 reloads the phase
				// generator to 0 instead of 10
				if (attrib & 0x80) break;
			}
		}

		// draw-flag bit 7 ends the whole display list for this frame
		if (draw & 0x80) break;
	}
}


void sega_xy_make_sintab(uint8_t *sintab)
{
	// The angle is 10 bits = one full turn. Bits [8:0] index the table and bit
	// 9 carries the sign, so the 512 entries span half a turn (0..pi) and hold
	// magnitude only: sin is non-negative across that range.
	//
	// 255 means "one count per clock": the accumulator adds deltax + deltax[7],
	// so 255 + 1 = 256 carries out on every clock.
	for (int i = 0; i < 1024; i++) sintab[i] = 0;
	for (int a = 0; a < 512; a++) {
		double theta = (M_PI * a) / 512.0;
		int    v     = (int)(std::sin(theta) * 255.0 + 0.5);
		if (v > 255) v = 255;
		if (v < 0)   v = 0;
		sintab[a << 1] = (uint8_t)v;
	}
}
