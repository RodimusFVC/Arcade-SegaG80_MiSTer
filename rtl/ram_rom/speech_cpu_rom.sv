// 8035 program ROM — 2 KB (808b.u7).
// Loaded from ioctl at base offset 0x10000; ioctl_addr[10:0] gives the
// byte position within the ROM (0x10000's low 11 bits are all zero).
module speech_cpu_rom (
    input               clk,
    input        [10:0] ioctl_addr,
    input         [7:0] ioctl_data,
    input               ioctl_wr,
    input        [10:0] cpu_addr,
    output reg    [7:0] cpu_data
);
    reg [7:0] mem [0:2047];

    always @(posedge clk) begin
        if (ioctl_wr) mem[ioctl_addr] <= ioctl_data;
        cpu_data <= mem[cpu_addr];
    end
endmodule
