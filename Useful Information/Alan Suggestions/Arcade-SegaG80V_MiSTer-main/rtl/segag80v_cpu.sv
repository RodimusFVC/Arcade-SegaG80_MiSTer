//============================================================================
//  Sega G-80 CPU board (800-0107) + EPROM board (800-0151)
//
//  Z80 at 15468480/4 = 3.867 MHz with two wait states on every memory access,
//  the memory and I/O maps, the LS253 input matrix, the coin/service/EDGINT
//  interrupt chain, and the 315-00xx address scrambler.
//
//  Reference: refs/mame/segag80v.cpp and CPU_Board_800-0107_sheet{6,7}of7.png.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

`default_nettype none

module segag80v_cpu #(
	// Wait states inserted on every memory access. MAME's segag80v.cpp uses 2
	// and notes the real figure "depends on how many rising clock edges MEMRQ
	// is held for, plus 1 additional cycle", with 3 causing visible slowdown in
	// Space Fury. Parameterised so the choice can be measured on a booting game.
	parameter int WAIT_STATES = 2
) (
	input  wire        clk,
	input  wire        ce_cpu,      // 3.867 MHz enable
	input  wire        reset,

	// ---- MRA configuration ----
	input  wire  [2:0] cfg_chip,    // security chip, see sega_security_pkg
	input  wire        cfg_usb,     // Universal Sound Board RAM at $D000
	input  wire  [1:0] cfg_fc,      // 0 = plain port, 1 = spinner, 2 = elim4

	// ---- program ROM, $0000-$BFFF ----
	output wire [15:0] rom_addr,
	input  wire  [7:0] rom_data,

	// ---- vector RAM, $E000-$EFFF (to sega_xy_top) ----
	output wire [11:0] vram_addr,
	output wire  [7:0] vram_din,
	output wire        vram_wr,
	input  wire  [7:0] vram_dout,

	// ---- Universal Sound Board shared RAM, $D000-$DFFF ----
	output wire [11:0] usb_addr,
	output wire  [7:0] usb_din,
	output wire        usb_wr,
	input  wire  [7:0] usb_dout,

	// ---- inputs ----
	input  wire  [7:0] in_d7d6,     // wired as the schematic shows them; the
	input  wire  [7:0] in_d5d4,     // $F8..$FB matrix falls out of the LS253
	input  wire  [7:0] in_d3d2,     // transposition in sega_mangled_ports
	input  wire  [7:0] in_d1d0,
	input  wire  [7:0] in_fc,
	input  wire  [7:0] in_coins,    // Eliminator 4-player coin inputs
	input  wire signed [7:0] spin_delta,
	input  wire        spin_stb,

	input  wire        draw_flag,   // DRAW from the X-Y boards (P1.13)
	input  wire        edgint,      // 40 Hz interrupt from the X-Y timing board
	input  wire        coin_a,      // active low, as the switches present them
	input  wire        coin_b,
	input  wire        service,

	// ---- sound board strobes ----
	output logic       snd_wr,      // $3E/$3F latches
	output logic [1:0] snd_sel,
	output logic       ay_wr,       // $3C/$3D  (Zektor AY-3-8912)
	output wire        ay_port,     // 0 = $3C address latch, 1 = $3D data
	output logic       speech_data_wr,   // $38
	output logic       speech_ctrl_wr,   // $3B
	output logic       usb_data_wr,      // $3F   (Star Trek)
	input  wire  [7:0] usb_status,       // $3F read
	output wire  [7:0] io_dout,

	output logic [1:0] coin_counter,
	output wire        dbg_wram_wr,
	output wire [15:0] dbg_wram_addr_raw,
	output wire [15:0] dbg_wram_addr_scr,
	output wire  [7:0] dbg_wram_data,
	output wire        dbg_io_rd,
	output wire  [7:0] dbg_port,
	output wire        dbg_irq,
	output wire  [1:0] dbg_coin_ff,
	output wire        dbg_int_ack,

	// debug: PC of the opcode that armed the scrambler
	output wire [15:0] dbg_op_addr
);

	// ------------------------------------------------------------------
	// Z80
	// ------------------------------------------------------------------
	wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
	wire [15:0] cpu_a;
	wire  [7:0] cpu_do;
	logic [7:0] cpu_di;
	wire        wait_n;
	logic       int_n, nmi_n;

	tv80e cpu (
		.reset_n (~reset),
		.clk     (clk),
		.cen     (ce_cpu),
		.wait_n  (wait_n),
		.int_n   (int_n),
		.nmi_n   (nmi_n),
		.busrq_n (1'b1),
		.m1_n    (m1_n),
		.mreq_n  (mreq_n),
		.iorq_n  (iorq_n),
		.rd_n    (rd_n),
		.wr_n    (wr_n),
		.rfsh_n  (rfsh_n),
		.halt_n  (),
		.busak_n (),
		.A       (cpu_a),
		.di      (cpu_di),
		.dout    (cpu_do)
	);

	wire mem_rd = ~mreq_n & ~rd_n & rfsh_n;
	wire mem_wr = ~mreq_n & ~wr_n & rfsh_n;
	wire io_rd  = ~iorq_n & ~rd_n & m1_n;
	wire io_wr  = ~iorq_n & ~wr_n & m1_n;
	wire int_ack= ~iorq_n & ~m1_n;          // INTCL

	// ------------------------------------------------------------------
	// Two wait states on every memory access.
	//
	// MAME models this with adjust_icount(-2) on every program-space read and
	// write and every opcode fetch, and does *not* apply it to I/O.
	// ------------------------------------------------------------------
	// tv80 samples wait_n during T2, the same cycle mreq_n first goes low, so
	// the counter must be *reloaded while the bus is idle* and wait_n driven
	// combinationally from the current mreq_n. Deriving it from an edge detect
	// asserts it a clock too late and inserts no waits at all.
	logic [3:0] wait_cnt;
	wire        mem_cycle = ~mreq_n & rfsh_n;

	always_ff @(posedge clk) begin
		if (reset)                      wait_cnt <= 4'(WAIT_STATES);
		else if (ce_cpu) begin
			if (!mem_cycle)             wait_cnt <= 4'(WAIT_STATES);
			else if (wait_cnt != 4'd0)  wait_cnt <= wait_cnt - 4'd1;
		end
	end
	assign wait_n = ~mem_cycle | (wait_cnt == 4'd0);

	// ------------------------------------------------------------------
	// Address decode
	// ------------------------------------------------------------------
	wire sel_rom  = (cpu_a <  16'hC000);
	wire sel_wram = (cpu_a >= 16'hC800) && (cpu_a < 16'hD000);
	wire sel_usb  = cfg_usb && (cpu_a >= 16'hD000) && (cpu_a < 16'hE000);
	wire sel_vram = (cpu_a >= 16'hE000) && (cpu_a < 16'hF000);

	assign rom_addr = cpu_a;

	// ------------------------------------------------------------------
	// Security chip at U21 — scrambles the low byte of the destination of
	// writes issued by opcode $32 (LD (nnnn),A).
	// ------------------------------------------------------------------
	logic        m1_rd_d;
	logic  [7:0] op_data;
	logic [15:0] op_addr;
	logic        mem_wr_d;

	wire m1_rd = ~m1_n & ~mreq_n & ~rd_n;

	always_ff @(posedge clk) begin
		if (reset) begin
			m1_rd_d  <= 1'b0;
			mem_wr_d <= 1'b0;
		end else if (ce_cpu) begin
			m1_rd_d  <= m1_rd;
			mem_wr_d <= mem_wr;
			if (m1_rd) begin
				op_data <= cpu_di;
				op_addr <= cpu_a;
			end
		end
	end

	// end of the opcode read, when the byte on the bus has settled
	wire op_fetch = ce_cpu & m1_rd_d & ~m1_rd;
	// end of a write, so the scrambled address is still valid during it
	wire wr_done  = ce_cpu & mem_wr_d & ~mem_wr;

	wire [15:0] wr_addr_s;
	assign dbg_op_addr = op_addr;

	sega_security sec (
		.clk         (clk),
		.reset       (reset),
		.chip        (cfg_chip),
		.op_fetch    (op_fetch),
		.op_addr     (op_addr),
		.op_data     (op_data),
		.mem_wr      (wr_done),
		.wr_addr     (cpu_a),
		.wr_addr_out (wr_addr_s)
	);

	// ------------------------------------------------------------------
	// 2K work RAM at $C800-$CFFF (the 2114s at U26-U28)
	// ------------------------------------------------------------------
	(* ramstyle = "M10K" *) logic [7:0] wram [0:2047];
	logic [7:0] wram_q;

	always_ff @(posedge clk) begin
		if (sel_wram && mem_wr) wram[wr_addr_s[10:0]] <= cpu_do;
		wram_q <= wram[cpu_a[10:0]];
	end

	assign vram_addr = wr_addr_s[11:0];
	assign vram_din  = cpu_do;
	assign vram_wr   = sel_vram && mem_wr;

	assign usb_addr  = wr_addr_s[11:0];
	assign usb_din   = cpu_do;
	assign usb_wr    = sel_usb && mem_wr;

	// ------------------------------------------------------------------
	// I/O
	// ------------------------------------------------------------------
	wire [7:0] port = cpu_a[7:0];

	logic [7:0] sel_latch;   // $F8 write: spinner select / elim4 demux select

	// DRAW (P1.13) and the coin/service switches are wired into the source
	// bytes here rather than by the caller. Bit positions follow the D7D6 and
	// D5D4 port definitions in refs/mame/segag80v.cpp:
	//   D7D6: bit 0 = COIN1, bit 4 = COIN2, bit 5 = DRAW
	//   D5D4: bit 0 = SERVICE
	// All the switch inputs are active low and idle high.
	wire [7:0] in_d7d6_live = { in_d7d6[7:6], draw_flag, coin_b,
	                            in_d7d6[3:1], coin_a };
	wire [7:0] in_d5d4_live = { in_d5d4[7:1], service };

	wire [7:0] mangled;
	sega_mangled_ports mp (
		.sel  (port[1:0]),
		.d7d6 (in_d7d6_live),
		.d5d4 (in_d5d4_live),
		.d3d2 (in_d3d2),
		.d1d0 (in_d1d0),
		.dout (mangled)
	);

	wire [7:0] spin_q;
	sega_spinner spin (
		.clk       (clk),
		.reset     (reset),
		.delta     (spin_delta),
		.delta_stb (spin_stb),
		.fc_in     (in_fc),
		.sel_raw   (sel_latch[0]),
		.dout      (spin_q)
	);

	wire [7:0] elim4_q;
	sega_elim4_ports e4 (
		.sel      (sel_latch),
		.fc_in    (in_fc),
		.coins_in (in_coins),
		.dout     (elim4_q)
	);

	// io_rd and io_wr are levels held for the whole I/O cycle, and ce_cpu
	// pulses several times inside one, so the multiplier must be strobed on the
	// *edge*. Reading $BE shifts the result down by eight; strobing it per
	// enable shifted it several times and returned garbage for the high byte.
	logic mult_rd_d, mult_wr_d, mult_wr_port_d;
	logic [7:0] mult_data_d;
	wire  mult_rd_lvl = io_rd && (port == 8'hBE);
	wire  mult_wr_lvl = io_wr && (port == 8'hBD || port == 8'hBE);

	always_ff @(posedge clk) begin
		if (reset) begin
			mult_rd_d      <= 1'b0;
			mult_wr_d      <= 1'b0;
			mult_wr_port_d <= 1'b0;
			mult_data_d    <= 8'd0;
		end else begin
			mult_rd_d <= mult_rd_lvl;
			mult_wr_d <= mult_wr_lvl;
			// hold which port and what data, since both are gone by the time
			// the falling edge is seen
			if (mult_wr_lvl) begin
				mult_wr_port_d <= (port == 8'hBE);
				mult_data_d    <= cpu_do;
			end
		end
	end

	// Strobe on the *falling* edge, i.e. at the end of the cycle. Reading $BE
	// shifts the result down by eight, so shifting on the rising edge would
	// move it before the Z80 latches the byte and the first read would return
	// the high byte instead of the low one.
	wire [7:0] mult_q;
	sega_multiplier mult (
		.clk    (clk),
		.reset  (reset),
		.wr     (!mult_wr_lvl && mult_wr_d),
		.wr_sel (mult_wr_port_d),
		.din    (mult_data_d),
		.rd     (!mult_rd_lvl && mult_rd_d),
		.dout   (mult_q)
	);

	logic [7:0] io_q;
	always_comb begin
		io_q = 8'hFF;
		casez (port)
			8'hBE: io_q = mult_q;
			8'h3F: io_q = cfg_usb ? usb_status : 8'hFF;
			8'b1111_10??: io_q = mangled;              // $F8-$FB
			8'hFC: unique case (cfg_fc)
			           2'd1:    io_q = spin_q;
			           2'd2:    io_q = elim4_q;
			           default: io_q = in_fc;
			       endcase
			default: io_q = 8'hFF;
		endcase
	end
	assign io_dout = io_q;
	assign ay_port = port[0];   // $3C -> 0, $3D -> 1

	always_comb begin
		cpu_di = 8'hFF;
		if      (io_rd)    cpu_di = io_q;
		else if (sel_rom)  cpu_di = rom_data;
		else if (sel_wram) cpu_di = wram_q;
		else if (sel_usb)  cpu_di = usb_dout;
		else if (sel_vram) cpu_di = vram_dout;
	end

	// ---- output strobes ----
	always_comb begin
		snd_wr         = io_wr && (port == 8'h3E || (port == 8'h3F && !cfg_usb));
		snd_sel        = {1'b0, port[0]};
		ay_wr          = io_wr && (port == 8'h3C || port == 8'h3D);
		speech_data_wr = io_wr && (port == 8'h38);
		speech_ctrl_wr = io_wr && (port == 8'h3B);
		usb_data_wr    = io_wr && (port == 8'h3F) && cfg_usb;
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			sel_latch    <= 8'd0;
			coin_counter <= 2'd0;
		end else if (ce_cpu && io_wr) begin
			// $F9, mirrored at $FD
			if (port == 8'hF9 || port == 8'hFD) coin_counter <= cpu_do[7:6];
			if (port == 8'hF8)                  sel_latch    <= cpu_do;
		end
	end

	// ------------------------------------------------------------------
	// Interrupt chain (CPU board sheet 7/7)
	//
	//   XINT   = COINA flip-flop | COINB flip-flop | SERVICE pulse
	//   /EDGINT = 40 Hz from the X-Y timing board, clocking another LS74
	//   INTCL  = interrupt acknowledge, clears all of them
	//
	// MAME latches the IRQ line and only recomputes it on an event, and the
	// SERVICE input has no flip-flop — it contributes to exactly one update.
	// Both behaviours are reproduced here.
	//
	// Note: port $BF bit 2 is believed to be the interrupt enable, but MAME
	// only logs writes there and never gates on it, and all five games work.
	// The latch is kept below and deliberately not used; wiring it in is an
	// open item that needs a booting game to validate.
	// ------------------------------------------------------------------
	logic [1:0] coin_ff;
	logic       edgint_ff;
	logic       service_pulse;
	logic       irq_line;
	logic       coin_a_d, coin_b_d, service_d, edgint_d;
	logic [7:0] int_enable_latch;

	wire coin_a_fall = coin_a_d & ~coin_a;
	wire coin_b_fall = coin_b_d & ~coin_b;
	wire coin_a_rise = ~coin_a_d & coin_a;
	wire coin_b_rise = ~coin_b_d & coin_b;
	wire service_fall= service_d & ~service;
	wire edgint_rise = ~edgint_d & edgint;

	wire any_event = coin_a_fall | coin_b_fall | coin_a_rise | coin_b_rise
	               | service_fall | edgint_rise | int_ack;

	always_ff @(posedge clk) begin
		if (reset) begin
			coin_ff       <= 2'd0;
			edgint_ff     <= 1'b0;
			service_pulse <= 1'b0;
			irq_line      <= 1'b0;
			coin_a_d      <= 1'b1;
			coin_b_d      <= 1'b1;
			service_d     <= 1'b1;
			edgint_d      <= 1'b0;
			int_enable_latch <= 8'd0;
		end else begin
			coin_a_d  <= coin_a;
			coin_b_d  <= coin_b;
			service_d <= service;
			edgint_d  <= edgint;

			if (ce_cpu && io_wr && cpu_a[7:0] == 8'hBF)
				int_enable_latch <= cpu_do;

			if (int_ack) begin
				coin_ff       <= 2'd0;
				edgint_ff     <= 1'b0;
				service_pulse <= 1'b0;
				irq_line      <= 1'b0;
			end else begin
				if (coin_a_fall) coin_ff[0] <= 1'b1;
				else if (coin_a_rise) coin_ff[0] <= 1'b0;
				if (coin_b_fall) coin_ff[1] <= 1'b1;
				else if (coin_b_rise) coin_ff[1] <= 1'b0;
				if (edgint_rise) edgint_ff <= 1'b1;

				// SERVICE has no flip-flop: it contributes to one update only
				service_pulse <= service_fall;

				if (any_event)
					irq_line <= (coin_ff != 2'd0) | edgint_ff
					          | coin_a_fall | coin_b_fall
					          | service_fall | edgint_rise;
			end
		end
	end

	assign int_n = ~irq_line;
	assign dbg_wram_wr       = sel_wram & mem_wr;
	assign dbg_wram_addr_raw = cpu_a;
	assign dbg_wram_addr_scr = wr_addr_s;
	assign dbg_wram_data     = cpu_do;
	assign dbg_io_rd   = io_rd;
	assign dbg_port    = port;
	assign dbg_irq     = irq_line;
	assign dbg_coin_ff = coin_ff;
	assign dbg_int_ack = int_ack;

	// the service switch also pulses NMI
	always_ff @(posedge clk) begin
		if (reset) nmi_n <= 1'b1;
		else       nmi_n <= ~service_fall;
	end

endmodule

`default_nettype wire
