# Hardware verification checklist

For whoever takes this to the DE10-Nano. Everything in `sim/` is verified
against MAME in simulation; this file lists only what **cannot** be checked
without real hardware, plus what is known good so you don't re-test it.

Run `cd sim && make all` first — 17/17 should pass before a build is worth
doing. If any of those fail, fix that before touching Quartus.

---

## Confirmed working on hardware

Do not re-verify unless something regressed.

| Date | What |
|---|---|
| 2026-08-03 | All five games boot, render attract screens, DE10-Nano |
| 2026-08-04 | Havoc renderer migration, 125 MHz PLL, new clock topology |
| 2026-08-05 | Controls, DIP menus and game startup (TV80 refresh register) |

### Resource note

The Universal Sound Board adds a second 8035 (`tv48`), 4K of shared program RAM
and 1K of work RAM. If the fit gets tight, that is the newest thing in the
build. `usb_filter.sv` is deliberately multiplier-free apart from three shared
envelope DAC gains, so it should cost logic rather than DSPs.

---

## Open — needs eyes on a screen

### 1. `READ_ADVANCE` — one-pixel alignment

`rtl/videodr0me_fb/vfb_readout.sv` sets `READ_ADVANCE = 10` where Major Havoc
uses 9. The Sega colour path is one register deeper than Havoc's (the shoulder
add is registered ahead of the per-gun ladder), and `READ_ADVANCE` sizes the
sync/blank shift register to match the datapath depth.

Reasoned from the stage count, never seen. **Check:** the picture should not be
shifted one pixel horizontally relative to its blanking, and the leftmost
column should not show the previous line's last pixel. If it looks worse than
with 9, revert it and say so.

### 2. Colour — the whole point of the 6-bit work

Sega drives each gun from a 2-bit ladder; `vfb_dac_ladder.sv` implements
0 / ⅓ / ⅔ / full. Verified numerically, never seen.

**Check:** Eliminator should show a distinct **orange** (`R3 G1 B0`) — 8% of
all its beam-on samples, and the single colour that motivated this work. If it
looks red or yellow rather than orange, the ladder or the colour field is
wrong. Space Fury and Star Trek use nearly the whole 64-colour palette, so
banding or wrong hues there are also a tell.

### 3. `PHASE_CLKS` — the one unresolved hardware question

