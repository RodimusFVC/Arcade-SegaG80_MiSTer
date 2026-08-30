// ---------------------------------------------------------------------------
// mm5837_noise.v -- U13 (315-0035), the board's single noise source.
//
// The MM5837 is a 17-stage shift register with XOR feedback from stages
// 17 and 14, clocked by an on-chip RC oscillator. That oscillator is supply
// and part dependent; ~32-48 kHz is the usual measured range at +12V, which
// is why the noise on these boards has an audible "gritty" ceiling rather
// than sounding like clean white noise. NOISE_HZ is left as a parameter so
// you can match a particular board.
// ---------------------------------------------------------------------------

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
            lfsr <= 17'h1ACE1;                 // any non-zero seed
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


// ---------------------------------------------------------------------------
// env_gen.v -- stands in for the 74123 one-shots (U1,U2,U20) and the RC
// decay networks feeding the MB4391 VCAs (U28,U30,U31).
//
// trig  : one-clock pulse, snaps the envelope to full scale
// sustain: hold at full scale instead of decaying (helicopter, whistle)
// ---------------------------------------------------------------------------

module env_gen #(
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer TICK_HZ     = 8_000,
    parameter integer DECAY_SHIFT = 7      // larger = slower decay
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
