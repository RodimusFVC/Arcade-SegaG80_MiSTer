//============================================================================
//
//  Sega G-80 raster video — VRAM + palette + tilemap scanout
//  MAME segag80r_v.cpp (videoram_w, draw_videoram, g80_set_palette_entry)
//
//============================================================================

module segag80_video (
    input              clk,
    input              reset,

    // CPU write side
    input       [12:0] cpu_addr,        // VRAM offset 0x0000–0x1FFF
    input        [7:0] cpu_din,
    input              cpu_wr,
    input              video_control_1, // m_video_control[1]: palette enable
    input              video_flip,      // m_video_flip

    // Scanout side — from T1.4 vtg
    input              ce_pix,
    input        [8:0] h_cnt,           // 0..327
    input        [8:0] v_cnt,           // 0..261

    // RGB out (resistor-ladder approximation)
    output       [7:0] r_out,
    output       [7:0] g_out,
    output       [7:0] b_out,

    // VRAM read for CPU (for readback)
    output       [7:0] cpu_dout
);

    //------------------------------------------------------------------------
    // Palette-write decode
    //   MAME: offset&0x1000 && video_control&0x02 → paletteram
    //------------------------------------------------------------------------
    wire pal_write  = cpu_wr & cpu_addr[12] & video_control_1;
    wire vram_write = cpu_wr & ~pal_write;

    //------------------------------------------------------------------------
    // 8 KB VRAM — dual-port
    //------------------------------------------------------------------------
    reg [7:0] vram [0:8191];
    reg [7:0] vram_cpu_rd;
    reg [7:0] vram_scan_rd;
    reg [12:0] scan_addr;

    always @(posedge clk) begin
        if (vram_write)
            vram[cpu_addr] <= cpu_din;
        vram_cpu_rd <= vram[cpu_addr];
        vram_scan_rd <= vram[scan_addr];
    end

    assign cpu_dout = vram_cpu_rd;

    //------------------------------------------------------------------------
    // 64-entry palette RAM
    //   MAME: paletteram offset = cpu_addr & 0x3F
    //   Byte format: bits[2:0]=R, bits[5:3]=G, bits[7:6]=B
    //------------------------------------------------------------------------
    reg [7:0] pal [0:63];
    wire [5:0] pal_wr_addr = cpu_addr[5:0];

    always @(posedge clk) begin
        if (pal_write)
            pal[pal_wr_addr] <= cpu_din;
    end

    //------------------------------------------------------------------------
    // Resistor-ladder DAC approximation
    //   R,G: 3 bits → 8 levels. MAME combine_weights with 4700/2400/1200+220.
    //        Approximate LUT: [0, 36, 73, 109, 146, 182, 219, 255]
    //   B:   2 bits → 4 levels. Approximate LUT: [0, 85, 170, 255]
    //------------------------------------------------------------------------
    function [7:0] dac3;
        input [2:0] v;
        case (v)
            3'd0: dac3 = 8'd0;
            3'd1: dac3 = 8'd36;
            3'd2: dac3 = 8'd73;
            3'd3: dac3 = 8'd109;
            3'd4: dac3 = 8'd146;
            3'd5: dac3 = 8'd182;
            3'd6: dac3 = 8'd219;
            3'd7: dac3 = 8'd255;
        endcase
    endfunction

    function [7:0] dac2;
        input [1:0] v;
        case (v)
            2'd0: dac2 = 8'd0;
            2'd1: dac2 = 8'd85;
            2'd2: dac2 = 8'd170;
            2'd3: dac2 = 8'd255;
        endcase
    endfunction

