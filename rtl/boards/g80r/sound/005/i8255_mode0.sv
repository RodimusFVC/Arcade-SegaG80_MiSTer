
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
            pa     <= 8'hFF;
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
                            pa <= 8'hFF;
                            pb <= 8'h00;
                            pc <= 8'h00;
                        end else begin
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
