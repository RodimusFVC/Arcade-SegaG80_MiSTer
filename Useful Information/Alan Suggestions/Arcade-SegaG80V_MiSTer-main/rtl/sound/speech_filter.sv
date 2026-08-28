//============================================================================
//  Sega speech board output filter
//
//  The SP0250's DAC is a 10 kHz sample-and-hold and is very bright on its own.
//  The board runs it through a passive network and a TL081 before the CD4053,
//  which is what gives the speech its cabinet tone.
//
//  Transcribed from refs/mame/nl_segaspeech.cpp. Note that MAME does *not*
//  normally apply this: segaspeech.cpp has ENABLE_NETLIST_FILTERING (0), so its
//  default path routes the SP0250 straight out. Comparing the unfiltered core
//  against a real cabinet recording showed far too much energy above 700 Hz,
//  which is what this fixes.
//
//  Topology, with MAME's schematic corrections already applied:
//
//    SP0250 --| |--/\/\/--+--------+-------> U8.3   (TL081, non-inverting)
//              C9   R18   |        |
//            0.1u   22k  R19      C10             gain = 1 + R21/R20
//                       250k    0.047u                 = 1 + 10k/4.7k
//                         |        |                   = 3.128
//                        GND      GND
//
//  That is two cascaded one-poles plus a gain:
//
//    C9  with R18+R19        DC block   tau 29.2 ms    5.45 Hz
//    C10 with R18||R19       low pass   tau 956 us     166.5 Hz
//    R19/(R18+R19) x (1 + R21/R20)      gain 0.9247 x 3.1277 = 2.8920
//
//  R19 IS 270K, NOT MAME'S 250k. Sega drawing 800-0294 rev H sheet 5 clearly
//  shows 270K, 250k is not an E24 value, and MAME does not document the
//  change — so this looks like a transcription slip on their side. The effect
//  is small (the pole moves 167.5 -> 166.5 Hz) but there is no reason to carry
//  it. R20 on the other hand really is 4.7k: MAME notes "schematic shows
//  470Ohm", but that is the *other*, simpler drawing in the Astro Blaster and
//  Space Fury manuals; 800-0294 already shows 4.7K, which confirms the gain.
//
//  C50 (0.003u) across R21 puts a shelf between 5.3 kHz and 16.6 kHz. It is
//  left out: the 167 Hz pole has already taken more than 30 dB off by then, so
//  it cannot matter, and leaving it out keeps this to two poles.
//
//  Every coefficient is a sum of at most four signed powers of two, so this
//  needs no multipliers. Run at the 3.12 MHz board clock, so it filters the
//  held DAC waveform the way the real network does, steps and all:
//
//    C9  DC block   e=1.09764e-05   >>16 - >>18 - >>21          0.08%
//    C10 low pass   e=3.35175e-04   >>11 - >>13 - >>15          0.15%
//    gain 2.8920                    <<2 - <<0 - >>3 + >>6       0.05%
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module speech_filter #(
	// 1 = the board's 0.047u C10 (167 Hz). The part is small enough that a
	// misread here would be easy, so the corner is left adjustable: set
	// C10_TENTH to use 0.0047u (1675 Hz) instead and rebuild.
	parameter bit C10_TENTH = 1'b0
) (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,              // 3.12 MHz speech board clock

	input  wire signed [7:0] dac,       // SP0250 output, held between samples
	output wire signed [15:0] audio
);
	localparam int W = 32;

	// The DAC is +/-63, carried 16 bits up so the smallest filter step
	// (a delta shifted right 23) is still meaningful.
	wire signed [W-1:0] x = {{8{dac[7]}}, dac, 16'd0};

	logic signed [W-1:0] cap_hp, cap_lp;

	// C9: step_cr — the returned value is the difference, the cap tracks DC
	wire signed [W-1:0] hp = x - cap_hp;
	wire signed [W-1:0] e_hp = (hp >>> 16) - (hp >>> 18) - (hp >>> 21);

	// C10: step_rc
	wire signed [W-1:0] d_lp = hp - cap_lp;
	wire signed [W-1:0] e_lp = (d_lp >>> 11) - (d_lp >>> 13) - (d_lp >>> 15);
	// C10/10 variant, 1675 Hz: e = 3.3665e-03
	wire signed [W-1:0] e_lp_f = (d_lp >>> 8) - (d_lp >>> 11) - (d_lp >>> 14);

	always_ff @(posedge clk) begin
		if (reset) begin
			cap_hp <= '0;
			cap_lp <= '0;
		end else if (ce) begin
			cap_hp <= cap_hp + e_hp;
			cap_lp <= cap_lp + (C10_TENTH ? e_lp_f : e_lp);
		end
	end

	// 0.9247 divider x 3.1277 op-amp = 2.8920, as 4 - 1 - 1/8 + 1/64
	wire signed [W-1:0] y = (cap_lp <<< 2) - cap_lp - (cap_lp >>> 3)
	                      + (cap_lp >>> 6);

	// back to the same scale the unfiltered path used ({dac, 8'd0})
	wire signed [W-1:0] o = y >>> 8;
	assign audio = (o >  32767) ?  16'sh7FFF :
	               (o < -32768) ? -16'sh8000 : o[15:0];

endmodule

`default_nettype wire
