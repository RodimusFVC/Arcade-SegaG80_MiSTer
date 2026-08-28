// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_p1
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  [7:0] data_i,
   input  write_p1_i,
   input  read_p1_i,
   input  read_reg_i,
   input  [7:0] p1_i,
   output [7:0] data_o,
   output [7:0] p1_o,
   output p1_low_imp_o);
  wire [7:0] p1_q;
  wire low_imp_q;
  wire n4588_o;
  wire n4593_o;
  wire n4594_o;
  wire [7:0] n4604_o;
  wire [7:0] n4606_o;
  wire [7:0] n4609_o;
  reg [7:0] n4610_q;
  wire n4611_o;
  reg n4612_q;
  assign data_o = n4606_o;
  assign p1_o = p1_q;
  assign p1_low_imp_o = low_imp_q;
  /* p1.vhd:81:10  */
  assign p1_q = n4610_q; // (signal)
  /* p1.vhd:84:10  */
  assign low_imp_q = n4612_q; // (signal)
  /* p1.vhd:96:14  */
  assign n4588_o = ~res_i;
  /* p1.vhd:103:9  */
  assign n4593_o = write_p1_i ? 1'b1 : 1'b0;
  /* p1.vhd:101:7  */
  assign n4594_o = en_clk_i & write_p1_i;
  /* p1.vhd:133:7  */
  assign n4604_o = read_reg_i ? p1_q : p1_i;
  /* p1.vhd:132:5  */
  assign n4606_o = read_p1_i ? n4604_o : 8'b11111111;
  /* p1.vhd:100:5  */
  assign n4609_o = n4594_o ? data_i : p1_q;
  /* p1.vhd:100:5  */
  always @(posedge clk_i or posedge n4588_o)
    if (n4588_o)
      n4610_q <= 8'b11111111;
    else
      n4610_q <= n4609_o;
  /* p1.vhd:100:5  */
  assign n4611_o = en_clk_i ? n4593_o : low_imp_q;
  /* p1.vhd:100:5  */
  always @(posedge clk_i or posedge n4588_o)
    if (n4588_o)
      n4612_q <= 1'b0;
    else
      n4612_q <= n4611_o;
endmodule
