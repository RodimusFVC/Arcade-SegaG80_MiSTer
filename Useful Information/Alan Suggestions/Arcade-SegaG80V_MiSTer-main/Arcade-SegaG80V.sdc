derive_pll_clocks
derive_clock_uncertainty

# Clock-domain crossings remain isolated even where clocks share the main PLL.
# All crossings use synchronizers, stable-data mailboxes, or the renderer's
# asynchronous source FIFO. Naming follows MajorHavoc.sdc, whose PLL
# configuration and renderer this core vendors.
set emu_clk_125 [get_clocks {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_vec [get_clocks {emu|machine_clocks|vec_pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set emu_clk_hps [get_clocks {*|h2f_user0_clk}]
set board_clk_50 [get_clocks {FPGA_CLK2_50}]
set sys_clk_50   [get_clocks {FPGA_CLK1_50}]
set sys_clk_audio [get_clocks {pll_audio|pll_audio_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}]
set sys_clk_hdmi [get_clocks {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}]

set_clock_groups -asynchronous \
	-group $emu_clk_125 \
	-group $emu_clk_vec

# The standalone vector-generator PLL is outside the framework PLL hierarchy.
set_clock_groups -asynchronous \
	-group $emu_clk_hps \
	-group $emu_clk_vec

set_clock_groups -asynchronous \
	-group $board_clk_50 \
	-group $emu_clk_vec

# MiSTer framework consumers sample stable core outputs in their own domains.
# They are asynchronous to the standalone vector/control PLL.
set_clock_groups -asynchronous -group $sys_clk_50 -group $emu_clk_vec
set_clock_groups -asynchronous -group $sys_clk_audio -group $emu_clk_vec
set_clock_groups -asynchronous -group $sys_clk_hdmi -group $emu_clk_vec
