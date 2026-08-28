# Audio — the four sound boards

> **All four are implemented.** This started as a plan and is now a record of
> what was built and how far each part can be trusted. Nothing here has been
> heard through a speaker; see [`../HARDWARE-CHECKS.md`](../HARDWARE-CHECKS.md)
> §7 for what to listen for.

The standard held to is the one the rest of this core is built on and that
Videodr0me set for his own audio: **model the hardware, verify against MAME,
don't approximate where the real thing is knowable.** Three of the four boards
meet it. The discrete boards cannot, and say so.

| # | Subsystem | Games | Status |
|---|---|---|---|
| 1 | AY-3-8912 | Zektor | **done** — jt49, DC-blocked |
| 2 | Speech board (8035 + SP0250) | Space Fury, Zektor, Star Trek | **done** — SP0250 bit-exact, output filter added |
| 3 | Universal Sound Board (8035 + 3× 8253) | Tac/Scan, Star Trek | **done** — 8253/MM5837 bit-exact, chain 0.999587 vs MAME |
| 4 | Discrete boards | Eliminator, Space Fury, Zektor | **done — behavioural, no reference to check against** |

---

## 1. AY-3-8912 — done

`rtl/sound/sega_ay.sv`. Zektor is the only X-Y game with a PSG.

- `AY8912` at `VIDEO_CLOCK/4/2` = 15468480/8 = 1.93356 MHz, from a fractional
  enable off `clk_12`.
- `$3C` latches the register address, `$3D` writes it — MAME's `write_ay()`
  calls `address_data_w(offset, data)`, where offset 0 is the address latch.
- `jt49` (vendored, GPL-3.0) provides the PSG.
- MAME sets `AY8910_RESISTOR_OUTPUT` with equal 10k loads on all three
  channels, so the per-channel linearised outputs are summed passively rather
  than using jt49's pre-mixed `sound`.

The `$3C/$3D` strobe is taken on the **falling** edge of the I/O cycle. `io_wr`
is a level held for the whole cycle and `ce_cpu` pulses several times inside
one; strobing per enable writes the register repeatedly. This is the same trap
the `$BD/$BE` multiplier hit — see `rtl/segag80v_cpu.sv`.

## 2. Speech board — done, not yet heard

**Hardware:** 8035 @ 3.12 MHz + **SP0250** LPC synthesiser, drawing 800-0294
(`refs/schematics/Speech_Board_800-0294_sheet5of5.png`). Reached at `$38`
(data) and `$3B` (control), both already decoded by `segag80v_cpu`.

**ROM:** `speech:cpu` 2 KB, `speech:data` up to 12 KB, plus a 32-byte 6331
addressing PROM. Present in `spacfury.zip`, `zektor.zip` and `startrek.zip`;
the MRA and `build_rom.py` both need extending to place them.

**What exists:** `rtl/i8035/i8035.v` is already vendored from
`Arcade-SegaVICZ80_MiSTer`. The SP0250 needs writing.

**References for the SP0250:**
- MAME `src/devices/sound/sp0250.cpp` — the authoritative decoder.
- `refs/cores/sega-vector/tools/wav2lpc.py` — a genuine SP0250 LPC **encoder**
  written from the SP0250 Applications Manual, with the real filter
  coefficient tables. Being able to encode as well as decode makes this
  testable end to end.

**SP0250: done and verified.** `rtl/sound/sp0250.sv`, checked against a C++
port of MAME's model (`sim/golden/sp0250_golden.*`) by `make sp0250`:

```
sp0250: 100000 samples, 15660 frame bytes, 0 failed
  coverage: 94760 non-zero samples, 128 distinct DAC values of 128
```

Every one of the 128 possible DAC values is exercised, so this is a real
sample-for-sample match and not a lucky quiet stretch.

Notes worth keeping:

* The lattice arithmetic **wraps at 16 bits** in the original
  (`z0 = in + ((z1*F)>>8) + ((z2*B)>>9)` on `int16_t`). The RTL truncates
  rather than saturating, deliberately.
