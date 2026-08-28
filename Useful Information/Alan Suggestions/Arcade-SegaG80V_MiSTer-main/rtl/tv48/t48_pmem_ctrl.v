// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_pmem_ctrl
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  [7:0] data_i,
   input  write_pcl_i,
   input  read_pcl_i,
   input  write_pch_i,
   input  read_pch_i,
   input  inc_pc_i,
   input  write_pmem_addr_i,
   input  [1:0] addr_type_i,
   input  read_pmem_i,
   input  [7:0] pmem_data_i,
   output [7:0] data_o,
   output [11:0] pmem_addr_o);
  wire [11:0] program_counter_q;
  wire [11:0] pmem_addr_s;
  wire [11:0] pmem_addr_q;
  wire n4719_o;
  wire [3:0] n4721_o;
  wire [10:0] n4722_o;
  wire [10:0] n4724_o;
  wire [10:0] n4725_o;
  wire [10:0] n4726_o;
  wire [7:0] n4727_o;
  wire [7:0] n4728_o;
  wire [7:0] n4729_o;
  wire [2:0] n4730_o;
  wire [2:0] n4731_o;
  wire [2:0] n4732_o;
  wire n4733_o;
  wire n4734_o;
  wire n4735_o;
  wire [11:0] n4736_o;
  wire [7:0] n4737_o;
  wire [7:0] n4738_o;
  wire [3:0] n4739_o;
  wire [3:0] n4740_o;
  wire [3:0] n4741_o;
  wire [11:0] n4743_o;
  wire n4745_o;
  wire n4755_o;
  wire n4757_o;
  wire n4760_o;
  wire [2:0] n4761_o;
  wire [7:0] n4762_o;
  reg [7:0] n4763_o;
  wire [3:0] n4764_o;
  reg [3:0] n4765_o;
  wire [7:0] n4769_o;
  wire [3:0] n4770_o;
  wire [3:0] n4772_o;
  wire [3:0] n4773_o;
  wire [3:0] n4774_o;
  wire [3:0] n4775_o;
  wire [3:0] n4777_o;
  wire [7:0] n4778_o;
  wire [7:0] n4779_o;
  wire [11:0] n4782_o;
  reg [11:0] n4783_q;
  wire [11:0] n4784_o;
  wire [11:0] n4785_o;
  reg [11:0] n4786_q;
  assign data_o = n4779_o;
  assign pmem_addr_o = pmem_addr_q;
  /* pmem_ctrl.vhd:98:10  */
  assign program_counter_q = n4783_q; // (signal)
  /* pmem_ctrl.vhd:102:10  */
  assign pmem_addr_s = n4784_o; // (signal)
  /* pmem_ctrl.vhd:103:10  */
  assign pmem_addr_q = n4786_q; // (signal)
  /* pmem_ctrl.vhd:115:14  */
  assign n4719_o = ~res_i;
  /* pmem_ctrl.vhd:127:28  */
  assign n4721_o = data_i[3:0];
  /* pmem_ctrl.vhd:133:30  */
  assign n4722_o = program_counter_q[10:0];
  /* pmem_ctrl.vhd:133:49  */
  assign n4724_o = n4722_o + 11'b00000000001;
  /* p2.vhd:153:3  */
  assign n4725_o = program_counter_q[10:0];
  /* pmem_ctrl.vhd:128:9  */
  assign n4726_o = inc_pc_i ? n4724_o : n4725_o;
  /* p2.vhd:115:5  */
  assign n4727_o = n4726_o[7:0];
  /* p2.vhd:115:5  */
  assign n4728_o = program_counter_q[7:0];
  /* pmem_ctrl.vhd:125:9  */
  assign n4729_o = write_pch_i ? n4728_o : n4727_o;
  /* decoder.vhd:496:15  */
  assign n4730_o = n4726_o[10:8];
  /* decoder.vhd:474:22  */
  assign n4731_o = n4721_o[2:0];
  /* pmem_ctrl.vhd:125:9  */
  assign n4732_o = write_pch_i ? n4731_o : n4730_o;
  /* p2.vhd:155:5  */
  assign n4733_o = n4721_o[3];
  assign n4734_o = program_counter_q[11];
  /* pmem_ctrl.vhd:125:9  */
  assign n4735_o = write_pch_i ? n4733_o : n4734_o;
  assign n4736_o = {n4735_o, n4732_o, n4729_o};
  assign n4737_o = n4736_o[7:0];
  /* pmem_ctrl.vhd:123:9  */
  assign n4738_o = write_pcl_i ? data_i : n4737_o;
  assign n4739_o = n4736_o[11:8];
  assign n4740_o = program_counter_q[11:8];
  /* pmem_ctrl.vhd:123:9  */
  assign n4741_o = write_pcl_i ? n4740_o : n4739_o;
  assign n4743_o = {n4741_o, n4738_o};
  /* pmem_ctrl.vhd:120:7  */
  assign n4745_o = en_clk_i & write_pmem_addr_i;
  /* pmem_ctrl.vhd:165:7  */
  assign n4755_o = addr_type_i == 2'b00;
  /* pmem_ctrl.vhd:169:7  */
  assign n4757_o = addr_type_i == 2'b01;
  /* pmem_ctrl.vhd:175:7  */
  assign n4760_o = addr_type_i == 2'b10;
  assign n4761_o = {n4760_o, n4757_o, n4755_o};
  assign n4762_o = program_counter_q[7:0];
  /* pmem_ctrl.vhd:164:5  */
  always @*
    case (n4761_o)
      3'b100: n4763_o = data_i;
      3'b010: n4763_o = data_i;
      3'b001: n4763_o = n4762_o;
      default: n4763_o = n4762_o;
    endcase
  assign n4764_o = program_counter_q[11:8];
  /* pmem_ctrl.vhd:164:5  */
  always @*
    case (n4761_o)
      3'b100: n4765_o = 4'b0011;
      3'b010: n4765_o = n4764_o;
      3'b001: n4765_o = n4764_o;
      default: n4765_o = n4764_o;
    endcase
  /* pmem_ctrl.vhd:207:51  */
  assign n4769_o = program_counter_q[7:0];
  /* pmem_ctrl.vhd:209:63  */
  assign n4770_o = program_counter_q[11:8];
  /* pmem_ctrl.vhd:208:5  */
  assign n4772_o = read_pch_i ? n4770_o : 4'b1111;
  assign n4773_o = n4769_o[3:0];
  /* pmem_ctrl.vhd:206:5  */
  assign n4774_o = read_pcl_i ? n4773_o : n4772_o;
  assign n4775_o = n4769_o[7:4];
  /* pmem_ctrl.vhd:206:5  */
  assign n4777_o = read_pcl_i ? n4775_o : 4'b1111;
  assign n4778_o = {n4777_o, n4774_o};
  /* pmem_ctrl.vhd:204:5  */
  assign n4779_o = read_pmem_i ? pmem_data_i : n4778_o;
  /* pmem_ctrl.vhd:119:5  */
  assign n4782_o = en_clk_i ? n4743_o : program_counter_q;
  /* pmem_ctrl.vhd:119:5  */
  always @(posedge clk_i or posedge n4719_o)
    if (n4719_o)
      n4783_q <= 12'b000000000000;
    else
      n4783_q <= n4782_o;
  /* pmem_ctrl.vhd:115:5  */
  assign n4784_o = {n4765_o, n4763_o};
  /* pmem_ctrl.vhd:119:5  */
  assign n4785_o = n4745_o ? pmem_addr_s : pmem_addr_q;
  /* pmem_ctrl.vhd:119:5  */
  always @(posedge clk_i or posedge n4719_o)
    if (n4719_o)
      n4786_q <= 12'b000000000000;
    else
      n4786_q <= n4785_o;
endmodule
