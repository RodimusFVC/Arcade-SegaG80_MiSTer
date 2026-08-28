// Golden model of the Universal Sound Board analog chain.
//
// A direct transcription of refs/mame/segausb.cpp
// (usb_sound_device::sound_stream_update), in the same double precision MAME
// uses. The RTL is fixed point with power-of-two coefficients, so this is NOT a
// bit-exact reference — the bench compares against it in RMS/correlation terms.

#pragma once
#include <cmath>

class UsbFilterGolden {
public:
	struct FilterState {
		double capval = 0.0, exponent = 0.0;
		void configure(double r, double c) {
			capval = 0.0;
			exponent = 1.0 - std::exp(-1.0 / (r * c * 2e6));
		}
		double step_rc(double in) { return capval += (in - capval) * exponent; }
		double step_cr(double in) {
			double const result = in - capval;
			capval += result * exponent;
			return result;
		}
	};

	UsbFilterGolden() { reset(); }

	void reset() {
		for (int g = 0; g < 3; g++) {
			grp_[g].chan_filter[0].configure(10e3, 1e-6);
			grp_[g].chan_filter[1].configure(10e3, 1e-6);
			grp_[g].gate1.configure(100e3, 0.01e-6);
			grp_[g].gate2.configure(2 * 100e3, 0.01e-6);
		}
		FilterState t;
		t.configure(100e3, 0.01e-6);     gate_rc1_exp[0] = t.exponent;
		t.configure(1e3, 0.01e-6);       gate_rc1_exp[1] = t.exponent;
		t.configure(2 * 100e3, 0.01e-6); gate_rc2_exp[0] = t.exponent;
		t.configure(2 * 1e3, 0.01e-6);   gate_rc2_exp[1] = t.exponent;

		noise_[0].configure(2.7e3 + 2.7e3, 1.0e-6);
		noise_[1].configure(2.7e3 + 1e3,   0.30e-6);
		noise_[2].configure(2.7e3 + 270,   0.15e-6);
		noise_[4].configure(33e3, 0.1e-6);
		final_.configure(100e3, 4.7e-6);
	}

	// One 2 MHz sample. tmr[g][c] are the 8253 channel outputs, env[g][c] the
	// envelope DAC values, cfg[g] the per-group envelope mode.
	double step(int noise_state, const int tmr[3][3], const int env[3][3], const int cfg[3]) {
		noise_[0].capval = 0.99765 * noise_[0].capval + noise_state * 0.0990460;
		noise_[1].capval = 0.96300 * noise_[1].capval + noise_state * 0.2965164;
		noise_[2].capval = 0.57000 * noise_[2].capval + noise_state * 1.0526913;
		double noiseval = noise_[0].capval + noise_[1].capval + noise_[2].capval
		                + noise_state * 0.1848;
		noiseval = noise_[4].step_cr(noiseval);
		noiseval *= 0.075;

		double sample = 0;
		for (int g = 0; g < 3; g++) {
			Group &grp = grp_[g];
			double chan0 = grp.chan_filter[0].step_cr(tmr[g][0]) * env[g][0] * (1.0 / 100.0);
			double chan1 = grp.chan_filter[1].step_cr(tmr[g][1]) * env[g][1] * (1.0 / 100.0);

			grp.gate1.exponent = gate_rc1_exp[tmr[g][2]];
			grp.gate2.exponent = gate_rc2_exp[tmr[g][2]];

			double chan2, mix;
			if (cfg[g] == 0) {
				chan2 = grp.gate2.step_rc(grp.gate1.step_rc(noiseval))
				        * -1.56 * env[g][2] * (1.0 / 33.0);
				mix = chan0 + chan1 + chan2;
			} else {
				chan2 = -noiseval * env[g][2] * (1.0 / 33.0);
				mix = chan0 + chan1 + chan2;
				mix = grp.gate2.step_rc(grp.gate1.step_rc(-mix)) * 1.56;
			}
			sample += mix;
		}
		return 0.1 * final_.step_cr(sample);
	}

private:
	struct Group {
		FilterState chan_filter[2], gate1, gate2;
	};
	Group       grp_[3];
	FilterState noise_[5], final_;
	double      gate_rc1_exp[2] = {0, 0}, gate_rc2_exp[2] = {0, 0};
};
