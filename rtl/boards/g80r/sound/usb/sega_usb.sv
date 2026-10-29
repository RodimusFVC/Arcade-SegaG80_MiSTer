//  Sega Universal Sound Board (8035 + three 8253 timers)
//  Based on MAME segausb.cpp (Aaron Giles, BSD-3-Clause)
//  This program is free software under the GNU General Public License v3.

`default_nettype none

module sega_usb #(
	parameter int CLK_HZ = 12_096_000
) (
	output chip_pool_pkg::i8035_i_t i8035_i,
	input  chip_pool_pkg::i8035_o_t i8035_o,
	output ram_pool_pkg::pram_i_t pgm_pr_i,
	input  ram_pool_pkg::pram_o_t pgm_pr_o,
	output ram_pool_pkg::pram_i_t work_pr_i,
	input  ram_pool_pkg::pram_o_t work_pr_o,
	input  wire        clk,
	input  wire        reset,

	input  wire        data_wr,
	input  wire  [7:0] din,
	output wire  [7:0] status,

	input  wire [11:0] pgm_addr,
	input  wire  [7:0] pgm_din,
	input  wire        pgm_wr,
	output logic [7:0] pgm_dout,

	output wire signed [15:0] audio,

	output wire        dbg_tick,
	output wire        dbg_noise,
	output wire  [8:0] dbg_tmr,      // {group2, group1, group0}
	output wire  [2:0] dbg_cfg,
	output wire [71:0] dbg_env
);

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

				if (gos_div == 16'd31) begin gos_div <= 16'd0; gos_flip <= 1'b1; end
				else                        gos_div <= gos_div + 16'd1;

				if (t1_div == 8'd255) begin t1_div <= 8'd0; ce_t1 <= 1'b1; end
				else                       t1_div <= t1_div + 8'd1;
			end
		end
	end

	logic [7:0] in_latch, out_latch;
	logic [7:0] t1_clock;
	localparam logic [7:0] T1_CLOCK_MASK = 8'h10;

	assign status = (out_latch & 8'h81) | (in_latch & 8'h7e);

	logic [7:0] pgm_q;

	wire pgm_wr_en = pgm_wr & in_latch[7];

	logic [7:0] work_q;
	logic [1:0] work_bank;

	logic [7:0] addr_lo;
	wire [9:0] work_addr = {work_bank, addr_lo};

	wire        psen_n, rd_n, wr_n, ale;
	wire  [7:0] cpu_do, p1_out, p2_out;
	logic [7:0] cpu_di;
	logic       ale_d;

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

	always_comb begin
		cpu_di = 8'hFF;
		if (!psen_n)    cpu_di = pgm_q;
		else if (!rd_n) cpu_di = work_q;
	end

	assign i8035_i.rst_n = ~reset & ~in_latch[7];
	assign i8035_i.ce = ce_cpu;
	assign i8035_i.int_n = 1'b1;
	assign i8035_i.ea = 1'b1;
	assign i8035_i.t0 = 1'b1;
	assign i8035_i.t1 = (t1_clock & T1_CLOCK_MASK) != 8'd0;
	assign i8035_i.db = cpu_di;
	assign i8035_i.p1 = {1'b0, in_latch[6:0]};
	assign i8035_i.p2 = 8'hFF;
	assign psen_n = i8035_o.psen_n;
	assign rd_n   = i8035_o.rd_n;
	assign wr_n   = i8035_o.wr_n;
	assign ale    = i8035_o.ale;
	assign cpu_do = i8035_o.db;
	assign p1_out = i8035_o.p1;
	assign p2_out = i8035_o.p2;

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

	assign pgm_pr_i  = '{a_addr: {3'd0, pgm_addr}, a_d: pgm_din, a_we: pgm_wr_en, b_addr: {3'd0, cpu_pc}, b_d: 8'd0, b_we: 1'b0};
	assign pgm_dout  = pgm_pr_o.a_q;
	assign pgm_q     = pgm_pr_o.b_q;
	assign work_pr_i = '{a_addr: {5'd0, work_addr}, a_d: wr_data, a_we: movx_wr & ~reset, b_addr: 15'd0, b_d: 8'd0, b_we: 1'b0};
	assign work_q    = work_pr_o.a_q;

	logic [7:0] env [0:2][0:2];
	logic [2:0] cfg;
	logic [7:0] last_p2;

	wire [1:0] grp     = addr_lo[4:3];
	wire       is_ctc  = (addr_lo[2] == 1'b0);
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
			if (data_wr) in_latch <= last_p2[6] ? din : (din & 8'h80);

			if (ce_t1 && !last_p2[7]) t1_clock <= t1_clock + 8'd1;

			if (ce_cpu) begin
				out_latch[0] <= p1_out[7];

				if (p2_out != last_p2) begin
					work_bank    <= p2_out[1:0];
					out_latch[7] <= p2_out[6];
					if (!p2_out[6]) in_latch <= 8'd0;
					if (last_p2[7] && !p2_out[7]) t1_clock <= 8'd0;
					last_p2 <= p2_out;
				end
			end

			if (movx_wr) begin
				if (in_regs && !is_ctc && (addr_lo[1:0] != 2'd3))
					env[grp][addr_lo[1:0]] <= wr_data;
				if (in_regs && !is_ctc && (addr_lo[1:0] == 2'd3))
					cfg[grp] <= wr_data[0];
			end
		end
	end

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
