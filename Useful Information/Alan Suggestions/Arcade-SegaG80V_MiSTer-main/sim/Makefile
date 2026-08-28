# Verilator benches for Arcade-SegaG80V_MiSTer
#
#   make security   exhaustive check of the 315-00xx address scrambler
#   make xy         X-Y vector generator vs the MAME golden model
#   make all        both
#   make clean

RTL      := ../rtl
VFLAGS   := -Wall -Wno-fatal --cc --exe --build -j 0 -O2 \
            -DTV80_REFRESH \
            -CFLAGS "-O2 -std=c++17"

.PHONY: all security ports color6 geometry sp0250 usbtimer usbnoise usbfilter xy xy1 cpu boot audio clean

all: security ports color6 geometry sp0250 usbtimer usbnoise usbfilter xy xy1 cpu boot

# ---------------------------------------------------------------------------

obj_security/Vsega_security_scramble: $(RTL)/sega_security.sv tb/tb_security.cpp
	verilator $(VFLAGS) --Mdir obj_security \
		--top-module sega_security_scramble \
		$(RTL)/sega_security.sv tb/tb_security.cpp

security: obj_security/Vsega_security_scramble
	@./obj_security/Vsega_security_scramble

# ---------------------------------------------------------------------------

obj_sp0250/Vsp0250: $(RTL)/sound/sp0250.sv tb/tb_sp0250.cpp \
                    golden/sp0250_golden.cpp golden/sp0250_golden.h
	verilator $(VFLAGS) --Mdir obj_sp0250 \
		--top-module sp0250 \
		-CFLAGS "-I../golden" \
		$(RTL)/sound/sp0250.sv tb/tb_sp0250.cpp golden/sp0250_golden.cpp

sp0250: obj_sp0250/Vsp0250
	@./obj_sp0250/Vsp0250

# ---------------------------------------------------------------------------

obj_usbtimer/Vusb_timer: $(RTL)/sound/usb_timer.sv tb/tb_usb_timer.cpp \
                         golden/usb_timer_golden.h
	verilator $(VFLAGS) --Mdir obj_usbtimer \
		--top-module usb_timer \
		-CFLAGS "-I../golden" \
		$(RTL)/sound/usb_timer.sv tb/tb_usb_timer.cpp

usbtimer: obj_usbtimer/Vusb_timer
	@./obj_usbtimer/Vusb_timer

obj_usbnoise/Vusb_noise: $(RTL)/sound/usb_noise.sv tb/tb_usb_noise.cpp
	verilator $(VFLAGS) --Mdir obj_usbnoise \
		--top-module usb_noise \
		$(RTL)/sound/usb_noise.sv tb/tb_usb_noise.cpp

usbnoise: obj_usbnoise/Vusb_noise
	@./obj_usbnoise/Vusb_noise

obj_usbfilter/Vusb_filter: $(RTL)/sound/usb_filter.sv tb/tb_usb_filter.cpp \
                           golden/usb_filter_golden.h
	verilator $(VFLAGS) --Mdir obj_usbfilter \
		--top-module usb_filter \
		-CFLAGS "-I../golden" \
		$(RTL)/sound/usb_filter.sv tb/tb_usb_filter.cpp

usbfilter: obj_usbfilter/Vusb_filter
	@./obj_usbfilter/Vusb_filter

# ---------------------------------------------------------------------------
# Audio capture: runs a real game through the whole machine and writes WAVs.
# Not part of `make all` — it is a listening aid, not a pass/fail check.

