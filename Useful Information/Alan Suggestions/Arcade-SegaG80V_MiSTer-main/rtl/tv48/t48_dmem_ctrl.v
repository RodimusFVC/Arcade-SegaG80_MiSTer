// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_dmem_ctrl
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  [7:0] data_i,
   input  write_dmem_addr_i,
   input  write_dmem_i,
   input  read_dmem_i,
   input  [1:0] addr_type_i,
   input  bank_select_i,
   input  [7:0] dmem_data_i,
   output [7:0] data_o,
   output [7:0] dmem_addr_o,
   output dmem_we_o,
   output [7:0] dmem_data_o);
  wire [7:0] dmem_addr_s;
  wire [7:0] dmem_addr_q;
  wire n4391_o;
  wire [2:0] n4392_o;
  localparam [7:0] n4393_o = 8'b00000000;
  wire [1:0] n4396_o;
  wire [1:0] n4397_o;
  wire [2:0] n4398_o;
  wire n4400_o;
  wire [2:0] n4401_o;
  wire [5:0] n4404_o;
  wire [5:0] n4406_o;
  localparam [7:0] n4407_o = 8'b00000000;
  wire [1:0] n4408_o;
  wire n4410_o;
  wire n4413_o;
  wire [3:0] n4414_o;
  wire n4415_o;
  wire n4416_o;
  wire n4417_o;
  wire n4418_o;
  reg n4419_o;
  wire [1:0] n4420_o;
  wire [1:0] n4421_o;
  wire [1:0] n4422_o;
  wire [1:0] n4423_o;
  reg [1:0] n4424_o;
  wire [1:0] n4425_o;
  wire [1:0] n4426_o;
  wire [1:0] n4427_o;
  reg [1:0] n4428_o;
  wire n4429_o;
  wire n4430_o;
  wire n4431_o;
  wire n4432_o;
  reg n4433_o;
  wire [1:0] n4434_o;
  wire [1:0] n4435_o;
  wire [1:0] n4436_o;
  reg [1:0] n4437_o;
  wire n4447_o;
  wire n4450_o;
  wire n4455_o;
  wire [7:0] n4456_o;
  wire [7:0] n4457_o;
  wire n4466_o;
  wire [7:0] n4467_o;
  wire [7:0] n4468_o;
  reg [7:0] n4469_q;
  assign data_o = n4457_o;
  assign dmem_addr_o = n4456_o;
  assign dmem_we_o = n4466_o;
  assign dmem_data_o = data_i;
  /* dmem_ctrl.vhd:91:10  */
  assign dmem_addr_s = n4467_o; // (signal)
  /* dmem_ctrl.vhd:92:10  */
  assign dmem_addr_q = n4469_q; // (signal)
  /* dmem_ctrl.vhd:112:7  */
  assign n4391_o = addr_type_i == 2'b00;
  /* dmem_ctrl.vhd:117:44  */
  assign n4392_o = data_i[2:0];
  /* decoder.vhd:147:5  */
  assign n4396_o = n4393_o[4:3];
  /* dmem_ctrl.vhd:119:9  */
  assign n4397_o = bank_select_i ? 2'b11 : n4396_o;
  /* decoder.vhd:145:5  */
  assign n4398_o = n4393_o[7:5];
  /* dmem_ctrl.vhd:115:7  */
  assign n4400_o = addr_type_i == 2'b01;
  /* dmem_ctrl.vhd:126:53  */
  assign n4401_o = data_i[2:0];
  /* decoder.vhd:134:5  */
  assign n4404_o = {2'b00, n4401_o, 1'b0};
  /* dmem_ctrl.vhd:128:51  */
  assign n4406_o = n4404_o + 6'b001000;
  /* decoder.vhd:127:5  */
  assign n4408_o = n4407_o[7:6];
  /* dmem_ctrl.vhd:124:7  */
  assign n4410_o = addr_type_i == 2'b10;
  /* dmem_ctrl.vhd:133:7  */
  assign n4413_o = addr_type_i == 2'b11;
  /* decoder.vhd:117:5  */
  assign n4414_o = {n4413_o, n4410_o, n4400_o, n4391_o};
  /* decoder.vhd:116:5  */
  assign n4415_o = data_i[0];
  /* decoder.vhd:115:5  */
  assign n4416_o = n4392_o[0];
  /* decoder.vhd:113:5  */
  assign n4417_o = n4406_o[0];
  /* decoder.vhd:112:5  */
  assign n4418_o = dmem_addr_q[0];
  /* dmem_ctrl.vhd:111:5  */
  always @*
    case (n4414_o)
      4'b1000: n4419_o = 1'b1;
      4'b0100: n4419_o = n4417_o;
      4'b0010: n4419_o = n4416_o;
      4'b0001: n4419_o = n4415_o;
      default: n4419_o = n4418_o;
    endcase
  /* decoder.vhd:108:5  */
  assign n4420_o = data_i[2:1];
  /* decoder.vhd:107:5  */
  assign n4421_o = n4392_o[2:1];
  /* decoder.vhd:106:5  */
  assign n4422_o = n4406_o[2:1];
  /* decoder.vhd:105:5  */
  assign n4423_o = dmem_addr_q[2:1];
  /* dmem_ctrl.vhd:111:5  */
  always @*
    case (n4414_o)
      4'b1000: n4424_o = n4423_o;
      4'b0100: n4424_o = n4422_o;
      4'b0010: n4424_o = n4421_o;
      4'b0001: n4424_o = n4420_o;
      default: n4424_o = n4423_o;
    endcase
  /* decoder.vhd:101:5  */
  assign n4425_o = data_i[4:3];
  /* decoder.vhd:100:5  */
  assign n4426_o = n4406_o[4:3];
  /* decoder.vhd:99:5  */
  assign n4427_o = dmem_addr_q[4:3];
  /* dmem_ctrl.vhd:111:5  */
  always @*
    case (n4414_o)
      4'b1000: n4428_o = n4427_o;
      4'b0100: n4428_o = n4426_o;
      4'b0010: n4428_o = n4397_o;
      4'b0001: n4428_o = n4425_o;
      default: n4428_o = n4427_o;
    endcase
  /* decoder.vhd:97:5  */
  assign n4429_o = data_i[5];
  /* decoder.vhd:96:5  */
  assign n4430_o = n4398_o[0];
  /* decoder.vhd:95:5  */
  assign n4431_o = n4406_o[5];
  /* decoder.vhd:94:5  */
  assign n4432_o = dmem_addr_q[5];
  /* dmem_ctrl.vhd:111:5  */
  always @*
    case (n4414_o)
      4'b1000: n4433_o = n4432_o;
      4'b0100: n4433_o = n4431_o;
      4'b0010: n4433_o = n4430_o;
      4'b0001: n4433_o = n4429_o;
      default: n4433_o = n4432_o;
    endcase
  /* decoder.vhd:92:5  */
  assign n4434_o = data_i[7:6];
  /* decoder.vhd:91:5  */
  assign n4435_o = n4398_o[2:1];
  /* decoder.vhd:90:5  */
  assign n4436_o = dmem_addr_q[7:6];
  /* dmem_ctrl.vhd:111:5  */
  always @*
    case (n4414_o)
      4'b1000: n4437_o = n4436_o;
      4'b0100: n4437_o = n4408_o;
      4'b0010: n4437_o = n4435_o;
      4'b0001: n4437_o = n4434_o;
      default: n4437_o = n4436_o;
    endcase
  /* dmem_ctrl.vhd:165:14  */
  assign n4447_o = ~res_i;
  /* dmem_ctrl.vhd:169:7  */
  assign n4450_o = en_clk_i & write_dmem_addr_i;
  /* dmem_ctrl.vhd:188:41  */
  assign n4455_o = en_clk_i & write_dmem_addr_i;
  /* dmem_ctrl.vhd:188:18  */
  assign n4456_o = n4455_o ? dmem_addr_s : dmem_addr_q;
  /* dmem_ctrl.vhd:196:18  */
  assign n4457_o = read_dmem_i ? dmem_data_i : 8'b11111111;
  /* t48_pack-p.vhd:66:5  */
  assign n4466_o = write_dmem_i ? 1'b1 : 1'b0;
  assign n4467_o = {n4437_o, n4433_o, n4428_o, n4424_o, n4419_o};
  /* dmem_ctrl.vhd:168:5  */
  assign n4468_o = n4450_o ? dmem_addr_s : dmem_addr_q;
  /* dmem_ctrl.vhd:168:5  */
  always @(posedge clk_i or posedge n4447_o)
    if (n4447_o)
      n4469_q <= 8'b00000000;
    else
      n4469_q <= n4468_o;
endmodule