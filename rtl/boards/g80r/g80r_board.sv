//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r.cpp, segag80r_v.cpp, segag80_m.cpp (Aaron Giles, BSD-3-Clause)

module g80r_board (
    output chip_pool_pkg::z80_i_t           z80_0_i,
    input  chip_pool_pkg::z80_o_t           z80_0_o,
    output chip_pool_pkg::z80_i_t           z80_1_i,
    input  chip_pool_pkg::z80_o_t           z80_1_o,
    output chip_pool_pkg::mcs48_i_t         mcs48_0_i,
    input  chip_pool_pkg::mcs48_o_t         mcs48_0_o,
    output chip_pool_pkg::i8035_i_t         i8035_0_i,
    input  chip_pool_pkg::i8035_o_t         i8035_0_o,
    output chip_pool_pkg::sp0250_i_t        sp0250_0_i,
    input  chip_pool_pkg::sp0250_o_t        sp0250_0_o,
    output chip_pool_pkg::tms36xx_i_t       tms36xx_0_i,
    input  chip_pool_pkg::tms36xx_o_t       tms36xx_0_o,
    output chip_pool_pkg::sn76489_i_t [1:0] sn76489_i,
    input  chip_pool_pkg::sn76489_o_t [1:0] sn76489_o,

    output      [15:0] rom0_a,  input  [7:0] rom0_d,
    output      [10:0] rom1_a,  input  [7:0] rom1_d,
    output      [12:0] rom2_a,  input  [7:0] rom2_d,
    output      [14:0] rom3_a,  input  [7:0] rom3_d,
    output      [12:0] rom4_a,  input  [7:0] rom4_d,
    output      [12:0] rom5_a,  input  [7:0] rom5_d,
    output      [13:0] rom6_a,  input  [7:0] rom6_d,
    output      [11:0] rom7_a,  input  [5:0][7:0] rom7_d,
    output      [12:0] rom8_a,  input  [7:0] rom8_d,
    output      [10:0] rom9_a,  input  [7:0] rom9_d,
    output       [4:0] rom10_a, input  [7:0] rom10_d,
    output       [9:0] rom11_a, input  [7:0] rom11_d,
    output      [12:0] rom12_a, input  [7:0] rom12_d,

    output ram_pool_pkg::pram_i_t [4:0] pr_i,
    input  ram_pool_pkg::pram_o_t [4:0] pr_o,

    input                reset,
    input                crt_flip,
    input          [3:0] h_center,
    input          [3:0] v_center,
    input                clk_sys,
    input          [2:0] game_id,      // 0=ASTROB,1=MONSTERB,2=SPACEOD,3=005,4=SINDBADM,5=PIGNEWT

    input                p1_up, p1_down, p1_left, p1_right,
    input                p1_fire1, p1_fire2,
    input                p1_start, p1_coin,

    input                p2_up, p2_down, p2_left, p2_right,
    input                p2_fire1, p2_fire2,
    input                p2_start, p2_coin,

    input                service,
    input                self_test,

    input          [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3,

    output               video_hsync, video_vsync,
    output               video_hblank, video_vblank,
    output               ce_pix,
    output         [7:0] video_r, video_g, video_b,

    output signed [15:0] audio_out,

    input         [24:0] ioctl_addr,
    input                ioctl_wr,
    input          [7:0] ioctl_data,
    input          [7:0] ioctl_index,

    input                pause,

    input         [15:0] hs_address,
    input          [7:0] hs_data_in,
    output         [7:0] hs_data_out,
    input                hs_write
);

wire        cpu_m1;
wire        cpu_mreq;
wire        cpu_iorq;
wire        cpu_rd;
wire        cpu_wr;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
wire  [7:0] cpu_din;

wire        hblank_i, vblank_i, hsync_i, vsync_i;
wire        ce_pix_i;
wire [8:0]  vtg_h, vtg_v;

wire [12:0] cpu_vram_addr;
wire  [7:0] cpu_vram_din;
wire        cpu_vram_wr;
wire  [7:0] vidram_to_cpu;
wire        vc1;
wire        vc6;
wire        vflip;

wire        vc3;
wire  [9:0] bg_scrollx;
wire [10:0] bg_scrolly;
wire        bg_enable;
wire  [3:0] bg_char_bank;
wire  [3:0] bg_color;
wire  [1:0] bg_pix;

wire        mb_board = (game_id == 3'd1);
wire        sm_board = (game_id == 3'd4);
wire        bg_board = (game_id == 3'd5) | mb_board | sm_board;

wire        so_board = (game_id == 3'd2);
wire        mb_music_wr;
wire  [7:0] mb_music_din;
wire        sm_snd_wr, sm_ppi_pc_wr;
wire  [7:0] sm_snd_din, sm_ppi_pc_din;
wire        s5_board = (game_id == 3'd3);
wire        s5_ppi_wr;
wire  [1:0] s5_ppi_addr;
wire  [7:0] s5_ppi_din;
wire        so_port_wr;
wire  [2:0] so_port_addr;
wire  [7:0] so_port_din;
wire  [7:0] so_port_dout;
wire        so_detect_set;
wire        so_show;
wire  [5:0] so_color6;
wire  [5:0] so_raw6;

wire        usb_en = (game_id == 3'd5);
chip_pool_pkg::i8035_i_t usb_i8035_i, mbv_i8035_i;
assign i8035_0_i = usb_en ? usb_i8035_i : mb_board ? mbv_i8035_i : '0;
wire        usb_data_wr;
wire  [7:0] usb_din;
wire  [7:0] usb_status;
wire [11:0] usb_pgm_addr;
wire  [7:0] usb_pgm_din;
wire        usb_pgm_wr;
wire  [7:0] usb_pgm_dout;
wire signed [15:0] usb_sample;
wire        [7:0]  mb_snd_cmd;
wire               mb_snd_busy;
wire signed [15:0] mb_voice_sample;

wire  [7:0] pix_r8, pix_g8, pix_b8;

wire        audio_we, audio_addr_w, ce_cpu_s;
wire  [7:0] audio_din_w;

wire        speech_data_we;
wire        speech_ctrl_we;

wire [10:0] speech_cpu_addr;
wire  [7:0] speech_cpu_data;
wire [13:0] speech_data_addr;
wire  [7:0] speech_data_data;

wire signed [15:0] speech_sample;
wire               speech_valid;

SegaG80_CPU cpu_board (
    .rom0_a(rom0_a), .rom0_d(rom0_d), .pr0_i(pr_i[0]), .pr0_o(pr_o[0]),
    .z80_0_i(z80_0_i), .z80_0_o(z80_0_o),
    .game_id       (game_id),
    .reset         (reset),
    .clk_sys       (clk_sys),
    .pause         (pause),
    .service       (service),
    .self_test     (self_test),

    .p1_up(p1_up), .p1_down(p1_down), .p1_left(p1_left), .p1_right(p1_right),
    .p1_fire1(p1_fire1), .p1_fire2(p1_fire2),
    .p1_start(p1_start), .p1_coin(p1_coin),
    .p2_up(p2_up), .p2_down(p2_down), .p2_left(p2_left), .p2_right(p2_right),
    .p2_fire1(p2_fire1), .p2_fire2(p2_fire2),
    .p2_start(p2_start), .p2_coin(p2_coin),

    .dip_sw0(dip_sw0), .dip_sw1(dip_sw1),
    .dip_sw2(dip_sw2), .dip_sw3(dip_sw3),

    .vblank_in     (vblank_i),

    .ioctl_addr    (ioctl_addr),
    .ioctl_wr      (ioctl_wr),
    .ioctl_data    (ioctl_data),
    .ioctl_index   (ioctl_index),

    .m1_o          (cpu_m1),
    .mreq_o        (cpu_mreq),
    .iorq_o        (cpu_iorq),
    .rd_o          (cpu_rd),
    .wr_o          (cpu_wr),
    .addr_o        (cpu_addr),
    .dout_o        (cpu_dout),
    .din_i         (cpu_din),

    .hs_address    (hs_address),
    .hs_data_in    (hs_data_in),
    .hs_data_out   (hs_data_out),
    .hs_write      (hs_write),
    .ce_pix_o            (ce_pix_i),
    .vram_addr_o         (cpu_vram_addr),
    .vram_din_o          (cpu_vram_din),
    .vram_wr_o           (cpu_vram_wr),
    .vidram_din_i        (vidram_to_cpu),
    .video_control_1_o   (vc1),
    .video_control_6_o   (vc6),
    .mb_snd_cmd_o        (mb_snd_cmd),
    .mb_snd_busy_i       (mb_snd_busy),
    .video_flip_o        (vflip),
    .video_control_3_o   (vc3),
    .bg_scrollx_o        (bg_scrollx),
    .bg_scrolly_o        (bg_scrolly),
    .bg_enable_o         (bg_enable),
    .bg_char_bank_o      (bg_char_bank),
    .audio_we_o          (audio_we),
    .audio_addr_o        (audio_addr_w),
    .audio_din_o         (audio_din_w),
    .ce_cpu_o            (ce_cpu_s),
    .speech_data_we_o    (speech_data_we),
    .speech_ctrl_we_o    (speech_ctrl_we),
    .usb_data_wr_o       (usb_data_wr),
    .usb_din_o           (usb_din),
    .usb_status_i        (usb_status),
    .usb_pgm_addr_o      (usb_pgm_addr),
    .usb_pgm_din_o       (usb_pgm_din),
    .usb_pgm_wr_o        (usb_pgm_wr),
    .usb_pgm_dout_i      (usb_pgm_dout),
    .so_port_wr_o        (so_port_wr),
    .so_port_addr_o      (so_port_addr),
    .so_port_din_o       (so_port_din),
    .so_port_dout_i      (so_port_dout),
    .mb_music_wr_o       (mb_music_wr),
    .mb_music_din_o      (mb_music_din),
    .sm_snd_wr_o         (sm_snd_wr),
    .sm_snd_din_o        (sm_snd_din),
    .sm_ppi_pc_wr_o      (sm_ppi_pc_wr),
    .sm_ppi_pc_din_o     (sm_ppi_pc_din),
    .s5_ppi_wr_o         (s5_ppi_wr),
    .s5_ppi_addr_o       (s5_ppi_addr),
    .s5_ppi_din_o        (s5_ppi_din)
);

segag80_spaceod_bg spaceod_bg_inst (
    .rom6_a(rom6_a), .rom6_d(rom6_d), .rom7_a(rom7_a), .rom7_d(rom7_d),
    .clk          (clk_sys),
    .reset        (reset),
    .ce_pix       (ce_pix_i),
    .h_cnt        (vtg_h),
    .v_cnt        (vtg_v),
    .port_wr      (so_port_wr),
    .port_addr    (so_port_addr),
    .port_din     (so_port_din),
    .port_dout    (so_port_dout),
    .detect_set   (so_detect_set),
    .bg_color6    (so_color6),
    .bg_raw6      (so_raw6),
    .bg_show      (so_show)
);

sega_usb #(.CLK_HZ(15_468_480)) usb_inst (
    .pgm_pr_i(pr_i[3]), .pgm_pr_o(pr_o[3]), .work_pr_i(pr_i[4]), .work_pr_o(pr_o[4]),
    .i8035_i    (usb_i8035_i),
    .i8035_o    (i8035_0_o),
    .clk        (clk_sys),
    .reset      (reset | ~usb_en),
    .data_wr    (usb_data_wr),
    .din        (usb_din),
    .status     (usb_status),
    .pgm_addr   (usb_pgm_addr),
    .pgm_din    (usb_pgm_din),
    .pgm_wr     (usb_pgm_wr),
    .pgm_dout   (usb_pgm_dout),
    .audio      (usb_sample),
    .dbg_tick   (),
    .dbg_noise  (),
    .dbg_tmr    (),
    .dbg_cfg    (),
    .dbg_env    ()
);

segag80_vtg vtg (
    .clk    (clk_sys),
    .reset  (reset),
    .ce_pix (ce_pix_i),
    .h_center (h_center),
    .v_center (v_center),
    .h_cnt  (vtg_h),
    .v_cnt  (vtg_v),
    .hblank (hblank_i),
    .vblank (vblank_i),
    .hsync  (hsync_i),
    .vsync  (vsync_i)
);

segag80_bg bg_inst (
    .rom3_a(rom3_a), .rom3_d(rom3_d), .rom4_a(rom4_a), .rom4_d(rom4_d), .rom5_a(rom5_a), .rom5_d(rom5_d),
    .clk              (clk_sys),
    .ce_pix           (ce_pix_i),
    .h_cnt            (vtg_h),
    .v_cnt            (vtg_v),
    .bg_scrollx       (bg_scrollx),
    .bg_scrolly       (bg_scrolly),
    .bg_char_bank     (bg_char_bank),
    .bg_flip          (vc3 ^ crt_flip),
    .mb_mode          (mb_board),
    .sm_mode          (sm_board),
    .bg_color         (bg_color),
    .bg_pix           (bg_pix)
);

segag80_video video_inst (
    .vram_pr_i(pr_i[1]), .vram_pr_o(pr_o[1]),
    .clk              (clk_sys),
    .reset            (reset),
    .cpu_addr         (cpu_vram_addr),
    .cpu_din          (cpu_vram_din),
    .cpu_wr           (cpu_vram_wr),
    .video_control_1  (vc1),
    .video_control_6  (vc6),
    .video_flip       (vflip ^ crt_flip),
    .bg_board         (bg_board),
    .mb_board         (mb_board),
    .sm_board         (sm_board),
    .bg_enable        (bg_enable),
    .bg_color         (bg_color),
    .bg_pix           (bg_pix),
    .so_board         (so_board),
    .so_show          (so_show),
    .so_color6        (so_color6),
    .so_raw6          (so_raw6),
    .so_detect_set    (so_detect_set),
    .ce_pix           (ce_pix_i),
    .h_cnt            (vtg_h),
    .v_cnt            (vtg_v),
    .r_out            (pix_r8),
    .g_out            (pix_g8),
    .b_out            (pix_b8),
    .cpu_dout         (vidram_to_cpu)
);

wire signed [15:0] astrob_sample;

astrob_audio audio_inst (
    .clk_sys    (clk_sys),
    .reset      (reset),
    .audio_we   (audio_we),
    .audio_addr (audio_addr_w),
    .audio_din  (audio_din_w),
    .ce_cpu     (ce_cpu_s),
    .audio_out  (astrob_sample)
);

assign rom1_a          = speech_cpu_addr;
assign speech_cpu_data = rom1_d;
assign rom2_a          = speech_data_addr[12:0];
reg    speech_data_upper_q;
always @(posedge clk_sys) speech_data_upper_q <= speech_data_addr[13];
assign speech_data_data = speech_data_upper_q ? 8'h00 : rom2_d;

segaspeech u_segaspeech (
    .mcs48_0_i(mcs48_0_i), .mcs48_0_o(mcs48_0_o), .sp0250_0_i(sp0250_0_i), .sp0250_0_o(sp0250_0_o),
    .clk              (clk_sys),
    .reset_n          (~reset),
    .data_w           (audio_din_w),
    .data_we          (speech_data_we),
    .ctrl_w           (audio_din_w),
    .ctrl_we          (speech_ctrl_we),
    .rom_8035_addr    (speech_cpu_addr),
    .rom_8035_data    (speech_cpu_data),
    .rom_speech_addr  (speech_data_addr),
    .rom_speech_data  (speech_data_data),
    .audio_out        (speech_sample),
    .audio_valid      (speech_valid)
);

assign video_hsync  = hsync_i;
assign video_vsync  = vsync_i;
assign video_hblank = hblank_i;
assign video_vblank = vblank_i;
assign ce_pix       = ce_pix_i;
assign video_r      = pix_r8;
assign video_g      = pix_g8;
assign video_b      = pix_b8;
wire signed [17:0] mix_sum = $signed({{2{astrob_sample[15]}}, astrob_sample})
                           + $signed({{2{speech_sample[15]}},  speech_sample});
wire signed [16:0] mixed   = mix_sum[17:1];

localparam USB_GAIN_LOG2 = 2;

localparam MBV_GAIN_LOG2 = 1;

monsterb_voice #(.CLK_HZ(15_468_480), .GAIN_LOG2(0)) mb_voice_inst (
    .rom11_a(rom11_a), .rom11_d(rom11_d), .rom12_a(rom12_a), .rom12_d(rom12_d),
    .i8035_i    (mbv_i8035_i),
    .i8035_o    (i8035_0_o),
    .clk        (clk_sys),
    .reset      (reset),
    .cmd_w      (mb_snd_cmd),
    .busy       (mb_snd_busy),
    .audio      (mb_voice_sample)
);

localparam SOD_GAIN_LOG2 = 0;

wire signed [15:0] spaceod_sample;

spaceod_sound_io #(.CLK_HZ(15_468_480)) spaceod_snd_inst (
    .clk        (clk_sys),
    .reset      (reset),
    .db         (so_port_din),
    .wr_ck0     (so_port_wr & (so_port_addr == 3'd7)),
    .wr_ck1     (so_port_wr & (so_port_addr == 3'd6)),
    .enable     (so_board),
    .audio      (spaceod_sample),
    .ce_snd     ()
);

localparam MBM_GAIN_LOG2 = 0;

wire signed [15:0] mb_music_sample;

monsterb_music #(.CLK_HZ(15_468_480)) mb_music_inst (
    .tms36xx_0_i (tms36xx_0_i),
    .tms36xx_0_o (tms36xx_0_o),
    .clk         (clk_sys),
    .reset       (reset),
    .port_a_wr   (mb_music_wr),
    .port_a_din  (mb_music_din),
    .ioctl_addr  (ioctl_addr[4:0]),
    .ioctl_data  (ioctl_data),
    .ioctl_wr    (ioctl_wr & (ioctl_index == 8'd4)),
    .audio       (mb_music_sample)
);

localparam SM_GAIN_LOG2 = 4;

wire signed [15:0] sindbadm_sample;

sindbadm_sound #(.CLK_HZ(15_468_480), .GAIN_LOG2(SM_GAIN_LOG2)) sindbadm_snd_inst (
    .rom8_a(rom8_a), .rom8_d(rom8_d), .ram_pr_i(pr_i[2]), .ram_pr_o(pr_o[2]),
    .z80_1_i(z80_1_i), .z80_1_o(z80_1_o), .sn76489_i(sn76489_i), .sn76489_o(sn76489_o),
    .clk        (clk_sys),
    .reset      (reset),
    .latch_wr   (sm_snd_wr),
    .latch_din  (sm_snd_din),
    .pc_wr      (sm_ppi_pc_wr),
    .pc_din     (sm_ppi_pc_din),
    .audio      (sindbadm_sample)
);

localparam S5_GAIN_LOG2 = 0;

wire signed [15:0] sega005_sample;

sega005_sound #(.CLK_HZ(15_468_480)) sega005_snd_inst (
    .rom9_a(rom9_a), .rom9_d(rom9_d), .rom10_a(rom10_a), .rom10_d(rom10_d),
    .clk        (clk_sys),
    .reset      (reset),
    .ppi_wr     (s5_ppi_wr),
    .ppi_addr   (s5_ppi_addr),
    .ppi_din    (s5_ppi_din),
    .audio      (sega005_sample)
);

wire signed [15:0] usb_mix    = usb_en ? usb_sample : 16'sd0;
wire signed [19:0] usb_scaled = $signed({{4{usb_mix[15]}}, usb_mix}) <<< USB_GAIN_LOG2;
wire signed [15:0] mbv_mix    = mb_board ? mb_voice_sample : 16'sd0;
wire signed [19:0] mbv_scaled = $signed({{4{mbv_mix[15]}}, mbv_mix}) <<< MBV_GAIN_LOG2;
wire signed [15:0] sod_mix    = so_board ? spaceod_sample : 16'sd0;
wire signed [19:0] sod_scaled = $signed({{4{sod_mix[15]}}, sod_mix});
wire signed [19:0] smx_mix    = sm_board ? $signed({{4{sindbadm_sample[15]}}, sindbadm_sample})
                                         : 20'sd0;
wire signed [15:0] mbm_mix    = mb_board ? mb_music_sample : 16'sd0;
wire signed [19:0] mbm_scaled = $signed({{4{mbm_mix[15]}}, mbm_mix}) <<< MBM_GAIN_LOG2;
wire signed [15:0] s5_mix     = s5_board ? sega005_sample : 16'sd0;
wire signed [19:0] s5_scaled  = $signed({{4{s5_mix[15]}}, s5_mix}) <<< S5_GAIN_LOG2;
wire signed [19:0] mix_all    = $signed({{3{mixed[16]}}, mixed}) + usb_scaled + mbv_scaled
                              + (sod_scaled <<< SOD_GAIN_LOG2) + smx_mix + mbm_scaled
                              + s5_scaled;

assign audio_out = pause ? 16'sd0 :
    (mix_all >  20'sd32767) ?  16'sd32767 :
    (mix_all < -20'sd32768) ? -16'sd32768 :
                               mix_all[15:0];

assign cpu_din = 8'hFF;

endmodule
