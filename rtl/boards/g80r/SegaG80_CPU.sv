//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r.cpp (Aaron Giles, BSD-3-Clause)

module SegaG80_CPU (
    output chip_pool_pkg::z80_i_t z80_0_i,
    input  chip_pool_pkg::z80_o_t z80_0_o,
    output      [15:0] rom0_a,
    input        [7:0] rom0_d,
    output ram_pool_pkg::pram_i_t pr0_i,
    input  ram_pool_pkg::pram_o_t pr0_o,
    input              reset,
    input              clk_sys,
    input        [2:0] game_id,       // 0=ASTROB,1=MONSTERB,2=SPACEOD,3=005,4=SINDBADM,5=PIGNEWT
    input              pause,
    input              service,
    input              self_test,

    input              p1_up, p1_down, p1_left, p1_right,
    input              p1_fire1, p1_fire2, p1_start, p1_coin,
    input              p2_up, p2_down, p2_left, p2_right,
    input              p2_fire1, p2_fire2, p2_start, p2_coin,

    input        [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3,

    input              vblank_in,

    input       [24:0] ioctl_addr,
    input              ioctl_wr,
    input        [7:0] ioctl_data,
    input        [7:0] ioctl_index,

    output             m1_o,
    output             mreq_o,
    output             iorq_o,
    output             rd_o,
    output             wr_o,
    output      [15:0] addr_o,
    output       [7:0] dout_o,
    input        [7:0] din_i,

    input       [15:0] hs_address,
    input        [7:0] hs_data_in,
    output       [7:0] hs_data_out,
    input              hs_write,

    output             ce_pix_o,

    output      [12:0] vram_addr_o,
    output       [7:0] vram_din_o,
    output             vram_wr_o,
    input        [7:0] vidram_din_i,
    output             video_control_1_o,
    output             video_flip_o,
    output             video_control_3_o,
    output             video_control_6_o,
    output       [7:0] mb_snd_cmd_o,
    input              mb_snd_busy_i,

    output       [9:0] bg_scrollx_o,
    output      [10:0] bg_scrolly_o,
    output             bg_enable_o,
    output       [3:0] bg_char_bank_o,

    output             audio_we_o,
    output             audio_addr_o,
    output       [7:0] audio_din_o,
    output             ce_cpu_o,

    output             speech_data_we_o,
    output             speech_ctrl_we_o,

    output             usb_data_wr_o,
    output       [7:0] usb_din_o,
    input        [7:0] usb_status_i,
    output      [11:0] usb_pgm_addr_o,
    output       [7:0] usb_pgm_din_o,
    output             usb_pgm_wr_o,
    input        [7:0] usb_pgm_dout_i,

    output             so_port_wr_o,
    output       [2:0] so_port_addr_o,
    output       [7:0] so_port_din_o,
    input        [7:0] so_port_dout_i,

    output             mb_music_wr_o,
    output       [7:0] mb_music_din_o,

    output             sm_snd_wr_o,
    output       [7:0] sm_snd_din_o,
    output             sm_ppi_pc_wr_o,
    output       [7:0] sm_ppi_pc_din_o,

    output             s5_ppi_wr_o,
    output       [1:0] s5_ppi_addr_o,
    output       [7:0] s5_ppi_din_o
);

reg [3:0] ph_cnt;
always @(posedge clk_sys or posedge reset) begin
    if (reset) ph_cnt <= 4'd0;
    else       ph_cnt <= (ph_cnt == 4'd11) ? 4'd0 : ph_cnt + 4'd1;
end

wire ce_cpu_raw = (ph_cnt == 4'd0) || (ph_cnt == 4'd4) ||
                  (ph_cnt == 4'd8);
assign ce_pix_o = (ph_cnt == 4'd0) || (ph_cnt == 4'd3) ||
                  (ph_cnt == 4'd6) || (ph_cnt == 4'd9);

wire ce_cpu = ce_cpu_raw & ~pause;

wire        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, busak_n, halt_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
wire io_write  = ~iorq_n & ~wr_n;
wire [7:0] port_addr = cpu_addr[7:0];
wire sm_en    = (game_id == 3'd4);
wire io_40    = (port_addr == 8'h40);
wire usb_en = (game_id == 3'd5);
reg [7:0] video_control;
reg [1:0] ws_cnt;
reg       mreq_d, iorq_d;
always @(posedge clk_sys) begin
    mreq_d <= mreq_n;
    iorq_d <= iorq_n;
end
wire mem_acc_now = ~mreq_n & (~rd_n | ~wr_n);
reg  mem_acc_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset) mem_acc_d <= 1'b0;
    else       mem_acc_d <= mem_acc_now;
end
wire access_start = mem_acc_now & ~mem_acc_d;

always @(posedge clk_sys or posedge reset) begin
    if (reset)                  ws_cnt <= 2'd0;
    else if (access_start)      ws_cnt <= 2'd2;
    else if (ce_cpu && ws_cnt)  ws_cnt <= ws_cnt - 2'd1;
end
wire cpu_wait = (ws_cnt != 2'd0);

reg selftest_d, nmi_pulse;
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        selftest_d <= 1'b0;
        nmi_pulse  <= 1'b0;
    end else begin
        selftest_d <= self_test;
        nmi_pulse  <= self_test & ~selftest_d;
    end
end
wire nmi_n_internal;
reg nmi_hold;
always @(posedge clk_sys or posedge reset) begin
    if (reset)            nmi_hold <= 1'b0;
    else if (nmi_pulse)   nmi_hold <= 1'b1;
    else if (ce_cpu)      nmi_hold <= 1'b0;
end
assign nmi_n_internal = ~nmi_hold;

reg vblank_d;
wire vblank_rising = vblank_in & ~vblank_d;
always @(posedge clk_sys) vblank_d <= vblank_in;

reg irq_pend;
wire irq_ack = ~m1_n & ~iorq_n;

wire sm_irq_ack = sm_en & io_write & io_40 & ce_cpu;

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        irq_pend <= 1'b0;
    else if (vblank_rising && (sm_en || video_control[2]))
        irq_pend <= 1'b1;
    else if (sm_en ? sm_irq_ack : (irq_ack && ce_cpu))
        irq_pend <= 1'b0;
end

wire irq_n_internal = ~irq_pend;

reg   [7:0] cpu_din;

assign z80_0_i  = '{ce: ce_cpu & ~cpu_wait, int_n: irq_n_internal, nmi_n: nmi_n_internal, di: cpu_din};
assign m1_n     = z80_0_o.m1_n;
assign mreq_n   = z80_0_o.mreq_n;
assign iorq_n   = z80_0_o.iorq_n;
assign rd_n     = z80_0_o.rd_n;
assign wr_n     = z80_0_o.wr_n;
assign rfsh_n   = z80_0_o.rfsh_n;
assign halt_n   = 1'b1;
assign busak_n  = 1'b1;
assign cpu_addr = z80_0_o.a;
assign cpu_dout = z80_0_o.dout;

assign m1_o   = ~m1_n;
assign mreq_o = ~mreq_n;
assign iorq_o = ~iorq_n;
assign rd_o   = ~rd_n;
assign wr_o   = ~wr_n;
assign addr_o = cpu_addr;
assign dout_o = cpu_dout;

reg [15:0] scrambled_write_pc;
wire       m1_read = ~m1_n & ~rd_n & ~mreq_n;

wire mem_wr_now  = ~mreq_n & ~wr_n;
wire wr_decodes  = ((cpu_addr >= 16'hC800) & (cpu_addr <= 16'hCFFF))
                 | (cpu_addr >= 16'hE000);
reg  mem_wr_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset) mem_wr_d <= 1'b0;
    else       mem_wr_d <= mem_wr_now & wr_decodes;
end
wire write_ended = mem_wr_d & ~(mem_wr_now & wr_decodes);

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        scrambled_write_pc <= 16'hFFFF;
    else if (m1_read & ce_cpu) begin
        if (cpu_din == 8'h32)
            scrambled_write_pc <= cpu_addr;
        else
            scrambled_write_pc <= 16'hFFFF;
    end
    else if (write_ended)
        scrambled_write_pc <= 16'hFFFF;
end

wire [2:0] chip_sel =
    (game_id == 3'd0) ? 3'd1 :
    (game_id == 3'd1) ? 3'd6 :
    (game_id == 3'd2) ? 3'd2 :
    (game_id == 3'd3) ? 3'd4 :
    (game_id == 3'd5) ? 3'd2 :
                        3'd0;

wire [7:0] decrypted_lo;
segag80_decrypt decrypt_inst (
    .pc        (scrambled_write_pc),
    .lo_in     (cpu_addr[7:0]),
    .chip_sel  (chip_sel),
    .lo_out    (decrypted_lo)
);

wire        decrypt_active = (scrambled_write_pc != 16'hFFFF);
wire [15:0] decrypt_addr   = decrypt_active ? {cpu_addr[15:8], decrypted_lo}
                                            : cpu_addr;

wire mem_read  = ~mreq_n & ~rd_n;
wire mem_write = ~mreq_n & ~wr_n;
wire io_read   = ~iorq_n & ~rd_n & ~(~m1_n);

wire rom_sel   = mem_read  & (cpu_addr < 16'hC000);
wire ram_sel   = (cpu_addr >= 16'hC800) & (cpu_addr <= 16'hCFFF);
wire vram_sel  = (cpu_addr >= 16'hE000);

wire usb_sel   = usb_en & (cpu_addr >= 16'hD000) & (cpu_addr <= 16'hDFFF);

wire io_be_bf = (port_addr == 8'hBE) | (port_addr == 8'hBF);

wire io_42_43 = (port_addr == 8'h42) | (port_addr == 8'h43);
wire io_80_83 = (port_addr >= 8'h80) & (port_addr <= 8'h83);

wire io_vid   = sm_en ? io_42_43 : io_be_bf;
wire io_f8_fb = (port_addr >= 8'hF8) & (port_addr <= 8'hFB);
wire io_f9    = (port_addr == 8'hF9) | (port_addr == 8'hFD);
wire io_fc    = (port_addr == 8'hFC);

wire io_3e_3f = (port_addr == 8'h3E) | (port_addr == 8'h3F);

wire io_38 = (port_addr == 8'h38);
wire io_3b = (port_addr == 8'h3B);

wire io_b8_bd = (port_addr >= 8'hB8) & (port_addr <= 8'hBD);

wire io_3f  = (port_addr == 8'h3F);

wire so_en    = (game_id == 3'd2);

wire mb_en    = (game_id == 3'd1);

wire s5_en    = (game_id == 3'd3);

wire [7:0] sm_ppi_b = {3'b111, ~p2_up, ~p2_down, ~p2_fire1, ~p2_right, ~p2_left};

reg [7:0] mb_snd_cmd;
always @(posedge clk_sys or posedge reset) begin
    if (reset)                                            mb_snd_cmd <= 8'h08;
    else if (mb_en & io_write & (port_addr == 8'h0E) & ce_cpu) mb_snd_cmd <= cpu_dout;
end
assign mb_snd_cmd_o = mb_snd_cmd;

assign mb_music_wr_o  = mb_en & io_write & (port_addr == 8'h0C) & ce_cpu;
assign mb_music_din_o = cpu_dout;
wire [7:0] sm_ppi_dout = (port_addr[1:0] == 2'd1) ? sm_ppi_b : 8'h00;
wire io_0c_0f = (port_addr >= 8'h0C) & (port_addr <= 8'h0F);
wire io_08_0f = (port_addr >= 8'h08) & (port_addr <= 8'h0F);

wire [7:0] rom_dout;
assign rom0_a   = cpu_addr;
assign rom_dout = rom0_d;

wire       sindbadm_en = (game_id == 3'd4);
wire [7:0] rom_dout_dec;

segag80_5028 u_dec5028 (
    .src  (rom_dout),
    .addr (cpu_addr),
    .m1   (~m1_n),
    .dout (rom_dout_dec)
);

wire [7:0] rom_dout_eff = (sindbadm_en & ~cpu_addr[15]) ? rom_dout_dec : rom_dout;

wire [7:0] mainram_dout;
wire [7:0] mainram_hs_rd;

assign pr0_i = '{a_addr: {4'd0, (ram_sel & mem_write) ? decrypt_addr[10:0] : cpu_addr[10:0]}, a_d: cpu_dout,
                a_we: ram_sel & mem_write & ce_cpu, b_addr: {4'd0, hs_address[10:0]}, b_d: hs_data_in, b_we: hs_write};
assign mainram_dout  = pr0_o.a_q;
assign mainram_hs_rd = pr0_o.b_q;

wire [7:0] vidram_dout = vidram_din_i;

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        video_control <= 8'd0;
    else if (io_write & io_vid & port_addr[0] & ce_cpu)
        video_control <= cpu_dout;
end

reg [9:0] vblank_latch_cnt;
always @(posedge clk_sys or posedge reset) begin
    if (reset)
        vblank_latch_cnt <= 10'd0;
    else if (vblank_rising)
        vblank_latch_cnt <= 10'd603;
    else if (vblank_latch_cnt != 10'd0)
        vblank_latch_cnt <= vblank_latch_cnt - 10'd1;
end
wire vblank_latch = (vblank_latch_cnt != 10'd0);

reg video_flip_r;
always @(posedge clk_sys or posedge reset) begin
    if (reset)                video_flip_r <= 1'b0;
    else if (vblank_rising)   video_flip_r <= video_control[0];
end

reg [9:0]  bg_scrollx;
reg [10:0] bg_scrolly;
reg        bg_enable;
reg [3:0]  bg_char_bank;

always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        bg_scrollx   <= 10'd0;
        bg_scrolly   <= 11'd0;
        bg_enable    <= 1'b0;
        bg_char_bank <= 4'd0;
    end else if (sm_en & io_write & (port_addr == 8'h41) & ce_cpu) begin
        bg_char_bank <= {2'b00, cpu_dout[1:0]};
        bg_scrollx   <= {cpu_dout[3:2], 8'd0};
        bg_scrolly   <= {cpu_dout[6:4], 8'd0};
        bg_enable    <= cpu_dout[7];
    end else if (io_write & io_b8_bd & ce_cpu & ~sm_en) begin
        if (mb_en) begin
            if (port_addr[2:0] == 3'd4) begin
                bg_char_bank <= cpu_dout[3:0];
                bg_scrolly   <= {cpu_dout[6:4], 8'd0};
                bg_enable    <= cpu_dout[7];
            end
        end else begin
            case (port_addr[2:0])
                3'd0: bg_scrollx[7:0] <= cpu_dout;
                3'd1: begin
                    bg_scrollx[9:8] <= cpu_dout[1:0];
                    bg_enable       <= cpu_dout[7];
                end
                3'd2: bg_scrolly[7:0] <= cpu_dout;
                3'd3: bg_scrolly[9:8] <= cpu_dout[1:0];
                3'd4: bg_char_bank    <= {cpu_dout[3], cpu_dout[0], cpu_dout[3], cpu_dout[0]};
                default: ;
            endcase
        end
    end
end

assign bg_scrollx_o   = bg_scrollx;
assign bg_scrolly_o   = bg_scrolly;
assign bg_enable_o    = bg_enable;
assign bg_char_bank_o = bg_char_bank;
assign video_control_3_o = video_control[3];
assign video_control_6_o = video_control[6];

wire [7:0] video_port_r =
    port_addr[0] ? {5'b11111, video_control[2], video_flip_r, vblank_latch}
                 : 8'hFF;

reg d7d6_b5, d7d6_b6;
reg d5d4_b2, d5d4_b3, d5d4_b6, d5d4_b7;
always @(*) begin
    case (game_id)
        3'd0: begin
            d7d6_b5 = 1'b1;      d7d6_b6 = 1'b1;
            d5d4_b2 = ~p1_left;  d5d4_b3 = ~p1_fire1;
            d5d4_b6 = ~p1_right; d5d4_b7 = ~p1_fire2;
        end
        3'd2: begin
            d7d6_b5 = ~p2_fire2; d7d6_b6 = ~p2_fire1;
            d5d4_b2 = ~p2_up;    d5d4_b3 = ~p2_left;
            d5d4_b6 = ~p2_down;  d5d4_b7 = ~p2_right;
        end
        default: begin
            d7d6_b5 = 1'b1;      d7d6_b6 = ~p1_up;
            d5d4_b2 = ~p1_left;  d5d4_b3 = ~p1_fire1;
            d5d4_b6 = ~p1_right; d5d4_b7 = ~p1_down;
        end
    endcase
end

wire [7:0] logical_d7d6 = {
    1'b1,
    d7d6_b6,
    d7d6_b5,
    ~p2_coin,
    3'b111,
    ~p1_coin
};

wire [7:0] logical_d5d4 = {
    d5d4_b7,
    d5d4_b6,
    ~p2_start,
    1'b1,
    d5d4_b3,
    d5d4_b2,
    ~p1_start,
    ~service
};

wire [7:0] logical_d3d2 = dip_sw0;
wire [7:0] logical_d1d0 = dip_sw1;

function [7:0] demangle;
    input [7:0] d7d6;
    input [7:0] d5d4;
    input [7:0] d3d2;
    input [7:0] d1d0;
    begin
        demangle = ((d7d6 << 7) & 8'h80) | ((d7d6 << 2) & 8'h40) |
                   ((d5d4 << 5) & 8'h20) | ((d5d4 << 0) & 8'h10) |
                   ((d3d2 << 3) & 8'h08) | ((d3d2 >> 2) & 8'h04) |
                   ((d1d0 << 1) & 8'h02) | ((d1d0 >> 4) & 8'h01);
    end
endfunction

wire so_upright = logical_d3d2[2];

wire [7:0] so_fc_raw = {2'b00, p1_fire2, p1_fire1, p1_up, p1_down, p1_right, p1_left};

wire [7:0] so_fc_dout = so_upright ? {5'b00000, so_fc_raw[2], so_fc_raw[0], so_fc_raw[1]}
                                   : so_fc_raw;

wire [7:0] so_d7d6 = logical_d7d6 | 8'h60;
wire [7:0] so_d5d4 = (logical_d5d4 & 8'hE3)
                   | {2'b11, 1'b0, ~so_fc_raw[3], ~so_fc_raw[4], ~so_fc_raw[5], 2'b00};

wire [7:0] eff_d7d6 = (so_en & so_upright) ? so_d7d6 : logical_d7d6;
wire [7:0] eff_d5d4 = (so_en & so_upright) ? so_d5d4 : logical_d5d4;

wire [1:0] mux_shift = port_addr[1:0];
wire [7:0] mangled_dout = demangle(
    eff_d7d6 >> mux_shift,
    eff_d5d4 >> mux_shift,
    logical_d3d2 >> mux_shift,
    logical_d1d0 >> mux_shift
);

wire [7:0] fc_dout = {
    p2_left,
    p2_right,
    p2_fire1,
    p2_fire2,
    4'b0000
};

always @* begin
    casez (1'b1)
        (rom_sel):                    cpu_din = rom_dout_eff;
        (ram_sel  & mem_read):        cpu_din = mainram_dout;
        (vram_sel & mem_read):        cpu_din = vidram_dout;
        (usb_sel  & mem_read):        cpu_din = usb_pgm_dout_i;
        (io_read  & io_vid):          cpu_din = video_port_r;
        (io_read  & io_f8_fb):        cpu_din = mangled_dout;
        (io_read  & io_fc):           cpu_din = so_en ? so_fc_dout : fc_dout;
        (io_read  & io_3f & usb_en):  cpu_din = usb_status_i;
        (io_read  & io_08_0f & so_en):cpu_din = so_port_dout_i;
        (io_read  & io_0c_0f & mb_en):cpu_din = (port_addr == 8'h0E)
                                              ? {3'b000, mb_snd_busy_i, 4'b0000}
                                              : 8'h00;
        (io_read  & io_80_83 & sm_en):cpu_din = sm_ppi_dout;
        default:                      cpu_din = 8'hFF;
    endcase
end

assign hs_data_out = mainram_hs_rd;

assign vram_addr_o       = (vram_sel & mem_write) ? decrypt_addr[12:0]
                                                  : cpu_addr[12:0];
assign vram_din_o        = cpu_dout;
assign vram_wr_o         = vram_sel & mem_write & ce_cpu;
assign video_control_1_o = video_control[1];
assign video_flip_o      = video_flip_r;

assign audio_we_o   = io_write & io_3e_3f & ~usb_en;
assign audio_addr_o = port_addr[0];
assign audio_din_o  = cpu_dout;
assign ce_cpu_o     = ce_cpu;

reg usb_io_wr_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset)       usb_io_wr_d <= 1'b0;
    else if (ce_cpu) usb_io_wr_d <= io_write & io_3f & usb_en;
end

assign usb_data_wr_o  = io_write & io_3f & usb_en & ce_cpu & ~usb_io_wr_d;
assign usb_din_o      = cpu_dout;
assign usb_pgm_addr_o = (usb_sel & mem_write) ? decrypt_addr[11:0]
                                              : cpu_addr[11:0];
assign usb_pgm_din_o  = cpu_dout;
assign usb_pgm_wr_o   = usb_sel & mem_write & ce_cpu;

assign so_port_wr_o   = io_write & io_08_0f & so_en & ce_cpu;
assign so_port_addr_o = port_addr[2:0];
assign so_port_din_o  = cpu_dout;

wire sm_ppi_wr  = io_write & io_80_83 & sm_en & ce_cpu;
wire sm_pa_wr   = sm_ppi_wr & (port_addr[1:0] == 2'd0);
wire sm_pc_wr   = sm_ppi_wr & (port_addr[1:0] == 2'd2);
wire sm_bsr_pc7 = sm_ppi_wr & (port_addr[1:0] == 2'd3)
                            & ~cpu_dout[7] & (cpu_dout[3:1] == 3'd7);

assign sm_snd_wr_o     = sm_pa_wr;
assign sm_snd_din_o    = cpu_dout;
assign sm_ppi_pc_wr_o  = sm_pc_wr | sm_bsr_pc7;
assign sm_ppi_pc_din_o = sm_pc_wr ? cpu_dout : {cpu_dout[0], 7'b0};

assign s5_ppi_wr_o   = io_write & io_0c_0f & s5_en & ce_cpu;
assign s5_ppi_addr_o = port_addr[1:0];
assign s5_ppi_din_o  = cpu_dout;

assign speech_data_we_o = io_write & io_38 & ce_cpu;
assign speech_ctrl_we_o = io_write & io_3b & ce_cpu;

endmodule
