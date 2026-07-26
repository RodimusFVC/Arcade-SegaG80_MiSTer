//============================================================================
// Sega speech board — i8035 + SP0250 + glue.
//
// Authoritative reference: MAME segaspeech.cpp (Aaron Giles, BSD-3-Clause).
// T48 core: Arnim Laeuger's MCS-48 implementation (t48_core.vhd).
//
// Host interface:
//   data_w + data_we  : 8-bit speech command latch (MAME data_w)
//                       bit 7=0 asserts /INT to 8035
//                       bit 7 rising edge (0->1) sets T0=1
//   ctrl_w + ctrl_we  : CD4053 audio gate (MAME control_w)
//                       bit 3 = enable speech output (0 mutes)
//
// 8035 ↔ board signals:
//   P1[6:0] read  : latch[6:0]                    (MAME p1_r)
//   P1[7]   read  : floats high                    (open-drain pull-up)
//   P1[7]   write : 0 = ack/clear T0               (MAME p1_w)
//   P2[5:0] write : speech-ROM page select
//   T0 in         : "fresh command waiting" flag
//   T1 in         : SP0250 DRQ
//   /INT in       : asserted when latch bit 7 is 0
//   External bus  : MCS-48 ALE/RD/WR multiplexed; address phase latched
//                   on falling edge of ALE, then read or write phase.
//                   Reads return speech_rom[P2[5:0]*256 + bus_addr]
//                   Writes go to SP0250 data port.
//
// Audio: SP0250 -> 14-bit signed PCM -> 16-bit, gated by speech_gate.
//============================================================================