* The LFSR is used **after** clocking, not before — getting that backwards
  costs you every unvoiced sample.
* The DAC is `z0 >> 6` as a signed 10-bit value, then clamped to -64..63.
* The RTL decides whether to load a frame at the *start* of a sample, nine
  clocks before it emits it, where MAME decides at emit time. The bench steps
  the model on `sample_start` and compares on `sample_stb` so both make the
  decision at the same logical instant. Comparing at the wrong point makes the
  FIFO states disagree for those nine clocks and the frames misalign.

**Board glue: done.** `rtl/sound/sega_speech.sv`, with the port wiring from
`segaspeech.cpp`:

| Signal | Behaviour |
|---|---|
| P1 in | `latch & 0x7F` |
| P1 out | bit 7 low clears T0 |
| P2 out | speech-data ROM bank, `[5:0]` selects a 256-byte page |
| I/O read | `speech_data[0x100 * (P2 & 0x3F) + addr]` |
| I/O write | SP0250 frame byte |
| T0 | set when latch bit 7 goes 0 -> 1 |
| T1 | SP0250 DRQ |
| INT | latch bit 7 inverted |

`$38` writes the latch, `$3B` is control: bit 3 gates speech output, bit 5
gates the off-board (USB) audio on Star Trek.

Two details that are easy to get wrong:

* **`I_EA` must be high.** The 8035 has no internal ROM — that is what
  distinguishes it from the 8048 — so it always fetches externally.
* **P2 is multiplexed.** The low nibble carries PC[11:8] during a program
  fetch and the written P2 register otherwise, exactly as on the real part.
  That is fine to use live for both the program address and the speech-data
  bank, because PSEN and RD never overlap. MAME sidesteps this by tracking the
  register in its `p2_w` callback and handling program fetch internally.

ROM image, now shared by `build_rom.py` and `make_mra.py`:

```
$00000  48K  program
$0C000   1K  sin/cos PROM
$0C400   2K  speech board 8035 program (mirrored at $0800 in its own space)
$0CC00  16K  speech board LPC data
```

Every MRA is checked to assemble byte-identical to the simulation image, so
what lands in FPGA memory is what the bench boots.

**Unverified:** none of this has been heard. The SP0250 is bit-exact against
MAME and the glue lints clean, but the 8035 has never been observed executing
the speech program. See `HARDWARE-CHECKS.md`.

**Note:** MAME's `segag80v.h` still `#include`s `tms5110.h`, which is
misleading — the real part is the SP0250 (`segaspeech.cpp` includes
`sound/sp0250.h`). Only the Italian *Advisor* bootleg uses a TMS5100, and it is
unimplemented in MAME too.

## 3. Universal Sound Board — done, unheard on hardware

**Hardware:** 8035 @ 6 MHz, three 8253 PITs, DACs, an MM5837 noise source and
analog filters. Drawing 800-0377, three sheets, in `refs/schematics/`.

**No ROM of its own** — the main Z80 downloads the program into the shared RAM
window at `$D000-$DFFF`, which is why that window goes through the security
scrambler. It is already wired in `segag80v_cpu`; the `usb_*` ports are
currently stubbed off in `segag80v.sv`.

Built as `rtl/sound/sega_usb.sv` (digital half) plus `rtl/sound/usb_timer.sv`,
`usb_noise.sv` and `usb_filter.sv`. MAME's model is `segausb.cpp` (850 lines)
plus `nl_segausb.cpp` (545 lines of netlist for the analog side); this core
follows the non-netlist path, which is the one MAME runs by default.

Clocks from MAME: `USB_MASTER_CLOCK` 6 MHz, `USB_2MHZ_CLOCK` = /3,
`USB_PCS_CLOCK` = /2 again, `USB_GOS_CLOCK` = /16/4, `MM5837_CLOCK` 100 kHz.

### 8253 — done and verified

`rtl/sound/usb_timer.sv`, checked against a C++ port of MAME's `timer8253` by
`make usbtimer`:

