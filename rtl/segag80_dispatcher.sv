//  Copyright (C) 2026 Rodimus

module segag80_dispatcher (
    input                reset,
    input                crt_flip,
    input          [3:0] h_center,
    input          [3:0] v_center,
    input                clk_sys,
    input          [2:0] game_id,

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

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

// Z80 (stock T80s, defaults): z80_0: main CPU (every game); z80_1: Sindbad Mystery sound board CPU.
chip_pool_pkg::z80_i_t z80_0_i, z80_1_i;
chip_pool_pkg::z80_o_t z80_0_o, z80_1_o;

/* verilator lint_off PINCONNECTEMPTY */
T80s z80_0 (
    .RESET_n(~reset), .CLK(clk_sys), .CEN(z80_0_i.ce), .WAIT_n(1'b1), .INT_n(z80_0_i.int_n), .NMI_n(z80_0_i.nmi_n),
    .BUSRQ_n(1'b1), .M1_n(z80_0_o.m1_n), .MREQ_n(z80_0_o.mreq_n), .IORQ_n(z80_0_o.iorq_n), .RD_n(z80_0_o.rd_n),
    .WR_n(z80_0_o.wr_n), .RFSH_n(z80_0_o.rfsh_n), .HALT_n(), .BUSAK_n(), .A(z80_0_o.a), .DI(z80_0_i.di), .DO(z80_0_o.dout)
);

T80s z80_1 (
    .RESET_n(~reset), .CLK(clk_sys), .CEN(z80_1_i.ce), .WAIT_n(1'b1), .INT_n(z80_1_i.int_n), .NMI_n(z80_1_i.nmi_n),
    .BUSRQ_n(1'b1), .M1_n(z80_1_o.m1_n), .MREQ_n(z80_1_o.mreq_n), .IORQ_n(z80_1_o.iorq_n), .RD_n(z80_1_o.rd_n),
    .WR_n(z80_1_o.wr_n), .RFSH_n(z80_1_o.rfsh_n), .HALT_n(), .BUSAK_n(), .A(z80_1_o.a), .DI(z80_1_i.di), .DO(z80_1_o.dout)
);

// 8035 (stock T48 t8039_notri_extrom, gate_port_input_g 0, 64-byte RAM, EA 0): mcs48_0: Astro Blaster speech board.
chip_pool_pkg::mcs48_i_t mcs48_0_i;
chip_pool_pkg::mcs48_o_t mcs48_0_o;

t8039_notri_extrom #(.gate_port_input_g(0), .ram_addr_width_g(6)) mcs48_0 (
    .xtal_i(clk_sys), .xtal_en_i(mcs48_0_i.xtal_en), .reset_n_i(mcs48_0_i.reset_n), .t0_i(mcs48_0_i.t0), .t0_o(),
    .t0_dir_o(), .int_n_i(mcs48_0_i.int_n), .ea_i(1'b0), .rd_n_o(mcs48_0_o.rd_n), .psen_n_o(), .wr_n_o(mcs48_0_o.wr_n),
    .ale_o(mcs48_0_o.ale), .db_i(mcs48_0_i.db), .db_o(mcs48_0_o.db), .db_dir_o(mcs48_0_o.db_dir), .t1_i(mcs48_0_i.t1),
    .p2_i(mcs48_0_i.p2_in), .p2_o(mcs48_0_o.p2), .p2l_low_imp_o(), .p2h_low_imp_o(), .p1_i(mcs48_0_i.p1_in),
    .p1_o(mcs48_0_o.p1), .p1_low_imp_o(), .prog_n_o(), .pmem_addr_o(mcs48_0_o.pmem_a), .pmem_data_i(mcs48_0_i.pmem_d)
);

// 8035 through i8035.v (bare t48_core): i8035_0: Pig Newton sound board CPU / Monster Bash uPD7751 (never together).
chip_pool_pkg::i8035_i_t i8035_0_i;
chip_pool_pkg::i8035_o_t i8035_0_o;

i8035 i8035_0 (
    .clk(clk_sys), .ce(i8035_0_i.ce), .I_RSTn(i8035_0_i.rst_n), .I_INTn(i8035_0_i.int_n), .I_EA(i8035_0_i.ea),
    .O_PSENn(i8035_0_o.psen_n), .O_RDn(i8035_0_o.rd_n), .O_WRn(i8035_0_o.wr_n), .O_ALE(i8035_0_o.ale),
    .O_PROGn(i8035_0_o.prog_n), .I_T0(i8035_0_i.t0), .O_T0(i8035_0_o.t0), .I_T1(i8035_0_i.t1), .I_DB(i8035_0_i.db),
    .O_DB(i8035_0_o.db), .I_P1(i8035_0_i.p1), .O_P1(i8035_0_o.p1), .I_P2(i8035_0_i.p2), .O_P2(i8035_0_o.p2)
);

// SP0250 (ours): sp0250_0: Astro Blaster speech board.
chip_pool_pkg::sp0250_i_t sp0250_0_i;
chip_pool_pkg::sp0250_o_t sp0250_0_o;

sp0250 sp0250_0 (
    .clk(clk_sys), .reset_n(sp0250_0_i.reset_n), .ce_3_12m(sp0250_0_i.ce_3_12m), .ce_rom_1_56m(sp0250_0_i.ce_rom_1_56m),
    .data_in(sp0250_0_i.data_in), .wr(sp0250_0_i.wr), .drq(sp0250_0_o.drq), .audio_out(sp0250_0_o.audio),
    .audio_valid(sp0250_0_o.audio_valid)
);

// TMS36XX (rtl/sound/tms36xx.sv, master): tms36xx_0: Monster Bash TMS3617 (parameter set A; cfg_b, tunes unused).
chip_pool_pkg::tms36xx_i_t tms36xx_0_i;
chip_pool_pkg::tms36xx_o_t tms36xx_0_o;

wire signed [15:0] tms36xx_0_audio;
wire               tms36xx_0_ce;

tms36xx #(.CLK_HZ(15_468_480), .BASEFREQ(247),
          .DECAY0_MS(500), .DECAY1_MS(500), .DECAY2_MS(500), .DECAY3_MS(500), .DECAY4_MS(500), .DECAY5_MS(500)) tms36xx_0
(
    .clk(clk_sys), .reset(reset), .cfg_b(tms36xx_0_i.cfg_b),
    .tune_we(tms36xx_0_i.tune_we), .tune(tms36xx_0_i.tune),
    .note_we(tms36xx_0_i.note_we), .note_octave(tms36xx_0_i.note_octave), .note(tms36xx_0_i.note),
    .enable_we(tms36xx_0_i.enable_we), .voice_enable(tms36xx_0_i.voice_enable),
    .audio(tms36xx_0_audio), .ce_snd(tms36xx_0_ce)
);
assign tms36xx_0_o.audio = tms36xx_0_audio; assign tms36xx_0_o.ce_snd = tms36xx_0_ce;

chip_pool_pkg::sn76489_i_t [1:0] sn76489_i;
chip_pool_pkg::sn76489_o_t [1:0] sn76489_o;

genvar sn;
generate
    for (sn = 0; sn < 2; sn++) begin : g_sn76489
        jt89 sn76489 (
            .rst(sn76489_i[sn].rst), .clk(clk_sys), .clk_en(sn76489_i[sn].ce), .wr_n(sn76489_i[sn].wr_n),
            .cs_n(sn76489_i[sn].cs_n), .din(sn76489_i[sn].din), .sound(sn76489_o[sn].sound), .ready(sn76489_o[sn].ready)
        );
    end
endgenerate
/* verilator lint_on PINCONNECTEMPTY */

/////////////////////////////  Shared ROM blocks  /////////////////////////////

//   rom0  48K  index 0 < $C000   program ROM (32K + 16K blocks)      rom1   2K  index 2  speech 8035 program
//   rom2   8K  index 3           speech data                         rom3  32K  index 8  bg board tilemap
//   rom4/5 8K  index 7 bit 13 0/1 bg board tile planes 0 / 1          rom6  16K  index 8  Space Odyssey tilemap
//   rom7  6x4K index 7 [14:12]   Space Odyssey tile planes 0-5        rom8   8K  index 6  Sindbad sound program
//   rom9   2K  index 5           005 tune ROM                        rom10  32B index 10 005 divisor PROM
//   rom11  1K  index 6           Monster Bash 7751 program           rom12  8K  index 9  Monster Bash 7751 samples
wire [15:0] rom0_a;  wire [7:0] rom0_d;    wire [10:0] rom1_a;  wire [7:0] rom1_d;
wire [12:0] rom2_a;  wire [7:0] rom2_d;    wire [14:0] rom3_a;  wire [7:0] rom3_d;
wire [12:0] rom4_a;  wire [7:0] rom4_d;    wire [12:0] rom5_a;  wire [7:0] rom5_d;
wire [13:0] rom6_a;  wire [7:0] rom6_d;    wire [11:0] rom7_a;  wire [5:0][7:0] rom7_d;
wire [12:0] rom8_a;  wire [7:0] rom8_d;    wire [10:0] rom9_a;  wire [7:0] rom9_d;
wire  [4:0] rom10_a; wire [7:0] rom10_d;   wire  [9:0] rom11_a; wire [7:0] rom11_d;
wire [12:0] rom12_a; wire [7:0] rom12_d;

wire ld_idx0 = ioctl_wr & (ioctl_index == 8'd0);
wire ld_idx7 = ioctl_wr & (ioctl_index == 8'd7);
wire ld_idx8 = ioctl_wr & (ioctl_index == 8'd8);

wire [7:0] rom0_lo_q, rom0_hi_q;
reg        rom0_hi_sel;
always @(posedge clk_sys) rom0_hi_sel <= rom0_a[15];
assign rom0_d = rom0_hi_sel ? rom0_hi_q : rom0_lo_q;

dpram_dc #(.widthad_a(15)) rom0_lo (
    .clock_a(clk_sys), .address_a(ioctl_addr[14:0]), .data_a(ioctl_data), .wren_a(ld_idx0 & (ioctl_addr < 25'h08000)), .q_a(),
    .clock_b(clk_sys), .address_b(rom0_a[14:0]), .data_b(8'd0), .wren_b(1'b0), .q_b(rom0_lo_q)
);
dpram_dc #(.widthad_a(14)) rom0_hi (
    .clock_a(clk_sys), .address_a(ioctl_addr[13:0]), .data_a(ioctl_data),
    .wren_a(ld_idx0 & (ioctl_addr >= 25'h08000) & (ioctl_addr < 25'h0C000)), .q_a(),
    .clock_b(clk_sys), .address_b(rom0_a[13:0]), .data_b(8'd0), .wren_b(1'b0), .q_b(rom0_hi_q)
);
dpram_dc #(.widthad_a(11)) rom1 (
    .clock_a(clk_sys), .address_a(ioctl_addr[10:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd2)), .q_a(),
    .clock_b(clk_sys), .address_b(rom1_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom1_d)
);
dpram_dc #(.widthad_a(13)) rom2 (
    .clock_a(clk_sys), .address_a(ioctl_addr[12:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd3)), .q_a(),
    .clock_b(clk_sys), .address_b(rom2_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom2_d)
);
dpram_dc #(.widthad_a(15)) rom3 (
    .clock_a(clk_sys), .address_a(ioctl_addr[14:0]), .data_a(ioctl_data), .wren_a(ld_idx8), .q_a(),
    .clock_b(clk_sys), .address_b(rom3_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom3_d)
);
dpram_dc #(.widthad_a(13)) rom4 (
    .clock_a(clk_sys), .address_a(ioctl_addr[12:0]), .data_a(ioctl_data), .wren_a(ld_idx7 & ~ioctl_addr[13]), .q_a(),
    .clock_b(clk_sys), .address_b(rom4_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom4_d)
);
dpram_dc #(.widthad_a(13)) rom5 (
    .clock_a(clk_sys), .address_a(ioctl_addr[12:0]), .data_a(ioctl_data), .wren_a(ld_idx7 & ioctl_addr[13]), .q_a(),
    .clock_b(clk_sys), .address_b(rom5_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom5_d)
);
dpram_dc #(.widthad_a(14)) rom6 (
    .clock_a(clk_sys), .address_a(ioctl_addr[13:0]), .data_a(ioctl_data), .wren_a(ld_idx8), .q_a(),
    .clock_b(clk_sys), .address_b(rom6_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom6_d)
);
genvar pl;
generate
    for (pl = 0; pl < 6; pl++) begin : g_rom7
        dpram_dc #(.widthad_a(12)) rom7 (
            .clock_a(clk_sys), .address_a(ioctl_addr[11:0]), .data_a(ioctl_data),
            .wren_a(ld_idx7 & (ioctl_addr[14:12] == pl)), .q_a(),
            .clock_b(clk_sys), .address_b(rom7_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom7_d[pl])
        );
    end
