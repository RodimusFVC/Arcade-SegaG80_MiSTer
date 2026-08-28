// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_cond_branch
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  compute_take_i,
   input  [3:0] branch_cond_i,
   input  [7:0] accu_i,
   input  t0_i,
   input  t1_i,
   input  int_n_i,
   input  f0_i,
   input  f1_i,
   input  tf_i,
   input  carry_i,
   input  [2:0] comp_value_i,
   output take_branch_o);
  wire take_branch_s;
  wire take_branch_q;
  wire n982_o;
  wire n984_o;
  wire n985_o;
  wire n987_o;
  wire n988_o;
  wire n989_o;
  wire n990_o;
  wire n991_o;
  wire n992_o;
  wire n993_o;
  wire n994_o;
  wire n995_o;
  wire n996_o;
  wire n997_o;
  wire n998_o;
  wire n999_o;
  wire n1000_o;
  wire n1001_o;
  wire n1002_o;
  wire n1003_o;
  wire n1004_o;
  wire n1006_o;
  wire n1007_o;
  wire n1008_o;
  wire n1010_o;
  wire n1012_o;
  wire n1014_o;
  wire n1015_o;
  wire n1017_o;
  wire n1018_o;
  wire n1019_o;
  wire n1021_o;
  wire n1022_o;
  wire n1023_o;
  wire n1025_o;
  wire n1027_o;
  wire [8:0] n1028_o;
  reg n1030_o;
  wire n1037_o;
  wire n1040_o;
  wire n1045_o;
  reg n1046_q;
  wire n1047_o;
  wire n1048_o;
  wire n1049_o;
  wire n1050_o;
  wire n1051_o;
  wire n1052_o;
  wire n1053_o;
  wire n1054_o;
  wire [1:0] n1055_o;
  reg n1056_o;
  wire [1:0] n1057_o;
  reg n1058_o;
  wire n1059_o;
  wire n1060_o;
  assign take_branch_o = take_branch_q;
  /* cond_branch.vhd:88:10  */
  assign take_branch_s = n1030_o; // (signal)
  /* cond_branch.vhd:89:10  */
  assign take_branch_q = n1046_q; // (signal)
  /* cond_branch.vhd:116:9  */
  assign n982_o = n1060_o ? 1'b1 : 1'b0;
  /* cond_branch.vhd:115:7  */
  assign n984_o = branch_cond_i == 4'b0000;
  /* cond_branch.vhd:123:33  */
  assign n985_o = accu_i[7];
  /* cond_branch.vhd:123:24  */
  assign n987_o = 1'b0 | n985_o;
  /* cond_branch.vhd:123:33  */
  assign n988_o = accu_i[6];
  /* cond_branch.vhd:123:24  */
  assign n989_o = n987_o | n988_o;
  /* cond_branch.vhd:123:33  */
  assign n990_o = accu_i[5];
  /* cond_branch.vhd:123:24  */
  assign n991_o = n989_o | n990_o;
  /* cond_branch.vhd:123:33  */
  assign n992_o = accu_i[4];
  /* cond_branch.vhd:123:24  */
  assign n993_o = n991_o | n992_o;
  /* cond_branch.vhd:123:33  */
  assign n994_o = accu_i[3];
  /* cond_branch.vhd:123:24  */
  assign n995_o = n993_o | n994_o;
  /* cond_branch.vhd:123:33  */
  assign n996_o = accu_i[2];
  /* cond_branch.vhd:123:24  */
  assign n997_o = n995_o | n996_o;
  /* cond_branch.vhd:123:33  */
  assign n998_o = accu_i[1];
  /* cond_branch.vhd:123:24  */
  assign n999_o = n997_o | n998_o;
  /* cond_branch.vhd:123:33  */
  assign n1000_o = accu_i[0];
  /* cond_branch.vhd:123:24  */
  assign n1001_o = n999_o | n1000_o;
  /* cond_branch.vhd:125:49  */
  assign n1002_o = comp_value_i[0];
  /* cond_branch.vhd:125:33  */
  assign n1003_o = ~n1002_o;
  /* cond_branch.vhd:125:31  */
  assign n1004_o = n1001_o == n1003_o;
  /* cond_branch.vhd:121:7  */
  assign n1006_o = branch_cond_i == 4'b0001;
  /* cond_branch.vhd:129:48  */
  assign n1007_o = comp_value_i[0];
  /* cond_branch.vhd:129:34  */
  assign n1008_o = carry_i == n1007_o;
  /* cond_branch.vhd:128:7  */
  assign n1010_o = branch_cond_i == 4'b0010;
  /* cond_branch.vhd:132:7  */
  assign n1012_o = branch_cond_i == 4'b0011;
  /* cond_branch.vhd:136:7  */
  assign n1014_o = branch_cond_i == 4'b0100;
  /* cond_branch.vhd:141:34  */
  assign n1015_o = ~int_n_i;
  /* cond_branch.vhd:140:7  */
  assign n1017_o = branch_cond_i == 4'b0101;
  /* cond_branch.vhd:145:45  */
  assign n1018_o = comp_value_i[0];
  /* cond_branch.vhd:145:31  */
  assign n1019_o = t0_i == n1018_o;
  /* cond_branch.vhd:144:7  */
  assign n1021_o = branch_cond_i == 4'b0110;
  /* cond_branch.vhd:149:45  */
  assign n1022_o = comp_value_i[0];
  /* cond_branch.vhd:149:31  */
  assign n1023_o = t1_i == n1022_o;
  /* cond_branch.vhd:148:7  */
  assign n1025_o = branch_cond_i == 4'b0111;
  /* cond_branch.vhd:152:7  */

  always @(posedge clk_i)
  begin
    //if(en_clk_i && res_i && take_branch_s) $display("n1040_o=%b take_branch_s: %b t1_i=%x comp_value_i[0]=%x", n1040_o, take_branch_s, t1_i, comp_value_i[0]);
  end


  assign n1027_o = branch_cond_i == 4'b1000;
  /* clock_ctrl.vhd:91:10  */
  assign n1028_o = {n1027_o, n1025_o, n1021_o, n1017_o, n1014_o, n1012_o, n1010_o, n1006_o, n984_o};
  /* cond_branch.vhd:113:5  */
  always @*
    case (n1028_o)
      9'b100000000: n1030_o = tf_i;
      9'b010000000: n1030_o = n1023_o;
      9'b001000000: n1030_o = n1019_o;
      9'b000100000: n1030_o = n1015_o;
      9'b000010000: n1030_o = f1_i;
      9'b000001000: n1030_o = f0_i;
      9'b000000100: n1030_o = n1008_o;
      9'b000000010: n1030_o = n1004_o;
      9'b000000001: n1030_o = n982_o;
      default: n1030_o = 1'b0;
    endcase
  /* cond_branch.vhd:177:14  */
  assign n1037_o = ~res_i;
  /* cond_branch.vhd:181:7  */
  assign n1040_o = en_clk_i & compute_take_i;
  /* cond_branch.vhd:180:5  */
  assign n1045_o = n1040_o ? take_branch_s : take_branch_q;
  /* cond_branch.vhd:180:5  */
  always @(posedge clk_i or posedge n1037_o)
    if (n1037_o)
      n1046_q <= 1'b0;
    else
      n1046_q <= n1045_o;
  /* cond_branch.vhd:64:5  */
  assign n1047_o = accu_i[0];
  assign n1048_o = accu_i[1];
  /* cond_branch.vhd:180:5  */
  assign n1049_o = accu_i[2];
  /* cond_branch.vhd:175:3  */
  assign n1050_o = accu_i[3];
  assign n1051_o = accu_i[4];
  /* clock_ctrl.vhd:292:5  */
  assign n1052_o = accu_i[5];
  /* cond_branch.vhd:113:5  */
  assign n1053_o = accu_i[6];
  /* clock_ctrl.vhd:206:5  */
  assign n1054_o = accu_i[7];
  /* cond_branch.vhd:116:18  */
  assign n1055_o = comp_value_i[1:0];
  /* cond_branch.vhd:116:18  */
  always @*
    case (n1055_o)
      2'b00: n1056_o = n1047_o;
      2'b01: n1056_o = n1048_o;
      2'b10: n1056_o = n1049_o;
      2'b11: n1056_o = n1050_o;
    endcase
  /* cond_branch.vhd:116:18  */
  assign n1057_o = comp_value_i[1:0];
  /* cond_branch.vhd:116:18  */
  always @*
    case (n1057_o)
      2'b00: n1058_o = n1051_o;
      2'b01: n1058_o = n1052_o;
      2'b10: n1058_o = n1053_o;
      2'b11: n1058_o = n1054_o;
    endcase
  /* cond_branch.vhd:116:18  */
  assign n1059_o = comp_value_i[2];
  /* cond_branch.vhd:116:18  */
  assign n1060_o = n1059_o ? n1058_o : n1056_o;
endmodule