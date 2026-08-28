//============================================================================
//  Sega G-80 security chip (315-0062/0063/0064/0070/0076/0082)
//
//  These are NOT opcode decrypters. They scramble the *address* of RAM writes
//  performed by the opcode $32 (LD (nnnn),A): the low byte of the destination
//  address is passed through one of four fixed bit permutations, chosen by two
//  bits of the PC *of that $32 opcode*.
//
//  Reference: refs/mame/segag80_m.cpp (sega_decrypt62..82, Aaron Giles / MB).
//  Only the first write after the $32 fetch is scrambled, matching MAME's
//  decrypt_offset() which consumes m_scrambled_write_pc on use.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

// ---------------------------------------------------------------------------
// Chip identifiers (MRA-selected)
// ---------------------------------------------------------------------------
package sega_security_pkg;
	localparam logic [2:0] CHIP_NONE = 3'd0;  // bootlegs: no scrambling
	localparam logic [2:0] CHIP_0062 = 3'd1;
	localparam logic [2:0] CHIP_0063 = 3'd2;
	localparam logic [2:0] CHIP_0064 = 3'd3;  // Space Fury, Star Trek
	localparam logic [2:0] CHIP_0070 = 3'd4;  // Eliminator 2P
	localparam logic [2:0] CHIP_0076 = 3'd5;  // Eliminator 4P, Tac/Scan
	localparam logic [2:0] CHIP_0082 = 3'd6;  // Zektor
endpackage


// ---------------------------------------------------------------------------
// The four permutations. Each is a pure bit shuffle of the low address byte;
// B, C and D each invert exactly one bit. MAME writes these as a sum of
// shifted masks, but every term lands on a distinct output bit, so the sum is
// a plain bit permutation.
// ---------------------------------------------------------------------------
module sega_security_perm (
	input  wire [1:0] perm,   // 0=A (identity), 1=B, 2=C, 3=D
	input  wire [7:0] din,
	output logic [7:0] dout
);
	// A: identity
	wire [7:0] a = din;

	// B: i = b&0x03 + (b&0x80)>>1 + (b&0x60)>>3 + (~b)&0x10
	//          + (b&0x08)<<2 + (b&0x04)<<5
	wire [7:0] b = { din[2],  din[7],  din[3], ~din[4],
	                 din[6],  din[5],  din[1],  din[0] };

	// C: i = b&0x03 + (b&0x80)>>4 + (~b&0x40)>>1 + (b&0x20)>>1
	//          + (b&0x10)>>2 + (b&0x08)<<3 + (b&0x04)<<5
	wire [7:0] c = { din[2],  din[3], ~din[6],  din[5],
	                 din[7],  din[4],  din[1],  din[0] };

	// D: i = b&0x23 + (b&0xC0)>>4 + (b&0x10)<<2 + (b&0x08)<<1
	//          + (~b&0x04)<<5
	wire [7:0] d = { ~din[2], din[4],  din[5],  din[3],
	                  din[7], din[6],  din[1],  din[0] };

	always_comb begin
		unique case (perm)
			2'd0: dout = a;
			2'd1: dout = b;
			2'd2: dout = c;
			2'd3: dout = d;
		endcase
	end
endmodule


