//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_v.cpp, segag80r.cpp (Aaron Giles, BSD-3-Clause)

module segag80_bg (
    input              clk,
    input              ce_pix,
    input        [8:0] h_cnt,
    input        [8:0] v_cnt,

    input        [9:0] bg_scrollx,
    input       [10:0] bg_scrolly,
    input        [3:0] bg_char_bank,
    input              bg_flip,         // video_control[3]
    input              mb_mode,         // 1 = Monster Bash page scroll
    input              sm_mode,         // 1 = Sindbad page scroll, 128-wide, unexpanded gfx

    output      [14:0] rom3_a,
    input        [7:0] rom3_d,
    output      [12:0] rom4_a,
    input        [7:0] rom4_d,
    output      [12:0] rom5_a,
    input        [7:0] rom5_d,

    output       [3:0] bg_color,
    output       [1:0] bg_pix
);

    reg [7:0] rom_p0  [0:8191];
    reg [7:0] rom_p1  [0:8191];

    wire [9:0] fetch_h_raw  = {1'b0, h_cnt} + 10'd2;
    wire       fetch_h_wrap = (fetch_h_raw >= 10'd328);
    wire [8:0] fetch_h      = fetch_h_wrap ? (fetch_h_raw[8:0] - 9'd328) : fetch_h_raw[8:0];
    wire [8:0] fetch_v_raw  = fetch_h_wrap ? (v_cnt + 9'd1) : v_cnt;
    wire [8:0] fetch_v      = (fetch_v_raw >= 9'd262) ? 9'd0 : fetch_v_raw;

    wire [9:0] flipmask = {10{bg_flip}};
    wire [9:0] effx_fs  = ({1'b0, fetch_h} + bg_scrollx) ^ flipmask;
    wire [9:0] effy_fs  = ({1'b0, fetch_v} + bg_scrolly[9:0]) ^ flipmask;

    wire [7:0]  flipmask8 = {8{bg_flip}};
    wire [7:0]  ps_inner  = (fetch_v[7:0] ^ flipmask8) + (bg_flip ? 8'hE0 : 8'h00);
    wire [10:0] effy_ps   = bg_scrolly + {3'd0, ps_inner};
    wire [7:0]  effx_ps   = fetch_h[7:0] ^ flipmask8;

    wire        page_mode = mb_mode | sm_mode;
    wire [9:0]  effx_pg   = bg_scrollx + {2'b00, effx_ps};

    wire [10:0] effy = page_mode ? effy_ps : {1'b0, effy_fs};
    wire [9:0]  effx = page_mode ? effx_pg : effx_fs;

    wire [14:0] map_rd_addr = mb_mode ? {2'b00, effy[10:3], effx[7:3]}
                            : sm_mode ? {      effy[10:3], effx[9:3]}
                                      : {2'b00, effy[9:3],  effx[9:3]};

    wire [7:0] map_dout = rom3_d, p0_dout = rom4_d, p1_dout = rom5_d;
    reg [7:0] code_s1;
    reg [2:0] px_s1, row_s1;
    reg [7:0] code_s2, p0_s2, p1_s2;
    reg [2:0] px_s2;

    wire [12:0] p0_rd_addr = {bg_char_bank[1:0], code_s1, row_s1};
    wire [12:0] p1_rd_addr = sm_mode ? {bg_char_bank[1:0], code_s1, row_s1}
                                     : {bg_char_bank[3:2], code_s1, row_s1};
    assign rom3_a = map_rd_addr;
    assign rom4_a = p0_rd_addr;
    assign rom5_a = p1_rd_addr;

    always @(posedge clk) begin
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

    wire [2:0] bit_sel = ~px_s2;

    assign bg_color = code_s2[7:4];
    assign bg_pix   = {p1_s2[bit_sel], p0_s2[bit_sel]};

endmodule
