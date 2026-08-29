//============================================================================
//
//  Monster Bash sound board — uPD7751 voice / sample player
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_a.cpp (monsterb_sound_device, D7751 connections)
//  and machine/i8243.cpp for the expander protocol.
//
//  This is the VOICE half of drawing 834-xxxx only. The TMS3617 music chip and
//  the SHOT/DIVE discrete circuits are separate and not implemented here.
//
//  Signal path — nothing like the Astro Blaster speech board:
//    Z80 --($0E)--> command + /INT --> uPD7751 (MCS-48, 6 MHz)
//    7751 P2[3:0] + PROG --> i8243 expander --> 12-bit sample ROM address
//    7751 BUS <-- sample ROM byte
//    7751 P1 --> 8-bit R-2R ladder (50K/100K, R91-97/R98-106) --> speaker
//
//  So it is straight 8-bit PCM playback, not LPC synthesis. The 7751 is an
//  8048 variant, so t48_core (via the existing i8035 wrapper) runs it; its
//  1 KB program is fed on the external bus with EA=1.
//
//============================================================================

module monsterb_voice #(
    parameter int CLK_HZ = 15_468_480,
    parameter int GAIN_LOG2 = 0
) (
    input                clk,
    input                reset,

    // Z80 side — i8255 port C ($0E). MAME upd7751_command_w:
    //   d0-d2 = command to the 7751's S0-2, d3 = /INT (asserted when LOW)
    input         [7:0]  cmd_w,
    output               busy,          // -> $0E read bit 4 (upd7751_status_r)

    // ROM loading
    input        [24:0]  ioctl_addr,
    input         [7:0]  ioctl_data,
    input                ioctl_wr,
    input                sel_pgm,       // 7751 program, 1 KB
    input                sel_smp,       // 7751 samples, 8 KB

    output signed [15:0] audio
);

    //------------------------------------------------------------------------
    // 6 MHz clock enable (MAME: UPD7751(config, m_audiocpu, 6000000))
    //------------------------------------------------------------------------
    localparam int CPU_HZ = 6_000_000;
    reg [23:0] acc;
    reg        ce_cpu;
    always @(posedge clk) begin
        if (reset) begin acc <= 24'd0; ce_cpu <= 1'b0; end
        else if (acc + CPU_HZ >= CLK_HZ) begin
            acc <= acc + CPU_HZ - CLK_HZ; ce_cpu <= 1'b1;
        end else begin
            acc <= acc + CPU_HZ;          ce_cpu <= 1'b0;
        end
    end

    //------------------------------------------------------------------------
    // ROMs
    //------------------------------------------------------------------------
    (* ramstyle = "M10K" *) reg [7:0] pgm_rom [0:1023];    // 7751.bin
    (* ramstyle = "M10K" *) reg [7:0] smp_rom [0:8191];    // 1543snd + 1544snd

    reg [7:0] pgm_q, smp_q;

    wire        psen_n;
    wire [7:0]  cpu_do;
    wire [7:0]  cpu_p1, cpu_p2;
    wire        prog_pin;

    // i8243 expander outputs: P4/P5/P6 are sample-ROM address nibbles,
    // P7 is the ROM select (active low, MAME upd7751_rom_select_w).
    reg [3:0] exp_p4, exp_p5, exp_p6, exp_p7;

    // Only two sample ROMs exist here, so of P7 only bit 1 can add 0x1000.
    wire [12:0] smp_addr = {~exp_p7[1], exp_p6, exp_p5, exp_p4};

    // MCS-48 program address: low byte on the BUS, A8-A11 on P2[3:0], both
    // latched at the ALE falling edge — same pattern as sound/usb/sega_usb.sv.
    wire       ale;
    wire       rd_n;
    reg  [7:0] addr_lo;
    reg  [7:0] p2_lat;
    reg        ale_d;
    wire [11:0] cpu_pc = {p2_lat[3:0], addr_lo};

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            ale_d <= 1'b0; addr_lo <= 8'd0; p2_lat <= 8'd0;
        end else if (ce_cpu) begin
            ale_d <= ale;
            if (!ale && ale_d) begin
                addr_lo <= cpu_do;
                p2_lat  <= cpu_p2;
            end
        end
    end

    always @(posedge clk) begin
        if (ioctl_wr & sel_pgm) pgm_rom[ioctl_addr[9:0]]  <= ioctl_data;
        if (ioctl_wr & sel_smp) smp_rom[ioctl_addr[12:0]] <= ioctl_data;
        pgm_q <= pgm_rom[cpu_pc[9:0]];
        smp_q <= smp_rom[smp_addr];
    end

    // INS A,BUS (the sample read) asserts RD; program fetches assert PSEN.
    reg [7:0] cpu_di;
    always @(*) begin
        cpu_di = 8'hFF;
        if (!psen_n)    cpu_di = pgm_q;
        else if (!rd_n) cpu_di = smp_q;
    end

    //------------------------------------------------------------------------
    // i8243 expander — machine/i8243.cpp
    //   PROG high->low : latch opcode nibble  {instr[1:0], port[1:0]}
    //   PROG low->high : 0=read (bus release), 1=write, 2=OR, 3=AND
    //------------------------------------------------------------------------
    reg  [3:0] exp_op;
    reg        prog_d;
    always @(posedge clk) prog_d <= prog_pin;
    wire prog_fall = prog_d & ~prog_pin;
    wire prog_rise = ~prog_d & prog_pin;

    function [3:0] exp_apply;
        input [1:0] op;
        input [3:0] cur;
        input [3:0] dat;
        begin
            case (op)
                2'd1: exp_apply = dat;
                2'd2: exp_apply = cur | dat;
                2'd3: exp_apply = cur & dat;
                default: exp_apply = cur;      // read — outputs unchanged
            endcase
        end
    endfunction

    wire [1:0] exp_port = exp_op[1:0];
    wire [1:0] exp_instr = exp_op[3:2];
    wire [3:0] exp_data = cpu_p2[3:0];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            exp_op <= 4'd0;
            exp_p4 <= 4'd0; exp_p5 <= 4'd0; exp_p6 <= 4'd0; exp_p7 <= 4'hF;
        end else begin
            if (prog_fall) exp_op <= exp_data;
            else if (prog_rise) begin
                if (exp_port == 2'd0) exp_p4 <= exp_apply(exp_instr, exp_p4, exp_data);
                if (exp_port == 2'd1) exp_p5 <= exp_apply(exp_instr, exp_p5, exp_data);
                if (exp_port == 2'd2) exp_p6 <= exp_apply(exp_instr, exp_p6, exp_data);
                if (exp_port == 2'd3) exp_p7 <= exp_apply(exp_instr, exp_p7, exp_data);
            end
        end
    end

    //------------------------------------------------------------------------
    // MCU
    //   P2 in : 0x80 | (command << 4)   (upd7751_command_r)
    //   P2 out: low nibble to the 8243, bit 7 is the status flag
    //   /INT  : asserted while $0E d3 is LOW
    //------------------------------------------------------------------------
    wire [7:0] p2_in = {1'b1, cmd_w[2:0], 4'b0000};

    assign busy = cpu_p2[7];

    i8035 mcu (
        .clk     (clk),
        .ce      (ce_cpu),
        .I_RSTn  (~reset),
        .I_INTn  (cmd_w[3]),
        .I_EA    (1'b1),              // program supplied externally
        .O_PSENn (psen_n),
        .O_RDn   (rd_n),
        .O_WRn   (),
        .O_ALE   (ale),
        .O_PROGn (prog_pin),
        .I_T0    (1'b1),
        .O_T0    (),
        .I_T1    (1'b0),              // "TEST", tied to ground
        .I_DB    (cpu_di),
        .O_DB    (cpu_do),
        .I_P1    (8'hFF),
        .O_P1    (cpu_p1),
        .I_P2    (p2_in),
        .O_P2    (cpu_p2)
    );

    //------------------------------------------------------------------------
    // 8-bit R-2R DAC. P1 is an unsigned sample; centre it and scale.
    //------------------------------------------------------------------------
    wire signed [8:0]  centred = $signed({1'b0, cpu_p1}) - 9'sd128;
    wire signed [15:0] dac     = {centred, 7'd0};

    assign audio = GAIN_LOG2 == 0 ? dac : (dac <<< GAIN_LOG2);

endmodule
