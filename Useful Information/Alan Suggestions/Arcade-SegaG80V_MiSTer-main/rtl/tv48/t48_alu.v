// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_alu
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  [7:0] data_i,
   input  write_accu_i,
   input  write_shadow_i,
   input  write_temp_reg_i,
   input  read_alu_i,
   input  carry_i,
   input  [3:0] alu_op_i,
   input  use_carry_i,
   input  da_high_i,
   input  accu_low_i,
   input  p06_temp_reg_i,
   input  p60_temp_reg_i,
   output [7:0] data_o,
   output carry_o,
   output aux_carry_o,
   output da_overflow_o);
  wire [7:0] accumulator_q;
  wire [7:0] accu_shadow_q;
  wire [7:0] temp_req_q;
  wire [7:0] in_a_s;
  wire [7:0] in_b_s;
  wire [7:0] data_s;
  wire [8:0] add_result_s;
  wire n489_o;
  wire [3:0] n491_o;
  wire [3:0] n492_o;
  wire [3:0] n493_o;
  wire [3:0] n494_o;
  wire [3:0] n495_o;
  wire [3:0] n496_o;
  wire [7:0] n497_o;
  wire [7:0] n499_o;
  wire [7:0] n500_o;
  wire [7:0] n502_o;
  wire [7:0] n504_o;
  wire n505_o;
  wire [7:0] n519_o;
  wire n521_o;
  wire [7:0] n522_o;
  wire n524_o;
  wire [7:0] n525_o;
  wire n527_o;
  wire [7:0] n528_o;
  wire n529_o;
  wire n531_o;
  wire [7:0] n532_o;
  wire n534_o;
  wire n536_o;
  wire [6:0] n537_o;
  wire n538_o;
  wire n539_o;
  wire n540_o;
  wire n542_o;
  wire [6:0] n543_o;
  wire n544_o;
  wire n545_o;
  wire n546_o;
  wire n548_o;
  wire [3:0] n549_o;
  wire [3:0] n550_o;
  wire n552_o;
  wire [7:0] n553_o;
  wire n555_o;
  wire [7:0] n556_o;
  wire n558_o;
  wire [3:0] n559_o;
  wire [3:0] n560_o;
  wire [7:0] n561_o;
  wire n563_o;
  wire n565_o;
  wire [12:0] n566_o;
  reg n568_o;
  wire n570_o;
  wire n571_o;
  wire n572_o;
  wire n573_o;
  wire n574_o;
  wire n576_o;
  wire n577_o;
  wire n578_o;
  wire n579_o;
  wire n580_o;
  wire n581_o;
  reg n583_o;
  wire [2:0] n584_o;
  wire [2:0] n585_o;
  wire [2:0] n586_o;
  wire [2:0] n587_o;
  wire [2:0] n588_o;
  wire [2:0] n590_o;
  wire [2:0] n591_o;
  wire [2:0] n592_o;
  wire [2:0] n593_o;
  wire [2:0] n594_o;
  wire [2:0] n595_o;
  wire [2:0] n596_o;
  reg [2:0] n598_o;
  wire [2:0] n599_o;
  wire [2:0] n600_o;
  wire [2:0] n601_o;
  wire [2:0] n602_o;
  wire [2:0] n603_o;
  wire [2:0] n605_o;
  wire [2:0] n606_o;
  wire [2:0] n607_o;
  wire [2:0] n608_o;
  wire [2:0] n609_o;
  wire [2:0] n610_o;
  wire [2:0] n611_o;
  reg [2:0] n613_o;
  wire n614_o;
  wire n615_o;
  wire n616_o;
  wire n617_o;
  wire n618_o;
  wire n620_o;
  wire n621_o;
  wire n622_o;
  wire n623_o;
  wire n624_o;
  wire n625_o;
  reg n627_o;
  wire n639_o;
  wire n642_o;
  localparam [8:0] n643_o = 9'b000000000;
  wire [7:0] n644_o;
  wire [8:0] n646_o;
  wire [8:0] n648_o;
  localparam [8:0] n650_o = 9'b000000000;
  wire [7:0] n651_o;
  wire n653_o;
  wire n655_o;
  wire [1:0] n656_o;
  wire n658_o;
  reg n659_o;
  wire [7:0] n661_o;
  reg [7:0] n662_o;
  wire [8:0] n664_o;
  wire [8:0] n665_o;
  wire [8:0] n666_o;
  wire [8:0] n667_o;
  wire n668_o;
  wire n669_o;
  wire [1:0] n670_o;
  wire n671_o;
  wire n674_o;
  wire n676_o;
  wire n678_o;
  wire n679_o;
  wire n680_o;
  wire n681_o;
  wire n684_o;
  wire n686_o;
  wire n688_o;
  wire n689_o;
  wire [1:0] n690_o;
  reg n692_o;
  wire [3:0] n699_o;
  wire [3:0] n700_o;
  wire [3:0] n701_o;
  wire n709_o;
  wire n711_o;
  wire n712_o;
  wire n714_o;
  wire n715_o;
  wire n717_o;
  wire n718_o;
  wire n720_o;
  wire n721_o;
  wire n723_o;
  wire n724_o;
  reg n727_o;
  wire [7:0] n730_o;
  wire [7:0] n732_o;
  reg [7:0] n733_q;
  wire [7:0] n734_o;
  reg [7:0] n735_q;
  wire [7:0] n736_o;
  reg [7:0] n737_q;
  wire [7:0] n738_o;
  assign data_o = n730_o;
  assign carry_o = n568_o;
  assign aux_carry_o = n692_o;
  assign da_overflow_o = n727_o;
  /* alu.vhd:99:10  */
  assign accumulator_q = n733_q; // (signal)
  /* alu.vhd:100:10  */
  assign accu_shadow_q = n735_q; // (signal)
  /* alu.vhd:101:10  */
  assign temp_req_q = n737_q; // (signal)
  /* alu.vhd:103:10  */
  assign in_a_s = accu_shadow_q; // (signal)
  /* alu.vhd:104:10  */
  assign in_b_s = temp_req_q; // (signal)
  /* alu.vhd:106:10  */
  assign data_s = n738_o; // (signal)
  /* alu.vhd:108:10  */
  assign add_result_s = n667_o; // (signal)
  /* alu.vhd:122:14  */
  assign n489_o = ~res_i;
  /* alu.vhd:132:52  */
  assign n491_o = data_i[3:0];
  /* t48_core.vhd:448:33  */
  assign n492_o = data_i[3:0];
  /* alu.vhd:131:11  */
  assign n493_o = accu_low_i ? n491_o : n492_o;
  /* t48_core.vhd:445:33  */
  assign n494_o = data_i[7:4];
  /* t48_core.vhd:444:33  */
  assign n495_o = accumulator_q[7:4];
  /* alu.vhd:131:11  */
  assign n496_o = accu_low_i ? n495_o : n494_o;
  /* t48_core.vhd:440:33  */
  assign n497_o = {n496_o, n493_o};
  /* alu.vhd:138:9  */
  assign n499_o = write_shadow_i ? data_i : accumulator_q;
  /* alu.vhd:152:9  */
  assign n500_o = write_temp_reg_i ? data_i : temp_req_q;
  /* alu.vhd:149:9  */
  assign n502_o = p60_temp_reg_i ? 8'b01100000 : n500_o;
  /* alu.vhd:146:9  */
  assign n504_o = p06_temp_reg_i ? 8'b00000110 : n502_o;
  /* alu.vhd:128:7  */
  assign n505_o = en_clk_i & write_accu_i;
  /* alu.vhd:203:26  */
  assign n519_o = in_a_s & in_b_s;
  /* alu.vhd:202:7  */
  assign n521_o = alu_op_i == 4'b0000;
  /* alu.vhd:207:26  */
  assign n522_o = in_a_s | in_b_s;
  /* alu.vhd:206:7  */
  assign n524_o = alu_op_i == 4'b0001;
  /* alu.vhd:211:26  */
  assign n525_o = in_a_s ^ in_b_s;
  /* alu.vhd:210:7  */
  assign n527_o = alu_op_i == 4'b0010;
  /* alu.vhd:215:32  */
  assign n528_o = add_result_s[7:0];
  /* alu.vhd:216:32  */
  assign n529_o = add_result_s[8];
  /* alu.vhd:214:7  */
  assign n531_o = alu_op_i == 4'b1010;
  /* alu.vhd:220:19  */
  assign n532_o = ~in_a_s;
  /* alu.vhd:219:7  */
  assign n534_o = alu_op_i == 4'b0011;
  /* alu.vhd:223:7  */
  assign n536_o = alu_op_i == 4'b0100;
  /* alu.vhd:228:37  */
  assign n537_o = in_a_s[6:0];
  /* alu.vhd:229:37  */
  assign n538_o = in_a_s[7];
  /* alu.vhd:234:37  */
  assign n539_o = in_a_s[7];
  /* alu.vhd:231:9  */
  assign n540_o = use_carry_i ? carry_i : n539_o;
  /* alu.vhd:227:7  */
  assign n542_o = alu_op_i == 4'b0101;
  /* alu.vhd:239:37  */
  assign n543_o = in_a_s[7:1];
  /* alu.vhd:240:37  */
  assign n544_o = in_a_s[0];
  /* alu.vhd:245:37  */
  assign n545_o = in_a_s[0];
  /* alu.vhd:242:9  */
  assign n546_o = use_carry_i ? carry_i : n545_o;
  /* alu.vhd:238:7  */
  assign n548_o = alu_op_i == 4'b0110;
  /* alu.vhd:250:37  */
  assign n549_o = in_a_s[7:4];
  /* alu.vhd:251:37  */
  assign n550_o = in_a_s[3:0];
  /* alu.vhd:249:7  */
  assign n552_o = alu_op_i == 4'b0111;
  /* alu.vhd:255:31  */
  assign n553_o = add_result_s[7:0];
  /* alu.vhd:254:7  */
  assign n555_o = alu_op_i == 4'b1000;
  /* alu.vhd:259:31  */
  assign n556_o = add_result_s[7:0];
  /* alu.vhd:258:7  */
  assign n558_o = alu_op_i == 4'b1001;
  /* alu.vhd:263:25  */
  assign n559_o = in_b_s[7:4];
  /* alu.vhd:263:46  */
  assign n560_o = in_a_s[3:0];
  /* alu.vhd:263:38  */
  assign n561_o = {n559_o, n560_o};
  /* alu.vhd:262:7  */
  assign n563_o = alu_op_i == 4'b1011;
  /* alu.vhd:266:7  */
  assign n565_o = alu_op_i == 4'b1100;
  /* t48_core.vhd:388:3  */
  assign n566_o = {n565_o, n563_o, n558_o, n555_o, n552_o, n548_o, n542_o, n536_o, n534_o, n531_o, n527_o, n524_o, n521_o};
  /* alu.vhd:200:5  */
  always @*
    case (n566_o)
      13'b1000000000000: n568_o = 1'b0;
      13'b0100000000000: n568_o = 1'b0;
      13'b0010000000000: n568_o = 1'b0;
      13'b0001000000000: n568_o = 1'b0;
      13'b0000100000000: n568_o = 1'b0;
      13'b0000010000000: n568_o = n544_o;
      13'b0000001000000: n568_o = n538_o;
      13'b0000000100000: n568_o = 1'b0;
      13'b0000000010000: n568_o = 1'b0;
      13'b0000000001000: n568_o = n529_o;
      13'b0000000000100: n568_o = 1'b0;
      13'b0000000000010: n568_o = 1'b0;
      13'b0000000000001: n568_o = 1'b0;
      default: n568_o = 1'b0;
    endcase
  /* t48_core.vhd:388:3  */
  assign n570_o = n519_o[0];
  /* t48_core.vhd:388:3  */
  assign n571_o = n522_o[0];
  /* t48_core.vhd:388:3  */
  assign n572_o = n525_o[0];
  /* t48_core.vhd:388:3  */
  assign n573_o = n528_o[0];
  /* t48_core.vhd:388:3  */
  assign n574_o = n532_o[0];
  /* t48_core.vhd:388:3  */
  assign n576_o = n543_o[0];
  /* t48_core.vhd:388:3  */
  assign n577_o = n549_o[0];
  /* t48_core.vhd:388:3  */
  assign n578_o = n553_o[0];
  /* t48_core.vhd:388:3  */
  assign n579_o = n556_o[0];
  /* t48_core.vhd:388:3  */
  assign n580_o = n561_o[0];
  /* t48_core.vhd:388:3  */
  assign n581_o = in_a_s[0];
  /* alu.vhd:200:5  */
  always @*
    case (n566_o)
      13'b1000000000000: n583_o = n581_o;
      13'b0100000000000: n583_o = n580_o;
      13'b0010000000000: n583_o = n579_o;
      13'b0001000000000: n583_o = n578_o;
      13'b0000100000000: n583_o = n577_o;
      13'b0000010000000: n583_o = n576_o;
      13'b0000001000000: n583_o = n540_o;
      13'b0000000100000: n583_o = 1'b0;
      13'b0000000010000: n583_o = n574_o;
      13'b0000000001000: n583_o = n573_o;
      13'b0000000000100: n583_o = n572_o;
      13'b0000000000010: n583_o = n571_o;
      13'b0000000000001: n583_o = n570_o;
      default: n583_o = 1'b0;
    endcase
  /* t48_core.vhd:388:3  */
  assign n584_o = n519_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n585_o = n522_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n586_o = n525_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n587_o = n528_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n588_o = n532_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n590_o = n537_o[2:0];
  /* t48_core.vhd:388:3  */
  assign n591_o = n543_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n592_o = n549_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n593_o = n553_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n594_o = n556_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n595_o = n561_o[3:1];
  /* t48_core.vhd:388:3  */
  assign n596_o = in_a_s[3:1];
  /* alu.vhd:200:5  */
  always @*
    case (n566_o)
      13'b1000000000000: n598_o = n596_o;
      13'b0100000000000: n598_o = n595_o;
      13'b0010000000000: n598_o = n594_o;
      13'b0001000000000: n598_o = n593_o;
      13'b0000100000000: n598_o = n592_o;
      13'b0000010000000: n598_o = n591_o;
      13'b0000001000000: n598_o = n590_o;
      13'b0000000100000: n598_o = 3'b000;
      13'b0000000010000: n598_o = n588_o;
      13'b0000000001000: n598_o = n587_o;
      13'b0000000000100: n598_o = n586_o;
      13'b0000000000010: n598_o = n585_o;
      13'b0000000000001: n598_o = n584_o;
      default: n598_o = 3'b000;
    endcase
  /* t48_core.vhd:370:25  */
  assign n599_o = n519_o[6:4];
  /* t48_core.vhd:363:5  */
  assign n600_o = n522_o[6:4];
  /* t48_core.vhd:363:5  */
  assign n601_o = n525_o[6:4];
  /* t48_core.vhd:363:5  */
  assign n602_o = n528_o[6:4];
  /* t48_core.vhd:350:25  */
  assign n603_o = n532_o[6:4];
  /* t48_core.vhd:340:25  */
  assign n605_o = n537_o[5:3];
  /* t48_core.vhd:339:25  */
  assign n606_o = n543_o[6:4];
  /* t48_core.vhd:338:25  */
  assign n607_o = n550_o[2:0];
  /* t48_core.vhd:337:25  */
  assign n608_o = n553_o[6:4];
  /* t48_core.vhd:336:25  */
  assign n609_o = n556_o[6:4];
  /* t48_core.vhd:335:25  */
  assign n610_o = n561_o[6:4];
  /* t48_core.vhd:334:25  */
  assign n611_o = in_a_s[6:4];
  /* alu.vhd:200:5  */
  always @*
    case (n566_o)
      13'b1000000000000: n613_o = n611_o;
      13'b0100000000000: n613_o = n610_o;
      13'b0010000000000: n613_o = n609_o;
      13'b0001000000000: n613_o = n608_o;
      13'b0000100000000: n613_o = n607_o;
      13'b0000010000000: n613_o = n606_o;
      13'b0000001000000: n613_o = n605_o;
      13'b0000000100000: n613_o = 3'b000;
      13'b0000000010000: n613_o = n603_o;
      13'b0000000001000: n613_o = n602_o;
      13'b0000000000100: n613_o = n601_o;
      13'b0000000000010: n613_o = n600_o;
      13'b0000000000001: n613_o = n599_o;
      default: n613_o = 3'b000;
    endcase
  /* t48_core.vhd:317:3  */
  assign n614_o = n519_o[7];
  /* t48_core.vhd:317:3  */
  assign n615_o = n522_o[7];
  /* t48_core.vhd:317:3  */
  assign n616_o = n525_o[7];
  /* t48_core.vhd:317:3  */
  assign n617_o = n528_o[7];
  /* t48_core.vhd:317:3  */
  assign n618_o = n532_o[7];
  /* t48_core.vhd:317:3  */
  assign n620_o = n537_o[6];
  /* t48_core.vhd:317:3  */
  assign n621_o = n550_o[3];
  /* t48_core.vhd:317:3  */
  assign n622_o = n553_o[7];
  /* t48_core.vhd:314:21  */
  assign n623_o = n556_o[7];
  /* t48_core.vhd:303:3  */
  assign n624_o = n561_o[7];
  /* t48_core.vhd:297:29  */
  assign n625_o = in_a_s[7];
  /* alu.vhd:200:5  */
  always @*
    case (n566_o)
      13'b1000000000000: n627_o = n625_o;
      13'b0100000000000: n627_o = n624_o;
      13'b0010000000000: n627_o = n623_o;
      13'b0001000000000: n627_o = n622_o;
      13'b0000100000000: n627_o = n621_o;
      13'b0000010000000: n627_o = n546_o;
      13'b0000001000000: n627_o = n620_o;
      13'b0000000100000: n627_o = 1'b0;
      13'b0000000010000: n627_o = n618_o;
      13'b0000000001000: n627_o = n617_o;
      13'b0000000000100: n627_o = n616_o;
      13'b0000000000010: n627_o = n615_o;
      13'b0000000000001: n627_o = n614_o;
      default: n627_o = 1'b0;
    endcase
  /* alu.vhd:307:20  */
  assign n639_o = carry_i & use_carry_i;
  /* alu.vhd:307:5  */
  assign n642_o = n639_o ? 1'b1 : 1'b0;
  /* t48_core.vhd:91:5  */
  assign n644_o = n643_o[8:1];
  /* alu.vhd:313:20  */
  assign n646_o = {1'b0, in_a_s};
  /* alu.vhd:314:20  */
  assign n648_o = {1'b0, in_b_s};
  /* t48_pack-p.vhd:57:12  */
  assign n651_o = n650_o[8:1];
  /* alu.vhd:317:7  */
  assign n653_o = alu_op_i == 4'b1001;
  /* alu.vhd:320:7  */
  assign n655_o = alu_op_i == 4'b1000;
  /* t48_pack-p.vhd:57:12  */
  assign n656_o = {n655_o, n653_o};
  /* t48_pack-p.vhd:57:12  */
  assign n658_o = n648_o[0];
  /* alu.vhd:316:5  */
  always @*
    case (n656_o)
      2'b10: n659_o = 1'b1;
      2'b01: n659_o = 1'b1;
      default: n659_o = n658_o;
    endcase
  assign n661_o = n648_o[8:1];
  /* alu.vhd:316:5  */
  always @*
    case (n656_o)
      2'b10: n662_o = 8'b11111111;
      2'b01: n662_o = n651_o;
      default: n662_o = n661_o;
    endcase
  /* t48_pack-p.vhd:57:12  */
  assign n664_o = {n662_o, n659_o};
  /* alu.vhd:327:35  */
  assign n665_o = n646_o + n664_o;
  /* t48_pack-p.vhd:57:12  */
  assign n666_o = {n644_o, n642_o};
  /* alu.vhd:328:35  */
  assign n667_o = n665_o + n666_o;
  /* alu.vhd:334:32  */
  assign n668_o = in_a_s[4];
  /* alu.vhd:334:44  */
  assign n669_o = in_b_s[4];
  /* alu.vhd:334:36  */
  assign n670_o = {n668_o, n669_o};
  /* alu.vhd:339:20  */
  assign n671_o = n667_o[4];
  /* alu.vhd:339:9  */
  assign n674_o = n671_o ? 1'b1 : 1'b0;
  /* alu.vhd:338:7  */
  assign n676_o = n670_o == 2'b00;
  /* alu.vhd:338:17  */
  assign n678_o = n670_o == 2'b11;
  /* alu.vhd:338:17  */
  assign n679_o = n676_o | n678_o;
  /* alu.vhd:344:20  */
  assign n680_o = n667_o[4];
  /* alu.vhd:344:24  */
  assign n681_o = ~n680_o;
  /* alu.vhd:344:9  */
  assign n684_o = n681_o ? 1'b1 : 1'b0;
  /* alu.vhd:343:7  */
  assign n686_o = n670_o == 2'b01;
  /* alu.vhd:343:17  */
  assign n688_o = n670_o == 2'b10;
  /* alu.vhd:343:17  */
  assign n689_o = n686_o | n688_o;
  /* t48_pack-p.vhd:58:12  */
  assign n690_o = {n689_o, n679_o};
  /* alu.vhd:337:5  */
  always @*
    case (n690_o)
      2'b10: n692_o = n684_o;
      2'b01: n692_o = n674_o;
      default: n692_o = 1'b0;
    endcase
  /* alu.vhd:389:35  */
  assign n699_o = accu_shadow_q[7:4];
  /* alu.vhd:391:35  */
  assign n700_o = accu_shadow_q[3:0];
  /* alu.vhd:388:5  */
  assign n701_o = da_high_i ? n699_o : n700_o;
  /* alu.vhd:373:9  */
  assign n709_o = n701_o == 4'b1010;
  /* alu.vhd:373:21  */
  assign n711_o = n701_o == 4'b1011;
  /* alu.vhd:373:21  */
  assign n712_o = n709_o | n711_o;
  /* alu.vhd:374:21  */
  assign n714_o = n701_o == 4'b1100;
  /* alu.vhd:374:21  */
  assign n715_o = n712_o | n714_o;
  /* alu.vhd:375:21  */
  assign n717_o = n701_o == 4'b1101;
  /* alu.vhd:375:21  */
  assign n718_o = n715_o | n717_o;
  /* alu.vhd:376:21  */
  assign n720_o = n701_o == 4'b1110;
  /* alu.vhd:376:21  */
  assign n721_o = n718_o | n720_o;
  /* alu.vhd:377:21  */
  assign n723_o = n701_o == 4'b1111;
  /* alu.vhd:377:21  */
  assign n724_o = n721_o | n723_o;
  /* alu.vhd:372:7  */
  always @*
    case (n724_o)
      1'b1: n727_o = 1'b1;
      default: n727_o = 1'b0;
    endcase
  /* alu.vhd:412:13  */
  assign n730_o = read_alu_i ? data_s : 8'b11111111;
  /* alu.vhd:127:5  */
  assign n732_o = n505_o ? n497_o : accumulator_q;
  /* alu.vhd:127:5  */
  always @(posedge clk_i or posedge n489_o)
    if (n489_o)
      n733_q <= 8'b00000000;
    else
      n733_q <= n732_o;
  /* alu.vhd:127:5  */
  assign n734_o = en_clk_i ? n499_o : accu_shadow_q;
  /* alu.vhd:127:5  */
  always @(posedge clk_i or posedge n489_o)
    if (n489_o)
      n735_q <= 8'b00000000;
    else
      n735_q <= n734_o;
  /* alu.vhd:127:5  */
  assign n736_o = en_clk_i ? n504_o : temp_req_q;
  /* alu.vhd:127:5  */
  always @(posedge clk_i or posedge n489_o)
    if (n489_o)
      n737_q <= 8'b00000000;
    else
      n737_q <= n736_o;
  /* alu.vhd:122:5  */
  assign n738_o = {n627_o, n613_o, n598_o, n583_o};
endmodule