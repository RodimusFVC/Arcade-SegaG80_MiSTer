//============================================================================
//  Sega G-80 X-Y control panel wiring
//
//  Builds the four source bytes the LS253 matrix reads, plus the FC port, from
//  MiSTer joystick bits. Every bit position is transcribed from the
//  INPUT_PORTS_START blocks in refs/mame/segag80v.cpp.
//
//  Two conventions to keep straight:
//    * D7D6 / D5D4 bits are ACTIVE LOW (switch to ground), so idle is 1.
//    * The FC port is ACTIVE HIGH on every game that uses it, except Space
//      Fury, where MAME marks bit 4 active high and bits 5-7 active low.
//      Those are transcribed exactly rather than normalised.
//
//  COIN1/COIN2 (D7D6 bits 0 and 4), DRAW (D7D6 bit 5) and SERVICE (D5D4 bit 0)
//  are merged in by segag80v_cpu, so they are left high here.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_inputs (
	input  wire  [2:0] game,        // see sega_game_pkg
	input  wire [31:0] joy1,
	input  wire [31:0] joy2,
	input  wire [31:0] joy3,
	input  wire [31:0] joy4,
	input  wire  [7:0] dsw1,        // SW1, read through D3D2
	input  wire  [7:0] dsw2,        // SW2, read through D1D0

	output logic [7:0] in_d7d6,
	output logic [7:0] in_d5d4,
	output logic [7:0] in_d3d2,
	output logic [7:0] in_d1d0,
	output logic [7:0] in_fc,
	output logic [7:0] in_coins,
	output wire        coin_a,
	output wire        coin_b,
	output wire        service
);

	// MiSTer joystick bits, matching the OSD "J1," line in the top level:
	//   0 right  1 left  2 down  3 up
	//   4 fire1  5 fire2  6 fire3  7 fire4
	//   8 start1 9 start2 10 coin 11 pause 12 service
	wire p1_r = joy1[0], p1_l = joy1[1], p1_b1 = joy1[4], p1_b2 = joy1[5];
	wire p1_b3 = joy1[6], p1_b4 = joy1[7];
	wire p2_r = joy2[0], p2_l = joy2[1], p2_b1 = joy2[4], p2_b2 = joy2[5];
	wire p3_r = joy3[0], p3_l = joy3[1], p3_b1 = joy3[4], p3_b2 = joy3[5];
	wire p4_r = joy4[0], p4_l = joy4[1], p4_b1 = joy4[4], p4_b2 = joy4[5];

	wire start1 = joy1[8] | joy2[8];
	wire start2 = joy1[9] | joy2[9];

	wire coin1 = joy1[10] | joy3[10];
	wire coin2 = joy2[10] | joy4[10];

	assign coin_a  = ~coin1;                       // active low
	assign coin_b  = ~coin2;
	assign service = ~(joy1[12] | joy2[12]);

	always_comb begin
		in_d7d6  = 8'hFF;
		in_d5d4  = 8'hFF;
		in_d3d2  = dsw1;
		in_d1d0  = dsw2;
		in_fc    = 8'h00;
		in_coins = 8'hFF;

		unique case (game)

		// ---- Eliminator, 2 players -------------------------------------
		// D7D6: 6 = P1 LEFT
		// D5D4: 1 = START1, 2 = P1 RIGHT, 3 = P1 B1,
		//       5 = START2, 6 = P1 B2, 7 = P2 LEFT
		// FC (active high): 0 = P2 B1, 1 = P2 B2, 2 = P2 RIGHT
		sega_game_pkg::GAME_ELIM2: begin
			in_d7d6[6] = ~p1_l;
			in_d5d4[1] = ~start1;
			in_d5d4[2] = ~p1_r;
			in_d5d4[3] = ~p1_b1;
			in_d5d4[5] = ~start2;
			in_d5d4[6] = ~p1_b2;
			in_d5d4[7] = ~p2_l;
			in_fc      = {5'b00000, p2_r, p2_b2, p2_b1};
		end

		// ---- Eliminator, 4 players -------------------------------------
		// D7D6 bit 0 is the OR of all four coin inputs; bit 6 = P2 B1.
		// D5D4: 1 = P2 B2, 2 = P2 RIGHT, 3 = P2 LEFT,
		//       4 = P1 B1, 5 = P1 B2, 6 = P1 RIGHT, 7 = P1 LEFT
		// FC (active low, through the LS240) carries players 3 and 4;
		// in_coins carries the four coin inputs. Both are demuxed by the
		// select latch at $F8 — see sega_elim4_ports.
		sega_game_pkg::GAME_ELIM4: begin
			in_d7d6[6] = ~p2_b1;
			in_d5d4[1] = ~p2_b2;
			in_d5d4[2] = ~p2_r;
			in_d5d4[3] = ~p2_l;
			in_d5d4[4] = ~p1_b1;
			in_d5d4[5] = ~p1_b2;
			in_d5d4[6] = ~p1_r;
			in_d5d4[7] = ~p1_l;
			in_fc      = {~p3_l, ~p3_r, ~p3_b2, ~p3_b1,
			              ~p4_l, ~p4_r, ~p4_b2, ~p4_b1};
			in_coins   = {4'hF, ~joy4[10], ~joy3[10], ~coin2, ~coin1};
		end

		// ---- Space Fury -------------------------------------------------
		// D5D4: 1 = START1, 2 = P1 LEFT, 3 = P1 B1,
		//       5 = START2, 6 = P1 RIGHT, 7 = P1 B2
		// FC: bit 4 active HIGH, bits 5-7 active LOW (as MAME has it)
		sega_game_pkg::GAME_SPACFURY: begin
			in_d5d4[1] = ~start1;
			in_d5d4[2] = ~p1_l;
			in_d5d4[3] = ~p1_b1;
			in_d5d4[5] = ~start2;
			in_d5d4[6] = ~p1_r;
			in_d5d4[7] = ~p1_b2;
			in_fc      = {~p2_r, ~p2_l, ~p2_b1, p2_b2, 4'b0000};
		end

		// ---- Zektor, Tac/Scan -------------------------------------------
		// Spinner games. START1/START2 move off D5D4 onto the FC port, which
		// is read through the spinner mux: bit 0 of the $F8 select latch
		// switches $FC between the spinner count and these raw bits.
		// FC (active high): 0 = START1, 1 = START2, 2 = B1, 3 = B2
		sega_game_pkg::GAME_ZEKTOR,
		sega_game_pkg::GAME_TACSCAN: begin
			in_fc = {4'b0000, p1_b2, p1_b1, start2, start1};
		end

		// ---- Star Trek ---------------------------------------------------
		// Same spinner arrangement, but four buttons and B1/B2 swapped:
		// FC (active high): 0 = START1, 1 = START2, 2 = B2, 3 = B1,
		//                   4 = B3, 5 = B4
		sega_game_pkg::GAME_STARTREK: begin
			in_fc = {2'b00, p1_b4, p1_b3, p1_b1, p1_b2, start2, start1};
		end

		default: ;
		endcase
	end

endmodule

`default_nettype wire