```
usb_timer: 6000000 output comparisons, 1999239 channel clocks, 4953 writes, 0 failed
  coverage: output transitions ch0=6577 ch1=5391 ch2=6405
```

Only clock modes 1 (one-shot) and 3 (square wave) are implemented, matching
MAME — the board's program uses no others, and a real 8253's remaining modes
would be dead logic.

One thing to know: **a register write and a channel clock landing on the same
cycle must be ordered write-then-clock.** MAME applies the write and then
clocks within the same stream update; plain non-blocking assignments let the
clock read pre-write state and the outputs diverge. The RTL sequences through
local variables to get this right. This is the third time this exact hazard has
come up in this core (the `$BD/$BE` multiplier, the SP0250 FIFO, and now here).

### The board — digital half

`rtl/sound/sega_usb.sv`. Mirrors the speech board.

**Digital**

| Piece | Detail |
|---|---|
| 8035 | 6 MHz, `I_EA` high, same wiring pattern as `sega_speech.sv` |
| Program RAM | 4K at `$0000-$0FFF`, **shared with the main Z80 at `$D000-$DFFF`**, routed through `segag80v_cpu`'s scrambler |
| Work RAM | 1K as four 256-byte banks, `P2[1:0]` selects; the 8035's whole I/O space maps to it |
| Control decode | writes to work RAM offsets `$00-$17`: `$00-$03` 8253 U41, `$04-$07` ENV0, `$08-$0B` 8253 U42, `$0C-$0F` ENV1, `$10-$13` 8253 U43, `$14-$17` ENV2. `$x7` bit 0 is that group's `config` bit |
| P1 in | `in_latch & 0x7F` |
| P1 out | bit 7 -> bit 0 of the output latch |
| P2 out | `[1:0]` work RAM bank, bit 6 ready/clears the input latch when low, bit 7 resets the U33 counter |
| T1 | `t1_clock & t1_clock_mask`, the mask set by board jumpers |
| Host | `$3F` read returns `(out_latch & 0x81) \| (in_latch & 0x7E)`; `$3F` write loads the input latch |

Clock enables, all from the 6 MHz master: `2MHZ = /3`, `PCS = 2MHZ/2`,
`GOS = 2MHZ/16/4`, and the MM5837 noise clock at 100 kHz.

Timer clocking: channels 0 and 1 clock at PCS with the gate held high; channel
2 clocks at 2 MHz with its gate toggling at GOS/2.

**MM5837 noise — done and verified.** `rtl/sound/usb_noise.sv`, 17-bit LFSR
with taps at 13 and 16, checked against MAME by `make usbnoise` over 400,000
steps.

The seed matters: **all-zero is a lock-up state** for this polynomial. MAME
seeds `0x15555` in `device_start` and so does the RTL. Both were initially
stuck at zero and the comparison passed with 0 failures — the coverage check
(output should be high about half the time) is what caught it. Worth
remembering that a stuck DUT matches a stuck model.

### Three things the /LOAD bit ties together

Bit 7 of the input latch (`$3F` write) is `/LOAD`, and it does three jobs that
have to move together. Getting one of them wrong is silent — the board just
plays nothing, or plays garbage:

1. It **holds the 8035 in reset** while set (MAME asserts `INPUT_LINE_RESET`).
2. It **gates writes to the shared program RAM** — `ram_w` drops the write
   unless `in_latch & 0x80`. So the program can only be loaded while the 8035
   is stopped, which is the whole point.
3. While the 8035 has CLEAR low (P2 bit 6), a host write to `$3F` **keeps only
   bit 7** and discards the low seven bits.

`$3F` is a level for the whole I/O cycle, so `segag80v.sv` strobes it on the
falling edge like the speech board's `$38`/`$3B`. That level-vs-edge trap has
now bitten four separate times in this core.

### Analog chain

MAME runs its stream at **2 MHz** and applies seventeen one-pole filters per
sample:

