// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_bus_mux
  (input  [7:0] alu_data_i,
   input  [7:0] bus_data_i,
   input  [7:0] dec_data_i,
   input  [7:0] dm_data_i,
   input  [7:0] pm_data_i,
   input  [7:0] p1_data_i,
   input  [7:0] p2_data_i,
   input  [7:0] psw_data_i,
   input  [7:0] tim_data_i,
   output [7:0] data_o);
  wire [7:0] n740_o;
  wire [7:0] n741_o;
  wire [7:0] n742_o;
  wire [7:0] n743_o;
  wire [7:0] n744_o;
  wire [7:0] n745_o;
  wire [7:0] n746_o;
  wire [7:0] n747_o;
  assign data_o = n747_o;
  /* bus_mux.vhd:89:26  */
  assign n740_o = alu_data_i & bus_data_i;
  /* bus_mux.vhd:90:26  */
  assign n741_o = n740_o & dec_data_i;
  /* bus_mux.vhd:91:26  */
  assign n742_o = n741_o & dm_data_i;
  /* bus_mux.vhd:92:26  */
  assign n743_o = n742_o & pm_data_i;
  /* bus_mux.vhd:93:26  */
  assign n744_o = n743_o & p1_data_i;
  /* bus_mux.vhd:94:26  */
  assign n745_o = n744_o & p2_data_i;
  /* bus_mux.vhd:95:26  */
  assign n746_o = n745_o & psw_data_i;
  /* bus_mux.vhd:96:26  */
  assign n747_o = n746_o & tim_data_i;
endmodule