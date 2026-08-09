Rendered directly from rtl/astrob_audio.sv via Verilator (no FPGA build).
Regenerate at any time:  verilator/vgen/render_all.sh

  invN.wav               voice N alone, 4 s. A/B directly against
                         Useful Information/ab_wavs/real_invN.wav
  inv1_warp.wav          WARP engaged. Only INV1 and INV3 have a warp path in
  inv3_warp.wav          the current RTL -- INV2/INV4 would be identical files
  all_four_together.wav  all four invader gates open at once

NOT rendered because they are not ported yet (silent in the RTL):
  LASER_1, LASER_2, SHORT_EXPL, LONG_EXPL, ASTROIDS, REFILL, BONUS, SONAR

NOT rendered because the V generator is absent as of the 2026-08-09 rebase:
  invN_ladder_sweep.wav  the CD4017 attack-rate pitch staircase. The RTL reads
                         latch_3f zero times, so there is nothing to sweep.
                         Re-enable in tb_wavdump.cpp once V is ported forward
                         from git 5b30d49.

Caveat: these are the raw mixed output of astrob_audio.sv. The real board has
analog filtering after this point that is not modelled, and MAME applies its
own netlist solve -- so expect our renders to be harsher/cleaner than either
reference even where the pitch and modulation are right.
