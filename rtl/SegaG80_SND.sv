//============================================================================
//
//  Kangaroo Sound Board (TVG-1-CPU-B, sound section)
//  Based on MAME kangaroo.cpp
//
//  Sound memory map:
//    0x0000-0x0FFF  ROM (tvg_81)
//    0x4000-0x43FF  RAM (1KB, mirrored 0x4000-0x4FFF)
//    0x6000         Soundlatch read (mirrored 0x6000-0x6FFF)
//    0x7000         AY-3-8910 data write (mirrored 0x7000-0x7FFF)
//    0x8000         AY-3-8910 address write (mirrored 0x8000-0x8FFF)
//
//  IRQ: vblank (same as main CPU)
//
//============================================================================

module Kangaroo_SND
(
    input         reset,
    input         clk_10m,           // 10 MHz master clock

    // Sound latch from main CPU
    input   [7:0] sound_latch,
    input         sound_latch_wr,    // Active pulse when latch written

    // VBlank for IRQ
    input         vblank,

    // Sound ROM loading (index 1)
    input  [24:0] ioctl_addr,
    input   [7:0] ioctl_data,
    input         ioctl_wr,
    input         sndrom_cs_i,       // Directly from ioctl_index == 1

    // Audio output
    output signed [15:0] sound_out,

    input         pause
);

//------------------------------------------------------- Clock Enables -------------------------------------------------------//

// 2.5 MHz for Z80 (10/4), 1.25 MHz for AY (10/8)
reg [2:0] div = 3'd0;
always_ff @(posedge clk_10m) begin
    div <= div + 3'd1;
end
wire cen_2m5 = (div[1:0] == 2'd0);    // Every 4th clock
wire cen_1m25 = (div == 3'd0);         // Every 8th clock

//------------------------------------------------------------ CPU -------------------------------------------------------------//

wire [15:0] snd_A;
wire  [7:0] snd_Dout;
wire n_m1, n_mreq, n_iorq, n_rd, n_wr, n_rfsh;

T80s #(.Mode(0), .T2Write(1), .IOWait(1)) sound_cpu
(
    .RESET_n(reset),
    .CLK(clk_10m),
    .CEN(cen_2m5 & ~pause),
    .INT_n(n_irq),
    .NMI_n(1'b1),
    .BUSRQ_n(1'b1),
    .M1_n(n_m1),
    .MREQ_n(n_mreq),
    .IORQ_n(n_iorq),
    .RD_n(n_rd),
    .WR_n(n_wr),
    .RFSH_n(n_rfsh),
    .A(snd_A),
    .DI(snd_Din),
    .DO(snd_Dout)
);

//------------------------------------------------------ Address Decoding ------------------------------------------------------//

wire mem_access = ~n_mreq & n_rfsh;
wire io_access  = ~n_iorq;
wire any_access = mem_access | io_access;

wire cs_sndrom  = mem_access & (snd_A[15:12] == 4'h0);
wire cs_sndram  = mem_access & (snd_A[15:12] == 4'h4);
wire cs_slatch  = any_access & (snd_A[15:12] == 4'h6) & ~n_rd;
wire cs_ay_data = any_access & (snd_A[15:12] == 4'h7) & ~n_wr;
wire cs_ay_addr = any_access & (snd_A[15:12] == 4'h8) & ~n_wr;

//--------------------------------------------------------- Data Mux -----------------------------------------------------------//

wire [7:0] sndrom_D;
wire [7:0] sndram_D;
wire [7:0] ay_Dout;

wire [7:0] snd_Din =
    cs_sndrom                  ? sndrom_D :
    (cs_sndram & ~n_rd)       ? sndram_D :
    cs_slatch                  ? sound_latch :
    8'hFF;

//-------------------------------------------------------- Sound ROM -----------------------------------------------------------//

eprom_4k sndrom
(
    .ADDR(snd_A[11:0]),
    .CLK(clk_10m),
    .DATA(sndrom_D),
    .ADDR_DL(ioctl_addr),
    .CLK_DL(clk_10m),
    .DATA_IN(ioctl_data),
    .CS_DL(sndrom_cs_i),
    .WR(ioctl_wr)
);

//-------------------------------------------------------- Sound RAM -----------------------------------------------------------//

// 1KB RAM at 0x4000-0x43FF (mirrored to 0x4FFF)
spram #(.DATA_WIDTH(8), .ADDR_WIDTH(10)) sndram
(
    .clk(clk_10m),
    .addr(snd_A[9:0]),
    .data(snd_Dout),
    .q(sndram_D),
    .we(cs_sndram & ~n_wr)
);

//------------------------------------------------------- AY-3-8910 -----------------------------------------------------------//

// AY uses bdir/bc1 interface. For Kangaroo's memory-mapped scheme:
// 0x7000 write = data write:    bdir=1, bc1=0
// 0x8000 write = address write: bdir=1, bc1=1
// All other times:              bdir=0, bc1=0 (inactive)
wire ay_bdir = cs_ay_data | cs_ay_addr;
wire ay_bc1  = cs_ay_addr;

wire [7:0] ayA_raw, ayB_raw, ayC_raw;

jt49_bus #(.COMP(3'b010)) ay_chip
(
    .rst_n(reset),
    .clk(clk_10m),
    .clk_en(cen_1m25),
    .bdir(ay_bdir),
    .bc1(ay_bc1),
    .din(snd_Dout),
    .sel(1'b1),        // No additional clock division
    .dout(ay_Dout),
    .A(ayA_raw),
    .B(ayB_raw),
    .C(ayC_raw),
    .IOA_in(8'h00),
    .IOB_in(8'h00)
);

//-------------------------------------------------------- VBlank IRQ ----------------------------------------------------------//

// Same as main CPU: standard IM1 vblank IRQ
reg n_irq = 1'b1;
reg vblank_last = 0;
always_ff @(posedge clk_10m) begin
    if(!reset) begin
        n_irq <= 1'b1;
        vblank_last <= 0;
    end
    else begin
        vblank_last <= vblank;
        if(vblank & ~vblank_last)
            n_irq <= 1'b0;
        if(~n_m1 & ~n_iorq)
            n_irq <= 1'b1;
    end
end

//----------------------------------------------------- Final Audio Output -----------------------------------------------------//

// Simple mix: sum three unsigned 8-bit channels, apply 50% gain, output as signed 16-bit
// MAME: AY8910 route ALL_OUTPUTS to mono at 0.50
wire [9:0] ay_sum = {2'b00, ayA_raw} + {2'b00, ayB_raw} + {2'b00, ayC_raw};

// Convert unsigned sum to signed 16-bit with appropriate scaling
// Max sum = 3*255 = 765, center at ~383. Scale up to fill 16-bit range.
wire signed [15:0] ay_signed = {1'b0, ay_sum, 5'd0} - 16'sd12288;  // rough center + scale

assign sound_out = ay_signed;

// DEBUG: 1kHz test tone
//reg [13:0] tone_cnt = 0;
//always_ff @(posedge clk_10m) begin
//    tone_cnt <= tone_cnt + 1;
//end
//wire signed [15:0] test_tone = tone_cnt[13] ? 16'sd4000 : -16'sd4000;

endmodule
