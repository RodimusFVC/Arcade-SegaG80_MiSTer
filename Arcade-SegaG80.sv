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

wire [127:0] status;
wire        ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

wire [1:0] ar = status[14:13];

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
	"J1,Button 1,Button 2,Not Used,Not Used,Coin,Start 1P,Start 2P,Pause;",
	"jn,A,B,Start,R,Select,L;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire   [1:0] buttons;
wire  [10:0] ps2_key;

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

wire CLK_SYS;
wire CLK_VID;
wire locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_SYS),
	.outclk_1(CLK_VID),
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

wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

wire        pause_cpu;
wire [12:0] kb;
wire  [0:0] kbx;
ctl_keyboard #(.NX(1), .NXO(1), .XKEYS({24'h10_06_00})) keyboard
	(.clk(CLK_SYS), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx(kbx));
wire btn_up       = kb[0];
wire btn_down     = kb[1];
wire btn_left     = kb[2];
wire btn_right    = kb[3];
wire btn_fire     = kb[4];
wire btn_fire2    = kb[5];
wire btn_1p_start = kb[6];
wire btn_2p_start = kb[7];
wire btn_coin1    = kb[8];
wire btn_coin2    = kb[9];
wire btn_service  = kb[10];
wire btn_pause    = kb[12];
wire btn_selftest = kbx[0];

wire m_up1      = btn_up      | joystick_0[3];
wire m_down1    = btn_down    | joystick_0[2];
wire m_left1    = btn_left    | joystick_0[1];
wire m_right1   = btn_right   | joystick_0[0];
wire m_fire1    = btn_fire    | joystick_0[4];
wire m_fire1b   = btn_fire2   | joystick_0[5];

wire m_up2      = btn_up      | joystick_1[3];
wire m_down2    = btn_down    | joystick_1[2];
wire m_left2    = btn_left    | joystick_1[1];
wire m_right2   = btn_right   | joystick_1[0];
wire m_fire2    = btn_fire    | joystick_1[4];
wire m_fire2b   = btn_fire2   | joystick_1[5];

wire m_start1   = btn_1p_start | joystick_0[9];
wire m_start2   = btn_2p_start | joystick_0[10];
wire m_coin1    = btn_coin1    | joystick_0[8];
wire m_coin2    = btn_coin2;
wire m_service  = btn_service;
wire m_selftest = btn_selftest;
wire m_pause    = btn_pause    | joystick_0[11];

wire [23:0] rgb_out;
pause #(8,8,8,49) pause
(
	.*,
	.clk_sys(CLK_SYS),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[26:25])
);

reg [7:0] dip_sw[8];
always @(posedge CLK_SYS) begin
	if(ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

reg [2:0] game_id;
always @(posedge CLK_SYS)
	if (ioctl_wr && (ioctl_index == 8'd1) && (ioctl_addr == 25'd0))
		game_id <= ioctl_dout[2:0];

wire hblank, vblank;
wire hs, vs;
wire [4:0] r_out, g_out, b_out;

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

wire rotate_ccw = 1;
wire no_rotate = status[12] | direct_video;
wire flip = status[11] | ~no_rotate;
wire video_rotated;
screen_rotate screen_rotate(.*);

arcade_video #(256, 24) arcade_video
(
	.*,

	.clk_video(CLK_VID),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(~hs),
	.VSync(~vs),

	.fx(status[17:15])
);

segag80_dispatcher g80_inst
(
	.reset(reset),
	.crt_flip(status[22]),
	.h_center(status[6:3]),
	.v_center(status[10:7]),
	.clk_sys(CLK_SYS),
	.game_id(game_id),

	.p1_up   (m_up1),
	.p1_down (m_down1),
	.p1_left (m_left1),
	.p1_right(m_right1),
	.p1_fire1(m_fire1),
	.p1_fire2(m_fire1b),
	.p1_start(m_start1),
	.p1_coin (m_coin1),

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

	.dip_sw0 (dip_sw[0]),
	.dip_sw1 (dip_sw[1]),
	.dip_sw2 (dip_sw[2]),
	.dip_sw3 (dip_sw[3]),

	.video_hsync (hs),
	.video_vsync (vs),
	.video_hblank(hblank),
	.video_vblank(vblank),
	.ce_pix      (ce_pix),
	.video_r     (r_out),
	.video_g     (g_out),
	.video_b     (b_out),

	.audio_out   (audio),

	.ioctl_addr  (ioctl_addr),
	.ioctl_wr    (ioctl_wr),
	.ioctl_data  (ioctl_dout),
	.ioctl_index (ioctl_index),

	.pause       (pause_cpu),

	.hs_address  (hs_address),
	.hs_data_in  (hs_data_in),
	.hs_data_out (hs_data_out),
	.hs_write    (hs_write_enable)
);

wire [15:0]hs_address;
wire [7:0] hs_data_in;
wire [7:0] hs_data_out;
wire hs_write_enable;
wire hs_access_read;
wire hs_access_write;
wire hs_pause;
wire hs_configured;

assign hs_pause        = 1'b0;
assign hs_write_enable = 1'b0;
assign hs_access_read  = 1'b0;
assign hs_access_write = 1'b0;
assign hs_configured   = 1'b0;
assign hs_address      = 16'd0;
assign hs_data_in      = 8'd0;
assign ioctl_din       = 8'd0;

endmodule
