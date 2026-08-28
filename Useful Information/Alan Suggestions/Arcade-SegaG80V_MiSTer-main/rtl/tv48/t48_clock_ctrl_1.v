// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_clock_ctrl_1
  (input  clk_i,
   input  xtal_i,
   input  xtal_en_i,
   input  res_i,
   input  en_clk_i,
   input  multi_cycle_i,
   input  assert_psen_i,
   input  assert_prog_i,
   input  assert_rd_i,
   input  assert_wr_i,
   output xtal3_o,
   output t0_o,
   output [2:0] mstate_o,
   output second_cycle_o,
   output ale_o,
   output psen_o,
   output prog_o,
   output rd_o,
   output wr_o);
  wire [1:0] xtal_q;
  wire xtal2_s;
  wire xtal3_s;
  wire x2_s;
  wire x3_s;
  wire t0_q;
  wire [2:0] mstate_q;
  wire ale_q;
  wire psen_q;
  wire prog_q;
  wire rd_q;
  wire wr_q;
  wire second_cycle_q;
  wire multi_cycle_q;
  wire n758_o;
  wire n761_o;
  wire [1:0] n763_o;
  wire [1:0] n765_o;
  wire n768_o;
  wire n786_o;
  wire n787_o;
  wire n788_o;
  wire n792_o;
  wire n793_o;
  wire n794_o;
  wire n811_o;
  wire n819_o;
  wire n821_o;
  wire n823_o;
  wire n824_o;
  wire n826_o;
  wire n828_o;
  wire n829_o;
  wire n830_o;
  wire n832_o;
  wire n834_o;
  wire n836_o;
  wire n838_o;
  wire n840_o;
  wire n842_o;
  wire n844_o;
  wire n846_o;
  wire n848_o;
  wire n850_o;
  wire n851_o;
  wire n852_o;
  wire n853_o;
  wire n854_o;
  wire n855_o;
  wire n857_o;
  wire n859_o;
  wire n861_o;
  wire [4:0] n862_o;
  reg n864_o;
  reg n866_o;
  reg n868_o;
  reg n870_o;
  reg n872_o;
  wire n890_o;
  wire n893_o;
  wire n895_o;
  wire n897_o;
  wire n899_o;
  wire n901_o;
  wire [4:0] n902_o;
  reg [2:0] n909_o;
  wire n918_o;
  wire n921_o;
  wire n923_o;
  wire n924_o;
  wire n926_o;
  wire n927_o;
  wire n929_o;
  wire n930_o;
  wire n931_o;
  wire n933_o;
  wire n935_o;
  wire [1:0] n959_o;
  reg [1:0] n960_q;
  wire n961_o;
  reg n962_q;
  wire [2:0] n963_o;
  reg [2:0] n964_q;
  reg n965_q;
  reg n966_q;
  reg n967_q;
  reg n968_q;
  reg n969_q;
  wire n970_o;
  reg n971_q;
  wire n972_o;
  reg n973_q;
  assign xtal3_o = xtal3_s;
  assign t0_o = t0_q;
  assign mstate_o = mstate_q;
  assign second_cycle_o = second_cycle_q;
  assign ale_o = ale_q;
  assign psen_o = psen_q;
  assign prog_o = prog_q;
  assign rd_o = rd_q;
  assign wr_o = wr_q;
  /* clock_ctrl.vhd:90:10  */
  assign xtal_q = n960_q; // (signal)
  /* clock_ctrl.vhd:92:10  */
  assign xtal2_s = n811_o; // (signal)
  /* clock_ctrl.vhd:93:10  */
  assign xtal3_s = n819_o; // (signal)
  /* clock_ctrl.vhd:95:10  */
  assign x2_s = n788_o; // (signal)
  /* clock_ctrl.vhd:96:10  */
  assign x3_s = n794_o; // (signal)
  /* clock_ctrl.vhd:98:10  */
  assign t0_q = n962_q; // (signal)
  /* clock_ctrl.vhd:102:10  */
  assign mstate_q = n964_q; // (signal)
  /* clock_ctrl.vhd:104:10  */
  assign ale_q = n965_q; // (signal)
  /* clock_ctrl.vhd:105:10  */
  assign psen_q = n966_q; // (signal)
  /* clock_ctrl.vhd:106:10  */
  assign prog_q = n967_q; // (signal)
  /* clock_ctrl.vhd:107:10  */
  assign rd_q = n968_q; // (signal)
  /* clock_ctrl.vhd:108:10  */
  assign wr_q = n969_q; // (signal)
  /* clock_ctrl.vhd:112:10  */
  assign second_cycle_q = n971_q; // (signal)
  /* clock_ctrl.vhd:113:10  */
  assign multi_cycle_q = n973_q; // (signal)
  /* clock_ctrl.vhd:137:16  */
  assign n758_o = ~res_i;
  /* clock_ctrl.vhd:143:21  */
  assign n761_o = $unsigned(xtal_q) < $unsigned(2'b10);
  /* clock_ctrl.vhd:144:30  */
  assign n763_o = xtal_q + 2'b01;
  /* clock_ctrl.vhd:143:11  */
  assign n765_o = n761_o ? n763_o : 2'b00;
  /* clock_ctrl.vhd:149:11  */
  assign n768_o = xtal3_s ? 1'b1 : 1'b0;
  /* clock_ctrl.vhd:164:25  */
  assign n786_o = xtal_q == 2'b01;
  /* clock_ctrl.vhd:164:29  */
  assign n787_o = xtal_en_i & n786_o;
  /* clock_ctrl.vhd:164:13  */
  assign n788_o = n787_o ? 1'b1 : 1'b0;
  /* clock_ctrl.vhd:167:25  */
  assign n792_o = xtal_q == 2'b10;
  /* clock_ctrl.vhd:167:29  */
  assign n793_o = xtal_en_i & n792_o;
  /* clock_ctrl.vhd:167:13  */
  assign n794_o = n793_o ? 1'b1 : 1'b0;
  /* t48_pack-p.vhd:75:5  */
  assign n811_o = x2_s ? 1'b1 : 1'b0;
  /* t48_pack-p.vhd:75:5  */
  assign n819_o = x3_s ? 1'b1 : 1'b0;
  /* clock_ctrl.vhd:206:14  */
  assign n821_o = ~res_i;
  /* clock_ctrl.vhd:218:26  */
  assign n823_o = ~second_cycle_q;
  /* clock_ctrl.vhd:218:22  */
  assign n824_o = n823_o & xtal2_s;
  /* clock_ctrl.vhd:218:11  */
  assign n826_o = n829_o ? 1'b1 : rd_q;
  /* clock_ctrl.vhd:218:11  */
  assign n828_o = n830_o ? 1'b1 : wr_q;
  /* clock_ctrl.vhd:218:11  */
  assign n829_o = n824_o & assert_rd_i;
  /* clock_ctrl.vhd:218:11  */
  assign n830_o = n824_o & assert_wr_i;
  /* clock_ctrl.vhd:216:9  */
  assign n832_o = mstate_q == 3'b100;
  /* clock_ctrl.vhd:228:11  */
  assign n834_o = xtal3_s ? 1'b0 : psen_q;
  /* clock_ctrl.vhd:227:9  */
  assign n836_o = mstate_q == 3'b000;
  /* clock_ctrl.vhd:233:11  */
  assign n838_o = xtal3_s ? 1'b0 : prog_q;
  /* clock_ctrl.vhd:233:11  */
  assign n840_o = xtal3_s ? 1'b0 : rd_q;
  /* clock_ctrl.vhd:233:11  */
  assign n842_o = xtal3_s ? 1'b0 : wr_q;
  /* clock_ctrl.vhd:232:9  */
  assign n844_o = mstate_q == 3'b001;
  /* clock_ctrl.vhd:243:11  */
  assign n846_o = xtal3_s ? 1'b1 : ale_q;
  /* clock_ctrl.vhd:241:9  */
  assign n848_o = mstate_q == 3'b010;
  /* clock_ctrl.vhd:248:11  */
  assign n850_o = n851_o ? 1'b1 : psen_q;
  /* clock_ctrl.vhd:248:11  */
  assign n851_o = xtal3_s & assert_psen_i;
  /* clock_ctrl.vhd:257:22  */
  assign n852_o = multi_cycle_q & xtal3_s;
  /* clock_ctrl.vhd:258:32  */
  assign n853_o = ~second_cycle_q;
  /* clock_ctrl.vhd:258:28  */
  assign n854_o = n853_o & n852_o;
  /* clock_ctrl.vhd:258:51  */
  assign n855_o = assert_prog_i & n854_o;
  /* clock_ctrl.vhd:257:11  */
  assign n857_o = n855_o ? 1'b1 : prog_q;
  /* clock_ctrl.vhd:263:11  */
  assign n859_o = xtal2_s ? 1'b0 : ale_q;
  /* clock_ctrl.vhd:247:9  */
  assign n861_o = mstate_q == 3'b011;
  assign n862_o = {n861_o, n848_o, n844_o, n836_o, n832_o};

  always @(posedge clk_i)
  begin
    //if(en_clk_i && xtal_en_i && second_cycle_q) $display("multi_cycle_q: %b second_cycle_q: %b", multi_cycle_q, second_cycle_q);
  end

  /* clock_ctrl.vhd:215:7  */
  always @*
    case (n862_o)
      5'b10000: n864_o = n859_o;
      5'b01000: n864_o = n846_o;
      5'b00100: n864_o = ale_q;
      5'b00010: n864_o = ale_q;
      5'b00001: n864_o = ale_q;
      default: n864_o = 1'b0;
    endcase
  /* clock_ctrl.vhd:215:7  */
  always @*
    case (n862_o)
      5'b10000: n866_o = n850_o;
      5'b01000: n866_o = psen_q;
      5'b00100: n866_o = psen_q;
      5'b00010: n866_o = n834_o;
      5'b00001: n866_o = psen_q;
      default: n866_o = 1'b0;
    endcase
  /* clock_ctrl.vhd:215:7  */
  always @*
    case (n862_o)
      5'b10000: n868_o = n857_o;
      5'b01000: n868_o = prog_q;
      5'b00100: n868_o = n838_o;
      5'b00010: n868_o = prog_q;
      5'b00001: n868_o = prog_q;
      default: n868_o = 1'b0;
    endcase
  /* clock_ctrl.vhd:215:7  */
  always @*
    case (n862_o)
      5'b10000: n870_o = rd_q;
      5'b01000: n870_o = rd_q;
      5'b00100: n870_o = n840_o;
      5'b00010: n870_o = rd_q;
      5'b00001: n870_o = n826_o;
      default: n870_o = 1'b0;
    endcase
  /* clock_ctrl.vhd:215:7  */
  always @*
    case (n862_o)
      5'b10000: n872_o = wr_q;
      5'b01000: n872_o = wr_q;
      5'b00100: n872_o = n842_o;
      5'b00010: n872_o = wr_q;
      5'b00001: n872_o = n828_o;
      default: n872_o = 1'b0;
    endcase
  /* clock_ctrl.vhd:292:14  */
  assign n890_o = ~res_i;
  /* clock_ctrl.vhd:303:11  */
  assign n893_o = mstate_q == 3'b100;
  /* clock_ctrl.vhd:306:11  */
  assign n895_o = mstate_q == 3'b000;
  /* clock_ctrl.vhd:309:11  */
  assign n897_o = mstate_q == 3'b001;
  /* clock_ctrl.vhd:312:11  */
  assign n899_o = mstate_q == 3'b010;
  /* clock_ctrl.vhd:315:11  */
  assign n901_o = mstate_q == 3'b011;
  assign n902_o = {n901_o, n899_o, n897_o, n895_o, n893_o};
  /* clock_ctrl.vhd:302:9  */
  always @*
    case (n902_o)
      5'b10000: n909_o = 3'b100;
      5'b01000: n909_o = 3'b011;
      5'b00100: n909_o = 3'b010;
      5'b00010: n909_o = 3'b001;
      5'b00001: n909_o = 3'b000;
      default: n909_o = 3'b000;
    endcase
  /* clock_ctrl.vhd:349:14  */
  assign n918_o = ~res_i;
  /* clock_ctrl.vhd:356:30  */
  assign n921_o = mstate_q == 3'b001;
  /* clock_ctrl.vhd:357:30  */
  assign n923_o = mstate_q == 3'b100;
  /* clock_ctrl.vhd:360:21  */
  assign n924_o = multi_cycle_i & n921_o;
  /* clock_ctrl.vhd:360:9  */
  assign n926_o = n924_o ? 1'b1 : multi_cycle_q;
  /* clock_ctrl.vhd:365:26  */
  assign n927_o = n923_o & multi_cycle_q;
  /* clock_ctrl.vhd:365:9  */
  assign n929_o = n927_o ? 1'b1 : second_cycle_q;
  /* clock_ctrl.vhd:371:27  */
  assign n930_o = second_cycle_q & multi_cycle_q;
  /* clock_ctrl.vhd:370:21  */
  assign n931_o = n930_o & n923_o;
  /* clock_ctrl.vhd:370:9  */
  assign n933_o = n931_o ? 1'b0 : n929_o;
  /* clock_ctrl.vhd:370:9  */
  assign n935_o = n931_o ? 1'b0 : n926_o;
  /* clock_ctrl.vhd:141:7  */
  assign n959_o = xtal_en_i ? n765_o : xtal_q;
  /* clock_ctrl.vhd:141:7  */
  always @(posedge xtal_i or posedge n758_o)
    if (n758_o)
      n960_q <= 2'b00;
    else
      n960_q <= n959_o;
  /* clock_ctrl.vhd:141:7  */
  assign n961_o = xtal_en_i ? n768_o : t0_q;
  /* clock_ctrl.vhd:141:7  */
  always @(posedge xtal_i or posedge n758_o)
    if (n758_o)
      n962_q <= 1'b0;
    else
      n962_q <= n961_o;
  /* clock_ctrl.vhd:299:5  */
  assign n963_o = en_clk_i ? n909_o : mstate_q;
  /* clock_ctrl.vhd:299:5  */
  always @(posedge clk_i or posedge n890_o)
    if (n890_o)
      n964_q <= 3'b010;
    else
      n964_q <= n963_o;
  /* clock_ctrl.vhd:213:5  */
  always @(posedge xtal_i or posedge n821_o)
    if (n821_o)
      n965_q <= 1'b0;
    else
      n965_q <= n864_o;
  /* clock_ctrl.vhd:213:5  */
  always @(posedge xtal_i or posedge n821_o)
    if (n821_o)
      n966_q <= 1'b0;
    else
      n966_q <= n866_o;
  /* clock_ctrl.vhd:213:5  */
  always @(posedge xtal_i or posedge n821_o)
    if (n821_o)
      n967_q <= 1'b0;
    else
      n967_q <= n868_o;
  /* clock_ctrl.vhd:213:5  */
  always @(posedge xtal_i or posedge n821_o)
    if (n821_o)
      n968_q <= 1'b0;
    else
      n968_q <= n870_o;
  /* clock_ctrl.vhd:213:5  */
  always @(posedge xtal_i or posedge n821_o)
    if (n821_o)
      n969_q <= 1'b0;
    else
      n969_q <= n872_o;
  /* clock_ctrl.vhd:353:5  */
  assign n970_o = en_clk_i ? n933_o : second_cycle_q;
  /* clock_ctrl.vhd:353:5  */
  always @(posedge clk_i or posedge n918_o)
    if (n918_o)
      n971_q <= 1'b0;
    else
      n971_q <= n970_o;
  /* clock_ctrl.vhd:353:5  */
  assign n972_o = en_clk_i ? n935_o : multi_cycle_q;
  /* clock_ctrl.vhd:353:5  */
  always @(posedge clk_i or posedge n918_o)
    if (n918_o)
      n973_q <= 1'b0;
    else
      n973_q <= n972_o;
endmodule