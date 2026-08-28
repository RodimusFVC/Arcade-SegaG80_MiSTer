//============================================================================
//
//  Sega G-80 raster background board — "full scroll" variant
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_v.cpp (bg_get_tile_info, draw_background_full_scroll,
//  pignewt_back_port_w) and segag80r.cpp (monsterb_expand_gfx, gfx_monsterb).
//
//  Used by G80_BACKGROUND_PIGNEWT (Pig Newton) and G80_BACKGROUND_SINDBADM.
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
    input        [9:0] bg_scrolly,
    input        [3:0] bg_char_bank,
    input              bg_flip,         // video_control[3]

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
    reg [7:0] rom_map [0:16383];    // gfx2 — one byte per tile

    wire        ld_plane1 = ioctl_addr[13];
    wire [12:0] ld_tile   = ioctl_addr[12:0];
    wire [13:0] ld_map    = ioctl_addr[13:0];

    //------------------------------------------------------------------------
    // Fetch two display pixels ahead. The wrap logic mirrors segag80_video.sv
    // so the leading pixels of each line are fetched during the prior hblank.
    //------------------------------------------------------------------------
    wire [9:0] fetch_h_raw  = {1'b0, h_cnt} + 10'd2;
    wire       fetch_h_wrap = (fetch_h_raw >= 10'd328);
    wire [8:0] fetch_h      = fetch_h_wrap ? (fetch_h_raw[8:0] - 9'd328) : fetch_h_raw[8:0];
    wire [8:0] fetch_v_raw  = fetch_h_wrap ? (v_cnt + 9'd1) : v_cnt;
    wire [8:0] fetch_v      = (fetch_v_raw >= 9'd262) ? 9'd0 : fetch_v_raw;

    // MAME: effx = (x + scrollx) ^ flipmask, then & (pixmap_width - 1).
    wire [9:0] flipmask = {10{bg_flip}};
    wire [9:0] effx     = ({1'b0, fetch_h} + bg_scrollx) ^ flipmask;
    wire [9:0] effy     = ({1'b0, fetch_v} + bg_scrolly) ^ flipmask;

    wire [13:0] map_rd_addr = {effy[9:3], effx[9:3]};

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
    wire [12:0] p1_rd_addr = {bg_char_bank[3:2], code_s1, row_s1};

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
