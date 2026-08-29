//============================================================================
//  Sindbad Mystery — Sega System 1 sound board
//
//  Z80 @ 8 MHz/2 driving two SN76496 (JT89), talking to the main CPU through
//  the i8255 PPI at $80-$83.  MAME: segag80r.cpp sindbadm_sound_map (614) and
//  sindbadm() (1195-1203).
//
//  Sound-CPU memory map (mirrors make the top three address bits sufficient):
//      $0000-$1FFF  program ROM      8 KB, ioctl index 6 (epr-5400.4a)
//      $8000-$87FF  work RAM         2 KB, mirror $1800
//      $A000-$A003  SN76496 #0 write        mirror $1FFC
//      $C000-$C003  SN76496 #1 write        mirror $1FFC
//      $E000        command latch read      mirror $1FFF (i8255 acka_r)
//
//  The SN data lines are wired backwards on this board — MAME sindbadm_sn_w
//  does bitswap<8>(data,0,1,2,3,4,5,6,7), a full bit reversal.
//
//  Two interrupts:
//    INT  240 Hz periodic (4*60), irq0_line_hold — held until the INTA cycle.
//    NMI  the port-A handshake.  Port A is an i8255 mode-1 output, so port C
//         bit 7 is /OBF: the main CPU's write to $80 pulls it low, the sound
//         CPU's read at $E000 (acka_r) releases it.  A direct port-C write
//         with bit 7 low also asserts it, covering a mode-0 configuration.
//         tri_pc_callback is 0x80, i.e. undriven = released, hence the reset
//         state.
//
//  SN #0 runs at 4 MHz and #1 at 2 MHz.  MAME's own comment on both lines is
//  "matches PCB videos, correct?", so treat the ratio as the confident part.
//  /READY is not modelled; MAME does not wait-state on it either.
//============================================================================

