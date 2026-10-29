//  Based on MAME segag80r_v.cpp (Aaron Giles, BSD-3-Clause)

module segag80_video (
    output ram_pool_pkg::pram_i_t vram_pr_i,
    input  ram_pool_pkg::pram_o_t vram_pr_o,
    input              clk,
    input              reset,

    input       [12:0] cpu_addr,
    input        [7:0] cpu_din,
    input              cpu_wr,
    input              video_control_1, // video_control[1]: palette enable
    input              video_control_6, // video_control[6]: Monster Bash bg palette
    input              video_flip,

    input              bg_board,
    input              mb_board,
    input              sm_board,
    input              bg_enable,
    input        [3:0] bg_color,
    input        [1:0] bg_pix,

    input              so_board,
    input              so_show,
    input        [5:0] so_color6,
    input        [5:0] so_raw6,
    output             so_detect_set,

    input              ce_pix,
    input        [8:0] h_cnt,
    input        [8:0] v_cnt,

    output       [7:0] r_out,
    output       [7:0] g_out,
    output       [7:0] b_out,

    output       [7:0] cpu_dout
);

    wire pal_write    = cpu_wr & cpu_addr[12] & video_control_1;
    wire bg_pal_hit   = sm_board ? (cpu_addr[12:6] == 7'b1000000)
                                 : (cpu_addr[12:6] == 7'b1000001);
    wire bg_pal_write = mb_board ? (cpu_wr & bg_pal_hit & video_control_6)
                                 : (pal_write & bg_board & bg_pal_hit);
    wire pal_we       = pal_write | bg_pal_write;
    wire vram_write   = cpu_wr & ~pal_write;

    reg [12:0] scan_addr;
    wire [7:0] vram_cpu_rd  = vram_pr_o.a_q;
    wire [7:0] vram_scan_rd = vram_pr_o.b_q;
    assign vram_pr_i = '{a_addr: {2'd0, cpu_addr}, a_d: cpu_din, a_we: vram_write,
                         b_addr: {2'd0, scan_addr}, b_d: 8'd0, b_we: 1'b0};

    assign cpu_dout = vram_cpu_rd;

    reg [7:0] pal [0:127];   // POOL-EXCEPTION: 128 bytes, read combinationally (pal_entry)
    wire [6:0] pal_wr_addr = {bg_pal_write, cpu_addr[5:0]};

    always @(posedge clk) begin
        if (pal_we)
            pal[pal_wr_addr] <= cpu_din;
    end

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

    function [7:0] dac2_so;
        input [1:0] v;
        case (v)
            2'd0: dac2_so = 8'd0;
            2'd1: dac2_so = 8'd102;
            2'd2: dac2_so = 8'd153;
            2'd3: dac2_so = 8'd255;
        endcase
    endfunction

    wire [4:0] char_x  = h_cnt[7:3];
    wire [4:0] char_y  = v_cnt[7:3];
    wire [2:0] pix_col = h_cnt[2:0];
    wire [2:0] pix_row = v_cnt[2:0];

    wire [4:0] flipmask5   = {5{video_flip}};
    wire [2:0] flipmask3   = {3{video_flip}};

    wire [2:0] eff_pix_col = pix_col ^ flipmask3;

    wire [9:0] fetch_h_raw  = {1'b0, h_cnt} + 10'd8;
    wire       fetch_h_wrap = (fetch_h_raw >= 10'd328);
    wire [8:0] fetch_h      = fetch_h_wrap ? (fetch_h_raw[8:0] - 9'd328) : fetch_h_raw[8:0];
    wire [8:0] fetch_v_raw  = fetch_h_wrap ? (v_cnt + 9'd1) : v_cnt;
    wire [8:0] fetch_v      = (fetch_v_raw >= 9'd262) ? 9'd0 : fetch_v_raw;

    wire [4:0] fetch_char_x = fetch_h[7:3];
    wire [4:0] fetch_char_y = fetch_v[7:3];

    wire [4:0] safe_fetch_char_y = (fetch_char_y > 5'd27) ? 5'd27 : fetch_char_y;

    wire [4:0] eff_fetch_char_y = video_flip ? (5'd27 - safe_fetch_char_y) : safe_fetch_char_y;
    wire [4:0] eff_fetch_char_x = fetch_char_x ^ flipmask5;
    wire [2:0] eff_fetch_pix_row = fetch_v[2:0] ^ flipmask3;

    reg  [7:0]  tile_code_next;
    reg  [7:0]  plane0_next;
    reg  [7:0]  plane1_next;
    wire [12:0] addr_tc_next = {3'b000, eff_fetch_char_y, eff_fetch_char_x};
    wire [12:0] addr_p0_next = {2'b01,  tile_code_next,    eff_fetch_pix_row};
    wire [12:0] addr_p1_next = {2'b11,  tile_code_next,    eff_fetch_pix_row};

    always @* begin
        case (pix_col)
            3'd5:    scan_addr = addr_tc_next;
            3'd6:    scan_addr = addr_p0_next;
            3'd7:    scan_addr = addr_p1_next;
            default: scan_addr = 13'd0;
        endcase
    end

    reg [2:0] pix_col_d;
    always @(posedge clk) begin
        pix_col_d <= pix_col;
        if (pix_col_d == 3'd5) tile_code_next <= vram_scan_rd;
        if (pix_col_d == 3'd6) plane0_next    <= vram_scan_rd;
        if (pix_col_d == 3'd7) plane1_next    <= vram_scan_rd;
    end

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

    wire [2:0] bit_sel    = ~eff_pix_col;
    wire       plane0_bit = plane0_cur[bit_sel];
    wire       plane1_bit = plane1_cur[bit_sel];
    wire [1:0] pixel_2bit = {plane1_bit, plane0_bit};

    wire       fg_clear   = bg_board & (pixel_2bit == 2'b00);
    wire [6:0] bg_index   = bg_enable ? {1'b1, bg_color, bg_pix} : 7'd0;
    wire [6:0] pal_index  = fg_clear ? bg_index
                                     : {1'b0, tile_code_cur[7:4], pixel_2bit};
    wire [7:0] pal_entry  = pal[pal_index];

    wire active = (h_cnt < 9'd256) && (v_cnt < 9'd224);

    wire fg_black   = (pal_entry == 8'd0);
    wire so_visible = so_board & fg_black & so_show;

    assign so_detect_set = active & so_board & (so_raw6 != 6'd0) & ~fg_black
                         & (tile_code_cur[7:4] == 4'd1);

    assign r_out = !active    ? 8'd0 :
                   so_visible ? dac2_so(so_color6[5:4]) : dac3(pal_entry[2:0]);
    assign g_out = !active    ? 8'd0 :
                   so_visible ? dac2_so(so_color6[3:2]) : dac3(pal_entry[5:3]);
    assign b_out = !active    ? 8'd0 :
                   so_visible ? dac2_so(so_color6[1:0]) : dac2(pal_entry[7:6]);

endmodule