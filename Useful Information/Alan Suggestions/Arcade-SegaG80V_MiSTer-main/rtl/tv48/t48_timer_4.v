// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_timer_4
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  t1_i,
   input  [2:0] clk_mstate_i,
   input  [7:0] data_i,
   input  read_timer_i,
   input  write_timer_i,
   input  start_t_i,
   input  start_cnt_i,
   input  stop_tcnt_i,
   output [7:0] data_o,
   output overflow_o);
  wire [7:0] counter_q;
  wire overflow_q;
  wire increment_s;
  wire [1:0] inc_sel_q;
  wire t1_q;
  wire t1_inc_s;
  wire [4:0] prescaler_q;
  wire pre_inc_s;
  wire n4474_o;
  wire n4476_o;
  wire n4478_o;
  wire n4479_o;
  wire n4480_o;
  wire n4483_o;
  wire n4485_o;
  wire n4489_o;
  wire n4491_o;
  wire n4492_o;
  wire n4495_o;
  wire n4497_o;
  wire n4499_o;
  wire [2:0] n4500_o;
  reg n4503_o;
  wire n4507_o;
  wire [7:0] n4510_o;
  wire n4512_o;
  wire n4515_o;
  wire [7:0] n4516_o;
  wire n4518_o;
  wire [7:0] n4519_o;
  wire n4521_o;
  wire n4524_o;
  wire n4526_o;
  wire n4528_o;
  wire n4531_o;
  wire [4:0] n4533_o;
  wire [4:0] n4534_o;
  wire [4:0] n4536_o;
  wire [1:0] n4538_o;
  wire [1:0] n4540_o;
  wire [1:0] n4542_o;
  wire n4546_o;
  wire [7:0] n4564_o;
  wire n4573_o;
  wire [7:0] n4574_o;
  reg [7:0] n4575_q;
  wire n4576_o;
  reg n4577_q;
  wire [1:0] n4578_o;
  reg [1:0] n4579_q;
  wire n4580_o;
  reg n4581_q;
  wire [4:0] n4582_o;
  reg [4:0] n4583_q;
  assign data_o = n4564_o;
  assign overflow_o = n4573_o;
  /* timer.vhd:89:10  */
  assign counter_q = n4575_q; // (signal)
  /* timer.vhd:90:10  */
  assign overflow_q = n4577_q; // (signal)
  /* timer.vhd:94:10  */
  assign increment_s = n4503_o; // (signal)
  /* timer.vhd:95:10  */
  assign inc_sel_q = n4579_q; // (signal)
  /* timer.vhd:98:10  */
  assign t1_q = n4581_q; // (signal)
  /* timer.vhd:99:10  */
  assign t1_inc_s = n4485_o; // (signal)
  /* timer.vhd:102:10  */
  assign prescaler_q = n4583_q; // (signal)
  /* timer.vhd:103:10  */
  assign pre_inc_s = n4492_o; // (signal)
  /* timer.vhd:134:48  */
  assign n4474_o = clk_mstate_i == 3'b100;
  /* timer.vhd:134:31  */
  assign n4476_o = n4474_o & 1'b1;
  /* timer.vhd:133:59  */
  assign n4478_o = 1'b0 | n4476_o;
  /* timer.vhd:136:30  */
  assign n4479_o = ~t1_i;
  /* timer.vhd:136:21  */
  assign n4480_o = n4479_o & t1_q;
  /* timer.vhd:136:7  */
  assign n4483_o = n4480_o ? 1'b1 : 1'b0;
  /* timer.vhd:133:5  */
  assign n4485_o = n4478_o ? n4483_o : 1'b0;
  /* timer.vhd:146:29  */
  assign n4489_o = clk_mstate_i == 3'b100;
  /* timer.vhd:146:55  */
  assign n4491_o = prescaler_q == 5'b11111;
  /* timer.vhd:146:39  */
  assign n4492_o = n4491_o & n4489_o;
  /* timer.vhd:163:7  */
  assign n4495_o = inc_sel_q == 2'b00;
  /* timer.vhd:165:7  */
  assign n4497_o = inc_sel_q == 2'b01;
  /* timer.vhd:167:7  */
  assign n4499_o = inc_sel_q == 2'b10;
  assign n4500_o = {n4499_o, n4497_o, n4495_o};
  /* timer.vhd:162:5  */
  always @*
    case (n4500_o)
      3'b100: n4503_o = t1_inc_s;
      3'b010: n4503_o = pre_inc_s;
      3'b001: n4503_o = 1'b0;
      default: n4503_o = 1'b0;
    endcase
  /* timer.vhd:186:14  */
  assign n4507_o = ~res_i;
  /* timer.vhd:203:37  */
  assign n4510_o = counter_q + 8'b00000001;
  /* timer.vhd:205:24  */
  assign n4512_o = counter_q == 8'b11111111;
  /* timer.vhd:205:11  */
  assign n4515_o = n4512_o ? 1'b1 : 1'b0;
  /* timer.vhd:202:9  */
  assign n4516_o = increment_s ? n4510_o : counter_q;
  /* timer.vhd:202:9  */
  assign n4518_o = increment_s ? n4515_o : 1'b0;
  /* timer.vhd:199:9  */
  assign n4519_o = write_timer_i ? data_i : n4516_o;
  /* timer.vhd:199:9  */
  assign n4521_o = write_timer_i ? 1'b0 : n4518_o;
  /* timer.vhd:213:52  */
  assign n4524_o = clk_mstate_i == 3'b011;
  /* timer.vhd:213:35  */
  assign n4526_o = n4524_o & 1'b1;
  /* timer.vhd:212:63  */
  assign n4528_o = 1'b0 | n4526_o;
  /* timer.vhd:221:28  */
  assign n4531_o = clk_mstate_i == 3'b010;
  /* timer.vhd:222:39  */
  assign n4533_o = prescaler_q + 5'b00001;
  /* timer.vhd:221:9  */
  assign n4534_o = n4531_o ? n4533_o : prescaler_q;
  /* timer.vhd:218:9  */
  assign n4536_o = start_t_i ? 5'b00000 : n4534_o;
  /* timer.vhd:231:9  */
  assign n4538_o = stop_tcnt_i ? 2'b00 : inc_sel_q;
  /* timer.vhd:229:9  */
  assign n4540_o = start_cnt_i ? 2'b10 : n4538_o;
  /* timer.vhd:227:9  */
  assign n4542_o = start_t_i ? 2'b01 : n4540_o;
  /* timer.vhd:194:7  */
  assign n4546_o = en_clk_i & n4528_o;
  /* timer.vhd:248:17  */
  assign n4564_o = read_timer_i ? counter_q : 8'b11111111;
  /* t48_pack-p.vhd:66:5  */
  assign n4573_o = overflow_q ? 1'b1 : 1'b0;
  /* timer.vhd:193:5  */
  assign n4574_o = en_clk_i ? n4519_o : counter_q;
  /* timer.vhd:193:5  */
  always @(posedge clk_i or posedge n4507_o)
    if (n4507_o)
      n4575_q <= 8'b00000000;
    else
      n4575_q <= n4574_o;
  /* timer.vhd:193:5  */
  assign n4576_o = en_clk_i ? n4521_o : overflow_q;
  /* timer.vhd:193:5  */
  always @(posedge clk_i or posedge n4507_o)
    if (n4507_o)
      n4577_q <= 1'b0;
    else
      n4577_q <= n4576_o;
  /* timer.vhd:193:5  */
  assign n4578_o = en_clk_i ? n4542_o : inc_sel_q;
  /* timer.vhd:193:5  */
  always @(posedge clk_i or posedge n4507_o)
    if (n4507_o)
      n4579_q <= 2'b00;
    else
      n4579_q <= n4578_o;
  /* timer.vhd:193:5  */
  assign n4580_o = n4546_o ? t1_i : t1_q;
  /* timer.vhd:193:5  */
  always @(posedge clk_i or posedge n4507_o)
    if (n4507_o)
      n4581_q <= 1'b0;
    else
      n4581_q <= n4580_o;
  /* timer.vhd:193:5  */
  assign n4582_o = en_clk_i ? n4536_o : prescaler_q;
  /* timer.vhd:193:5  */
  always @(posedge clk_i or posedge n4507_o)
    if (n4507_o)
      n4583_q <= 5'b00000;
    else
      n4583_q <= n4582_o;
endmodule