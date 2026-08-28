//============================================================================
//  Sega speech board (drawing 800-0294)
//
//  Used by Space Fury, Zektor and Star Trek. An 8035 at 3.12 MHz reads LPC
//  frames out of the speech data ROM and feeds them to an SP0250.
//
//  Transcribed from refs/mame/segaspeech.cpp:
//
//    P1 in       latch & 0x7F
//    P1 out      bit 7 low clears T0
//    P2 out      speech data ROM bank; [5:0] selects a 256-byte page
//    I/O read    speech_data[0x100 * (P2 & 0x3F) + addr]
//    I/O write   SP0250 frame byte
//    T0          set when the latch's bit 7 goes 0 -> 1
//    T1          SP0250 DRQ
//    INT         latch bit 7 inverted (asserted while bit 7 is low)
//
//  The main CPU writes the latch at $38 and the control register at $3B.
//  Control bit 3 gates the speech output; bit 5 gates a third CD4053 channel
//  fed from off-board, which on Star Trek is the Universal Sound Board.
//
//  The 8035's program ROM is 2K mirrored at $0800, which the address mask
//  below reproduces.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_speech #(
	parameter int CLK_HZ  = 12_096_000,   // clk domain
	parameter int CPU_HZ  =  3_120_000,   // speech board master clock
	// The board's output filter. MAME does not apply it (segaspeech.cpp has
	// ENABLE_NETLIST_FILTERING 0), so set FILTER=0 to match MAME exactly.
	parameter bit FILTER    = 1'b1,
	parameter bit C10_TENTH = 1'b0
) (
	input  wire        clk,
	input  wire        reset,

	// from the main CPU
	input  wire        data_wr,      // $38, one cycle
	input  wire        ctrl_wr,      // $3B, one cycle
	input  wire  [7:0] din,

	// ROM load
	input  wire        rom_wr,
	input  wire [14:0] rom_addr,     // 0x0000-0x07FF cpu, 0x0800-0x47FF data
	input  wire  [7:0] rom_data,

	// audio in from the Universal Sound Board, gated by control bit 5
	input  wire signed [15:0] usb_audio,

	output wire signed [15:0] audio,

	// simulation taps; unused on hardware and pruned by synthesis
	output wire [10:0] dbg_prog_addr,
	output wire        dbg_sp_wr,
	output wire  [7:0] dbg_sp_data,
	output wire        dbg_drq,
	output wire        dbg_t0,
	output wire  [7:0] dbg_p1,
	output wire        dbg_rd_n,
	output wire [13:0] dbg_data_addr,
	output wire        dbg_int_n,
	output wire signed [7:0] dbg_dac
);

	// ------------------------------------------------------------------
	// 3.12 MHz clock enable
	// ------------------------------------------------------------------
	logic [23:0] acc;
	logic        ce;

	always_ff @(posedge clk) begin
		if (reset) begin
			acc <= '0;
			ce  <= 1'b0;
		end else if (acc + CPU_HZ >= CLK_HZ) begin
			acc <= acc + CPU_HZ - CLK_HZ;
			ce  <= 1'b1;
		end else begin
			acc <= acc + CPU_HZ;
			ce  <= 1'b0;
		end
	end

	// ------------------------------------------------------------------
	// Host-facing latch and control register
	// ------------------------------------------------------------------
	logic [7:0] latch;
	logic [7:0] control;
	logic       t0;
	logic       p1_7_d;

	// MAME clears T0 inside p1_w, i.e. only at the instant the program writes
	// P1 with bit 7 low — not for as long as the pin sits low. That difference
	// matters: once the speech program has left bit 7 low, a level-sensitive
	// clear wipes each newly arrived word within a few clocks, long before the
	// 8035 (58 clk per instruction here) can poll T0, and the board goes
	// permanently silent after the first word. Clearing on the falling edge
	// reproduces MAME's behaviour: repeated writes of a low bit 7 are
	// idempotent, and a word arriving while the pin is already low survives.
	wire p1_7_fall = ce && !p1_out[7] && p1_7_d;

	always_ff @(posedge clk) begin
		if (reset) begin
			// bit 7 high means "no interrupt pending". MAME never touches the
			// 8035's INT line until the first host write, so its effective
			// power-on state is deasserted; resetting the latch to 0 instead
			// would hold INT asserted from boot.
			latch   <= 8'h80;
			control <= 8'h00;
			t0      <= 1'b0;
			p1_7_d  <= 1'b1;
		end else begin
			if (ce) p1_7_d <= p1_out[7];
			if (ctrl_wr) control <= din;
			if (data_wr) begin
				// a rising edge on bit 7 clocks a 1 into T0
				if (!latch[7] && din[7]) t0 <= 1'b1;
				latch <= din;
			end
			if (p1_7_fall) t0 <= 1'b0;
		end
	end

	// ------------------------------------------------------------------
	// Program ROM: 2K, mirrored at $0800
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] cpu_rom [0:2047];
	logic [7:0] cpu_rom_q;

	wire rom_wr_cpu  = rom_wr && (rom_addr < 15'h0800);
	wire rom_wr_data = rom_wr && (rom_addr >= 15'h0800) && (rom_addr < 15'h4800);

	// ------------------------------------------------------------------
	// Speech data ROM: 16K, paged 256 bytes at a time by P2[5:0]
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] data_rom [0:16383];
	logic [7:0] data_rom_q;

	// ------------------------------------------------------------------
	// 8035
	// ------------------------------------------------------------------
	wire        psen_n, rd_n, wr_n, ale, prog_n;
	wire  [7:0] cpu_do, p1_out, p2_out;
	wire        cpu_t0_out;
	logic [7:0] cpu_di;
	logic [7:0] addr_lo;      // latched from the multiplexed bus by ALE
	logic [7:0] p2_lat;       // P2 sampled at the same ALE edge

	// The low address byte is multiplexed onto the data bus and latched on the
	// falling edge of ALE.
	// A real board latches the bus in a 74LS373 at ALE, and samples P2 at the
	// same instant. That matters: the core multiplexes PC[11:8] onto P2 only
	// around the fetch and its P2 output is registered, so reading P2 live
	// during PSEN gets the *written* P2 register (the speech data bank)
	// instead of the program counter — the 8035 then fetches from whichever
	// page the bank last selected. Latching both halves together is both
	// what the hardware does and correct for MOVX, where P2 carries the bank.
	logic ale_d;
	always_ff @(posedge clk) begin
		if (reset) begin
			addr_lo <= 8'd0;
			p2_lat  <= 8'd0;
			ale_d   <= 1'b0;
		end else if (ce) begin
			ale_d <= ale;
			if (!ale && ale_d) begin
				addr_lo <= cpu_do;
				p2_lat  <= p2_out;
			end
		end
	end

	// P2 is multiplexed exactly as on the real part: the low nibble carries
	// PC[11:8] during a program fetch and the written P2 register otherwise,
	// so it can be used live for both the program address and the speech data
	// bank — PSEN and RD never overlap.
	//
	// Program ROM is 2K mirrored at $0800, so only 11 bits matter.
	wire [10:0] prog_addr = {p2_lat[2:0], addr_lo};
	wire [13:0] data_addr = {p2_lat[5:0], addr_lo};

	// Registered on clk, not ce: there are ~4 clk per ce at 12.096/3.12, so the
	// data is ready well inside the cycle the 8035 reads it.
	always_ff @(posedge clk) begin
		cpu_rom_q  <= cpu_rom[prog_addr];
		data_rom_q <= data_rom[data_addr];
	end

	always_comb begin
		cpu_di = 8'hFF;
		if (!psen_n)     cpu_di = cpu_rom_q;    // program fetch
		else if (!rd_n)  cpu_di = data_rom_q;   // MOVX read: speech data
	end

	i8035 cpu (
		.clk     (clk),
		.ce      (ce),
		.I_RSTn  (~reset),
		.I_INTn  (latch[7]),        // INT asserted while bit 7 is low
		.I_EA    (1'b1),            // 8035 has no internal ROM
		.O_PSENn (psen_n),
		.O_RDn   (rd_n),
		.O_WRn   (wr_n),
		.O_ALE   (ale),
		.O_PROGn (prog_n),
		.I_T0    (t0),
		.O_T0    (cpu_t0_out),
		.I_T1    (sp_drq),
		.I_DB    (cpu_di),
		.O_DB    (cpu_do),
		.I_P1    ({1'b0, latch[6:0]}),   // P1 in = latch & 0x7F, as MAME's p1_r
		.O_P1    (p1_out),
		.I_P2    (8'hFF),
		.O_P2    (p2_out)
	);

	// ------------------------------------------------------------------
	// SP0250
	// ------------------------------------------------------------------
	// A MOVX write goes to the synthesiser. WR is a level for the whole cycle,
	// so strobe once at its end, when the data bus has settled — the same
	// treatment the CPU multiplier and the AY need.
	// The 8035 drives the data bus only while WR is low and releases it at the
	// rising edge, so the bus must be sampled *during* the pulse and the value
	// held for the strobe. Reading cpu_do at the strobe itself gets whatever
	// the core drives when idle — which is mostly 00, and silences the board.
	logic wr_n_d;
	logic [7:0] wr_data;
	always_ff @(posedge clk) begin
		if (reset) begin
			wr_n_d  <= 1'b1;
			wr_data <= 8'd0;
		end else if (ce) begin
			wr_n_d <= wr_n;
			if (!wr_n) wr_data <= cpu_do;
		end
	end
	wire sp_wr = ce && wr_n && !wr_n_d;

	wire       sp_drq;
	wire signed [7:0] sp_dac;
	wire       sp_stb;

	sp0250 synth (
		.clk          (clk),
		.ce           (ce),
		.reset        (reset),
		.wr           (sp_wr),
		.din          (wr_data),
		.drq          (sp_drq),
		.dac          (sp_dac),
		.sample_stb   (sp_stb),
		.sample_start (),
		.dbg_fifo_pos (),
		.dbg_repeat   (),
		.dbg_rcount   (),
		.dbg_pcount   (),
		.dbg_amp      ()
	);

	assign dbg_prog_addr = prog_addr;
	assign dbg_sp_wr     = sp_wr;
	assign dbg_sp_data   = wr_data;
	assign dbg_drq       = sp_drq;
	assign dbg_t0        = t0;
	assign dbg_p1        = p1_out;
	assign dbg_rd_n      = rd_n;
	assign dbg_data_addr = data_addr;
	assign dbg_int_n     = latch[7];
	assign dbg_dac       = sp_dac;

	// ------------------------------------------------------------------
	// ROM load
	// ------------------------------------------------------------------
	always_ff @(posedge clk) begin
		if (rom_wr_cpu)  cpu_rom[rom_addr[10:0]] <= rom_data;
		if (rom_wr_data) data_rom[rom_addr[13:0] - 14'h0800] <= rom_data;
	end

	// ------------------------------------------------------------------
	// Output mix. Control bit 3 gates the speech, bit 5 gates the off-board
	// channel (the USB on Star Trek), both through a CD4053.
	// ------------------------------------------------------------------
	// The board filters the SP0250 *before* the CD4053, so the gate comes
	// after. See speech_filter.sv — MAME leaves this filter out by default.
	wire signed [15:0] sp_filtered;

	speech_filter #(.C10_TENTH(C10_TENTH)) filt (
		.clk   (clk),
		.reset (reset),
		.ce    (ce),
		.dac   (sp_dac),
		.audio (sp_filtered)
	);

	wire signed [15:0] speech_out = control[3]
	                              ? (FILTER ? sp_filtered : {sp_dac, 8'd0})
	                              : 16'sd0;
	wire signed [15:0] aux_out    = control[5] ? usb_audio      : 16'sd0;

	assign audio = speech_out + aux_out;

endmodule

`default_nettype wire
