//============================================================================
//
//  Sega G-80 program ROM
//  48 KB dpram loaded from ioctl (index 0) at offsets 0x00000–0x0BFFF.
//  Port A: write from ioctl. Port B: Z80 read.
//
//============================================================================

module segag80_rom (
    input              clk,

    // ioctl write side
    input       [24:0] ioctl_addr,
    input        [7:0] ioctl_data,
    input              ioctl_wr,
    input        [7:0] ioctl_index,

    // Z80 read side
    input       [15:0] cpu_addr,     // 0x0000–0xBFFF
    output reg   [7:0] cpu_dout
);

    reg [7:0] mem [0:48*1024-1];

    wire rom_wr = ioctl_wr && (ioctl_index == 8'd0) &&
                  (ioctl_addr < 25'h0C000);

    always @(posedge clk) begin
        if (rom_wr)
            mem[ioctl_addr[15:0]] <= ioctl_data;
        cpu_dout <= mem[cpu_addr[15:0]];
    end

endmodule
