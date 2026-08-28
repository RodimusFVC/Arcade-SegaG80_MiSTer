//============================================================================
//  Sega G-80 discrete sound boards (Eliminator, Zektor, Space Fury)
//
//  The main Z80 drives these boards through two latches at $3E (LO) and $3F
//  (HI); each bit gates one sound. The bit-to-sound map below is transcribed
//  exactly from the ALIAS lines in refs/mame/nl_elim.cpp and nl_spacfury.cpp,
//  and from the lo/hi masks in refs/mame/segag80.cpp, so *that* part is
//  faithful and checkable.
//
//  FIDELITY WARNING, and it is a bigger one than anywhere else in this core.
//  MAME models these boards only as netlists — 30 KB each of 555 timers,
//  CA3080 transconductance amps and CD4011 one-shots, simulated as a circuit.
//  There is no simplified model to port and nothing to diff against, unlike
//  the 8253, the MM5837, the SP0250 and the vector generator. What follows is
//  a *behavioural* reconstruction: each latch bit drives an envelope and a
//  source chosen to be the right kind of sound. Where a value could be read
//  straight off the netlist it was, and it says so; the rest are estimates and
//  will need an ear.
//
//  Grounded values so far:
//    Eliminator/Zektor U13 is a 555 astable, R59 2k + R61 47k + C30 0.022uF,
//    f = 1.44 / ((2k + 2*47k) * 0.022u) = 682 Hz. That sets the reference for
//    the mid-range voices on that board.
//
//    The final mixer weights are read straight off Sega drawing 800-3174 rev B
//    sheet 8 (Eliminator manual) — see the sum below. That drawing also shows
//    the board's noise source is an MM5837 (U4), which is why the LFSR in
//    discrete_blocks.sv uses that polynomial, and it labels HI D6/D7 as
//    HEXAGONS rather than MAME's BACKGROUND.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_discrete #(
	parameter int CLK_HZ = 12_096_000,
	parameter int CE_HZ  = 48_000
) (
	input  wire        clk,
	input  wire        reset,

	input  wire  [2:0] game,        // sega_game_pkg
	input  wire        wr,          // one cycle, $3E/$3F write
	input  wire        sel,         // 0 = $3E (LO), 1 = $3F (HI)
	input  wire  [7:0] din,

	output wire signed [15:0] audio
);
	import sega_game_pkg::*;

	// ------------------------------------------------------------------
	// 48 kHz tick
	// ------------------------------------------------------------------
	logic [23:0] acc;
	logic        ce;
	always_ff @(posedge clk) begin
		if (reset) begin acc <= '0; ce <= 1'b0; end
		else if (acc + CE_HZ >= CLK_HZ) begin
			acc <= acc + CE_HZ - CLK_HZ; ce <= 1'b1;
		end else begin
			acc <= acc + CE_HZ;          ce <= 1'b0;
		end
	end

	// phase increment for a given frequency, at CE_HZ
	`define INC(hz) 24'((64'd16777216 * 64'(hz)) / 64'(CE_HZ))

	// ------------------------------------------------------------------
	// The two latches. Bits are active high into the netlist inputs.
	// ------------------------------------------------------------------
	logic [7:0] lo, hi;
	always_ff @(posedge clk) begin
		if (reset) begin lo <= 8'd0; hi <= 8'd0; end
		else if (wr) begin
			if (sel) hi <= din;
			else     lo <= din;
		end
	end

	// The latch bits are ACTIVE LOW: the games park both ports at $FF when
	// nothing should be sounding, and each bit is pulled low to trigger. MAME
	// passes the raw bit into the netlist and lets the CD4011 stages invert it;
	// here the inversion has to be explicit, and getting it backwards turns
	// every voice on at once.
	wire [7:0] lo_g = ~lo;
	wire [7:0] hi_g = ~hi;

	wire is_sf    = (game == GAME_SPACFURY);
	wire is_elim  = (game == GAME_ELIM2) || (game == GAME_ELIM4);
	wire is_zek   = (game == GAME_ZEKTOR);
	wire enabled  = is_sf | is_elim | is_zek;

	wire noise;
	dsc_noise ns (.clk(clk), .reset(reset), .ce(ce), .out(noise));

	// ==================================================================
	// Eliminator / Zektor  (nl_elim.cpp, shared netlist)
	//
	//   LO: D1 FIREBALL     D2 EXPLOSION_1  D3 EXPLOSION_2  D4 EXPLOSION_3
	//       D5 BOUNCE       D6 TORPEDO_1    D7 TORPEDO_2
	//   HI: D0 THRUST_LOW   D1 THRUST_HI    D2 THRUST_LSB   D3 THRUST_MSB
	//       D4 SKITTER      D5 ENEMY_SHIP   D6 BACKGROUND_LSB
	//       D7 BACKGROUND_MSB
	// ==================================================================
	wire signed [15:0] e_fire, e_ex1, e_ex2, e_ex3, e_bounce, e_tor1, e_tor2;
	wire signed [15:0] e_thrust, e_skitter, e_enemy, e_bg;

	// Fireball: filtered noise with a slow tail
	dsc_voice #(.ATK(4), .DCY(12), .USE_NOISE(1), .LPF_SH(5)) v_fire (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[1] : 1'b0),
		.noise(noise), .inc(24'd0), .out(e_fire));

	// Three explosion sizes: noise, longer decay for the bigger ones
	dsc_voice #(.ATK(2), .DCY(11), .USE_NOISE(1), .LPF_SH(4)) v_ex1 (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[2] : 1'b0),
		.noise(noise), .inc(24'd0), .out(e_ex1));
	dsc_voice #(.ATK(2), .DCY(12), .USE_NOISE(1), .LPF_SH(5)) v_ex2 (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[3] : 1'b0),
		.noise(noise), .inc(24'd0), .out(e_ex2));
	dsc_voice #(.ATK(2), .DCY(13), .USE_NOISE(1), .LPF_SH(6)) v_ex3 (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[4] : 1'b0),
		.noise(noise), .inc(24'd0), .out(e_ex3));

	// Bounce: short mid tone
	dsc_voice #(.ATK(2), .DCY(9), .USE_NOISE(0), .LPF_SH(3)) v_bounce (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[5] : 1'b0),
		.noise(noise), .inc(`INC(420)), .out(e_bounce));

	// Two torpedoes, around the 682 Hz the U13 astable actually runs at
	dsc_voice #(.ATK(1), .DCY(10), .USE_NOISE(0), .LPF_SH(2)) v_tor1 (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[6] : 1'b0),
		.noise(noise), .inc(`INC(682)), .out(e_tor1));
	dsc_voice #(.ATK(1), .DCY(10), .USE_NOISE(0), .LPF_SH(2)) v_tor2 (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? lo_g[7] : 1'b0),
		.noise(noise), .inc(`INC(910)), .out(e_tor2));

	// Thrust: continuous filtered noise, four levels from HI D0-D3
	wire [1:0] thrust_lvl = {hi_g[3], hi_g[2]};
	wire       thrust_on  = (is_elim|is_zek) & (hi_g[0] | hi_g[1]);
	wire [15:0] thr_env;
	dsc_env #(.ATK(7), .DCY(8)) e_thr (
		.clk(clk), .reset(reset), .ce(ce), .gate(thrust_on), .level(thr_env));
	wire signed [15:0] thr_raw = noise ? $signed({1'b0, thr_env[15:1]})
	                                   : -$signed({1'b0, thr_env[15:1]});
	wire signed [15:0] thr_f;
	dsc_lpf #(.SH(6)) f_thr (.clk(clk), .reset(reset), .ce(ce),
	                         .in(thr_raw), .out(thr_f));
	// D1 picks the brighter of the two thrust bands; D2/D3 set its level
	wire signed [15:0] thr_band = hi_g[1] ? thr_raw : thr_f;
	assign e_thrust = (thrust_lvl == 2'd0) ? (thr_band >>> 2) :
	                  (thrust_lvl == 2'd1) ? (thr_band >>> 1) :
	                  (thrust_lvl == 2'd2) ? thr_band - (thr_band >>> 2) : thr_band;

	// Skitter and enemy ship: continuous tones while gated
	dsc_voice #(.ATK(5), .DCY(7), .USE_NOISE(0), .LPF_SH(2)) v_skit (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? hi_g[4] : 1'b0),
		.noise(noise), .inc(`INC(1400)), .out(e_skitter));
	dsc_voice #(.ATK(5), .DCY(7), .USE_NOISE(0), .LPF_SH(3)) v_enemy (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_elim|is_zek ? hi_g[5] : 1'b0),
		.noise(noise), .inc(`INC(240)), .out(e_enemy));

	// Background: a low drone whose pitch steps with D6/D7
	wire [1:0] bg_sel = {hi_g[7], hi_g[6]};
	wire [23:0] bg_inc = (bg_sel == 2'd0) ? `INC(55)  :
	                     (bg_sel == 2'd1) ? `INC(73)  :
	                     (bg_sel == 2'd2) ? `INC(98)  : `INC(131);
	dsc_voice #(.ATK(8), .DCY(8), .USE_NOISE(0), .LPF_SH(4)) v_bg (
		.clk(clk), .reset(reset), .ce(ce),
		.gate((is_elim|is_zek) & (hi_g[6] | hi_g[7])),
		.noise(noise), .inc(bg_inc), .out(e_bg));

	// ==================================================================
	// Space Fury  (nl_spacfury.cpp)
	//
	//   LO: D0 CRAFTS_SCALE  D1 MOVING  D2 THRUST  D6 STAR_SPIN
	//       D7 PARTIAL_WARSHIP
	//   HI: D0 CRAFTS_JOINING D1 SHOOT  D2 FIREBALL D3 SMALL_EXPL
	//       D4 LARGE_EXPL     D5 DOCKING_BANG
	// ==================================================================
	wire signed [15:0] s_scale, s_moving, s_thrust, s_star, s_warship;
	wire signed [15:0] s_join, s_shoot, s_fire, s_small, s_large, s_bang;

	dsc_voice #(.ATK(6), .DCY(9), .USE_NOISE(0), .LPF_SH(3)) v_scale (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & lo_g[0]),
		.noise(noise), .inc(`INC(330)), .out(s_scale));
	dsc_voice #(.ATK(6), .DCY(8), .USE_NOISE(0), .LPF_SH(4)) v_moving (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & lo_g[1]),
		.noise(noise), .inc(`INC(160)), .out(s_moving));
	dsc_voice #(.ATK(7), .DCY(8), .USE_NOISE(1), .LPF_SH(6)) v_sthr (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & lo_g[2]),
		.noise(noise), .inc(24'd0), .out(s_thrust));
	dsc_voice #(.ATK(5), .DCY(9), .USE_NOISE(0), .LPF_SH(2)) v_star (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & lo_g[6]),
		.noise(noise), .inc(`INC(1800)), .out(s_star));
	dsc_voice #(.ATK(4), .DCY(10), .USE_NOISE(0), .LPF_SH(3)) v_warship (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & lo_g[7]),
		.noise(noise), .inc(`INC(520)), .out(s_warship));

	dsc_voice #(.ATK(5), .DCY(9), .USE_NOISE(0), .LPF_SH(3)) v_join (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & hi_g[0]),
		.noise(noise), .inc(`INC(260)), .out(s_join));
	dsc_voice #(.ATK(1), .DCY(9), .USE_NOISE(0), .LPF_SH(2)) v_shoot (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & hi_g[1]),
		.noise(noise), .inc(`INC(760)), .out(s_shoot));
	dsc_voice #(.ATK(3), .DCY(11), .USE_NOISE(1), .LPF_SH(4)) v_sfire (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & hi_g[2]),
		.noise(noise), .inc(24'd0), .out(s_fire));
	dsc_voice #(.ATK(2), .DCY(10), .USE_NOISE(1), .LPF_SH(4)) v_small (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & hi_g[3]),
		.noise(noise), .inc(24'd0), .out(s_small));
	dsc_voice #(.ATK(2), .DCY(13), .USE_NOISE(1), .LPF_SH(6)) v_large (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & hi_g[4]),
		.noise(noise), .inc(24'd0), .out(s_large));
	dsc_voice #(.ATK(1), .DCY(11), .USE_NOISE(1), .LPF_SH(5)) v_bang (
		.clk(clk), .reset(reset), .ce(ce), .gate(is_sf & hi_g[5]),
		.noise(noise), .inc(24'd0), .out(s_bang));

	// ------------------------------------------------------------------
	// Mix. Every voice is quartered, so a handful sounding at once still
	// leaves headroom; MAME's own output_scale for these boards is 0.15
	// (Eliminator/Zektor) and 2.0 (Space Fury), which is a reminder that the
	// absolute level here is arbitrary either way.
	// ------------------------------------------------------------------
	// Weights are the real ones, read off Sega drawing 800-3174 rev B sheet 8:
	// U9 is a TL082 inverting summer with Rf = R5 = 10K, and each source
	// arrives through its own resistor, so the gain is 10K/Rin.
	//
	//   BUFFER, the summed event voices   R8  22K   x1.00   (reference)
	//   divider chain / hexagons          R9  33K   x0.667  -3.5 dB
	//   SKITTER                           R6 220K   x0.100  -20 dB
	//   ENEMY SHIP                        R7 220K   x0.100  -20 dB
	//   PSG (the AY, fitted on Zektor)    R10 10K   x2.20   +6.8 dB
	//
	// Skitter and enemy ship being 20 dB down is the striking one, and is not
	// something the netlist makes obvious.
	wire signed [19:0] buf_e =
		{{4{e_fire[15]}},    e_fire}    + {{4{e_ex1[15]}},     e_ex1}     +
		{{4{e_ex2[15]}},     e_ex2}     + {{4{e_ex3[15]}},     e_ex3}     +
		{{4{e_bounce[15]}},  e_bounce}  + {{4{e_tor1[15]}},    e_tor1}    +
		{{4{e_tor2[15]}},    e_tor2}    + {{4{e_thrust[15]}},  e_thrust};

	wire signed [19:0] sk20 = {{4{e_skitter[15]}}, e_skitter};
	wire signed [19:0] en20 = {{4{e_enemy[15]}},   e_enemy};
	wire signed [19:0] bg20 = {{4{e_bg[15]}},      e_bg};

	// 0.1 as >>3 - >>5 + >>7 - >>9, 0.667 as >>1 + >>3 + >>5 + >>7
	wire signed [19:0] sum_e = buf_e
		+ ((sk20 >>> 3) - (sk20 >>> 5) + (sk20 >>> 7) - (sk20 >>> 9))
		+ ((en20 >>> 3) - (en20 >>> 5) + (en20 >>> 7) - (en20 >>> 9))
		+ ((bg20 >>> 1) + (bg20 >>> 3) + (bg20 >>> 5) + (bg20 >>> 7));

	wire signed [19:0] sum_s =
		{{4{s_scale[15]}},   s_scale}   + {{4{s_moving[15]}},  s_moving}  +
		{{4{s_thrust[15]}},  s_thrust}  + {{4{s_star[15]}},    s_star}    +
		{{4{s_warship[15]}}, s_warship} + {{4{s_join[15]}},    s_join}    +
		{{4{s_shoot[15]}},   s_shoot}   + {{4{s_fire[15]}},    s_fire}    +
		{{4{s_small[15]}},   s_small}   + {{4{s_large[15]}},   s_large}   +
		{{4{s_bang[15]}},    s_bang};

	// each voice can reach full scale alone, so leave room for several
	wire signed [19:0] sum = (is_sf ? sum_s : sum_e) >>> 5;

	assign audio = !enabled          ? 16'sd0 :
	               (sum >  20'sd32767) ?  16'sh7FFF :
	               (sum < -20'sd32768) ? -16'sh8000 : sum[15:0];

	`undef INC

endmodule

`default_nettype wire
