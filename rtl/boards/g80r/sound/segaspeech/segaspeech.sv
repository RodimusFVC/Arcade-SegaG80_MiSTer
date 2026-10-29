//  Based on MAME segaspeech.cpp (Aaron Giles, BSD-3-Clause)

module segaspeech (
    output chip_pool_pkg::mcs48_i_t  mcs48_0_i,
    input  chip_pool_pkg::mcs48_o_t  mcs48_0_o,
    output chip_pool_pkg::sp0250_i_t sp0250_0_i,
    input  chip_pool_pkg::sp0250_o_t sp0250_0_o,
    input                clk,
    input                reset_n,
    input        [7:0]   data_w,
    input                data_we,
    input        [7:0]   ctrl_w,
    input                ctrl_we,

    output       [10:0]  rom_8035_addr,
    input        [7:0]   rom_8035_data,

    output       [13:0]  rom_speech_addr,
    input        [7:0]   rom_speech_data,

    output signed [15:0] audio_out,
    output               audio_valid
);

    reg [3:0] ce_div;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) ce_div <= 4'd0;
        else          ce_div <= (ce_div == 4'd9) ? 4'd0 : ce_div + 4'd1;
    end
    wire ce_3_12m     = (ce_div == 4'd0) || (ce_div == 4'd5);
    wire ce_rom_1_56m = (ce_div == 4'd0);

    reg [7:0] latch;
    reg       t0;
    reg       speech_gate;

    wire [7:0] p1_o;

    reg p1_7_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) p1_7_prev <= 1'b1;
        else          p1_7_prev <= p1_o[7];
    end
    wire p1_7_falling = p1_7_prev & ~p1_o[7];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            latch       <= 8'h00;
            t0          <= 1'b0;
            speech_gate <= 1'b0;
        end else begin
            if (data_we) begin
                if (!latch[7] && data_w[7])
                    t0 <= 1'b1;
                latch <= data_w;
            end
            if (p1_7_falling)
                t0 <= 1'b0;
            if (ctrl_we)
                speech_gate <= ctrl_w[3];
        end
    end

    wire int_n = latch[7];

    wire        ale_o;
    wire        rd_n_o;
    wire        wr_n_o;
    wire [7:0]  db_o;
    wire        db_dir_o;
    wire [7:0]  p2_o;

    reg [7:0] bus_addr_latch;
    reg       ale_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_addr_latch <= 8'h00;
            ale_prev       <= 1'b0;
        end else begin
            ale_prev <= ale_o;
            if (ale_prev && !ale_o)
                bus_addr_latch <= db_o;
        end
    end

    assign rom_speech_addr = {p2_o[5:0], bus_addr_latch};

    wire [7:0] db_i = rom_speech_data;

    reg wr_n_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) wr_n_prev <= 1'b1;
        else          wr_n_prev <= wr_n_o;
    end
    wire sp_wr = ~wr_n_prev & wr_n_o;

    wire               sp_drq;
    wire signed [13:0] sp_audio;
    wire               sp_audio_valid;

    assign sp0250_0_i.reset_n = reset_n;
    assign sp0250_0_i.ce_3_12m = ce_3_12m;
    assign sp0250_0_i.ce_rom_1_56m = ce_rom_1_56m;
    assign sp0250_0_i.data_in = db_o;
    assign sp0250_0_i.wr = sp_wr;
    assign sp_drq         = sp0250_0_o.drq;
    assign sp_audio       = sp0250_0_o.audio;
    assign sp_audio_valid = sp0250_0_o.audio_valid;

    wire [11:0] t48_pmem_addr;
    assign rom_8035_addr = t48_pmem_addr[10:0];

    assign mcs48_0_i.reset_n = reset_n;
    assign mcs48_0_i.xtal_en = ce_3_12m;
    assign mcs48_0_i.int_n = int_n;
    assign mcs48_0_i.t0 = t0;
    assign mcs48_0_i.t1 = sp_drq;
    assign mcs48_0_i.p1_in = {1'b1, latch[6:0]};
    assign mcs48_0_i.p2_in = 8'hFF;
    assign mcs48_0_i.db = db_i;
    assign mcs48_0_i.pmem_d = rom_8035_data;
    assign rd_n_o        = mcs48_0_o.rd_n;
    assign wr_n_o        = mcs48_0_o.wr_n;
    assign ale_o         = mcs48_0_o.ale;
    assign db_o          = mcs48_0_o.db;
    assign db_dir_o      = mcs48_0_o.db_dir;
    assign p2_o          = mcs48_0_o.p2;
    assign p1_o          = mcs48_0_o.p1;
    assign t48_pmem_addr = mcs48_0_o.pmem_a;

    wire signed [15:0] sp_audio_16 = {sp_audio[13], sp_audio, 1'b0};

    assign audio_out   = speech_gate ? sp_audio_16 : 16'sd0;
    assign audio_valid = sp_audio_valid;

    wire _unused = |{db_dir_o};

endmodule
