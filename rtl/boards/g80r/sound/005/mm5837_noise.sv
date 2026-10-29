
`default_nettype none

module mm5837_noise #(
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer NOISE_HZ = 40_000
)(
    input  wire               clk,
    input  wire               rst_n,
    output wire               noise_bit,
    output wire signed [17:0] noise_out
);

    localparam [63:0] DIVN = (64'd0 + CLK_HZ) / NOISE_HZ - 64'd1;

    reg [31:0] div;
    reg [16:0] lfsr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div  <= 32'd0;
            lfsr <= 17'h1ACE1;
        end else if (div >= DIVN[31:0]) begin
            div  <= 32'd0;
            lfsr <= {lfsr[15:0], lfsr[16] ^ lfsr[13]};
        end else begin
            div <= div + 32'd1;
        end
    end

    assign noise_bit = lfsr[16];
    assign noise_out = lfsr[16] ? 18'sd40000 : -18'sd40000;

endmodule

module env_gen #(
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer TICK_HZ     = 8_000,
    parameter integer DECAY_SHIFT = 7
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        trig,
    input  wire        sustain,
    output reg  [15:0] level
);

    localparam [63:0] DIVT = (64'd0 + CLK_HZ) / TICK_HZ - 64'd1;

    reg [31:0] div;
    wire       tick = (div >= DIVT[31:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div   <= 32'd0;
            level <= 16'd0;
        end else begin
            div <= tick ? 32'd0 : (div + 32'd1);

            if (trig)
                level <= 16'hFFFF;
            else if (sustain)
                level <= 16'hFFFF;
            else if (tick) begin
                if (level > (16'd1 << DECAY_SHIFT))
                    level <= level - (level >> DECAY_SHIFT);
                else
                    level <= 16'd0;
            end
        end
    end

endmodule

`default_nettype wire
