// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_int
  (input  clk_i,
   input  res_i,
   input  en_clk_i,
   input  xtal_i,
   input  xtal_en_i,
   input  [2:0] clk_mstate_i,
   input  jtf_executed_i,
   input  tim_overflow_i,
   input  en_tcnti_i,
   input  dis_tcnti_i,
   input  int_n_i,
   input  ale_i,
   input  last_cycle_i,
   input  en_i_i,
   input  dis_i_i,
   input  retr_executed_i,
   input  int_executed_i,
   output tf_o,
   output ext_int_o,
   output tim_int_o,
   output int_pending_o,
   output int_in_progress_o
   );
  wire [1:0] int_state_s;
  wire [1:0] int_state_q;
  wire timer_flag_q;
  wire timer_overflow_q;
  wire timer_int_enable_q;
  wire int_q;
  wire int_enable_q;
  wire ale_q;
  wire int_type_q;
  wire int_in_progress_q;
  wire n4861_o;
  wire n4863_o;
  wire n4864_o;
  wire [1:0] n4866_o;
  wire n4868_o;
  wire [1:0] n4870_o;
  wire n4872_o;
  wire [1:0] n4874_o;
  wire n4876_o;
  wire [2:0] n4877_o;
  reg [1:0] n4879_o;
  wire n4882_o;
  wire n4885_o;
  wire n4887_o;
  wire n4888_o;
  wire n4889_o;
  wire n4890_o;
  wire n4891_o;
  wire n4893_o;
  wire n4895_o;
  wire n4897_o;
  wire n4899_o;
  wire n4901_o;
  wire n4903_o;
  wire n4904_o;
  wire n4905_o;
  wire n4906_o;
  wire n4908_o;
  wire n4915_o;
  wire n4916_o;
  wire n4917_o;
  wire n4919_o;
  wire n4920_o;
  wire n4922_o;
  wire n4953_o;
  wire n4955_o;
  wire n4956_o;
  wire n4957_o;
  wire n4965_o;
  wire n4966_o;
  wire n4968_o;
  wire n4984_o;
  wire n4985_o;
  wire n4987_o;
  wire n4989_o;
  wire n4990_o;
  wire [1:0] n4991_o;
  reg [1:0] n4992_q;
  wire n4993_o;
  reg n4994_q;
  wire n4995_o;
  reg n4996_q;
  wire n4997_o;
  reg n4998_q;
  wire n4999_o;
  reg n5000_q;
  wire n5001_o;
  reg n5002_q;
  wire n5003_o;
  reg n5004_q;
  wire n5005_o;
  reg n5006_q;
  wire n5007_o;
  reg n5008_q;
  assign tf_o = n4984_o;
  assign ext_int_o = int_type_q;
  assign tim_int_o = n4985_o;
  assign int_pending_o = n4987_o;
  assign int_in_progress_o = n4990_o;
  /* int.vhd:91:10  */
  assign int_state_s = n4879_o; // (signal)
  /* int.vhd:92:10  */
  assign int_state_q = n4992_q; // (signal)
  /* int.vhd:94:10  */
  assign timer_flag_q = n4994_q; // (signal)
  /* int.vhd:95:10  */
  assign timer_overflow_q = n4996_q; // (signal)
  /* int.vhd:96:10  */
  assign timer_int_enable_q = n4998_q; // (signal)
  /* int.vhd:97:10  */
  assign int_q = n5000_q; // (signal)
  /* int.vhd:98:10  */
  assign int_enable_q = n5002_q; // (signal)
  /* int.vhd:99:10  */
  assign ale_q = n5004_q; // (signal)
  /* int.vhd:100:10  */
  assign int_type_q = n5006_q; // (signal)
  /* int.vhd:101:10  */
  assign int_in_progress_q = n5008_q; // (signal)
  /* int.vhd:123:30  */
  assign n4861_o = last_cycle_i & int_in_progress_q;
  /* int.vhd:124:42  */
  assign n4863_o = clk_mstate_i == 3'b100;
  /* int.vhd:124:25  */
  assign n4864_o = n4863_o & n4861_o;
  /* int.vhd:123:9  */
  assign n4866_o = n4864_o ? 2'b01 : int_state_q;
  /* int.vhd:122:7  */
  assign n4868_o = int_state_q == 2'b00;
  /* int.vhd:129:9  */
  assign n4870_o = int_executed_i ? 2'b10 : int_state_q;
  /* int.vhd:128:7  */
  assign n4872_o = int_state_q == 2'b01;
  /* int.vhd:134:9  */
  assign n4874_o = retr_executed_i ? 2'b00 : int_state_q;
  /* int.vhd:133:7  */
  assign n4876_o = int_state_q == 2'b10;
  assign n4877_o = {n4876_o, n4872_o, n4868_o};
  /* int.vhd:121:5  */
  always @*
    case (n4877_o)
      3'b100: n4879_o = n4874_o;
      3'b010: n4879_o = n4870_o;
      3'b001: n4879_o = n4866_o;
      default: n4879_o = 2'b00;
    endcase
  /* int.vhd:158:14  */
  assign n4882_o = ~res_i;
  /* int.vhd:174:9  */
  assign n4885_o = tim_overflow_i ? 1'b1 : timer_flag_q;
  /* int.vhd:172:9  */
  assign n4887_o = jtf_executed_i ? 1'b0 : n4885_o;
  /* int.vhd:178:24  */
  assign n4888_o = ~int_type_q;
  /* int.vhd:178:36  */
  assign n4889_o = int_executed_i & n4888_o;
  /* int.vhd:179:11  */
  assign n4890_o = ~timer_int_enable_q;
  /* int.vhd:178:56  */
  assign n4891_o = n4889_o | n4890_o;
  /* int.vhd:181:9  */
  assign n4893_o = tim_overflow_i ? 1'b1 : timer_overflow_q;
  /* int.vhd:178:9  */
  assign n4895_o = n4891_o ? 1'b0 : n4893_o;
  /* int.vhd:187:9  */
  assign n4897_o = en_tcnti_i ? 1'b1 : timer_int_enable_q;
  /* int.vhd:185:9  */
  assign n4899_o = dis_tcnti_i ? 1'b0 : n4897_o;
  /* int.vhd:193:9  */
  assign n4901_o = en_i_i ? 1'b1 : int_enable_q;
  /* int.vhd:191:9  */
  assign n4903_o = dis_i_i ? 1'b0 : n4901_o;
  /* int.vhd:199:22  */
  assign n4904_o = int_enable_q & int_q;
  /* int.vhd:199:40  */
  assign n4905_o = n4904_o | timer_overflow_q;
  /* int.vhd:202:14  */
  assign n4906_o = ~int_in_progress_q;
  /* int.vhd:203:45  */
  assign n4908_o = int_enable_q & int_q;
  /* t48_pack-p.vhd:66:5  */
  assign n4915_o = n4908_o ? 1'b1 : 1'b0;
  /* int.vhd:199:9  */
  assign n4916_o = n4917_o ? n4915_o : int_type_q;
  /* int.vhd:199:9  */
  assign n4917_o = n4905_o & n4906_o;
  /* int.vhd:199:9  */
  assign n4919_o = n4905_o ? 1'b1 : int_in_progress_q;
  /* int.vhd:197:9  */
  assign n4920_o = retr_executed_i ? int_type_q : n4916_o;
  /* int.vhd:197:9  */
  assign n4922_o = retr_executed_i ? 1'b0 : n4919_o;
  /* int.vhd:224:14  */
  assign n4953_o = ~res_i;
  /* int.vhd:232:25  */
  assign n4955_o = ale_q & last_cycle_i;
  /* int.vhd:233:22  */
  assign n4956_o = ~ale_i;
  /* int.vhd:233:18  */
  assign n4957_o = n4956_o & n4955_o;
  /* t48_pack-p.vhd:75:5  */
  assign n4965_o = int_n_i ? 1'b1 : 1'b0;
  /* int.vhd:234:20  */
  assign n4966_o = ~n4965_o;
  /* int.vhd:229:7  */
  assign n4968_o = xtal_en_i & n4957_o;
  /* t48_pack-p.vhd:66:5  */
  assign n4984_o = timer_flag_q ? 1'b1 : 1'b0;
  /* int.vhd:249:35  */
  assign n4985_o = ~int_type_q;
  /* int.vhd:250:36  */
  assign n4987_o = int_state_q == 2'b01;
  /* int.vhd:251:58  */
  assign n4989_o = int_state_q != 2'b00;
  /* int.vhd:251:42  */
  assign n4990_o = n4989_o & int_in_progress_q;
  /* int.vhd:167:5  */
  assign n4991_o = en_clk_i ? int_state_s : int_state_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n4992_q <= 2'b00;
    else
      n4992_q <= n4991_o;
  /* int.vhd:167:5  */
  assign n4993_o = en_clk_i ? n4887_o : timer_flag_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n4994_q <= 1'b0;
    else
      n4994_q <= n4993_o;
  /* int.vhd:167:5  */
  assign n4995_o = en_clk_i ? n4895_o : timer_overflow_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n4996_q <= 1'b0;
    else
      n4996_q <= n4995_o;
  /* int.vhd:167:5  */
  assign n4997_o = en_clk_i ? n4899_o : timer_int_enable_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n4998_q <= 1'b0;
    else
      n4998_q <= n4997_o;
  /* int.vhd:228:5  */
  assign n4999_o = n4968_o ? n4966_o : int_q;
  /* int.vhd:228:5  */
  always @(posedge xtal_i or posedge n4953_o)
    if (n4953_o)
      n5000_q <= 1'b0;
    else
      n5000_q <= n4999_o;
  /* int.vhd:167:5  */
  assign n5001_o = en_clk_i ? n4903_o : int_enable_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n5002_q <= 1'b0;
    else
      n5002_q <= n5001_o;
  /* int.vhd:228:5  */
  assign n5003_o = xtal_en_i ? ale_i : ale_q;
  /* int.vhd:228:5  */
  always @(posedge xtal_i or posedge n4953_o)
    if (n4953_o)
      n5004_q <= 1'b0;
    else
      n5004_q <= n5003_o;
  /* int.vhd:167:5  */
  assign n5005_o = en_clk_i ? n4920_o : int_type_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n5006_q <= 1'b0;
    else
      n5006_q <= n5005_o;
  /* int.vhd:167:5  */
  assign n5007_o = en_clk_i ? n4922_o : int_in_progress_q;
  /* int.vhd:167:5  */
  always @(posedge clk_i or posedge n4882_o)
    if (n4882_o)
      n5008_q <= 1'b0;
    else
      n5008_q <= n5007_o;
endmodule