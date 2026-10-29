//  Based on MAME segag80r.cpp (Aaron Giles, BSD-3-Clause)

module sindbadm_sound #(
    parameter int unsigned CLK_HZ    = 15_468_480,
    parameter int unsigned Z80_HZ    =  4_000_000,
    parameter int unsigned SN0_HZ    =  4_000_000,
    parameter int unsigned SN1_HZ    =  2_000_000,
    parameter int          GAIN_LOG2 =  4
)(
    output chip_pool_pkg::z80_i_t           z80_1_i,
    input  chip_pool_pkg::z80_o_t           z80_1_o,
    output chip_pool_pkg::sn76489_i_t [1:0] sn76489_i,
    input  chip_pool_pkg::sn76489_o_t [1:0] sn76489_o,
    input                       clk,
    input                       reset,

    input                       latch_wr,
    input                [7:0]  latch_din,
    input                       pc_wr,
    input                [7:0]  pc_din,

    output              [12:0]  rom8_a,
    input                [7:0]  rom8_d,
    output ram_pool_pkg::pram_i_t     ram_pr_i,
    input  ram_pool_pkg::pram_o_t     ram_pr_o,

    output signed       [15:0]  audio
);

    localparam [32:0] INC_Z80 = 33'((longint'(Z80_HZ) <<< 32) / longint'(CLK_HZ));
    localparam [32:0] INC_SN0 = 33'((longint'(SN0_HZ) <<< 32) / longint'(CLK_HZ));
    localparam [32:0] INC_SN1 = 33'((longint'(SN1_HZ) <<< 32) / longint'(CLK_HZ));

    reg [32:0] acc_z80, acc_sn0, acc_sn1;
    always @(posedge clk) begin
        acc_z80 <= {1'b0, acc_z80[31:0]} + INC_Z80;
        acc_sn0 <= {1'b0, acc_sn0[31:0]} + INC_SN0;
        acc_sn1 <= {1'b0, acc_sn1[31:0]} + INC_SN1;
    end
    wire ce_z80 = acc_z80[32];
    wire ce_sn0 = acc_sn0[32];
    wire ce_sn1 = acc_sn1[32];

    reg [7:0] snd_latch;
    always @(posedge clk) if (latch_wr) snd_latch <= latch_din;

    wire latch_rd;
    reg  nmi_req;
    always @(posedge clk or posedge reset) begin
        if (reset)                     nmi_req <= 1'b0;
        else if (latch_wr)             nmi_req <= 1'b1;
        else if (pc_wr)                nmi_req <= ~pc_din[7];
        else if (latch_rd & ce_z80)    nmi_req <= 1'b0;
    end

    localparam int unsigned IRQ_DIV = CLK_HZ / 240;

    reg [$clog2(IRQ_DIV)-1:0] irq_cnt;
    reg                       irq_pend;
    wire                      intack;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            irq_cnt  <= '0;
            irq_pend <= 1'b0;
        end else begin
            if (irq_cnt == IRQ_DIV[$clog2(IRQ_DIV)-1:0] - 1'b1) begin
                irq_cnt  <= '0;
                irq_pend <= 1'b1;
            end else begin
                irq_cnt <= irq_cnt + 1'b1;
                if (intack) irq_pend <= 1'b0;
            end
        end
    end

    wire        mreq_n, iorq_n, rd_n, wr_n, m1_n;
    wire [15:0] addr;
    wire  [7:0] dout;
    reg   [7:0] din;

    assign intack = ~m1_n & ~iorq_n;

    assign z80_1_i = '{ce: ce_z80, int_n: ~irq_pend, nmi_n: ~nmi_req, di: din};
    assign m1_n    = z80_1_o.m1_n;
    assign mreq_n  = z80_1_o.mreq_n;
    assign iorq_n  = z80_1_o.iorq_n;
    assign rd_n    = z80_1_o.rd_n;
    assign wr_n    = z80_1_o.wr_n;
    assign addr    = z80_1_o.a;
    assign dout    = z80_1_o.dout;

    wire mem     = ~mreq_n;
    wire mem_rd  = mem & ~rd_n;
    wire mem_wr  = mem & ~wr_n;

    wire rom_sel = mem & (addr[15:13] == 3'b000);
    wire ram_sel = mem & (addr[15:13] == 3'b100);
    wire sn0_sel = mem & (addr[15:13] == 3'b101);
    wire sn1_sel = mem & (addr[15:13] == 3'b110);
    wire lat_sel = mem & (addr[15:13] == 3'b111);

    assign latch_rd = lat_sel & mem_rd;

    assign rom8_a = addr[12:0];
    wire [7:0] rom_q = rom8_d;

    assign ram_pr_i = '{a_addr: {4'd0, addr[10:0]}, a_d: dout, a_we: ram_sel & mem_wr & ce_z80,
                        b_addr: 15'd0, b_d: 8'd0, b_we: 1'b0};
    wire [7:0] ram_q = ram_pr_o.a_q;

    always @(*) begin
        case (1'b1)
            rom_sel: din = rom_q;
            ram_sel: din = ram_q;
            lat_sel: din = snd_latch;
            default: din = 8'hFF;
        endcase
    end

    wire [7:0] sn_din = {dout[0], dout[1], dout[2], dout[3],
                         dout[4], dout[5], dout[6], dout[7]};

    reg  [7:0] sn0_data, sn1_data;
    reg        sn0_wr, sn1_wr;
    always @(posedge clk) begin
        sn0_wr <= sn0_sel & mem_wr & ce_z80;
        sn1_wr <= sn1_sel & mem_wr & ce_z80;
        if (sn0_sel & mem_wr & ce_z80) sn0_data <= sn_din;
        if (sn1_sel & mem_wr & ce_z80) sn1_data <= sn_din;
    end

    wire signed [10:0] sn0_snd, sn1_snd;

    assign sn76489_i[0].rst = reset;
    assign sn76489_i[0].ce = ce_sn0;
    assign sn76489_i[0].wr_n = ~sn0_wr;
    assign sn76489_i[0].cs_n = 1'b0;
    assign sn76489_i[0].din = sn0_data;
    assign sn0_snd      = sn76489_o[0].sound;

    assign sn76489_i[1].rst = reset;
    assign sn76489_i[1].ce = ce_sn1;
    assign sn76489_i[1].wr_n = ~sn1_wr;
    assign sn76489_i[1].cs_n = 1'b0;
    assign sn76489_i[1].din = sn1_data;
    assign sn1_snd      = sn76489_o[1].sound;

    wire signed [11:0] sn_sum = $signed({sn0_snd[10], sn0_snd})
                              + $signed({sn1_snd[10], sn1_snd});

    wire signed [15:0] sn_wide = {{4{sn_sum[11]}}, sn_sum};
    assign audio = sn_wide <<< GAIN_LOG2;

endmodule
