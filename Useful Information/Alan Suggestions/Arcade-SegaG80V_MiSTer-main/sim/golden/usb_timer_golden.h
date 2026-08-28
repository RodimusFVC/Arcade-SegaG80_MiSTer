// Golden model of the 8253 as the Sega Universal Sound Board uses it.
//
// Transcribed from refs/mame/segausb.cpp (timer8253). Only clock modes 1 and 3
// are implemented, matching MAME — the board's program uses no others.

#pragma once
#include <cstdint>

class UsbTimerGolden {
public:
	void reset() {
		for (int i = 0; i < 3; i++) ch_[i] = Channel();
	}

	void write(uint8_t offset, uint8_t data) {
		if (offset == 3) {
			if (((data & 0xc0) >> 6) < 3) {
				Channel &c = ch_[(data & 0xc0) >> 6];
				c.holding     = 1;
				c.latchmode   = (data >> 4) & 3;
				c.clockmode   = (data >> 1) & 7;
				c.bcdmode     = data & 1;
				c.latchtoggle = 0;
				c.output      = (c.clockmode == 1);
			}
			return;
		}
		Channel &c = ch_[offset];
		bool was_holding = c.holding;
		switch (c.latchmode) {
			case 1: c.count = data;      c.holding = 0; break;
			case 2: c.count = data << 8; c.holding = 0; break;
			case 3:
				if (c.latchtoggle == 0) {
					c.count = (uint16_t)((c.count & 0xff00) | data);
					c.latchtoggle = 1;
				} else {
					c.count = (uint16_t)((c.count & 0x00ff) | (data << 8));
					c.holding = 0;
					c.latchtoggle = 0;
				}
				break;
		}
		if (was_holding && !c.holding) c.remain = 1;
	}

	void set_gate(int i, int g) { ch_[i].gate = (uint8_t)g; }

	void clock(int i) {
		Channel &c = ch_[i];
		uint8_t old_lastgate = c.lastgate;
		c.lastgate = c.gate;
		if (c.holding) return;
		switch (c.clockmode) {
			case 1:
				if (!old_lastgate && c.gate) { c.output = 0; c.remain = c.count; }
				else { if (--c.remain == 0) c.output = 1; }
				break;
			case 3:
				c.remain = (uint16_t)((c.remain - 1) & ~1);
				if (c.remain == 0) { c.output ^= 1; c.remain = c.count; }
				break;
		}
	}

	int out(int i) const { return ch_[i].output; }

private:
	struct Channel {
		uint8_t  holding = 0, latchmode = 0, latchtoggle = 0;
		uint8_t  clockmode = 0, bcdmode = 0, output = 0;
		uint8_t  lastgate = 0, gate = 0;
		uint16_t count = 0, remain = 0;
	};
	Channel ch_[3];
};
