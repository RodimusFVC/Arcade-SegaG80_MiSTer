//============================================================================
//
//  Sega G-80 top-level module
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r.cpp / segag80r_v.cpp / segag80_m.cpp
//
//  This is the platform scaffold. CPU/ROM/video/audio guts are filled in by
//  T1.2–T2.2. For now, stubs drive outputs to safe values so the module
//  parses and simulates.
//
//============================================================================

module SegaG80 #(
    parameter [1:0] GAME_ID = 2'd0    // 0=ASTROB, 1=MONSTERB, 2=SPACEOD, 3=rsvd
) (
    input                reset,
    input                clk_sys,      // 15.468480 MHz (MAME VIDEO_CLOCK)

    // Player 1 controls (active HIGH)
    input                p1_up, p1_down, p1_left, p1_right,
    input                p1_fire1, p1_fire2,
    input                p1_start, p1_coin,

    // Player 2 controls (active HIGH)
    input                p2_up, p2_down, p2_left, p2_right,
    input                p2_fire1, p2_fire2,
    input                p2_start, p2_coin,

    input                service,      // edge triggers Z80 NMI

    // DIP banks (active-LOW per MAME)
    input          [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3,

    // Video
    output               video_hsync, video_vsync,
    output               video_hblank, video_vblank,
    output               ce_pix,
    output         [7:0] video_r, video_g, video_b,

    // Audio (mono)
    output signed [15:0] audio_out,

    // ROM loading
    input         [24:0] ioctl_addr,
    input                ioctl_wr,
    input          [7:0] ioctl_data,
    input          [7:0] ioctl_index,

    input                pause,

    // Hiscore
    input         [15:0] hs_address,
    input          [7:0] hs_data_in,
    output         [7:0] hs_data_out,
    input                hs_write
);

//----------------------------------------------------------------------------
// Internal buses (driven by sub-modules in later tasks)
//----------------------------------------------------------------------------
wire        cpu_m1;          // Z80 M1
wire        cpu_mreq;
wire        cpu_iorq;
wire        cpu_rd;
wire        cpu_wr;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
wire  [7:0] cpu_din;         // to Z80

// Video timing signals from T1.4
wire        hblank_i, vblank_i, hsync_i, vsync_i;
wire        ce_pix_i;
wire [8:0]  vtg_h, vtg_v;

// Videoram bus between CPU and video block
wire [12:0] cpu_vram_addr;
wire  [7:0] cpu_vram_din;
wire        cpu_vram_wr;
wire  [7:0] vidram_to_cpu;
wire        vc1;
wire        vflip;

// Videoram/palette output from T1.5
wire  [7:0] pix_r8, pix_g8, pix_b8;

// Audio from T2.2
wire signed [15:0] snd_out;

// Audio bus between CPU and astrob_audio
wire        audio_we, audio_addr_w, ce_cpu_s;
wire  [7:0] audio_din_w;

//----------------------------------------------------------------------------
// CPU + ROM + address decode (T1.2 fills this in)
//----------------------------------------------------------------------------
SegaG80_CPU #(
    .GAME_ID (GAME_ID)
) cpu_board (
    .reset         (reset),
    .clk_sys       (clk_sys),
    .pause         (pause),
    .service       (service),

    .p1_up(p1_up), .p1_down(p1_down), .p1_left(p1_left), .p1_right(p1_right),
    .p1_fire1(p1_fire1), .p1_fire2(p1_fire2),
    .p1_start(p1_start), .p1_coin(p1_coin),
    .p2_up(p2_up), .p2_down(p2_down), .p2_left(p2_left), .p2_right(p2_right),
    .p2_fire1(p2_fire1), .p2_fire2(p2_fire2),
    .p2_start(p2_start), .p2_coin(p2_coin),

    .dip_sw0(dip_sw0), .dip_sw1(dip_sw1),
    .dip_sw2(dip_sw2), .dip_sw3(dip_sw3),

    // Video signals produced by the video section (below) flow back in to
    // the CPU for the vblank_latch read on port $BF.
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
    .video_flip_o        (vflip),
    .audio_we_o          (audio_we),
    .audio_addr_o        (audio_addr_w),
    .audio_din_o         (audio_din_w),
    .ce_cpu_o            (ce_cpu_s)
);

//----------------------------------------------------------------------------
// Video timing (T1.4 fills this in)
//----------------------------------------------------------------------------
// Pixel clock enable sourced from CPU /3 divider.
// (ce_pix_o is an added output on SegaG80_CPU — see T1.4 Edit 2a.)
// ce_pix_i is the signal surfaced through the SegaG80_CPU instantiation.
segag80_vtg vtg (
    .clk    (clk_sys),
    .reset  (reset),
    .ce_pix (ce_pix_i),
    .h_cnt  (vtg_h),
    .v_cnt  (vtg_v),
    .hblank (hblank_i),
    .vblank (vblank_i),
    .hsync  (hsync_i),
    .vsync  (vsync_i)
);

//----------------------------------------------------------------------------
// Videoram + tilemap + palette
//----------------------------------------------------------------------------
segag80_video video_inst (
    .clk              (clk_sys),
    .reset            (reset),
    .cpu_addr         (cpu_vram_addr),
    .cpu_din          (cpu_vram_din),
    .cpu_wr           (cpu_vram_wr),
    .video_control_1  (vc1),
    .video_flip       (vflip),
    .ce_pix           (ce_pix_i),
    .h_cnt            (vtg_h),
    .v_cnt            (vtg_v),
    .r_out            (pix_r8),
    .g_out            (pix_g8),
    .b_out            (pix_b8),
    .cpu_dout         (vidram_to_cpu)
);

//----------------------------------------------------------------------------
// Audio — Astro Blaster simplified approximation
//----------------------------------------------------------------------------
astrob_audio audio_inst (
    .clk_sys    (clk_sys),
    .reset      (reset),
    .audio_we   (audio_we),
    .audio_addr (audio_addr_w),
    .audio_din  (audio_din_w),
    .ce_cpu     (ce_cpu_s),
    .audio_out  (snd_out)
);

//----------------------------------------------------------------------------
// Output assignments
//----------------------------------------------------------------------------
assign video_hsync  = hsync_i;
assign video_vsync  = vsync_i;
assign video_hblank = hblank_i;
assign video_vblank = vblank_i;
assign ce_pix       = ce_pix_i;
assign video_r      = pix_r8;
assign video_g      = pix_g8;
assign video_b      = pix_b8;
assign audio_out    = snd_out;

// CPU data-in tied off until T1.2 wires the bus (this will be removed by T1.2).
assign cpu_din = 8'hFF;

endmodule
