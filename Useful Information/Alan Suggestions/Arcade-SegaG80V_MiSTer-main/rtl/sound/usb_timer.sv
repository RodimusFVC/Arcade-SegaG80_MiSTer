//============================================================================
//  8253 programmable interval timer, as used on the Sega Universal Sound Board
//
//  Three of these sit on the board (U41, U42, U43), one per sound group.
//  Transcribed from refs/mame/segausb.cpp (timer8253).
//
//  Only clock modes 1 (one-shot) and 3 (square wave) are implemented, matching
//  MAME — those are the only modes the board's program uses, and a real 8253's
//  other modes would be dead logic here.
//
//  Register interface, written through the 8035's work RAM window:
//    offset 0-2   count byte for that channel, per its latch mode
//    offset 3     control: {channel[1:0], latchmode[1:0], clockmode[2:0], bcd}
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module usb_timer (
	input  wire        clk,
	input  wire        reset,

	// register write
	input  wire        wr,
	input  wire  [1:0] addr,
	input  wire  [7:0] din,

	// per-channel clock enables and gates
	input  wire  [2:0] ch_clk,     // one cycle: advance this channel
	input  wire  [2:0] ch_gate,

	output wire  [2:0] out         // channel outputs
);

	logic        holding   [0:2];
	logic  [1:0] latchmode [0:2];
	logic        latchtog  [0:2];
	logic  [2:0] clockmode [0:2];
	logic        bcdmode   [0:2];
	logic        output_q  [0:2];
	logic        lastgate  [0:2];
	logic [15:0] count     [0:2];
	logic [15:0] remain    [0:2];

	assign out = {output_q[2], output_q[1], output_q[0]};

	wire [1:0] ctrl_ch = din[7:6];

	// MAME applies a register write and then clocks within the same update, so
	// a clock arriving on the same cycle as a write must see the written
	// values. Working through local variables gives that ordering; plain
	// non-blocking assignments would let the clock read pre-write state.
	integer i;
	always_ff @(posedge clk) begin
		automatic logic        v_hold  [0:2];
		automatic logic  [1:0] v_lmode [0:2];
		automatic logic        v_ltog  [0:2];
		automatic logic  [2:0] v_cmode [0:2];
		automatic logic        v_out   [0:2];
		automatic logic        v_lgate [0:2];
		automatic logic [15:0] v_count [0:2];
		automatic logic [15:0] v_rem   [0:2];
		automatic logic        was_holding;

		if (reset) begin
			for (i = 0; i < 3; i = i + 1) begin
				holding[i]   <= 1'b0;
				latchmode[i] <= 2'd0;
				latchtog[i]  <= 1'b0;
				clockmode[i] <= 3'd0;
				bcdmode[i]   <= 1'b0;
				output_q[i]  <= 1'b0;
				lastgate[i]  <= 1'b0;
				count[i]     <= 16'd0;
				remain[i]    <= 16'd0;
			end
		end else begin
			for (i = 0; i < 3; i = i + 1) begin
				v_hold[i]  = holding[i];
				v_lmode[i] = latchmode[i];
				v_ltog[i]  = latchtog[i];
				v_cmode[i] = clockmode[i];
				v_out[i]   = output_q[i];
				v_lgate[i] = lastgate[i];
				v_count[i] = count[i];
				v_rem[i]   = remain[i];
			end

			// ---- register write ------------------------------------------
			if (wr) begin
				if (addr == 2'd3) begin
					// mode set; channel 3 is a read-back command and ignored
					if (ctrl_ch != 2'd3) begin
						v_hold[ctrl_ch]  = 1'b1;
						v_lmode[ctrl_ch] = din[5:4];
						v_cmode[ctrl_ch] = din[3:1];
						v_ltog[ctrl_ch]  = 1'b0;
						v_out[ctrl_ch]   = (din[3:1] == 3'd1);
						bcdmode[ctrl_ch] <= din[0];
					end
				end else begin
					was_holding = v_hold[addr];
					unique case (v_lmode[addr])
					2'd1: begin                       // low byte only
						v_count[addr] = {8'd0, din};
						v_hold[addr]  = 1'b0;
					end
					2'd2: begin                       // high byte only
						v_count[addr] = {din, 8'd0};
						v_hold[addr]  = 1'b0;
					end
					2'd3: begin                       // low then high
						if (!v_ltog[addr]) begin
							v_count[addr] = {v_count[addr][15:8], din};
							v_ltog[addr]  = 1'b1;
						end else begin
							v_count[addr] = {din, v_count[addr][7:0]};
							v_hold[addr]  = 1'b0;
							v_ltog[addr]  = 1'b0;
						end
					end
					default: ;                        // mode 0 latches, unused
					endcase
					// loading the initial count kicks the channel off at 1
					if (was_holding && !v_hold[addr]) v_rem[addr] = 16'd1;
				end
			end

			// ---- clocking -------------------------------------------------
			for (i = 0; i < 3; i = i + 1) begin
				if (ch_clk[i]) begin
					automatic logic old_lgate = v_lgate[i];
					v_lgate[i] = ch_gate[i];
					if (!v_hold[i]) begin
						unique case (v_cmode[i])
						3'd1: begin
							// one-shot, restarted by a rising gate
							if (!old_lgate && ch_gate[i]) begin
								v_out[i] = 1'b0;
								v_rem[i] = v_count[i];
							end else begin
								v_rem[i] = v_rem[i] - 16'd1;
								if (v_rem[i] == 16'd0) v_out[i] = 1'b1;
							end
						end
						3'd3: begin
							// square wave: counts down by two, toggles at zero
							v_rem[i] = (v_rem[i] - 16'd1) & ~16'd1;
							if (v_rem[i] == 16'd0) begin
								v_out[i] = ~v_out[i];
								v_rem[i] = v_count[i];
							end
						end
						default: ;
						endcase
					end
				end
			end

			for (i = 0; i < 3; i = i + 1) begin
				holding[i]   <= v_hold[i];
				latchmode[i] <= v_lmode[i];
				latchtog[i]  <= v_ltog[i];
				clockmode[i] <= v_cmode[i];
				output_q[i]  <= v_out[i];
				lastgate[i]  <= v_lgate[i];
				count[i]     <= v_count[i];
				remain[i]    <= v_rem[i];
			end
		end
	end

endmodule

`default_nettype wire
