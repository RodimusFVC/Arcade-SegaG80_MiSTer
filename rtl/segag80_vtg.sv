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

    // DIAG-REVERT-2026-09-01: OSD Screen Centering offsets, two's complement (+-8).
    // The CONF_STR entries for these already existed but were never wired to
    // anything -- the menu consumed status[10:3] and did nothing.
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

    // ==========================================================================
    // DIAG-REVERT-2026-09-01 -- ANALOG/CRT SYNC PLACEMENT + live centering
    //
    // Pixel clock is 5.15616 MHz (VIDEO_CLOCK/3, correct since CLOCK-SWAP-FIX-
    // 2026-07-26), so HTOTAL 328 = 63.6 us = 15.72 kHz and VTOTAL 262 = 60.0 Hz.
    // The raster rate is textbook; the porch SPLIT was not. HTOTAL and HBSTART come
    // from MAME (segag80r.cpp:134-136) and give 72 counts / 13.96 us of blanking,
    // but MAME's set_raw says nothing about where sync sits inside that, so the
    // placement was invented:
    //
    //   old:  front 256..287 = 32 cnt = 6.21 us
    //         sync  288..319 = 32 cnt = 6.21 us
    //         back  320..327 =  8 cnt = 1.55 us   <-- runt
    //
    //   new:  front 256..267 = 12 cnt = 2.33 us   (h_center = 0)
    //         sync  268..295 = 28 cnt = 5.43 us
    //         back  296..327 = 32 cnt = 6.20 us
    //
    // A 15 kHz tube wants roughly front 1.5 / sync 4.7 / back 5.7 us, with the BACK
    // porch the longest -- it is what the clamp settles on and what sets horizontal
    // image position. It was the shortest by a factor of four. HDMI never sees this
    // (ascal re-times off DE). Same defect class as Vastar and Kangaroo, 2026-09-01.
    //
    // Across the full +-8 centering range: front 4..20 cnt (0.78..3.88 us), back
    // 40..24 cnt (7.76..4.65 us). Every setting stays in the blanking region.
    //
    // Vertical is left as it was apart from becoming adjustable: vblank is 38 lines
    // (v_cnt 224..261) and the 9-line pulse at 232 sits well inside it. +-8 keeps
    // vs_start in 224..240 and vs_end in 232..248, never on a visible line (0..223).
    // NOTE the 9-line vsync is wide for NTSC (3 is typical); left alone deliberately,
    // there is no evidence it misbehaves and it is not what this fix is about.
    //
    // TO REVERT: uncomment the four localparams, delete the DIAG wires, and restore
    // the two assigns at the bottom of this module to use them.
    // // localparam HSYNC_START = 9'd288;
    // // localparam HSYNC_END   = 9'd319;    // inclusive
    // // localparam VSYNC_START = 9'd232;
    // // localparam VSYNC_END   = 9'd240;    // inclusive
    // ==========================================================================
    wire [8:0] hs_start = 9'd268 + {{5{h_center[3]}}, h_center};  // DIAG
    wire [8:0] hs_end   = hs_start + 9'd27;   // DIAG: inclusive -> 28 counts wide
    wire [8:0] vs_start = 9'd232 + {{5{v_center[3]}}, v_center};  // DIAG
    wire [8:0] vs_end   = vs_start + 9'd8;    // DIAG: inclusive -> 9 lines, unchanged

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
    // DIAG-REVERT-2026-09-01: originals, uncomment to restore
    // assign hsync  = (h_cnt >= HSYNC_START) && (h_cnt <= HSYNC_END);
    // assign vsync  = (v_cnt >= VSYNC_START) && (v_cnt <= VSYNC_END);
    assign hsync  = (h_cnt >= hs_start) && (h_cnt <= hs_end);   // DIAG
    assign vsync  = (v_cnt >= vs_start) && (v_cnt <= vs_end);   // DIAG

endmodule
