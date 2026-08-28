//============================================================================
//  Sega G-80 X-Y (vector) arcade hardware for MiSTer FPGA
//
//  Eliminator, Space Fury, Zektor, Tac/Scan, Star Trek.
//  Original hardware by Sega/Gremlin, 1981-1982.
//
//  Vector renderer and CRT pipeline by Videodr0me (videodr0me_fb, from
//  Arcade-MajorHavoc_MiSTer). This top level follows that core's structure.
//
//  This program is free software under the GNU General Public License v3.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

	`include "build_id.v"

	logic [127:0] status;
	logic  [31:0] joystick_0;
	logic  [31:0] joystick_1;
	logic  [31:0] joystick_2;
	logic  [31:0] joystick_3;
	logic   [8:0] spinner_0;
	logic   [8:0] spinner_1;
	logic   [1:0] buttons;
	logic         direct_video;
	wire   [21:0] gamma_bus;

	logic         ioctl_download;
	logic         ioctl_wr;
	logic  [26:0] ioctl_addr;
	logic   [7:0] ioctl_dout;
	logic  [15:0] ioctl_index;

	logic clk_vec;      // 12.096 MHz vector-generator / machine domain
	logic clk_125;
	logic clk_50;
	logic pll_locked;
	logic vec_pll_locked;

	logic         video_is_720p;
	logic   [7:0] game_id = 8'd0;

	//============================================================
	// OSD
	//============================================================
	localparam CONF_STR = {
		"SegaG80V;;",
		"-;",
		"P1,Video Options;",
		"P1-;",
		"P1O[15:14],Aspect ratio,Optimized,Stretched,Pixel Perfect;",
		"D0P1O[25],120Hz (720p only),Off,On;",
		"P1O[40:39],Buffer Mode,EOF + VBL,VBL,EOF;",
		"P1O[30:28],Dot Scale,2x,2.5x,3x,1x;",
		"P1-;",
		"P1O[43:41],Bloom Width,Off,1,2,3,4,5,6,7;",
		"P1O[46:44],Bloom Curve,0,1,2,3,4,5,6,7;",
		"P1O[49:47],Halo Filter,Off,1,2,3,4,5,6,7;",
		"P1O[51:50],Halo Spread,Original,Wide,Wider,Widest;",
		"P1O[65:63],Halo Curve,0,1,2,3,4,5,6,7;",
		"P1O[67:66],Halo Knee,0,1,2,3;",
		"P1O[68],Expand Highlights,Off,On;",
		"P1-;",
		"P1O[53:52],Phosphor Decay,Off,LUT A,LUT B,LUT C;",
		"P1O[55:54],Inter-frame Phosphor,Off,LUT A,LUT B,LUT C;",
		"P1O[56],Colour Space,Off,Amplifone;",
		"P1O[59:57],Presentation Colour,Normal,1,2,3,4,5,6,7;",
		"P1O[60],Slot Mask,Off,On;",
		"P1O[61],Slot Mask Rows,Off,On;",
		"P1O[62],Bypass CRT Pipeline,Off,On;",
		"-;",
		"P2,Pause Options;",
		"P2-;",
		"P2O[116],Pause when OSD is open,Off,On;",
		"P2O[117],Dim video after 10s,On,Off;",
		"-;",
		"P3,Core Info;",
		"P3-;",
		"P3-,Sega G-80 X-Y vector core;",
		"P3-;",
		"P3-,Vector renderer and CRT;",
		"P3-,pipeline by Videodr0me.;",
		"P3-;",
		"P3-,Hardware analysis from;",
		"P3-,MAME (Aaron Giles).;",
		"P3-;",
		"P3-,If you enjoy the vector;",
		"P3-,render effects, please;",
		"P3-,support Videodr0me:;",
		"P3-;",
		"P3-,buymeacoffee.com/videodr0me;",
		"-;",
		"DIP;",
		"R[0],Reset;",
		// bits 4..12: fire1..fire4, start1, start2, coin, pause, service
		"J1,Fire,Fire 2,Fire 3,Fire 4,Start 1,Start 2,Coin,Pause,Service;",
		"jn,A,B,X,Y,Start,Select,R,L,;",
		"V,v0.1.", `BUILD_DATE
	};

	hps_io #(.CONF_STR(CONF_STR)) hps_io_inst (
		.clk_sys(clk_vec),
		.HPS_BUS(HPS_BUS),
		.joystick_0(joystick_0),
		.joystick_1(joystick_1),
		.joystick_2(joystick_2),
		.joystick_3(joystick_3),
		.spinner_0(spinner_0),
		.spinner_1(spinner_1),
		.buttons(buttons),
		.forced_scandoubler(),
		.direct_video(direct_video),
		.gamma_bus(gamma_bus),
		.status(status),
		.status_menumask({15'd0, !video_is_720p}),
		.ioctl_download(ioctl_download),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_index(ioctl_index)
	);

	pll pll (
		.refclk(CLK_50M),
		.rst(1'b0),
		.outclk_0(clk_125),
		.outclk_1(),
		.outclk_2(clk_50),
		.locked(pll_locked)
	);

	sega_clocks machine_clocks (
		.refclk(CLK_50M),
		.reset(1'b0),
		.clk_vec(clk_vec),
		.locked(vec_pll_locked)
	);

	//============================================================
	// MRA payload
	//   index 0   : ROM image, $0000-$BFFF program + $C000-$C3FF sin/cos PROM
	//   index 1   : one game-identifier byte
	//   index 254 : DIP switches
	//============================================================
	logic [7:0] dip_switch [0:7];
	initial begin
		dip_switch[0] = 8'hFF;   // SW1
		dip_switch[1] = 8'h33;   // SW2: 1 coin / 1 credit
		dip_switch[2] = 8'hFF;
		dip_switch[3] = 8'hFF;
		dip_switch[4] = 8'hFF;
		dip_switch[5] = 8'hFF;
		dip_switch[6] = 8'hFF;
		dip_switch[7] = 8'hFF;
	end

	always @(posedge clk_vec) begin
		if (ioctl_wr && (ioctl_index == 16'd1))
			game_id <= ioctl_dout;
		if (ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[26:3])
			dip_switch[ioctl_addr[2:0]] <= ioctl_dout;
	end

	wire rom_download     = ioctl_download && (ioctl_index == 16'd0);
	wire variant_download = ioctl_download && (ioctl_index == 16'd1);
	wire machine_reset    = RESET || status[0] || buttons[1] ||
	                        rom_download || variant_download ||
	                        !pll_locked || !vec_pll_locked;

	//============================================================
	// Machine
	//============================================================
	wire [2:0] game = game_id[2:0];
	wire [2:0] cfg_chip;
	wire       cfg_usb;
	wire       cfg_speech;
	wire [1:0] cfg_fc;
	wire [2:0] cfg_orient;

	sega_game_cfg gamecfg (
		.game(game), .cfg_chip(cfg_chip), .cfg_usb(cfg_usb),
		.cfg_speech(cfg_speech), .cfg_fc(cfg_fc), .cfg_orient(cfg_orient)
	);

	wire [7:0] in_d7d6, in_d5d4, in_d3d2, in_d1d0, in_fc, in_coins;
	wire       coin_a, coin_b, service;

	sega_inputs inputs (
		.game(game),
		.joy1(joystick_0), .joy2(joystick_1),
		.joy3(joystick_2), .joy4(joystick_3),
		.dsw1(dip_switch[0]), .dsw2(dip_switch[1]),
		.in_d7d6(in_d7d6), .in_d5d4(in_d5d4),
		.in_d3d2(in_d3d2), .in_d1d0(in_d1d0),
		.in_fc(in_fc), .in_coins(in_coins),
		.coin_a(coin_a), .coin_b(coin_b), .service(service)
	);

	// Spinner (Zektor, Tac/Scan, Star Trek).
	//
	// hps_io toggles spinner_N[8] on every update and puts a signed delta in
	// [7:0], so the toggle is the strobe. The d-pad is folded in as a fallback
	// for pads without a spinner or mouse: holding left/right emits a small
	// delta at a fixed rate.
	logic signed [7:0] spin_delta;
	logic              spin_stb;
	logic              spin_tog_d;
	logic       [15:0] spin_div;

	wire spin_tog = spinner_0[8] ^ spinner_1[8];
	wire signed [8:0] spin_sum =
		$signed({spinner_0[7], spinner_0[7:0]}) +
		$signed({spinner_1[7], spinner_1[7:0]});

	wire dpad_l = joystick_0[1] | joystick_1[1];
	wire dpad_r = joystick_0[0] | joystick_1[0];

	always_ff @(posedge clk_vec) begin
		spin_stb   <= 1'b0;
		spin_tog_d <= spin_tog;
		spin_div   <= spin_div + 16'd1;

		if (spin_tog != spin_tog_d) begin
			// real spinner or mouse movement
			spin_delta <= spin_sum[8] ? 8'sd127 : spin_sum[7:0];
			spin_stb   <= 1'b1;
		end else if (spin_div == 16'd0 && (dpad_l ^ dpad_r)) begin
			spin_delta <= dpad_r ? 8'sd3 : -8'sd3;
			spin_stb   <= 1'b1;
		end
	end

	logic pause_cpu;
	logic [23:0] paused_rgb;
	wire  [7:0] raw_video_r, raw_video_g, raw_video_b;

	pause #(8, 8, 8, 12) pause_inst (
		.clk_sys(clk_vec),
		.reset(machine_reset),
		.user_button(joystick_0[11] | joystick_1[11]),   // pause
		.pause_request(1'b0),
		.options({~status[117], status[116]}),
		.OSD_STATUS(OSD_STATUS),
		.r(raw_video_r), .g(raw_video_g), .b(raw_video_b),
		.pause_cpu(pause_cpu),
		.rgb_out(paused_rgb)
	);

	wire signed [15:0] audio_ay;
	wire signed [15:0] audio_speech;
	wire signed [15:0] audio_usb;
	wire signed [15:0] audio_discrete;
	wire       vec_tick;
	wire [9:0] vec_x, vec_y;
	wire [5:0] vec_colour;
	wire       vec_beam, vec_valid, vec_frame_done, drawing;

	segag80v machine (
		.clk_vec(clk_vec),
		.reset(machine_reset),
		.pause(pause_cpu),
		.cfg_chip(cfg_chip), .cfg_usb(cfg_usb), .cfg_speech(cfg_speech),
		.cfg_game(game),
		.cfg_fc(cfg_fc),
		.rom_wr(ioctl_wr && rom_download),
		.rom_addr(ioctl_addr[16:0]),
		.rom_data(ioctl_dout),
		.in_d7d6(in_d7d6), .in_d5d4(in_d5d4),
		.in_d3d2(in_d3d2), .in_d1d0(in_d1d0),
		.in_fc(in_fc), .in_coins(in_coins),
		.spin_delta(spin_delta), .spin_stb(spin_stb),
		.coin_a(coin_a), .coin_b(coin_b), .service(service),
		.vec_x(vec_x), .vec_y(vec_y), .vec_colour(vec_colour),
		.vec_beam(vec_beam), .vec_valid(vec_valid),
		.drawing(drawing), .frame_done(vec_frame_done), .vec_tick(vec_tick),
		.snd_wr(), .snd_sel(), .ay_wr(), .ay_port(),
		.speech_data_wr(), .speech_ctrl_wr(), .usb_data_wr(), .snd_data(),
		.audio_ay(audio_ay), .audio_speech(audio_speech), .audio_usb(audio_usb),
		.audio_discrete(audio_discrete),
		.dbg_usb_tick(), .dbg_usb_noise(), .dbg_usb_tmr(),
		.dbg_usb_cfg(), .dbg_usb_env(),
		.dbg_sp_prog_addr(), .dbg_sp_wr(), .dbg_sp_data(), .dbg_sp_drq(),
		.dbg_sp_t0(), .dbg_sp_p1(), .dbg_sp_rd_n(), .dbg_sp_data_addr(),
		.dbg_sp_int_n(), .dbg_sp_dac(), .coin_counter(),
		.dbg_irq(), .dbg_coin_ff(), .dbg_int_ack()
	);

	//============================================================
	// Video
	//============================================================
	logic sdram_data_oe;
	logic [15:0] sdram_data_out;
	logic  [1:0] sdram_dqm;
	logic video_hblank, video_vblank;
	logic fifo_full;

	assign SDRAM_CLK  = ~clk_125;
	assign SDRAM_DQ   = sdram_data_oe ? sdram_data_out : 16'hzzzz;
	assign SDRAM_DQML = sdram_dqm[0];
	assign SDRAM_DQMH = sdram_dqm[1];

	sega_video video (
		.clk_vec(clk_vec),
		.vec_tick(vec_tick),
		.clk_125(clk_125),
		.reset(machine_reset),
		.hdmi_height(HDMI_HEIGHT),
		.aspect_ratio(status[15:14]),
		.orientation(cfg_orient),

		.vec_x(vec_x), .vec_y(vec_y), .vec_colour(vec_colour),
		.vec_beam(vec_beam), .vec_valid(vec_valid),
		.frame_done(vec_frame_done),

		.osd_flash_param(8'd0),
		.osd_120hz(status[25]),
		.osd_buffer_mode(status[40:39]),
		.osd_dot_mode(status[30:28]),
		.osd_bloom_width(status[43:41]),
		.osd_bloom_curve(status[46:44]),
		.osd_halo_filter(status[49:47]),
		.osd_phosphor_mode(status[53:52]),
		.osd_inter_frame_phosphor_mode(status[55:54]),
		.osd_halo_spread(status[51:50]),
		.osd_halo_curve(status[65:63]),
		.osd_halo_knee(status[67:66]),
		.osd_expand_highlights(status[68]),
		.osd_color_space(status[56]),
		.osd_presentation_color(status[59:57]),
		.osd_slot_mask(status[60]),
		.osd_slot_mask_rows(status[61]),
		.osd_full_bypass(status[62]),

		.video_arx(VIDEO_ARX), .video_ary(VIDEO_ARY),
		.ce_pixel(CE_PIXEL),
		.hblank(video_hblank), .vblank(video_vblank),
		.video_r(raw_video_r), .video_g(raw_video_g), .video_b(raw_video_b),
		.hsync(VGA_HS), .vsync(VGA_VS),
		.mode_is_720p(video_is_720p),
		.fifo_full(fifo_full),

		.ddram_clk(DDRAM_CLK),
		.ddram_busy(DDRAM_BUSY),
		.ddram_burst_count(DDRAM_BURSTCNT),
		.ddram_address(DDRAM_ADDR),
		.ddram_data_out(DDRAM_DOUT),
		.ddram_data_ready(DDRAM_DOUT_READY),
		.ddram_read(DDRAM_RD),
		.ddram_data_in(DDRAM_DIN),
		.ddram_byte_enable(DDRAM_BE),
		.ddram_write(DDRAM_WE),

		.sdram_data_in(SDRAM_DQ),
		.sdram_data_out(sdram_data_out),
		.sdram_data_oe(sdram_data_oe),
		.sdram_cke(SDRAM_CKE),
		.sdram_ncs(SDRAM_nCS),
		.sdram_nras(SDRAM_nRAS),
		.sdram_ncas(SDRAM_nCAS),
		.sdram_nwe(SDRAM_nWE),
		.sdram_dqm(sdram_dqm),
		.sdram_address(SDRAM_A),
		.sdram_bank(SDRAM_BA)
	);

	assign CLK_VIDEO = clk_125;
	assign VGA_R = paused_rgb[23:16];
	assign VGA_G = paused_rgb[15:8];
	assign VGA_B = paused_rgb[7:0];
	assign VGA_DE = !(video_hblank || video_vblank);
	assign VGA_F1 = 1'b0;
	assign VGA_SL = 2'b00;
	assign VGA_SCALER = 1'b0;
	assign VGA_DISABLE = 1'b0;
	assign HDMI_FREEZE = 1'b0;
	assign HDMI_BLACKOUT = 1'b0;
	assign HDMI_BOB_DEINT = 1'b0;

	// Zektor's PSG, the speech board and the Universal Sound Board. On Star
	// Trek the USB already arrives inside audio_speech via the CD4053, so
	// audio_usb is zero there and this never double-counts it. The discrete
	// sound boards are the remaining audio work, so there is headroom left.
	// Each board is scaled so its own peaks land in roughly the same place,
	// then summed with headroom. On Star Trek the USB already arrives inside
	// audio_speech via the CD4053, so audio_usb is zero there and this never
	// double-counts it. The discrete sound boards are still to come.
	// Boards are summed at full weight and saturated. Each one is scaled so
	// its own peaks land near -10 dBFS, and no game runs more than three at
	// once, so this keeps a sensible output level without clipping.
	wire signed [17:0] audio_sum =
		{{2{audio_ay[15]}}, audio_ay} + {{2{audio_speech[15]}}, audio_speech}
		+ {{2{audio_usb[15]}}, audio_usb}
		+ {{2{audio_discrete[15]}}, audio_discrete};
	wire signed [15:0] audio_mix =
		(audio_sum >  18'sd32767) ?  16'sh7FFF :
		(audio_sum < -18'sd32768) ? -16'sh8000 : audio_sum[15:0];
	assign AUDIO_L = audio_mix;
	assign AUDIO_R = audio_mix;
	assign AUDIO_S = 1'b1;
	assign AUDIO_MIX = 2'b00;

	assign LED_USER  = fifo_full || ioctl_download;
	assign LED_DISK  = 2'b00;
	assign LED_POWER = 2'b00;
	assign BUTTONS   = 2'b00;

	assign ADC_BUS = 4'bzzzz;
	assign USER_OUT = 7'h7f;
	assign {UART_RTS, UART_TXD, UART_DTR} = 3'b000;
	assign {SD_SCK, SD_MOSI, SD_CS} = 3'bzzz;

`ifdef MISTER_FB
	assign FB_EN = 1'b0;
	assign FB_FORMAT = 5'd0;
	assign FB_WIDTH = 12'd0;
	assign FB_HEIGHT = 12'd0;
	assign FB_BASE = 32'd0;
	assign FB_STRIDE = 14'd0;
	assign FB_FORCE_BLANK = 1'b0;
`ifdef MISTER_FB_PALETTE
	assign FB_PAL_CLK = 1'b0;
	assign FB_PAL_ADDR = 8'd0;
	assign FB_PAL_DOUT = 24'd0;
	assign FB_PAL_WR = 1'b0;
`endif
`endif

`ifdef MISTER_DUAL_SDRAM
	assign SDRAM2_CLK = 1'bz;
	assign SDRAM2_A = 13'hzzz;
	assign SDRAM2_BA = 2'bzz;
	assign SDRAM2_DQ = 16'hzzzz;
	assign {SDRAM2_nCS, SDRAM2_nCAS, SDRAM2_nRAS, SDRAM2_nWE} = 4'hf;
`endif

endmodule
