//============================================================================
//  Sega Universal Sound Board analog chain
//
//  Fixed-point version of the filter/mix network in refs/mame/segausb.cpp
//  (usb_sound_device::sound_stream_update).
//
//  FIDELITY NOTE. Unlike the 8253, the MM5837, the SP0250 and the vector
//  generator, this has no bit-exact target. MAME's own comment calls its noise
//  section "just an approximation to the pink noise filter being applied on
//  the PCB, but it sounds pretty close", and the whole chain is double
//  precision. So this approximates an approximation and can only be judged by
//  ear. What is checkable is that every coefficient below is within 0.6% of
//  MAME's, and that the topology and evaluation order match it exactly.
//
//  Arithmetic: 32-bit signed Q8.24 (range +/-128.0, resolution 6e-8).
//
//  Every one-pole coefficient is a sum of at most four signed power-of-two
//  terms, so the filters need no multipliers. MAME's exponents at its 2 MHz
//  stream rate, exponent = 1 - exp(-1/(R*C*2e6)), and what is used here:
//
//    chan CR    (10k,1u)     0.000049999   >>14 - >>16 + >>18 + >>21   0.14%
//    gate1 slow (100k,.01u)  0.000499875   >>11 + >>16 - >>18          0.03%
//    gate1 fast (1k,.01u)    0.048770575    >>4 -  >>6 +  >>9          0.12%
//    gate2 slow (200k,.01u)  0.000249969   >>12 + >>17 - >>19          0.04%
//    gate2 fast (2k,.01u)    0.024690088    >>5 -  >>7 + >>10 + >>12   0.13%
//    noise CR   (33k,.1u)    0.000151504   >>13 + >>15 - >>20          0.09%
//    final CR   (100k,4.7u)  0.000001064   >>20 + >>23 - >>26          0.55%
//
//  The three noise poles are stated by MAME as cap = a*cap + state*b. That is
//  the same one-pole form with exponent (1-a) and a DC target of state*b/(1-a),
//  so they use the same machinery:
//
//    pole0  a=0.99765  e >>9 + >>11 - >>13 + >>15   target <<5+<<3+<<1+>>3
//    pole1  a=0.96300  e  >>5 +  >>7 -  >>9 - >>13  target <<3
//    pole2  a=0.57000  e  >>1 -  >>4 -  >>7         target <<1+>>1->>4+>>7
//
//  Only the three envelope DAC gains need real multipliers (the envelope is
//  an 8-bit value written by the 8035), and the sequencer shares one set of
//  them across the three groups.
//
//  Timing: MAME evaluates one sample of the whole board per 2 MHz tick. Here
//  that is spread over five clocks — noise, then the three groups, then the
//  final mix. At CLK_HZ = 12.096 MHz consecutive 2 MHz ticks are at least six
//  clocks apart, so the sequence always completes; `busy` guards it anyway.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module usb_filter (
	input  wire        clk,
	input  wire        reset,
	input  wire        tick,          // 2 MHz stream tick

	input  wire        noise_in,      // MM5837 state
	input  wire  [2:0] tmr0,          // 8253 outputs, one group per port
	input  wire  [2:0] tmr1,
	input  wire  [2:0] tmr2,
	input  wire  [7:0] env0_0, env0_1, env0_2,
	input  wire  [7:0] env1_0, env1_1, env1_2,
	input  wire  [7:0] env2_0, env2_1, env2_2,
	input  wire  [2:0] cfg,           // per-group envelope mode

	output logic signed [15:0] audio
);
	localparam int W = 32;                                  // Q8.24
	localparam logic signed [W-1:0] ONE = 32'sh0100_0000;

	// ------------------------------------------------------------------
	// Filter coefficients, as signed shift-add sums of the delta
	// ------------------------------------------------------------------
	function automatic logic signed [W-1:0] e_chan(input logic signed [W-1:0] d);
		e_chan = (d >>> 14) - (d >>> 16) + (d >>> 18) + (d >>> 21);
	endfunction
	function automatic logic signed [W-1:0] e_g1_slow(input logic signed [W-1:0] d);
		e_g1_slow = (d >>> 11) + (d >>> 16) - (d >>> 18);
	endfunction
	function automatic logic signed [W-1:0] e_g1_fast(input logic signed [W-1:0] d);
		e_g1_fast = (d >>> 4) - (d >>> 6) + (d >>> 9);
	endfunction
	function automatic logic signed [W-1:0] e_g2_slow(input logic signed [W-1:0] d);
		e_g2_slow = (d >>> 12) + (d >>> 17) - (d >>> 19);
	endfunction
	function automatic logic signed [W-1:0] e_g2_fast(input logic signed [W-1:0] d);
		e_g2_fast = (d >>> 5) - (d >>> 7) + (d >>> 10) + (d >>> 12);
	endfunction
	function automatic logic signed [W-1:0] e_ncr(input logic signed [W-1:0] d);
		e_ncr = (d >>> 13) + (d >>> 15) - (d >>> 20);
	endfunction
	function automatic logic signed [W-1:0] e_final(input logic signed [W-1:0] d);
		e_final = (d >>> 20) + (d >>> 23) - (d >>> 26);
	endfunction
	function automatic logic signed [W-1:0] e_p0(input logic signed [W-1:0] d);
		e_p0 = (d >>> 9) + (d >>> 11) - (d >>> 13) + (d >>> 15);
	endfunction
	function automatic logic signed [W-1:0] e_p1(input logic signed [W-1:0] d);
		e_p1 = (d >>> 5) + (d >>> 7) - (d >>> 9) - (d >>> 13);
	endfunction
	function automatic logic signed [W-1:0] e_p2(input logic signed [W-1:0] d);
		e_p2 = (d >>> 1) - (d >>> 4) - (d >>> 7);
	endfunction

	// 1.56x amplifier: 1 + 1/2 + 1/16 = 1.5625, 0.16% high
	function automatic logic signed [W-1:0] gain156(input logic signed [W-1:0] x);
		gain156 = x + (x >>> 1) + (x >>> 4);
	endfunction

	// ------------------------------------------------------------------
	// Noise source: three parallel poles plus a direct term, then a CR
	// filter and a 0.075 trim.
	// ------------------------------------------------------------------
	logic signed [W-1:0] nf0, nf1, nf2, ncr;
	logic signed [W-1:0] nv;                     // registered noiseval

	// noise_in is one bit, so every one of these is a constant select
	wire signed [W-1:0] ns = noise_in ? ONE : 32'sd0;
	wire signed [W-1:0] t0 = (ns <<< 5) + (ns <<< 3) + (ns <<< 1) + (ns >>> 3);
	wire signed [W-1:0] t1 = (ns <<< 3);
	wire signed [W-1:0] t2 = (ns <<< 1) + (ns >>> 1) - (ns >>> 4) + (ns >>> 7);
	wire signed [W-1:0] direct = (ns >>> 2) - (ns >>> 4) - (ns >>> 8) + (ns >>> 10);

	wire signed [W-1:0] nf0_n = nf0 + e_p0(t0 - nf0);
	wire signed [W-1:0] nf1_n = nf1 + e_p1(t1 - nf1);
	wire signed [W-1:0] nf2_n = nf2 + e_p2(t2 - nf2);

	wire signed [W-1:0] nsum    = nf0_n + nf1_n + nf2_n + direct;
	wire signed [W-1:0] ncr_out = nsum - ncr;    // step_cr returns the difference
	// * 0.075, as 1/16 + 1/64 - 1/256 + 1/1024 = 0.075195
	wire signed [W-1:0] nv_next = (ncr_out >>> 4) + (ncr_out >>> 6)
	                            - (ncr_out >>> 8) + (ncr_out >>> 10);

	// ------------------------------------------------------------------
	// Per-group state and inputs
	// ------------------------------------------------------------------
	logic signed [W-1:0] cf0 [0:2];
	logic signed [W-1:0] cf1 [0:2];
	logic signed [W-1:0] gt1 [0:2];
	logic signed [W-1:0] gt2 [0:2];
	logic signed [W-1:0] fin;
	logic signed [W-1:0] acc;

	logic  [2:0] st;
	logic        busy;

	// State 0 runs on the tick cycle itself, so the whole sequence occupies
	// clocks 0..4 and the next tick cannot arrive before clock 6.
	wire       run    = tick | busy;
	wire [2:0] st_cur = tick ? 3'd0 : st;

	// States 1..3 select group 0..2; states 0 and 4 park on group 0 so the
	// array indices below always stay in range.
	wire [1:0] grp = (st_cur == 3'd2) ? 2'd1 : (st_cur == 3'd3) ? 2'd2 : 2'd0;

	wire [2:0] tsel  = (grp == 2'd0) ? tmr0 : (grp == 2'd1) ? tmr1 : tmr2;
	wire [7:0] ev0   = (grp == 2'd0) ? env0_0 : (grp == 2'd1) ? env1_0 : env2_0;
	wire [7:0] ev1   = (grp == 2'd0) ? env0_1 : (grp == 2'd1) ? env1_1 : env2_1;
	wire [7:0] ev2   = (grp == 2'd0) ? env0_2 : (grp == 2'd1) ? env1_2 : env2_2;
	wire       cfg_g = cfg[grp];

	// ------------------------------------------------------------------
	// Envelope DAC gains. These are the only multipliers in the module.
	// 1/100 as >>7 + >>9 + >>12 (0.098% high), 1/33 as >>5 - >>10 (0.098%).
	// ------------------------------------------------------------------
	function automatic logic signed [W-1:0] dac100(
			input logic signed [W-1:0] x, input logic [7:0] e);
		logic signed [W+8:0] p;
		begin
			p = $signed(x) * $signed({1'b0, e});
			dac100 = W'((p >>> 7) + (p >>> 9) + (p >>> 12));
		end
	endfunction
	function automatic logic signed [W-1:0] dac33(
			input logic signed [W-1:0] x, input logic [7:0] e);
		logic signed [W+8:0] p;
		begin
			p = $signed(x) * $signed({1'b0, e});
			dac33 = W'((p >>> 5) - (p >>> 10));
		end
	endfunction

	// ---- channels 0 and 1: CR filter the 8253 square wave, then scale ----
	wire signed [W-1:0] sq0 = tsel[0] ? ONE : 32'sd0;
	wire signed [W-1:0] sq1 = tsel[1] ? ONE : 32'sd0;
	wire signed [W-1:0] cr0 = sq0 - cf0[grp];
	wire signed [W-1:0] cr1 = sq1 - cf1[grp];
	wire signed [W-1:0] c0  = dac100(cr0, ev0);
	wire signed [W-1:0] c1  = dac100(cr1, ev1);

	// ---- channel 2: the switched gate filters -------------------------
	// MAME picks the exponents from channel 2's output, then steps gate1 and
	// gate2 in series *within this sample* and uses the result immediately —
	// so these are the stepped values, not the stored ones.
	function automatic logic signed [W-1:0] step_g1(
			input logic signed [W-1:0] cap, input logic signed [W-1:0] x,
			input logic fast);
		step_g1 = cap + (fast ? e_g1_fast(x - cap) : e_g1_slow(x - cap));
	endfunction
	function automatic logic signed [W-1:0] step_g2(
			input logic signed [W-1:0] cap, input logic signed [W-1:0] x,
			input logic fast);
		step_g2 = cap + (fast ? e_g2_fast(x - cap) : e_g2_slow(x - cap));
	endfunction

	// config 0: noise -> switched RC -> 1.56x -> invert -> DAC -> 33k -> mix
	wire signed [W-1:0] a_g1 = step_g1(gt1[grp], nv, tsel[2]);
	wire signed [W-1:0] a_g2 = step_g2(gt2[grp], a_g1, tsel[2]);
	wire signed [W-1:0] a_c2 = -gain156(dac33(a_g2, ev2));
	wire signed [W-1:0] a_mix = c0 + c1 + a_c2;

	// config 1: noise -> invert -> DAC -> 33k -> mix -> invert -> RC -> 1.56x
	wire signed [W-1:0] b_c2  = -dac33(nv, ev2);
	wire signed [W-1:0] b_pre = c0 + c1 + b_c2;
	wire signed [W-1:0] b_g1  = step_g1(gt1[grp], -b_pre, tsel[2]);
	wire signed [W-1:0] b_g2  = step_g2(gt2[grp], b_g1, tsel[2]);
	wire signed [W-1:0] b_mix = gain156(b_g2);

	wire signed [W-1:0] mix   = cfg_g ? b_mix : a_mix;
	wire signed [W-1:0] g1_n  = cfg_g ? b_g1  : a_g1;
	wire signed [W-1:0] g2_n  = cfg_g ? b_g2  : a_g2;

	// ---- final mix: CR filter, 0.1 trim, then to 16-bit ---------------
	wire signed [W-1:0] fin_out = acc - fin;
	// * 0.1, as 1/8 - 1/32 + 1/128 - 1/512 = 0.099609
	wire signed [W-1:0] scaled  = (fin_out >>> 3) - (fin_out >>> 5)
	                            + (fin_out >>> 7) - (fin_out >>> 9);
	// MAME's nominal 1.0 maps to a quarter of 16-bit full scale, leaving 12 dB
	// of headroom. That is not arbitrary: MAME's own value for this chain
	// reaches 3.26 on a worst-case stimulus (all nine envelope DACs at random
	// full-scale values at once — see sim/tb/tb_usb_filter.cpp), so mapping
	// 1.0 to full scale would clip the board's own peaks. The core's mixer
	// sets the final level.
	wire signed [W-1:0] shifted = scaled >>> 11;
	wire signed [15:0]  clamped = (shifted >  32767) ?  16'sh7FFF :
	                              (shifted < -32768) ? -16'sh8000 :
	                                                    shifted[15:0];

	// ------------------------------------------------------------------
	integer i;
	always_ff @(posedge clk) begin
		if (reset) begin
			nf0 <= '0; nf1 <= '0; nf2 <= '0; ncr <= '0; nv <= '0;
			fin <= '0; acc <= '0; audio <= 16'sd0;
			st  <= 3'd0; busy <= 1'b0;
			for (i = 0; i < 3; i = i + 1) begin
				cf0[i] <= '0; cf1[i] <= '0; gt1[i] <= '0; gt2[i] <= '0;
			end
		end else begin
			if (run) begin
				st   <= st_cur + 3'd1;
				busy <= (st_cur != 3'd4);
			end

			if (run) begin
				unique case (st_cur)
				3'd0: begin                       // noise source
					nf0 <= nf0_n;
					nf1 <= nf1_n;
					nf2 <= nf2_n;
					ncr <= ncr + e_ncr(ncr_out);
					nv  <= nv_next;
					acc <= '0;
				end
				3'd1, 3'd2, 3'd3: begin           // one group per clock
					cf0[grp] <= cf0[grp] + e_chan(cr0);
					cf1[grp] <= cf1[grp] + e_chan(cr1);
					gt1[grp] <= g1_n;
					gt2[grp] <= g2_n;
					acc      <= acc + mix;
				end
				3'd4: begin                       // final mix
					fin   <= fin + e_final(fin_out);
					audio <= clamped;
				end
				default: ;
				endcase
			end
		end
	end

endmodule

`default_nettype wire
