//============================================================================
//
//  Sega G-80 raster background board — Space Odyssey variant
//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_v.cpp (spaceod_get_tile_info, spaceod_scan_rows,
//  spaceod_back_port_r/w, draw_background_spaceod, spaceod_bg_init_palette)
//  and segag80r.cpp (gfx_spaceod).
//
//  Unlike the Pig Newton board this one has:
//    - 6 bitplanes (gfx1 = 6 x 4 KB, one ROM per plane), 512 tiles
//    - two tilemap geometries: 128x32 (horizontal) and 32x128 (vertical),
//      both addressed as four 32x32 sections by spaceod_scan_rows
//    - a FIXED palette: the 6-bit pixel is itself RGB222, so there is no
//      palette RAM on this path at all
//    - collision detection fed back to the CPU at $08-$0F
//
//  The H/V counters are NOT free-running: the CPU clocks them one step per
//  write to port 2, direction from bg_control[0], axis from bg_control[1].
//  They are uint16_t in MAME even though the flip XOR is only 8 bits wide.
//
//============================================================================

module segag80_spaceod_bg (
    input              clk,
    input              reset,
    input              ce_pix,
    input        [8:0] h_cnt,
    input        [8:0] v_cnt,

    // Background board ports $08-$0F
    input              port_wr,        // one-cycle strobe
    input        [2:0] port_addr,
    input        [7:0] port_din,
    output       [7:0] port_dout,      // MAME: 0xfe | bg_detect

    // Collision detect, computed in segag80_video where the fg palette lives
    input              detect_set,

    // ROM loading
    input       [24:0] ioctl_addr,
    input        [7:0] ioctl_data,
    input              ioctl_wr,
    input              sel_tiles,      // gfx1 — 24 KB, six 4 KB planes
    input              sel_map,        // gfx2 — 16 KB tilemap

    // Pixel out
    output       [5:0] bg_color6,      // (pixel | fixed_color) & 0x3f
    output       [5:0] bg_raw6,        // raw pixel, for the collision test
    output             bg_show         // MAME displays when m_bg_enable == 0
);

    //------------------------------------------------------------------------
    // Board registers — spaceod_back_port_w
    //------------------------------------------------------------------------
    reg  [7:0] bg_control;   // d0 dir, d1 h/v, d2 char bank, d7:d6 ROM select
    reg [15:0] hcounter, vcounter;
    reg  [5:0] fixed_color;
    reg        bg_disable;   // m_bg_enable: 1 disables the layer
    reg        bg_detect;

    assign port_dout = {7'h7F, bg_detect};   // 0xFE | detect
    assign bg_show   = ~bg_disable;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            bg_control  <= 8'd0;
            hcounter    <= 16'd0;
            vcounter    <= 16'd0;
            fixed_color <= 6'd0;
            bg_disable  <= 1'b0;
            bg_detect   <= 1'b0;
        end else begin
            // A port-3 write in the same cycle must win, so this comes first.
            if (detect_set) bg_detect <= 1'b1;

            if (port_wr) begin
                case (port_addr)
                    3'd0: bg_control <= port_din;
                    3'd1: begin hcounter <= 16'd0; vcounter <= 16'd0; end
                    3'd2: if (!bg_control[1])
                              hcounter <= bg_control[0] ? hcounter - 16'd1
                                                        : hcounter + 16'd1;
                          else
                              vcounter <= bg_control[0] ? vcounter - 16'd1
                                                        : vcounter + 16'd1;
                    3'd3: bg_detect   <= 1'b0;
                    3'd4: bg_disable  <= port_din[0];
                    3'd5: fixed_color <= port_din[5:0];
                    default: ;   // ports 6/7 latch to connectors only
                endcase
            end
        end
    end

    //------------------------------------------------------------------------
    // ROMs
    //------------------------------------------------------------------------
    // Six DISCRETE arrays, deliberately not reg [7:0] rom_pl [0:5][0:4095]:
    // a variable index on the outer dimension defeats M10K inference and
    // Quartus builds the whole 192 Kbit out of logic (~100k extra LUTs).
    (* ramstyle = "M10K" *) reg [7:0] rom_pl0 [0:4095];
    (* ramstyle = "M10K" *) reg [7:0] rom_pl1 [0:4095];
    (* ramstyle = "M10K" *) reg [7:0] rom_pl2 [0:4095];
    (* ramstyle = "M10K" *) reg [7:0] rom_pl3 [0:4095];
    (* ramstyle = "M10K" *) reg [7:0] rom_pl4 [0:4095];
    (* ramstyle = "M10K" *) reg [7:0] rom_pl5 [0:4095];
    (* ramstyle = "M10K" *) reg [7:0] rom_map [0:16383];

    wire [2:0]  ld_plane = ioctl_addr[14:12];
    wire [11:0] ld_tile  = ioctl_addr[11:0];
    wire [13:0] ld_map   = ioctl_addr[13:0];

    wire ld_pl = ioctl_wr & sel_tiles;
    wire ld_p0 = ld_pl & (ld_plane == 3'd0);
    wire ld_p1 = ld_pl & (ld_plane == 3'd1);
    wire ld_p2 = ld_pl & (ld_plane == 3'd2);
    wire ld_p3 = ld_pl & (ld_plane == 3'd3);
    wire ld_p4 = ld_pl & (ld_plane == 3'd4);
    wire ld_p5 = ld_pl & (ld_plane == 3'd5);

    //------------------------------------------------------------------------
    // Effective coordinates. Fetch two display pixels ahead; the wrap logic
    // matches segag80_video.sv so the leading pixels of a line are fetched
    // during the prior hblank.
    //------------------------------------------------------------------------
    wire [9:0] fetch_h_raw  = {1'b0, h_cnt} + 10'd2;
    wire       fetch_h_wrap = (fetch_h_raw >= 10'd328);
    wire [8:0] fetch_h      = fetch_h_wrap ? (fetch_h_raw[8:0] - 9'd328) : fetch_h_raw[8:0];
    wire [8:0] fetch_v_raw  = fetch_h_wrap ? (v_cnt + 9'd1) : v_cnt;
    wire [8:0] fetch_v      = (fetch_v_raw >= 9'd262) ? 9'd0 : fetch_v_raw;

    wire        vmode    = bg_control[1];
    wire [15:0] flipmask = bg_control[0] ? 16'h00FF : 16'h0000;
    wire [15:0] xoffset  = vmode ? 16'h0010 : 16'h0000;
    wire  [9:0] xmask    = vmode ? 10'h0FF : 10'h3FF;
    wire  [9:0] ymask    = vmode ? 10'h3FF : 10'h0FF;

    // MAME: effy = (y + vcounter + 22) ^ flipmask.  The +22 is the offset
    // between the main board's V counter and this board's, which starts at
    // VSYNC (line 240) rather than line 0.
    wire [15:0] effy_r = (({7'd0, fetch_v} + vcounter) + 16'd22) ^ flipmask;
    // MAME: effx = ((x + hcounter) ^ flipmask) + xoffset — xoffset is added
    // AFTER the flip, not before.
    wire [15:0] effx_r = (({7'd0, fetch_h} + hcounter) ^ flipmask) + xoffset;

    wire [9:0] effy = effy_r[9:0] & ymask;
    wire [9:0] effx = effx_r[9:0] & xmask;

    // spaceod_scan_rows: (row&31)*32 + (col&31) + (row>>5)*1024 + (col>>5)*1024
    wire [6:0]  trow = effy[9:3];
    wire [6:0]  tcol = effx[9:3];
    wire [11:0] tile_index = {2'd0, trow[4:0], tcol[4:0]}
                           + {trow[6:5], 10'd0}
                           + {tcol[6:5], 10'd0};

    wire [13:0] map_rd_addr = {bg_control[7:6], tile_index};

    //------------------------------------------------------------------------
    // Two-stage fetch: tilemap byte, then all six planes in parallel.
    //------------------------------------------------------------------------
    reg [7:0] map_dout;
    reg [7:0] p0_dout, p1_dout, p2_dout, p3_dout, p4_dout, p5_dout;
    reg [7:0] code_s1;
    reg [2:0] px_s1, row_s1;
    reg [2:0] px_s2;
    reg [7:0] p0_s2, p1_s2, p2_s2, p3_s2, p4_s2, p5_s2;

    wire [8:0]  tile_num = {bg_control[2], code_s1};
    wire [11:0] pl_addr  = {tile_num, row_s1};

    always @(posedge clk) begin
        if (ioctl_wr & sel_map) rom_map[ld_map] <= ioctl_data;
        if (ld_p0) rom_pl0[ld_tile] <= ioctl_data;
        if (ld_p1) rom_pl1[ld_tile] <= ioctl_data;
        if (ld_p2) rom_pl2[ld_tile] <= ioctl_data;
        if (ld_p3) rom_pl3[ld_tile] <= ioctl_data;
        if (ld_p4) rom_pl4[ld_tile] <= ioctl_data;
        if (ld_p5) rom_pl5[ld_tile] <= ioctl_data;

        map_dout <= rom_map[map_rd_addr];
        p0_dout  <= rom_pl0[pl_addr];
        p1_dout  <= rom_pl1[pl_addr];
        p2_dout  <= rom_pl2[pl_addr];
        p3_dout  <= rom_pl3[pl_addr];
        p4_dout  <= rom_pl4[pl_addr];
        p5_dout  <= rom_pl5[pl_addr];

        if (ce_pix) begin
            code_s1 <= map_dout;
            px_s1   <= effx[2:0];
            row_s1  <= effy[2:0];

            px_s2 <= px_s1;
            p0_s2 <= p0_dout;
            p1_s2 <= p1_dout;
            p2_s2 <= p2_dout;
            p3_s2 <= p3_dout;
            p4_s2 <= p4_dout;
            p5_s2 <= p5_dout;
        end
    end

    // Leftmost pixel is the byte MSB. MAME's gfx_8x8x6_planar lists
    // planeoffset MSB-first, so RGN_FRAC(5,6) (ROM index 5) is pixel bit 5.
    wire [2:0] bit_sel = ~px_s2;
    wire [5:0] pixel6  = {p5_s2[bit_sel], p4_s2[bit_sel], p3_s2[bit_sel],
                          p2_s2[bit_sel], p1_s2[bit_sel], p0_s2[bit_sel]};

    assign bg_raw6   = pixel6;
    assign bg_color6 = pixel6 | fixed_color;

endmodule
