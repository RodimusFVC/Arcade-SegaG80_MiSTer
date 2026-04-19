//============================================================================
//
//  Sega G-80 CPU board
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r.cpp:552-583 (memory + port maps), 1059 (clock)
//
//============================================================================

module SegaG80_CPU #(
    parameter [1:0] GAME_ID = 2'd0
) (
    input              reset,
    input              clk_sys,       // 15.468480 MHz
    input              pause,
    input              service,       // active HIGH, edge → NMI

    // Controls
    input              p1_up, p1_down, p1_left, p1_right,
    input              p1_fire1, p1_fire2, p1_start, p1_coin,
    input              p2_up, p2_down, p2_left, p2_right,
    input              p2_fire1, p2_fire2, p2_start, p2_coin,

    input        [7:0] dip_sw0, dip_sw1, dip_sw2, dip_sw3,

    input              vblank_in,     // from video timing (T1.4)

    // ROM loading pass-through (handled here + in T1.3 rom modules)
    input       [24:0] ioctl_addr,
    input              ioctl_wr,
    input        [7:0] ioctl_data,
    input        [7:0] ioctl_index,

    // Exposed Z80 bus (for sub-blocks to observe)
    output             m1_o,
    output             mreq_o,
    output             iorq_o,
    output             rd_o,
    output             wr_o,
    output      [15:0] addr_o,
    output       [7:0] dout_o,
    input        [7:0] din_i,

    // Hiscore (to RAM module in T1.3)
    input       [15:0] hs_address,
    input        [7:0] hs_data_in,
    output       [7:0] hs_data_out,
    input              hs_write,

    // Pixel clock enable (consumed by video timing in T1.4)
    output             ce_pix_o,

    // VRAM bus — segag80_video lives in the parent
    output      [12:0] vram_addr_o,
    output       [7:0] vram_din_o,
    output             vram_wr_o,
    input        [7:0] vidram_din_i,
    output             video_control_1_o,
    output             video_flip_o,

    // Audio bus (to astrob_audio in parent)
    output             audio_we_o,
    output             audio_addr_o,
    output       [7:0] audio_din_o,
    output             ce_cpu_o
);

