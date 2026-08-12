//============================================================================
//
//  Sega G-80 CPU board
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r.cpp:552-583 (memory + port maps), 1059 (clock)
//
//============================================================================

module SegaG80_CPU (
    input              reset,
    input              clk_sys,       // 15.468480 MHz
    input        [2:0] game_id,       // 0=ASTROB,1=MONSTERB,2=SPACEOD,3=005,4=SINDBADM,5=PIGNEWT
    input              pause,
    // SELFTEST-SPLIT-2026-08-11: two distinct switches on real hardware.
    input              service,       // active HIGH, level -> SERVICE1 port bit
    input              self_test,     // active HIGH, edge  -> Z80 NMI

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
    output             ce_cpu_o,

    // Speech board write strobes (to segaspeech in parent)
    output             speech_data_we_o,    // port $38
    output             speech_ctrl_we_o     // port $3B
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

// CLOCK-SWAP-FIX-2026-07-26 — the two clock enables were EXCHANGED.
// MAME (segag80r.cpp:129-132, 1059):
//     VIDEO_CLOCK = 15.46848 MHz     (= our clk_sys)
//     PIXEL_CLOCK = VIDEO_CLOCK/3    = 5.1562 MHz
//     Z80         = VIDEO_CLOCK/4    = 3.8671 MHz
// The comments below always named the right divisors; the pulse POSITIONS
// implemented the opposite. Positions {0,3,6,9} = one pulse every 3 clocks
// (= /3); positions {0,4,8} = one pulse every 4 clocks (= /4). So ce_cpu was
// getting /3 and ce_pix was getting /4 — exactly swapped.
//
// MEASURED before the fix (verilator/scramble, rate_main.cpp):
//     ce_cpu 5.1562 MHz (should be 3.8671), ce_pix 3.8671 MHz (should be 5.1562)
//     implied refresh = ce_pix/(HTOTAL 328 * VTOTAL 262) = 45.00 Hz, not 60.00
// ⇒ the core ran a 45 Hz screen with a Z80 33% too fast. HW-corroborated
// 2026-07-26: MAME plays noticeably FASTER than the core, which is what a
// 45-vs-60 Hz frame rate looks like.
// ORIGINAL (swapped):
// wire ce_cpu_raw = (ph_cnt == 4'd0) || (ph_cnt == 4'd3) ||
//                   (ph_cnt == 4'd6) || (ph_cnt == 4'd9);     // /4
// assign ce_pix_o = (ph_cnt == 4'd0) || (ph_cnt == 4'd4) ||
//                   (ph_cnt == 4'd8);                          // /3
wire ce_cpu_raw = (ph_cnt == 4'd0) || (ph_cnt == 4'd4) ||
                  (ph_cnt == 4'd8);                          // /4 = 3.8671 MHz
assign ce_pix_o = (ph_cnt == 4'd0) || (ph_cnt == 4'd3) ||
                  (ph_cnt == 4'd6) || (ph_cnt == 4'd9);      // /3 = 5.1562 MHz

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
// WAITSTATE-FIX-2026-07-26 — we were charging wait states on things MAME doesn't.
// MAME installs taps on AS_PROGRAM read, AS_PROGRAM write and AS_OPCODES read only
// (segag80r.cpp init_waitstates) — i.e. real MEMORY accesses. There is NO iospace
// tap, and a Z80 M1 REFRESH cycle asserts MREQ but is a DRAM refresh, not a memory
// access, so MAME charges nothing for either.
//
// MEASURED before the fix (verilator/scramble/wait_main.cpp, real ROM, 40M clks):
//   ours 2,072,429 charges vs MAME-equivalent 1,349,139  = 1.54x
//   excess = 722,800 M1 refresh cycles + 490 I/O accesses
//   => ~35% of Z80 time burned on waits MAME never applies.
// That deficit is proportional to workload: invisible when the game is light, but
// once per-frame work exceeds the budget the core cannot finish a frame and
// everything (including audio) drags -- and it does not recover while the load
// stays high. Matches the HW report of a hard slowdown from mid-wave-3 onward that
// MAME does not exhibit.
// Detect the access by MREQ asserted TOGETHER WITH RD or WR, not by the MREQ edge:
//   opcode fetch / mem read : MREQ+RD assert together        -> counted
//   mem write               : WR asserts a cycle AFTER MREQ  -> counted (an MREQ-edge
//                             test would MISS every write)
//   M1 refresh              : MREQ low but RD and WR both high -> correctly ignored
//   I/O                     : IORQ, never MREQ                 -> correctly ignored
// (`rfsh_n` is NOT usable as the qualifier — measured LOW 100% of the time on this
//  T80 build, which silently zeroed access_start when tried. Verify, don't assume.)
// ORIGINAL:
// wire access_start = (mreq_d & ~mreq_n) | (iorq_d & ~iorq_n);
wire mem_acc_now = ~mreq_n & (~rd_n | ~wr_n);
reg  mem_acc_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset) mem_acc_d <= 1'b0;
    else       mem_acc_d <= mem_acc_now;
end
wire access_start = mem_acc_now & ~mem_acc_d;

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
// SELFTEST-SPLIT-2026-08-11: driven by self_test (the CPU-board red switch),
// NOT by service. Was `service` -- which meant the panel service button also
// fired the NMI, and no input could do one without the other.
reg selftest_d, nmi_pulse;
always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        selftest_d <= 1'b0;
        nmi_pulse  <= 1'b0;
    end else begin
        selftest_d <= self_test;
        nmi_pulse  <= self_test & ~selftest_d;   // rising edge
    end
end
wire nmi_n_internal;
// Hold NMI_n low for at least one clk_sys cycle so T80 sees the falling edge.
// NOTE (verified 2026-08-11, T80.vhd:1236-1242): T80's NMI edge detector sits
// OUTSIDE its `if CEN = '1'` block -- it samples NMI_n on every clk_sys edge
// and latches NMI_s until the NMI is serviced, matching a real Z80's internal
// latch and MAME's pulse_input_line(INPUT_LINE_NMI, attotime::zero). So the
// hold does NOT need to align with ce_cpu/CEN; any >=1 clk_sys low pulse is
// captured. Do not "fix" this to track CEN -- that was tried and was based on
// a misreading of T80.
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
//   SCRAMBLE-ONESHOT-FIX-2026-07-26 — CO-SIM PROVEN.
//   The old comment here claimed "MAME ... never clears it after the write — it
//   is simply overwritten by the next opcode fetch." **That is wrong.** MAME
//   clears it inside decrypt_offset (segag80r.cpp:412-421):
//       offs_t pc = m_scrambled_write_pc;
//       m_scrambled_write_pc = 0xffff;      <-- ONE-SHOT, consumed on use
//   i.e. exactly ONE write is scrambled per $32 fetch. Whoever wrote the
//   original read g80r_opcode_r and missed the clear in the other function.
//
//   Why it mattered: the Z80's INTA cycle is M1+IORQ, so mreq_n is HIGH and
//   m1_read below never fires — the latch stayed armed straight through the
//   interrupt acknowledge into the two stack-push WRITES that follow. Those
//   pushes got their low address byte munged, so the return address was stored
//   somewhere else; RETI then popped garbage and the CPU jumped into the weeds.
//   Symptoms: random crashes, spurious screen flip (video_flip is CPU-written),
//   corrupted game state. Frequency depends on an IRQ landing right after an
//   LD (nnnn),A, which is why it looked random.
//
//   MEASURED (verilator/scramble, real T80s via GHDL + this latch + real
//   segag80_decrypt, vs MAME's rule): 149 interrupts, 298 stack writes,
//   **92 mismatches** e.g. push raw=C9FF -> ours C9DF, MAME C9FF.
//
//   The clear is taken on the FALLING edge of the write, not the first cycle of
//   it: the address must stay decrypted for the whole MW cycle or a multi-tick
//   write would split across two addresses.
//   (Faithfulness note: MAME consumes only on RAM/VRAM writes — decrypt_offset
//   is called from mainram_w/vidram_w/usb_ram_w — so the consume is gated to
//   the same address ranges rather than any memory write.)
//----------------------------------------------------------------------------
reg [15:0] scrambled_write_pc;
wire       m1_read = ~m1_n & ~rd_n & ~mreq_n;

// One-shot consume, gated to the ranges MAME routes through decrypt_offset.
wire mem_wr_now  = ~mreq_n & ~wr_n;
wire wr_decodes  = ((cpu_addr >= 16'hC800) & (cpu_addr <= 16'hCFFF))
                 | (cpu_addr >= 16'hE000);
reg  mem_wr_d;
always @(posedge clk_sys or posedge reset) begin
    if (reset) mem_wr_d <= 1'b0;
    else       mem_wr_d <= mem_wr_now & wr_decodes;
end
wire write_ended = mem_wr_d & ~(mem_wr_now & wr_decodes);

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        scrambled_write_pc <= 16'hFFFF;
    else if (m1_read & ce_cpu) begin
        if (cpu_din == 8'h32)
            scrambled_write_pc <= cpu_addr;
        else
            scrambled_write_pc <= 16'hFFFF;
    end
    else if (write_ended)
        scrambled_write_pc <= 16'hFFFF;   // consumed, per MAME decrypt_offset
end

//----------------------------------------------------------------------------
// Decrypt block — munges the low byte of the write address while
// scrambled_write_pc is valid. Stays valid from the 0x32 M1 fetch until
// the next opcode fetch, matching MAME's m_scrambled_write_pc lifecycle.
//----------------------------------------------------------------------------
wire [2:0] chip_sel =
    (game_id == 3'd0) ? 3'd1 :   // ASTROB    → 315-0062
    (game_id == 3'd1) ? 3'd6 :   // MONSTERB  → 315-0082
    (game_id == 3'd2) ? 3'd2 :   // SPACEOD   → 315-0063
    (game_id == 3'd3) ? 3'd4 :   // 005       → 315-0070
    (game_id == 3'd5) ? 3'd2 :   // PIGNEWT   → 315-0063 (same chip as SPACEOD,
                                  //             confirmed via MAME's init_pignewt())
                        3'd0;    // SINDBADM/unknown → no-op

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
wire io_38 = (port_addr == 8'h38);
wire io_3b = (port_addr == 8'h3B);

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
// Logical port assembly — MAME segag80r.cpp g80r_generic + per-game
// PORT_MODIFY overrides. All bits are ACTIVE-LOW unless noted
// (IP_ACTIVE_LOW is the MAME default).
//----------------------------------------------------------------------------
// Per-game control mapping — verified against segag80r.cpp
// INPUT_PORTS_START(<game>) PORT_MODIFY overrides on top of g80r_generic,
// one case arm per game_id, matching MAME's source 1:1. game_id is now
// unique per game (Pig Newton split off id 5 on 2026-07-26 specifically
// because its control layout differs from Space Odyssey's even though
// they share a security chip — see the id comment at this module's top
// and the chip_sel mux above). Full per-game bit layouts differ more than
// a single bit: Space Odyssey moves its buttons into D7D6 entirely, so
// nothing here can be assumed "same for every game."
//
//   ASTROB (0):    2-way, 2 buttons.   D5D4: 2=LEFT,3=BTN1,6=RIGHT,7=BTN2
//   MONSTERB(1)/
//   005(3)/
//   SINDBADM(4)/
//   PIGNEWT(5):    4-way, 1 button.    D7D6: 6=UP
//                                      D5D4: 2=LEFT,3=BTN1,6=RIGHT,7=DOWN
//   SPACEOD (2):   8-way, 2 buttons,   D7D6: 5=BTN2,6=BTN1
//                  MAME tags every                        (no upright
//                  relevant bit                            layout ever
//                  PORT_COCKTAIL                           shipped)
//                  (no upright ever   D5D4: 2=UP,3=LEFT,6=DOWN,7=RIGHT
//                  shipped)
//----------------------------------------------------------------------------
reg d7d6_b5, d7d6_b6;
reg d5d4_b2, d5d4_b3, d5d4_b6, d5d4_b7;
always @(*) begin
    case (game_id)
        3'd0: begin // ASTROB
            d7d6_b5 = 1'b1;      d7d6_b6 = 1'b1;
            d5d4_b2 = ~p1_left;  d5d4_b3 = ~p1_fire1;
            d5d4_b6 = ~p1_right; d5d4_b7 = ~p1_fire2;
        end
        3'd2: begin // SPACEOD
            d7d6_b5 = ~p1_fire2; d7d6_b6 = ~p1_fire1;
            d5d4_b2 = ~p1_up;    d5d4_b3 = ~p1_left;
            d5d4_b6 = ~p1_down;  d5d4_b7 = ~p1_right;
        end
        default: begin // MONSTERB/005/SINDBADM/PIGNEWT
            d7d6_b5 = 1'b1;      d7d6_b6 = ~p1_up;
            d5d4_b2 = ~p1_left;  d5d4_b3 = ~p1_fire1;
            d5d4_b6 = ~p1_right; d5d4_b7 = ~p1_down;
        end
    endcase
end

wire [7:0] logical_d7d6 = {
    1'b1,                    // bit 7 unused (HIGH)
    d7d6_b6,                 // bit 6 = see per-game case above
    d7d6_b5,                 // bit 5 = see per-game case above
    ~p2_coin,                // bit 4 = COIN2
    3'b111,                  // bits 3..1 unused (HIGH)
    ~p1_coin                 // bit 0 = COIN1
};
// NOTE: MiSTer has one coin button per player. We drive both COIN1 and
// COIN2 from p1_coin here for ASTROB single-player. T2.4 overrides with
// a per-game mapping if needed.

wire [7:0] logical_d5d4 = {
    d5d4_b7,                 // bit 7 = see per-game case above
    d5d4_b6,                 // bit 6 = see per-game case above
    ~p2_start,               // bit 5 = START2
    1'b1,                    // bit 4 unused
    d5d4_b3,                 // bit 3 = see per-game case above
    d5d4_b2,                 // bit 2 = see per-game case above
    ~p1_start,               // bit 1 = START1
    ~service                 // bit 0 = SERVICE1
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

// Speech board strobes (MAME segag80r.cpp:1890-1891)
assign speech_data_we_o = io_write & io_38 & ce_cpu;
assign speech_ctrl_we_o = io_write & io_3b & ce_cpu;

endmodule