obj_audio/Vaudio_wrap: $(RTL)/segag80v.sv $(RTL)/segag80v_cpu.sv \
                     $(RTL)/sega_ports.sv $(RTL)/sega_security.sv \
                     $(RTL)/xy/sega_xy.sv $(RTL)/xy/sega_xy_top.sv \
                     $(RTL)/sound/sega_speech.sv $(RTL)/sound/speech_filter.sv $(RTL)/sound/sp0250.sv \
		$(RTL)/sound/discrete_blocks.sv $(RTL)/sound/sega_discrete.sv \
                     $(RTL)/sound/sega_ay.sv $(RTL)/sound/sega_usb.sv \
                     $(RTL)/sound/usb_timer.sv $(RTL)/sound/usb_noise.sv \
                     $(RTL)/sound/usb_filter.sv $(RTL)/sega_inputs.sv \
                     tb/audio_wrap.sv tb/tb_audio.cpp golden/usb_filter_golden.h
	verilator $(VFLAGS) -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD \
		-Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-CASEX \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-CASEINCOMPLETE \
		--no-timing --Mdir obj_audio --top-module audio_wrap \
		-CFLAGS "-I../golden" -I$(RTL) -I$(RTL)/tv80 \
		tb/audio_wrap.sv \
		$(RTL)/segag80v.sv $(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv \
		$(RTL)/sega_security.sv $(RTL)/sega_game_pkg.sv $(RTL)/sega_inputs.sv \
		$(RTL)/xy/sega_xy.sv $(RTL)/xy/sega_xy_top.sv \
		$(RTL)/sound/sega_speech.sv $(RTL)/sound/speech_filter.sv $(RTL)/sound/sp0250.sv \
		$(RTL)/sound/discrete_blocks.sv $(RTL)/sound/sega_discrete.sv \
		$(RTL)/sound/sega_ay.sv $(RTL)/sound/sega_usb.sv \
		$(RTL)/sound/usb_timer.sv $(RTL)/sound/usb_noise.sv \
		$(RTL)/sound/usb_filter.sv \
		$(RTL)/i8035/i8035.v $(RTL)/spram.v $(RTL)/tv48/*.v \
		$(RTL)/jt49/*.v \
		$(RTL)/tv80/tv80e.v $(RTL)/tv80/tv80_core.v $(RTL)/tv80/tv80_alu.v \
		$(RTL)/tv80/tv80_mcode.v $(RTL)/tv80/tv80_reg.v \
		tb/tb_audio.cpp

AUDIO_SECS ?= 25

audio: obj_audio/Vaudio_wrap
	@mkdir -p audio
	@./obj_audio/Vaudio_wrap roms/zektor.rom   3 $(AUDIO_SECS) audio/zektor
	@./obj_audio/Vaudio_wrap roms/spacfury.rom 2 $(AUDIO_SECS) audio/spacfury
	@./obj_audio/Vaudio_wrap roms/tacscan.rom  4 $(AUDIO_SECS) audio/tacscan
	@./obj_audio/Vaudio_wrap roms/startrek.rom 5 $(AUDIO_SECS) audio/startrek

# ---------------------------------------------------------------------------

obj_geometry/Vsega_geometry: $(RTL)/sega_geometry.sv tb/tb_geometry.cpp
	verilator $(VFLAGS) --Mdir obj_geometry \
		--top-module sega_geometry \
		$(RTL)/sega_geometry.sv tb/tb_geometry.cpp

geometry: obj_geometry/Vsega_geometry
	@./obj_geometry/Vsega_geometry

# ---------------------------------------------------------------------------

obj_color6/Vvfb_dac_ladder: $(RTL)/videodr0me_fb/vfb_dac_ladder.sv tb/tb_color6.cpp
	verilator $(VFLAGS) --Mdir obj_color6 \
		--top-module vfb_dac_ladder \
		$(RTL)/videodr0me_fb/vfb_dac_ladder.sv tb/tb_color6.cpp

color6: obj_color6/Vvfb_dac_ladder
	@./obj_color6/Vvfb_dac_ladder

# ---------------------------------------------------------------------------

obj_ports/Vports_wrap: $(RTL)/sega_ports.sv tb/ports_wrap.sv tb/tb_ports.cpp
	verilator $(VFLAGS) --Mdir obj_ports \
		--top-module ports_wrap \
		tb/ports_wrap.sv $(RTL)/sega_ports.sv tb/tb_ports.cpp

ports: obj_ports/Vports_wrap
	@./obj_ports/Vports_wrap

# ---------------------------------------------------------------------------

obj_cpu/Vsegag80v_cpu: $(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv \
                       $(RTL)/sega_security.sv tb/tb_cpu.cpp
	verilator $(VFLAGS) -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD \
		-Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-CASEX \
		--no-timing -CFLAGS "-I../golden" \
		--Mdir obj_cpu --top-module segag80v_cpu \
		-I$(RTL)/tv80 \
		$(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv $(RTL)/sega_security.sv \
		$(RTL)/tv80/tv80e.v $(RTL)/tv80/tv80_core.v $(RTL)/tv80/tv80_alu.v \
		$(RTL)/tv80/tv80_mcode.v $(RTL)/tv80/tv80_reg.v \
		tb/tb_cpu.cpp

# A zero-wait-state build, used only to confirm that wait states are inserted
# uniformly per memory cycle (the delta must be linear in WAIT_STATES).
obj_cpu0/Vsegag80v_cpu: $(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv \
                        $(RTL)/sega_security.sv tb/tb_cpu.cpp
	verilator $(VFLAGS) -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD \
		-Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-CASEX \
		--no-timing -CFLAGS "-I../golden" \
		--Mdir obj_cpu0 --top-module segag80v_cpu -GWAIT_STATES=0 \
		-I$(RTL)/tv80 \
		$(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv $(RTL)/sega_security.sv \
		$(RTL)/tv80/tv80e.v $(RTL)/tv80/tv80_core.v $(RTL)/tv80/tv80_alu.v \
		$(RTL)/tv80/tv80_mcode.v $(RTL)/tv80/tv80_reg.v \
		tb/tb_cpu.cpp

obj_cpu1/Vsegag80v_cpu: $(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv \
                        $(RTL)/sega_security.sv tb/tb_cpu.cpp
	verilator $(VFLAGS) -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD \
		-Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-CASEX \
		--no-timing -CFLAGS "-I../golden" \
		--Mdir obj_cpu1 --top-module segag80v_cpu -GWAIT_STATES=1 \
		-I$(RTL)/tv80 \
		$(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv $(RTL)/sega_security.sv \
		$(RTL)/tv80/tv80e.v $(RTL)/tv80/tv80_core.v $(RTL)/tv80/tv80_alu.v \
		$(RTL)/tv80/tv80_mcode.v $(RTL)/tv80/tv80_reg.v \
		tb/tb_cpu.cpp

# End-to-end: boot real game ROMs through the CPU + X-Y boards.
# Needs sim/roms/<set>.rom, built by tools/build_rom.py.
obj_boot/Vboot_wrap: $(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv \
                     $(RTL)/sega_security.sv $(RTL)/xy/sega_xy.sv \
                     $(RTL)/xy/sega_xy_top.sv $(RTL)/sound/sega_usb.sv \
                     $(RTL)/sound/usb_timer.sv $(RTL)/sound/usb_noise.sv \
                     $(RTL)/sound/usb_filter.sv tb/boot_wrap.sv tb/tb_boot.cpp
	verilator $(VFLAGS) -Wno-PINCONNECTEMPTY -Wno-TIMESCALEMOD \
		-Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-CASEX \
		--no-timing --Mdir obj_boot --top-module boot_wrap \
		-I$(RTL)/tv80 \
		tb/boot_wrap.sv $(RTL)/segag80v_cpu.sv $(RTL)/sega_ports.sv \
		$(RTL)/sega_security.sv $(RTL)/xy/sega_xy.sv $(RTL)/xy/sega_xy_top.sv \
		$(RTL)/sound/sega_usb.sv $(RTL)/sound/usb_timer.sv \
		$(RTL)/sound/usb_noise.sv $(RTL)/sound/usb_filter.sv \
		$(RTL)/i8035/i8035.v $(RTL)/spram.v $(RTL)/tv48/*.v \
		$(RTL)/tv80/tv80e.v $(RTL)/tv80/tv80_core.v $(RTL)/tv80/tv80_alu.v \
		$(RTL)/tv80/tv80_mcode.v $(RTL)/tv80/tv80_reg.v \
		tb/tb_boot.cpp

# chip ids: 3=315-0064 4=315-0070 5=315-0076 6=315-0082
# 150 frames (~3.75 emulated seconds) is enough for every game to clear its
# self-test and reach attract mode, where it actually draws.
boot: obj_boot/Vboot_wrap
	@./obj_boot/Vboot_wrap roms/elim2.rom    4 150
	@./obj_boot/Vboot_wrap roms/elim4.rom    5 150
	@./obj_boot/Vboot_wrap roms/spacfury.rom 3 150
	@./obj_boot/Vboot_wrap roms/zektor.rom   6 150 0 1
	@./obj_boot/Vboot_wrap roms/tacscan.rom  5 150 1 1
	@./obj_boot/Vboot_wrap roms/startrek.rom 3 150 1 1

cpu: obj_cpu/Vsegag80v_cpu obj_cpu0/Vsegag80v_cpu obj_cpu1/Vsegag80v_cpu
	@./obj_cpu/Vsegag80v_cpu
	@w0=`./obj_cpu0/Vsegag80v_cpu | sed -n 's/^CLOCKS=//p'`; \
	 w1=`./obj_cpu1/Vsegag80v_cpu | sed -n 's/^CLOCKS=//p'`; \
	 w2=`./obj_cpu/Vsegag80v_cpu  | sed -n 's/^CLOCKS=//p'`; \
	 d1=$$((w1 - w0)); d2=$$((w2 - w1)); \
	 echo "wait-state timing: 0w=$$w0 1w=$$w1 2w=$$w2 (deltas $$d1, $$d2)"; \
	 if [ "$$d1" -eq "$$d2" ] && [ "$$d1" -gt 0 ]; then \
	   echo "  ok   one extra clock per memory cycle per wait state"; \
	 else \
	   echo "  FAIL wait states are not uniform per memory cycle"; exit 1; \
	 fi

# ---------------------------------------------------------------------------

obj_xy/Vsega_xy: $(RTL)/xy/sega_xy.sv \
                 tb/tb_xy.cpp golden/segag80v_golden.cpp golden/segag80v_golden.h
	verilator $(VFLAGS) --Mdir obj_xy \
		--top-module sega_xy \
		-CFLAGS "-I../golden" \
		$(RTL)/xy/sega_xy.sv \
		tb/tb_xy.cpp golden/segag80v_golden.cpp

xy: obj_xy/Vsega_xy
	@./obj_xy/Vsega_xy 16

# Same comparison with the alternate reading of the phase generator: one VCL
# clock per phase instead of sixteen. See docs/01-hardware-reference.md §2.
obj_xy1/Vsega_xy: $(RTL)/xy/sega_xy.sv \
                  tb/tb_xy.cpp golden/segag80v_golden.cpp golden/segag80v_golden.h
	verilator $(VFLAGS) --Mdir obj_xy1 \
		--top-module sega_xy -GPHASE_CLKS=1 \
		-CFLAGS "-I../golden" \
		$(RTL)/xy/sega_xy.sv \
		tb/tb_xy.cpp golden/segag80v_golden.cpp

xy1: obj_xy1/Vsega_xy
	@./obj_xy1/Vsega_xy 1

clean:
	rm -rf obj_security obj_ports obj_color6 obj_geometry obj_sp0250 obj_usbtimer obj_usbnoise obj_usbfilter obj_audio obj_boot obj_cpu obj_cpu0 obj_cpu1 obj_xy obj_xy1
