//  Copyright (C) 2026 Rodimus
//  Based on MAME segag80r_v.cpp, segag80r.cpp (Aaron Giles, BSD-3-Clause)

module segag80_spaceod_bg (
    input              clk,
    input              reset,
    input              ce_pix,
    input        [8:0] h_cnt,
    input        [8:0] v_cnt,

    input              port_wr,
    input        [2:0] port_addr,
    input        [7:0] port_din,
    output       [7:0] port_dout,

    input              detect_set,

    output      [13:0] rom6_a,
    input        [7:0] rom6_d,
    output      [11:0] rom7_a,
    input   [5:0][7:0] rom7_d,

    output       [5:0] bg_color6,
    output       [5:0] bg_raw6,
    output             bg_show
);

    reg  [7:0] bg_control;
    reg [15:0] hcounter, vcounter;
    reg  [5:0] fixed_color;
    reg        bg_disable;
    reg        bg_detect;

    assign port_dout = {7'h7F, bg_detect};
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
                    default: ;
                endcase
            end
        end
    end

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

    wire [15:0] effy_r = (({7'd0, fetch_v} + vcounter) + 16'd22) ^ flipmask;
    wire [15:0] effx_r = (({7'd0, fetch_h} + hcounter) ^ flipmask) + xoffset;

    wire [9:0] effy = effy_r[9:0] & ymask;
    wire [9:0] effx = effx_r[9:0] & xmask;

    wire [6:0]  trow = effy[9:3];
    wire [6:0]  tcol = effx[9:3];
    wire [11:0] tile_index = {2'd0, trow[4:0], tcol[4:0]}
                           + {trow[6:5], 10'd0}
                           + {tcol[6:5], 10'd0};

    wire [13:0] map_rd_addr = {bg_control[7:6], tile_index};

    wire [7:0] map_dout = rom6_d;
    wire [7:0] p0_dout = rom7_d[0], p1_dout = rom7_d[1], p2_dout = rom7_d[2], p3_dout = rom7_d[3], p4_dout = rom7_d[4],
               p5_dout = rom7_d[5];
    reg [7:0] code_s1;
    reg [2:0] px_s1, row_s1;
    reg [2:0] px_s2;
    reg [7:0] p0_s2, p1_s2, p2_s2, p3_s2, p4_s2, p5_s2;

    wire [8:0]  tile_num = {bg_control[2], code_s1};
    wire [11:0] pl_addr  = {tile_num, row_s1};
    assign rom6_a = map_rd_addr;
    assign rom7_a = pl_addr;

    always @(posedge clk) begin

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

    wire [2:0] bit_sel = ~px_s2;
    wire [5:0] pixel6  = {p5_s2[bit_sel], p4_s2[bit_sel], p3_s2[bit_sel],
                          p2_s2[bit_sel], p1_s2[bit_sel], p0_s2[bit_sel]};

    assign bg_raw6   = pixel6;
    assign bg_color6 = pixel6 | fixed_color;

endmodule
