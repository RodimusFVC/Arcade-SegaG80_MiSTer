# T48 MCS-48 / 8035 Core

**Upstream**: https://github.com/devsaurus/t48  
**Version**: Release 1.4 (downloaded as zip; no commit hash available)  
**License**: GPL-2.0 (see `COPYING`)  
**Author**: Arnim Laeuger (arniml@opencores.org)

## Why this core

Chosen over JT* and OpenCores alternatives because it is battle-tested in
production MiSTer cores (Donkey Kong 3, Scramble, others), supports 8035 mode
via `ea_i = '1'`, exposes a clean `xtal_en_i` clock-gate for integration with
clk_sys, and has a complete verification suite. VHDL is non-ideal given the
project's SystemVerilog direction, but pragmatic given the alternative is
writing an MCS-48 from scratch.

## Local modifications

None. Files vendored verbatim. Any future local change must be marked with
a `-- LOCAL:` comment on the modified line.

## 8035 / 8039 mode

The 8035 is the ROM-less variant of the MCS-48 family. Configure `t48_core`
with `ea_i = '1'` to force all program fetches through the external program
memory interface (`pmem_addr_o` / `pmem_data_i`). Wire an external BRAM
containing `808b.u7` to those ports.

The `t8039_notri` system module (used for the smoke test) ties `pmem_data_i`
to 0x00 (NOP) and leaves `pmem_addr_o` open. For production use in
`segaspeech.sv`, instantiate `t48_core` directly and wire the BRAM.

## Port list summary (t48_core)

| Port | Dir | Width | Function |
|------|-----|-------|----------|
| `xtal_i` | in | 1 | Clock (tie to `clk_sys`) |
| `xtal_en_i` | in | 1 | Clock gate on xtal input |
| `clk_i` | in | 1 | Core clock (tie to `clk_sys`) |
| `en_clk_i` | in | 1 | Core clock enable (tie to `xtal3_o` feedback) |
| `xtal3_o` | out | 1 | xtal ÷ 3 enable; feed back to `en_clk_i` |
| `reset_i` | in | 1 | Active-high reset |
| `ea_i` | in | 1 | 1 = external ROM (8035 mode) |
| `int_n_i` | in | 1 | INT, active-low |
| `t0_i/t0_o/t0_dir_o` | bidir | 1 | T0 test input / quasi-bidir |
| `t1_i` | in | 1 | T1 test input |
| `p1_i/p1_o/p1_low_imp_o` | bidir | 8 | Port 1 |
| `p2_i/p2_o/p2l/p2h_low_imp_o` | bidir | 8 | Port 2 (low/high nibble drive indicators) |
| `db_i/db_o/db_dir_o` | bidir | 8 | BUS port (MOVX / INS / OUTL BUS) |
| `rd_n_o/wr_n_o` | out | 1 | BUS read / write strobes (active-low) |
| `ale_o` | out | 1 | Address latch enable |
| `psen_n_o` | out | 1 | Program store enable (active-low) |
| `prog_n_o` | out | 1 | Program pulse (8243 expander; unused here) |
| `pmem_addr_o` | out | 12 | External program memory address |
| `pmem_data_i` | in | 8 | External program memory data |
| `dmem_addr_o` | out | 8 | Internal data RAM address |
| `dmem_we_o` | out | 1 | Internal data RAM write enable |
| `dmem_data_i/o` | bidir | 8 | Internal data RAM data |

## Clock integration (clk_sys = 15.468 MHz, target MCU = ~208 kHz)

```
xtal_i    = clk_sys
xtal_en_i = ce_3_12m   (pulse every ~5 clk_sys cycles ≈ 3.12 MHz)
clk_i     = clk_sys
en_clk_i  = xtal3_o    (feedback from core; xtal ÷ 3 = ~1.04 MHz)
```

The core then divides by 5 clock states internally, yielding:
`3.12 MHz ÷ 3 ÷ 5 = 208 kHz` effective instruction rate.

## Files used in this project

Only the RTL and system files needed for t8039/t48_core. Bench files,
t8243 expander, UPI-41 variants, and adc.vhd (8022 only) are not compiled.
