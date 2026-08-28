//============================================================================
//  Sega G-80 X-Y vector generator
//
//  Implements the combined function of the X-Y Control board (800-0163) and
//  the X-Y Timing board (800-0161): walk the display list in vector RAM and
//  emit the beam path.
//
//  Transcribed from refs/mame/segag80v_v.cpp (Aaron Giles' gate-level model)
//  and cross-checked against refs/schematics/XY_*.png. Chip designators in the
//  comments refer to those drawings.
//
//  Output is one {x, y, colour, beam} sample per DDA step. The Sega DDA moves
//  the beam by at most one count per VCL clock, so the sample stream *is* the
//  rasterised beam path — it feeds videodr0me_fb directly, with no line drawer
//  in between.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_xy #(
	// VCL clocks charged per phase-generator slot.
	//
	// MAME charges 1/U51_CLOCK == 16 VCL periods per phase. Reading U51 (LS161)
	// driving U50 (LS154) on XY_Timing_800-0161 sheet 7/7 suggests the counter
	// may instead be clocked directly by VCL, making a phase 1 clock. This is
	// the one unresolved timing question in the design; see
	// docs/01-hardware-reference.md §2. The default matches MAME so that the
	// golden-model comparison is exact.
	parameter int PHASE_CLKS  = 16,

	// VCL clocks per 40 Hz frame: 2578080 / 40.
	parameter int BUDGET_CLKS = 64452
) (
	input  wire        clk,
	input  wire        ce,          // VCL clock enable (2.578 MHz)
	input  wire        reset,

	input  wire        frame_start, // EDGINT: begin a new pass over the list

	// Vector RAM read port (4K x 8). Synchronous: data is valid on the ce tick
	// after the address is presented.
	output wire [11:0] vram_addr,
	input  wire  [7:0] vram_data,

	// sin/cos PROM s-c.xyt-u39 (1K x 8, A0 grounded). Same read timing.
	output wire  [9:0] sin_addr,
	input  wire  [7:0] sin_data,

	// Beam output, one sample per ce tick while stepping
	output logic  [9:0] out_x,
	output logic  [9:0] out_y,
	output logic  [5:0] out_colour,  // RRGGBB, = (attrib >> 1) & 0x3F
	output logic        out_beam,
	output logic        out_valid,

	// Status
	output wire         drawing,     // the DRAW flag the CPU polls at $F8 bit 5
	output logic        frame_done   // one ce tick when the list ends
);

	// Minimum dwell so a synchronous memory read fits even at PHASE_CLKS == 1
	// FETCH + LATCH + one final DWELL tick already cost 3 clocks, so 3 is the
	// shortest slot this sequencer can produce. Slot length affects only the
	// real-time duration of DRAW, never the budget bookkeeping below.
	localparam int DWELL    = (PHASE_CLKS < 3) ? 3 : PHASE_CLKS;
	// Budget charged per MAME: 10 phases for a symbol header, 4 for a vector
	// record. `int` is signed, so these subtract cleanly from `budget`.
	localparam int HDR_COST = 10 * PHASE_CLKS;
	localparam int VEC_COST =  4 * PHASE_CLKS;

	typedef enum logic [3:0] {
		ST_IDLE,
		ST_HDR_FETCH,   // present symaddr
		ST_HDR_LATCH,   // vram_data valid, latch into the header registers
		ST_HDR_DWELL,   // burn the rest of the phase slot
		ST_SYM_START,   // header complete: emit the origin move
		ST_VEC_CHECK,   // vector loop condition
		ST_VEC_FETCH,   // present vecaddr
		ST_VEC_LATCH,
		ST_VEC_DWELL,
		ST_SIN_X,       // present sum_x to the PROM
		ST_SIN_Y,       // latch deltax, present sum_y
		ST_SIN_DONE,    // latch deltay, set up the walk
		ST_STEP,        // DDA, one sample per ce tick
		ST_VEC_END,     // attrib[7]: next vector or next symbol
		ST_SYM_END      // draw[7] / budget: next symbol or end of frame
	} state_t;

	state_t state;

	logic signed [31:0] budget;
	logic        [15:0] dwell;
	logic         [3:0] hdr_idx;   // 0..9   position within the symbol header
	logic         [1:0] vec_idx;   // 0..3   position within the vector record

	// Display-list state
	logic [11:0] symaddr;
	logic [11:0] vecaddr;
	logic  [7:0] draw_flag;
	logic [11:0] curx, cury;
	logic  [9:0] symangle;
	logic  [7:0] scale;

	// Per-vector state
	logic  [7:0] attrib;
	logic  [8:0] remaining;   // (len * scale) >> 7, max 508
	logic  [9:0] vecangle;
	logic  [7:0] deltax, deltay;
	logic        xneg, yneg;
	logic  [7:0] xaccum, yaccum;
	logic        beam_ena;
	logic        dda_ran;    // did this vector's step loop run at least once

	// Angle sums: the PROM index is bits [8:0], the direction is bit 9.
	// The +0x100 on the Y sum is what separates cos from sin.
	wire [10:0] sum_x = {1'b0, vecangle} + {1'b0, symangle};
	wire [10:0] sum_y = sum_x + 11'h100;

	// ------------------------------------------------------------------
	// Memory addressing
	// ------------------------------------------------------------------
	wire hdr_active = (state == ST_HDR_FETCH) || (state == ST_HDR_LATCH)
	               || (state == ST_HDR_DWELL);

	assign vram_addr = hdr_active ? symaddr : vecaddr;
	assign sin_addr  = (state == ST_SIN_X) ? {sum_x[8:0], 1'b0}
	                                       : {sum_y[8:0], 1'b0};

	// ------------------------------------------------------------------
	// Clip / screen transform — BOX/BOY at U29 combining into BOS
	//
	// The raw counter is 12 bits but only 11 reach the transform: bit 11, which
	// the header replicates from bit 2 of the high nibble, participates in the
	// counter arithmetic only.
	// ------------------------------------------------------------------
	function automatic logic [10:0] clip_axis(input logic [11:0] raw);
		logic [10:0] v;
		begin
			v = raw[10:0] ^ 11'h200;
			if      ((v & 11'h600) == 11'h200) clip_axis = {1'b1, 10'h000};
			else if ((v & 11'h600) == 11'h400) clip_axis = {1'b1, 10'h3ff};
			else                               clip_axis = {1'b0, v[9:0]};
		end
	endfunction

	wire [10:0] cx      = clip_axis(curx);
	wire [10:0] cy      = clip_axis(cury);
	wire        clipped = cx[10] | cy[10];

	// ------------------------------------------------------------------
	// One DDA step: adders U44/U45 (X) and U46/U47 (Y).
	//
	// Bit 7 of the PROM value is fed back as a carry-in, which rounds small
	// steps down and large steps up. The carry out of bit 8 clocks the up/down
	// position counters U15-U17 (X) and U18-U20 (Y); bit 9 of the angle sum
	// picks the direction.
	// ------------------------------------------------------------------
	wire [8:0] xsum  = {1'b0, xaccum} + {1'b0, deltax} + {8'd0, deltax[7]};
	wire [8:0] ysum  = {1'b0, yaccum} + {1'b0, deltay} + {8'd0, deltay[7]};
	wire [11:0] curx_next = xneg ? (curx - {11'd0, xsum[8]})
	                             : (curx + {11'd0, xsum[8]});
	wire [11:0] cury_next = yneg ? (cury - {11'd0, ysum[8]})
	                             : (cury + {11'd0, ysum[8]});
	wire [10:0] cx_next = clip_axis(curx_next);
	wire [10:0] cy_next = clip_axis(cury_next);

	// 25LS14 at U8: length x scale, keep the 9 MSBs
	wire [15:0] len_prod = {8'd0, vram_data} * {8'd0, scale};

	assign drawing = (state != ST_IDLE);

	// ------------------------------------------------------------------
	// Sequencer
	// ------------------------------------------------------------------
	always_ff @(posedge clk) begin
		if (reset) begin
			state      <= ST_IDLE;
			budget     <= '0;
			out_valid  <= 1'b0;
			frame_done <= 1'b0;
			out_x      <= '0;
			out_y      <= '0;
			out_colour <= '0;
			out_beam   <= 1'b0;
			dda_ran    <= 1'b0;
		end else if (ce) begin
			out_valid  <= 1'b0;
			frame_done <= 1'b0;

			if (frame_start) begin
				// EDGINT restarts the walk from the top of the list. If the
				// previous pass had not finished, emit frame_done anyway so the
				// renderer still gets exactly one end-of-frame per 40 Hz tick
				// and never misses a buffer swap.
				if (state != ST_IDLE) frame_done <= 1'b1;
				state   <= ST_HDR_FETCH;
				budget  <= BUDGET_CLKS;
				symaddr <= 12'd0;
				hdr_idx <= 4'd0;
			end else begin
				unique case (state)

				ST_IDLE: ;   // wait for frame_start

				// ---- symbol header, phases 0..9 --------------------------
				ST_HDR_FETCH: begin
					dwell <= 16'(DWELL - 3);
					state <= ST_HDR_LATCH;
				end

				ST_HDR_LATCH: begin
					unique case (hdr_idx)
					4'd0: draw_flag    <= vram_data;
					4'd1: curx[7:0]    <= vram_data;
					// bit 2 of the high nibble is preloaded into U17 as both
					// bit 10 and bit 11
					4'd2: begin curx[10:8] <= vram_data[2:0];
					            curx[11]   <= vram_data[2]; end
					4'd3: cury[7:0]    <= vram_data;
					4'd4: begin cury[10:8] <= vram_data[2:0];
					            cury[11]   <= vram_data[2]; end
					4'd5: vecaddr[7:0]  <= vram_data;
					4'd6: vecaddr[11:8] <= vram_data[3:0];
					4'd7: symangle[7:0] <= vram_data;
					4'd8: symangle[9:8] <= vram_data[1:0];
					4'd9: scale         <= vram_data;
					endcase

					symaddr <= symaddr + 12'd1;
					state   <= ST_HDR_DWELL;
				end

				ST_HDR_DWELL: begin
					if (dwell != 16'd0) begin
						dwell <= dwell - 16'd1;
					end else if (hdr_idx == 4'd9) begin
						budget <= budget - HDR_COST;
						state  <= ST_SYM_START;
					end else begin
						hdr_idx <= hdr_idx + 4'd1;
						state   <= ST_HDR_FETCH;
					end
				end

				ST_SYM_START: begin
					if (draw_flag[0]) begin
						// emit the symbol origin as a beam-off move
						out_x      <= cx[9:0];
						out_y      <= cy[9:0];
						out_colour <= 6'd0;
						out_beam   <= 1'b0;
						out_valid  <= 1'b1;
						state      <= ST_VEC_CHECK;
					end else begin
						state <= ST_SYM_END;
					end
				end

				// ---- vector record, phases 10..13 -------------------------
				ST_VEC_CHECK: begin
					if (budget > 0) begin
						vec_idx <= 2'd0;
						state   <= ST_VEC_FETCH;
					end else begin
						state <= ST_SYM_END;
					end
				end

				ST_VEC_FETCH: begin
					dwell <= 16'(DWELL - 3);
					state <= ST_VEC_LATCH;
				end

				ST_VEC_LATCH: begin
					unique case (vec_idx)
					2'd0: attrib        <= vram_data;
					2'd1: remaining     <= len_prod[15:7];
					2'd2: vecangle[7:0] <= vram_data;
					2'd3: vecangle[9:8] <= vram_data[1:0];
					endcase

					vecaddr <= vecaddr + 12'd1;
					state   <= ST_VEC_DWELL;
				end

				ST_VEC_DWELL: begin
					if (dwell != 16'd0) begin
						dwell <= dwell - 16'd1;
					end else if (vec_idx == 2'd3) begin
						budget <= budget - VEC_COST;
						state  <= ST_SIN_X;
					end else begin
						vec_idx <= vec_idx + 2'd1;
						state   <= ST_VEC_FETCH;
					end
				end

				// ---- sin/cos lookups + walk setup -------------------------
				// Zero budget cost: MAME charges four phases for the record and
				// these lookups are bookkeeping folded into the last of them.
				ST_SIN_X: state <= ST_SIN_Y;      // sum_x presented this tick

				ST_SIN_Y: begin
					deltax <= sin_data;           // X value now valid
					state  <= ST_SIN_DONE;        // sum_y presented this tick
				end

				ST_SIN_DONE: begin
					deltay   <= sin_data;
					xneg     <= sum_x[9];
					yneg     <= sum_y[9];
					beam_ena <= attrib[0] & (|attrib[6:1]);
					xaccum   <= 8'd0;
					yaccum   <= 8'd0;
					dda_ran  <= 1'b0;
					state    <= ST_STEP;
				end

				// ---- DDA walk --------------------------------------------
				ST_STEP: begin
					if (remaining == 9'd0) begin
						// A zero-length vector draws a dot. MAME emits this
						// once, before its step loop, so it is emitted here on
						// entry when the length was already zero — and skipped
						// when the loop ran the length down, matching the
						// golden model exactly.
						if (!dda_ran) begin
							out_x      <= cx[9:0];
							out_y      <= cy[9:0];
							out_colour <= attrib[6:1];
							out_beam   <= beam_ena & ~clipped;
							out_valid  <= 1'b1;
						end
						state <= ST_VEC_END;
					end else if (budget <= 0) begin
						state <= ST_VEC_END;
					end else begin
						xaccum    <= xsum[7:0];
						yaccum    <= ysum[7:0];
						curx      <= curx_next;
						cury      <= cury_next;
						remaining <= remaining - 9'd1;
						budget    <= budget - 1;
						dda_ran   <= 1'b1;

						// emit the position *after* this step
						out_x      <= cx_next[9:0];
						out_y      <= cy_next[9:0];
						out_colour <= attrib[6:1];
						out_beam   <= beam_ena
						            & ~(cx_next[10] | cy_next[10]);
						out_valid  <= 1'b1;
					end
				end

				ST_VEC_END: begin
					// attribute bit 7 ends the symbol; U52 reloads the phase
					// generator to 0 instead of 10
					if (attrib[7]) state <= ST_SYM_END;
					else           state <= ST_VEC_CHECK;
				end

				ST_SYM_END: begin
					// draw-flag bit 7 ends the whole display list
					if (draw_flag[7] || budget <= 0) begin
						state      <= ST_IDLE;
						frame_done <= 1'b1;
					end else begin
						hdr_idx <= 4'd0;
						state   <= ST_HDR_FETCH;
					end
				end

				default: state <= ST_IDLE;
				endcase
			end
		end
	end

endmodule

`default_nettype wire
