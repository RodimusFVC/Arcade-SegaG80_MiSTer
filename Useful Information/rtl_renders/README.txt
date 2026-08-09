Rendered directly from rtl/astrob_audio.sv via Verilator (no FPGA build).
Regenerate at any time:  verilator/vgen/render_all.sh

  invN.wav               voice N alone, V ladder held at step Q0.
                         Q0 is the reset state, which is where the board's
                         test-mode capture was taken -- so these line up
                         directly with Useful Information/ab_wavs/real_invN.wav
  invN_warp.wav          same, with WARP engaged
  all_four_together.wav  all four invader gates open at once
  invN_ladder_sweep.wav  voice N walked through all ten CD4017 attack-rate
                         steps, 0.8 s each -- the pitch staircase in isolation

NOT rendered because they are not ported yet (silent in the RTL):
  LASER_1, LASER_2, SHORT_EXPL, LONG_EXPL, ASTROIDS, REFILL, BONUS, SONAR

Caveat: these are the raw mixed output of astrob_audio.sv. The real board has
analog filtering after this point that is not modelled, and MAME applies its
own netlist solve -- so expect our renders to be harsher/cleaner than either
reference even where the pitch and modulation are right.
