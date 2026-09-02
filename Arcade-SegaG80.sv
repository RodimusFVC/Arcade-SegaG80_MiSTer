//============================================================================
// 
//  Port to MiSTer.
//  Copyright (C) 2026 Rodimus
//
//  SegaG80 Platform for MiSTer
//  Based on Time Pilot port, original design Copyright (C) 2017 Dar
//  Initial port to MiSTer Copyright (C) 2017 Sorgelig
//  Updated port to MiSTer Copyright (C) 2021, 2022 Ace,
//  Ash Evans (aka ElectronAsh/OzOnE), Artemio Urbina and Kitrinx (aka Rysha)
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the 
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio;
assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
// DIAG-REVERT-2026-05-28: repurpose status LEDs to show the speech command path
// (driven from g80_inst below). LED_USER = command SERVICED (8035 acked via the
// P1[7] pulse); LED_POWER[0] = command SENT (host set T0). On a coin-up / known
// speech trigger:  neither = not sent (port/host);  sent-only = 8035 not
// servicing (stuck);  both = serviced -> bug is downstream. Each stretched ~0.2s.
// Revert: delete the dbg_speech_* wire + the two DIAG assigns, uncomment the two
// originals, and drop the g80_inst dbg ports + segaspeech/SegaG80 dbg ports.
wire dbg_speech_sent, dbg_speech_ack;
// assign LED_POWER = 0;
// assign LED_USER  = ioctl_download;
assign LED_POWER = {1'b0, dbg_speech_sent};   // DIAG: bit0 = speech command sent
assign LED_USER  = dbg_speech_ack;            // DIAG: 8035 serviced a command
assign BUTTONS = 0;

///////////////////////////////////////////////////

wire [1:0] ar = status[14:13];

// Monitor aspect ratio (4:3 tube), NOT the framebuffer pixel ratio.
// Old values were 14:16/16:14 (224:256 active-area pixel count) — that looked fat.
// Vertical (status[12]=0): 3:4. Horizontal (status[12]=1): 4:3.
assign VIDEO_ARX = status[12] ? ((!ar) ? 12'd4 : (ar - 1'd1)) : ((!ar) ? 12'd3 : (ar - 1'd1));
assign VIDEO_ARY = status[12] ? ((!ar) ? 12'd3 : 12'd0) : ((!ar) ? 12'd4 : 12'd0);

