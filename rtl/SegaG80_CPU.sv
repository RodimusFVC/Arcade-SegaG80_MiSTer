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
    output             video_control_3_o,   // background board flip
    output             video_control_6_o,   // Monster Bash bg palette enable
    output       [7:0] mb_snd_cmd_o,        // Monster Bash $0E latch -> uPD7751
    input              mb_snd_busy_i,       // uPD7751 status -> $0E read bit 4

    // Background board registers (ports $B8-$BD)
    output       [9:0] bg_scrollx_o,
    output      [10:0] bg_scrolly_o,
    output             bg_enable_o,
    output       [3:0] bg_char_bank_o,

    // Audio bus (to astrob_audio in parent)
    output             audio_we_o,
    output             audio_addr_o,
    output       [7:0] audio_din_o,
    output             ce_cpu_o,

    // Speech board write strobes (to segaspeech in parent)
    output             speech_data_we_o,    // port $38
    output             speech_ctrl_we_o,    // port $3B

    // Sega Universal Sound Board (to sega_usb in parent) — Pig Newton only.
    // $3F is data write / status read; $D000-$DFFF is the shared program RAM,
    // whose writes go through the security scrambler exactly like VRAM's.
    output             usb_data_wr_o,
    output       [7:0] usb_din_o,
    input        [7:0] usb_status_i,
    output      [11:0] usb_pgm_addr_o,
    output       [7:0] usb_pgm_din_o,
    output             usb_pgm_wr_o,
    input        [7:0] usb_pgm_dout_i,

    // Space Odyssey background board ports ($08-$0F)
    output             so_port_wr_o,
    output       [2:0] so_port_addr_o,
    output       [7:0] so_port_din_o,
    input        [7:0] so_port_dout_i
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

// Sindbad (sindbadm_vblank_start): interrupts are ALWAYS enabled — not masked
// by video_control[2] — and are acknowledged MANUALLY by a write to $40, not by
// the INTA cycle. Its machine_config replaces the CPU without re-installing
// segag80r_irq_ack, so INTA must not clear the latch on that game.
wire sm_irq_ack = sm_en & io_write & io_40 & ce_cpu;

always @(posedge clk_sys or posedge reset) begin
    if (reset)
        irq_pend <= 1'b0;
    else if (vblank_rising && (sm_en || video_control[2]))
        irq_pend <= 1'b1;
    else if (sm_en ? sm_irq_ack : (irq_ack && ce_cpu))
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

// USB shared program RAM — MAME init_pignewt installs this over $D000-$DFFF,
// a window no other G-80 raster game decodes.
wire usb_sel   = usb_en & (cpu_addr >= 16'hD000) & (cpu_addr <= 16'hDFFF);

//----------------------------------------------------------------------------
// Port decode — segag80r.cpp:576-583
//   0xBE/0xBF : video port r/w
//   0xF8-0xFB : mangled ports (read)
//   0xF9      : coin counter write (mirror 0xFD)
//   0xFC      : direct FC port (read)
//----------------------------------------------------------------------------
wire [7:0] port_addr = cpu_addr[7:0];
wire io_be_bf = (port_addr == 8'hBE) | (port_addr == 8'hBF);

