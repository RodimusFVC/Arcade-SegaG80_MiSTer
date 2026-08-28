//============================================================================
//  Sega Universal Sound Board (drawing 800-0377)
//
//  Used by Tac/Scan and Star Trek. An 8035 at 6 MHz drives three 8253 timers
//  and three envelope DAC groups, mixed with an MM5837 noise source.
//
//  Transcribed from refs/mame/segausb.cpp.
//
//  The board has no ROM of its own: the main Z80 uploads the 8035's program
//  into shared RAM through the $D000-$DFFF window, which is why that window
//  goes through the security scrambler.
//
//  Register map, seen by the 8035 as its entire I/O space and backed by 1K of
//  work RAM in four 256-byte banks selected by P2[1:0]. Writes to the first
//  24 bytes of the bank are also decoded as controls:
//
//    $00-$03  8253 U41   $04-$06  ENV0 DACs   $07  ENV0 config
//    $08-$0B  8253 U42   $0C-$0E  ENV1 DACs   $0F  ENV1 config
//    $10-$13  8253 U43   $14-$16  ENV2 DACs   $17  ENV2 config
//
//  Clocking, all divided from the 6 MHz master:
//    2MHZ = /3, PCS = 2MHZ/2, GOS = 2MHZ/16/4, MM5837 = 100 kHz,
//    T1 counter = 2MHZ/256
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module sega_usb #(
	parameter int CLK_HZ = 12_096_000
) (
	input  wire        clk,
	input  wire        reset,

	// ---- host side, main Z80 ----
	input  wire        data_wr,      // $3F write, one cycle
	input  wire  [7:0] din,
	output wire  [7:0] status,       // $3F read

	// shared program RAM window at $D000-$DFFF
	input  wire [11:0] pgm_addr,
	input  wire  [7:0] pgm_din,
	input  wire        pgm_wr,
	output logic [7:0] pgm_dout,

	// ---- audio ----
	output wire signed [15:0] audio,

	// Simulation taps: everything the analog chain consumes, so a bench can
	// drive MAME's double-precision model from the same stimulus and compare.
	// Unused on hardware; synthesis prunes them.
	output wire        dbg_tick,
	output wire        dbg_noise,
	output wire  [8:0] dbg_tmr,      // {group2, group1, group0}
	output wire  [2:0] dbg_cfg,
	output wire [71:0] dbg_env       // g0c0, g0c1, g0c2, g1c0, ... g2c2
);

	// ------------------------------------------------------------------
	// Clock enables
	// ------------------------------------------------------------------
	localparam int CPU_HZ = 6_000_000;

	logic [23:0] acc_cpu;
	logic        ce_cpu;
	always_ff @(posedge clk) begin
		if (reset) begin acc_cpu <= '0; ce_cpu <= 1'b0; end
		else if (acc_cpu + CPU_HZ >= CLK_HZ) begin
			acc_cpu <= acc_cpu + CPU_HZ - CLK_HZ; ce_cpu <= 1'b1;
		end else begin
			acc_cpu <= acc_cpu + CPU_HZ;          ce_cpu <= 1'b0;
		end
	end

	// 2 MHz stream tick = master/3
	logic [1:0] div3;
	logic       ce_2m;
	always_ff @(posedge clk) begin
		if (reset) begin div3 <= 2'd0; ce_2m <= 1'b0; end
		else begin
			ce_2m <= 1'b0;
			if (ce_cpu) begin
				if (div3 == 2'd2) begin div3 <= 2'd0; ce_2m <= 1'b1; end
				else               div3 <= div3 + 2'd1;
			end
		end
	end

	// PCS = 2MHz/2, GOS gate toggles at 2MHz/(GOS*2), MM5837 = 2MHz/20,
	// T1 counter = 2MHz/256
	logic        pcs_tog;
	logic  [4:0] mm_div;
	logic [15:0] gos_div;
	logic  [7:0] t1_div;
	logic        ce_pcs, ce_mm, gos_flip, ce_t1;

	always_ff @(posedge clk) begin
		if (reset) begin
			pcs_tog <= 1'b0; mm_div <= 5'd0; gos_div <= 16'd0; t1_div <= 8'd0;
			ce_pcs <= 1'b0; ce_mm <= 1'b0; gos_flip <= 1'b0; ce_t1 <= 1'b0;
		end else begin
			ce_pcs <= 1'b0; ce_mm <= 1'b0; gos_flip <= 1'b0; ce_t1 <= 1'b0;
			if (ce_2m) begin
				pcs_tog <= ~pcs_tog;
				if (pcs_tog) ce_pcs <= 1'b1;

				if (mm_div == 5'd19) begin mm_div <= 5'd0; ce_mm <= 1'b1; end
				else                       mm_div <= mm_div + 5'd1;

				// Channel 2's gate toggles every 2MHZ/GOS/2 ticks. GOS is
				// 2MHz/16/4 = 2MHz/64, so that is 64/2 = every 32 ticks —
				// one full gate period per GOS cycle.
				if (gos_div == 16'd31) begin gos_div <= 16'd0; gos_flip <= 1'b1; end
				else                        gos_div <= gos_div + 16'd1;

				if (t1_div == 8'd255) begin t1_div <= 8'd0; ce_t1 <= 1'b1; end
				else                       t1_div <= t1_div + 8'd1;
			end
		end
	end

	// ------------------------------------------------------------------
	// Host latches
	// ------------------------------------------------------------------
	logic [7:0] in_latch, out_latch;
	logic [7:0] t1_clock;
	localparam logic [7:0] T1_CLOCK_MASK = 8'h10;   // set by board jumpers

	// only bits 0 and 7 come from the 8035; 1-6 read back the input latch
	assign status = (out_latch & 8'h81) | (in_latch & 8'h7e);

	// ------------------------------------------------------------------
	// Shared program RAM, 4K. Port A is the main Z80, port B the 8035.
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] pgm_ram [0:4095];
	logic [7:0] pgm_q;

	// /LOAD: the main Z80 may only write while bit 7 of the input latch is
	// set, which is the same bit that holds the 8035 in reset. The board
	// cannot have its program rewritten underneath a running 8035.
	wire pgm_wr_en = pgm_wr & in_latch[7];

	always_ff @(posedge clk) begin
		if (pgm_wr_en) pgm_ram[pgm_addr] <= pgm_din;
		pgm_dout <= pgm_ram[pgm_addr];
		pgm_q    <= pgm_ram[cpu_pc];
	end

	// ------------------------------------------------------------------
	// Work RAM, 1K as four 256-byte banks
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] work_ram [0:1023];
	logic [7:0] work_q;
	logic [1:0] work_bank;

	wire [9:0] work_addr = {work_bank, addr_lo};

	// ------------------------------------------------------------------
	// 8035
	// ------------------------------------------------------------------
	wire        psen_n, rd_n, wr_n, ale;
	wire  [7:0] cpu_do, p1_out, p2_out;
	logic [7:0] addr_lo;
	logic [7:0] cpu_di;
	logic       ale_d;

	// P2 must be sampled at the ALE edge alongside the low address byte: the
	// core's P2 output is registered, so reading it live during PSEN returns
	// the written P2 register rather than PC[11:8]. See sega_speech.sv.
	logic [7:0] p2_lat;
	wire [11:0] cpu_pc = {p2_lat[3:0], addr_lo};

	always_ff @(posedge clk) begin
		if (reset) begin
			addr_lo <= 8'd0;
			p2_lat  <= 8'd0;
			ale_d   <= 1'b0;
		end else if (ce_cpu) begin
			ale_d <= ale;
			if (!ale && ale_d) begin
				addr_lo <= cpu_do;
				p2_lat  <= p2_out;
			end
		end
	end

	always_ff @(posedge clk) work_q <= work_ram[work_addr];

	always_comb begin
		cpu_di = 8'hFF;
		if (!psen_n)    cpu_di = pgm_q;    // program fetch from shared RAM
		else if (!rd_n) cpu_di = work_q;   // MOVX read: work RAM
	end

	i8035 cpu (
		.clk     (clk),
		.ce      (ce_cpu),
		// Bit 7 of the input latch is /LOAD: while the host has it set the
		// 8035 is held in reset and the program RAM is being written.
		.I_RSTn  (~reset & ~in_latch[7]),
		.I_INTn  (1'b1),
		.I_EA    (1'b1),                  // 8035 has no internal ROM
		.O_PSENn (psen_n),
		.O_RDn   (rd_n),
		.O_WRn   (wr_n),
		.O_ALE   (ale),
		.O_PROGn (),
		.I_T0    (1'b1),
		.O_T0    (),
		.I_T1    ((t1_clock & T1_CLOCK_MASK) != 8'd0),
		.I_DB    (cpu_di),
		.O_DB    (cpu_do),
		.I_P1    ({1'b0, in_latch[6:0]}),  // P1 in = in_latch & 0x7F, as MAME
		.O_P1    (p1_out),
		.I_P2    (8'hFF),
		.O_P2    (p2_out)
	);

	// MOVX write, strobed once at the end of the cycle. The 8035 drives the
	// data bus only while WR is low and releases it at the rising edge, so the
	// bus is sampled during the pulse and held for the strobe — reading cpu_do
	// at the strobe itself gets whatever the core drives when idle.
	logic wr_n_d;
	logic [7:0] wr_data;
	always_ff @(posedge clk) begin
		if (reset) begin
			wr_n_d  <= 1'b1;
			wr_data <= 8'd0;
		end else if (ce_cpu) begin
			wr_n_d <= wr_n;
			if (!wr_n) wr_data <= cpu_do;
		end
	end
	wire movx_wr = ce_cpu && wr_n && !wr_n_d;

	// ------------------------------------------------------------------
	// Port writes and the control decode
	// ------------------------------------------------------------------
	logic [7:0] env [0:2][0:2];
	logic [2:0] cfg;
	logic [7:0] last_p2;


	// which group and register a work RAM write targets
	wire [1:0] grp     = addr_lo[4:3];
	wire       is_ctc  = (addr_lo[2] == 1'b0);         // $x0-$x3 timer, $x4-$x7 env
	wire       in_regs = (addr_lo < 8'h18);

	wire tmr_wr0 = movx_wr && in_regs && is_ctc && (grp == 2'd0);
	wire tmr_wr1 = movx_wr && in_regs && is_ctc && (grp == 2'd1);
	wire tmr_wr2 = movx_wr && in_regs && is_ctc && (grp == 2'd2);

	integer g;
	always_ff @(posedge clk) begin
		if (reset) begin
			in_latch  <= 8'd0;
			out_latch <= 8'd0;
			work_bank <= 2'd0;
			last_p2   <= 8'd0;
			t1_clock  <= 8'd0;
			cfg       <= 3'd0;
			for (g = 0; g < 3; g = g + 1) begin
				env[g][0] <= 8'd0; env[g][1] <= 8'd0; env[g][2] <= 8'd0;
			end
		end else begin
			// Host write to $3F. While the 8035 has CLEAR low (P2 bit 6),
			// the low seven bits are ignored — only the /LOAD bit lands.
			if (data_wr) in_latch <= last_p2[6] ? din : (din & 8'h80);

			// T1 free-running counter, held clear while P2 bit 7 is high
			if (ce_t1 && !last_p2[7]) t1_clock <= t1_clock + 8'd1;

			if (ce_cpu) begin
				// P1 bit 7 -> bit 0 of the output latch
				out_latch[0] <= p1_out[7];

				// P2: bank select, ready bit, input-latch clear, T1 reset
				if (p2_out != last_p2) begin
					work_bank    <= p2_out[1:0];
					out_latch[7] <= p2_out[6];
					if (!p2_out[6]) in_latch <= 8'd0;
					if (last_p2[7] && !p2_out[7]) t1_clock <= 8'd0;
					last_p2 <= p2_out;
				end
			end

			// work RAM write, plus the control decode on the low 24 bytes
			if (movx_wr) begin
				work_ram[work_addr] <= wr_data;
				if (in_regs && !is_ctc && (addr_lo[1:0] != 2'd3))
					env[grp][addr_lo[1:0]] <= wr_data;
				if (in_regs && !is_ctc && (addr_lo[1:0] == 2'd3))
					cfg[grp] <= wr_data[0];
			end
		end
	end

	// ------------------------------------------------------------------
	// Timers. Channels 0 and 1 clock at PCS with the gate held high;
	// channel 2 clocks at 2 MHz with its gate toggling at GOS/2.
	// ------------------------------------------------------------------
	logic ch2_gate;
	always_ff @(posedge clk) begin
		if (reset)         ch2_gate <= 1'b0;
		else if (gos_flip) ch2_gate <= ~ch2_gate;
	end

	wire [2:0] ch_clk  = {ce_2m, ce_pcs, ce_pcs};
	wire [2:0] ch_gate = {ch2_gate, 1'b1, 1'b1};

	wire [2:0] tmr_out, tmr_out1, tmr_out2;

	usb_timer t0 (.clk(clk), .reset(reset), .wr(tmr_wr0), .addr(addr_lo[1:0]),
	              .din(wr_data), .ch_clk(ch_clk), .ch_gate(ch_gate), .out(tmr_out));
	usb_timer t1 (.clk(clk), .reset(reset), .wr(tmr_wr1), .addr(addr_lo[1:0]),
	              .din(wr_data), .ch_clk(ch_clk), .ch_gate(ch_gate), .out(tmr_out1));
	usb_timer t2 (.clk(clk), .reset(reset), .wr(tmr_wr2), .addr(addr_lo[1:0]),
	              .din(wr_data), .ch_clk(ch_clk), .ch_gate(ch_gate), .out(tmr_out2));

	wire noise;
	usb_noise ns (.clk(clk), .reset(reset), .tick(ce_mm), .state(noise));

	assign dbg_tick  = ce_2m;
	assign dbg_noise = noise;
	assign dbg_tmr   = {tmr_out2, tmr_out1, tmr_out};
	assign dbg_cfg   = cfg;
	assign dbg_env   = {env[2][2], env[2][1], env[2][0],
	                    env[1][2], env[1][1], env[1][0],
	                    env[0][2], env[0][1], env[0][0]};

	// ------------------------------------------------------------------
	// Analog chain
	// ------------------------------------------------------------------
	usb_filter flt (
		.clk      (clk),
		.reset    (reset),
		.tick     (ce_2m),
		.noise_in (noise),
		.tmr0     (tmr_out),
		.tmr1     (tmr_out1),
		.tmr2     (tmr_out2),
		.env0_0   (env[0][0]), .env0_1 (env[0][1]), .env0_2 (env[0][2]),
		.env1_0   (env[1][0]), .env1_1 (env[1][1]), .env1_2 (env[1][2]),
		.env2_0   (env[2][0]), .env2_1 (env[2][1]), .env2_2 (env[2][2]),
		.cfg      (cfg),
		.audio    (audio)
	);

endmodule

`default_nettype wire