// ---------------------------------------------------------------------------
// Per-chip configuration.
//
// Every chip selects on two PC bits: bit 0 and one higher bit. MAME's switch
// masks are 0x03 (hi bit = 1), 0x09 (hi bit = 3) and 0x11 (hi bit = 4). The
// four cases map onto permutations A..D in a chip-specific order, packed here
// as {perm[3], perm[2], perm[1], perm[0]} indexed by {pc[hibit], pc[0]}.
// ---------------------------------------------------------------------------
module sega_security_cfg (
	input  wire  [2:0] chip,
	output logic [3:0] hibit,
	output logic [7:0] permmap,
	output logic       enable
);
	always_comb begin
		unique case (chip)
			//                      hibit  permmap  (see table below)
			sega_security_pkg::CHIP_0062: begin hibit=4'd1; permmap=8'h1B; enable=1'b1; end
			sega_security_pkg::CHIP_0063: begin hibit=4'd3; permmap=8'h1B; enable=1'b1; end
			sega_security_pkg::CHIP_0064: begin hibit=4'd1; permmap=8'hE4; enable=1'b1; end
			sega_security_pkg::CHIP_0070: begin hibit=4'd3; permmap=8'hB1; enable=1'b1; end
			sega_security_pkg::CHIP_0076: begin hibit=4'd3; permmap=8'hE4; enable=1'b1; end
			sega_security_pkg::CHIP_0082: begin hibit=4'd4; permmap=8'hE4; enable=1'b1; end
			default:                      begin hibit=4'd1; permmap=8'hE4; enable=1'b0; end
		endcase
	end
	// permmap derivations, index = {pc[hibit], pc[0]}:
	//   0062: 0->D 1->C 2->B 3->A  = {A,B,C,D} = {0,1,2,3} = 8'h1B
	//   0063: 0->D 1->C 2->B 3->A  = 8'h1B
	//   0064: 0->A 1->B 2->C 3->D  = {D,C,B,A} = {3,2,1,0} = 8'hE4
	//   0070: 0->B 1->A 2->D 3->C  = {C,D,A,B} = {2,3,0,1} = 8'hB1
	//   0076: 0->A 1->B 2->C 3->D  = 8'hE4
	//   0082: 0->A 1->B 2->C 3->D  = 8'hE4
endmodule


// ---------------------------------------------------------------------------
// Combinational scrambler: given the chip and the PC of the $32 opcode,
// permute the low byte of the write address.
// ---------------------------------------------------------------------------
module sega_security_scramble (
	input  wire  [2:0]  chip,
	input  wire  [15:0] op_pc,
	input  wire  [7:0]  addr_lo,
	output wire  [7:0]  addr_lo_scrambled
);
	wire [3:0] hibit;
	wire [7:0] permmap;
	wire       enable;

	sega_security_cfg cfg (.chip(chip), .hibit(hibit), .permmap(permmap), .enable(enable));

	wire       pc_hi = op_pc[hibit];
	wire [1:0] sel   = {pc_hi, op_pc[0]};
	wire [1:0] perm  = permmap[{sel, 1'b1} -: 2];   // permmap[2*sel+1 : 2*sel]

	wire [7:0] permuted;
	sega_security_perm p (.perm(perm), .din(addr_lo), .dout(permuted));

	assign addr_lo_scrambled = enable ? permuted : addr_lo;
endmodule


// ---------------------------------------------------------------------------
// Bus-side wrapper.
//
// Tracks opcode fetches (M1 cycles) to arm on $32, then scrambles the low byte
// of the next RAM write address. `armed` is cleared by the next opcode fetch or
// by the write that consumes it, exactly like MAME's m_scrambled_write_pc.
// ---------------------------------------------------------------------------
module sega_security (
	input  wire        clk,
	input  wire        reset,
	input  wire  [2:0] chip,

	// Opcode fetch strobe: one cycle, when the Z80 latches an opcode byte
	input  wire        op_fetch,
	input  wire [15:0] op_addr,
	input  wire  [7:0] op_data,

	// Memory write about to happen into one of the scrambled RAM windows
	input  wire        mem_wr,      // one cycle, coincident with the write
	input  wire [15:0] wr_addr,
	output wire [15:0] wr_addr_out  // combinational: scrambled if armed
);
	logic        armed;
	logic [15:0] armed_pc;

	wire [7:0] lo_scrambled;
	sega_security_scramble s (
		.chip(chip), .op_pc(armed_pc), .addr_lo(wr_addr[7:0]),
		.addr_lo_scrambled(lo_scrambled)
	);

	assign wr_addr_out = armed ? {wr_addr[15:8], lo_scrambled} : wr_addr;

	always_ff @(posedge clk) begin
		if (reset) begin
			armed    <= 1'b0;
			armed_pc <= 16'hFFFF;
		end else if (op_fetch) begin
			// LD (nnnn),A arms the scrambler; any other opcode disarms it
			armed    <= (op_data == 8'h32);
			armed_pc <= op_addr;
		end else if (mem_wr) begin
			// a single write consumes the arming
			armed    <= 1'b0;
		end
	end
endmodule

`default_nettype wire
