// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_psw
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  [7:0] data_i,
   input  read_psw_i,
   input  read_sp_i,
   input  write_psw_i,
   input  write_sp_i,
   input  special_data_i,
   input  inc_stackp_i,
   input  dec_stackp_i,
   input  write_carry_i,
   input  write_aux_carry_i,
   input  write_f0_i,
   input  write_bs_i,
   input  aux_carry_i,
   output [7:0] data_o,
   output carry_o,
   output aux_carry_o,
   output f0_o,
   output bs_o);
  wire [3:0] psw_q;
  wire [2:0] sp_q;
  wire n4793_o;
  wire [2:0] n4797_o;
  wire [2:0] n4798_o;
  wire [2:0] n4800_o;
  wire [2:0] n4801_o;
  wire [2:0] n4803_o;
  wire [2:0] n4804_o;
  wire n4805_o;
  wire n4806_o;
  wire n4807_o;
  wire n4808_o;
  wire n4812_o;
  wire n4813_o;
  wire n4814_o;
  wire n4815_o;
  wire n4819_o;
  wire n4820_o;
  wire n4821_o;
  wire n4822_o;
  wire n4823_o;
  wire n4824_o;
  wire n4825_o;
  wire n4826_o;
  wire [3:0] n4827_o;
  wire [3:0] n4839_o;
  localparam [7:0] n4840_o = 8'b11111111;
  wire [3:0] n4841_o;
  wire [3:0] n4843_o;
  wire [3:0] n4844_o;
  wire n4846_o;
  wire n4847_o;
  wire n4848_o;
  wire n4849_o;
  wire [3:0] n4850_o;
  reg [3:0] n4851_q;
  wire [2:0] n4852_o;
  reg [2:0] n4853_q;
  wire [7:0] n4854_o;
  assign data_o = n4854_o;
  assign carry_o = n4846_o;
  assign aux_carry_o = n4847_o;
  assign f0_o = n4848_o;
  assign bs_o = n4849_o;
  /* psw.vhd:101:10  */
  assign psw_q = n4851_q; // (signal)
  /* psw.vhd:103:10  */
  assign sp_q = n4853_q; // (signal)
  /* psw.vhd:119:14  */
  assign n4793_o = ~res_i;
  /* psw.vhd:131:34  */
  assign n4797_o = data_i[2:0];
  /* psw.vhd:130:9  */
  assign n4798_o = write_sp_i ? n4797_o : sp_q;
  /* psw.vhd:136:25  */
  assign n4800_o = sp_q + 3'b001;
  /* psw.vhd:135:9  */
  assign n4801_o = inc_stackp_i ? n4800_o : n4798_o;
  /* psw.vhd:140:25  */
  assign n4803_o = sp_q - 3'b001;
  /* psw.vhd:139:9  */
  assign n4804_o = dec_stackp_i ? n4803_o : n4801_o;
  assign n4805_o = data_i[7];
  assign n4806_o = psw_q[3];
  /* psw.vhd:127:9  */
  assign n4807_o = write_psw_i ? n4805_o : n4806_o;
  /* psw.vhd:144:9  */
  assign n4808_o = write_carry_i ? special_data_i : n4807_o;
  assign n4812_o = data_i[6];
  assign n4813_o = psw_q[2];
  /* psw.vhd:127:9  */
  assign n4814_o = write_psw_i ? n4812_o : n4813_o;
  /* psw.vhd:148:9  */
  assign n4815_o = write_aux_carry_i ? aux_carry_i : n4814_o;
  assign n4819_o = data_i[5];
  assign n4820_o = psw_q[1];
  /* psw.vhd:127:9  */
  assign n4821_o = write_psw_i ? n4819_o : n4820_o;
  /* psw.vhd:152:9  */
  assign n4822_o = write_f0_i ? special_data_i : n4821_o;
  assign n4823_o = data_i[4];
  assign n4824_o = psw_q[0];
  /* psw.vhd:127:9  */
  assign n4825_o = write_psw_i ? n4823_o : n4824_o;
  /* psw.vhd:156:9  */
  assign n4826_o = write_bs_i ? special_data_i : n4825_o;
  assign n4827_o = {n4808_o, n4815_o, n4822_o, n4826_o};
  /* psw.vhd:182:5  */
  assign n4839_o = read_psw_i ? psw_q : 4'b1111;
  assign n4841_o = n4840_o[3:0];
  /* psw.vhd:187:33  */
  assign n4843_o = {1'b1, sp_q};
  /* psw.vhd:186:5  */
  assign n4844_o = read_sp_i ? n4843_o : n4841_o;
  /* psw.vhd:207:23  */
  assign n4846_o = psw_q[3];
  /* psw.vhd:208:23  */
  assign n4847_o = psw_q[2];
  /* psw.vhd:209:23  */
  assign n4848_o = psw_q[1];
  /* psw.vhd:210:23  */
  assign n4849_o = psw_q[0];
  /* psw.vhd:123:5  */
  assign n4850_o = en_clk_i ? n4827_o : psw_q;
  /* psw.vhd:123:5  */
  always @(posedge clk_i or posedge n4793_o)
    if (n4793_o)
      n4851_q <= 4'b0000;
    else
      n4851_q <= n4850_o;
  /* psw.vhd:123:5  */
  assign n4852_o = en_clk_i ? n4804_o : sp_q;
  /* psw.vhd:123:5  */
  always @(posedge clk_i or posedge n4793_o)
    if (n4793_o)
      n4853_q <= 3'b000;
    else
      n4853_q <= n4852_o;
  /* psw.vhd:119:5  */
  assign n4854_o = {n4839_o, n4844_o};
endmodule