module sindbadm_sound #(
    parameter int unsigned CLK_HZ    = 15_468_480,  // clk_sys
    parameter int unsigned Z80_HZ    =  4_000_000,  // 8 MHz XTAL / 2
    parameter int unsigned SN0_HZ    =  4_000_000,  // 8 MHz XTAL / 2
    parameter int unsigned SN1_HZ    =  2_000_000,  // 8 MHz XTAL / 4
    parameter int          GAIN_LOG2 =  4           // 2 x 11-bit -> full scale
)(
    input                       clk,
    input                       reset,

    // Main-CPU side — i8255 PPI at $80-$83
    input                       latch_wr,   // write strobe, port A ($80)
    input                [7:0]  latch_din,
    input                       pc_wr,      // write strobe, port C ($82)
    input                [7:0]  pc_din,

    // Program ROM load — ioctl index 6
    input               [12:0]  ioctl_addr,
    input                [7:0]  ioctl_data,
    input                       ioctl_wr,

    output signed       [15:0]  audio
);

    //------------------------------------------------------------------------
    // Clock enables.  Fractional accumulators: clk_sys is not an integer
    // multiple of any of these rates.
    //------------------------------------------------------------------------
    localparam [32:0] INC_Z80 = 33'((longint'(Z80_HZ) <<< 32) / longint'(CLK_HZ));
    localparam [32:0] INC_SN0 = 33'((longint'(SN0_HZ) <<< 32) / longint'(CLK_HZ));
    localparam [32:0] INC_SN1 = 33'((longint'(SN1_HZ) <<< 32) / longint'(CLK_HZ));

    reg [32:0] acc_z80, acc_sn0, acc_sn1;
    always @(posedge clk) begin
        acc_z80 <= {1'b0, acc_z80[31:0]} + INC_Z80;
        acc_sn0 <= {1'b0, acc_sn0[31:0]} + INC_SN0;
        acc_sn1 <= {1'b0, acc_sn1[31:0]} + INC_SN1;
    end
    wire ce_z80 = acc_z80[32];
    wire ce_sn0 = acc_sn0[32];
    wire ce_sn1 = acc_sn1[32];

    //------------------------------------------------------------------------
    // Command latch and NMI handshake
    //------------------------------------------------------------------------
    reg [7:0] snd_latch;
    always @(posedge clk) if (latch_wr) snd_latch <= latch_din;

    wire latch_rd;                       // sound CPU read of $E000
    reg  nmi_req;
    always @(posedge clk or posedge reset) begin
        if (reset)                     nmi_req <= 1'b0;
        else if (latch_wr)             nmi_req <= 1'b1;
        else if (pc_wr)                nmi_req <= ~pc_din[7];
        else if (latch_rd & ce_z80)    nmi_req <= 1'b0;
    end

    //------------------------------------------------------------------------
    // Periodic INT — 4 * 60 Hz, held until the interrupt acknowledge cycle
    //------------------------------------------------------------------------
    localparam int unsigned IRQ_DIV = CLK_HZ / 240;

    reg [$clog2(IRQ_DIV)-1:0] irq_cnt;
    reg                       irq_pend;
    wire                      intack;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            irq_cnt  <= '0;
            irq_pend <= 1'b0;
        end else begin
            if (irq_cnt == IRQ_DIV[$clog2(IRQ_DIV)-1:0] - 1'b1) begin
                irq_cnt  <= '0;
                irq_pend <= 1'b1;
            end else begin
                irq_cnt <= irq_cnt + 1'b1;
                if (intack) irq_pend <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------
    // Z80
    //------------------------------------------------------------------------
    wire        mreq_n, iorq_n, rd_n, wr_n, m1_n;
    wire [15:0] addr;
    wire  [7:0] dout;
    reg   [7:0] din;

    assign intack = ~m1_n & ~iorq_n;

    T80s sound_cpu (
        .RESET_n (~reset),
        .CLK     (clk),
        .CEN     (ce_z80),
        .WAIT_n  (1'b1),
        .INT_n   (~irq_pend),
        .NMI_n   (~nmi_req),
        .BUSRQ_n (1'b1),
        .M1_n    (m1_n),
        .MREQ_n  (mreq_n),
        .IORQ_n  (iorq_n),
        .RD_n    (rd_n),
        .WR_n    (wr_n),
        .RFSH_n  (),
        .HALT_n  (),
        .BUSAK_n (),
        .A       (addr),
        .DI      (din),
        .DO      (dout)
    );

    wire mem     = ~mreq_n;
    wire mem_rd  = mem & ~rd_n;
    wire mem_wr  = mem & ~wr_n;

    wire rom_sel = mem & (addr[15:13] == 3'b000);   // $0000-$1FFF
    wire ram_sel = mem & (addr[15:13] == 3'b100);   // $8000-$9FFF (mirrored)
    wire sn0_sel = mem & (addr[15:13] == 3'b101);   // $A000-$BFFF (mirrored)
    wire sn1_sel = mem & (addr[15:13] == 3'b110);   // $C000-$DFFF (mirrored)
    wire lat_sel = mem & (addr[15:13] == 3'b111);   // $E000-$FFFF (mirrored)

    assign latch_rd = lat_sel & mem_rd;

    //------------------------------------------------------------------------
    // Program ROM (8 KB) and work RAM (2 KB)
    //------------------------------------------------------------------------
    reg [7:0] rom [0:8191];
    reg [7:0] rom_q;
    always @(posedge clk) begin
        if (ioctl_wr) rom[ioctl_addr] <= ioctl_data;
        rom_q <= rom[addr[12:0]];
    end

    reg [7:0] ram [0:2047];
    reg [7:0] ram_q;
    always @(posedge clk) begin
        if (ram_sel & mem_wr & ce_z80) ram[addr[10:0]] <= dout;
        ram_q <= ram[addr[10:0]];
    end

    always @(*) begin
        case (1'b1)
            rom_sel: din = rom_q;
            ram_sel: din = ram_q;
            lat_sel: din = snd_latch;
            default: din = 8'hFF;   // INTA reads 0xFF -> RST 38h, matches IM 1
        endcase
    end

    //------------------------------------------------------------------------
    // The two SN76496 — data bus reversed on the way in
    //------------------------------------------------------------------------
    wire [7:0] sn_din = {dout[0], dout[1], dout[2], dout[3],
                         dout[4], dout[5], dout[6], dout[7]};

    reg  [7:0] sn0_data, sn1_data;
    reg        sn0_wr, sn1_wr;
    always @(posedge clk) begin
        sn0_wr <= sn0_sel & mem_wr & ce_z80;
        sn1_wr <= sn1_sel & mem_wr & ce_z80;
        if (sn0_sel & mem_wr & ce_z80) sn0_data <= sn_din;
        if (sn1_sel & mem_wr & ce_z80) sn1_data <= sn_din;
    end

    wire signed [10:0] sn0_snd, sn1_snd;

    jt89 u_sn0 (
        .rst    (reset),
        .clk    (clk),
        .clk_en (ce_sn0),
        .wr_n   (~sn0_wr),
        .cs_n   (1'b0),
        .din    (sn0_data),
        .sound  (sn0_snd),
        .ready  ()
    );

    jt89 u_sn1 (
        .rst    (reset),
        .clk    (clk),
        .clk_en (ce_sn1),
        .wr_n   (~sn1_wr),
        .cs_n   (1'b0),
        .din    (sn1_data),
        .sound  (sn1_snd),
        .ready  ()
    );

    // Both chips route to the speaker at 1.0 in MAME.
    wire signed [11:0] sn_sum = $signed({sn0_snd[10], sn0_snd})
                              + $signed({sn1_snd[10], sn1_snd});

    wire signed [15:0] sn_wide = {{4{sn_sum[11]}}, sn_sum};
    assign audio = sn_wide <<< GAIN_LOG2;

endmodule
