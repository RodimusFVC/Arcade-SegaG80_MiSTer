//  Based on MAME segag80r.cpp (Aaron Giles, BSD-3-Clause)

module segag80_vtg (
    input            clk,
    input            reset,
    input            ce_pix,

    input      [3:0] h_center,
    input      [3:0] v_center,

    output reg [8:0] h_cnt,
    output reg [8:0] v_cnt,
    output           hblank,
    output           vblank,
    output           hsync,
    output           vsync
);

    localparam HTOTAL  = 9'd328;
    localparam HBSTART = 9'd256;
    localparam VTOTAL  = 9'd262;
    localparam VBSTART = 9'd224;

    wire [8:0] hs_start = 9'd268 + {{5{h_center[3]}}, h_center};
    wire [8:0] hs_end   = hs_start + 9'd27;
    wire [8:0] vs_start = 9'd232 + {{5{v_center[3]}}, v_center};
    wire [8:0] vs_end   = vs_start + 9'd8;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            h_cnt <= 9'd0;
            v_cnt <= 9'd0;
        end else if (ce_pix) begin
            if (h_cnt == HTOTAL - 9'd1) begin
                h_cnt <= 9'd0;
                if (v_cnt == VTOTAL - 9'd1)
                    v_cnt <= 9'd0;
                else
                    v_cnt <= v_cnt + 9'd1;
            end else begin
                h_cnt <= h_cnt + 9'd1;
            end
        end
    end

    assign hblank = (h_cnt >= HBSTART);
    assign vblank = (v_cnt >= VBSTART);
    assign hsync  = (h_cnt >= hs_start) && (h_cnt <= hs_end);
    assign vsync  = (v_cnt >= vs_start) && (v_cnt <= vs_end);

endmodule
