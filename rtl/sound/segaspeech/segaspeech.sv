//============================================================================
// Sega speech board wrapper — STUB (speech disabled).
//
// The full 8035 + SP0250 + latch + CD4053 implementation drove Quartus past
// the Cyclone V ALM budget and exploded compile times. This stub preserves
// the exact port interface so SegaG80.sv needs no changes; it keeps the $3B
// bit3 gate register for Z80-side compat and outputs silence. The original
// implementation, T48 core, and SP0250 core all remain on disk and can be
// re-enabled by uncommenting them in files.qip once a tighter architecture
// exists.
//============================================================================

module segaspeech (
    input                clk,
    input                reset_n,
    input        [7:0]   data_w,
    input                data_we,
    input        [7:0]   ctrl_w,
    input                ctrl_we,
    output       [10:0]  rom_8035_addr,
    input        [7:0]   rom_8035_data,
    output       [13:0]  rom_speech_addr,
    input        [7:0]   rom_speech_data,
    output signed [15:0] audio_out,
    output               audio_valid
);

    // $3B bit3 = speech audio gate (CD4053 ch1). Preserved for Z80 compat.
    reg speech_gate;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)     speech_gate <= 1'b0;
        else if (ctrl_we) speech_gate <= ctrl_w[3];
    end

    // Keep unused inputs lint-clean so Quartus doesn't warn-storm.
    wire _unused = |{data_w, data_we, rom_8035_data, rom_speech_data, speech_gate};

    assign rom_8035_addr   = 11'd0;
    assign rom_speech_addr = 14'd0;
    assign audio_out       = 16'sd0;
    assign audio_valid     = 1'b0;

endmodule
