// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_db_bus
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  ea_i,
   input  [7:0] data_i,
   input  write_bus_i,
   input  read_bus_i,
   input  output_pcl_i,
   input  bidir_bus_i,
   input  [7:0] pcl_i,
   input  [7:0] db_i,
   output [7:0] data_o,
   output [7:0] db_o,
   output db_dir_o);
  wire [7:0] bus_q;
  wire db_dir_q;
  wire db_dir_qq;
  wire n1065_o;
  wire n1068_o;
  wire n1069_o;
  wire n1071_o;
  wire n1074_o;
  wire n1075_o;
  wire [7:0] n1088_o;
  wire n1096_o;
  wire n1097_o;
  wire n1099_o;
  wire [7:0] n1100_o;
  wire [7:0] n1101_o;
  reg [7:0] n1102_q;
  wire n1103_o;
  reg n1104_q;
  wire n1105_o;
  reg n1106_q;
  assign data_o = n1100_o;
  assign db_o = n1088_o;
  assign db_dir_o = n1097_o;
  /* db_bus.vhd:85:10  */
  assign bus_q = n1102_q; // (signal)
  /* db_bus.vhd:88:10  */
  assign db_dir_q = n1104_q; // (signal)
  /* db_bus.vhd:89:10  */
  assign db_dir_qq = n1106_q; // (signal)
  /* db_bus.vhd:101:14  */
  assign n1065_o = ~res_i;
  /* db_bus.vhd:108:9  */
  assign n1068_o = write_bus_i ? 1'b1 : db_dir_q;
  /* db_bus.vhd:120:26  */
  assign n1069_o = ea_i | bidir_bus_i;
  /* db_bus.vhd:120:9  */
  assign n1071_o = n1069_o ? 1'b0 : db_dir_q;
  /* db_bus.vhd:115:9  */
  assign n1074_o = write_bus_i ? 1'b1 : n1071_o;
  /* db_bus.vhd:107:7  */
  assign n1075_o = en_clk_i & write_bus_i;
  /* db_bus.vhd:138:15  */
  assign n1088_o = output_pcl_i ? pcl_i : bus_q;
  /* t48_pack-p.vhd:66:5  */
  assign n1096_o = output_pcl_i ? 1'b1 : 1'b0;
  /* db_bus.vhd:140:25  */
  assign n1097_o = db_dir_qq | n1096_o;
  /* db_bus.vhd:143:20  */
  assign n1099_o = ~read_bus_i;
  /* db_bus.vhd:143:15  */
  assign n1100_o = n1099_o ? 8'b11111111 : db_i;
  /* db_bus.vhd:106:5  */
  assign n1101_o = n1075_o ? data_i : bus_q;
  /* db_bus.vhd:106:5  */
  always @(posedge clk_i or posedge n1065_o)
    if (n1065_o)
      n1102_q <= 8'b00000000;
    else
      n1102_q <= n1101_o;
  /* db_bus.vhd:106:5  */
  assign n1103_o = en_clk_i ? n1074_o : db_dir_q;
  /* db_bus.vhd:106:5  */
  always @(posedge clk_i or posedge n1065_o)
    if (n1065_o)
      n1104_q <= 1'b0;
    else
      n1104_q <= n1103_o;
  /* db_bus.vhd:106:5  */
  assign n1105_o = en_clk_i ? n1068_o : db_dir_qq;
  /* db_bus.vhd:106:5  */
  always @(posedge clk_i or posedge n1065_o)
    if (n1065_o)
      n1106_q <= 1'b0;
    else
      n1106_q <= n1105_o;
endmodule