//----------------------------------------------------------------------------
// Clock enables — MAME segag80r.cpp:1059/132
//   ce_cpu = CLK_SYS / 4  (Z80 clock)
//   ce_pix = CLK_SYS / 3  (pixel clock, consumed by T1.4)
//
// Both generated from a single 12-phase counter (LCM of 3 and 4) so phase
// relationship is stable.
//----------------------------------------------------------------------------
reg [3:0] ph_cnt;   // 0..11 cycling
always @(posedge clk_sys or posedge reset) begin
    if (reset) ph_cnt <= 4'd0;
    else       ph_cnt <= (ph_cnt == 4'd11) ? 4'd0 : ph_cnt + 4'd1;
end

wire ce_cpu_raw = (ph_cnt == 4'd0) || (ph_cnt == 4'd3) ||
                  (ph_cnt == 4'd6) || (ph_cnt == 4'd9);     // /4
assign ce_pix_o = (ph_cnt == 4'd0) || (ph_cnt == 4'd4) ||
                  (ph_cnt == 4'd8);                          // /3

// Pause holds ce_cpu low so the Z80 freezes. Pixel clock keeps running so
// the video output isn't destabilized.
wire ce_cpu = ce_cpu_raw & ~pause;

//----------------------------------------------------------------------------
// Wait-state shim — Sega G-80 holds MREQ for ~2 extra cycles per access
// (segag80r.cpp:145 WAIT_STATES = 2). Implement as a wait counter that
// suppresses ce_cpu for 2 z80 clocks after each new MREQ/IORQ.
//----------------------------------------------------------------------------
reg [1:0] ws_cnt;
reg       mreq_d, iorq_d;
always @(posedge clk_sys) begin
    mreq_d <= mreq_n;
    iorq_d <= iorq_n;
end
wire access_start = (mreq_d & ~mreq_n) | (iorq_d & ~iorq_n);

always @(posedge clk_sys or posedge reset) begin
    if (reset)                  ws_cnt <= 2'd0;
    else if (access_start)      ws_cnt <= 2'd2;
    else if (ce_cpu && ws_cnt)  ws_cnt <= ws_cnt - 2'd1;
end
wire cpu_wait = (ws_cnt != 2'd0);

//----------------------------------------------------------------------------
// NMI from service switch — edge-triggered pulse
// MAME segag80r.cpp:375 INPUT_CHANGED_MEMBER(service_switch) pulse_input_line(NMI)
//----------------------------------------------------------------------------
reg service_d, nmi_pulse;
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        service_d <= 1'b0;
        nmi_pulse <= 1'b0;
    end else begin
        service_d <= service;
        nmi_pulse <= service & ~service_d;   // rising edge
    end
end
wire nmi_n_internal;
// Hold NMI low for one ce_cpu cycle after rising edge.
reg nmi_hold;
always @(posedge clk_sys or posedge reset) begin
    if (reset)            nmi_hold <= 1'b0;
    else if (nmi_pulse)   nmi_hold <= 1'b1;
    else if (ce_cpu)      nmi_hold <= 1'b0;
end
assign nmi_n_internal = ~nmi_hold;

//----------------------------------------------------------------------------
// IRQ — MAME segag80r_v.cpp:42-56
//   vblank_start: if (video_control & 0x04) ASSERT_LINE /INT
//   IRQ_CALLBACK: CLEAR_LINE /INT, return 0xFF (vectorless → RST 38h)
//----------------------------------------------------------------------------
reg vblank_d;
wire vblank_rising = vblank_in & ~vblank_d;
always @(posedge clk_sys) vblank_d <= vblank_in;

reg irq_pend;
wire irq_ack = ~m1_n & ~iorq_n;   // Z80 INTA cycle

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        irq_pend <= 1'b0;
    else if (vblank_rising && video_control[2])
        irq_pend <= 1'b1;
    else if (irq_ack && ce_cpu)
        irq_pend <= 1'b0;
end

wire irq_n_internal = ~irq_pend;

//----------------------------------------------------------------------------
// T80 instantiation
//----------------------------------------------------------------------------
wire        mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, busak_n, halt_n;
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
reg   [7:0] cpu_din;

T80s T80_inst (
    .RESET_n   (~reset),
    .CLK       (clk_sys),
    .CEN       (ce_cpu & ~cpu_wait),
    .WAIT_n    (1'b1),
    .INT_n     (irq_n_internal),
    .NMI_n     (nmi_n_internal),
    .BUSRQ_n   (1'b1),
    .M1_n      (m1_n),
    .MREQ_n    (mreq_n),
    .IORQ_n    (iorq_n),
    .RD_n      (rd_n),
    .WR_n      (wr_n),
    .RFSH_n    (rfsh_n),
    .HALT_n    (halt_n),
    .BUSAK_n   (busak_n),
    .A         (cpu_addr),
    .DI        (cpu_din),
    .DO        (cpu_dout)
);

// Expose to parent
assign m1_o   = ~m1_n;
assign mreq_o = ~mreq_n;
assign iorq_o = ~iorq_n;
assign rd_o   = ~rd_n;
assign wr_o   = ~wr_n;
assign addr_o = cpu_addr;
assign dout_o = cpu_dout;

//----------------------------------------------------------------------------
// Scrambled-write PC latch — MAME segag80r.cpp:400-410 (g80r_opcode_r)
//   On every M1 opcode fetch: latch PC if the fetched byte is 0x32
//   (LD (nn),A), otherwise set sentinel 0xFFFF.
//
//   MAME updates m_scrambled_write_pc ONLY inside g80r_opcode_r and never
//   clears it after the write — it is simply overwritten by the next
//   opcode fetch. We match that lifecycle so decrypt_addr stays valid
//   across the entire MW cycle (and any future multi-tick WR_n timing).
//----------------------------------------------------------------------------
reg [15:0] scrambled_write_pc;
wire       m1_read = ~m1_n & ~rd_n & ~mreq_n;

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        scrambled_write_pc <= 16'hFFFF;
    else if (m1_read & ce_cpu) begin
        if (cpu_din == 8'h32)
            scrambled_write_pc <= cpu_addr;
        else
            scrambled_write_pc <= 16'hFFFF;
    end
end

//----------------------------------------------------------------------------
// Decrypt block — munges the low byte of the write address while
// scrambled_write_pc is valid. Stays valid from the 0x32 M1 fetch until
// the next opcode fetch, matching MAME's m_scrambled_write_pc lifecycle.
//----------------------------------------------------------------------------
wire [2:0] chip_sel =
    (GAME_ID == 2'd0) ? 3'd1 :   // ASTROB → 62
    (GAME_ID == 2'd1) ? 3'd6 :   // MONSTERB → 82
    /* SPACEOD */       3'd0;    // no decrypt

wire [7:0] decrypted_lo;
segag80_decrypt decrypt_inst (
    .pc        (scrambled_write_pc),
    .lo_in     (cpu_addr[7:0]),
    .chip_sel  (chip_sel),
    .lo_out    (decrypted_lo)
);

wire        decrypt_active = (scrambled_write_pc != 16'hFFFF);
wire [15:0] decrypt_addr   = decrypt_active ? {cpu_addr[15:8], decrypted_lo}
                                            : cpu_addr;

//----------------------------------------------------------------------------
// Address decode — segag80r.cpp:552-559
//----------------------------------------------------------------------------
wire mem_read  = ~mreq_n & ~rd_n;
wire mem_write = ~mreq_n & ~wr_n;
wire io_read   = ~iorq_n & ~rd_n & ~(~m1_n);   // not during INTA
wire io_write  = ~iorq_n & ~wr_n;

wire rom_sel   = mem_read  & (cpu_addr < 16'hC000);                // 0x0000–0xBFFF
wire ram_sel   = (cpu_addr >= 16'hC800) & (cpu_addr <= 16'hCFFF);   // 0xC800–0xCFFF
wire vram_sel  = (cpu_addr >= 16'hE000);                            // 0xE000–0xFFFF

//----------------------------------------------------------------------------
// Port decode — segag80r.cpp:576-583
//   0xBE/0xBF : video port r/w
//   0xF8-0xFB : mangled ports (read)
//   0xF9      : coin counter write (mirror 0xFD)
//   0xFC      : direct FC port (read)
//----------------------------------------------------------------------------
wire [7:0] port_addr = cpu_addr[7:0];
wire io_be_bf = (port_addr == 8'hBE) | (port_addr == 8'hBF);
wire io_f8_fb = (port_addr >= 8'hF8) & (port_addr <= 8'hFB);
// $F9 and mirror $FD are coin-counter writes (MAME segag80r.cpp:513-517).
// No physical counter to drive on MiSTer; decoded so as to decode-complete
// the write but value is discarded.
wire io_f9    = (port_addr == 8'hF9) | (port_addr == 8'hFD);
wire io_fc    = (port_addr == 8'hFC);

// Astro Blaster audio ($3E/$3F) — MAME segag80r.cpp:1894
wire io_3e_3f = (port_addr == 8'h3E) | (port_addr == 8'h3F);

// Speech board ($38 data, $3B control) — MAME segag80r.cpp:1889-1891.
// Decoded here to keep the bus happy; data is dropped. See T2.3 notes.
wire io_38    = (port_addr == 8'h38);
wire io_3b    = (port_addr == 8'h3B);
wire io_speech = io_38 | io_3b;

// Silence lint warning by using the signal in a way the optimizer drops.
(* keep = "false" *) wire _speech_sink = io_speech & io_write;

//----------------------------------------------------------------------------
// Program ROM (48 KB) — loaded from ioctl index 0
//----------------------------------------------------------------------------
wire [7:0] rom_dout;
segag80_rom prog_rom (
    .clk         (clk_sys),
    .ioctl_addr  (ioctl_addr),
    .ioctl_data  (ioctl_data),
    .ioctl_wr    (ioctl_wr),
    .ioctl_index (ioctl_index),
    .cpu_addr    (cpu_addr),
    .cpu_dout    (rom_dout)
);

//----------------------------------------------------------------------------
// Main RAM 2KB @ 0xC800–0xCFFF — dual-port: Z80 + hiscore
//----------------------------------------------------------------------------
wire [7:0] mainram_dout;
wire [7:0] mainram_hs_rd;

dpram_dc #(.widthad_a(11), .width_a(8)) mainram_inst (
    .clock_a   (clk_sys),
    .address_a (ram_sel & mem_write ? decrypt_addr[10:0] : cpu_addr[10:0]),
    .data_a    (cpu_dout),
    .wren_a    (ram_sel & mem_write & ce_cpu),
    .q_a       (mainram_dout),

    .clock_b   (clk_sys),
    .address_b (hs_address[10:0]),
    .data_b    (hs_data_in),
    .wren_b    (hs_write),
    .q_b       (mainram_hs_rd)
);

//----------------------------------------------------------------------------
// Video RAM 8KB @ 0xE000–0xFFFF — owned by segag80_video in the parent.
// We expose the CPU write port and read port here via extra ports.
//----------------------------------------------------------------------------
// vidram_dout is driven by the parent through a new input vidram_din_i.
wire [7:0] vidram_dout = vidram_din_i;

//----------------------------------------------------------------------------
// Video port $BE/$BF  (MAME segag80r_v.cpp:287-324)
//
//   Write $BE (offset 0): unused (logs only)
//   Write $BF (offset 1): m_video_control (FLIP, palette access, int enable, n/c)
//   Read  $BE           : 0xFF (unused)
//   Read  $BF           : {0xF8, int_en, video_flip, vblank_latch}
//
// Hooked here; T1.7 extends the vblank_latch / m_video_flip handling.
//----------------------------------------------------------------------------
reg [7:0] video_control;    // latched at port $BF write
always @(posedge clk_sys or posedge reset) begin
    if (reset)
        video_control <= 8'd0;
    else if (io_write & io_be_bf & port_addr[0] & ce_cpu)
        video_control <= cpu_dout;
end

//----------------------------------------------------------------------------
// 555 monostable approximation for vblank_latch.
//   R=56k, C=1000pF → ~39 µs pulse. At 15.468480 MHz that's ~603 clocks.
//----------------------------------------------------------------------------
reg [9:0] vblank_latch_cnt;
always @(posedge clk_sys or posedge reset) begin
    if (reset)
        vblank_latch_cnt <= 10'd0;
    else if (vblank_rising)
        vblank_latch_cnt <= 10'd603;
    else if (vblank_latch_cnt != 10'd0)
        vblank_latch_cnt <= vblank_latch_cnt - 10'd1;
end
wire vblank_latch = (vblank_latch_cnt != 10'd0);

//----------------------------------------------------------------------------
// video_flip — latched at vblank start from video_control[0]
//----------------------------------------------------------------------------
reg video_flip_r;
always @(posedge clk_sys or posedge reset) begin
    if (reset)                video_flip_r <= 1'b0;
    else if (vblank_rising)   video_flip_r <= video_control[0];
end

wire [7:0] video_port_r =
    port_addr[0] ? {5'b11111, video_control[2], video_flip_r, vblank_latch}
                 : 8'hFF;

//----------------------------------------------------------------------------
// Logical port assembly — MAME segag80r.cpp:632-706 + 720-747 (astrob)
// All bits are ACTIVE-LOW unless noted (IP_ACTIVE_LOW is the MAME default).
//----------------------------------------------------------------------------
wire [7:0] logical_d7d6 = {
    3'b111,                 // bits 7..5 unused (HIGH)
    ~p2_coin,               // bit 4 = COIN2
    3'b111,                 // bits 3..1 unused (HIGH)
    ~p1_coin                // bit 0 = COIN1
};
// NOTE: MiSTer has one coin button per player. We drive both COIN1 and
// COIN2 from p1_coin here for ASTROB single-player. T2.4 overrides with
// a per-game mapping if needed.

wire [7:0] logical_d5d4 = {
    ~p1_fire2,              // bit 7 = BUTTON2 (cocktail-flipped in MAME,
                            //                  but D5D4 is upright-side)
    ~p1_right,              // bit 6 = JOYSTICK_RIGHT
    ~p2_start,              // bit 5 = START2
    1'b1,                   // bit 4 unused
    ~p1_fire1,              // bit 3 = BUTTON1
    ~p1_left,               // bit 2 = JOYSTICK_LEFT
    ~p1_start,              // bit 1 = START1
    ~service                // bit 0 = SERVICE1
};

wire [7:0] logical_d3d2 = dip_sw0;     // SW1 bank, active-LOW
wire [7:0] logical_d1d0 = dip_sw1;     // SW2 bank, active-LOW

//----------------------------------------------------------------------------
// demangle — MAME segag80r.cpp:443-449
//----------------------------------------------------------------------------
function [7:0] demangle;
    input [7:0] d7d6;
    input [7:0] d5d4;
    input [7:0] d3d2;
    input [7:0] d1d0;
    begin
        demangle = ((d7d6 << 7) & 8'h80) | ((d7d6 << 2) & 8'h40) |
                   ((d5d4 << 5) & 8'h20) | ((d5d4 << 0) & 8'h10) |
                   ((d3d2 << 3) & 8'h08) | ((d3d2 >> 2) & 8'h04) |
                   ((d1d0 << 1) & 8'h02) | ((d1d0 >> 4) & 8'h01);
    end
endfunction

//----------------------------------------------------------------------------
// Mangled port read — MAME segag80r.cpp:452-465
//   shift = port_addr & 3; each logical byte is right-shifted by shift.
//----------------------------------------------------------------------------
wire [1:0] mux_shift = port_addr[1:0];
wire [7:0] mangled_dout = demangle(
    logical_d7d6 >> mux_shift,
    logical_d5d4 >> mux_shift,
    logical_d3d2 >> mux_shift,
    logical_d1d0 >> mux_shift
);

//----------------------------------------------------------------------------
// FC direct port — ACTIVE-HIGH per MAME astrob layout (cocktail side)
//----------------------------------------------------------------------------
wire [7:0] fc_dout = {
    p2_left,                // 7
    p2_right,               // 6
    p2_fire1,               // 5
    p2_fire2,               // 4
    4'b0000                 // 3..0 unused
};

//----------------------------------------------------------------------------
// Coin counter write ($F9) — MAME segag80r.cpp:513-517. Bookkeeping only; we
// have nothing to hook a coin counter to on MiSTer, so just absorb it.
//----------------------------------------------------------------------------
// (No state needed; value discarded.)

//----------------------------------------------------------------------------
// CPU data-in mux
//----------------------------------------------------------------------------
always @* begin
    casez (1'b1)
        (rom_sel):              cpu_din = rom_dout;
        (ram_sel  & mem_read):  cpu_din = mainram_dout;
        (vram_sel & mem_read):  cpu_din = vidram_dout;
        (io_read  & io_be_bf):  cpu_din = video_port_r;
        (io_read  & io_f8_fb):  cpu_din = mangled_dout;
        (io_read  & io_fc):     cpu_din = fc_dout;
        default:                cpu_din = 8'hFF;
    endcase
end

//----------------------------------------------------------------------------
// Hiscore read-back from mainram port B
//----------------------------------------------------------------------------
assign hs_data_out = mainram_hs_rd;

// Expose VRAM bus to parent (segag80_video instance lives there).
assign vram_addr_o       = (vram_sel & mem_write) ? decrypt_addr[12:0]
                                                  : cpu_addr[12:0];
assign vram_din_o        = cpu_dout;
assign vram_wr_o         = vram_sel & mem_write & ce_cpu;
assign video_control_1_o = video_control[1];
assign video_flip_o      = video_flip_r;

// Astro Blaster audio bus
assign audio_we_o   = io_write & io_3e_3f;
assign audio_addr_o = port_addr[0];
assign audio_din_o  = cpu_dout;
assign ce_cpu_o     = ce_cpu;

endmodule