`include "build_id.v"
localparam CONF_STR = {
	"A.SEGAG80;;",
	"P1,Video Options;",
	"P1ODE,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"P1OC,Orientation,Vert,Horz;",
	"P1OB,HDMI Flip,Off,On;",
	"P1OM,CRT Flip,Off,On;",
	"P1OFH,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	// DIAG-REVERT-2026-09-01: centering lives with the other screen options, not in a
	// submenu of its own. These two entries already existed but were never wired to the
	// RTL -- the menu did nothing. Now live, and the labels match the sign-extended
	// two's complement offsets in segag80_vtg.sv. The old lists had the signs inverted
	// and were short (15 and 13 entries for 4-bit fields).
	// Originals, uncomment to restore (they sat under a "P3,Screen Centering;" header
	// below the DIP block, which is also removed):
	// "P3O36,H Center,0,-1,-2,-3,-4,-5,-6,-7,+7,+6,+5,+4,+3,+2,+1;",
	// "P3O7A,V Center,0,-1,-2,-3,-4,-5,-6,-7,-8,-9,-10,-11,-12;",
	"P1O36,H Center,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O7A,V Center,0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"-;",
	"H1OR,Autosave Hiscores,Off,On;",
	"P2,Pause Options;",
	"P2OP,Pause when OSD is open,On,Off;",
	"P2OQ,Dim video after 10s,On,Off;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	// Slots 3/4 are unused by every game currently on this core (max real
	// button count is 2, on astrob/spaceod) but must stay reserved so bit
	// positions match the MRAs' universal 8-slot button template exactly
	// (see Astro Blaster.mra / 005.mra <buttons names=...>) -- this is a
	// shared multi-game core, so J1 can't be sized per-game like a
	// single-game core's CONF_STR normally would. Generic "Button N" names
	// (not "Fire"/"Warp") because meaning differs per game (astrob:
	// Fire+Warp, 005/monsterb/pignewt/sindbadm: Fire only, spaceod: 2
	// buttons) -- same convention SNK6502 uses for the same reason.
	"J1,Button 1,Button 2,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,B,Start,R,Select,L;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;

wire [21:0] gamma_bus;
wire        direct_video;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_SYS),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({~hs_configured,direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.ps2_key(ps2_key)
);

////////////////////   CLOCKS   ///////////////////
//
// outclk_0 = 15.468480 MHz (MAME segag80r.cpp:130 VIDEO_CLOCK).
// Z80 runs at /4 (~3.867 MHz), pixel clock at /3 (~5.156 MHz).
// Internal clock enables are generated inside SegaG80_CPU.
//
// DIAG-REVERT-2026-09-01: outclk_1 = 38.6712 MHz added and fed to arcade_video as
// clk_video. sys/gamma_corr.sv walks its 768-entry LUT sequentially R->G->B and
// needs at least FOUR clk_vid cycles per ce_pix to finish; driving clk_video from
// CLK_SYS gave it exactly THREE (ce_pix = CLK_SYS/3, SegaG80_CPU.sv:151), so the
// blue channel was served the green curve and green ran a pixel late whenever
// gamma was enabled. Every other core in the fleet has ratio 8 -- Kangaroo does
// the same thing deliberately, running its core on clk_10m but arcade_video on
// CLK_40M. At 38.6712 MHz the ratio is 7.5, comfortably over 4.
// ce_pix stays a CLK_SYS-domain pulse (2-3 cycles wide in the faster domain);
// arcade_video rising-edge detects it, so CE is still one clean cycle. Both
// clocks come from the same PLL and are phase-locked, so there is no CDC.
// NOTE: this also moves sys's clk_vid (OSD, scandoubler, analog DAC, and
// screen_rotate's DDRAM_CLK) from 15.47 to 38.67 MHz, which is in line with the
// rest of the fleet rather than an outlier.
// TO REVERT: drop .outclk_1 / CLK_VID here and in rtl/pll.v + rtl/pll/pll_0002.v,
// and put .clk_video back to CLK_SYS.
//
wire CLK_SYS;
wire CLK_VID;   // DIAG-REVERT-2026-09-01: 38.6712 MHz video clock
wire locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_SYS),
	.outclk_1(CLK_VID),   // DIAG-REVERT-2026-09-01
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll),
	.locked(locked)
);

wire [63:0] reconfig_to_pll;
wire [63:0] reconfig_from_pll;
wire        cfg_waitrequest;
wire        cfg_write;
wire  [5:0] cfg_address;
wire [31:0] cfg_data;

// PLL reconfig kept for potential future use (no runtime retune for G-80)
pll_cfg pll_cfg
(
	.mgmt_clk(CLK_50M),
	.mgmt_reset(0),
	.mgmt_waitrequest(cfg_waitrequest),
	.mgmt_read(0),
	.mgmt_readdata(),
	.mgmt_write(cfg_write),
	.mgmt_address(cfg_address),
	.mgmt_writedata(cfg_data),
	.reconfig_to_pll(reconfig_to_pll),
	.reconfig_from_pll(reconfig_from_pll)
);

assign cfg_write = 0;
assign cfg_address = 0;
assign cfg_data = 0;

// FIX-2026-05-25: include ioctl_download and PLL lock in the reset chain.
// Per JF Juno First 2026-05-25 — the prior "T48 confirmed as the fault"
// diagnosis for SegaG80 speech (Astro Blaster) may actually be the same
// cold-boot ordering bug fixed on JF: the 8035 was deasserting reset while
// its program ROM was still streaming into BRAM, fetching garbage opcodes,
// latching into a bad state from which it never recovered. See
// Common-Pitfalls/Core reset must include ioctl_download.md.
wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

///////////////////         Keyboard           //////////////////

reg btn_up       = 0;
reg btn_down     = 0;
reg btn_left     = 0;
reg btn_right    = 0;
reg btn_fire     = 0;
reg btn_fire2    = 0;
reg btn_coin1    = 0;
reg btn_coin2    = 0;
reg btn_1p_start = 0;
reg btn_2p_start = 0;
reg btn_pause    = 0;
reg btn_service  = 0;
reg btn_selftest = 0;

wire pressed = ps2_key[9];
wire [7:0] code = ps2_key[7:0];
always @(posedge CLK_SYS) begin
	reg old_state;
	old_state <= ps2_key[10];
	if(old_state != ps2_key[10]) begin
		case(code)
			'h16: btn_1p_start <= pressed; // 1
			'h1E: btn_2p_start <= pressed; // 2
			'h2E: btn_coin1    <= pressed; // 5
			'h36: btn_coin2    <= pressed; // 6
			'h46: btn_service  <= pressed; // 9  = SERVICE1 credit (MAME default key)
				'h06: btn_selftest <= pressed; // F2 = CPU-board self-test switch (MAME default key)
			'h4D: btn_pause    <= pressed; // P

			'h75: btn_up      <= pressed; // up
			'h72: btn_down    <= pressed; // down
			'h6B: btn_left    <= pressed; // left
			'h74: btn_right   <= pressed; // right
			'h14: btn_fire    <= pressed; // ctrl
			'h11: btn_fire2   <= pressed; // alt
		endcase
	end
end

//////////////////  Arcade Buttons/Interfaces   ///////////////////////////

//Player 1
wire m_up1      = btn_up      | joystick_0[3];
wire m_down1    = btn_down    | joystick_0[2];
wire m_left1    = btn_left    | joystick_0[1];
wire m_right1   = btn_right   | joystick_0[0];
wire m_fire1    = btn_fire    | joystick_0[4];
wire m_fire1b   = btn_fire2   | joystick_0[5];

//Player 2
wire m_up2      = btn_up      | joystick_1[3];
wire m_down2    = btn_down    | joystick_1[2];
wire m_left2    = btn_left    | joystick_1[1];
wire m_right2   = btn_right   | joystick_1[0];
wire m_fire2    = btn_fire    | joystick_1[4];
// P2-JOY-FIX-2026-07-26: read P2's controller, not P1's. Every sibling P2 line
// (m_up2/m_down2/m_left2/m_right2/m_fire2) uses joystick_1; this one said
// joystick_0, so P1's button 2 drove BOTH the P1 warp bit (D5D4 b7, active-low)
// and the P2 cocktail warp bit (FC b4, active-HIGH) at once.
// ORIGINAL:
// wire m_fire2b   = btn_fire2   | joystick_0[5];
wire m_fire2b   = btn_fire2   | joystick_1[5];

// (DIAG-REVERT-2026-07-26 warp lockout removed 2026-07-26: it did its job —
//  slowdown persisted with warp physically disabled, so the input path is
//  EXONERATED. Do not re-run this diagnostic.)

//Start/coin/service
// Bit positions match the new 8-slot J1 above (button,button,-,-,coin,
// start1,start2,pause), NOT the old 6-slot one. Fixed 2026-07-26: the MRAs
// were already on the 8-slot universal template but J1 above was still the
// old 6-slot layout, so every bit from Start P1 onward landed 2-3 positions
// off (e.g. bit6 read as "Start P1" here while the MRA's default binding
// for that slot was an unrelated physical button) -- this is what broke
// controls, not the earlier game_id control-mapping fix.
wire m_start1   = btn_1p_start | joystick_0[9];
wire m_start2   = btn_2p_start | joystick_0[10];
wire m_coin1    = btn_coin1    | joystick_0[8];
wire m_coin2    = btn_coin2;
// No "Service" slot in the 8-slot template (no sibling core in this vault
// exposes Service as a mappable gamepad button either) -- keyboard-only.
wire m_service  = btn_service;
// SELFTEST-SPLIT-2026-08-11: separate input, matching the real cabinet's red
// CPU-board switch (AstroBlaster manual p.14) and MAME's SERVICESW port.
wire m_selftest = btn_selftest;
wire m_pause    = btn_pause    | joystick_0[11];

// PAUSE SYSTEM
wire pause_cpu;
wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_SYS),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[26:25])
);

// DIP SWITCHES — hps_io index 254 carries up to 8 bytes of DIP banks.
// G-80 games use 1–4 banks depending on game; unused banks default to 0xFF.
reg [7:0] dip_sw[8];	// Active-LOW per MAME
always @(posedge CLK_SYS) begin
	if(ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

// Game ID — latched from MRA ioctl_index=1 byte 0, must arrive before index=0 ROM data.
// 0=ASTROB, 1=MONSTERB, 2=SPACEOD, 3=005, 4=SINDBADM(unsupported), 5=PIGNEWT
// (2 and 5 both use the 315-0063 security chip -- see chip_sel in
// SegaG80_CPU.sv -- but need distinct ids because their control-port
// layouts differ; split 2026-07-26.)
reg [2:0] game_id;
always @(posedge CLK_SYS)
	if (ioctl_wr && (ioctl_index == 8'd1) && (ioctl_addr == 25'd0))
		game_id <= ioctl_dout[2:0];

///////////////                 Video                  ////////////////

wire hblank, vblank;
wire hs, vs;
wire [4:0] r_out, g_out, b_out;

// Scale 5-bit color to 8-bit for VGA output
wire [7:0] r = (r_out[0] ? 8'h19 : 8'h00) + 
               (r_out[1] ? 8'h24 : 8'h00) + 
               (r_out[2] ? 8'h35 : 8'h00) +
               (r_out[3] ? 8'h40 : 8'h00) + 
               (r_out[4] ? 8'h4D : 8'h00);
wire [7:0] g = (g_out[0] ? 8'h19 : 8'h00) + 
               (g_out[1] ? 8'h24 : 8'h00) + 
               (g_out[2] ? 8'h35 : 8'h00) +
               (g_out[3] ? 8'h40 : 8'h00) + 
               (g_out[4] ? 8'h4D : 8'h00);
wire [7:0] b = (b_out[0] ? 8'h19 : 8'h00) + 
               (b_out[1] ? 8'h24 : 8'h00) + 
               (b_out[2] ? 8'h35 : 8'h00) +
               (b_out[3] ? 8'h40 : 8'h00) + 
               (b_out[4] ? 8'h4D : 8'h00);
wire ce_pix;

// Astro Blaster is ROT270 in MAME (monitor rotated 90° CCW from landscape).
// MiSTer screen_rotate with rotate_ccw=1 gives us that orientation.
wire rotate_ccw = 1;
wire no_rotate = status[12] | direct_video;
wire flip = status[11] | ~no_rotate;
wire video_rotated;
screen_rotate screen_rotate(.*);

arcade_video #(256, 24) arcade_video
(
	.*,

	.clk_video(CLK_VID),   // DIAG-REVERT-2026-09-01: was CLK_SYS (gamma_corr ratio)

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.fx(status[17:15])
);

//----------------------------------------------------------------
// Sega G-80 core
//----------------------------------------------------------------
// MAME: segag80r.cpp / segag80v.cpp. Module body defined in rtl/SegaG80.sv (T1.1).
// Inputs are raw active-HIGH from the MiSTer controls; the G-80 port mangling
// (segag80r.cpp:443 demangle) happens inside SegaG80_CPU.
//
SegaG80 g80_inst
(
	.reset(reset),
	.crt_flip(status[22]),
	.h_center(status[6:3]),    // DIAG-REVERT-2026-09-01: menu was dead, now wired
	.v_center(status[10:7]),   // DIAG-REVERT-2026-09-01: menu was dead, now wired
	.clk_sys(CLK_SYS),
	.game_id(game_id),

	// Player 1 controls (active HIGH)
	.p1_up   (m_up1),
	.p1_down (m_down1),
	.p1_left (m_left1),
	.p1_right(m_right1),
	.p1_fire1(m_fire1),
	.p1_fire2(m_fire1b),
	.p1_start(m_start1),
	.p1_coin (m_coin1),

	// Player 2 controls (active HIGH)
	.p2_up   (m_up2),
	.p2_down (m_down2),
	.p2_left (m_left2),
	.p2_right(m_right2),
	.p2_fire1(m_fire2),
	.p2_fire2(m_fire2b),
	.p2_start(m_start2),
	.p2_coin (m_coin2),

	.service   (m_service),
	.self_test (m_selftest),

	// DIP banks (active-LOW, MAME convention)
	.dip_sw0 (dip_sw[0]),
	.dip_sw1 (dip_sw[1]),
	.dip_sw2 (dip_sw[2]),
	.dip_sw3 (dip_sw[3]),

	// Video
	.video_hsync (hs),
	.video_vsync (vs),
	.video_hblank(hblank),
	.video_vblank(vblank),
	.ce_pix      (ce_pix),
	.video_r     (r_out),
	.video_g     (g_out),
	.video_b     (b_out),

	// Audio
	.audio_out   (audio),

	// ROM loading
	.ioctl_addr  (ioctl_addr),
	.ioctl_wr    (ioctl_wr),
	.ioctl_data  (ioctl_dout),
	.ioctl_index (ioctl_index),

	.pause       (pause_cpu),


	// Hiscore
	.hs_address  (hs_address),
	.hs_data_in  (hs_data_in),
	.hs_data_out (hs_data_out),
	.hs_write    (hs_write_enable),

	// DIAG-REVERT-2026-05-28: speech command-path activity -> status LEDs
	.dbg_speech_sent (dbg_speech_sent),
	.dbg_speech_ack  (dbg_speech_ack)
);

// HISCORE SYSTEM
// --------------
wire [15:0]hs_address;
wire [7:0] hs_data_in;
wire [7:0] hs_data_out;
wire hs_write_enable;
wire hs_access_read;
wire hs_access_write;
wire hs_pause;
wire hs_configured;

// HISCORE-DISABLED-2026-07-26 ------------------------------------------------
// Disabled at the user's request. It has caused problems before, and the MRA's
// hiscore config (index 5) is EMPTY ("fill in once hiscore addresses are
// mapped"), so this module is running UNCONFIGURED. It is a live suspect for
// the progressive slowdown: it can assert pause_cpu (throttling the whole core,
// game AND audio, since sound is CPU-triggered) and it writes straight into
// mainram port B via hs_write_enable, so an unconfigured address could also be
// corrupting game RAM.
// TO RESTORE: delete the tie-offs below, uncomment the instantiation, and fill
// in MRA index 5 with a real hiscore config FIRST.
assign hs_pause        = 1'b0;
assign hs_write_enable = 1'b0;
assign hs_access_read  = 1'b0;
assign hs_access_write = 1'b0;
assign hs_configured   = 1'b0;   // ~hs_configured masks the OSD hiscore entry
assign hs_address      = 16'd0;
assign hs_data_in      = 8'd0;
assign ioctl_din       = 8'd0;   // was driven by hiscore .data_to_hps
// ORIGINAL:
// hiscore #(
// 	.HS_ADDRESSWIDTH(16),
// 	.CFG_ADDRESSWIDTH(3),
// 	.CFG_LENGTHWIDTH(2)
// ) hi (
// 	.*,
// 	.clk(CLK_SYS),
// 	.paused(pause_cpu),
// 	.autosave(status[27]),
// 	.ram_address(hs_address),
// 	.data_from_ram(hs_data_out),
// 	.data_to_ram(hs_data_in),
// 	.data_from_hps(ioctl_dout),
// 	.data_to_hps(ioctl_din),
// 	.ram_write(hs_write_enable),
// 	.ram_intent_read(hs_access_read),
// 	.ram_intent_write(hs_access_write),
// 	.pause_cpu(hs_pause),
// 	.configured(hs_configured)
// );
// ---------------------------------------------------------------------------

endmodule
