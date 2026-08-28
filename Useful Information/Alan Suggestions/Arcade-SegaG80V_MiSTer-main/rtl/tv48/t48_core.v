// The following code is a copy of the T48 core by Arnim Läuger which has been automatically converted to Verilog for ease of simulation
// https://github.com/devsaurus/t48

`timescale 1ps / 1ps

module t48_core
  (input  xtal_i,
   input  xtal_en_i,
   input  reset_i,
   input  t0_i,
   input  int_n_i,
   input  ea_i,
   input  [7:0] db_i,
   input  t1_i,
   input  [7:0] p2_i,
   input  [7:0] p1_i,
   input  clk_i,
   input  en_clk_i,
   input  [7:0] dmem_data_i,
   input  [7:0] pmem_data_i,
   output t0_o,
   output t0_dir_o,
   output rd_n_o,
   output psen_n_o,
   output wr_n_o,
   output ale_o,
   output [7:0] db_o,
   output db_dir_o,
   output [7:0] p2_o,
   output p2l_low_imp_o,
   output p2h_low_imp_o,
   output [7:0] p1_o,
   output p1_low_imp_o,
   output prog_n_o,
   output xtal3_o,
   output [7:0] dmem_addr_o,
   output dmem_we_o,
   output [7:0] dmem_data_o,
   output [11:0] pmem_addr_o
  );
  wire [7:0] t48_data_s;
  wire xtal_en_s;
  wire en_clk_s;
  wire [7:0] alu_data_s;
  wire alu_write_accu_s;
  wire alu_write_shadow_s;
  wire alu_write_temp_reg_s;
  wire alu_read_alu_s;
  wire alu_carry_s;
  wire alu_aux_carry_s;
  wire [3:0] alu_op_s;
  wire alu_use_carry_s;
  wire alu_da_high_s;
  wire alu_da_overflow_s;
  wire alu_accu_low_s;
  wire alu_p06_temp_reg_s;
  wire alu_p60_temp_reg_s;
  wire bus_write_bus_s;
  wire bus_read_bus_s;
  wire bus_output_pcl_s;
  wire bus_bidir_bus_s;
  wire [7:0] bus_data_s;
  wire [2:0] cnd_comp_value_s;
  wire clk_multi_cycle_s;
  wire clk_assert_psen_s;
  wire clk_assert_prog_s;
  wire clk_assert_rd_s;
  wire clk_assert_wr_s;
  wire [2:0] clk_mstate_s;
  wire clk_second_cycle_s;
  wire psen_s;
  wire prog_s;
  wire rd_s;
  wire wr_s;
  wire ale_s;
  wire xtal3_s;
  wire cnd_compute_take_s;
  wire [3:0] cnd_branch_cond_s;
  wire cnd_take_branch_s;
  wire cnd_f1_s;
  wire cnd_tf_s;
  wire dm_write_dmem_addr_s;
  wire dm_write_dmem_s;
  wire dm_read_dmem_s;
  wire [1:0] dm_addr_type_s;
  wire [7:0] dm_data_s;
  wire [7:0] dec_data_s;
  wire p1_write_p1_s;
  wire p1_read_p1_s;
  wire p1_read_reg_s;
  wire [7:0] p1_data_s;
  wire p2_write_p2_s;
  wire p2_write_exp_s;
  wire p2_read_p2_s;
  wire p2_read_reg_s;
  wire p2_read_exp_s;
  wire p2_output_pch_s;
  wire [7:0] p2_data_s;
  wire pm_write_pcl_s;
  wire pm_read_pcl_s;
  wire pm_write_pch_s;
  wire pm_read_pch_s;
  wire pm_read_pmem_s;
  wire pm_inc_pc_s;
  wire pm_write_pmem_addr_s;
  wire [7:0] pm_data_s;
  wire [1:0] pm_addr_type_s;
  wire [11:0] pmem_addr_s;
  wire psw_read_psw_s;
  wire psw_read_sp_s;
  wire psw_write_psw_s;
  wire psw_write_sp_s;
  wire psw_carry_s;
  wire psw_aux_carry_s;
  wire psw_f0_s;
  wire psw_bs_s;
  wire psw_special_data_s;
  wire psw_inc_stackp_s;
  wire psw_dec_stackp_s;
  wire psw_write_carry_s;
  wire psw_write_aux_carry_s;
  wire psw_write_f0_s;
  wire psw_write_bs_s;
  wire [7:0] psw_data_s;
  wire tim_overflow_s;
  wire tim_of_s;
  wire tim_read_timer_s;
  wire tim_write_timer_s;
  wire tim_start_t_s;
  wire tim_start_cnt_s;
  wire tim_stop_tcnt_s;
  wire [7:0] tim_data_s;
  wire n26_o;
  wire n34_o;
  wire [7:0] alu_b_n35;
  wire alu_b_n36;
  wire alu_b_n37;
  wire alu_b_n38;
  wire [7:0] alu_b_data_o;
  wire alu_b_carry_o;
  wire alu_b_aux_carry_o;
  wire alu_b_da_overflow_o;
  wire [7:0] bus_mux_b_n47;
  wire [7:0] bus_mux_b_data_o;
  wire clock_ctrl_b_n50;
  wire clock_ctrl_b_n51;
  wire [2:0] clock_ctrl_b_n52;
  wire clock_ctrl_b_n53;
  wire clock_ctrl_b_n54;
  wire clock_ctrl_b_n55;
  wire clock_ctrl_b_n56;
  wire clock_ctrl_b_n57;
  wire clock_ctrl_b_n58;
  wire clock_ctrl_b_xtal3_o;
  wire clock_ctrl_b_t0_o;
  wire [2:0] clock_ctrl_b_mstate_o;
  wire clock_ctrl_b_second_cycle_o;
  wire clock_ctrl_b_ale_o;
  wire clock_ctrl_b_psen_o;
  wire clock_ctrl_b_prog_o;
  wire clock_ctrl_b_rd_o;
  wire clock_ctrl_b_wr_o;
  wire cond_branch_b_n77;
  wire [3:0] n83_o;
  wire [3:0] n85_o;
  localparam [8:0] n87_o = 9'bXX01ZX01X;
  wire [3:0] n94_o;
  wire [3:0] n96_o;
  localparam [8:0] n98_o = 9'bXX01ZX01X;
  wire cond_branch_b_take_branch_o;
  wire [7:0] use_db_bus_db_bus_b_n102;
  wire [7:0] n103_o;
  wire [7:0] use_db_bus_db_bus_b_n104;
  wire use_db_bus_db_bus_b_n105;
  wire [7:0] use_db_bus_db_bus_b_data_o;
  wire [7:0] use_db_bus_db_bus_b_db_o;
  wire use_db_bus_db_bus_b_db_dir_o;
  wire decoder_b_n112;
  wire [7:0] decoder_b_n113;
  wire decoder_b_n114;
  wire decoder_b_n115;
  wire decoder_b_n116;
  wire decoder_b_n117;
  wire decoder_b_n118;
  wire decoder_b_n119;
  wire decoder_b_n120;
  wire decoder_b_n121;
  wire decoder_b_n122;
  wire decoder_b_n123;
  wire decoder_b_n124;
  wire decoder_b_n125;
  wire decoder_b_n126;
  wire decoder_b_n127;
  wire decoder_b_n128;
  wire decoder_b_n129;
  wire decoder_b_n130;
  wire decoder_b_n131;
  wire decoder_b_n132;
  wire decoder_b_n133;
  wire decoder_b_n134;
  wire decoder_b_n135;
  wire decoder_b_n136;
  wire [3:0] decoder_b_n137;
  wire decoder_b_n138;
  wire decoder_b_n139;
  wire decoder_b_n140;
  wire decoder_b_n141;
  wire decoder_b_n142;
  wire decoder_b_n143;
  wire decoder_b_n144;
  wire decoder_b_n145;
  wire decoder_b_n146;
  wire decoder_b_n147;
  wire decoder_b_n148;
  wire decoder_b_n149;
  wire decoder_b_n150;
  wire [3:0] decoder_b_n151;
  wire [2:0] decoder_b_n152;
  wire decoder_b_n153;
  wire decoder_b_n154;
  wire [1:0] decoder_b_n155;
  wire decoder_b_n156;
  wire decoder_b_n157;
  wire decoder_b_n158;
  wire decoder_b_n159;
  wire decoder_b_n160;
  wire decoder_b_n161;
  wire decoder_b_n162;
  wire decoder_b_n163;
  wire decoder_b_n164;
  wire decoder_b_n165;
  wire decoder_b_n166;
  wire [1:0] decoder_b_n167;
  wire decoder_b_n168;
  wire decoder_b_n169;
  wire decoder_b_n170;
  wire decoder_b_n171;
  wire decoder_b_n172;
  wire decoder_b_n173;
  wire decoder_b_n174;
  wire decoder_b_t0_dir_o;
  wire [7:0] decoder_b_data_o;
  wire decoder_b_alu_write_accu_o;
  wire decoder_b_alu_write_shadow_o;
  wire decoder_b_alu_write_temp_reg_o;
  wire decoder_b_alu_read_alu_o;
  wire decoder_b_bus_write_bus_o;
  wire decoder_b_bus_read_bus_o;
  wire decoder_b_dm_write_dmem_addr_o;
  wire decoder_b_dm_write_dmem_o;
  wire decoder_b_dm_read_dmem_o;
  wire decoder_b_p1_write_p1_o;
  wire decoder_b_p1_read_p1_o;
  wire decoder_b_p2_write_p2_o;
  wire decoder_b_p2_write_exp_o;
  wire decoder_b_p2_read_p2_o;
  wire decoder_b_p2_read_exp_o;
  wire decoder_b_pm_write_pcl_o;
  wire decoder_b_pm_read_pcl_o;
  wire decoder_b_pm_write_pch_o;
  wire decoder_b_pm_read_pch_o;
  wire decoder_b_pm_read_pmem_o;
  wire decoder_b_psw_read_psw_o;
  wire decoder_b_psw_read_sp_o;
  wire decoder_b_psw_write_psw_o;
  wire decoder_b_psw_write_sp_o;
  wire [3:0] decoder_b_alu_op_o;
  wire decoder_b_alu_use_carry_o;
  wire decoder_b_alu_da_high_o;
  wire decoder_b_alu_accu_low_o;
  wire decoder_b_alu_p06_temp_reg_o;
  wire decoder_b_alu_p60_temp_reg_o;
  wire decoder_b_bus_output_pcl_o;
  wire decoder_b_bus_bidir_bus_o;
  wire decoder_b_clk_multi_cycle_o;
  wire decoder_b_clk_assert_psen_o;
  wire decoder_b_clk_assert_prog_o;
  wire decoder_b_clk_assert_rd_o;
  wire decoder_b_clk_assert_wr_o;
  wire decoder_b_cnd_compute_take_o;
  wire [3:0] decoder_b_cnd_branch_cond_o;
  wire [2:0] decoder_b_cnd_comp_value_o;
  wire decoder_b_cnd_f1_o;
  wire decoder_b_cnd_tf_o;
  wire [1:0] decoder_b_dm_addr_type_o;
  wire decoder_b_p1_read_reg_o;
  wire decoder_b_p2_read_reg_o;
  wire decoder_b_p2_output_pch_o;
  wire decoder_b_pm_inc_pc_o;
  wire decoder_b_pm_write_pmem_addr_o;
  wire [1:0] decoder_b_pm_addr_type_o;
  wire decoder_b_psw_special_data_o;
  wire decoder_b_psw_inc_stackp_o;
  wire decoder_b_psw_dec_stackp_o;
  wire decoder_b_psw_write_carry_o;
  wire decoder_b_psw_write_aux_carry_o;
  wire decoder_b_psw_write_f0_o;
  wire decoder_b_psw_write_bs_o;
  wire decoder_b_tim_read_timer_o;
  wire decoder_b_tim_write_timer_o;
  wire decoder_b_tim_start_t_o;
  wire decoder_b_tim_start_cnt_o;
  wire decoder_b_tim_stop_tcnt_o;
  wire [7:0] dmem_ctrl_b_n301;
  wire [7:0] dmem_ctrl_b_n302;
  wire dmem_ctrl_b_n303;
  wire [7:0] dmem_ctrl_b_n304;
  wire [7:0] dmem_ctrl_b_data_o;
  wire [7:0] dmem_ctrl_b_dmem_addr_o;
  wire dmem_ctrl_b_dmem_we_o;
  wire [7:0] dmem_ctrl_b_dmem_data_o;
  wire [3:0] n318_o;
  wire [3:0] n320_o;
  localparam [8:0] n322_o = 9'bXX01ZX01X;
  wire [7:0] use_timer_timer_b_n324;
  wire use_timer_timer_b_n325;
  wire [7:0] use_timer_timer_b_data_o;
  wire use_timer_timer_b_overflow_o;
  wire n337_o;
  wire [7:0] use_p1_p1_b_n338;
  wire [7:0] use_p1_p1_b_n339;
  wire use_p1_p1_b_n340;
  wire [7:0] use_p1_p1_b_data_o;
  wire [7:0] use_p1_p1_b_p1_o;
  wire use_p1_p1_b_p1_low_imp_o;
  wire [7:0] use_p2_p2_b_n347;
  wire [3:0] n348_o;
  wire [7:0] use_p2_p2_b_n349;
  wire use_p2_p2_b_n350;
  wire use_p2_p2_b_n351;
  wire [7:0] use_p2_p2_b_data_o;
  wire [7:0] use_p2_p2_b_p2_o;
  wire use_p2_p2_b_p2l_low_imp_o;
  wire use_p2_p2_b_p2h_low_imp_o;
  wire [7:0] pmem_ctrl_b_n360;
  wire [11:0] pmem_ctrl_b_n361;
  wire [7:0] pmem_ctrl_b_data_o;
  wire [11:0] pmem_ctrl_b_pmem_addr_o;
  wire [7:0] psw_b_n366;
  wire psw_b_n367;
  wire psw_b_n368;
  wire psw_b_n369;
  wire psw_b_n370;
  wire [7:0] psw_b_data_o;
  wire psw_b_carry_o;
  wire psw_b_aux_carry_o;
  wire psw_b_f0_o;
  wire psw_b_bs_o;
  wire n388_o;
  wire n390_o;
  wire n397_o;
  wire n399_o;
  wire n406_o;
  wire n408_o;
  wire n415_o;
  wire n417_o;
  wire n424_o;
  wire n432_o;
  wire n433_o;
  wire n434_o;
  wire n435_o;
  wire n436_o;
  wire n437_o;
  wire n438_o;
  wire n439_o;
  wire n440_o;
  wire n441_o;
  wire [1:0] n442_o;
  reg n443_o;
  wire [1:0] n444_o;
  reg n445_o;
  wire n446_o;
  wire n447_o;
  wire n448_o;
  wire n449_o;
  wire n450_o;
  wire n451_o;
  wire n452_o;
  wire n453_o;
  wire n454_o;
  wire n455_o;
  wire n456_o;
  wire n457_o;
  wire n458_o;
  wire [1:0] n459_o;
  reg n460_o;
  wire [1:0] n461_o;
  reg n462_o;
  wire n463_o;
  wire n464_o;
  wire n465_o;
  wire n466_o;
  wire n467_o;
  wire n468_o;
  wire n469_o;
  wire n470_o;
  wire n471_o;
  wire n472_o;
  wire n473_o;
  wire n474_o;
  wire n475_o;
  wire [1:0] n476_o;
  reg n477_o;
  wire [1:0] n478_o;
  reg n479_o;
  wire n480_o;
  wire n481_o;
  wire n482_o;
  wire n483_o;
  assign t0_o = clock_ctrl_b_n51;
  assign t0_dir_o = decoder_b_n112;
  assign rd_n_o = n415_o;
  assign psen_n_o = n397_o;
  assign wr_n_o = n424_o;
  assign ale_o = n388_o;
  assign db_o = use_db_bus_db_bus_b_n104;
  assign db_dir_o = use_db_bus_db_bus_b_n105;
  assign p2_o = use_p2_p2_b_n349;
  assign p2l_low_imp_o = use_p2_p2_b_n350;
  assign p2h_low_imp_o = use_p2_p2_b_n351;
  assign p1_o = use_p1_p1_b_n339;
  assign p1_low_imp_o = use_p1_p1_b_n340;
  assign prog_n_o = n406_o;
  assign xtal3_o = n432_o;
  assign dmem_addr_o = dmem_ctrl_b_n302;
  assign dmem_we_o = dmem_ctrl_b_n303;
  assign dmem_data_o = dmem_ctrl_b_n304;
  assign pmem_addr_o = pmem_addr_s;
  /* t48_core.vhd:137:10  */
  assign t48_data_s = bus_mux_b_n47; // (signal)
  /* t48_core.vhd:139:10  */
  assign xtal_en_s = n26_o; // (signal)
  /* t48_core.vhd:140:10  */
  assign en_clk_s = n34_o; // (signal)
  /* t48_core.vhd:143:10  */
  assign alu_data_s = alu_b_n35; // (signal)
  /* t48_core.vhd:144:10  */
  assign alu_write_accu_s = decoder_b_n114; // (signal)
  /* t48_core.vhd:145:10  */
  assign alu_write_shadow_s = decoder_b_n115; // (signal)
  /* t48_core.vhd:146:10  */
  assign alu_write_temp_reg_s = decoder_b_n116; // (signal)
  /* t48_core.vhd:147:10  */
  assign alu_read_alu_s = decoder_b_n117; // (signal)
  /* t48_core.vhd:148:10  */
  assign alu_carry_s = alu_b_n36; // (signal)
  /* t48_core.vhd:149:10  */
  assign alu_aux_carry_s = alu_b_n37; // (signal)
  /* t48_core.vhd:150:10  */
  assign alu_op_s = decoder_b_n137; // (signal)
  /* t48_core.vhd:151:10  */
  assign alu_use_carry_s = decoder_b_n142; // (signal)
  /* t48_core.vhd:152:10  */
  assign alu_da_high_s = decoder_b_n138; // (signal)
  /* t48_core.vhd:153:10  */
  assign alu_da_overflow_s = alu_b_n38; // (signal)
  /* t48_core.vhd:154:10  */
  assign alu_accu_low_s = decoder_b_n139; // (signal)
  /* t48_core.vhd:155:10  */
  assign alu_p06_temp_reg_s = decoder_b_n140; // (signal)
  /* t48_core.vhd:156:10  */
  assign alu_p60_temp_reg_s = decoder_b_n141; // (signal)
  /* t48_core.vhd:159:10  */
  assign bus_write_bus_s = decoder_b_n118; // (signal)
  /* t48_core.vhd:160:10  */
  assign bus_read_bus_s = decoder_b_n119; // (signal)
  /* t48_core.vhd:161:10  */
  assign bus_output_pcl_s = decoder_b_n143; // (signal)
  /* t48_core.vhd:162:10  */
  assign bus_bidir_bus_s = decoder_b_n144; // (signal)
  /* t48_core.vhd:163:10  */
  assign bus_data_s = use_db_bus_db_bus_b_n102; // (signal)
  /* t48_core.vhd:166:10  */
  assign clk_multi_cycle_s = decoder_b_n145; // (signal)
  /* t48_core.vhd:167:10  */
  assign clk_assert_psen_s = decoder_b_n146; // (signal)
  /* t48_core.vhd:168:10  */
  assign clk_assert_prog_s = decoder_b_n147; // (signal)
  /* t48_core.vhd:169:10  */
  assign clk_assert_rd_s = decoder_b_n148; // (signal)
  /* t48_core.vhd:170:10  */
  assign clk_assert_wr_s = decoder_b_n149; // (signal)
  /* t48_core.vhd:171:10  */
  assign clk_mstate_s = clock_ctrl_b_n52; // (signal)
  /* t48_core.vhd:172:10  */
  assign clk_second_cycle_s = clock_ctrl_b_n53; // (signal)
  /* t48_core.vhd:173:10  */
  assign psen_s = clock_ctrl_b_n55; // (signal)
  /* t48_core.vhd:174:10  */
  assign prog_s = clock_ctrl_b_n56; // (signal)
  /* t48_core.vhd:175:10  */
  assign rd_s = clock_ctrl_b_n57; // (signal)
  /* t48_core.vhd:176:10  */
  assign wr_s = clock_ctrl_b_n58; // (signal)
  /* t48_core.vhd:177:10  */
  assign ale_s = clock_ctrl_b_n54; // (signal)
  /* t48_core.vhd:178:10  */
  assign xtal3_s = clock_ctrl_b_n50; // (signal)
  /* t48_core.vhd:181:10  */
  assign cnd_compute_take_s = decoder_b_n150; // (signal)
  /* t48_core.vhd:182:10  */
  assign cnd_branch_cond_s = decoder_b_n151; // (signal)
  /* t48_core.vhd:183:10  */
  assign cnd_take_branch_s = cond_branch_b_n77; // (signal)
  /* t48_core.vhd:184:10  */
  assign cnd_comp_value_s = decoder_b_n152; // (signal)
  /* t48_core.vhd:185:10  */
  assign cnd_f1_s = decoder_b_n153; // (signal)
  /* t48_core.vhd:186:10  */
  assign cnd_tf_s = decoder_b_n154; // (signal)
  /* t48_core.vhd:189:10  */
  assign dm_write_dmem_addr_s = decoder_b_n120; // (signal)
  /* t48_core.vhd:190:10  */
  assign dm_write_dmem_s = decoder_b_n121; // (signal)
  /* t48_core.vhd:191:10  */
  assign dm_read_dmem_s = decoder_b_n122; // (signal)
  /* t48_core.vhd:192:10  */
  assign dm_addr_type_s = decoder_b_n155; // (signal)
  /* t48_core.vhd:193:10  */
  assign dm_data_s = dmem_ctrl_b_n301; // (signal)
  /* t48_core.vhd:196:10  */
  assign dec_data_s = decoder_b_n113; // (signal)
  /* t48_core.vhd:199:10  */
  assign p1_write_p1_s = decoder_b_n123; // (signal)
  /* t48_core.vhd:200:10  */
  assign p1_read_p1_s = decoder_b_n124; // (signal)
  /* t48_core.vhd:201:10  */
  assign p1_read_reg_s = decoder_b_n161; // (signal)
  /* t48_core.vhd:202:10  */
  assign p1_data_s = use_p1_p1_b_n338; // (signal)
  /* t48_core.vhd:205:10  */
  assign p2_write_p2_s = decoder_b_n125; // (signal)
  /* t48_core.vhd:206:10  */
  assign p2_write_exp_s = decoder_b_n126; // (signal)
  /* t48_core.vhd:207:10  */
  assign p2_read_p2_s = decoder_b_n127; // (signal)
  /* t48_core.vhd:208:10  */
  assign p2_read_reg_s = decoder_b_n162; // (signal)
  /* t48_core.vhd:209:10  */
  assign p2_read_exp_s = decoder_b_n163; // (signal)
  /* t48_core.vhd:210:10  */
  assign p2_output_pch_s = decoder_b_n164; // (signal)
  /* t48_core.vhd:211:10  */
  assign p2_data_s = use_p2_p2_b_n347; // (signal)
  /* t48_core.vhd:214:10  */
  assign pm_write_pcl_s = decoder_b_n128; // (signal)
  /* t48_core.vhd:215:10  */
  assign pm_read_pcl_s = decoder_b_n129; // (signal)
  /* t48_core.vhd:216:10  */
  assign pm_write_pch_s = decoder_b_n130; // (signal)
  /* t48_core.vhd:217:10  */
  assign pm_read_pch_s = decoder_b_n131; // (signal)
  /* t48_core.vhd:218:10  */
  assign pm_read_pmem_s = decoder_b_n132; // (signal)
  /* t48_core.vhd:219:10  */
  assign pm_inc_pc_s = decoder_b_n165; // (signal)
  /* t48_core.vhd:220:10  */
  assign pm_write_pmem_addr_s = decoder_b_n166; // (signal)
  /* t48_core.vhd:221:10  */
  assign pm_data_s = pmem_ctrl_b_n360; // (signal)
  /* t48_core.vhd:222:10  */
  assign pm_addr_type_s = decoder_b_n167; // (signal)
  /* t48_core.vhd:223:10  */
  assign pmem_addr_s = pmem_ctrl_b_n361; // (signal)
  /* t48_core.vhd:226:10  */
  assign psw_read_psw_s = decoder_b_n133; // (signal)
  /* t48_core.vhd:227:10  */
  assign psw_read_sp_s = decoder_b_n134; // (signal)
  /* t48_core.vhd:228:10  */
  assign psw_write_psw_s = decoder_b_n135; // (signal)
  /* t48_core.vhd:229:10  */
  assign psw_write_sp_s = decoder_b_n136; // (signal)
  /* t48_core.vhd:230:10  */
  assign psw_carry_s = psw_b_n367; // (signal)
  /* t48_core.vhd:231:10  */
  assign psw_aux_carry_s = psw_b_n368; // (signal)
  /* t48_core.vhd:232:10  */
  assign psw_f0_s = psw_b_n369; // (signal)
  /* t48_core.vhd:233:10  */
  assign psw_bs_s = psw_b_n370; // (signal)
  /* t48_core.vhd:234:10  */
  assign psw_special_data_s = decoder_b_n168; // (signal)
  /* t48_core.vhd:235:10  */
  assign psw_inc_stackp_s = decoder_b_n169; // (signal)
  /* t48_core.vhd:236:10  */
  assign psw_dec_stackp_s = decoder_b_n170; // (signal)
  /* t48_core.vhd:237:10  */
  assign psw_write_carry_s = decoder_b_n171; // (signal)
  /* t48_core.vhd:238:10  */
  assign psw_write_aux_carry_s = decoder_b_n172; // (signal)
  /* t48_core.vhd:239:10  */
  assign psw_write_f0_s = decoder_b_n173; // (signal)
  /* t48_core.vhd:240:10  */
  assign psw_write_bs_s = decoder_b_n174; // (signal)
  /* t48_core.vhd:241:10  */
  assign psw_data_s = psw_b_n366; // (signal)
  /* t48_core.vhd:244:10  */
  assign tim_overflow_s = n337_o; // (signal)
  /* t48_core.vhd:245:10  */
  assign tim_of_s = use_timer_timer_b_n325; // (signal)
  /* t48_core.vhd:246:10  */
  assign tim_read_timer_s = decoder_b_n156; // (signal)
  /* t48_core.vhd:247:10  */
  assign tim_write_timer_s = decoder_b_n157; // (signal)
  /* t48_core.vhd:248:10  */
  assign tim_start_t_s = decoder_b_n158; // (signal)
  /* t48_core.vhd:249:10  */
  assign tim_start_cnt_s = decoder_b_n159; // (signal)
  /* t48_core.vhd:250:10  */
  assign tim_stop_tcnt_s = decoder_b_n160; // (signal)
  /* t48_core.vhd:251:10  */
  assign tim_data_s = use_timer_timer_b_n324; // (signal)
  /* t48_pack-p.vhd:75:5  */
  assign n26_o = xtal_en_i ? 1'b1 : 1'b0;
  /* t48_pack-p.vhd:75:5  */
  assign n34_o = en_clk_i ? 1'b1 : 1'b0;
  /* t48_core.vhd:286:29  */
  assign alu_b_n35 = alu_b_data_o; // (signal)
  /* t48_core.vhd:292:29  */
  assign alu_b_n36 = alu_b_carry_o; // (signal)
  /* t48_core.vhd:293:29  */
  assign alu_b_n37 = alu_b_aux_carry_o; // (signal)
  /* t48_core.vhd:297:29  */
  assign alu_b_n38 = alu_b_da_overflow_o; // (signal)
  /* t48_core.vhd:280:3  */
  t48_alu alu_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .data_i(t48_data_s),
    .write_accu_i(alu_write_accu_s),
    .write_shadow_i(alu_write_shadow_s),
    .write_temp_reg_i(alu_write_temp_reg_s),
    .read_alu_i(alu_read_alu_s),
    .carry_i(psw_carry_s),
    .alu_op_i(alu_op_s),
    .use_carry_i(alu_use_carry_s),
    .da_high_i(alu_da_high_s),
    .accu_low_i(alu_accu_low_s),
    .p06_temp_reg_i(alu_p06_temp_reg_s),
    .p60_temp_reg_i(alu_p60_temp_reg_s),
    .data_o(alu_b_data_o),
    .carry_o(alu_b_carry_o),
    .aux_carry_o(alu_b_aux_carry_o),
    .da_overflow_o(alu_b_da_overflow_o));
  /* t48_core.vhd:314:21  */
  assign bus_mux_b_n47 = bus_mux_b_data_o; // (signal)
  /* t48_core.vhd:303:3  */
  t48_bus_mux bus_mux_b (
    .alu_data_i(alu_data_s),
    .bus_data_i(bus_data_s),
    .dec_data_i(dec_data_s),
    .dm_data_i(dm_data_s),
    .pm_data_i(pm_data_s),
    .p1_data_i(p1_data_s),
    .p2_data_i(p2_data_s),
    .psw_data_i(psw_data_s),
    .tim_data_i(tim_data_s),
    .data_o(bus_mux_b_data_o));
  /* t48_core.vhd:327:25  */
  assign clock_ctrl_b_n50 = clock_ctrl_b_xtal3_o; // (signal)
  /* t48_core.vhd:328:25  */
  assign clock_ctrl_b_n51 = clock_ctrl_b_t0_o; // (signal)
  /* t48_core.vhd:334:25  */
  assign clock_ctrl_b_n52 = clock_ctrl_b_mstate_o; // (signal)
  /* t48_core.vhd:335:25  */
  assign clock_ctrl_b_n53 = clock_ctrl_b_second_cycle_o; // (signal)
  /* t48_core.vhd:336:25  */
  assign clock_ctrl_b_n54 = clock_ctrl_b_ale_o; // (signal)
  /* t48_core.vhd:337:25  */
  assign clock_ctrl_b_n55 = clock_ctrl_b_psen_o; // (signal)
  /* t48_core.vhd:338:25  */
  assign clock_ctrl_b_n56 = clock_ctrl_b_prog_o; // (signal)
  /* t48_core.vhd:339:25  */
  assign clock_ctrl_b_n57 = clock_ctrl_b_rd_o; // (signal)
  /* t48_core.vhd:340:25  */
  assign clock_ctrl_b_n58 = clock_ctrl_b_wr_o; // (signal)
  /* t48_core.vhd:317:3  */
  t48_clock_ctrl_1 clock_ctrl_b (
    .clk_i(clk_i),
    .xtal_i(xtal_i),
    .xtal_en_i(xtal_en_s),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .multi_cycle_i(clk_multi_cycle_s),
    .assert_psen_i(clk_assert_psen_s),
    .assert_prog_i(clk_assert_prog_s),
    .assert_rd_i(clk_assert_rd_s),
    .assert_wr_i(clk_assert_wr_s),
    .xtal3_o(clock_ctrl_b_xtal3_o),
    .t0_o(clock_ctrl_b_t0_o),
    .mstate_o(clock_ctrl_b_mstate_o),
    .second_cycle_o(clock_ctrl_b_second_cycle_o),
    .ale_o(clock_ctrl_b_ale_o),
    .psen_o(clock_ctrl_b_psen_o),
    .prog_o(clock_ctrl_b_prog_o),
    .rd_o(clock_ctrl_b_rd_o),
    .wr_o(clock_ctrl_b_wr_o));
  /* t48_core.vhd:350:25  */
  assign cond_branch_b_n77 = cond_branch_b_take_branch_o; // (signal)
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n83_o = {3'b0, t0_i};  //  uext
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n85_o = 4'b1000 - n83_o;
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n94_o = {3'b0, t1_i};  //  uext
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n96_o = 4'b1000 - n94_o;
  /* t48_core.vhd:343:3  */
  t48_cond_branch cond_branch_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .compute_take_i(cnd_compute_take_s),
    .branch_cond_i(cnd_branch_cond_s),
    .accu_i(alu_data_s),
    // Both T0 and T1 reach the conditional-branch unit through a std_logic
    // table lookup that this VHDL-to-Verilog translation gets wrong, so JT0 /
    // JNT0 / JT1 / JNT1 never see the pin. t1_i was already bypassed here;
    // t0_i had not been, which left JNT0 permanently taking its branch. The
    // Sega speech board polls exactly that instruction to notice a pending
    // word, so its 8035 sat in a 4-instruction loop forever and the board was
    // silent. See sim/tb/tb_i8035.cpp, which tests all four instructions.
    //.t0_i(n449_o),
    .t0_i(t0_i),
    //.t1_i(n466_o),
    .t1_i(t1_i),
    .int_n_i(int_n_i),
    .f0_i(psw_f0_s),
    .f1_i(cnd_f1_s),
    .tf_i(cnd_tf_s),
    .carry_i(psw_carry_s),
    .comp_value_i(cnd_comp_value_s),
    .take_branch_o(cond_branch_b_take_branch_o));
  /* t48_core.vhd:370:25  */
  assign use_db_bus_db_bus_b_n102 = use_db_bus_db_bus_b_data_o; // (signal)
  /* t48_core.vhd:375:36  */
  assign n103_o = pmem_addr_s[7:0];
  /* t48_core.vhd:377:25  */
  assign use_db_bus_db_bus_b_n104 = use_db_bus_db_bus_b_db_o; // (signal)
  /* t48_core.vhd:378:25  */
  assign use_db_bus_db_bus_b_n105 = use_db_bus_db_bus_b_db_dir_o; // (signal)
  /* t48_core.vhd:363:5  */
  t48_db_bus use_db_bus_db_bus_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .ea_i(ea_i),
    .data_i(t48_data_s),
    .write_bus_i(bus_write_bus_s),
    .read_bus_i(bus_read_bus_s),
    .output_pcl_i(bus_output_pcl_s),
    .bidir_bus_i(bus_bidir_bus_s),
    .pcl_i(n103_o),
    .db_i(db_i),
    .data_o(use_db_bus_db_bus_b_data_o),
    .db_o(use_db_bus_db_bus_b_db_o),
    .db_dir_o(use_db_bus_db_bus_b_db_dir_o));
  /* t48_core.vhd:401:33  */
  assign decoder_b_n112 = decoder_b_t0_dir_o; // (signal)
  /* t48_core.vhd:403:33  */
  assign decoder_b_n113 = decoder_b_data_o; // (signal)
  /* t48_core.vhd:404:33  */
  assign decoder_b_n114 = decoder_b_alu_write_accu_o; // (signal)
  /* t48_core.vhd:405:33  */
  assign decoder_b_n115 = decoder_b_alu_write_shadow_o; // (signal)
  /* t48_core.vhd:406:33  */
  assign decoder_b_n116 = decoder_b_alu_write_temp_reg_o; // (signal)
  /* t48_core.vhd:407:33  */
  assign decoder_b_n117 = decoder_b_alu_read_alu_o; // (signal)
  /* t48_core.vhd:408:33  */
  assign decoder_b_n118 = decoder_b_bus_write_bus_o; // (signal)
  /* t48_core.vhd:409:33  */
  assign decoder_b_n119 = decoder_b_bus_read_bus_o; // (signal)
  /* t48_core.vhd:410:33  */
  assign decoder_b_n120 = decoder_b_dm_write_dmem_addr_o; // (signal)
  /* t48_core.vhd:411:33  */
  assign decoder_b_n121 = decoder_b_dm_write_dmem_o; // (signal)
  /* t48_core.vhd:412:33  */
  assign decoder_b_n122 = decoder_b_dm_read_dmem_o; // (signal)
  /* t48_core.vhd:413:33  */
  assign decoder_b_n123 = decoder_b_p1_write_p1_o; // (signal)
  /* t48_core.vhd:414:33  */
  assign decoder_b_n124 = decoder_b_p1_read_p1_o; // (signal)
  /* t48_core.vhd:416:33  */
  assign decoder_b_n125 = decoder_b_p2_write_p2_o; // (signal)
  /* t48_core.vhd:417:33  */
  assign decoder_b_n126 = decoder_b_p2_write_exp_o; // (signal)
  /* t48_core.vhd:418:33  */
  assign decoder_b_n127 = decoder_b_p2_read_p2_o; // (signal)
  /* t48_core.vhd:415:33  */
  assign decoder_b_n128 = decoder_b_pm_write_pcl_o; // (signal)
  /* t48_core.vhd:419:33  */
  assign decoder_b_n129 = decoder_b_pm_read_pcl_o; // (signal)
  /* t48_core.vhd:420:33  */
  assign decoder_b_n130 = decoder_b_pm_write_pch_o; // (signal)
  /* t48_core.vhd:421:33  */
  assign decoder_b_n131 = decoder_b_pm_read_pch_o; // (signal)
  /* t48_core.vhd:422:33  */
  assign decoder_b_n132 = decoder_b_pm_read_pmem_o; // (signal)
  /* t48_core.vhd:423:33  */
  assign decoder_b_n133 = decoder_b_psw_read_psw_o; // (signal)
  /* t48_core.vhd:424:33  */
  assign decoder_b_n134 = decoder_b_psw_read_sp_o; // (signal)
  /* t48_core.vhd:425:33  */
  assign decoder_b_n135 = decoder_b_psw_write_psw_o; // (signal)
  /* t48_core.vhd:426:33  */
  assign decoder_b_n136 = decoder_b_psw_write_sp_o; // (signal)
  /* t48_core.vhd:428:33  */
  assign decoder_b_n137 = decoder_b_alu_op_o; // (signal)
  /* t48_core.vhd:430:33  */
  assign decoder_b_n138 = decoder_b_alu_da_high_o; // (signal)
  /* t48_core.vhd:432:33  */
  assign decoder_b_n139 = decoder_b_alu_accu_low_o; // (signal)
  /* t48_core.vhd:433:33  */
  assign decoder_b_n140 = decoder_b_alu_p06_temp_reg_o; // (signal)
  /* t48_core.vhd:434:33  */
  assign decoder_b_n141 = decoder_b_alu_p60_temp_reg_o; // (signal)
  /* t48_core.vhd:429:33  */
  assign decoder_b_n142 = decoder_b_alu_use_carry_o; // (signal)
  /* t48_core.vhd:435:33  */
  assign decoder_b_n143 = decoder_b_bus_output_pcl_o; // (signal)
  /* t48_core.vhd:436:33  */
  assign decoder_b_n144 = decoder_b_bus_bidir_bus_o; // (signal)
  /* t48_core.vhd:437:33  */
  assign decoder_b_n145 = decoder_b_clk_multi_cycle_o; // (signal)
  /* t48_core.vhd:438:33  */
  assign decoder_b_n146 = decoder_b_clk_assert_psen_o; // (signal)
  /* t48_core.vhd:439:33  */
  assign decoder_b_n147 = decoder_b_clk_assert_prog_o; // (signal)
  /* t48_core.vhd:440:33  */
  assign decoder_b_n148 = decoder_b_clk_assert_rd_o; // (signal)
  /* t48_core.vhd:441:33  */
  assign decoder_b_n149 = decoder_b_clk_assert_wr_o; // (signal)
  /* t48_core.vhd:444:33  */
  assign decoder_b_n150 = decoder_b_cnd_compute_take_o; // (signal)
  /* t48_core.vhd:445:33  */
  assign decoder_b_n151 = decoder_b_cnd_branch_cond_o; // (signal)
  /* t48_core.vhd:447:33  */
  assign decoder_b_n152 = decoder_b_cnd_comp_value_o; // (signal)
  /* t48_core.vhd:448:33  */
  assign decoder_b_n153 = decoder_b_cnd_f1_o; // (signal)
  /* t48_core.vhd:449:33  */
  assign decoder_b_n154 = decoder_b_cnd_tf_o; // (signal)
  /* t48_core.vhd:450:33  */
  assign decoder_b_n155 = decoder_b_dm_addr_type_o; // (signal)
  /* t48_core.vhd:451:33  */
  assign decoder_b_n156 = decoder_b_tim_read_timer_o; // (signal)
  /* t48_core.vhd:452:33  */
  assign decoder_b_n157 = decoder_b_tim_write_timer_o; // (signal)
  /* t48_core.vhd:453:33  */
  assign decoder_b_n158 = decoder_b_tim_start_t_o; // (signal)
  /* t48_core.vhd:454:33  */
  assign decoder_b_n159 = decoder_b_tim_start_cnt_o; // (signal)
  /* t48_core.vhd:455:33  */
  assign decoder_b_n160 = decoder_b_tim_stop_tcnt_o; // (signal)
  /* t48_core.vhd:456:33  */
  assign decoder_b_n161 = decoder_b_p1_read_reg_o; // (signal)
  /* t48_core.vhd:457:33  */
  assign decoder_b_n162 = decoder_b_p2_read_reg_o; // (signal)
  /* t48_core.vhd:458:33  */
  assign decoder_b_n163 = decoder_b_p2_read_exp_o; // (signal)
  /* t48_core.vhd:459:33  */
  assign decoder_b_n164 = decoder_b_p2_output_pch_o; // (signal)
  /* t48_core.vhd:460:33  */
  assign decoder_b_n165 = decoder_b_pm_inc_pc_o; // (signal)
  /* t48_core.vhd:461:33  */
  assign decoder_b_n166 = decoder_b_pm_write_pmem_addr_o; // (signal)
  /* t48_core.vhd:462:33  */
  assign decoder_b_n167 = decoder_b_pm_addr_type_o; // (signal)
  /* t48_core.vhd:463:33  */
  assign decoder_b_n168 = decoder_b_psw_special_data_o; // (signal)
  /* t48_core.vhd:467:33  */
  assign decoder_b_n169 = decoder_b_psw_inc_stackp_o; // (signal)
  /* t48_core.vhd:468:33  */
  assign decoder_b_n170 = decoder_b_psw_dec_stackp_o; // (signal)
  /* t48_core.vhd:469:33  */
  assign decoder_b_n171 = decoder_b_psw_write_carry_o; // (signal)
  /* t48_core.vhd:470:33  */
  assign decoder_b_n172 = decoder_b_psw_write_aux_carry_o; // (signal)
  /* t48_core.vhd:471:33  */
  assign decoder_b_n173 = decoder_b_psw_write_f0_o; // (signal)
  /* t48_core.vhd:472:33  */
  assign decoder_b_n174 = decoder_b_psw_write_bs_o; // (signal)
  /* t48_core.vhd:388:3  */
  t48_decoder_1 decoder_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .xtal_i(xtal_i),
    .xtal_en_i(xtal_en_s),
    .ea_i(ea_i),
    .ale_i(ale_s),
    .int_n_i(int_n_i),
    .data_i(t48_data_s),
    .alu_carry_i(alu_carry_s),
    .alu_da_overflow_i(alu_da_overflow_s),
    .clk_mstate_i(clk_mstate_s),
    .clk_second_cycle_i(clk_second_cycle_s),
    .cnd_take_branch_i(cnd_take_branch_s),
    .psw_carry_i(psw_carry_s),
    .psw_aux_carry_i(psw_aux_carry_s),
    .psw_f0_i(psw_f0_s),
    .tim_overflow_i(tim_overflow_s),
    .t0_dir_o(decoder_b_t0_dir_o),
    .data_o(decoder_b_data_o),
    .alu_write_accu_o(decoder_b_alu_write_accu_o),
    .alu_write_shadow_o(decoder_b_alu_write_shadow_o),
    .alu_write_temp_reg_o(decoder_b_alu_write_temp_reg_o),
    .alu_read_alu_o(decoder_b_alu_read_alu_o),
    .bus_write_bus_o(decoder_b_bus_write_bus_o),
    .bus_read_bus_o(decoder_b_bus_read_bus_o),
    .dm_write_dmem_addr_o(decoder_b_dm_write_dmem_addr_o),
    .dm_write_dmem_o(decoder_b_dm_write_dmem_o),
    .dm_read_dmem_o(decoder_b_dm_read_dmem_o),
    .p1_write_p1_o(decoder_b_p1_write_p1_o),
    .p1_read_p1_o(decoder_b_p1_read_p1_o),
    .p2_write_p2_o(decoder_b_p2_write_p2_o),
    .p2_write_exp_o(decoder_b_p2_write_exp_o),
    .p2_read_p2_o(decoder_b_p2_read_p2_o),
    .p2_read_exp_o(decoder_b_p2_read_exp_o),
    .pm_write_pcl_o(decoder_b_pm_write_pcl_o),
    .pm_read_pcl_o(decoder_b_pm_read_pcl_o),
    .pm_write_pch_o(decoder_b_pm_write_pch_o),
    .pm_read_pch_o(decoder_b_pm_read_pch_o),
    .pm_read_pmem_o(decoder_b_pm_read_pmem_o),
    .psw_read_psw_o(decoder_b_psw_read_psw_o),
    .psw_read_sp_o(decoder_b_psw_read_sp_o),
    .psw_write_psw_o(decoder_b_psw_write_psw_o),
    .psw_write_sp_o(decoder_b_psw_write_sp_o),
    .alu_op_o(decoder_b_alu_op_o),
    .alu_use_carry_o(decoder_b_alu_use_carry_o),
    .alu_da_high_o(decoder_b_alu_da_high_o),
    .alu_accu_low_o(decoder_b_alu_accu_low_o),
    .alu_p06_temp_reg_o(decoder_b_alu_p06_temp_reg_o),
    .alu_p60_temp_reg_o(decoder_b_alu_p60_temp_reg_o),
    .bus_output_pcl_o(decoder_b_bus_output_pcl_o),
    .bus_bidir_bus_o(decoder_b_bus_bidir_bus_o),
    .clk_multi_cycle_o(decoder_b_clk_multi_cycle_o),
    .clk_assert_psen_o(decoder_b_clk_assert_psen_o),
    .clk_assert_prog_o(decoder_b_clk_assert_prog_o),
    .clk_assert_rd_o(decoder_b_clk_assert_rd_o),
    .clk_assert_wr_o(decoder_b_clk_assert_wr_o),
    .cnd_compute_take_o(decoder_b_cnd_compute_take_o),
    .cnd_branch_cond_o(decoder_b_cnd_branch_cond_o),
    .cnd_comp_value_o(decoder_b_cnd_comp_value_o),
    .cnd_f1_o(decoder_b_cnd_f1_o),
    .cnd_tf_o(decoder_b_cnd_tf_o),
    .dm_addr_type_o(decoder_b_dm_addr_type_o),
    .p1_read_reg_o(decoder_b_p1_read_reg_o),
    .p2_read_reg_o(decoder_b_p2_read_reg_o),
    .p2_output_pch_o(decoder_b_p2_output_pch_o),
    .pm_inc_pc_o(decoder_b_pm_inc_pc_o),
    .pm_write_pmem_addr_o(decoder_b_pm_write_pmem_addr_o),
    .pm_addr_type_o(decoder_b_pm_addr_type_o),
    .psw_special_data_o(decoder_b_psw_special_data_o),
    .psw_inc_stackp_o(decoder_b_psw_inc_stackp_o),
    .psw_dec_stackp_o(decoder_b_psw_dec_stackp_o),
    .psw_write_carry_o(decoder_b_psw_write_carry_o),
    .psw_write_aux_carry_o(decoder_b_psw_write_aux_carry_o),
    .psw_write_f0_o(decoder_b_psw_write_f0_o),
    .psw_write_bs_o(decoder_b_psw_write_bs_o),
    .tim_read_timer_o(decoder_b_tim_read_timer_o),
    .tim_write_timer_o(decoder_b_tim_write_timer_o),
    .tim_start_t_o(decoder_b_tim_start_t_o),
    .tim_start_cnt_o(decoder_b_tim_start_cnt_o),
    .tim_stop_tcnt_o(decoder_b_tim_stop_tcnt_o)
    );
  /* t48_core.vhd:487:28  */
  assign dmem_ctrl_b_n301 = dmem_ctrl_b_data_o; // (signal)
  /* t48_core.vhd:489:28  */
  assign dmem_ctrl_b_n302 = dmem_ctrl_b_dmem_addr_o; // (signal)
  /* t48_core.vhd:490:28  */
  assign dmem_ctrl_b_n303 = dmem_ctrl_b_dmem_we_o; // (signal)
  /* t48_core.vhd:491:28  */
  assign dmem_ctrl_b_n304 = dmem_ctrl_b_dmem_data_o; // (signal)
  /* t48_core.vhd:476:3  */
  t48_dmem_ctrl dmem_ctrl_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .data_i(t48_data_s),
    .write_dmem_addr_i(dm_write_dmem_addr_s),
    .write_dmem_i(dm_write_dmem_s),
    .read_dmem_i(dm_read_dmem_s),
    .addr_type_i(dm_addr_type_s),
    .bank_select_i(psw_bs_s),
    .dmem_data_i(dmem_data_i),
    .data_o(dmem_ctrl_b_data_o),
    .dmem_addr_o(dmem_ctrl_b_dmem_addr_o),
    .dmem_we_o(dmem_ctrl_b_dmem_we_o),
    .dmem_data_o(dmem_ctrl_b_dmem_data_o));
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n318_o = {3'b0, t1_i};  //  uext
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n320_o = 4'b1000 - n318_o;
  /* t48_core.vhd:506:26  */
  assign use_timer_timer_b_n324 = use_timer_timer_b_data_o; // (signal)
  /* t48_core.vhd:512:26  */
  assign use_timer_timer_b_n325 = use_timer_timer_b_overflow_o; // (signal)
  /* t48_core.vhd:495:5  */
  t48_timer_4 use_timer_timer_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    //.t1_i(n483_o),
    .t1_i(t1_i),
    .clk_mstate_i(clk_mstate_s),
    .data_i(t48_data_s),
    .read_timer_i(tim_read_timer_s),
    .write_timer_i(tim_write_timer_s),
    .start_t_i(tim_start_t_s),
    .start_cnt_i(tim_start_cnt_s),
    .stop_tcnt_i(tim_stop_tcnt_s),
    .data_o(use_timer_timer_b_data_o),
    .overflow_o(use_timer_timer_b_overflow_o));
  /* t48_pack-p.vhd:75:5  */
  assign n337_o = tim_of_s ? 1'b1 : 1'b0;
  /* t48_core.vhd:530:25  */
  assign use_p1_p1_b_n338 = use_p1_p1_b_data_o; // (signal)
  /* t48_core.vhd:535:25  */
  assign use_p1_p1_b_n339 = use_p1_p1_b_p1_o; // (signal)
  /* t48_core.vhd:536:25  */
  assign use_p1_p1_b_n340 = use_p1_p1_b_p1_low_imp_o; // (signal)
  /* t48_core.vhd:524:5  */
  t48_p1 use_p1_p1_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .data_i(t48_data_s),
    .write_p1_i(p1_write_p1_s),
    .read_p1_i(p1_read_p1_s),
    .read_reg_i(p1_read_reg_s),
    .p1_i(p1_i),
    .data_o(use_p1_p1_b_data_o),
    .p1_o(use_p1_p1_b_p1_o),
    .p1_low_imp_o(use_p1_p1_b_p1_low_imp_o));
  /* t48_core.vhd:555:26  */
  assign use_p2_p2_b_n347 = use_p2_p2_b_data_o; // (signal)
  /* t48_core.vhd:562:37  */
  assign n348_o = pmem_addr_s[11:8];
  /* t48_core.vhd:564:26  */
  assign use_p2_p2_b_n349 = use_p2_p2_b_p2_o; // (signal)
  /* t48_core.vhd:565:26  */
  assign use_p2_p2_b_n350 = use_p2_p2_b_p2l_low_imp_o; // (signal)
  /* t48_core.vhd:566:26  */
  assign use_p2_p2_b_n351 = use_p2_p2_b_p2h_low_imp_o; // (signal)
  /* t48_core.vhd:547:5  */
  t48_p2 use_p2_p2_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .xtal_i(xtal_i),
    .xtal_en_i(xtal_en_s),
    .data_i(t48_data_s),
    .write_p2_i(p2_write_p2_s),
    .write_exp_i(p2_write_exp_s),
    .read_p2_i(p2_read_p2_s),
    .read_reg_i(p2_read_reg_s),
    .read_exp_i(p2_read_exp_s),
    .output_pch_i(p2_output_pch_s),
    .pch_i(n348_o),
    .p2_i(p2_i),
    .data_o(use_p2_p2_b_data_o),
    .p2_o(use_p2_p2_b_p2_o),
    .p2l_low_imp_o(use_p2_p2_b_p2l_low_imp_o),
    .p2h_low_imp_o(use_p2_p2_b_p2h_low_imp_o));
  /* t48_core.vhd:583:28  */
  assign pmem_ctrl_b_n360 = pmem_ctrl_b_data_o; // (signal)
  /* t48_core.vhd:592:28  */
  assign pmem_ctrl_b_n361 = pmem_ctrl_b_pmem_addr_o; // (signal)
  /* t48_core.vhd:577:3  */
  t48_pmem_ctrl pmem_ctrl_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .data_i(t48_data_s),
    .write_pcl_i(pm_write_pcl_s),
    .read_pcl_i(pm_read_pcl_s),
    .write_pch_i(pm_write_pch_s),
    .read_pch_i(pm_read_pch_s),
    .inc_pc_i(pm_inc_pc_s),
    .write_pmem_addr_i(pm_write_pmem_addr_s),
    .addr_type_i(pm_addr_type_s),
    .read_pmem_i(pm_read_pmem_s),
    .pmem_data_i(pmem_data_i),
    .data_o(pmem_ctrl_b_data_o),
    .pmem_addr_o(pmem_ctrl_b_pmem_addr_o));
  /* t48_core.vhd:602:29  */
  assign psw_b_n366 = psw_b_data_o; // (signal)
  /* t48_core.vhd:614:29  */
  assign psw_b_n367 = psw_b_carry_o; // (signal)
  /* t48_core.vhd:616:29  */
  assign psw_b_n368 = psw_b_aux_carry_o; // (signal)
  /* t48_core.vhd:617:29  */
  assign psw_b_n369 = psw_b_f0_o; // (signal)
  /* t48_core.vhd:618:29  */
  assign psw_b_n370 = psw_b_bs_o; // (signal)
  /* t48_core.vhd:596:3  */
  t48_psw psw_b (
    .clk_i(clk_i),
    .res_i(reset_i),
    .en_clk_i(en_clk_s),
    .data_i(t48_data_s),
    .read_psw_i(psw_read_psw_s),
    .read_sp_i(psw_read_sp_s),
    .write_psw_i(psw_write_psw_s),
    .write_sp_i(psw_write_sp_s),
    .special_data_i(psw_special_data_s),
    .inc_stackp_i(psw_inc_stackp_s),
    .dec_stackp_i(psw_dec_stackp_s),
    .write_carry_i(psw_write_carry_s),
    .write_aux_carry_i(psw_write_aux_carry_s),
    .write_f0_i(psw_write_f0_s),
    .write_bs_i(psw_write_bs_s),
    .aux_carry_i(alu_aux_carry_s),
    .data_o(psw_b_data_o),
    .carry_o(psw_b_carry_o),
    .aux_carry_o(psw_b_aux_carry_o),
    .f0_o(psw_b_f0_o),
    .bs_o(psw_b_bs_o));
  /* t48_pack-p.vhd:66:5  */
  assign n388_o = ale_s ? 1'b1 : 1'b0;
  /* t48_core.vhd:626:30  */
  assign n390_o = ~psen_s;
  /* t48_pack-p.vhd:66:5  */
  assign n397_o = n390_o ? 1'b1 : 1'b0;
  /* t48_core.vhd:627:30  */
  assign n399_o = ~prog_s;
  /* t48_pack-p.vhd:66:5  */
  assign n406_o = n399_o ? 1'b1 : 1'b0;
  /* t48_core.vhd:628:30  */
  assign n408_o = ~rd_s;
  /* t48_pack-p.vhd:66:5  */
  assign n415_o = n408_o ? 1'b1 : 1'b0;
  /* t48_core.vhd:629:30  */
  assign n417_o = ~wr_s;
  /* t48_pack-p.vhd:66:5  */
  assign n424_o = n417_o ? 1'b1 : 1'b0;
  /* t48_pack-p.vhd:66:5  */
  assign n432_o = xtal3_s ? 1'b1 : 1'b0;
  /* t48_core.vhd:618:29  */
  assign n433_o = n87_o[0];
  /* t48_core.vhd:617:29  */
  assign n434_o = n87_o[1];
  /* t48_core.vhd:616:29  */
  assign n435_o = n87_o[2];
  /* t48_core.vhd:614:29  */
  assign n436_o = n87_o[3];
  /* t48_core.vhd:602:29  */
  assign n437_o = n87_o[4];
  /* t48_core.vhd:596:3  */
  assign n438_o = n87_o[5];
  /* t48_core.vhd:596:3  */
  assign n439_o = n87_o[6];
  /* t48_core.vhd:596:3  */
  assign n440_o = n87_o[7];
  /* t48_core.vhd:596:3  */
  assign n441_o = n87_o[8];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n442_o = n85_o[1:0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  always @*
    case (n442_o)
      2'b00: n443_o = n433_o;
      2'b01: n443_o = n434_o;
      2'b10: n443_o = n435_o;
      2'b11: n443_o = n436_o;
    endcase
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n444_o = n85_o[1:0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  always @*
    case (n444_o)
      2'b00: n445_o = n437_o;
      2'b01: n445_o = n438_o;
      2'b10: n445_o = n439_o;
      2'b11: n445_o = n440_o;
    endcase
  /* t48_core.vhd:577:3  */
  assign n446_o = n85_o[2];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n447_o = n446_o ? n445_o : n443_o;
  /* t48_core.vhd:565:26  */
  assign n448_o = n85_o[3];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n449_o = n448_o ? n441_o : n447_o;
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n450_o = n98_o[0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n451_o = n98_o[1];
  /* t48_core.vhd:555:26  */
  assign n452_o = n98_o[2];
  /* t48_core.vhd:547:5  */
  assign n453_o = n98_o[3];
  /* t48_core.vhd:547:5  */
  assign n454_o = n98_o[4];
  /* t48_core.vhd:547:5  */
  assign n455_o = n98_o[5];
  /* t48_core.vhd:547:5  */
  assign n456_o = n98_o[6];
  /* t48_core.vhd:536:25  */
  assign n457_o = n98_o[7];
  /* t48_core.vhd:535:25  */
  assign n458_o = n98_o[8];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n459_o = n96_o[1:0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  always @*
    case (n459_o)
      2'b00: n460_o = n450_o;
      2'b01: n460_o = n451_o;
      2'b10: n460_o = n452_o;
      2'b11: n460_o = n453_o;
    endcase
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n461_o = n96_o[1:0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  always @*
    case (n461_o)
      2'b00: n462_o = n454_o;
      2'b01: n462_o = n455_o;
      2'b10: n462_o = n456_o;
      2'b11: n462_o = n457_o;
    endcase
  /* t48_core.vhd:512:26  */
  assign n463_o = n96_o[2];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n464_o = n463_o ? n462_o : n460_o;
  /* t48_core.vhd:495:5  */
  assign n465_o = n96_o[3];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n466_o = n465_o ? n458_o : n464_o;
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n467_o = n322_o[0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:25  */
  assign n468_o = n322_o[1];
  /* t48_core.vhd:491:28  */
  assign n469_o = n322_o[2];
  /* t48_core.vhd:490:28  */
  assign n470_o = n322_o[3];
  /* t48_core.vhd:489:28  */
  assign n471_o = n322_o[4];
  /* t48_core.vhd:487:28  */
  assign n472_o = n322_o[5];
  /* t48_core.vhd:476:3  */
  assign n473_o = n322_o[6];
  /* t48_core.vhd:476:3  */
  assign n474_o = n322_o[7];
  /* t48_core.vhd:476:3  */
  assign n475_o = n322_o[8];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n476_o = n320_o[1:0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  always @*
    case (n476_o)
      2'b00: n477_o = n467_o;
      2'b01: n477_o = n468_o;
      2'b10: n477_o = n469_o;
      2'b11: n477_o = n470_o;
    endcase
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n478_o = n320_o[1:0];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  always @*
    case (n478_o)
      2'b00: n479_o = n471_o;
      2'b01: n479_o = n472_o;
      2'b10: n479_o = n473_o;
      2'b11: n479_o = n474_o;
    endcase
  /* t48_core.vhd:469:33  */
  assign n480_o = n320_o[2];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n481_o = n480_o ? n479_o : n477_o;
  /* t48_core.vhd:467:33  */
  assign n482_o = n320_o[3];
  /* ../../src/ieee2008/std_logic_1164-body.vhdl:912:24  */
  assign n483_o = n482_o ? n475_o : n481_o;
endmodule