- 3 poles plus a direct term on the noise source, then a CR filter and a trim
- 4 per group x 3 groups: two channel CR filters, two switched gate RC filters
  whose exponents are selected by that group's channel 2 output
- 1 final CR

Each is `capval += (input - capval) * exponent` (RC) or the CR variant.

**Fidelity note:** MAME's own comment calls the noise filter *"just an
approximation to the pink noise filter being applied on the PCB, but it sounds
pretty close"*, and the whole chain is `double`. So unlike the 8253, the SP0250
and the vector generator, **there is no bit-exact target here.**

What is checkable is that the topology and evaluation order match MAME exactly
and that every coefficient is close. `rtl/sound/usb_filter.sv` is Q8.24 fixed
point, and **every filter coefficient is a sum of at most four signed
powers of two, so the filters need no multipliers at all** — the closest is
0.03% and the worst 0.55%. Only the three envelope DAC gains need real
multipliers, and the sequencer shares one set across the three groups by
processing one group per clock (noise, three groups, final mix — five of the
six clocks available per 2 MHz tick).

`make usbfilter` scores the RTL against a transcription of MAME's double
chain. It cannot demand bit equality, so it asks the questions that matter for
a filter — shape, magnitude, level, boundedness — plus coverage, because a
filter comparison that passes on silence proves nothing:

```
usb_filter: 349999 samples scored
  golden  rms 0.39329  peak 3.26496  mean +0.00566
  rtl     rms 0.39257  peak 3.25354  mean +0.00592
  correlation 1.00000   rms ratio 0.9982   peak abs error 0.01142
  saturated samples 0   headroom used 3.25 of 4.0
  coverage: config0 595000 config1 605000  gate-slow 600728 gate-fast 599272
```

**Headroom.** MAME's own value for this chain reaches 3.26 on a worst-case
stimulus, so mapping its nominal 1.0 to 16-bit full scale would clip the
board's own peaks. The RTL maps 1.0 to a quarter of full scale (12 dB of
headroom) and lets the core's mixer set the level.

**Two ordering details worth keeping**, both easy to get subtly wrong:

- The gate filters are stepped **within** the sample and their output is used
  immediately — in config 0 it feeds channel 2, in config 1 it filters the
  already-summed mix. Using the stored value instead adds a sample of delay and
  changes the topology.
- Channel 2's gate toggles every **32** 2 MHz ticks, not 64 or 128: MAME's
  `USB_2MHZ_CLOCK / USB_GOS_CLOCK / 2` is `64 / 2`.

### Routing

Per MAME's `machine_config`, the two games differ:

- **Tac/Scan** — `SEGAUSB(...).add_route(..., "speaker", 1.0)`, straight out.
- **Star Trek** — `SEGAUSB(...).add_route(..., "speech", 1.0, 1)`, into the
  speech board's CD4053 aux input, gated by speech control bit 5.

`cfg_speech` in `sega_game_pkg.sv` picks between them so the mix never
double-counts the board.

## 4. Discrete boards — done, but behavioural

**Implemented in `rtl/sound/sega_discrete.sv` and `discrete_blocks.sv`.**