//------------------------------------------------------------------------
    // Scanout pipeline — G80R character bitmap (MAME charlayout at
    // segag80r.cpp:1021; videoram_w map at segag80r_v.cpp:260-277;
    // draw_videoram at segag80r_v.cpp:632).
    //
    //   VRAM layout (per videoram_w — mark_dirty on offset & 0x800):
    //     0x0000..0x07FF : tilemap (tile codes, 32x28 used)
    //     0x0800..0x0FFF : plane 0 bitmap (LSB of pixel color)
    //     0x1000..0x103F : palette (when video_control & 0x02)
    //     0x1800..0x1FFF : plane 1 bitmap (MSB of pixel color)
    //
    //   Per tile:
    //     tile_code = VRAM[effy*32 + effx]                     (base 0x0000)
    //     plane 0   = VRAM[0x0800 | {tile_code, pix_row}]      (base 0x0800)
    //     plane 1   = VRAM[0x1800 | {tile_code, pix_row}]      (base 0x1800)
    //   Per pixel (x = pix_col, 0 = leftmost pixel):
    //     bit_sel    = 7 - x                                   (MAME xbits {0..7} = MSB first;
    //                                                           bit-offset 0 is byte MSB per
    //                                                           gfxdecode convention)
    //     pixel_2bit = {plane1[bit_sel], plane0[bit_sel]}
    //     pal_index  = {tile_code[7:4], pixel_2bit}            (6 bits, 64-entry pal)
    //
    // We prefetch tile N+1's data during pix_col 5,6,7 of tile N (3
    // single-cycle BRAM reads). 24 clk_sys per tile, 3 reads needed —
    // plenty of slack.
    //
    // Known limitation: the first character cell of each scanline (pix_col
    // 0..7 at h_cnt=0..7) renders whatever stale data is in the _cur regs
    // from the previous line, because prefetch for tile_x=0 would need to
    // happen during the prior line's hblank. Artifact is ~8 pixels at the
    // left edge — acceptable for first-light; cleaner hblank-prefetch is
    // a later refinement.
    //------------------------------------------------------------------------
    wire [4:0] char_x  = h_cnt[7:3];
    wire [4:0] char_y  = v_cnt[7:3];
    wire [2:0] pix_col = h_cnt[2:0];
    wire [2:0] pix_row = v_cnt[2:0];

    wire [4:0] flipmask5   = {5{video_flip}};
    wire [4:0] effy        = video_flip ? (5'd27 - char_y) : char_y;
    wire [4:0] next_char_x = char_x + 5'd1;
    wire [4:0] eff_next_x  = next_char_x ^ flipmask5;
    wire [2:0] eff_pix_col = video_flip ? ~pix_col : pix_col;
    wire [2:0] eff_pix_row = video_flip ? ~pix_row : pix_row;

    // Prefetch targets for tile N+1:
    reg  [7:0]  tile_code_next;
    reg  [7:0]  plane0_next;
    reg  [7:0]  plane1_next;
    wire [12:0] addr_tc_next = {3'b000, effy, eff_next_x};
    wire [12:0] addr_p0_next = {2'b01,  tile_code_next, eff_pix_row};  // 0x0800 base
    wire [12:0] addr_p1_next = {2'b11,  tile_code_next, eff_pix_row};  // 0x1800 base
    // Plane base offsets per MAME segag80r_v.cpp videoram_w (mark_dirty on offset & 0x800).
    // addr_p1 has bit 12 set → VRAM offset 0x1000, matches charlayout.

    // scan_addr is now combinational (driven by pix_col schedule).
    // Was a `reg` driven by a clocked always block — remove that.
    always @* begin
        case (pix_col)
            3'd5:    scan_addr = addr_tc_next;
            3'd6:    scan_addr = addr_p0_next;
            3'd7:    scan_addr = addr_p1_next;
            default: scan_addr = 13'd0;   // don't-care; vram_scan_rd ignored
        endcase
    end

    // vram_scan_rd is valid 1 clk_sys after scan_addr changes. pix_col_d
    // lags pix_col by one clk_sys, so `pix_col_d == N` means scan_addr
    // was set to phase-N's target one cycle ago and vram_scan_rd now
    // reflects that read.
    reg [2:0] pix_col_d;
    always @(posedge clk) begin
        pix_col_d <= pix_col;
        if (pix_col_d == 3'd5) tile_code_next <= vram_scan_rd;
        if (pix_col_d == 3'd6) plane0_next    <= vram_scan_rd;
        if (pix_col_d == 3'd7) plane1_next    <= vram_scan_rd;
    end

    // Transfer to CURRENT registers at the tile boundary (pix_col 7 → 0):
    reg [7:0] tile_code_cur;
    reg [7:0] plane0_cur;
    reg [7:0] plane1_cur;
    always @(posedge clk) begin
        if (ce_pix && pix_col == 3'd7) begin
            tile_code_cur <= tile_code_next;
            plane0_cur    <= plane0_next;
            plane1_cur    <= plane1_next;
        end
    end

    // Current-pixel lookup.
    // MAME charlayout xbits = {0,1,..,7}: leftmost pixel (pix_col=0) takes bit-offset 0,
    // which per MAME's gfxdecode extraction is the byte's MSB (bit 7).  So bit index = ~pix_col.
    wire [2:0] bit_sel    = ~eff_pix_col;
    wire       plane0_bit = plane0_cur[bit_sel];
    wire       plane1_bit = plane1_cur[bit_sel];
    wire [1:0] pixel_2bit = {plane1_bit, plane0_bit};
    wire [5:0] pal_index  = {tile_code_cur[7:4], pixel_2bit};
    wire [7:0] pal_entry  = pal[pal_index];

    wire active = (h_cnt < 9'd256) && (v_cnt < 9'd224);

    assign r_out = active ? dac3(pal_entry[2:0]) : 8'd0;
    assign g_out = active ? dac3(pal_entry[5:3]) : 8'd0;
    assign b_out = active ? dac2(pal_entry[7:6]) : 8'd0;

endmodule