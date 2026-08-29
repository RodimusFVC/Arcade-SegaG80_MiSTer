//============================================================================
//
//  Sega G-80 raster background board — "full scroll" variant
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_v.cpp (bg_get_tile_info, draw_background_full_scroll,
//  pignewt_back_port_w) and segag80r.cpp (monsterb_expand_gfx, gfx_monsterb).
//
//  Used by G80_BACKGROUND_PIGNEWT (Pig Newton), G80_BACKGROUND_SINDBADM and,
//  via mb_mode, G80_BACKGROUND_MONSTERB (draw_background_page_scroll).
//
//  Monster Bash shares bg_get_tile_info and monsterb_expand_gfx but differs
//  in geometry and scrolling: 32 x (gfx2/32) = 32x256 tiles => 256x2048 px,
//  an 8-bit flip mask, no X scroll, and a Y offset that is an 8-page select
//  added OUTSIDE the 8-bit line wrap — that is what makes it page scroll.
//
//  The tilemap is 128 x 128 tiles of 8x8 (gfx2 region is 0x4000 bytes, one
//  byte per tile => 0x4000/128 = 128 rows), giving a 1024x1024 pixmap, so
//  both scroll masks are 0x3FF and the AND is implicit in the 10-bit width.
//  The map lives in ROM, not RAM — nothing here is CPU-writable.
//
//  MAME expands gfx1 into 16 banks with monsterb_expand_gfx, but the
//  expansion is pure address arithmetic, so the two raw 8 KB ROMs are
//  addressed directly instead:
//      dest[0x0000 + i*0x800] = src[0x0000 + (i & 3)*0x800]   plane 0
//      dest[0x8000 + i*0x800] = src[0x2000 + (i >> 2)*0x800]  plane 1
//  With tile = code + 0x100*bank, tile*8 = code*8 + bank*0x800, so:
//      plane 0 = rom_p0[{bank[1:0], code, row}]
//      plane 1 = rom_p1[{bank[3:2], code, row}]
//
//============================================================================

module segag80_bg (
    input              clk,
    input              ce_pix,
    input        [8:0] h_cnt,           // 0..327
    input        [8:0] v_cnt,           // 0..261

    // Background board registers — ports $B8-$BD
    input        [9:0] bg_scrollx,
    input       [10:0] bg_scrolly,
    input        [3:0] bg_char_bank,
    input              bg_flip,         // video_control[3]
    input              mb_mode,         // 1 = Monster Bash page scroll
    input              sm_mode,         // 1 = Sindbad page scroll, 128-wide, unexpanded gfx

    // ROM loading
    input       [24:0] ioctl_addr,
    input        [7:0] ioctl_data,
    input              ioctl_wr,
    input              sel_tiles,       // gfx1 — 16 KB, plane 0 then plane 1
    input              sel_map,         // gfx2 — 16 KB tilemap

    // Pixel out — palette index is {1'b1, bg_color, bg_pix} (MAME color base 64)
    output       [3:0] bg_color,
    output       [1:0] bg_pix
);

    //------------------------------------------------------------------------
    // ROMs
    //------------------------------------------------------------------------
    reg [7:0] rom_p0  [0:8191];     // gfx1 0x0000-0x1FFF — plane 0 (LSB)
    reg [7:0] rom_p1  [0:8191];     // gfx1 0x2000-0x3FFF — plane 1 (MSB)
    reg [7:0] rom_map [0:32767];    // gfx2 — one byte per tile (Sindbad needs 32 KB)

    wire        ld_plane1 = ioctl_addr[13];
    wire [12:0] ld_tile   = ioctl_addr[12:0];
    wire [14:0] ld_map    = ioctl_addr[14:0];

    //------------------------------------------------------------------------
    // Fetch two display pixels ahead. The wrap logic mirrors segag80_video.sv
    // so the leading pixels of each line are fetched during the prior hblank.
    //------------------------------------------------------------------------
    wire [9:0] fetch_h_raw  = {1'b0, h_cnt} + 10'd2;
    wire       fetch_h_wrap = (fetch_h_raw >= 10'd328);
    wire [8:0] fetch_h      = fetch_h_wrap ? (fetch_h_raw[8:0] - 9'd328) : fetch_h_raw[8:0];
    wire [8:0] fetch_v_raw  = fetch_h_wrap ? (v_cnt + 9'd1) : v_cnt;
    wire [8:0] fetch_v      = (fetch_v_raw >= 9'd262) ? 9'd0 : fetch_v_raw;

    // Pig Newton / Sindbad — draw_background_full_scroll:
    //   effx = (x + scrollx) ^ flipmask, effy = (y + scrolly) ^ flipmask, 10-bit.
    wire [9:0] flipmask = {10{bg_flip}};
    wire [9:0] effx_fs  = ({1'b0, fetch_h} + bg_scrollx) ^ flipmask;
    wire [9:0] effy_fs  = ({1'b0, fetch_v} + bg_scrolly[9:0]) ^ flipmask;

    // Monster Bash — draw_background_page_scroll:
    //   effy = scrolly + (((y ^ flip) + (flip & 0xe0)) & 0xff)
    //   effx = (x ^ flip)                       (bg_scrollx is always 0 here)
    wire [7:0]  flipmask8 = {8{bg_flip}};
    wire [7:0]  ps_inner  = (fetch_v[7:0] ^ flipmask8) + (bg_flip ? 8'hE0 : 8'h00);
    wire [10:0] effy_ps   = bg_scrolly + {3'd0, ps_inner};
    wire [7:0]  effx_ps   = fetch_h[7:0] ^ flipmask8;

    // Sindbad shares the page-scroll formula but keeps a 128-wide map and a
    // real X scroll ((data<<6)&0x300), so effx must carry bg_scrollx.
    wire        page_mode = mb_mode | sm_mode;
    wire [9:0]  effx_pg   = bg_scrollx + {2'b00, effx_ps};

    wire [10:0] effy = page_mode ? effy_ps : {1'b0, effy_fs};
    wire [9:0]  effx = page_mode ? effx_pg : effx_fs;

    // Pixmaps: Pig Newton 1024x1024, Monster Bash 256x2048, Sindbad 1024x2048.
    // Map width: 128 tiles except Monster Bash's 32.
    wire [14:0] map_rd_addr = mb_mode ? {2'b00, effy[10:3], effx[7:3]}
                            : sm_mode ? {      effy[10:3], effx[9:3]}
                                      : {2'b00, effy[9:3],  effx[9:3]};

    //------------------------------------------------------------------------
    // Two-stage fetch: tilemap byte, then its two plane bytes in parallel.
    // Three clk_sys per ce_pix leaves ample slack for each registered read.
    //------------------------------------------------------------------------
    reg [7:0] map_dout, p0_dout, p1_dout;
    reg [7:0] code_s1;
    reg [2:0] px_s1, row_s1;
    reg [7:0] code_s2, p0_s2, p1_s2;
    reg [2:0] px_s2;

    wire [12:0] p0_rd_addr = {bg_char_bank[1:0], code_s1, row_s1};
    // init_sindbadm does NOT call monsterb_expand_gfx: gfx1 is a plain
    // gfx_8x8x2_planar region, so plane 1 uses the SAME bank bits as plane 0.
    // The expanded games take plane 1's bank from bits [3:2] instead.
    wire [12:0] p1_rd_addr = sm_mode ? {bg_char_bank[1:0], code_s1, row_s1}
                                     : {bg_char_bank[3:2], code_s1, row_s1};

    always @(posedge clk) begin
        if (ioctl_wr & sel_map)                rom_map[ld_map]  <= ioctl_data;
        if (ioctl_wr & sel_tiles & ~ld_plane1) rom_p0[ld_tile]  <= ioctl_data;
        if (ioctl_wr & sel_tiles &  ld_plane1) rom_p1[ld_tile]  <= ioctl_data;

        map_dout <= rom_map[map_rd_addr];
        p0_dout  <= rom_p0[p0_rd_addr];
        p1_dout  <= rom_p1[p1_rd_addr];

        if (ce_pix) begin
            code_s1 <= map_dout;
            px_s1   <= effx[2:0];
            row_s1  <= effy[2:0];

            code_s2 <= code_s1;
            px_s2   <= px_s1;
            p0_s2   <= p0_dout;
            p1_s2   <= p1_dout;
        end
    end

    // Leftmost pixel is the byte MSB, matching the foreground charlayout.
    wire [2:0] bit_sel = ~px_s2;

    assign bg_color = code_s2[7:4];
    assign bg_pix   = {p1_s2[bit_sel], p0_s2[bit_sel]};

endmodule
