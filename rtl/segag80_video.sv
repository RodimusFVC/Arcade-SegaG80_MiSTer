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
    input              flip_vertical,   // CRT Flip OSD override (status[22] at
                                         // the Arcade-SegaG80.sv level), XOR'd
                                         // against video_flip below. Same
                                         // pattern as JunoFirst_CPU.sv's
                                         // eff_x/eff_y flip_vertical XOR.

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
    // plenty of slack. The fetch position is computed as (h_cnt+8) so the
    // schedule rolls smoothly across line boundaries: tile 0 of each row is
    // prefetched during the last tile of the prior row, and tile 0 of the
    // first row is prefetched during the last line of vblank.
    //------------------------------------------------------------------------
    wire [4:0] char_x  = h_cnt[7:3];
    wire [4:0] char_y  = v_cnt[7:3];
    wire [2:0] pix_col = h_cnt[2:0];
    wire [2:0] pix_row = v_cnt[2:0];

    // CRT Flip (flip_vertical) XORs on top of the game's native cocktail-flip
    // bit (video_flip) so the OSD toggle works regardless of what the game
    // itself has set — same combination JunoFirst uses for flip_x/flip_y.
    wire       flip_eff     = video_flip ^ flip_vertical;
    wire [4:0] flipmask5   = {5{flip_eff}};
    wire [2:0] flipmask3   = {3{flip_eff}};

    // Display-side effective coords (for bit_sel on _cur registers).
    wire [2:0] eff_pix_col = pix_col ^ flipmask3;

    // ----- Fetch coords: 1 tile ahead of display (SNK6502-style continuous
    // prefetch). At pix_col 5/6/7 of the displayed tile we read the data
    // for the NEXT tile to be displayed. By computing fetch position from
    // (h_cnt + 8), the schedule rolls over naturally at end-of-line: during
    // the last tile of row N we are already fetching tile 0 of row N+1.
    // This eliminates the "first tile of each row is stale" artifact and
    // therefore the last-row mirroring symptom (last row was inheriting
    // the previous-row last-tile data from the forced-update kludge).
    //
    // h_cnt wraps at HTOTAL=328, v_cnt at VTOTAL=262.
    wire [9:0] fetch_h_raw  = {1'b0, h_cnt} + 10'd8;
    wire       fetch_h_wrap = (fetch_h_raw >= 10'd328);
    wire [8:0] fetch_h      = fetch_h_wrap ? (fetch_h_raw[8:0] - 9'd328) : fetch_h_raw[8:0];
    wire [8:0] fetch_v_raw  = fetch_h_wrap ? (v_cnt + 9'd1) : v_cnt;
    wire [8:0] fetch_v      = (fetch_v_raw >= 9'd262) ? 9'd0 : fetch_v_raw;

    wire [4:0] fetch_char_x = fetch_h[7:3];
    wire [4:0] fetch_char_y = fetch_v[7:3];

    // Clamp fetch_char_y to valid display rows (0..27). When fetch points
    // beyond row 27 (entering vblank), result is never displayed because
    // `active` gates the output to v_cnt < 224.
    wire [4:0] safe_fetch_char_y = (fetch_char_y > 5'd27) ? 5'd27 : fetch_char_y;

    wire [4:0] eff_fetch_char_y = flip_eff ? (5'd27 - safe_fetch_char_y) : safe_fetch_char_y;
    wire [4:0] eff_fetch_char_x = fetch_char_x ^ flipmask5;
    wire [2:0] eff_fetch_pix_row = fetch_v[2:0] ^ flipmask3;

    // Prefetch targets for the next tile to be displayed:
    reg  [7:0]  tile_code_next;
    reg  [7:0]  plane0_next;
    reg  [7:0]  plane1_next;
    wire [12:0] addr_tc_next = {3'b000, eff_fetch_char_y, eff_fetch_char_x};
    wire [12:0] addr_p0_next = {2'b01,  tile_code_next,    eff_fetch_pix_row};  // 0x0800 base
    wire [12:0] addr_p1_next = {2'b11,  tile_code_next,    eff_fetch_pix_row};  // 0x1800 base
    // Plane base offsets per MAME segag80r_v.cpp videoram_w (mark_dirty on offset & 0x800).
    // addr_p1 has bit 12 set → VRAM offset 0x1000, matches charlayout.

    // scan_addr is combinational (driven by pix_col schedule).
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

    // Transfer NEXT -> CUR at the end of each tile, every line, unconditionally.
    // No "forced update" special cases — the fetch coords looking 1 tile ahead
    // mean tile 0 of every row is correctly prefetched during the previous
    // row's last tile (or during hblank for the first row of a frame).
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