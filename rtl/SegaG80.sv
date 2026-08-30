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
    input                crt_flip,     // OSD CRT Flip; XORed into the video path only
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

    // SELFTEST-SPLIT-2026-08-11: these are TWO different physical switches on
    // a real cabinet -- see AstroBlaster manual p.14 ("red self-test switch
    // located on the CPU board") vs p.10 ("U9 is the input port for the coin
    // switches and service switch"). MAME models them as two separate ports:
    // segag80r.cpp:643 IPT_SERVICE1 (a port bit, MAME default key 9) and
    // segag80r.cpp:708 SERVICESW / PORT_SERVICE_NO_TOGGLE (NMI, MAME key F2,
    // never read as a port). They were previously collapsed onto one signal,
    // so no key could assert self-test without also adding a service credit.
    input                service,      // service CREDIT -> SERVICE1 port bit
    input                self_test,    // CPU-board switch, edge -> Z80 NMI

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
wire        vc6;
wire        vflip;

// Background board (Pig Newton / Sindbad Mystery)
wire        vc3;
wire  [9:0] bg_scrollx;
wire [10:0] bg_scrolly;
wire        bg_enable;
wire  [3:0] bg_char_bank;
wire  [3:0] bg_color;
wire  [1:0] bg_pix;

// game_id 5 = PIGNEWT — the only background board wired up so far.
wire        mb_board = (game_id == 3'd1);   // Monster Bash
wire        sm_board = (game_id == 3'd4);   // Sindbad Mystery
wire        bg_board = (game_id == 3'd5) | mb_board | sm_board;

// Space Odyssey background board — game_id 2.
wire        so_board = (game_id == 3'd2);
wire        mb_music_wr;
wire  [7:0] mb_music_din;
wire        sm_snd_wr, sm_ppi_pc_wr;
wire  [7:0] sm_snd_din, sm_ppi_pc_din;
wire        s5_board = (game_id == 3'd3);   // 005
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

// Sega Universal Sound Board — Pig Newton only.
wire        usb_en = (game_id == 3'd5);
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
    .self_test     (self_test),

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

//----------------------------------------------------------------------------
// Space Odyssey background board — gfx1 at ioctl index 7, gfx2 at index 8.
//----------------------------------------------------------------------------
segag80_spaceod_bg spaceod_bg_inst (
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
    .ioctl_addr   (ioctl_addr),
    .ioctl_data   (ioctl_data),
    .ioctl_wr     (ioctl_wr),
    .sel_tiles    (ioctl_index == 8'd7),
    .sel_map      (ioctl_index == 8'd8),
    .bg_color6    (so_color6),
    .bg_raw6      (so_raw6),
    .bg_show      (so_show)
);

//----------------------------------------------------------------------------
// Sega Universal Sound Board (drawing 800-0377) — Pig Newton.
// From the Arcade-SegaG80V core; the board carries no ROM of its own, the
// main Z80 uploads the 8035 program through the $D000-$DFFF window.
// Held in reset on every other game: in_latch resets to 0, which would
// otherwise release the 8035 to run against empty program RAM.
//----------------------------------------------------------------------------
sega_usb #(.CLK_HZ(15_468_480)) usb_inst (
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
// Background board — gfx1 tiles at ioctl index 7, gfx2 tilemap at index 8.
segag80_bg bg_inst (
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
    .ioctl_addr       (ioctl_addr),
    .ioctl_data       (ioctl_data),
    .ioctl_wr         (ioctl_wr),
    .sel_tiles        (ioctl_index == 8'd7),
    .sel_map          (ioctl_index == 8'd8),
    .bg_color         (bg_color),
    .bg_pix           (bg_pix)
);

segag80_video video_inst (
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
// Mix: astrob_audio + speech at EQUAL gain, then 0.5 on the sum.
//
// LEVEL FIX 2026-08-09 — the old comment ("speech at half gain per MAME vol
// balance") misread MAME. segag80r.cpp:1085-86 is:
//     ASTRO_BLASTER_AUDIO(...).add_route(ALL_OUTPUTS, "speech", 1.0, 1);
//     SEGA_SPEECH_BOARD(...).add_route(ALL_OUTPUTS, "speaker", 0.5);
// The sound board does NOT route to the speaker -- it routes INTO the speech
// board at gain 1.0, and the speech board's COMBINED output hits the speaker
// at 0.5. Speech itself is 1.0 internally (segaspeech.cpp:207/218). So the 0.5
// is a MASTER on the sum, not an attenuation of speech. Applying it to the
// speech leg alone put the voice 6 dB under the sound board -- user on HW:
// "voice is low, invaders are blaring."
// Net effect of this fix: speech absolute level UNCHANGED, invaders -6 dB.
// `pause` reaches this module already (gates the CPU below) but was never
// used for audio -- astrob_audio's oscillators run on clk_sys directly, not
// ce_cpu, so a paused CPU (no new port writes) does NOT stop an
// already-gated-on voice from continuing to oscillate and sound. Muting the
// final mix here covers both astrob_audio and speech in one place, no
// module port changes needed anywhere. Fixed 2026-07-26.
// LEVELFIX-REVERT-2026-08-09: original speech-halved mix below, uncomment to restore
// wire signed [15:0] speech_halved = {speech_sample[15], speech_sample[15:1]};
// wire signed [16:0] mixed = $signed({astrob_sample[15], astrob_sample})
//                          + $signed({speech_halved[15], speech_halved});
wire signed [17:0] mix_sum = $signed({{2{astrob_sample[15]}}, astrob_sample})
                           + $signed({{2{speech_sample[15]}},  speech_sample});
wire signed [16:0] mixed   = mix_sum[17:1];   // master 0.5 on the SUM, per MAME

// The USB board is exclusive to Pig Newton, where astrob_audio and speech are
// both silent, so it is summed instead of sharing the 0.5 master.
// Explicitly muted off-game so nothing can leak into Astro Blaster's mix.
//
// Output level: the SegaG80V core sums this board at unity, but on Pig Newton
// it lands far below a usable level. Adjust this one constant by ear — 2 = 4x,
// 3 = 8x, 0 = the vector core's unity. The clamp below catches overshoot.
localparam USB_GAIN_LOG2 = 2;

//----------------------------------------------------------------------------
// Monster Bash uPD7751 voice board. Summed as its own leg, muted off-game, so
// the Astro Blaster / speech mix above is untouched.
// Level: adjust by ear — 0 = raw R-2R ladder level, 1 = 2x, 2 = 4x.
//----------------------------------------------------------------------------
localparam MBV_GAIN_LOG2 = 1;

monsterb_voice #(.CLK_HZ(15_468_480), .GAIN_LOG2(0)) mb_voice_inst (
    .clk        (clk_sys),
    .reset      (reset),
    .cmd_w      (mb_snd_cmd),
    .busy       (mb_snd_busy),
    .ioctl_addr (ioctl_addr),
    .ioctl_data (ioctl_data),
    .ioctl_wr   (ioctl_wr),
    .sel_pgm    (ioctl_index == 8'd6),
    .sel_smp    (ioctl_index == 8'd9),
    .audio      (mb_voice_sample)
);

//----------------------------------------------------------------------------
// Space Odyssey discrete sound board (Gremlin/SEGA 834-0051). Trigger latches
// IC43/IC44 are at $0E/$0F, inside the $08-$0F block the background board
// already decodes, so it shares so_port_wr. Summed as its own leg, muted
// off-game. Level: adjust by ear — 0 = the board model's own output level.
//----------------------------------------------------------------------------
localparam SOD_GAIN_LOG2 = 0;

wire signed [15:0] spaceod_sample;

spaceod_sound_io #(.CLK_HZ(15_468_480)) spaceod_snd_inst (
    .clk        (clk_sys),
    .reset      (reset),
    .db         (so_port_din),
    .wr_ck0     (so_port_wr & (so_port_addr == 3'd7)),   // IC44 = $0F
    .wr_ck1     (so_port_wr & (so_port_addr == 3'd6)),   // IC43 = $0E
    .enable     (so_board),
    .audio      (spaceod_sample),
    .ce_snd     ()
);

//----------------------------------------------------------------------------
// Monster Bash music — TMS3617 + the pr1512.u31 82S123 at ioctl index 4.
// Its own leg alongside the uPD7751 voice, muted off-game. MAME routes music
// and the voice DAC at 0.5 each; level here is by ear, like the other boards.
//----------------------------------------------------------------------------
localparam MBM_GAIN_LOG2 = 0;

wire signed [15:0] mb_music_sample;

monsterb_music #(.CLK_HZ(15_468_480)) mb_music_inst (
    .clk         (clk_sys),
    .reset       (reset),
    .port_a_wr   (mb_music_wr),
    .port_a_din  (mb_music_din),
    .ioctl_addr  (ioctl_addr[4:0]),
    .ioctl_data  (ioctl_data),
    .ioctl_wr    (ioctl_wr & (ioctl_index == 8'd4)),
    .audio       (mb_music_sample)
);

//----------------------------------------------------------------------------
// Sindbad Mystery sound board (Sega System 1: Z80 + 2x SN76496/JT89).
// Program ROM is ioctl index 6 — shared with Monster Bash's uPD7751 program,
// which is harmless since only one game's MRA ever loads. Summed as its own
// leg, muted off-game. Level: adjust by ear — 4 puts both chips at full scale.
//----------------------------------------------------------------------------
localparam SM_GAIN_LOG2 = 4;

wire signed [15:0] sindbadm_sample;

sindbadm_sound #(.CLK_HZ(15_468_480), .GAIN_LOG2(SM_GAIN_LOG2)) sindbadm_snd_inst (
    .clk        (clk_sys),
    .reset      (reset),
    .latch_wr   (sm_snd_wr),
    .latch_din  (sm_snd_din),
    .pc_wr      (sm_ppi_pc_wr),
    .pc_din     (sm_ppi_pc_din),
    .ioctl_addr (ioctl_addr[12:0]),
    .ioctl_data (ioctl_data),
    .ioctl_wr   (ioctl_wr & (ioctl_index == 8'd6)),
    .audio      (sindbadm_sample)
);

//----------------------------------------------------------------------------
// 005 discrete sound board (Sega 834-0130) — melody chain plus seven effect
// voices, all synthesized from the schematic. The 2716 tune ROM is at ioctl
// index 5 and the 6331 divisor PROM at index 10. Summed as its own leg, muted
// off-game. Level: adjust by ear — 0 = the board model's own output level.
//----------------------------------------------------------------------------
localparam S5_GAIN_LOG2 = 0;

wire signed [15:0] sega005_sample;

sega005_sound #(.CLK_HZ(15_468_480)) sega005_snd_inst (
    .clk        (clk_sys),
    .reset      (reset),
    .ppi_wr     (s5_ppi_wr),
    .ppi_addr   (s5_ppi_addr),
    .ppi_din    (s5_ppi_din),
    .ioctl_addr (ioctl_addr),
    .ioctl_data (ioctl_data),
    .ioctl_wr   (ioctl_wr),
    .sel_rom    (ioctl_index == 8'd5),
    .sel_prom   (ioctl_index == 8'd10),
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

// CPU data-in tied off until T1.2 wires the bus (this will be removed by T1.2).
assign cpu_din = 8'hFF;

endmodule
