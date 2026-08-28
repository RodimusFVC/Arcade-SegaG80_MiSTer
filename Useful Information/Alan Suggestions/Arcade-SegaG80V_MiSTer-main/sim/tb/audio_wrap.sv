// Audio capture harness: the machine plus the real input mapping.
//
// The first version of this bench drove segag80v's port bytes directly and got
// them wrong — in particular it held D3D2 at 0xFF, which is Demo Sounds *off*,
// so every recording came out silent. Driving sega_inputs and sega_game_cfg
// instead means the bench uses exactly the path the MiSTer top level uses, and
// the only thing left to get right is a joystick bit.

`default_nettype none

module audio_wrap #(
	parameter bit SPEECH_FILTER = 1'b1,
	parameter bit SPEECH_C10_TENTH = 1'b0
) (
	input  wire        clk,
	input  wire        reset,

	input  wire  [2:0] game,
	input  wire  [7:0] dsw1,
	input  wire  [7:0] dsw2,
	input  wire [31:0] joy1,
	input  wire [31:0] joy2,

	input  wire        rom_wr,
	input  wire [16:0] rom_addr,
	input  wire  [7:0] rom_data,

	// audio
	output wire signed [15:0] audio_ay,
	output wire signed [15:0] audio_speech,
	output wire signed [15:0] audio_usb,
	output wire signed [15:0] audio_discrete,

	// liveness
	output wire        frame_done,
	output wire        vec_valid,
	output wire        vec_beam,
	output wire        ay_wr,
	output wire        speech_data_wr,
	output wire        speech_ctrl_wr,
	output wire        usb_data_wr,
	output wire        snd_wr,
	output wire  [1:0] snd_sel,
	output wire  [7:0] snd_data,

	// Universal Sound Board taps, for the MAME-model comparison
	output wire        dbg_usb_tick,
	output wire        dbg_usb_noise,
	output wire  [8:0] dbg_usb_tmr,
	output wire  [2:0] dbg_usb_cfg,
	output wire [71:0] dbg_usb_env,
	output wire [10:0] dbg_sp_prog_addr,
	output wire        dbg_sp_wr,
	output wire  [7:0] dbg_sp_data,
	output wire        dbg_sp_drq,
	output wire        dbg_sp_t0,
	output wire  [7:0] dbg_sp_p1,
	output wire        dbg_sp_rd_n,
	output wire [13:0] dbg_sp_data_addr,
	output wire        dbg_sp_int_n,
	output wire signed [7:0] dbg_sp_dac,
	output wire  [1:0] coin_counter,
	output wire        dbg_irq,
	output wire  [1:0] dbg_coin_ff,
	output wire        dbg_int_ack
);

	wire [2:0] cfg_chip, cfg_orient;
	wire       cfg_usb, cfg_speech;
	wire [1:0] cfg_fc;

	sega_game_cfg gamecfg (
		.game(game), .cfg_chip(cfg_chip), .cfg_usb(cfg_usb),
		.cfg_speech(cfg_speech), .cfg_fc(cfg_fc), .cfg_orient(cfg_orient)
	);

	wire [7:0] in_d7d6, in_d5d4, in_d3d2, in_d1d0, in_fc, in_coins;
	wire       coin_a, coin_b, service;

	sega_inputs inputs (
		.game(game), .joy1(joy1), .joy2(joy2), .joy3(32'd0), .joy4(32'd0),
		.dsw1(dsw1), .dsw2(dsw2),
		.in_d7d6(in_d7d6), .in_d5d4(in_d5d4),
		.in_d3d2(in_d3d2), .in_d1d0(in_d1d0),
		.in_fc(in_fc), .in_coins(in_coins),
		.coin_a(coin_a), .coin_b(coin_b), .service(service)
	);

	segag80v #(.SPEECH_FILTER(SPEECH_FILTER),
	           .SPEECH_C10_TENTH(SPEECH_C10_TENTH)) machine (
		.clk_vec(clk), .reset(reset), .pause(1'b0),
		.cfg_chip(cfg_chip), .cfg_usb(cfg_usb), .cfg_speech(cfg_speech),
		.cfg_game(game),
		.cfg_fc(cfg_fc),
		.rom_wr(rom_wr), .rom_addr(rom_addr), .rom_data(rom_data),
		.in_d7d6(in_d7d6), .in_d5d4(in_d5d4),
		.in_d3d2(in_d3d2), .in_d1d0(in_d1d0),
		.in_fc(in_fc), .in_coins(in_coins),
		.spin_delta(8'sd0), .spin_stb(1'b0),
		.coin_a(coin_a), .coin_b(coin_b), .service(service),
		.vec_x(), .vec_y(), .vec_colour(),
		.vec_beam(vec_beam), .vec_valid(vec_valid),
		.drawing(), .frame_done(frame_done), .vec_tick(),
		.snd_wr(snd_wr), .snd_sel(snd_sel), .ay_wr(ay_wr), .ay_port(),
		.speech_data_wr(speech_data_wr), .speech_ctrl_wr(speech_ctrl_wr),
		.usb_data_wr(usb_data_wr), .snd_data(snd_data),
		.audio_ay(audio_ay), .audio_speech(audio_speech), .audio_usb(audio_usb),
		.audio_discrete(audio_discrete),
		.dbg_usb_tick(dbg_usb_tick), .dbg_usb_noise(dbg_usb_noise),
		.dbg_usb_tmr(dbg_usb_tmr), .dbg_usb_cfg(dbg_usb_cfg),
		.dbg_usb_env(dbg_usb_env),
		.dbg_sp_prog_addr(dbg_sp_prog_addr), .dbg_sp_wr(dbg_sp_wr),
		.dbg_sp_data(dbg_sp_data),
		.dbg_sp_drq(dbg_sp_drq), .dbg_sp_t0(dbg_sp_t0),
		.dbg_sp_p1(dbg_sp_p1), .dbg_sp_rd_n(dbg_sp_rd_n),
		.dbg_sp_data_addr(dbg_sp_data_addr),
		.dbg_sp_int_n(dbg_sp_int_n), .dbg_sp_dac(dbg_sp_dac),
		.coin_counter(coin_counter),
		.dbg_irq(dbg_irq), .dbg_coin_ff(dbg_coin_ff), .dbg_int_ack(dbg_int_ack)
	);

endmodule

`default_nettype wire
