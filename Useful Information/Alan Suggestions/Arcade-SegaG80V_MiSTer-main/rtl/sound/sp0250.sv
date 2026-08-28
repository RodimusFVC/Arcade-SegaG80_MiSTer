//============================================================================
//  GI SP0250 LPC speech synthesiser
//
//  Used on the Sega speech board (drawing 800-0294) by Space Fury, Zektor and
//  Star Trek, clocked at 3.12 MHz.
//
//  Transcribed from MAME's sound/sp0250.cpp (Olivier Galibert). Verified
//  sample-for-sample against a C++ port of that model — see sim/tb/tb_sp0250.
//
//  Structure
//    A 15-byte FIFO holds one LPC frame. When it is full and the current
//    frame's repeat count is exhausted, the frame is unpacked into six lattice
//    filter stages, an amplitude, a pitch and a repeat count, and DRQ is
//    raised for the next frame.
//
//    One output sample is produced every 4 * 39 ROMCLOCKs, i.e. clock/312 =
//    10 kHz at 3.12 MHz. The six filter stages are evaluated sequentially over
//    six clocks inside that window, which is ample and costs one multiplier.
//
//    The lattice arithmetic wraps at 16 bits in the original and the games
//    depend on it, so the accumulator is deliberately truncated rather than
//    saturated.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sp0250 (
	input  wire        clk,
	input  wire        ce,          // SP0250 master clock enable (3.12 MHz)
	input  wire        reset,

	input  wire        wr,          // one cycle: host writes a frame byte
	input  wire  [7:0] din,

	output wire        drq,         // high while the FIFO has room
	output logic signed [7:0] dac,  // -64..63, updated at 10 kHz
	output logic       sample_stb,  // one cycle when dac updates
	output logic       sample_start, // one cycle when a sample begins

	// debug taps, left unconnected in the design
	output wire  [3:0] dbg_fifo_pos,
	output wire  [7:0] dbg_repeat,
	output wire  [7:0] dbg_rcount,
	output wire  [7:0] dbg_pcount,
	output wire signed [15:0] dbg_amp
);
	assign dbg_fifo_pos = fifo_pos;
	assign dbg_repeat   = repeat_cnt;
	assign dbg_rcount   = rcount;
	assign dbg_pcount   = pcount;
	assign dbg_amp      = amp;

	// ------------------------------------------------------------------
	// Coefficient ROM, verbatim from the SP0250 manual via MAME
	// ------------------------------------------------------------------
	function automatic logic [9:0] coef_mag(input logic [6:0] i);
		case (i)
		7'd0:coef_mag=10'd0;   7'd1:coef_mag=10'd9;   7'd2:coef_mag=10'd17;  7'd3:coef_mag=10'd25;
		7'd4:coef_mag=10'd33;  7'd5:coef_mag=10'd41;  7'd6:coef_mag=10'd49;  7'd7:coef_mag=10'd57;
		7'd8:coef_mag=10'd65;  7'd9:coef_mag=10'd73;  7'd10:coef_mag=10'd81; 7'd11:coef_mag=10'd89;
		7'd12:coef_mag=10'd97; 7'd13:coef_mag=10'd105;7'd14:coef_mag=10'd113;7'd15:coef_mag=10'd121;
		7'd16:coef_mag=10'd129;7'd17:coef_mag=10'd137;7'd18:coef_mag=10'd145;7'd19:coef_mag=10'd153;
		7'd20:coef_mag=10'd161;7'd21:coef_mag=10'd169;7'd22:coef_mag=10'd177;7'd23:coef_mag=10'd185;
		7'd24:coef_mag=10'd193;7'd25:coef_mag=10'd201;7'd26:coef_mag=10'd203;7'd27:coef_mag=10'd217;
		7'd28:coef_mag=10'd225;7'd29:coef_mag=10'd233;7'd30:coef_mag=10'd241;7'd31:coef_mag=10'd249;
		7'd32:coef_mag=10'd257;7'd33:coef_mag=10'd265;7'd34:coef_mag=10'd273;7'd35:coef_mag=10'd281;
		7'd36:coef_mag=10'd289;7'd37:coef_mag=10'd297;7'd38:coef_mag=10'd301;7'd39:coef_mag=10'd305;
		7'd40:coef_mag=10'd309;7'd41:coef_mag=10'd313;7'd42:coef_mag=10'd317;7'd43:coef_mag=10'd321;
		7'd44:coef_mag=10'd325;7'd45:coef_mag=10'd329;7'd46:coef_mag=10'd333;7'd47:coef_mag=10'd337;
		7'd48:coef_mag=10'd341;7'd49:coef_mag=10'd345;7'd50:coef_mag=10'd349;7'd51:coef_mag=10'd353;
		7'd52:coef_mag=10'd357;7'd53:coef_mag=10'd361;7'd54:coef_mag=10'd365;7'd55:coef_mag=10'd369;
		7'd56:coef_mag=10'd373;7'd57:coef_mag=10'd377;7'd58:coef_mag=10'd381;7'd59:coef_mag=10'd385;
		7'd60:coef_mag=10'd389;7'd61:coef_mag=10'd393;7'd62:coef_mag=10'd397;7'd63:coef_mag=10'd401;
		7'd64:coef_mag=10'd405;7'd65:coef_mag=10'd409;7'd66:coef_mag=10'd413;7'd67:coef_mag=10'd417;
		7'd68:coef_mag=10'd421;7'd69:coef_mag=10'd425;7'd70:coef_mag=10'd427;7'd71:coef_mag=10'd429;
		7'd72:coef_mag=10'd431;7'd73:coef_mag=10'd433;7'd74:coef_mag=10'd435;7'd75:coef_mag=10'd437;
		7'd76:coef_mag=10'd439;7'd77:coef_mag=10'd441;7'd78:coef_mag=10'd443;7'd79:coef_mag=10'd445;
		7'd80:coef_mag=10'd447;7'd81:coef_mag=10'd449;7'd82:coef_mag=10'd451;7'd83:coef_mag=10'd453;
		7'd84:coef_mag=10'd455;7'd85:coef_mag=10'd457;7'd86:coef_mag=10'd459;7'd87:coef_mag=10'd461;
		7'd88:coef_mag=10'd463;7'd89:coef_mag=10'd465;7'd90:coef_mag=10'd467;7'd91:coef_mag=10'd469;
		7'd92:coef_mag=10'd471;7'd93:coef_mag=10'd473;7'd94:coef_mag=10'd475;7'd95:coef_mag=10'd477;
		7'd96:coef_mag=10'd479;7'd97:coef_mag=10'd481;7'd98:coef_mag=10'd482;7'd99:coef_mag=10'd483;
		7'd100:coef_mag=10'd484;7'd101:coef_mag=10'd485;7'd102:coef_mag=10'd486;7'd103:coef_mag=10'd487;
		7'd104:coef_mag=10'd488;7'd105:coef_mag=10'd489;7'd106:coef_mag=10'd490;7'd107:coef_mag=10'd491;
		7'd108:coef_mag=10'd492;7'd109:coef_mag=10'd493;7'd110:coef_mag=10'd494;7'd111:coef_mag=10'd495;
		7'd112:coef_mag=10'd496;7'd113:coef_mag=10'd497;7'd114:coef_mag=10'd498;7'd115:coef_mag=10'd499;
		7'd116:coef_mag=10'd500;7'd117:coef_mag=10'd501;7'd118:coef_mag=10'd502;7'd119:coef_mag=10'd503;
		7'd120:coef_mag=10'd504;7'd121:coef_mag=10'd505;7'd122:coef_mag=10'd506;7'd123:coef_mag=10'd507;
		7'd124:coef_mag=10'd508;7'd125:coef_mag=10'd509;7'd126:coef_mag=10'd510;default:coef_mag=10'd511;
		endcase
	endfunction

	// bit 7 clear negates, as in sp0250_gc()
	function automatic logic signed [15:0] coef(input logic [7:0] v);
		logic [9:0] m;
		begin
			m = coef_mag(v[6:0]);
			coef = v[7] ? $signed({6'd0, m}) : -$signed({6'd0, m});
		end
	endfunction

	// amp = (v & 0x1f) << (v >> 5), as in sp0250_ga()
	function automatic logic signed [15:0] amp_of(input logic [7:0] v);
		amp_of = $signed({11'd0, v[4:0]}) <<< v[7:5];
	endfunction

	// ------------------------------------------------------------------
	// Frame FIFO
	// ------------------------------------------------------------------
	logic  [7:0] fifo [0:14];
	logic  [3:0] fifo_pos;

	assign drq = (fifo_pos != 4'd15);

	// ------------------------------------------------------------------
	// Decoded frame state
	// ------------------------------------------------------------------
	logic signed [15:0] fF [0:5];
	logic signed [15:0] fB [0:5];
	logic signed [15:0] z1 [0:5];
	logic signed [15:0] z2 [0:5];
	logic signed [15:0] amp;
	logic               voiced;
	logic         [7:0] pitch, pcount, repeat_cnt, rcount;
	logic        [14:0] lfsr;

	// ------------------------------------------------------------------
	// Sample timing: one sample every 4 * 39 = 156 ROMCLOCKs, and ROMCLOCK is
	// the master clock halved, so every 312 master clocks -> 10 kHz.
	// ------------------------------------------------------------------
	localparam int SAMPLE_DIV = 312;
	logic [8:0] div_cnt;
	logic       start_sample;

	always_ff @(posedge clk) begin
		if (reset) begin
			div_cnt <= 9'd0;
			start_sample <= 1'b0;
		end else begin
			start_sample <= 1'b0;
			if (ce) begin
				if (div_cnt == 9'(SAMPLE_DIV - 1)) begin
					div_cnt <= 9'd0;
					start_sample <= 1'b1;
				end else begin
					div_cnt <= div_cnt + 9'd1;
				end
			end
		end
	end

	// ------------------------------------------------------------------
	// Sequencer: unpack a frame if due, excite, then run the six stages
	// ------------------------------------------------------------------
	typedef enum logic [1:0] { S_IDLE, S_EXCITE, S_FILTER, S_DONE } state_t;
	state_t state;
	logic [2:0] stage;
	logic signed [15:0] z0;

	// z0 = in + ((z1*F) >> 8) + ((z2*B) >> 9), truncated to 16 bits
	wire signed [31:0] mF = z1[stage] * fF[stage];
	wire signed [31:0] mB = z2[stage] * fB[stage];
	wire signed [15:0] z0_next = z0 + 16'(mF >>> 8) + 16'(mB >>> 9);

	wire [14:0] lfsr_next = {lfsr[0] ^ lfsr[1], lfsr[14:1]};

	// dac = z0 >> 6 as a signed 10-bit value, then clamped to -64..63
	wire signed [9:0] dac_full = z0[15:6];
	wire dac_sat_lo = (dac_full < -10'sd64);
	wire dac_sat_hi = (dac_full >  10'sd63);

	integer i;
	always_ff @(posedge clk) begin
		if (reset) begin
			state      <= S_IDLE;
			fifo_pos   <= 4'd0;
			lfsr       <= 15'h7fff;
			amp        <= 16'sd0;
			voiced     <= 1'b0;
			pitch      <= 8'd0;
			pcount     <= 8'd0;
			repeat_cnt <= 8'd0;
			rcount     <= 8'd0;
			dac          <= 8'sd0;
			sample_stb   <= 1'b0;
			sample_start <= 1'b0;
			stage      <= 3'd0;
			for (i = 0; i < 6; i = i + 1) begin
				fF[i] <= 16'sd0; fB[i] <= 16'sd0;
				z1[i] <= 16'sd0; z2[i] <= 16'sd0;
			end
			for (i = 0; i < 15; i = i + 1) fifo[i] <= 8'd0;
		end else begin
			sample_stb   <= 1'b0;
			sample_start <= 1'b0;

			// host write into the frame FIFO
			if (wr && fifo_pos != 4'd15) begin
				fifo[fifo_pos] <= din;
				fifo_pos <= fifo_pos + 4'd1;
			end

			unique case (state)

			S_IDLE: if (start_sample) begin
				sample_start <= 1'b1;
				if (rcount >= repeat_cnt) begin
					if (fifo_pos == 4'd15) begin
						// unpack the frame
						fB[0] <= coef(fifo[0]);  fF[0] <= coef(fifo[1]);
						amp   <= amp_of(fifo[2]);
						fB[1] <= coef(fifo[3]);  fF[1] <= coef(fifo[4]);
						pitch <= fifo[5];
						fB[2] <= coef(fifo[6]);  fF[2] <= coef(fifo[7]);
						repeat_cnt <= {2'd0, fifo[8][5:0]};
						voiced     <= fifo[8][6];
						fB[3] <= coef(fifo[9]);  fF[3] <= coef(fifo[10]);
						fB[4] <= coef(fifo[11]); fF[4] <= coef(fifo[12]);
						fB[5] <= coef(fifo[13]); fF[5] <= coef(fifo[14]);
						fifo_pos <= 4'd0;
						pcount   <= 8'd0;
						rcount   <= 8'd0;
						for (i = 0; i < 6; i = i + 1) begin
							z1[i] <= 16'sd0; z2[i] <= 16'sd0;
						end
					end else begin
						// NOP frame while waiting for input
						repeat_cnt <= 8'd1;
						pcount     <= 8'd0;
						rcount     <= 8'd0;
					end
				end
				state <= S_EXCITE;
			end

			S_EXCITE: begin
				// 15-bit LFSR, clocked every sample regardless of voicing.
				// The chip uses the value *after* the shift, so the excitation
				// samples lfsr_next, not the current register.
				lfsr <= lfsr_next;

				if (voiced) z0 <= (pcount == 8'd0) ? amp : 16'sd0;
				else        z0 <= lfsr_next[0] ? amp : -amp;

				stage <= 3'd0;
				state <= S_FILTER;
			end

			S_FILTER: begin
				z0        <= z0_next;
				z2[stage] <= z1[stage];
				z1[stage] <= z0_next;
				if (stage == 3'd5) state <= S_DONE;
				else               stage <= stage + 3'd1;
			end

			S_DONE: begin
				// 13-bit amplitude reduced to 7 bits, clipped
				if (dac_sat_lo)      dac <= -8'sd64;
				else if (dac_sat_hi) dac <=  8'sd63;
				else                 dac <= dac_full[7:0];

				sample_stb <= 1'b1;

				if (pcount == pitch) begin
					pcount <= 8'd0;
					rcount <= rcount + 8'd1;
				end else begin
					pcount <= pcount + 8'd1;
				end

				state <= S_IDLE;
			end

			endcase
		end
	end

endmodule

`default_nettype wire
