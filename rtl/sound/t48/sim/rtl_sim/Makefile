
RTL_DIR   = $(PROJECT_DIR)/rtl/vhdl
T8243_DIR = $(RTL_DIR)/t8243
BENCH_DIR = $(PROJECT_DIR)/bench/vhdl

COMMONDEP=work
WORKDIR=--workdir=work

ELABORATE = ghdl -m $(WORKDIR)

testbenches = tb tb_t8048 

.PHONY: all
all: work
	$(ELABORATE) tb
	$(ELABORATE) tb_t8048
	$(ELABORATE) tb_t8039
	$(ELABORATE) tb_t8048_t8243
	$(ELABORATE) tb_t8243
	$(ELABORATE) tb_t8041
	$(ELABORATE) tb_t8041a
	$(ELABORATE) tb_t8042ah
	$(ELABORATE) tb_t8021
	$(ELABORATE) tb_t8022

.PHONY: clean
clean:
	ghdl --clean $(WORKDIR)
	rm -f *~ *.ghw *.hex

.PHONY: veryclean
veryclean: clean
	rm -rf work


.PHONY: run_behav
run_rom: $(COMMONDEP) work intel
	ghdl -m $(WORKDIR) tb_rom behav
	./tb_rom-behav --wave=tbrom.ghw

work:
	make import

.PHONY: import
import:
	mkdir -p work
	ghdl -i $(WORKDIR) $(RTL_DIR)/*.vhd
	ghdl -i $(WORKDIR) $(RTL_DIR)/system/*.vhd
	ghdl -i $(WORKDIR) $(T8243_DIR)/*.vhd
	ghdl -i $(WORKDIR) $(BENCH_DIR)/*.vhd
