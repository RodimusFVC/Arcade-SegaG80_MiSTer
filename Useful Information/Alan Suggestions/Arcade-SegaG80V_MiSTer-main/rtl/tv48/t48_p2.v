// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_p2
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  xtal_i,
   input  xtal_en_i,
   input  [7:0] data_i,
   input  write_p2_i,
   input  write_exp_i,
   input  read_p2_i,
   input  read_reg_i,
   input  read_exp_i,
   input  output_pch_i,
   input  [3:0] pch_i,
   input  [7:0] p2_i,
   output [7:0] data_o,
   output [7:0] p2_o,
   output p2l_low_imp_o,
   output p2h_low_imp_o);
  wire [7:0] p2_q;
  wire l_low_imp_q;
  wire h_low_imp_q;
  wire en_clk_q;
  wire l_low_imp_del_q;
  wire h_low_imp_del_q;
  wire output_pch_q;
  wire n4618_o;
  wire [3:0] n4620_o;
  wire [3:0] n4621_o;
  wire [3:0] n4622_o;
  wire n4625_o;
  wire [3:0] n4626_o;
  wire [3:0] n4627_o;
  wire [3:0] n4628_o;
  wire [3:0] n4629_o;
  wire [3:0] n4630_o;
  wire n4632_o;
  wire n4636_o;
  wire [7:0] n4638_o;
  wire n4653_o;
  wire [3:0] n4655_o;
  wire [3:0] n4656_o;
  wire [3:0] n4657_o;
  wire n4658_o;
  wire n4659_o;
  wire n4660_o;
  wire n4663_o;
  wire n4664_o;
  wire n4667_o;
  wire [7:0] n4668_o;
  wire [3:0] n4691_o;
  wire [7:0] n4693_o;
  wire [7:0] n4694_o;
  wire [7:0] n4695_o;
  wire [7:0] n4697_o;
  wire [7:0] n4700_o;
  reg [7:0] n4701_q;
  wire n4702_o;
  reg n4703_q;
  wire n4704_o;
  reg n4705_q;
  wire n4706_o;
  reg n4707_q;
  wire n4708_o;
  reg n4709_q;
  wire n4710_o;
  reg n4711_q;
  wire n4712_o;
  reg n4713_q;
  wire [7:0] n4714_o;
  reg [7:0] n4715_q;
  assign data_o = n4697_o;
  assign p2_o = n4715_q;
  assign p2l_low_imp_o = l_low_imp_del_q;
  assign p2h_low_imp_o = h_low_imp_del_q;
  /* p2.vhd:89:10  */
  assign p2_q = n4701_q; // (signal)
  /* p2.vhd:92:10  */
  assign l_low_imp_q = n4703_q; // (signal)
  /* p2.vhd:93:10  */
  assign h_low_imp_q = n4705_q; // (signal)
  /* p2.vhd:95:10  */
  assign en_clk_q = n4707_q; // (signal)
  /* p2.vhd:96:10  */
  assign l_low_imp_del_q = n4709_q; // (signal)
  /* p2.vhd:97:10  */
  assign h_low_imp_del_q = n4711_q; // (signal)
  /* p2.vhd:98:10  */
  assign output_pch_q = n4713_q; // (signal)
  /* p2.vhd:110:14  */
  assign n4618_o = ~res_i;
  /* p2.vhd:129:41  */
  assign n4620_o = data_i[3:0];
  /* decoder.vhd:496:15  */
  assign n4621_o = p2_q[3:0];
  /* p2.vhd:127:9  */
  assign n4622_o = write_exp_i ? n4620_o : n4621_o;
  /* p2.vhd:127:9  */
  assign n4625_o = write_exp_i ? 1'b1 : 1'b0;
  /* decoder.vhd:496:15  */
  assign n4626_o = data_i[3:0];
  /* p2.vhd:121:9  */
  assign n4627_o = write_p2_i ? n4626_o : n4622_o;
  /* decoder.vhd:496:15  */
  assign n4628_o = data_i[7:4];
  /* decoder.vhd:496:15  */
  assign n4629_o = p2_q[7:4];
  /* p2.vhd:121:9  */
  assign n4630_o = write_p2_i ? n4628_o : n4629_o;
  /* p2.vhd:121:9  */
  assign n4632_o = write_p2_i ? 1'b1 : n4625_o;
  /* p2.vhd:121:9  */
  assign n4636_o = write_p2_i ? 1'b1 : 1'b0;
  assign n4638_o = {n4630_o, n4627_o};
  /* p2.vhd:155:14  */
  assign n4653_o = ~res_i;
  /* decoder.vhd:481:15  */
  assign n4655_o = p2_q[3:0];
  /* p2.vhd:170:9  */
  assign n4656_o = output_pch_i ? pch_i : n4655_o;
  /* decoder.vhd:474:22  */
  assign n4657_o = p2_q[7:4];
  /* p2.vhd:179:26  */
  assign n4658_o = output_pch_q ^ output_pch_i;
  /* p2.vhd:179:44  */
  assign n4659_o = n4658_o | l_low_imp_q;
  /* p2.vhd:178:21  */
  assign n4660_o = n4659_o & en_clk_q;
  /* p2.vhd:178:9  */
  assign n4663_o = n4660_o ? 1'b1 : 1'b0;
  /* p2.vhd:189:21  */
  assign n4664_o = h_low_imp_q & en_clk_q;
  /* p2.vhd:189:9  */
  assign n4667_o = n4664_o ? 1'b1 : 1'b0;
  assign n4668_o = {n4657_o, n4656_o};
  /* p2.vhd:221:32  */
  assign n4691_o = p2_i[3:0];
  /* p2.vhd:221:26  */
  assign n4693_o = {4'b0000, n4691_o};
  /* p2.vhd:220:7  */
  assign n4694_o = read_exp_i ? n4693_o : p2_i;
  /* p2.vhd:218:7  */
  assign n4695_o = read_reg_i ? p2_q : n4694_o;
  /* p2.vhd:217:5  */
  assign n4697_o = read_p2_i ? n4695_o : 8'b11111111;
  /* p2.vhd:115:5  */
  assign n4700_o = en_clk_i ? n4638_o : p2_q;
  /* p2.vhd:115:5  */
  always @(posedge clk_i or posedge n4618_o)
    if (n4618_o)
      n4701_q <= 8'b11111111;
    else
      n4701_q <= n4700_o;
  /* p2.vhd:115:5  */
  assign n4702_o = en_clk_i ? n4632_o : l_low_imp_q;
  /* p2.vhd:115:5  */
  always @(posedge clk_i or posedge n4618_o)
    if (n4618_o)
      n4703_q <= 1'b0;
    else
      n4703_q <= n4702_o;
  /* p2.vhd:115:5  */
  assign n4704_o = en_clk_i ? n4636_o : h_low_imp_q;
  /* p2.vhd:115:5  */
  always @(posedge clk_i or posedge n4618_o)
    if (n4618_o)
      n4705_q <= 1'b0;
    else
      n4705_q <= n4704_o;
  /* p2.vhd:162:5  */
  assign n4706_o = xtal_en_i ? en_clk_i : en_clk_q;
  /* p2.vhd:162:5  */
  always @(posedge xtal_i or posedge n4653_o)
    if (n4653_o)
      n4707_q <= 1'b0;
    else
      n4707_q <= n4706_o;
  /* p2.vhd:162:5  */
  assign n4708_o = xtal_en_i ? n4663_o : l_low_imp_del_q;
  /* p2.vhd:162:5  */
  always @(posedge xtal_i or posedge n4653_o)
    if (n4653_o)
      n4709_q <= 1'b0;
    else
      n4709_q <= n4708_o;
  /* p2.vhd:162:5  */
  assign n4710_o = xtal_en_i ? n4667_o : h_low_imp_del_q;
  /* p2.vhd:162:5  */
  always @(posedge xtal_i or posedge n4653_o)
    if (n4653_o)
      n4711_q <= 1'b0;
    else
      n4711_q <= n4710_o;
  /* p2.vhd:162:5  */
  assign n4712_o = xtal_en_i ? output_pch_i : output_pch_q;
  /* p2.vhd:162:5  */
  always @(posedge xtal_i or posedge n4653_o)
    if (n4653_o)
      n4713_q <= 1'b0;
    else
      n4713_q <= n4712_o;
  /* p2.vhd:162:5  */
  assign n4714_o = xtal_en_i ? n4668_o : n4715_q;
  /* p2.vhd:162:5  */
  always @(posedge xtal_i or posedge n4653_o)
    if (n4653_o)
      n4715_q <= 8'b11111111;
    else
      n4715_q <= n4714_o;
endmodule