module segaspeech (
    input                clk,                 // clk_sys = 15.468480 MHz (rtl/pll/pll_0002.v).
                                              // NOT 20 MHz — that stale comment produced the
                                              // wrong CE divisors; see SPEED-FIX-2026-07-26.
    input                reset_n,
    input        [7:0]   data_w,
    input                data_we,
    input        [7:0]   ctrl_w,
    input                ctrl_we,

    // 8035 program ROM (2KB at 0x000-0x7FF, mirrored to 0xFFF)
    output       [10:0]  rom_8035_addr,
    input        [7:0]   rom_8035_data,

    // Speech data ROM (16KB)
    output       [13:0]  rom_speech_addr,
    input        [7:0]   rom_speech_data,

    output signed [15:0] audio_out,
    output               audio_valid,

    // DIAG-REVERT-2026-05-28: command-path activity for parent LED routing.
    // dbg_cmd_sent = host set T0 (a speech command arrived); dbg_cmd_ack = the
    // 8035 acked/serviced a command (P1[7] pulse). Both stretched ~0.2s. Revert:
    // delete these two ports + the stretch block below; in the parent restore
    // LED_USER = ioctl_download and LED_POWER = 0.
    output               dbg_cmd_sent,
    output               dbg_cmd_ack
);

    //------------------------------------------------------------------------
    // Clock-enable generation
    //
    // Sega speech board XTAL = 3.12 MHz; T48 internally divides XTAL by 3
    // to get its clock-state rate. From 20 MHz, /8 gives 2.5 MHz (about 80%
    // of nominal) which is within the tolerance band for both 8035 and
    // SP0250; speech will be slightly low-pitched but intelligible.
    //
    // ce_3_12m is the oscillator-rate clock-enable. It is fed to t48_core's
    // xtal_en_i (the XTAL clock-enable port) — see the t48_core integration
    // note below for the full clock/reset contract.
    //
    // For exact pitch, replace with a fractional clock-enable generator
    // (accumulator-based) producing 3.12 MHz and 1.56 MHz pulses.
    //------------------------------------------------------------------------
    // SPEED-FIX-2026-07-26 — speech played at 62% speed (HW-confirmed slow 2026-07-26).
    // The old /8 and /16 were computed against a "20 MHz system clock" (see the port
    // comment above, which was WRONG). clk_sys is actually the PLL's
    // **15.468480 MHz** (rtl/pll/pll_0002.v output_clock_frequency0), so:
    //     /8  = 1.9336 MHz vs 3.12 MHz nominal = 62%
    //     /16 = 0.9668 MHz vs 1.56 MHz nominal = 62%
    // Correct divisors from 15.468480 MHz are /5 and /10:
    //     /5  = 3.093696 MHz vs 3.12 MHz  = 99.16%
    //     /10 = 1.546848 MHz vs 1.56 MHz  = 99.16%   (0.84% flat, inaudible)
    // Both the 8035 and the SP0250 run off the same 3.12 MHz XTAL on the real board
    // (MAME segaspeech.cpp:30 SPEECH_MASTER_CLOCK 3120000, used for I8035 AND SP0250),
    // and ROMCLOCK is XTAL/2 — the 2:1 ratio is preserved exactly here.
    // ORIGINAL:
    // reg [3:0] ce_div;
    // always @(posedge clk or negedge reset_n) begin
    //     if (!reset_n) ce_div <= 4'd0;
    //     else          ce_div <= ce_div + 4'd1;
    // end
    // wire ce_3_12m     = (ce_div[2:0] == 3'd0);   // /8  ≈ 2.5 MHz
    // wire ce_rom_1_56m = (ce_div      == 4'd0);   // /16 ≈ 1.25 MHz
    reg [3:0] ce_div;                                // mod-10
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) ce_div <= 4'd0;
        else          ce_div <= (ce_div == 4'd9) ? 4'd0 : ce_div + 4'd1;
    end
    wire ce_3_12m     = (ce_div == 4'd0) || (ce_div == 4'd5);  // /5  = 3.0937 MHz
    wire ce_rom_1_56m = (ce_div == 4'd0);                      // /10 = 1.5468 MHz

    //------------------------------------------------------------------------
    // Host-side latch with T0/INT decode (MAME delayed_speech_w)
    //------------------------------------------------------------------------
    reg [7:0] latch;
    reg       t0;
    reg       speech_gate;

    // P1 from T48 — continuously driven; we monitor bit 7 for the ack.
    wire [7:0] p1_o;

    // p1_o[7] going low is the "I consumed the command" handshake. Detect
    // its falling edge so we only clear T0 once per ack (not every cycle
    // it stays low).
    reg p1_7_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) p1_7_prev <= 1'b1;
        else          p1_7_prev <= p1_o[7];
    end
    wire p1_7_falling = p1_7_prev & ~p1_o[7];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            latch       <= 8'h00;
            t0          <= 1'b0;
            speech_gate <= 1'b0;
        end else begin
            if (data_we) begin
                // Rising edge of bit 7 of the host write sets T0
                if (!latch[7] && data_w[7])
                    t0 <= 1'b1;
                latch <= data_w;
            end
            // 8035 acked by pulling P1[7] low
            if (p1_7_falling)
                t0 <= 1'b0;
            // Host wrote control byte
            if (ctrl_we)
                speech_gate <= ctrl_w[3];
        end
    end

    // /INT is active-low; asserted when latch[7] is 0
    wire int_n = latch[7];

    //------------------------------------------------------------------------
    // T48 (8035) bus capture — MCS-48 external bus is multiplexed:
    //   ALE high  : 8035 puts address byte on db_o
    //   ALE falls : we latch the address
    //   RD_n low  : 8035 reads -> we drive db_i with rom_speech_data
    //   WR_n low  : 8035 writes -> sample db_o into SP0250
    //
    // T48's `db_dir_o` indicates direction (0 = T48 drives db_o, 1 = inputs).
    //------------------------------------------------------------------------
    wire        ale_o;
    wire        rd_n_o;
    wire        wr_n_o;
    wire [7:0]  db_o;
    wire        db_dir_o;
    wire [7:0]  p2_o;

    // Latch the bus address on the falling edge of ALE
    reg [7:0] bus_addr_latch;
    reg       ale_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bus_addr_latch <= 8'h00;
            ale_prev       <= 1'b0;
        end else begin
            ale_prev <= ale_o;
            if (ale_prev && !ale_o)        // ALE falling edge
                bus_addr_latch <= db_o;
        end
    end

    // Compose speech-ROM address from P2[5:0] (page) + bus address (offset)
    assign rom_speech_addr = {p2_o[5:0], bus_addr_latch};

    // 8035 read returns speech ROM byte; T48 latches via db_i during RD_n low
    wire [7:0] db_i = rom_speech_data;

    //------------------------------------------------------------------------
    // SP0250 instance + write-strobe generation
    //
    // The 8035 writes a byte to SP0250 by doing MOVX @Rn,A which produces
    // a WR_n pulse with the data on db_o. We sample on the rising edge of
    // WR_n (end of write cycle, when data is guaranteed valid). Use a
    // 1-cycle strobe synchronized to clk.
    //------------------------------------------------------------------------
    reg wr_n_prev;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) wr_n_prev <= 1'b1;
        else          wr_n_prev <= wr_n_o;
    end
    // FIX-2026-07-26 — CO-SIM PROVEN. Was the FALLING edge, which samples the ADDRESS
    // phase: MOVX @Rn,A drives R0 (the frame-buffer pointer, 0x23-0x31) onto the bus
    // first, then A (the data). The old strobe captured R0 every time, so the SP0250 was
    // fed a stream of RAM POINTERS instead of LPC frames -- the "modem noise" symptom.
    // Note the comment block above always SAID rising edge; only the code disagreed.
    //
    // Proof (verilator/speech_full, real segaspeech + GHDL-converted i8039 + real ROMs,
    // both edges captured in ONE run, diffed against MAME's known-good mame_stream.bin):
    //   WR_n falling: 23 22 22 29 28 28 27 26 26 25 24 24 24 21 20   <- RAM addresses
    //   WR_n rising : 00 00 00 00 00 FF 00 00 01 00 00 00 00 00 00   <- 15/15 MATCH
    //   MAME        : 00 00 00 00 00 FF 00 00 01 00 00 00 00 00 00
    // ORIGINAL:
    // wire sp_wr = wr_n_prev & ~wr_n_o;     // WR_n falling edge = strobe
    wire sp_wr = ~wr_n_prev & wr_n_o;     // WR_n RISING edge = data phase valid

    wire               sp_drq;
    wire signed [13:0] sp_audio;
    wire               sp_audio_valid;

    sp0250 u_sp0250 (
        .clk          (clk),
        .reset_n      (reset_n),
        .ce_3_12m     (ce_3_12m),
        .ce_rom_1_56m (ce_rom_1_56m),
        .data_in      (db_o),
        .wr           (sp_wr),
        .drq          (sp_drq),
        .audio_out    (sp_audio),
        .audio_valid  (sp_audio_valid)
    );

    //------------------------------------------------------------------------
    // T48 8035 core
    //
    // 8035 has NO internal program ROM, so ea_i = 0 (external access).
    // T48's pmem_addr_o is 12 bits; we use the low 11 (2KB ROM).
    //
    // CLOCK/RESET CONTRACT (FIX-2026-05-20).
    // t48_core has TWO clock domains plus a strict wiring contract. Verified
    // against the core's own clock_ctrl.vhd, the constant table t48_pack-p.vhd,
    // and Arnim Laeuger's reference 8039 toplevel t8039_notri.vhd:
    //   * clk_i and xtal_i are the SAME clock net.
    //   * xtal_en_i is the oscillator-rate clock-enable (the ~3.12 MHz tick) —
    //     it gates the XTAL/3 divider.
    //   * en_clk_i MUST be driven from the core's own xtal3_o output (XTAL/3).
    //     The 5-state machine FSM advances once per xtal3 tick; feeding any
    //     other enable desyncs the FSM from the ALE/RD/WR generator. xtal3_o
    //     is looped straight back into en_clk_i via t48_xtal3.
    //   * reset_i is ACTIVE-LOW (res_active_c = '0' in t48_pack-p.vhd) — drive
    //     it with reset_n directly, NOT ~reset_n.
    //
    // The original wiring put ce_3_12m on en_clk_i, left xtal3_o open, and fed
    // ~reset_n to reset_i. The inverted reset held the 8035 in reset for the
    // entire game — PC frozen, zero speech (proven 2026-05-20 by the PC-audio-
    // hijack diagnostic: the speech DAC, driven from t48_pmem_addr, was a dead
    // flatline). See Projects/Arcade-SegaG80_MiSTer/Claude/speech_t48_clock_reset_fix_2026-05-20.md.
    //------------------------------------------------------------------------
    wire [11:0] t48_pmem_addr;
    assign rom_8035_addr = t48_pmem_addr[10:0];

    //========================================================================
    // MIGRATE-2026-05-28: hand-rolled t48_core  ->  t8039_notri_extrom wrapper
    //
    // Applying the Juno First playbook (Projects/Arcade-JunoFirst_MiSTer/Claude/
    // jf_audio_RESUME_HANDOFF_2026-05-25.md): JF stopped hand-instantiating
    // t48_core and moved to Arnim Laeuger's author-blessed 8039 toplevel. The
    // wrapper bakes in the clock/reset/xtal3-loopback contract AND — the part
    // that matters here — the open-drain port-input gating (p_in <= p_ext AND
    // p_out). FIX-2026-05-20 had already hand-corrected the clock/reset contract,
    // but the hand-roll still fed p1_i/p2_i to the core *ungated*. P2[5:0] is the
    // speech-ROM page latch; any firmware read-back of P2 read 0xFF instead of
    // the page actually written -> mis-addressed speech ROM -> near-constant
    // bytes to the SP0250 (the open "garbled static, no words" symptom).
    //
    // ea_i=0 / pmem_data_i program fetch (the path that currently works) is
    // unchanged; the *_extrom variant keeps that direct fetch port. ram_addr_
    // width_g=6 => 64B internal RAM (8035). See:
    //   Common-Pitfalls/T48 external program ROM needs multiplexed bus.md
    //   rtl/sound/i8039/t8039_notri_extrom.vhd
    //
    // Original hand-rolled instance + external dmem RAM preserved commented-out
    // below (no git on this core -> comment-don't-delete). To revert: delete the
    // wrapper instance, uncomment the block, drop the i8039 files from files.qip.
    //========================================================================

    t8039_notri_extrom #(
        // MIGRATE-2026-05-28: gate_port_input_g 1 -> 0. MAME p1_r() returns the
        // command latch DIRECTLY (no AND with the 8035's P1 output), and P2 is
        // output-only on this board, so the open-drain input gating is wrong here
        // (and was a no-op-at-best change on my part). 0 = ungated -> matches the
        // proven pre-migration hand-roll and MAME.
        .gate_port_input_g (0),
        .ram_addr_width_g  (6)                // 8035 = 64 bytes internal RAM
    ) u_8035 (
        .xtal_i        (clk),
        .xtal_en_i     (ce_3_12m),            // oscillator-rate clock-enable
        .reset_n_i     (reset_n),             // wrapper port is active-LOW
        .t0_i          (t0),
        .t0_o          (),
        .t0_dir_o      (),
        .int_n_i       (int_n),
        .ea_i          (1'b0),                // program fetched via pmem_data_i
        .rd_n_o        (rd_n_o),
        .psen_n_o      (),
        .wr_n_o        (wr_n_o),
        .ale_o         (ale_o),
        .db_i          (db_i),
        .db_o          (db_o),
        .db_dir_o      (db_dir_o),
        .t1_i          (sp_drq),              // SP0250 DRQ -> T1
        .p2_i          (8'hFF),
        .p2_o          (p2_o),
        .p2l_low_imp_o (),
        .p2h_low_imp_o (),
        .p1_i          ({1'b1, latch[6:0]}),  // P1[7]=high, P1[6:0]=cmd
        .p1_o          (p1_o),
        .p1_low_imp_o  (),
        .prog_n_o      (),
        .pmem_addr_o   (t48_pmem_addr),
        .pmem_data_i   (rom_8035_data)
    );

    // ---- MIGRATE-2026-05-28: original hand-rolled t48_core, commented out -----
    // // FIX-2026-05-20: t48_core xtal3_o looped back into en_clk_i (the contract).
    // wire t48_xtal3;
    //
    // // Internal data RAM (64 bytes, 6-bit address). Use BRAM-friendly pattern.
    // wire [7:0]  dmem_addr_o;
    // wire        dmem_we_o;
    // wire [7:0]  dmem_data_o;
    // wire [7:0]  dmem_data_i;
    // reg  [7:0]  dmem_ram [0:63];
    // reg  [7:0]  dmem_q;
    // always @(posedge clk) begin
    //     if (dmem_we_o) dmem_ram[dmem_addr_o[5:0]] <= dmem_data_o;
    //     dmem_q <= dmem_ram[dmem_addr_o[5:0]];
    // end
    // assign dmem_data_i = dmem_q;
    //
    // t48_core #(
    //     .xtal_div_3_g        (1),
    //     .register_mnemonic_g (0),     // skip instruction debug tracking
    //     .include_port1_g     (1),
    //     .include_port2_g     (1),
    //     .include_bus_g       (1),
    //     .include_timer_g     (0),     // speech firmware doesn't use the timer
    //     .sample_t1_state_g   (4)
    // ) u_8035 (
    //     // T48 interface
    //     .xtal_i        (clk),
    //     // FIX-2026-05-20: was .xtal_en_i(1'b1). ce_3_12m is the oscillator-rate
    //     // clock-enable and belongs on xtal_en_i (gates the XTAL/3 divider).
    //     .xtal_en_i     (ce_3_12m),
    //     // FIX-2026-05-20: was .reset_i(~reset_n). reset_i is ACTIVE-LOW
    //     // (res_active_c='0'); ~reset_n held the 8035 in reset all game long.
    //     .reset_i       (reset_n),
    //     .t0_i          (t0),
    //     .t0_o          (),
    //     .t0_dir_o      (),
    //     .int_n_i       (int_n),
    //     .ea_i          (1'b0),                    // 8035 = external ROM only
    //     .rd_n_o        (rd_n_o),
    //     .psen_n_o      (),
    //     .wr_n_o        (wr_n_o),
    //     .ale_o         (ale_o),
    //     .db_i          (db_i),
    //     .db_o          (db_o),
    //     .db_dir_o      (db_dir_o),
    //     .t1_i          (sp_drq),                  // SP0250 DRQ -> T1
    //     .p2_i          (8'hFF),
    //     .p2_o          (p2_o),
    //     .p2l_low_imp_o (),
    //     .p2h_low_imp_o (),
    //     .p1_i          ({1'b1, latch[6:0]}),      // P1[7]=high, P1[6:0]=cmd
    //     .p1_o          (p1_o),
    //     .p1_low_imp_o  (),
    //     .prog_n_o      (),
    //     // Core interface
    //     .clk_i         (clk),
    //     // FIX-2026-05-20: was .en_clk_i(ce_3_12m). en_clk_i must be the core's
    //     // own xtal3_o output, looped back via t48_xtal3.
    //     .en_clk_i      (t48_xtal3),
    //     // FIX-2026-05-20: was .xtal3_o() unconnected. Must drive en_clk_i.
    //     .xtal3_o       (t48_xtal3),
    //     .dmem_addr_o   (dmem_addr_o),
    //     .dmem_we_o     (dmem_we_o),
    //     .dmem_data_i   (dmem_data_i),
    //     .dmem_data_o   (dmem_data_o),
    //     .pmem_addr_o   (t48_pmem_addr),
    //     .pmem_data_i   (rom_8035_data)
    // );
    // ---- end MIGRATE-2026-05-28 commented original ----------------------------

    //------------------------------------------------------------------------
    // Audio output: 14-bit signed -> 16-bit signed, gated by control[3]
    //------------------------------------------------------------------------
    wire signed [15:0] sp_audio_16 = {sp_audio[13], sp_audio, 1'b0};

    // DIAG-REVERT-2026-05-28: speech-ROM read tap removed; real SP0250 -> DAC
    // path restored (full speech audio, gated by control[3]). The diagnostic
    // write-up survives in Projects/Arcade-SegaG80_MiSTer/Claude/
    // speech_writestream_tap_2026-05-20.md if it ever needs re-running.
    assign audio_out   = speech_gate ? sp_audio_16 : 16'sd0;
    assign audio_valid = sp_audio_valid;

    //========================================================================
    // DIAG-REVERT-2026-05-28: command-path activity LEDs   >>> DIAGNOSTIC >>>
    // Splits the "no event tracking / modem noise" symptom three ways on a
    // coin-up or known speech trigger:
    //   neither LED  -> command never SENT (host/port decode)
    //   sent on, ack off -> 8035 not SERVICING the command (stuck / steering bug)
    //   both on      -> command serviced -> bug is downstream (ROM pointer/decode)
    // dbg_cmd_sent = host set T0 (rising edge of data_w[7] on a data write — the
    //                exact condition that sets t0 below).
    // dbg_cmd_ack  = 8035 pulled P1[7] low (the command-path ack). Stretched ~0.2s.
    //========================================================================
    localparam [23:0] DBG_STRETCH = 24'd3_000_000;   // ~0.19 s at 15.468 MHz
    wire cmd_sent_evt = data_we & ~latch[7] & data_w[7];
    reg [23:0] dbg_sent_cnt, dbg_ack_cnt;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            dbg_sent_cnt <= 24'd0;
            dbg_ack_cnt  <= 24'd0;
        end else begin
            if (cmd_sent_evt)            dbg_sent_cnt <= DBG_STRETCH;
            else if (dbg_sent_cnt != 0)  dbg_sent_cnt <= dbg_sent_cnt - 24'd1;
            if (p1_7_falling)            dbg_ack_cnt  <= DBG_STRETCH;
            else if (dbg_ack_cnt != 0)   dbg_ack_cnt  <= dbg_ack_cnt - 24'd1;
        end
    end
    assign dbg_cmd_sent = (dbg_sent_cnt != 24'd0);
    assign dbg_cmd_ack  = (dbg_ack_cnt  != 24'd0);
    // DIAG-REVERT-2026-05-28: command-path activity LEDs   <<< END DIAGNOSTIC <<<

    // Lint: keep unused signals visible
    wire _unused = |{db_dir_o};

endmodule
