
`default_nettype none

(* multstyle = "logic" *)
module melody_gen #(
    parameter integer CLK_HZ        = 50_000_000,

    parameter integer TEMPO_MILLIHZ = 39_344,

    parameter integer LS161_CLK_HZ  = 566_000,

    parameter integer DIV2_ADDR     = 1,

    parameter integer SKIP_FF       = 1,

    parameter signed [17:0] W_QB    = 18'sd14000,
    parameter signed [17:0] W_QD    = 18'sd25200,

    parameter integer HP_HZ         = 159,
    parameter integer LP_HZ         = 1592,

    parameter integer GATE_MS       = 700,
    parameter integer AUDIO_HZ      = 48_000
)(
    input  wire               clk,
    input  wire               rst_n,

    input  wire               tick,
    input  wire [7:0]         pb,

    output wire [10:0]        rom_addr,
    input  wire [7:0]         rom_q,
    output wire [4:0]         prom_addr,
    input  wire [7:0]         prom_q,

    output wire signed [15:0] audio
);

    localparam [63:0] TEMPO_DIV = ((64'd1000 * CLK_HZ) / TEMPO_MILLIHZ) - 64'd1;

    localparam [63:0] INC161 = ((64'd0 + LS161_CLK_HZ) << 32) / CLK_HZ;

    wire        pb_hold   = pb[4];
    wire        pb_auto   = pb[5];
    wire        pb_mclk   = pb[6];
    wire [3:0]  pb_page   = pb[3:0];

    wire        tempo_run = rom_q[5];
    reg [31:0]  tempo_cnt;
    reg         tempo_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tempo_cnt  <= 32'd0;
            tempo_tick <= 1'b0;
        end else if (!tempo_run) begin
            tempo_cnt  <= 32'd0;
            tempo_tick <= 1'b0;
        end else if (tempo_cnt >= TEMPO_DIV[31:0]) begin
            tempo_cnt  <= 32'd0;
            tempo_tick <= 1'b1;
        end else begin
            tempo_cnt  <= tempo_cnt + 32'd1;
            tempo_tick <= 1'b0;
        end
    end

    reg [7:0] seq_cnt;
    reg       mclk_d;
    wire      mclk_rise = pb_mclk & ~mclk_d;
    wire      seq_clk   = pb_auto ? tempo_tick : mclk_rise;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            seq_cnt <= 8'd0;
            mclk_d  <= 1'b0;
        end else begin
            mclk_d <= pb_mclk;
            if (pb_hold)         seq_cnt <= 8'd0;
            else if (seq_clk)    seq_cnt <= seq_cnt + 8'd1;
        end
    end

    assign rom_addr  = (DIV2_ADDR != 0) ? {pb_page, seq_cnt[7:1]}
                                        : {pb_page, seq_cnt[6:0]};
    assign prom_addr = rom_q[4:0];

    reg [32:0] acc161;
    wire       tick161 = acc161[32];

    reg [7:0]  q161;
    reg        carry;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc161 <= 33'd0;
            q161   <= 8'd0;
            carry  <= 1'b0;
        end else begin
            carry  <= 1'b0;
            acc161 <= {1'b0, acc161[31:0]} + INC161[32:0];

            if (pb_hold) begin
                q161 <= prom_q;
            end else if (tick161) begin
                if (q161 == 8'hFF) begin
                    q161  <= prom_q;
                    carry <= (SKIP_FF != 0) ? (prom_q != 8'hFF) : 1'b1;
                end else begin
                    q161 <= q161 + 8'd1;
                end
            end
        end
    end

    reg [2:0] q293;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          q293 <= 3'd0;
        else if (pb_hold)    q293 <= 3'd0;
        else if (carry)      q293 <= q293 + 3'd1;
    end

    wire qb = q293[0];
    wire qd = q293[2];

    wire signed [17:0] raw = (qb ? W_QB : -W_QB) + (qd ? W_QD : -W_QD);

    wire signed [17:0] shaped_lp, shaped_hp;

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(HP_HZ), .Q_X100(71))
        f_hp (.clk(clk), .rst_n(rst_n), .tick(tick), .in(raw),
              .lp(), .bp(), .hp(shaped_hp));

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(LP_HZ), .Q_X100(71))
        f_lp (.clk(clk), .rst_n(rst_n), .tick(tick), .in(shaped_hp),
              .lp(shaped_lp), .bp(), .hp());

    localparam [63:0] GATE_N = (64'd0 + GATE_MS) * AUDIO_HZ / 64'd1000;

    reg [23:0] gate_cnt;
    wire       gate_on = (gate_cnt != 24'd0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)            gate_cnt <= 24'd0;
        else if (tempo_tick)   gate_cnt <= GATE_N[23:0];
        else if (tick && gate_on) gate_cnt <= gate_cnt - 24'd1;
    end

    reg [15:0] mel_env;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) mel_env <= 16'd0;
        else if (tick) begin
            if (gate_on) mel_env <= mel_env + ((16'hFFFF - mel_env) >> 5);
            else         mel_env <= mel_env - (mel_env >> 15);
        end
    end

    (* multstyle = "logic" *) wire signed [34:0] p_mel = shaped_lp * $signed({1'b0, mel_env});
    assign audio = p_mel[33:18];

endmodule

`default_nettype wire
