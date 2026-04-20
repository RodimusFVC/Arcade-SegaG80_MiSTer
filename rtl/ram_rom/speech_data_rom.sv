// Speech data ROM — 8 KB populated (809a/810/811/812a concatenated).
// CPU-side address is 14 bits; upper 8 KB (cpu_addr[13]=1) returns 0xFF
// since the 8035 firmware should not reach there.
// Loaded from ioctl at base offset 0x10800.
// ioctl_addr is the pre-computed offset within this ROM (0x0000–0x1FFF).
module speech_data_rom (
    input               clk,
    input        [12:0] ioctl_addr,
    input         [7:0] ioctl_data,
    input               ioctl_wr,
    input        [13:0] cpu_addr,
    output reg    [7:0] cpu_data
);
    reg [7:0] mem [0:8191];

    always @(posedge clk) begin
        if (ioctl_wr) mem[ioctl_addr] <= ioctl_data;
        cpu_data <= cpu_addr[13] ? 8'hFF : mem[cpu_addr[12:0]];
    end
endmodule