Eliminator, Space Fury and Zektor each have an analog sound board driven by
latches at `$3E/$3F`. MAME models them as netlists: `nl_elim.cpp` is 1227 lines
(and also carries Zektor's), `nl_spacfury.cpp` 1106.

There is no simplified MAME model to port and nothing to diff against, so each
channel is a behavioural voice — an envelope times an oscillator or the shared
MM5837 noise, through a one-pole filter. **Read every envelope time and pitch
below as an estimate.** What *is* faithful:

* the bit-to-sound map, from the netlist `ALIAS` lines (tabulated below);
* the latch bits being **active low** — the games park `$3E/$3F` at `$FF` and
  pull a bit low to trigger. MAME hides this by passing the raw bit into the
  netlist and letting the CD4011 stages invert it. Backwards, every voice turns
  on at once;
* the Eliminator/Zektor **final mixer weights**, read off Sega drawing 800-3174
  rev B sheet 8 — U9 is a TL082 inverting summer with Rf = 10K, so each source's
  gain is 10K/Rin. Skitter and enemy ship land 20 dB below everything else,
  which the netlist does not make obvious;
* the noise source being an MM5837, confirmed by the same drawing.

Space Fury's mixer has not been extracted; its weights are still guesses.

The trigger lines are named in the netlists, so the scope is known exactly:

**Eliminator** — 7 lines at `$3E`, 8 at `$3F`:

| Line | Sound | | Line | Sound |
|---|---|---|---|---|
| LO D1 | Fireball | | HI D0 | Thrust low |
| LO D2 | Explosion 1 | | HI D1 | Thrust high |
| LO D3 | Explosion 2 | | HI D2 | Thrust level LSB |
| LO D4 | Explosion 3 | | HI D3 | Thrust level MSB |
| LO D5 | Bounce | | HI D4 | Skitter |
| LO D6 | Torpedo 1 | | HI D5 | Enemy ship |
| LO D7 | Torpedo 2 | | HI D6/D7 | Background level |

**Space Fury** — 5 at `$3E`, 6 at `$3F`: crafts scale, moving, thrust, star
spin, partial warship, crafts joining, shoot, fireball, small explosion, large
explosion, docking bang.

So roughly 9 one-shots plus two 2-bit **level** controls (thrust, background)
for Eliminator, and 11 lines for Space Fury.

### Two routes

**(a) RTL analog modelling**, the way Videodr0me did `asteroids_cabinet_audio.sv`.
Highest fidelity and consistent with the rest of this core. These are 555
timers, op-amp filters and noise sources — tractable, but 2300 lines of netlist
is real work.

**(b) Samples** via `wave_sound.sv` from `Arcade-SegaVICZ80_MiSTer`. Much
faster, with two problems:
- MAME no longer ships sample sets for these games (it moved to netlists), so
  samples would have to be rendered from the netlist or recorded from real
  hardware.
- The continuous, parameterised sounds — thrust and background, each with a
  2-bit level — do not map onto one-shot playback.

**Recommendation: (a).** Route (b) cannot represent the level-controlled
sounds, which are a large part of what Eliminator sounds like, and "quality
first" was the explicit brief. Route (b) is a reasonable *interim* if we want
audible sound early, but it should not be the destination.

### SDRAM constraint if (b) is ever used

`wave_sound` is SDRAM-backed, but `videodr0me_fb` already owns SDRAM for its
halo-alignment delay and keeps all four banks' rows open
(`vfb_sdram_core.sv`). Samples would have to live in DDR3 instead, or share
under a carefully arbitrated scheme. Settle this before committing.

---

## Mixing — as built

Every board is scaled so its own peaks land between -9 and -16 dBFS, then summed
at full weight with saturation in `Arcade-SegaG80V.sv`. Measured over 30 s of
gameplay via `make audio`:

| Game | Levels |
|---|---|
| Eliminator | discrete -12.1 dBFS |
| Space Fury | speech -14.2, discrete -10.3 |
| Zektor | AY -12.1, speech -13.6, discrete -12.0 |
| Tac/Scan | USB -9.4 |
| Star Trek | speech -15.8 (the USB arrives inside it) |

Within Eliminator and Zektor the *relative* weights are real (drawing 800-3174
sheet 8). The level of each board against the others is judgement and needs an
ear.

MAME's own `add_route` weights, for reference:

- Eliminator: discrete only, output scale 0.15
- Space Fury: discrete (scale 2.0) into the speech board, then to the speaker
- Zektor: discrete (0.15) + AY (routed through the same netlist) into speech
- Tac/Scan: USB only
- Star Trek: USB into the speech board

Note that on Space Fury, Zektor and Star Trek the sound board feeds *through*
the speech board rather than mixing beside it, so the speech board's analog
stage colours the whole mix. `nl_segaspeech.cpp` (120 lines) is the filter.
