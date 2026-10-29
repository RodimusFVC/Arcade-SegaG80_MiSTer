//  Based on MAME nl_astrob.cpp (Aaron Giles, CC0-1.0)

module astrob_audio (
    input                     clk_sys,
    input                     reset,

    input                     audio_we,
    input                     audio_addr,     // 0 = $3E, 1 = $3F
    input               [7:0] audio_din,
    input                     ce_cpu,

    output reg signed  [15:0] audio_out
);

    reg [7:0] latch_3e, latch_3f;

    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            latch_3e <= 8'hFF;
            latch_3f <= 8'hFF;
        end else if (audio_we & ce_cpu) begin
            if (audio_addr == 1'b0) latch_3e <= audio_din;
            else                    latch_3f <= audio_din;
        end
    end

    wire mute = latch_3e[5];

    wire inv1_gate = ~latch_3e[0];
    wire inv2_gate = ~latch_3e[1];
    wire inv3_gate = ~latch_3e[2];
    wire inv4_gate = ~latch_3e[3];

    wire warp_active = ~latch_3e[7];

    localparam signed [15:0] VOICE_FS = 16'sd6000;

    wire attack_run  = latch_3f[4];
    wire rate_reset  = ~latch_3f[5];

    localparam V_ASTABLE_FREERUN = 1'b0;

    reg  attack_bit_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) attack_bit_d <= 1'b1;
        else       attack_bit_d <= latch_3f[4];
    end
    wire attack_pulse = attack_bit_d & ~latch_3f[4];

    localparam [19:0] VSTEP_HALF = 20'd540856;
    reg [19:0] vclk_cnt;
    reg        vclk_out, vclk_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            vclk_cnt <= VSTEP_HALF; vclk_out <= 1'b0;
        end else if (!attack_run) begin
            vclk_cnt <= VSTEP_HALF;
        end else if (vclk_cnt == 20'd0) begin
            vclk_cnt <= VSTEP_HALF; vclk_out <= ~vclk_out;
        end else begin
            vclk_cnt <= vclk_cnt - 20'd1;
        end
    end
    always @(posedge clk_sys) vclk_d <= vclk_out;
    wire vclk_rise = vclk_out & ~vclk_d;

    wire v_clk = attack_pulse | (V_ASTABLE_FREERUN & vclk_rise);

    reg [3:0] vstep;
    always @(posedge clk_sys or posedge reset) begin
        if (reset)              vstep <= 4'd0;
        else if (rate_reset)    vstep <= 4'd0;
        else if (v_clk)         vstep <= (vstep == 4'd9) ? 4'd0 : vstep + 4'd1;
    end

    reg [17:0] rom_i1n, rom_i1w;
    reg [15:0] rom_i2;
    reg [16:0] rom_i3n, rom_i3w;
    always @* begin
        case (vstep)
        4'd0: begin rom_i1n=18'd148307; rom_i1w=18'd171299; rom_i2=16'd2481; rom_i3n=17'd71284; rom_i3w=17'd77265; end
        4'd1: begin rom_i1n=18'd145754; rom_i1w=18'd168350; rom_i2=16'd2458; rom_i3n=17'd70596; rom_i3w=17'd76519; end
        4'd2: begin rom_i1n=18'd143206; rom_i1w=18'd165407; rom_i2=16'd2434; rom_i3n=17'd69909; rom_i3w=17'd75774; end
        4'd3: begin rom_i1n=18'd142104; rom_i1w=18'd164134; rom_i2=16'd2424; rom_i3n=17'd69612; rom_i3w=17'd75452; end
        4'd4: begin rom_i1n=18'd139952; rom_i1w=18'd161649; rom_i2=16'd2404; rom_i3n=17'd69031; rom_i3w=17'd74823; end
        4'd5: begin rom_i1n=18'd137260; rom_i1w=18'd158540; rom_i2=16'd2379; rom_i3n=17'd68306; rom_i3w=17'd74037; end
        4'd6: begin rom_i1n=18'd134450; rom_i1w=18'd155294; rom_i2=16'd2354; rom_i3n=17'd67548; rom_i3w=17'd73216; end
        4'd7: begin rom_i1n=18'd130506; rom_i1w=18'd150739; rom_i2=16'd2317; rom_i3n=17'd66485; rom_i3w=17'd72063; end
        4'd8: begin rom_i1n=18'd127870; rom_i1w=18'd147694; rom_i2=16'd2293; rom_i3n=17'd65774; rom_i3w=17'd71293; end
        default: begin rom_i1n=18'd125757; rom_i1w=18'd145253; rom_i2=16'd2274; rom_i3n=17'd65204; rom_i3w=17'd70675; end
        endcase
    end

    localparam [17:0] INV1_PER_NORM     = 18'd148307;
    localparam [17:0] INV1_PER_WARP     = 18'd171299;
    localparam [15:0] INV1_ENVSTEP_NORM = 16'd23695;
    localparam [15:0] INV1_ENVSTEP_WARP = 16'd33018;
    localparam [17:0] INV1_W_MIN        = 18'd7415;
    localparam [17:0] INV1_W_SPAN       = 18'd59323;

    wire [17:0] inv1_period  = warp_active ? rom_i1w : rom_i1n;
    wire [15:0] inv1_envstep = warp_active ? INV1_ENVSTEP_WARP : INV1_ENVSTEP_NORM;

    reg [15:0] inv1_env_pre;
    reg  [7:0] inv1_env;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv1_env <= 8'd0;  inv1_env_pre <= 16'd0;
        end else if (inv1_env_pre >= inv1_envstep) begin
            inv1_env <= inv1_env + 8'd1;
            inv1_env_pre <= 16'd0;
        end else begin
            inv1_env_pre <= inv1_env_pre + 16'd1;
        end
    end

    wire [25:0] inv1_w_prod = INV1_W_SPAN * inv1_env;
    wire [17:0] inv1_width  = INV1_W_MIN + inv1_w_prod[25:8];

    reg [17:0] inv1_per_cnt, inv1_wid_cnt;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv1_per_cnt <= 18'd0;
            inv1_wid_cnt <= 18'd0;
        end else if (!inv1_gate) begin
            inv1_per_cnt <= 18'd0;
            inv1_wid_cnt <= 18'd0;
        end else if (inv1_per_cnt == 18'd0) begin
            inv1_per_cnt <= inv1_period;
            inv1_wid_cnt <= inv1_width;
        end else begin
            inv1_per_cnt <= inv1_per_cnt - 18'd1;
            if (inv1_wid_cnt != 18'd0) inv1_wid_cnt <= inv1_wid_cnt - 18'd1;
        end
    end

    localparam signed [15:0] INV1_POS = 16'sd9000;
    localparam signed [15:0] INV1_NEG = 16'sd3000;
    wire signed [15:0] inv1_out =
        !inv1_gate              ? 16'sd0    :
        (inv1_wid_cnt != 18'd0) ?  INV1_POS : -INV1_NEG;

    localparam [15:0] INV2_HALF_PERIOD = 16'd2481;
    localparam [19:0] INV2_GATE_HALF   = 20'd505671;

    reg [15:0] inv2_osc_cnt;
    reg        inv2_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv2_osc_cnt <= INV2_HALF_PERIOD;
            inv2_osc_out <= 1'b0;
        end else if (!inv2_gate) begin
            inv2_osc_cnt <= INV2_HALF_PERIOD;
            inv2_osc_out <= 1'b0;
        end else if (inv2_osc_cnt == 16'd0) begin
            inv2_osc_cnt <= rom_i2;
            inv2_osc_out <= ~inv2_osc_out;
        end else begin
            inv2_osc_cnt <= inv2_osc_cnt - 16'd1;
        end
    end

    reg inv2_osc_out_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) inv2_osc_out_d <= 1'b0;
        else       inv2_osc_out_d <= inv2_osc_out;
    end
    wire inv2_osc_rise = inv2_osc_out & ~inv2_osc_out_d;

    reg [19:0] inv2_g_cnt;
    reg        inv2_hold;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv2_g_cnt <= INV2_GATE_HALF;
            inv2_hold  <= 1'b0;
        end else if (inv2_g_cnt == 20'd0) begin
            inv2_g_cnt <= INV2_GATE_HALF;
            inv2_hold  <= ~inv2_hold;
        end else begin
            inv2_g_cnt <= inv2_g_cnt - 20'd1;
        end
    end

    reg [6:0] inv2_div;
    always @(posedge clk_sys or posedge reset) begin
        if (reset)                          inv2_div <= 7'd0;
        else if (!inv2_gate || inv2_hold)   inv2_div <= 7'd0;
        else if (inv2_osc_rise)             inv2_div <= inv2_div + 7'd1;
    end

    localparam signed [15:0] INV2_W_Q1 = 16'sd399;
    localparam signed [15:0] INV2_W_Q2 = 16'sd839;
    localparam signed [15:0] INV2_W_Q3 = 16'sd1488;
    localparam signed [15:0] INV2_W_Q4 = 16'sd3274;

    wire signed [15:0] inv2_tap_sum =
        (inv2_div[0] ?  INV2_W_Q1 : -INV2_W_Q1) +
        (inv2_div[1] ?  INV2_W_Q2 : -INV2_W_Q2) +
        (inv2_div[2] ?  INV2_W_Q3 : -INV2_W_Q3) +
        (inv2_div[3] ?  INV2_W_Q4 : -INV2_W_Q4);

    wire signed [15:0] inv2_out = inv2_gate ? inv2_tap_sum : 16'sd0;

    localparam [20:0] INV3_TRI_HALF_N = 21'd888993;
    localparam [20:0] INV3_TRI_HALF_W = 21'd1531533;
    localparam [16:0] INV3_PER_CTR_N  = 17'd71284;
    localparam [16:0] INV3_PER_CTR_W  = 17'd77265;
    localparam [16:0] INV3_PER_DEV    = 17'd5700;

    wire [20:0] inv3_tri_half = warp_active ? INV3_TRI_HALF_W : INV3_TRI_HALF_N;
    wire [20:0] inv3_lfo_step = inv3_tri_half >> 8;

    reg [20:0] inv3_lfo_pre;
    reg  [7:0] inv3_lfo;
    reg        inv3_lfo_dir;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv3_lfo <= 8'd128;  inv3_lfo_dir <= 1'b0;  inv3_lfo_pre <= 21'd0;
        end else if (inv3_lfo_pre >= inv3_lfo_step) begin
            inv3_lfo_pre <= 21'd0;
            if (inv3_lfo_dir) begin
                if (inv3_lfo == 8'd0)   inv3_lfo_dir <= 1'b0;
                else                    inv3_lfo <= inv3_lfo - 8'd1;
            end else begin
                if (inv3_lfo == 8'd255) inv3_lfo_dir <= 1'b1;
                else                    inv3_lfo <= inv3_lfo + 8'd1;
            end
        end else begin
            inv3_lfo_pre <= inv3_lfo_pre + 21'd1;
        end
    end

    wire [16:0] inv3_per_ctr = warp_active ? rom_i3w : rom_i3n;
    wire signed [17:0] inv3_lfo_c = $signed({10'd0, inv3_lfo}) - 18'sd128;
    wire signed [35:0] inv3_dev_p = $signed({19'd0, INV3_PER_DEV}) * inv3_lfo_c;
    wire signed [17:0] inv3_dev   = inv3_dev_p[24:7];
    wire [16:0] inv3_half = inv3_per_ctr + inv3_dev[16:0];

    reg [16:0] inv3_osc_cnt;
    reg        inv3_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv3_osc_cnt <= 17'd0;
            inv3_osc_out <= 1'b0;
        end else if (!inv3_gate) begin
            inv3_osc_cnt <= 17'd0;
            inv3_osc_out <= 1'b0;
        end else if (inv3_osc_cnt == 17'd0) begin
            inv3_osc_cnt <= inv3_half;
            inv3_osc_out <= ~inv3_osc_out;
        end else begin
            inv3_osc_cnt <= inv3_osc_cnt - 17'd1;
        end
    end

    wire signed [15:0] inv3_out = inv3_gate ? (inv3_osc_out ? VOICE_FS : -VOICE_FS) : 16'sd0;

    localparam [17:0] INV4_STEP_HALF = 18'd112580;

    reg [17:0] inv4_stp_cnt;
    reg        inv4_stp_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv4_stp_cnt <= INV4_STEP_HALF;
            inv4_stp_out <= 1'b0;
        end else if (inv4_stp_cnt == 18'd0) begin
            inv4_stp_cnt <= INV4_STEP_HALF;
            inv4_stp_out <= ~inv4_stp_out;
        end else begin
            inv4_stp_cnt <= inv4_stp_cnt - 18'd1;
        end
    end

    reg inv4_stp_d;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) inv4_stp_d <= 1'b0;
        else       inv4_stp_d <= inv4_stp_out;
    end
    wire inv4_stp_rise = inv4_stp_out & ~inv4_stp_d;

    reg [3:0] inv4_ring;
    always @(posedge clk_sys or posedge reset) begin
        if (reset)              inv4_ring <= 4'd0;
        else if (inv4_stp_rise) inv4_ring <= inv4_ring + 4'd1;
    end
    wire [3:0] inv4_code = inv4_ring;

    reg [271:0] i4row;
    always @* begin
        case (vstep)
        4'd0: i4row = {17'd12982, 17'd10119, 17'd11483, 17'd9221, 17'd12086, 17'd9591, 17'd10795, 17'd8784, 17'd12537, 17'd9861, 17'd11144, 17'd9008, 17'd11707, 17'd9360, 17'd10498, 17'd8591};
        4'd1: i4row = {17'd12800, 17'd10014, 17'd11345, 17'd9135, 17'd11931, 17'd9497, 17'd10674, 17'd8706, 17'd12369, 17'd9761, 17'd11015, 17'd8925, 17'd11563, 17'd9271, 17'd10385, 17'd8517};
        4'd2: i4row = {17'd12620, 17'd9909, 17'd11208, 17'd9048, 17'd11778, 17'd9403, 17'd10554, 17'd8628, 17'd12203, 17'd9662, 17'd10886, 17'd8843, 17'd11420, 17'd9181, 17'd10271, 17'd8442};
        4'd3: i4row = {17'd12543, 17'd9864, 17'd11149, 17'd9011, 17'd11712, 17'd9363, 17'd10502, 17'd8594, 17'd12132, 17'd9619, 17'd10831, 17'd8807, 17'd11358, 17'd9143, 17'd10223, 17'd8409};
        4'd4: i4row = {17'd12394, 17'd9776, 17'd11034, 17'd8938, 17'd11584, 17'd9284, 17'd10402, 17'd8528, 17'd11994, 17'd9535, 17'd10723, 17'd8738, 17'd11239, 17'd9068, 17'd10127, 17'd8346};
        4'd5: i4row = {17'd12209, 17'd9665, 17'd10891, 17'd8846, 17'd11425, 17'd9185, 17'd10276, 17'd8445, 17'd11822, 17'd9430, 17'd10589, 17'd8650, 17'd11090, 17'd8973, 17'd10008, 17'd8266};
        4'd6: i4row = {17'd12019, 17'd9550, 17'd10743, 17'd8751, 17'd11261, 17'd9081, 17'd10145, 17'd8358, 17'd11644, 17'd9321, 17'd10449, 17'd8559, 17'd10936, 17'd8875, 17'd9885, 17'd8183};
        4'd7: i4row = {17'd11755, 17'd9389, 17'd10536, 17'd8616, 17'd11032, 17'd8936, 17'd9962, 17'd8235, 17'd11398, 17'd9168, 17'd10254, 17'd8431, 17'd10721, 17'd8736, 17'd9712, 17'd8066};
        4'd8: i4row = {17'd11581, 17'd9282, 17'd10399, 17'd8526, 17'd10880, 17'd8839, 17'd9840, 17'd8153, 17'd11236, 17'd9066, 17'd10125, 17'd8344, 17'd10579, 17'd8644, 17'd9596, 17'd7987};
        default: i4row = {17'd11443, 17'd9196, 17'd10290, 17'd8454, 17'd10760, 17'd8762, 17'd9743, 17'd8087, 17'd11107, 17'd8984, 17'd10022, 17'd8275, 17'd10465, 17'd8570, 17'd9504, 17'd7924};
        endcase
    end
    wire [16:0] inv4_half = i4row[inv4_code*17 +: 17];

    reg [16:0] inv4_osc_cnt;
    reg        inv4_osc_out;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            inv4_osc_cnt <= 17'd0;
            inv4_osc_out <= 1'b0;
        end else if (!inv4_gate) begin
            inv4_osc_cnt <= 17'd0;
            inv4_osc_out <= 1'b0;
        end else if (inv4_osc_cnt == 17'd0) begin
            inv4_osc_cnt <= inv4_half;
            inv4_osc_out <= ~inv4_osc_out;
        end else begin
            inv4_osc_cnt <= inv4_osc_cnt - 17'd1;
        end
    end

    wire signed [15:0] inv4_out = inv4_gate ? (inv4_osc_out ? VOICE_FS : -VOICE_FS) : 16'sd0;

    reg [7:0] tick_cnt;
    reg       tick;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin tick_cnt <= 8'd0; tick <= 1'b0; end
        else begin tick_cnt <= tick_cnt + 8'd1; tick <= (tick_cnt == 8'd0); end
    end

    reg [16:0] lfsr;
    wire lfsr_zero = (lfsr == 17'd0);
    always @(posedge clk_sys or posedge reset) begin
        if (reset) lfsr <= 17'h1;
        else if (tick) lfsr <= {lfsr[15:0], (lfsr[16] ^ lfsr[13]) | lfsr_zero};
    end
    wire noise_bit = lfsr[16];

    wire       sexpl_bit = latch_3f[2];
    wire       lexpl_bit = latch_3f[3];
    reg        sexpl_d, lexpl_d;
    always @(posedge clk_sys) begin sexpl_d <= sexpl_bit; lexpl_d <= lexpl_bit; end
    wire sexpl_trig = sexpl_d & ~sexpl_bit;
    wire lexpl_trig = lexpl_d & ~lexpl_bit;

    localparam [13:0] SEXPL_TICKS = 14'd2097;
    localparam [13:0] LEXPL_TICKS = 14'd9184;
    reg [13:0] sp_cnt, lp_cnt;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin sp_cnt <= 14'd0; lp_cnt <= 14'd0; end
        else begin
            if (sexpl_trig)            sp_cnt <= SEXPL_TICKS;
            else if (tick && sp_cnt!=0) sp_cnt <= sp_cnt - 14'd1;
            if (lexpl_trig)            lp_cnt <= LEXPL_TICKS;
            else if (tick && lp_cnt!=0) lp_cnt <= lp_cnt - 14'd1;
        end
    end

    localparam [16:0] ENV_MAX = 17'd61440;
    reg [16:0] expl_env;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) expl_env <= 17'd0;
        else if (tick) begin
            if (sp_cnt != 0)        expl_env <= expl_env + ((ENV_MAX - expl_env) >> 10);
            else if (lp_cnt != 0)   expl_env <= expl_env + ((ENV_MAX - expl_env) >> 11);
            else if (expl_env != 0) expl_env <= expl_env - (expl_env >> 13) - 17'd1;
        end
    end

    localparam signed [15:0] EXPL_F    = 16'sd447;
    localparam signed [15:0] EXPL_DAMP = 16'sd16943;
    reg  signed [23:0] expl_lp, expl_bp;
    wire signed [17:0] expl_x   = noise_bit ? $signed({1'b0, expl_env}) : -$signed({1'b0, expl_env});
    wire signed [39:0] expl_bpD = expl_bp * EXPL_DAMP;
    wire signed [23:0] expl_hp  = {{6{expl_x[17]}}, expl_x} - expl_lp - expl_bpD[37:14];
    wire signed [39:0] expl_bpF = expl_bp * EXPL_F;
    wire signed [39:0] expl_hpF = expl_hp * EXPL_F;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin expl_lp <= 24'sd0; expl_bp <= 24'sd0; end
        else if (tick) begin
            if (expl_env == 17'd0) begin expl_lp <= 24'sd0; expl_bp <= 24'sd0; end
            else begin
                expl_lp <= expl_lp + expl_bpF[39:16];
                expl_bp <= expl_bp + expl_hpF[39:16];
            end
        end
    end
    localparam EXPL_GAIN_LOG2 = 2;
    wire signed [23:0] expl_amp = expl_lp <<< EXPL_GAIN_LOG2;
    wire signed [15:0] expl_out =
        (expl_amp >  24'sd6000) ?  16'sd6000 :
        (expl_amp < -24'sd6000) ? -16'sd6000 : expl_amp[15:0];

    wire astro_gate = ~latch_3e[4];
    reg [16:0] astro_env;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) astro_env <= 17'd0;
        else if (tick) begin
            if (astro_gate) astro_env <= astro_env + ((ENV_MAX - astro_env) >> 6);
            else if (astro_env != 0) astro_env <= astro_env - (astro_env >> 6) - 17'd1;
        end
    end

    localparam signed [15:0] ASTRO_F    = 16'sd701;
    localparam signed [15:0] ASTRO_DAMP = 16'sd15312;
    localparam signed [15:0] ASTRO_P482 = 16'sd1602;
    reg  signed [23:0] astro_lp, astro_bp, astro_p1;
    wire signed [17:0] astro_x   = noise_bit ? $signed({1'b0, astro_env}) : -$signed({1'b0, astro_env});
    wire signed [39:0] astro_bpD = astro_bp * ASTRO_DAMP;
    wire signed [23:0] astro_hp  = {{6{astro_x[17]}}, astro_x} - astro_lp - astro_bpD[37:14];
    wire signed [39:0] astro_bpF = astro_bp * ASTRO_F;
    wire signed [39:0] astro_hpF = astro_hp * ASTRO_F;
    wire signed [24:0] astro_pd  = astro_lp - astro_p1;
    wire signed [40:0] astro_pdP = astro_pd * ASTRO_P482;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin astro_lp <= 24'sd0; astro_bp <= 24'sd0; astro_p1 <= 24'sd0; end
        else if (tick) begin
            if (astro_env == 17'd0) begin
                astro_lp <= 24'sd0; astro_bp <= 24'sd0; astro_p1 <= 24'sd0;
            end else begin
                astro_lp <= astro_lp + astro_bpF[39:16];
                astro_bp <= astro_bp + astro_hpF[39:16];
                astro_p1 <= astro_p1 + astro_pdP[38:15];
            end
        end
    end
    localparam ASTRO_GAIN_LOG2 = 2;
    wire signed [23:0] astro_amp = astro_p1 <<< ASTRO_GAIN_LOG2;
    wire signed [15:0] astro_out =
        (astro_amp >  24'sd6000) ?  16'sd6000 :
        (astro_amp < -24'sd6000) ? -16'sd6000 : astro_amp[15:0];

    localparam [13:0] LASER_TICKS = 14'd9184;
    localparam [15:0] VC_RESET    = 16'd2458;
    localparam [15:0] VC_TARGET   = 16'd49152;

    localparam signed [15:0] LW_Q1 = 16'sd258;
    localparam signed [15:0] LW_Q2 = 16'sd543;
    localparam signed [15:0] LW_Q3 = 16'sd962;
    localparam signed [15:0] LW_Q4 = 16'sd2119;
    localparam signed [15:0] LW_Q6 = 16'sd2118;

    localparam [1343:0] L1ROM = {21'd740, 21'd757, 21'd757, 21'd757, 21'd757, 21'd757, 21'd757, 21'd757,
              21'd631, 21'd643, 21'd655, 21'd667, 21'd680, 21'd694, 21'd708, 21'd723,
              21'd545, 21'd555, 21'd566, 21'd577, 21'd587, 21'd598, 21'd609, 21'd620,
              21'd471, 21'd479, 21'd487, 21'd496, 21'd506, 21'd515, 21'd525, 21'd535,
              21'd418, 21'd423, 21'd429, 21'd435, 21'd441, 21'd448, 21'd455, 21'd463,
              21'd363, 21'd373, 21'd381, 21'd388, 21'd395, 21'd401, 21'd407, 21'd412,
              21'd198, 21'd232, 21'd261, 21'd285, 21'd306, 21'd324, 21'd339, 21'd352,
              21'd15, 21'd15, 21'd15, 21'd15, 21'd15, 21'd63, 21'd114, 21'd159};
    localparam [1343:0] L2ROM = {21'd346, 21'd353, 21'd353, 21'd353, 21'd353, 21'd353, 21'd353, 21'd353,
              21'd297, 21'd302, 21'd308, 21'd313, 21'd319, 21'd325, 21'd332, 21'd339,
              21'd256, 21'd261, 21'd266, 21'd271, 21'd276, 21'd281, 21'd286, 21'd292,
              21'd221, 21'd225, 21'd229, 21'd233, 21'd237, 21'd242, 21'd246, 21'd251,
              21'd196, 21'd198, 21'd201, 21'd204, 21'd207, 21'd210, 21'd213, 21'd217,
              21'd170, 21'd174, 21'd178, 21'd182, 21'd185, 21'd188, 21'd190, 21'd193,
              21'd92, 21'd107, 21'd121, 21'd133, 21'd143, 21'd151, 21'd158, 21'd164,
              21'd15, 21'd15, 21'd15, 21'd15, 21'd15, 21'd28, 21'd52, 21'd73};

    reg        l1_bit_d;
    always @(posedge clk_sys) l1_bit_d <= latch_3f[0];
    wire l1_trig = l1_bit_d & ~latch_3f[0];

    reg [13:0] l1_cnt;
    reg [15:0] l1_vc;
    wire       l1_act = (l1_cnt != 14'd0);
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin l1_cnt <= 14'd0; l1_vc <= VC_RESET; end
        else begin
            if (l1_trig) l1_cnt <= LASER_TICKS;
            else if (tick && l1_act) begin
                l1_cnt <= l1_cnt - 14'd1;
                l1_vc  <= l1_vc + ((VC_TARGET - l1_vc) >> 14);
                if (l1_cnt == 14'd1) l1_vc <= VC_RESET;
            end
        end
    end
    wire [5:0]  l1_idx  = (l1_vc[15:9] > 7'd63) ? 6'd63 : l1_vc[14:9];
    wire [20:0] l1_half = L1ROM[l1_idx*21 +: 21];

    reg [20:0] l1_osc_cnt;
    reg        l1_osc;
    reg [5:0]  l1_div;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin l1_osc_cnt <= 21'd0; l1_osc <= 1'b0; l1_div <= 6'd0; end
        else if (!l1_act) begin l1_osc_cnt <= 21'd0; l1_osc <= 1'b0; l1_div <= 6'd0; end
        else if (l1_osc_cnt == 21'd0) begin
            l1_osc_cnt <= l1_half;
            l1_osc     <= ~l1_osc;
            if (!l1_osc) l1_div <= l1_div + 6'd1;
        end else l1_osc_cnt <= l1_osc_cnt - 21'd1;
    end

    wire signed [15:0] l1_sum =
        (l1_div[0] ? LW_Q1 : -LW_Q1) + (l1_div[1] ? LW_Q2 : -LW_Q2) +
        (l1_div[2] ? LW_Q3 : -LW_Q3) + (l1_div[3] ? LW_Q4 : -LW_Q4) +
        (l1_div[5] ? LW_Q6 : -LW_Q6);
    wire signed [15:0] laser1_out = l1_act ? l1_sum : 16'sd0;

    reg        l2_bit_d;
    always @(posedge clk_sys) l2_bit_d <= latch_3f[1];
    wire l2_trig = l2_bit_d & ~latch_3f[1];

    reg [13:0] l2_cnt;
    reg [15:0] l2_vc;
    wire       l2_act = (l2_cnt != 14'd0);
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin l2_cnt <= 14'd0; l2_vc <= VC_RESET; end
        else begin
            if (l2_trig) l2_cnt <= LASER_TICKS;
            else if (tick && l2_act) begin
                l2_cnt <= l2_cnt - 14'd1;
                l2_vc  <= l2_vc + ((VC_TARGET - l2_vc) >> 14);
                if (l2_cnt == 14'd1) l2_vc <= VC_RESET;
            end
        end
    end
    wire [5:0]  l2_idx  = (l2_vc[15:9] > 7'd63) ? 6'd63 : l2_vc[14:9];
    wire [20:0] l2_half = L2ROM[l2_idx*21 +: 21];

    reg [20:0] l2_osc_cnt;
    reg        l2_osc;
    reg [5:0]  l2_div;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin l2_osc_cnt <= 21'd0; l2_osc <= 1'b0; l2_div <= 6'd0; end
        else if (!l2_act) begin l2_osc_cnt <= 21'd0; l2_osc <= 1'b0; l2_div <= 6'd0; end
        else if (l2_osc_cnt == 21'd0) begin
            l2_osc_cnt <= l2_half;
            l2_osc     <= ~l2_osc;
            if (!l2_osc) l2_div <= l2_div + 6'd1;
        end else l2_osc_cnt <= l2_osc_cnt - 21'd1;
    end

    wire signed [15:0] l2_sum =
        (l2_div[0] ? LW_Q1 : -LW_Q1) + (l2_div[1] ? LW_Q2 : -LW_Q2) +
        (l2_div[2] ? LW_Q3 : -LW_Q3) + (l2_div[3] ? LW_Q4 : -LW_Q4) +
        (l2_div[5] ? LW_Q6 : -LW_Q6);
    wire signed [15:0] laser2_out = l2_act ? l2_sum : 16'sd0;

    wire refill_gate = ~latch_3e[6];

    localparam [21:0] RFL_STEP_HALF = 22'd2903243;
    localparam [19:0] RFL_ALT_HALF  = 20'd505275;

    reg [21:0] rfl_sc; reg rfl_sq;
    reg [3:0]  rfl_step;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin rfl_sc <= RFL_STEP_HALF; rfl_sq <= 1'b0; rfl_step <= 4'd0; end
        else if (!refill_gate) begin rfl_sc <= RFL_STEP_HALF; rfl_sq <= 1'b0; rfl_step <= 4'd0; end
        else if (rfl_sc == 22'd0) begin
            rfl_sc <= RFL_STEP_HALF;
            rfl_sq <= ~rfl_sq;
            if (!rfl_sq) rfl_step <= (rfl_step == 4'd9) ? 4'd0 : rfl_step + 4'd1;
        end else rfl_sc <= rfl_sc - 22'd1;
    end

    reg [19:0] rfl_ac; reg rfl_alt;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin rfl_ac <= RFL_ALT_HALF; rfl_alt <= 1'b0; end
        else if (rfl_ac == 20'd0) begin rfl_ac <= RFL_ALT_HALF; rfl_alt <= ~rfl_alt; end
        else rfl_ac <= rfl_ac - 20'd1;
    end

    reg [14:0] rfl_u5rom, rfl_u4rom;
    always @* begin
        case (rfl_step)
        4'd0: begin rfl_u5rom=15'd17008; rfl_u4rom=15'd20567; end
        4'd1: begin rfl_u5rom=15'd16289; rfl_u4rom=15'd19707; end
        4'd2: begin rfl_u5rom=15'd15320; rfl_u4rom=15'd18548; end
        4'd3: begin rfl_u5rom=15'd15045; rfl_u4rom=15'd18219; end
        4'd4: begin rfl_u5rom=15'd14796; rfl_u4rom=15'd17922; end
        4'd5: begin rfl_u5rom=15'd14437; rfl_u4rom=15'd17493; end
        4'd6: begin rfl_u5rom=15'd14190; rfl_u4rom=15'd17198; end
        4'd7: begin rfl_u5rom=15'd14021; rfl_u4rom=15'd16995; end
        4'd8: begin rfl_u5rom=15'd13915; rfl_u4rom=15'd16868; end
        default: begin rfl_u5rom=15'd13840; rfl_u4rom=15'd16779; end
        endcase
    end

    reg [14:0] rfl_c5, rfl_c4; reg rfl_s5, rfl_s4;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin rfl_c5 <= 15'd0; rfl_s5 <= 1'b0; rfl_c4 <= 15'd0; rfl_s4 <= 1'b0; end
        else begin
            if (!refill_gate ||  rfl_alt) begin rfl_c5 <= 15'd0; rfl_s5 <= 1'b0; end
            else if (rfl_c5 == 15'd0) begin rfl_c5 <= rfl_u5rom; rfl_s5 <= ~rfl_s5; end
            else rfl_c5 <= rfl_c5 - 15'd1;
            if (!refill_gate || !rfl_alt) begin rfl_c4 <= 15'd0; rfl_s4 <= 1'b0; end
            else if (rfl_c4 == 15'd0) begin rfl_c4 <= rfl_u4rom; rfl_s4 <= ~rfl_s4; end
            else rfl_c4 <= rfl_c4 - 15'd1;
        end
    end

    wire signed [15:0] refill_out =
        !refill_gate ? 16'sd0 :
        ((rfl_alt ? rfl_s4 : rfl_s5) ? 16'sd3000 : -16'sd3000);

    reg        sonar_bit_d;
    always @(posedge clk_sys) sonar_bit_d <= latch_3f[7];
    wire sonar_trig = sonar_bit_d & ~latch_3f[7];

    localparam [13:0] SONAR_TICKS = 14'd8459;
    reg [13:0] sonar_pc;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) sonar_pc <= 14'd0;
        else if (sonar_trig) sonar_pc <= SONAR_TICKS;
        else if (tick && sonar_pc != 0) sonar_pc <= sonar_pc - 14'd1;
    end

    reg [23:0] sonar_env24;
    wire [16:0] sonar_env   = sonar_env24[23:7];
    wire [23:0] sonar_d_att = {ENV_MAX,7'd0} - sonar_env24;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) sonar_env24 <= 24'd0;
        else if (tick) begin
            if (sonar_pc != 0)
                sonar_env24 <= sonar_env24 + (({2'b0,sonar_d_att}*2) >> 13);
            else if (sonar_env24 != 0)
                sonar_env24 <= sonar_env24 - (({2'b0,sonar_env24}*9) >> 18) - 24'd1;
        end
    end

    localparam [23:0] SON_INC0 = 24'd130264;
    localparam [23:0] SON_INC1 = 24'd130952;
    localparam [23:0] SON_INC2 = 24'd131488;
    localparam [23:0] SON_INC3 = 24'd133535;
    reg [23:0] son_ph0, son_ph1, son_ph2, son_ph3;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin
            son_ph0 <= 24'h000000; son_ph1 <= 24'h5A0000;
            son_ph2 <= 24'h9C0000; son_ph3 <= 24'h2E0000;
        end else if (tick) begin
            son_ph0 <= son_ph0 + SON_INC0;
            son_ph1 <= son_ph1 + SON_INC1;
            son_ph2 <= son_ph2 + SON_INC2;
            son_ph3 <= son_ph3 + SON_INC3;
        end
    end

    localparam [767:0] SINLUT = {12'd2012, 12'd2021, 12'd2028, 12'd2035, 12'd2039, 12'd2043, 12'd2046, 12'd2047,
              12'd1901, 12'd1919, 12'd1936, 12'd1951, 12'd1966, 12'd1979, 12'd1992, 12'd2003,
              12'd1716, 12'd1743, 12'd1769, 12'd1793, 12'd1817, 12'd1840, 12'd1861, 12'd1881,
              12'd1465, 12'd1500, 12'd1533, 12'd1566, 12'd1598, 12'd1629, 12'd1659, 12'd1688,
              12'd1158, 12'd1199, 12'd1239, 12'd1279, 12'd1318, 12'd1356, 12'd1393, 12'd1430,
              12'd807, 12'd852, 12'd898, 12'd943, 12'd987, 12'd1031, 12'd1074, 12'd1116,
              12'd424, 12'd473, 12'd522, 12'd570, 12'd618, 12'd666, 12'd713, 12'd760,
              12'd25, 12'd75, 12'd126, 12'd176, 12'd226, 12'd275, 12'd325, 12'd375};
    function signed [12:0] sine_q;
        input [23:0] ph;
        reg   [5:0]  idx;
        reg   [11:0] mag;
        begin
            idx = ph[22] ? ~ph[21:16] : ph[21:16];
            mag = SINLUT[idx*12 +: 12];
            sine_q = ph[23] ? -$signed({1'b0,mag}) : $signed({1'b0,mag});
        end
    endfunction

    wire signed [12:0] son_s0 = sine_q(son_ph0);
    wire signed [12:0] son_s1 = sine_q(son_ph1);
    wire signed [12:0] son_s2 = sine_q(son_ph2);
    wire signed [12:0] son_s3 = sine_q(son_ph3);
    wire signed [26:0] son_mix27 = son_s0*16'sd468 + son_s1*16'sd1907
                                 + son_s2*16'sd2020 + son_s3*16'sd1605;
    wire signed [15:0] son_mix = son_mix27 >>> 11;
    wire signed [33:0] son_envP = son_mix * $signed({1'b0, sonar_env});
    wire signed [15:0] sonar_out = son_envP[33:16];

    reg        bonus_bit_d;
    always @(posedge clk_sys) bonus_bit_d <= latch_3f[6];
    wire bonus_trig = bonus_bit_d & ~latch_3f[6];

    localparam [11:0] BONUS_TICKS = 12'd2097;
    reg [11:0] bonus_pc;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) bonus_pc <= 12'd0;
        else if (bonus_trig) bonus_pc <= BONUS_TICKS;
        else if (tick && bonus_pc != 0) bonus_pc <= bonus_pc - 12'd1;
    end

    reg [23:0] bonus_env24;
    wire [16:0] bonus_env   = bonus_env24[23:7];
    wire [23:0] bonus_d_att = {ENV_MAX,7'd0} - bonus_env24;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) bonus_env24 <= 24'd0;
        else if (tick) begin
            if (bonus_pc != 0)
                bonus_env24 <= bonus_env24 + (bonus_d_att >> 9);
            else if (bonus_env24 != 0)
                bonus_env24 <= bonus_env24 - (({3'b0,bonus_env24}*5) >> 20) - 24'd1;
        end
    end

    localparam [20:0] BON_CHOP_HALF = 21'd1075694;
    reg [20:0] bon_cc; reg bon_sel;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin bon_cc <= BON_CHOP_HALF; bon_sel <= 1'b0; end
        else if (bon_cc == 21'd0) begin bon_cc <= BON_CHOP_HALF; bon_sel <= ~bon_sel; end
        else bon_cc <= bon_cc - 21'd1;
    end

    localparam [12:0] BON_HALF_HI = 13'd5154;
    localparam [12:0] BON_HALF_LO = 13'd5340;
    reg [12:0] bon_tc; reg bon_sq;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) begin bon_tc <= 13'd0; bon_sq <= 1'b0; end
        else if (bon_tc == 13'd0) begin
            bon_tc <= bon_sel ? BON_HALF_HI : BON_HALF_LO;
            bon_sq <= ~bon_sq;
        end else bon_tc <= bon_tc - 13'd1;
    end

    wire signed [24:0] bon_amp25 = $signed({1'b0,bonus_env}) * $signed(8'sd80);
    wire signed [15:0] bon_amp   = bon_amp25[24:10];
    wire signed [15:0] bonus_out = bon_sq ? bon_amp : -bon_amp;

    localparam signed [15:0] MIXW_EXPL   = 16'sd16384;
    localparam signed [15:0] MIXW_ASTRO  = 16'sd7700;
    localparam signed [15:0] MIXW_SONAR  = 16'sd350;
    localparam signed [15:0] MIXW_BONUS  = 16'sd164;
    localparam signed [15:0] MIXW_REFILL = 16'sd164;
    localparam signed [15:0] MIXW_LASER1 = 16'sd164;
    localparam signed [15:0] MIXW_LASER2 = 16'sd77;
    localparam signed [15:0] MIXW_INV1   = 16'sd77;
    localparam signed [15:0] MIXW_INV2   = 16'sd77;
    localparam signed [15:0] MIXW_INV3   = 16'sd77;
    localparam signed [15:0] MIXW_INV4   = 16'sd77;

    localparam signed [15:0] MIXE_EXPL   = 16'sd16384;
    localparam signed [15:0] MIXE_ASTRO  = 16'sd12738;
    localparam signed [15:0] MIXE_SONAR  = 16'sd4546;
    localparam signed [15:0] MIXE_BONUS  = 16'sd3530;
    localparam signed [15:0] MIXE_REFILL = 16'sd3530;
    localparam signed [15:0] MIXE_LASER1 = 16'sd3530;
    localparam signed [15:0] MIXE_LASER2 = 16'sd2743;
    localparam signed [15:0] MIXE_INV1   = 16'sd1829;
    localparam signed [15:0] MIXE_INV2   = 16'sd2743;
    localparam signed [15:0] MIXE_INV3   = 16'sd2743;

    localparam signed [15:0] MIXE_INV4   = 16'sd867;

    wire signed [31:0] mix_acc =
          expl_out   * MIXE_EXPL
        + astro_out  * MIXE_ASTRO
        + sonar_out  * MIXE_SONAR
        + bonus_out  * MIXE_BONUS
        + refill_out * MIXE_REFILL
        + laser1_out * MIXE_LASER1
        + laser2_out * MIXE_LASER2
        + inv1_out   * MIXE_INV1
        + inv2_out   * MIXE_INV2
        + inv3_out   * MIXE_INV3
        + inv4_out   * MIXE_INV4;

    localparam MIX_Q14          = 14;
    localparam MIX_MAKEUP_LOG2  = 1;

    localparam OUTPUT_GAIN_LOG2 = 1;

    wire signed [31:0] mix_scaled =
        mix_acc >>> (MIX_Q14 - MIX_MAKEUP_LOG2 - OUTPUT_GAIN_LOG2);

    wire signed [15:0] voice_sum_clamped =
        (mix_scaled >  32'sd32767) ?  16'sd32767 :
        (mix_scaled < -32'sd32768) ? -16'sd32768 :
                                      mix_scaled[15:0];

    localparam LPF_SHIFT = 10;

    wire signed [15:0] lpf_in = mute ? 16'sd0 : voice_sum_clamped;

    reg  signed [31:0] lpf_acc;
    wire signed [31:0] lpf_tgt  = {{2{lpf_in[15]}}, lpf_in, 14'd0};
    wire signed [31:0] lpf_diff = lpf_tgt - lpf_acc;
    always @(posedge clk_sys or posedge reset) begin
        if (reset) lpf_acc <= 32'sd0;
        else       lpf_acc <= lpf_acc + (lpf_diff >>> LPF_SHIFT);
    end

    wire signed [15:0] lpf_out = lpf_acc[29:14] + {15'd0, lpf_acc[13]};

    always @(posedge clk_sys or posedge reset) begin
        if (reset)
            audio_out <= 16'sd0;
        else
            audio_out <= lpf_out;
    end

endmodule
