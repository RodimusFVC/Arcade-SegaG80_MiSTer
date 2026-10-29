//  Universal Sound Board filter / mix network
//  Based on MAME segausb.cpp (Aaron Giles, BSD-3-Clause)
//  This program is free software under the GNU General Public License v3.

`default_nettype none

module usb_filter (
	input  wire        clk,
	input  wire        reset,
	input  wire        tick,

	input  wire        noise_in,
	input  wire  [2:0] tmr0,
	input  wire  [2:0] tmr1,
	input  wire  [2:0] tmr2,
	input  wire  [7:0] env0_0, env0_1, env0_2,
	input  wire  [7:0] env1_0, env1_1, env1_2,
	input  wire  [7:0] env2_0, env2_1, env2_2,
	input  wire  [2:0] cfg,

	output logic signed [15:0] audio
);
	localparam int W = 32;
	localparam logic signed [W-1:0] ONE = 32'sh0100_0000;

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

	function automatic logic signed [W-1:0] gain156(input logic signed [W-1:0] x);
		gain156 = x + (x >>> 1) + (x >>> 4);
	endfunction

	logic signed [W-1:0] nf0, nf1, nf2, ncr;
	logic signed [W-1:0] nv;

	wire signed [W-1:0] ns = noise_in ? ONE : 32'sd0;
	wire signed [W-1:0] t0 = (ns <<< 5) + (ns <<< 3) + (ns <<< 1) + (ns >>> 3);
	wire signed [W-1:0] t1 = (ns <<< 3);
	wire signed [W-1:0] t2 = (ns <<< 1) + (ns >>> 1) - (ns >>> 4) + (ns >>> 7);
	wire signed [W-1:0] direct = (ns >>> 2) - (ns >>> 4) - (ns >>> 8) + (ns >>> 10);

	wire signed [W-1:0] nf0_n = nf0 + e_p0(t0 - nf0);
	wire signed [W-1:0] nf1_n = nf1 + e_p1(t1 - nf1);
	wire signed [W-1:0] nf2_n = nf2 + e_p2(t2 - nf2);

	wire signed [W-1:0] nsum    = nf0_n + nf1_n + nf2_n + direct;
	wire signed [W-1:0] ncr_out = nsum - ncr;
	wire signed [W-1:0] nv_next = (ncr_out >>> 4) + (ncr_out >>> 6)
	                            - (ncr_out >>> 8) + (ncr_out >>> 10);

	logic signed [W-1:0] cf0 [0:2];
	logic signed [W-1:0] cf1 [0:2];
	logic signed [W-1:0] gt1 [0:2];
	logic signed [W-1:0] gt2 [0:2];
	logic signed [W-1:0] fin;
	logic signed [W-1:0] acc;

	logic  [2:0] st;
	logic        busy;

	wire       run    = tick | busy;
	wire [2:0] st_cur = tick ? 3'd0 : st;

	wire [1:0] grp = (st_cur == 3'd2) ? 2'd1 : (st_cur == 3'd3) ? 2'd2 : 2'd0;

	wire [2:0] tsel  = (grp == 2'd0) ? tmr0 : (grp == 2'd1) ? tmr1 : tmr2;
	wire [7:0] ev0   = (grp == 2'd0) ? env0_0 : (grp == 2'd1) ? env1_0 : env2_0;
	wire [7:0] ev1   = (grp == 2'd0) ? env0_1 : (grp == 2'd1) ? env1_1 : env2_1;
	wire [7:0] ev2   = (grp == 2'd0) ? env0_2 : (grp == 2'd1) ? env1_2 : env2_2;
	wire       cfg_g = cfg[grp];

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

	wire signed [W-1:0] sq0 = tsel[0] ? ONE : 32'sd0;
	wire signed [W-1:0] sq1 = tsel[1] ? ONE : 32'sd0;
	wire signed [W-1:0] cr0 = sq0 - cf0[grp];
	wire signed [W-1:0] cr1 = sq1 - cf1[grp];
	wire signed [W-1:0] c0  = dac100(cr0, ev0);
	wire signed [W-1:0] c1  = dac100(cr1, ev1);

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

	wire signed [W-1:0] a_g1 = step_g1(gt1[grp], nv, tsel[2]);
	wire signed [W-1:0] a_g2 = step_g2(gt2[grp], a_g1, tsel[2]);
	wire signed [W-1:0] a_c2 = -gain156(dac33(a_g2, ev2));
	wire signed [W-1:0] a_mix = c0 + c1 + a_c2;

	wire signed [W-1:0] b_c2  = -dac33(nv, ev2);
	wire signed [W-1:0] b_pre = c0 + c1 + b_c2;
	wire signed [W-1:0] b_g1  = step_g1(gt1[grp], -b_pre, tsel[2]);
	wire signed [W-1:0] b_g2  = step_g2(gt2[grp], b_g1, tsel[2]);
	wire signed [W-1:0] b_mix = gain156(b_g2);

	wire signed [W-1:0] mix   = cfg_g ? b_mix : a_mix;
	wire signed [W-1:0] g1_n  = cfg_g ? b_g1  : a_g1;
	wire signed [W-1:0] g2_n  = cfg_g ? b_g2  : a_g2;

	wire signed [W-1:0] fin_out = acc - fin;
	wire signed [W-1:0] scaled  = (fin_out >>> 3) - (fin_out >>> 5)
	                            + (fin_out >>> 7) - (fin_out >>> 9);
	wire signed [W-1:0] shifted = scaled >>> 11;
	wire signed [15:0]  clamped = (shifted >  32767) ?  16'sh7FFF :
	                              (shifted < -32768) ? -16'sh8000 :
	                                                    shifted[15:0];

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
				3'd0: begin
					nf0 <= nf0_n;
					nf1 <= nf1_n;
					nf2 <= nf2_n;
					ncr <= ncr + e_ncr(ncr_out);
					nv  <= nv_next;
					acc <= '0;
				end
				3'd1, 3'd2, 3'd3: begin
					cf0[grp] <= cf0[grp] + e_chan(cr0);
					cf1[grp] <= cf1[grp] + e_chan(cr1);
					gt1[grp] <= g1_n;
					gt2[grp] <= g2_n;
					acc      <= acc + mix;
				end
				3'd4: begin
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
