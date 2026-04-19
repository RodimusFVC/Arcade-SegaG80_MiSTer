//============================================================================
//
//  Sega G-80 raster video timing generator
//  MAME segag80r.cpp:132-140, 1071
//  HTOTAL=328, HBSTART=256, VTOTAL=262, VBSTART=224
//
//============================================================================

module segag80_vtg (
    input            clk,
    input            reset,
    input            ce_pix,

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

    localparam HSYNC_START = 9'd288;
    localparam HSYNC_END   = 9'd319;    // inclusive
    localparam VSYNC_START = 9'd232;
    localparam VSYNC_END   = 9'd240;    // inclusive

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
    assign hsync  = (h_cnt >= HSYNC_START) && (h_cnt <= HSYNC_END);
    assign vsync  = (v_cnt >= VSYNC_START) && (v_cnt <= VSYNC_END);

endmodule
