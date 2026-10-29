
`default_nettype none

(* multstyle = "logic" *)
module fx_bank #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer AUDIO_HZ = 48_000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               tick,
    input  wire [7:0]         pa,
    input  wire signed [17:0] noise1,
    output wire signed [15:0] ch_lexpl,
    output wire signed [15:0] ch_sexpl,
    output wire signed [15:0] ch_bomb,
    output wire signed [15:0] ch_shoot,
    output wire signed [15:0] ch_missile,
    output wire signed [15:0] ch_helicopter,
    output wire signed [15:0] ch_whistle
);

    localparam [63:0] PU40 = (64'd1 << 40) / CLK_HZ;

    reg [7:0] pa_d;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pa_d <= 8'hFF;
        else        pa_d <= pa;

    wire [7:0] fall = pa_d & ~pa;

    wire gate_heli = ~pa[5];
    wire gate_whis = ~pa[6];

    wire signed [17:0] noise2;

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(503), .Q_X100(158))
        f_n2 (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise1),
              .lp(), .bp(noise2), .hp());

    wire [15:0] env_lexpl, env_sexpl, env_bomb, env_shoot, env_miss;
    wire [15:0] env_heli,  env_whis;

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(15))
        e_lexpl (.clk(clk), .rst_n(rst_n), .trig(fall[0]), .sustain(1'b0), .level(env_lexpl));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(13))
        e_sexpl (.clk(clk), .rst_n(rst_n), .trig(fall[1]), .sustain(1'b0), .level(env_sexpl));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(16))
        e_bomb  (.clk(clk), .rst_n(rst_n), .trig(fall[2]), .sustain(1'b0), .level(env_bomb));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(12))
        e_shoot (.clk(clk), .rst_n(rst_n), .trig(fall[3]), .sustain(1'b0), .level(env_shoot));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(14))
        e_miss  (.clk(clk), .rst_n(rst_n), .trig(fall[4]), .sustain(1'b0), .level(env_miss));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(15))
        e_heli  (.clk(clk), .rst_n(rst_n), .trig(fall[5]), .sustain(gate_heli), .level(env_heli));

    env_gen #(.CLK_HZ(CLK_HZ), .TICK_HZ(AUDIO_HZ), .DECAY_SHIFT(13))
        e_whis  (.clk(clk), .rst_n(rst_n), .trig(fall[6]), .sustain(gate_whis), .level(env_whis));

    wire signed [17:0] bp_lexpl, bp_sexpl, bp_miss, bp_shoot;

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(226), .Q_X100(158))
        f_lex (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise1),
               .lp(), .bp(bp_lexpl), .hp());

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(408), .Q_X100(105))
        f_sex (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise1),
               .lp(), .bp(bp_sexpl), .hp());

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(734), .Q_X100(108))
        f_mis (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise2),
               .lp(), .bp(bp_miss), .hp());

    svf #(.AUDIO_HZ(AUDIO_HZ), .F0_HZ(229), .Q_X100(158))
        f_pis (.clk(clk), .rst_n(rst_n), .tick(tick), .in(noise2),
               .lp(), .bp(bp_shoot), .hp());

    localparam [63:0] HELI_T_HI = (64'd47  * AUDIO_HZ) / 64'd10000;
    localparam [63:0] HELI_T_LO = (64'd707 * AUDIO_HZ) / 64'd10000;

    reg [15:0] heli_cnt;
    reg        heli_ph;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            heli_cnt <= 16'd0;
            heli_ph  <= 1'b0;
        end else if (tick) begin
            if (heli_ph) begin
                if (heli_cnt >= HELI_T_HI[15:0]) begin heli_cnt <= 16'd0; heli_ph <= 1'b0; end
                else heli_cnt <= heli_cnt + 16'd1;
            end else begin
                if (heli_cnt >= HELI_T_LO[15:0]) begin heli_cnt <= 16'd0; heli_ph <= 1'b1; end
                else heli_cnt <= heli_cnt + 16'd1;
            end
        end
    end

    reg [15:0] heli_gain;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) heli_gain <= 16'd0;
        else if (tick) begin
            if (heli_ph) heli_gain <= heli_gain + ((16'hFFFF - heli_gain) >> 4);
            else         heli_gain <= heli_gain - (heli_gain >> 6);
        end
    end

    localparam [31:0] INC_WHIS = ((PU40 * 64'd2112) >> 8);
    localparam [31:0] INC_WLFO = ((PU40 * 64'd33  ) >> 12);
    localparam [31:0] WHIS_DEV = INC_WHIS / 32'd12;

    reg [31:0] ph_whis, ph_wlfo;

    wire [7:0] wlfo_tri = ph_wlfo[31] ? ~ph_wlfo[30:23] : ph_wlfo[30:23];
    wire [31:0] inc_whis = INC_WHIS - (WHIS_DEV >> 1)
                         + ((WHIS_DEV * wlfo_tri) >> 8);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph_whis <= 32'd0;
            ph_wlfo <= 32'd0;
        end else begin
            ph_whis <= ph_whis + inc_whis;
            ph_wlfo <= ph_wlfo + INC_WLFO;
        end
    end

    localparam [31:0] INC_BOMB_HI = ((PU40 * 64'd1540) >> 8);
    localparam [31:0] INC_BOMB_LO = ((PU40 * 64'd190 ) >> 8);

    reg [31:0] ph_bomb, inc_bomb;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ph_bomb  <= 32'd0;
            inc_bomb <= INC_BOMB_LO;
        end else begin
            if (fall[2]) inc_bomb <= INC_BOMB_HI;
            else if (tick && inc_bomb > INC_BOMB_LO)
                inc_bomb <= inc_bomb - (inc_bomb >> 7);
            ph_bomb <= ph_bomb + inc_bomb;
        end
    end

    wire signed [17:0] sq_whis = ph_whis[31] ? 18'sd30000 : -18'sd30000;
    wire signed [17:0] sq_bomb = ph_bomb[31] ? 18'sd28000 : -18'sd28000;

    (* multstyle = "logic" *) wire signed [34:0] p_heli_ch = noise2 * $signed({1'b0, heli_gain});
    wire signed [17:0] heli_ch = p_heli_ch[33:16];

    (* multstyle = "logic" *) wire signed [34:0] p_lexpl = bp_lexpl * $signed({1'b0, env_lexpl});
    (* multstyle = "logic" *) wire signed [34:0] p_sexpl = bp_sexpl * $signed({1'b0, env_sexpl});
    (* multstyle = "logic" *) wire signed [34:0] p_miss  = bp_miss  * $signed({1'b0, env_miss});
    (* multstyle = "logic" *) wire signed [34:0] p_shoot = bp_shoot * $signed({1'b0, env_shoot});
    (* multstyle = "logic" *) wire signed [34:0] p_bomb  = sq_bomb  * $signed({1'b0, env_bomb});
    (* multstyle = "logic" *) wire signed [34:0] p_whis  = sq_whis  * $signed({1'b0, env_whis});
    (* multstyle = "logic" *) wire signed [34:0] p_heli  = heli_ch  * $signed({1'b0, env_heli});

    assign ch_lexpl      = p_lexpl[33:18];
    assign ch_sexpl      = p_sexpl[33:18];
    assign ch_missile    = p_miss[33:18];
    assign ch_shoot      = p_shoot[33:18];
    assign ch_bomb       = p_bomb[33:18];
    assign ch_whistle    = p_whis[33:18];
    assign ch_helicopter = p_heli[33:18];

endmodule

`default_nettype wire
