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
    input                clk,                 // 20 MHz system clock
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
    output               audio_valid
);

    //------------------------------------------------------------------------
    // Clock-enable generation
    //
    // Sega speech board XTAL = 3.12 MHz; T48 internally divides XTAL by 3
    // to get its clock-state rate. From 20 MHz, /8 gives 2.5 MHz (about 80%
    // of nominal) which is within the tolerance band for both 8035 and
    // SP0250; speech will be slightly low-pitched but intelligible.
    //
    // For exact pitch, replace with a fractional clock-enable generator
    // (accumulator-based) producing 3.12 MHz and 1.56 MHz pulses.
    //------------------------------------------------------------------------
    reg [3:0] ce_div;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) ce_div <= 4'd0;
        else          ce_div <= ce_div + 4'd1;
    end
    wire ce_3_12m     = (ce_div[2:0] == 3'd0);   // /8  ≈ 2.5 MHz
    wire ce_rom_1_56m = (ce_div      == 4'd0);   // /16 ≈ 1.25 MHz

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
    wire sp_wr = wr_n_prev & ~wr_n_o;     // WR_n falling edge = strobe

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
    //------------------------------------------------------------------------
    wire [11:0] t48_pmem_addr;
    assign rom_8035_addr = t48_pmem_addr[10:0];

    // Internal data RAM (64 bytes, 6-bit address). Use BRAM-friendly pattern.
    wire [7:0]  dmem_addr_o;
    wire        dmem_we_o;
    wire [7:0]  dmem_data_o;
    wire [7:0]  dmem_data_i;
    reg  [7:0]  dmem_ram [0:63];
    reg  [7:0]  dmem_q;
    always @(posedge clk) begin
        if (dmem_we_o) dmem_ram[dmem_addr_o[5:0]] <= dmem_data_o;
        dmem_q <= dmem_ram[dmem_addr_o[5:0]];
    end
    assign dmem_data_i = dmem_q;

    t48_core #(
        .xtal_div_3_g        (1),
        .register_mnemonic_g (0),     // skip instruction debug tracking
        .include_port1_g     (1),
        .include_port2_g     (1),
        .include_bus_g       (1),
        .include_timer_g     (0),     // speech firmware doesn't use the timer
        .sample_t1_state_g   (4)
    ) u_8035 (
        // T48 interface
        .xtal_i        (clk),
        .xtal_en_i     (1'b1),
        .reset_i       (~reset_n),
        .t0_i          (t0),
        .t0_o          (),
        .t0_dir_o      (),
        .int_n_i       (int_n),
        .ea_i          (1'b0),                    // 8035 = external ROM only
        .rd_n_o        (rd_n_o),
        .psen_n_o      (),
        .wr_n_o        (wr_n_o),
        .ale_o         (ale_o),
        .db_i          (db_i),
        .db_o          (db_o),
        .db_dir_o      (db_dir_o),
        .t1_i          (sp_drq),                  // SP0250 DRQ -> T1
        .p2_i          (8'hFF),
        .p2_o          (p2_o),
        .p2l_low_imp_o (),
        .p2h_low_imp_o (),
        .p1_i          ({1'b1, latch[6:0]}),      // P1[7]=high, P1[6:0]=cmd
        .p1_o          (p1_o),
        .p1_low_imp_o  (),
        .prog_n_o      (),
        // Core interface
        .clk_i         (clk),
        .en_clk_i      (ce_3_12m),
        .xtal3_o       (),
        .dmem_addr_o   (dmem_addr_o),
        .dmem_we_o     (dmem_we_o),
        .dmem_data_i   (dmem_data_i),
        .dmem_data_o   (dmem_data_o),
        .pmem_addr_o   (t48_pmem_addr),
        .pmem_data_i   (rom_8035_data)
    );

    //------------------------------------------------------------------------
    // Audio output: 14-bit signed -> 16-bit signed, gated by control[3]
    //------------------------------------------------------------------------
    wire signed [15:0] sp_audio_16 = {sp_audio[13], sp_audio, 1'b0};

    assign audio_out   = speech_gate ? sp_audio_16 : 16'sd0;
    assign audio_valid = sp_audio_valid;

    // Lint: keep unused signals visible
    wire _unused = |{db_dir_o};

endmodule
