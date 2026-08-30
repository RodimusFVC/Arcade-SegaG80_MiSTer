// ---------------------------------------------------------------------------
// i8255_mode0.v -- enough of an 8255A to stand in for U5 (315-0080).
//
// The 005 program only ever uses mode 0 with A and B as outputs, so this
// implements mode 0 plus the bit set/reset command. Ports read back the
// last value written, which is what the real part does for outputs.
//
// The bus strobes are registered before the edge is detected, so an
// asynchronous Z80-side WR of any width longer than one clk is captured
// exactly once with no combinational race.
//
// Address decode on the real board comes from CS, A0 and A1 off the G-80 bus.
// In the G-80 I/O map the PPI sits at Z80 ports $0C..$0F:
//   $0C = port A, $0D = port B, $0E = port C, $0F = control
// ---------------------------------------------------------------------------

`default_nettype none

module i8255_mode0 (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       cs_n,
    input  wire       wr_n,
    input  wire       rd_n,
    input  wire [1:0] addr,
    input  wire [7:0] din,
    output reg  [7:0] dout,

    output reg  [7:0] pa,
    output reg  [7:0] pb,
    output reg  [7:0] pc
);

    // Synchronise and edge-detect the write strobe
    reg       wr_s, wr_q;
    reg [1:0] addr_s;
    reg [7:0] din_s;

    wire wr_stb = wr_s & ~wr_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_s   <= 1'b0;
            wr_q   <= 1'b0;
            addr_s <= 2'd0;
            din_s  <= 8'h00;
            pa     <= 8'hFF;   // triggers are active low, so idle high
            pb     <= 8'h00;
            pc     <= 8'h00;
        end else begin
            wr_s   <= ~cs_n & ~wr_n;
            wr_q   <= wr_s;
            addr_s <= addr;
            din_s  <= din;

            if (wr_stb) begin
                case (addr_s)
                    2'd0: pa <= din_s;
                    2'd1: pb <= din_s;
                    2'd2: pc <= din_s;
                    2'd3: begin
                        if (din_s[7]) begin
                            // Mode set: the real part clears the output latches
                            pa <= 8'hFF;
                            pb <= 8'h00;
                            pc <= 8'h00;
                        end else begin
                            // Bit set/reset on port C
                            pc[din_s[3:1]] <= din_s[0];
                        end
                    end
                endcase
            end
        end
    end

    always @(*) begin
        if (!cs_n && !rd_n) begin
            case (addr)
                2'd0:    dout = pa;
                2'd1:    dout = pb;
                2'd2:    dout = pc;
                default: dout = 8'hFF;
            endcase
        end else begin
            dout = 8'hFF;
        end
    end

endmodule

`default_nettype wire
