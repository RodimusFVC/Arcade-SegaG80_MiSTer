//============================================================================
//  Building blocks for the Sega G-80 discrete sound boards
//
//  These are behavioural models, not a netlist port. MAME emulates the
//  Eliminator, Zektor and Space Fury boards only as SPICE-style netlists
//  (nl_elim.cpp, nl_spacfury.cpp — 30 KB each of 555s, CA3080 OTAs and CD4011
//  one-shots), which is not something that maps onto RTL. So unlike the 8253,
//  the MM5837, the SP0250 and the vector generator, **there is no bit-exact
//  target here and nothing to diff against.** Read every parameter in
//  sega_discrete.sv as an approximation.
//
//  Everything runs off a single clock enable, nominally 48 kHz-ish, which is
//  ample for these sounds — the highest tone on either board is a few kHz.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

// ---------------------------------------------------------------------------
// White noise. 17-bit maximal LFSR, the same polynomial the MM5837 uses, which
// is also what these boards use for their own noise source.
// ---------------------------------------------------------------------------
module dsc_noise (
	input  wire clk,
	input  wire reset,
	input  wire ce,
	output wire out
);
	logic [16:0] shift;
	always_ff @(posedge clk) begin
		if (reset)   shift <= 17'h15555;      // zero is a lock-up state
		else if (ce) shift <= {shift[15:0], shift[13] ^ shift[16]};
	end
	assign out = shift[16];
endmodule

// ---------------------------------------------------------------------------
// RC envelope. Rises towards full scale while gated and decays towards zero
// when released, both as one-pole exponentials — which is what an RC charging
// through a diode and discharging through a resistor actually does.
//
// ATK and DCY are shift amounts: the time constant is (1 << n) ce ticks.
// ---------------------------------------------------------------------------
module dsc_env #(
	parameter int ATK = 6,
	parameter int DCY = 11
) (
	input  wire clk,
	input  wire reset,
	input  wire ce,
	input  wire gate,
	output wire [15:0] level
);
	localparam logic [23:0] FULL = 24'hFF0000;

	logic [23:0] cap;
	always_ff @(posedge clk) begin
		if (reset)        cap <= '0;
		else if (ce) begin
			if (gate)     cap <= cap + ((FULL - cap) >> ATK);
			else          cap <= cap - (cap >> DCY);
		end
	end
	assign level = cap[23:8];
endmodule

// ---------------------------------------------------------------------------
// Square-wave oscillator. `inc` is added to a phase accumulator each tick, so
// the frequency is inc * ce_hz / 2^24. Also brings out a triangle, which is a
// closer match for the OTA-based voices than a hard square.
// ---------------------------------------------------------------------------
module dsc_osc (
	input  wire        clk,
	input  wire        reset,
	input  wire        ce,
	input  wire [23:0] inc,
	output wire        square,
	output wire signed [15:0] wave
);
	logic [23:0] phase;
	always_ff @(posedge clk) begin
		if (reset)   phase <= '0;
		else if (ce) phase <= phase + inc;
	end
	assign square = phase[23];
	// fold the top bits into a triangle: up on the first half, down on the second
	wire [15:0] ramp = phase[22:7];
	assign wave = phase[23] ? $signed({1'b0, ~ramp[15:1]}) : $signed({1'b0, ramp[15:1]});
endmodule

// ---------------------------------------------------------------------------
// One-pole low pass, cap += (in - cap) >> SH.
// ---------------------------------------------------------------------------
module dsc_lpf #(
	parameter int SH = 4
) (
	input  wire clk,
	input  wire reset,
	input  wire ce,
	input  wire signed [15:0] in,
	output wire signed [15:0] out
);
	logic signed [23:0] cap;
	always_ff @(posedge clk) begin
		if (reset)   cap <= '0;
		else if (ce) cap <= cap + (({{8{in[15]}}, in} - cap) >>> SH);
	end
	assign out = cap[15:0];
endmodule

// ---------------------------------------------------------------------------
// A complete voice: envelope x source, where the source is either the shared
// noise bit or an oscillator. Used for most channels on both boards.
// ---------------------------------------------------------------------------
module dsc_voice #(
	parameter int ATK    = 6,
	parameter int DCY    = 11,
	parameter bit USE_NOISE = 1'b0,
	parameter int LPF_SH = 3
) (
	input  wire clk,
	input  wire reset,
	input  wire ce,
	input  wire gate,
	input  wire noise,
	input  wire [23:0] inc,
	output wire signed [15:0] out
);
	wire [15:0] env;
	dsc_env #(.ATK(ATK), .DCY(DCY)) e (
		.clk(clk), .reset(reset), .ce(ce), .gate(gate), .level(env));

	wire osc_sq;
	wire signed [15:0] osc_wave;
	dsc_osc o (.clk(clk), .reset(reset), .ce(ce), .inc(inc),
	           .square(osc_sq), .wave(osc_wave));

	// +/-1 source, then scaled by the envelope
	wire src = USE_NOISE ? noise : osc_sq;
	wire signed [16:0] raw = src ? $signed({1'b0, env}) : -$signed({1'b0, env});
	wire signed [15:0] shaped = raw[16:1];

	dsc_lpf #(.SH(LPF_SH)) f (
		.clk(clk), .reset(reset), .ce(ce), .in(shaped), .out(out));
endmodule

`default_nettype wire