// Sindbad Mystery has its own I/O map (MAME sindbadm_portmap):
//   $40 = IRQ acknowledge, $41 = background control,
//   $42/$43 = video ports (NOT $BE/$BF), $80-$83 = i8255 PPI,
//   $F8-$FB = mangled ports, and no $FC at all.
wire sm_en    = (game_id == 3'd4);
wire io_42_43 = (port_addr == 8'h42) | (port_addr == 8'h43);
wire io_80_83 = (port_addr >= 8'h80) & (port_addr <= 8'h83);
wire io_40    = (port_addr == 8'h40);

// Video port select — same register, different address on Sindbad. Bit 0 picks
// the control register in both cases ($BF and $43).
wire io_vid   = sm_en ? io_42_43 : io_be_bf;
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

// Background board ($B8-$BD) — MAME segag80r.cpp:1997-1999 (init_pignewt).
// $B4/$B5 (pignewt_back_color_w) has no known rendering effect and is absorbed.
wire io_b8_bd = (port_addr >= 8'hB8) & (port_addr <= 8'hBD);

// Universal Sound Board — Pig Newton only. $3F is shared with the Astro
// Blaster audio port, so both sides are gated on game_id.
wire usb_en = (game_id == 3'd5);
wire io_3f  = (port_addr == 8'h3F);

// Space Odyssey background board ($08-$0F) — MAME segag80r.cpp:1926-1929.
// Reads return 0xFE | bg_detect; $0E/$0F are also the sound-board write
// ports, which back_port_w treats as no-ops.
wire so_en    = (game_id == 3'd2);

// Monster Bash i8255 PPI ($0C-$0F) — MAME main_ppi8255_portmap + monsterb().
//   $0C = port A (TMS3617 music), $0D = port B (SHOT/DIVE triggers),
//   $0E = port C (uPD7751 command out, BUSY status in), $0F = control.
// Only the read matters here: upd7751_status_r returns busy<<4, so the
// undecoded 8'hFF default reads as permanently busy and hangs the game at
// coin-up. 005 shares this port map but never reads it, which is why only
// Monster Bash is affected.
wire mb_en    = (game_id == 3'd1);

// Sindbad's i8255 has in_pb_callback = ioport("FC"), so the game reads player
// inputs through PPI port B ($81). Layout is sindbadm's FC PORT_MODIFY, all
// ACTIVE-LOW: d0 LEFT, d1 RIGHT, d2 BUTTON1, d3 DOWN, d4 UP, d7:5 unused.
wire [7:0] sm_ppi_b = {3'b111, ~p2_up, ~p2_down, ~p2_fire1, ~p2_right, ~p2_left};

// Monster Bash PPI port C ($0E) write — upd7751_command_w: d0-d2 command to
// the 7751's S0-2, d3 = /INT. Latched here and handed to the voice board.
reg [7:0] mb_snd_cmd;
always @(posedge clk_sys or posedge reset) begin
    if (reset)                                            mb_snd_cmd <= 8'h08;
    else if (mb_en & io_write & (port_addr == 8'h0E) & ce_cpu) mb_snd_cmd <= cpu_dout;
end
assign mb_snd_cmd_o = mb_snd_cmd;
wire [7:0] sm_ppi_dout = (port_addr[1:0] == 2'd1) ? sm_ppi_b : 8'h00;
wire io_0c_0f = (port_addr >= 8'h0C) & (port_addr <= 8'h0F);
wire io_08_0f = (port_addr >= 8'h08) & (port_addr <= 8'h0F);

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

// Sindbad Mystery's Z80 is a Sega 315-5028: $0000-$7FFF is encrypted, with
// separate opcode-fetch and data-read tables. $8000+ is plaintext.
wire       sindbadm_en = (game_id == 3'd4);
wire [7:0] rom_dout_dec;

segag80_5028 u_dec5028 (
    .src  (rom_dout),
    .addr (cpu_addr),
    .m1   (~m1_n),
    .dout (rom_dout_dec)
);

wire [7:0] rom_dout_eff = (sindbadm_en & ~cpu_addr[15]) ? rom_dout_dec : rom_dout;

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
    else if (io_write & io_vid & port_addr[0] & ce_cpu)
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

//----------------------------------------------------------------------------
// Background board registers — MAME segag80r_v.cpp pignewt_back_port_w.
//   $B8 scroll X low   $B9 scroll X high (d1..d0) + enable (d7)
//   $BA scroll Y low   $BB scroll Y high (d1..d0)
//   $BC character bank — MAME remaps to (d&0x09)|((d>>2)&2)|((d<<2)&4),
//                        i.e. only d3 and d0 survive, as {d3,d0,d3,d0}
//   $BD not connected
//----------------------------------------------------------------------------
// Monster Bash uses the SAME $B8-$BD range with different semantics
// (monsterb_back_port_w): only port 4 is connected, carrying char bank,
// an 8-page Y select and the enable. It has no X scroll, and unlike Pig
// Newton all four char-bank bits are significant.
reg [9:0]  bg_scrollx;
reg [10:0] bg_scrolly;      // 11 bits — Monster Bash pages reach 0x700
reg        bg_enable;
reg [3:0]  bg_char_bank;

always @(posedge clk_sys or posedge reset) begin
    if (reset) begin
        bg_scrollx   <= 10'd0;
        bg_scrolly   <= 11'd0;
        bg_enable    <= 1'b0;
        bg_char_bank <= 4'd0;
    end else if (sm_en & io_write & (port_addr == 8'h41) & ce_cpu) begin
        // sindbadm_back_port_w port 1: d0-d1 ROM bank, d2-d3 X page,
        // d4-d6 Y page, d7 enable. Port 0 ($40) is the IRQ ack, handled above.
        bg_char_bank <= {2'b00, cpu_dout[1:0]};
        bg_scrollx   <= {cpu_dout[3:2], 8'd0};   // (data << 6) & 0x300
        bg_scrolly   <= {cpu_dout[6:4], 8'd0};   // (data << 4) & 0x700
        bg_enable    <= cpu_dout[7];
    end else if (io_write & io_b8_bd & ce_cpu & ~sm_en) begin
        if (mb_en) begin
            // d0-d3 = CG0-CG3, d4-d6 = SCN0-2, d7 = BKGEN
            if (port_addr[2:0] == 3'd4) begin
                bg_char_bank <= cpu_dout[3:0];
                bg_scrolly   <= {cpu_dout[6:4], 8'd0};   // (data << 4) & 0x700
                bg_enable    <= cpu_dout[7];
            end
        end else begin
            case (port_addr[2:0])
                3'd0: bg_scrollx[7:0] <= cpu_dout;
                3'd1: begin
                    bg_scrollx[9:8] <= cpu_dout[1:0];
                    bg_enable       <= cpu_dout[7];
                end
                3'd2: bg_scrolly[7:0] <= cpu_dout;
                3'd3: bg_scrolly[9:8] <= cpu_dout[1:0];
                3'd4: bg_char_bank    <= {cpu_dout[3], cpu_dout[0], cpu_dout[3], cpu_dout[0]};
                default: ;
            endcase
        end
    end
end

assign bg_scrollx_o   = bg_scrollx;
assign bg_scrolly_o   = bg_scrolly;
assign bg_enable_o    = bg_enable;
assign bg_char_bank_o = bg_char_bank;
assign video_control_3_o = video_control[3];
assign video_control_6_o = video_control[6];

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
//   SPACEOD (2):   8-way, 2 buttons. UNIQUE: it is the only G-80 raster game
//                  whose $FC port carries PLAYER 1 (every other game tags
//                  those bits PORT_COCKTAIL = player 2). D7D6/D5D4 hold the
//                  COCKTAIL (P2) side: D7D6 5=BTN2,6=BTN1;
//                  D5D4 2=UP,3=LEFT,6=DOWN,7=RIGHT. In UPRIGHT the game
//                  re-reads P1's UP/BTN1/BTN2 out of D5D4 — see the
//                  spaceod_mangled_ports_r / spaceod_port_fc_r block below.
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
        3'd2: begin // SPACEOD — these are the COCKTAIL (P2) bits; P1 is on $FC
            d7d6_b5 = ~p2_fire2; d7d6_b6 = ~p2_fire1;
            d5d4_b2 = ~p2_up;    d5d4_b3 = ~p2_left;
            d5d4_b6 = ~p2_down;  d5d4_b7 = ~p2_right;
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
//----------------------------------------------------------------------------
// Space Odyssey cabinet shuffle — MAME spaceod_mangled_ports_r (468-495) and
// spaceod_port_fc_r (496-509). The ports are wired for COCKTAIL; in UPRIGHT
// the cocktail bits are forced inactive and P1's UP/BUTTON1/BUTTON2 are read
// out of D5D4 bits 4/3/2 instead, while $FC keeps only LEFT/RIGHT/DOWN with
// the two horizontal bits swapped.
//----------------------------------------------------------------------------
wire so_upright = logical_d3d2[2];          // Cabinet DIP: 1 = upright

// $FC as MAME codes it for spaceod: PLAYER 1, ACTIVE-HIGH.
wire [7:0] so_fc_raw = {2'b00, p1_fire2, p1_fire1, p1_up, p1_down, p1_right, p1_left};

// spaceod_port_fc_r: swap D0/D1 and mask to 0x07.
wire [7:0] so_fc_dout = so_upright ? {5'b00000, so_fc_raw[2], so_fc_raw[0], so_fc_raw[1]}
                                   : so_fc_raw;

// spaceod_mangled_ports_r: d7d6 |= 0x60; d5d4 = (d5d4 & ~0x1c) | moved bits | 0xc0.
wire [7:0] so_d7d6 = logical_d7d6 | 8'h60;
wire [7:0] so_d5d4 = (logical_d5d4 & 8'hE3)
                   | {2'b11, 1'b0, ~so_fc_raw[3], ~so_fc_raw[4], ~so_fc_raw[5], 2'b00};

wire [7:0] eff_d7d6 = (so_en & so_upright) ? so_d7d6 : logical_d7d6;
wire [7:0] eff_d5d4 = (so_en & so_upright) ? so_d5d4 : logical_d5d4;

wire [1:0] mux_shift = port_addr[1:0];
wire [7:0] mangled_dout = demangle(
    eff_d7d6 >> mux_shift,
    eff_d5d4 >> mux_shift,
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
        (rom_sel):                    cpu_din = rom_dout_eff;
        (ram_sel  & mem_read):        cpu_din = mainram_dout;
        (vram_sel & mem_read):        cpu_din = vidram_dout;
        (usb_sel  & mem_read):        cpu_din = usb_pgm_dout_i;
        (io_read  & io_vid):          cpu_din = video_port_r;
        (io_read  & io_f8_fb):        cpu_din = mangled_dout;
        (io_read  & io_fc):           cpu_din = so_en ? so_fc_dout : fc_dout;
        (io_read  & io_3f & usb_en):  cpu_din = usb_status_i;
        (io_read  & io_08_0f & so_en):cpu_din = so_port_dout_i;
        // $0E returns upd7751_status_r = busy << 4; other PPI regs read 0.
        (io_read  & io_0c_0f & mb_en):cpu_din = (port_addr == 8'h0E)
                                              ? {3'b000, mb_snd_busy_i, 4'b0000}
                                              : 8'h00;
        (io_read  & io_80_83 & sm_en):cpu_din = sm_ppi_dout;
        default:                      cpu_din = 8'hFF;
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

// Astro Blaster audio bus — $3F doubles as the USB data port on Pig Newton.
assign audio_we_o   = io_write & io_3e_3f & ~usb_en;
assign audio_addr_o = port_addr[0];
assign audio_din_o  = cpu_dout;
assign ce_cpu_o     = ce_cpu;

// Universal Sound Board bus (MAME segag80r.cpp:2003-2006, init_pignewt).
// usb_ram_w applies decrypt_offset, so the shared-RAM window reuses the same
// scrambled address the VRAM write path uses.
assign usb_data_wr_o  = io_write & io_3f & usb_en & ce_cpu;
assign usb_din_o      = cpu_dout;
assign usb_pgm_addr_o = (usb_sel & mem_write) ? decrypt_addr[11:0]
                                              : cpu_addr[11:0];
assign usb_pgm_din_o  = cpu_dout;
assign usb_pgm_wr_o   = usb_sel & mem_write & ce_cpu;

// Space Odyssey background board bus (MAME segag80r.cpp:1926-1929).
assign so_port_wr_o   = io_write & io_08_0f & so_en & ce_cpu;
assign so_port_addr_o = port_addr[2:0];
assign so_port_din_o  = cpu_dout;

// Speech board strobes (MAME segag80r.cpp:1890-1891)
assign speech_data_we_o = io_write & io_38 & ce_cpu;
assign speech_ctrl_we_o = io_write & io_3b & ce_cpu;

endmodule