endgenerate
dpram_dc #(.widthad_a(13)) rom8 (
    .clock_a(clk_sys), .address_a(ioctl_addr[12:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd6)), .q_a(),
    .clock_b(clk_sys), .address_b(rom8_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom8_d)
);
dpram_dc #(.widthad_a(11)) rom9 (
    .clock_a(clk_sys), .address_a(ioctl_addr[10:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd5)), .q_a(),
    .clock_b(clk_sys), .address_b(rom9_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom9_d)
);
dpram_dc #(.widthad_a(5)) rom10 (
    .clock_a(clk_sys), .address_a(ioctl_addr[4:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd10)), .q_a(),
    .clock_b(clk_sys), .address_b(rom10_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom10_d)
);
dpram_dc #(.widthad_a(10)) rom11 (
    .clock_a(clk_sys), .address_a(ioctl_addr[9:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd6)), .q_a(),
    .clock_b(clk_sys), .address_b(rom11_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom11_d)
);
dpram_dc #(.widthad_a(13)) rom12 (
    .clock_a(clk_sys), .address_a(ioctl_addr[12:0]), .data_a(ioctl_data), .wren_a(ioctl_wr & (ioctl_index == 8'd9)), .q_a(),
    .clock_b(clk_sys), .address_b(rom12_a), .data_b(8'd0), .wren_b(1'b0), .q_b(rom12_d)
);

/////////////////////////////  Shared RAM pool  /////////////////////////////

//   block 0  2K  main RAM $C800-$CFFF            A = Z80, B = hiscore
//   block 1  8K  video RAM $E000-$FFFF           A = Z80, B = video scan
//   block 2  2K  Sindbad Mystery sound work RAM  A = sound Z80
//   block 3  4K  Sound Board program RAM         A = main Z80 ($D000 window), B = 8035 fetch
//   block 4  1K  Sound Board work RAM            A = 8035 MOVX
// BBD delay line (wider than 8 bits) - each marked POOL-EXCEPTION.
localparam int RAM_BLOCKS = 5;
function automatic int ram_aw(input int b);
    case (b)
        1:       ram_aw = 13;
        3:       ram_aw = 12;
        4:       ram_aw = 10;
        default: ram_aw = 11;
    endcase
endfunction

ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] g80r_pr_i, pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;
assign pool_i = g80r_pr_i;
genvar n;
generate
    for (n = 0; n < RAM_BLOCKS; n++) begin : rpool
        dpram_dc #(.widthad_a(ram_aw(n))) ram (
            .clock_a(clk_sys), .address_a(pool_i[n].a_addr[ram_aw(n)-1:0]), .data_a(pool_i[n].a_d),
            .wren_a(pool_i[n].a_we), .q_a(pool_o[n].a_q),
            .clock_b(clk_sys), .address_b(pool_i[n].b_addr[ram_aw(n)-1:0]), .data_b(pool_i[n].b_d),
            .wren_b(pool_i[n].b_we), .q_b(pool_o[n].b_q)
        );
    end
