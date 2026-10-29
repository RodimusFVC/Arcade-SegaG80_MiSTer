//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_a.cpp, i8243.cpp (Aaron Giles, BSD-3-Clause)

module monsterb_voice #(
    parameter int CLK_HZ = 15_468_480,
    parameter int GAIN_LOG2 = 0
) (
    output chip_pool_pkg::i8035_i_t i8035_i,
    input  chip_pool_pkg::i8035_o_t i8035_o,
    input                clk,
    input                reset,

    input         [7:0]  cmd_w,
    output               busy,

    output        [9:0]  rom11_a,
    input         [7:0]  rom11_d,
    output       [12:0]  rom12_a,
    input         [7:0]  rom12_d,

    output signed [15:0] audio
);

    localparam int CPU_HZ = 6_000_000;
    reg [23:0] acc;
    reg        ce_cpu;
    always @(posedge clk) begin
        if (reset) begin acc <= 24'd0; ce_cpu <= 1'b0; end
        else if (acc + CPU_HZ >= CLK_HZ) begin
            acc <= acc + CPU_HZ - CLK_HZ; ce_cpu <= 1'b1;
        end else begin
            acc <= acc + CPU_HZ;          ce_cpu <= 1'b0;
        end
    end

    wire [7:0] pgm_q = rom11_d, smp_q = rom12_d;

    wire        psen_n;
    wire [7:0]  cpu_do;
    wire [7:0]  cpu_p1, cpu_p2;
    wire        prog_pin;

    reg [3:0] exp_p4, exp_p5, exp_p6, exp_p7;

    wire [12:0] smp_addr = {~exp_p7[1], exp_p6, exp_p5, exp_p4};

    wire       ale;
    wire       rd_n;
    reg  [7:0] addr_lo;
    reg  [7:0] p2_lat;
    reg        ale_d;
    wire [11:0] cpu_pc = {p2_lat[3:0], addr_lo};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ale_d <= 1'b0; addr_lo <= 8'd0; p2_lat <= 8'd0;
        end else if (ce_cpu) begin
            ale_d <= ale;
            if (!ale && ale_d) begin
                addr_lo <= cpu_do;
                p2_lat  <= cpu_p2;
            end
        end
    end

    assign rom11_a = cpu_pc[9:0];
    assign rom12_a = smp_addr;

    reg [7:0] cpu_di;
    always @(*) begin
        cpu_di = 8'hFF;
        if (!psen_n)    cpu_di = pgm_q;
        else if (!rd_n) cpu_di = smp_q;
    end

    reg  [3:0] exp_op;
    reg        prog_d;
    always @(posedge clk) prog_d <= prog_pin;
    wire prog_fall = prog_d & ~prog_pin;
    wire prog_rise = ~prog_d & prog_pin;

    function [3:0] exp_apply;
        input [1:0] op;
        input [3:0] cur;
        input [3:0] dat;
        begin
            case (op)
                2'd1: exp_apply = dat;
                2'd2: exp_apply = cur | dat;
                2'd3: exp_apply = cur & dat;
                default: exp_apply = cur;
            endcase
        end
    endfunction

    wire [1:0] exp_port = exp_op[1:0];
    wire [1:0] exp_instr = exp_op[3:2];
    wire [3:0] exp_data = cpu_p2[3:0];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exp_op <= 4'd0;
            exp_p4 <= 4'd0; exp_p5 <= 4'd0; exp_p6 <= 4'd0; exp_p7 <= 4'hF;
        end else begin
            if (prog_fall) exp_op <= exp_data;
            else if (prog_rise) begin
                if (exp_port == 2'd0) exp_p4 <= exp_apply(exp_instr, exp_p4, exp_data);
                if (exp_port == 2'd1) exp_p5 <= exp_apply(exp_instr, exp_p5, exp_data);
                if (exp_port == 2'd2) exp_p6 <= exp_apply(exp_instr, exp_p6, exp_data);
                if (exp_port == 2'd3) exp_p7 <= exp_apply(exp_instr, exp_p7, exp_data);
            end
        end
    end

    wire [7:0] p2_in = {1'b1, cmd_w[2:0], 4'b0000};

    assign busy = cpu_p2[7];

    assign i8035_i  = '{rst_n: ~reset, ce: ce_cpu, int_n: cmd_w[3], ea: 1'b1, t0: 1'b1, t1: 1'b0, db: cpu_di, p1: 8'hFF,
                        p2: p2_in};
    assign psen_n   = i8035_o.psen_n;
    assign rd_n     = i8035_o.rd_n;
    assign ale      = i8035_o.ale;
    assign prog_pin = i8035_o.prog_n;
    assign cpu_do   = i8035_o.db;
    assign cpu_p1   = i8035_o.p1;
    assign cpu_p2   = i8035_o.p2;

    wire signed [8:0]  centred = $signed({1'b0, cpu_p1}) - 9'sd128;
    wire signed [15:0] dac     = {centred, 7'd0};

    assign audio = GAIN_LOG2 == 0 ? dac : (dac <<< GAIN_LOG2);

endmodule
