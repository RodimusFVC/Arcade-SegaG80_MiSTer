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

module SegaG80 (
    input                reset,
    input                clk_sys,      // 15.468480 MHz (MAME VIDEO_CLOCK)
    input          [2:0] game_id,      // 0=ASTROB,1=MONSTERB,2=SPACEOD,3=005,4=SINDBADM,5=PIGNEWT

    // Player 1 controls (active HIGH)
    input                p1_up, p1_down, p1_left, p1_right,
    input                p1_fire1, p1_fire2,
    input                p1_start, p1_coin,

    // Player 2 controls (active HIGH)
    input                p2_up, p2_down, p2_left, p2_right,
    input                p2_fire1, p2_fire2,
    input                p2_start, p2_coin,

    input                service,      // edge triggers Z80 NMI

    // CRT Flip override (status[22] at the Arcade-SegaG80.sv level). XOR'd
    // with the game's native video_flip cocktail bit in segag80_video.sv.
    input                flip_vertical,

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
    input                hs_write,

    // DIAG-REVERT-2026-05-28: speech command-path activity (-> parent status LEDs)
    output               dbg_speech_sent,
    output               dbg_speech_ack
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

// Audio bus between CPU and astrob_audio
wire        audio_we, audio_addr_w, ce_cpu_s;
wire  [7:0] audio_din_w;

// Speech board control surface
wire        speech_data_we;
wire        speech_ctrl_we;

// Speech ROM interfaces
wire [10:0] speech_cpu_addr;
wire  [7:0] speech_cpu_data;
wire [13:0] speech_data_addr;
wire  [7:0] speech_data_data;

// Speech audio output
wire signed [15:0] speech_sample;
wire               speech_valid;

//----------------------------------------------------------------------------
// CPU + ROM + address decode (T1.2 fills this in)
//----------------------------------------------------------------------------
SegaG80_CPU cpu_board (
    .game_id       (game_id),
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
    .ce_cpu_o            (ce_cpu_s),
    .speech_data_we_o    (speech_data_we),
    .speech_ctrl_we_o    (speech_ctrl_we)
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
    .flip_vertical    (flip_vertical),
    .ce_pix           (ce_pix_i),
    .h_cnt            (vtg_h),
    .v_cnt            (vtg_v),
    .r_out            (pix_r8),
    .g_out            (pix_g8),
    .b_out            (pix_b8),
    .cpu_dout         (vidram_to_cpu)
);

//----------------------------------------------------------------------------
// Audio — Astro Blaster synthesized effects
//----------------------------------------------------------------------------
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

//----------------------------------------------------------------------------
// Speech board (Sega 315-0061 daughterboard — 8035 + SP0250)
//----------------------------------------------------------------------------

// ioctl index selectors (MRA layout: game_id=index1, main_cpu=index0,
//   speech_cpu=index2, speech_data=index3).
wire ioctl_speech_cpu_sel  = (ioctl_index == 8'd2);
wire ioctl_speech_data_sel = (ioctl_index == 8'd3);

// 8035 program ROM — 2 KB
speech_cpu_rom u_speech_cpu_rom (
    .clk          (clk_sys),
    .ioctl_addr   (ioctl_addr[10:0]),
    .ioctl_data   (ioctl_data),
    .ioctl_wr     (ioctl_wr & ioctl_speech_cpu_sel),
    .cpu_addr     (speech_cpu_addr),
    .cpu_data     (speech_cpu_data)
);

// Speech data ROM — 8 KB populated (809a/810/811/812a)
// ioctl_index=3 resets ioctl_addr to 0 at start of transfer, so no offset needed.
wire [12:0] speech_data_wr_addr = ioctl_addr[12:0];

speech_data_rom u_speech_data_rom (
    .clk          (clk_sys),
    .ioctl_addr   (speech_data_wr_addr),
    .ioctl_data   (ioctl_data),
    .ioctl_wr     (ioctl_wr & ioctl_speech_data_sel),
    .cpu_addr     (speech_data_addr),
    .cpu_data     (speech_data_data)
);

segaspeech u_segaspeech (
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
    .audio_valid      (speech_valid),
    // DIAG-REVERT-2026-05-28: command-path activity LEDs
    .dbg_cmd_sent     (dbg_speech_sent),
    .dbg_cmd_ack      (dbg_speech_ack)
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
// Mix: astrob_audio (full gain) + speech (half gain per MAME vol balance).
// `pause` reaches this module already (gates the CPU below) but was never
// used for audio -- astrob_audio's oscillators run on clk_sys directly, not
// ce_cpu, so a paused CPU (no new port writes) does NOT stop an
// already-gated-on voice from continuing to oscillate and sound. Muting the
// final mix here covers both astrob_audio and speech in one place, no
// module port changes needed anywhere. Fixed 2026-07-26.
wire signed [15:0] speech_halved = {speech_sample[15], speech_sample[15:1]};
wire signed [16:0] mixed = $signed({astrob_sample[15], astrob_sample})
                         + $signed({speech_halved[15], speech_halved});
assign audio_out = pause ? 16'sd0 :
    (mixed >  17'sd32767) ?  16'sd32767 :
    (mixed < -17'sd32768) ? -16'sd32768 :
                             mixed[15:0];

// CPU data-in tied off until T1.2 wires the bus (this will be removed by T1.2).
assign cpu_din = 8'hFF;

endmodule
