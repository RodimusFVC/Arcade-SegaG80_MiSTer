// Speech data ROM — 8 KB populated (809a/810/811/812a concatenated).
// CPU-side address is 14 bits; upper 8 KB (cpu_addr[13]=1) returns 0x00,
// matching MAME's zero-filled 0x4000 "speech:data" region. See FIX-2026-07-26
// below — the firmware DOES reach there, and 0xFF there is max-amplitude noise.
// Loaded from ioctl at base offset 0x10800.
// ioctl_addr is the pre-computed offset within this ROM (0x0000-0x1FFF).
//
// 2026-05-16 — M10K-inferring rewrite.
// Previous form had `cpu_data <= cpu_addr[13] ? 8'hFF : mem[cpu_addr[12:0]]`
// — the `?:` mux inside the BRAM data path forced Quartus to reject M10K
// inference and fall back to distributed flip-flops: ~30K ALUTs + 65K FFs
// for what should be ONE M10K block. (Confirmed in map.rpt by-entity table.)
// New form does a clean BRAM read into `mem_q`, then muxes outside — same
// 1-cycle latency, sibling `speech_cpu_rom` was the working reference.
module speech_data_rom (
    input               clk,
    input        [12:0] ioctl_addr,
    input         [7:0] ioctl_data,
    input               ioctl_wr,
    input        [13:0] cpu_addr,
    output        [7:0] cpu_data
);
    reg [7:0] mem [0:8191];
    reg [7:0] mem_q;
    reg       upper_q;

    always @(posedge clk) begin
        if (ioctl_wr) mem[ioctl_addr] <= ioctl_data;
        mem_q   <= mem[cpu_addr[12:0]];   // Clean BRAM read — Quartus infers M10K
        upper_q <= cpu_addr[13];           // Pipeline the upper-bit selector
    end

    // Mux on the BRAM output side, after the read register — preserves the
    // original module's 1-cycle latency without polluting the BRAM data path.
    //
    // ALIGN-2026-07-26 (⚠️ NOT A FIX — DISPROVEN AS THE GARBAGE CAUSE, see below).
    // Kept only because it matches the authoritative reference; behaviourally a NO-OP.
    //
    // A/B PROOF (verilator/speech_sim/fill_ab.py, ~7 s, no build): ran the firmware twice
    // changing ONLY this byte. Result: 6394 speech-ROM reads, **ZERO** at >= 0x2000;
    // P2 pages touched are 0x00-0x17 only; the two SP0250 streams came out BYTE-IDENTICAL
    // (12000 bytes). The firmware never reaches the fill, so 0xFF vs 0x00 cannot matter.
    // DO NOT re-derive this theory — it is dead. The garbage is made from GOOD data in the
    // populated region, which is where to look instead.
    //
    // Original rationale (now known to be only half-right):
    // unpopulated upper 8 KB returns 0x00, NOT 0xFF.
    // MAME declares `ROM_REGION(0x4000, "speech:data")` and loads only 0x2000
    // (segag80r.cpp astrob), so 0x2000-0x3FFF reads back as ZERO there.
    // The old 0xFF rested on the header's stated-but-unverified assumption that
    // "the 8035 firmware should not reach there". It does: MCS-48 reset leaves
    // P2 = 0xFF -> page 0x3F, and the firmware's wait loop tests T1(DRQ) BEFORE
    // T0(command) (speech_firmware_analysis_2026-05-20.md:30-31), so with an
    // empty FIFO it free-runs the feed path over whatever the pointer addresses.
    // Measured through the (co-sim-proven) SP0250 model:
    //     all-0x00 -> peak  0/64, rms  0.0  = SILENCE
    //     all-0xFF -> peak 64/64, rms 60.8, 43.5% at clamp = sustained max-amp buzz
    //     (ga(0xFF)=3968, gc(0xFF)=+511, frame[8]=0xFF -> voiced, repeat 63)
    // 43.5% matches the 40-42% clamp rate seen in the captured garbage streams.
    // ORIGINAL:
    // assign cpu_data = upper_q ? 8'hFF : mem_q;
    assign cpu_data = upper_q ? 8'h00 : mem_q;
endmodule