endgenerate

/////////////////////////////  Boards  /////////////////////////////

// every video output registered once in clk_sys before it crosses into the video clock (palette path is combinational)
wire       brd_hsync, brd_vsync, brd_hblank, brd_vblank, brd_ce_pix;
wire [7:0] brd_r, brd_g, brd_b;
reg        vid_hsync_q, vid_vsync_q, vid_hblank_q, vid_vblank_q, vid_ce_pix_q;
reg  [7:0] vid_r_q, vid_g_q, vid_b_q;
always @(posedge clk_sys) begin
    {vid_hsync_q, vid_vsync_q, vid_hblank_q, vid_vblank_q, vid_ce_pix_q} <= {brd_hsync, brd_vsync, brd_hblank, brd_vblank, brd_ce_pix};
    {vid_r_q, vid_g_q, vid_b_q} <= {brd_r, brd_g, brd_b};
end
assign {video_hsync, video_vsync, video_hblank, video_vblank, ce_pix} = {vid_hsync_q, vid_vsync_q, vid_hblank_q, vid_vblank_q, vid_ce_pix_q};
assign {video_r, video_g, video_b} = {vid_r_q, vid_g_q, vid_b_q};

g80r_board g80r (
    .z80_0_i(z80_0_i), .z80_0_o(z80_0_o), .z80_1_i(z80_1_i), .z80_1_o(z80_1_o), .mcs48_0_i(mcs48_0_i),
    .mcs48_0_o(mcs48_0_o), .i8035_0_i(i8035_0_i), .i8035_0_o(i8035_0_o), .sp0250_0_i(sp0250_0_i),
    .sp0250_0_o(sp0250_0_o), .tms36xx_0_i(tms36xx_0_i), .tms36xx_0_o(tms36xx_0_o), .sn76489_i(sn76489_i), .sn76489_o(sn76489_o),
    .rom0_a(rom0_a), .rom0_d(rom0_d), .rom1_a(rom1_a), .rom1_d(rom1_d), .rom2_a(rom2_a), .rom2_d(rom2_d),
    .rom3_a(rom3_a), .rom3_d(rom3_d), .rom4_a(rom4_a), .rom4_d(rom4_d), .rom5_a(rom5_a), .rom5_d(rom5_d),
    .rom6_a(rom6_a), .rom6_d(rom6_d), .rom7_a(rom7_a), .rom7_d(rom7_d), .rom8_a(rom8_a), .rom8_d(rom8_d),
    .rom9_a(rom9_a), .rom9_d(rom9_d), .rom10_a(rom10_a), .rom10_d(rom10_d), .rom11_a(rom11_a), .rom11_d(rom11_d),
    .rom12_a(rom12_a), .rom12_d(rom12_d), .pr_i(g80r_pr_i), .pr_o(pool_o),
    .reset(reset),
    .crt_flip(crt_flip),
    .h_center(h_center),
    .v_center(v_center),
    .clk_sys(clk_sys),
    .game_id(game_id),
    .p1_up(p1_up),
    .p1_down(p1_down),
    .p1_left(p1_left),
    .p1_right(p1_right),
    .p1_fire1(p1_fire1),
    .p1_fire2(p1_fire2),
    .p1_start(p1_start),
    .p1_coin(p1_coin),
    .p2_up(p2_up),
    .p2_down(p2_down),
    .p2_left(p2_left),
    .p2_right(p2_right),
    .p2_fire1(p2_fire1),
    .p2_fire2(p2_fire2),
    .p2_start(p2_start),
    .p2_coin(p2_coin),
    .service(service),
    .self_test(self_test),
    .dip_sw0(dip_sw0),
    .dip_sw1(dip_sw1),
    .dip_sw2(dip_sw2),
    .dip_sw3(dip_sw3),
    .video_hsync(brd_hsync),
    .video_vsync(brd_vsync),
    .video_hblank(brd_hblank),
    .video_vblank(brd_vblank),
    .ce_pix(brd_ce_pix),
    .video_r(brd_r),
    .video_g(brd_g),
    .video_b(brd_b),
    .audio_out(audio_out),
    .ioctl_addr(ioctl_addr),
    .ioctl_wr(ioctl_wr),
    .ioctl_data(ioctl_data),
    .ioctl_index(ioctl_index),
    .pause(pause),
    .hs_address(hs_address),
    .hs_data_in(hs_data_in),
    .hs_data_out(hs_data_out),
    .hs_write(hs_write)
);

endmodule
