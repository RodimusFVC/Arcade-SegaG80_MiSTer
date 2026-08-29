//============================================================================
//  Monster Bash — music half of the sound board (TMS3617)
//
//  MAME segag80r_a.cpp:227 monsterb_sound_device::sound_a_w, reached from the
//  i8255 PPI port A at $0C:
//
//      low nibble  -> one of 13 note lines on the TMS3617
//      high nibble -> address into an 82S123 (pr1512.u31); its bits 7-2 are
//                     the six voice-enable lines
//
//  The PROM is 32 x 8 but only the low 16 entries are reachable. It is small
//  enough to sit in logic, so the read is asynchronous and the note and enable
//  writes land on the same cycle, as they do in MAME.
//============================================================================

`default_nettype none

module monsterb_music #(
    parameter int unsigned CLK_HZ = 15_468_480
)(
    input  wire               clk,
    input  wire               reset,

    input  wire               port_a_wr,    // PPI port A ($0C) write strobe
    input  wire        [7:0]  port_a_din,

    // 82S123 voice-enable PROM — ioctl index 4
    input  wire        [4:0]  ioctl_addr,
    input  wire        [7:0]  ioctl_data,
    input  wire               ioctl_wr,

    output wire signed [15:0] audio
);

    reg [7:0] prom [0:31];
    always @(posedge clk) if (ioctl_wr) prom[ioctl_addr] <= ioctl_data;

    wire [7:0] prom_q = prom[{1'b0, port_a_din[7:4]}];

    // MAME: TMS36XX(config, m_music, 247), TMS3617, decays all 0.5 s.
    tms36xx #(
        .CLK_HZ    (CLK_HZ),
        .BASEFREQ  (247),
        .DECAY0_MS (500), .DECAY1_MS (500), .DECAY2_MS (500),
        .DECAY3_MS (500), .DECAY4_MS (500), .DECAY5_MS (500)
    ) u_tms3617 (
        .clk          (clk),
        .reset        (reset),
        .note_we      (port_a_wr),
        .note_octave  (2'd0),                // sound_a_w passes octave 0
        .note         (port_a_din[3:0]),
        .enable_we    (port_a_wr),
        .voice_enable (prom_q[7:2]),         // tms3617_enable_w(val >> 2)
        .audio        (audio),
        .ce_snd       ()
    );

endmodule

`default_nettype wire