`rtl/xy/sega_xy.sv` parameter, currently **16** (MAME's value). MAME's own
header says *"the games seem to run too fast"*. Reading U51/U50 on
`XY_Timing_800-0161` sheet 7/7 suggests it may be 1.

Both values pass the golden-model tests, so only hardware can settle it.
**Check:** does attract-mode animation and object motion run at a plausible
speed? If everything looks too fast or too slow, rebuild with `PHASE_CLKS = 1`
and compare. Whichever looks right, record it here.

### 4. Controls

Transcribed from MAME's `INPUT_PORTS_START` blocks, reworked on 2026-08-05
along with the MRA control metadata and DIP menus. `make boot` now exercises
both the `$FC` spinner-game Start path and the `$D5D4` matrix path and checks
that Start consumes a credit, so the wiring is proven in simulation.

**Check per game:** buttons do what the label says, both players work, and for
Eliminator 4-player that players 3 and 4 respond — they come through a demux on
the `$F8` select latch, which is the fiddliest part and the only one the boot
bench does not cover.

### 5. Spinner — never exercised at all

Zektor, Tac/Scan and Star Trek. Uses `hps_io` `spinner_0/1` (toggle strobe with
a signed delta), with the d-pad as a fallback.

**Check:** a real spinner or mouse rotates the ship smoothly in both
directions, and the self-test's spinner reading counts *upward* whichever way
you turn (that is deliberate — the port returns a monotonic count with
direction in bit 0). Sensitivity may well need tuning; the divider is in
`Arcade-SegaG80V.sv`.

### 6. Tac/Scan orientation

The only game with swapped axes (`SWAP_XY | FLIP_X | FLIP_Y`), rendered into a
portrait 832×1024 target. **Check:** it is rotated the right way and fills the
screen sensibly at 720p and 1080p.

### 7a. Fixed: the t48 core ignored T0

`rtl/tv48/t48_core.v` passed both T0 and T1 into the conditional-branch unit
through a std_logic table lookup that the VHDL-to-Verilog translation gets
wrong. `t1_i` had already been bypassed with a hand edit; `t0_i` had not. The
result was that **`JT0` / `JNT0` never saw the pin**, so `JNT0` took its branch
forever.

That is exactly what the Sega speech board polls to notice a pending word:

```
22E: JT1 239      ; DRQ set -> feed the SP0250 a frame   (worked: T1 was patched)
230: JNT0 22E     ; T0 clear -> keep waiting             (never fell through)
232: IN A,P1      ; T0 set -> read the word number
233: CALL 43B     ; ack: OUTL P1,#7F pulses P1.7 low, clearing T0
```

So the 8035 sat in that four-instruction loop forever, dutifully feeding the
SP0250 silence, which is why the board fed exactly 15 bytes per DRQ and every
byte was 00. With `t0_i` wired directly the program advances: addresses touched
went 166 -> 299 and all three of Space Fury's power-on words are now consumed.

This affects **both** sound boards — they are the only users of `i8035`.

### 7b. Sound status by game (2026-08-05)

All boards are now implemented and every game makes sound. Measured by
`make audio`, which coins up, starts, and records 30 s at 48 kHz.

| Game | Boards | State | Level |
|---|---|---|---|
| Eliminator 2P/4P | discrete | works | -10.3 dBFS |
| Space Fury | speech + discrete | both work | speech -13.4, discrete -10.3 |
| Zektor | AY + speech + discrete | all work | AY -12.1, speech -13.2, discrete -10.3 |
| Tac/Scan | Universal Sound Board | works | -9.4 dBFS |
| Star Trek | speech + USB via CD4053 | both work | speech -15.8 dBFS |

Everything now lands between -9 and -16 dBFS, so the boards sit together
without one burying another.

**How much to trust each board.** This matters, because they are not equal:

| Board | Verification |
|---|---|
| 8253, MM5837, SP0250 | bit-exact against MAME, exhaustive benches |
| USB analog chain | correlation 0.999587 with MAME on real gameplay |
| Speech output filter | transcribed from `nl_segaspeech.cpp`; spectral match to a cabinet recording 0.84 |
| **Discrete boards** | **behavioural reconstruction, nothing to diff against** |

The discrete boards are the weak link and are labelled as such in the source.
MAME models them only as netlists — 30 KB each of 555s, CA3080 OTAs and CD4011
one-shots — so there is no simplified model to port and no reference to check
against. What is faithful is the bit-to-sound map, taken from the ALIAS lines
in `nl_elim.cpp` and `nl_spacfury.cpp`, and the fact that **the latch bits are
active low** (the games park $3E/$3F at $FF and pull a bit low to trigger;
getting that backwards turns every voice on at once, which is how it was found).
The envelope times and pitches are estimates. Only one is grounded: Eliminator
and Zektor's U13 is a 555 astable at R59 2k + R61 47k + C30 0.022uF = 682 Hz,
which sets the torpedo.

**So the discrete boards need an ear more than anything else in this core.**
Expect the right *kind* of sound in the right place at the right time, but not
the right timbre. Per-channel netlist tracing is the way to tighten them.

### 7c. MAME vs the Sega schematics — where they differ

Checked MAME's netlists against the drawings in `refs/schematics/` and the
Eliminator manual. Four things worth recording:

| What | MAME | Schematic | Verdict |
|---|---|---|---|
| Speech R19 | 250k | **270K** (800-0294 rev H sh.5) | schematic; 250k is not an E24 value and MAME does not document the change. **Fixed.** |
| Speech R20 | 4.7k, noted "schematic shows 470Ohm" | **4.7K** on 800-0294 | MAME right. The 470R is on the *other*, simpler drawing in the Astro Blaster / Space Fury manuals. Gain 3.128 confirmed. |
| Speech U8 pins 2/3 | swapped vs schematic | drawn signal→pin 2 | MAME right, verified from a working PCB. As drawn the amp cannot work. |
| Space Fury oscillators | split to 105.8/105.7/105.9 Hz | one shared osc | MAME deliberate, for netlist isolation. Real value ~105.8 Hz. |

The R19 fix moves the speech low pass 167.5 -> 166.5 Hz. Negligible, but there
was no reason to carry someone else's typo.

**The valuable find was Eliminator's final mixer**, Sega drawing 800-3174 rev B
sheet 8. U9 is a TL082 inverting summer with Rf = R5 = 10K and each source
arrives through its own resistor, so the weights are simply 10K/Rin:

| Source | Rin | Gain | vs BUFFER |
|---|---|---|---|
| PSG (the AY, fitted on Zektor) | R10 10K | 2.20 | +6.8 dB |
| BUFFER — the summed event voices | R8 22K | 1.00 | reference |
| divider chain / hexagons | R9 33K | 0.667 | -3.5 dB |
| SKITTER | R6 220K | 0.100 | -20 dB |
| ENEMY SHIP | R7 220K | 0.100 | -20 dB |

Skitter and enemy ship sitting **20 dB below** everything else is not something
the netlist makes obvious, and the first cut had them at equal weight. Now
applied. The same drawing also confirms the board's noise source is an **MM5837**
(U4), which is the polynomial `discrete_blocks.sv` already used, and it labels
HI D6/D7 as **HEXAGONS**, not MAME's BACKGROUND.

Space Fury's own mixer has not been extracted yet — its weights are still
guesses.

### 7d. Known gap: the speech board filter corner

`speech_filter.sv` uses the 0.047u C10 the netlist specifies, giving a 167.5 Hz
low pass. That is aggressive for speech, and 0.047u is a small value to read off
a schematic, so the module has a `C10_TENTH` parameter that moves it to
1675 Hz. The measured spectral match against a cabinet recording went from 0.24
unfiltered to 0.84 filtered, so 167 Hz is defensible — but if it sounds muffled
on hardware, try the parameter before assuming the filter is wrong.

### 7e. Audio — what to listen for

Everything below works in simulation and **none of it has been through a
speaker**. That is the whole point of this section.

- **Eliminator** makes sound at all. It was completely silent until the
  discrete board landed, so this is the clearest pass/fail on the board.
- **Space Fury speaks** — *"So, a creature for my amusement. Prepare for
  battle!"* — and its discrete board plays under it.
- **Zektor** has all three: AY music, speech, and discrete effects.
- **Tac/Scan makes music.** The Universal Sound Board's only outing where
  nothing else can mask it; Star Trek has the speech board too.
- **Star Trek** speaks, with the USB arriving through the speech board's CD4053.
- Nothing clicks, buzzes, or clips.

**Balance is the thing most likely to be wrong.** Every board is scaled to peak
between -9 and -16 dBFS and they are summed at full weight with saturation in
`Arcade-SegaG80V.sv`. Within Eliminator and Zektor the *relative* weights are
real — read off drawing 800-3174 sheet 8 — but the level of each board against
the others is judgement, and so is all of Space Fury's discrete mix.

If a board is silent rather than mis-levelled, the plumbing is already proven in
simulation, so suspect the mix or the OSD before the board: `make audio`
records each source separately and will show whether the board itself is
producing anything.

**MRAs must be regenerated** if you are coming from an old checkout — the ROM
image grew from 0xC400 to 0x10C00 bytes to carry the speech ROMs, and an old
MRA will load a truncated image.

---

## Timing

`SEED 2` in the `.qsf` and `Arcade-SegaG80V.sdc` follow `MajorHavoc.sdc`.

If it stops closing, check the timing report for **unconstrained clocks** first
— particularly `emu_clk_vec`, which comes from the standalone `sega_clocks`
PLL outside the framework hierarchy and needs its own asynchronous groups
against `FPGA_CLK1_50`, `pll_audio` and `pll_hdmi`. Those groups are already in
the SDC; if the instance path changes they will silently match nothing.

## Requirements

- Quartus 17.0.x Lite
- **32 MB SDRAM module** in addition to DDR3 — `videodr0me_fb` keeps its
  halo-alignment delay line in SDRAM
- ROMs are not included; MRAs are in `mra/`

## Reporting back

Anything that needs changing: note the game, the video mode, and what you saw.
For colour and geometry a photo is worth more than a description — the
simulation can reproduce the display list exactly (`sim/tools/render.cpp`), so
a picture makes it possible to tell a rendering bug from a machine bug.
