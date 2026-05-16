// Speech data ROM — 8 KB populated (809a/810/811/812a concatenated).
// CPU-side address is 14 bits; upper 8 KB (cpu_addr[13]=1) returns 0xFF
// since the 8035 firmware should not reach there.
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
    assign cpu_data = upper_q ? 8'hFF : mem_q;
endmodule
