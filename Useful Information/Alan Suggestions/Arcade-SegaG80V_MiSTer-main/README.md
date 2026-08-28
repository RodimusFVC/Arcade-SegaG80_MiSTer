# Arcade-SegaG80V_MiSTer

Sega/Gremlin **G-80 X-Y (vector)** arcade hardware for MiSTer FPGA —
Eliminator, Space Fury, Zektor, Tac/Scan and Star Trek.

The game module is new; the vector-to-raster renderer and CRT pipeline are
[Videodr0me `videodr0me_fb`](https://github.com/Videodr0me/Arcade-MajorHavoc_MiSTer),
adapted for the Sega 2-bit-per-gun colour ladder. Inter-frame persistence uses
the Major Havoc sparse phosphor compositor; there is no separate present gate.

> **Status: running on real hardware.** All five games boot and render on a
> DE10-Nano, with controls and DIP menus for every game. **All four sound
> boards are implemented** — AY-3-8912, speech, Universal Sound Board and the
> discrete boards — and every game makes sound in simulation, but none of it
> has been heard through a speaker yet. See [Progress](#progress) and
> [HARDWARE-CHECKS.md](HARDWARE-CHECKS.md).

**No ROMs are included.** Nothing here works without them.

---

## Why this exists

There is no Sega G80 vector core on any FPGA platform. A GitHub search for
`sega g80 vector fpga` returns zero results; the arcade-hardware community has
wanted an X-Y board replacement for years and nobody has built one. This is the
first attempt.

## How it works

Sega's vector generator is a **DDA**: it walks the beam by at most one count per
2.578 MHz VCL clock, driven by a sin/cos PROM and a pair of 8-bit accumulators.
That means its output *is* the rasterised beam path — one `{x, y, colour, beam}`
sample per clock, which is exactly the feed `vfb_top` wants. No line drawer sits
in between.

The display list is two-level: a symbol list of 10-byte headers (position,
rotation, scale, and a pointer to a shape) and per-symbol vector lists of 4-byte
records (colour/beam attribute, length, angle). Rotation and scaling happen in
the vector generator, not on the Z80.

Full hardware notes: [`docs/01-hardware-reference.md`](docs/01-hardware-reference.md).

## Progress

| Component | State |
|---|---|
| Repo scaffold, vendored renderer + `sys/` | done |
| `rtl/sega_security.sv` — 315-0062/63/64/70/76/82 | **done, verified** |
| `rtl/xy/sega_xy.sv` — the vector generator | **done, verified** |
| `rtl/xy/sega_xy_top.sv` — vector RAM + sin PROM wrapper | done, lints clean |
| `rtl/sega_ports.sv` — LS253 matrix, spinner, elim4, multiplier | **done, verified** |
| `rtl/segag80v_cpu.sv` — Z80, memory/IO map, wait states, IRQ chain | **done, verified** |
| `rtl/videodr0me_fb/vfb_dac_ladder.sv` — 6-bit colour repack | **done, verified** |
| `rtl/sega_geometry.sv` — coordinate map + orientation | **done, verified** |
| `rtl/segag80v.sv` — machine (CPU + X-Y + ROM) | done, lints clean |
| `rtl/sega_video.sv` — mode timing + geometry + renderer | done, lints clean |
| `Arcade-SegaG80V.sv` + Quartus project + PLL + SDC | done, elaborates clean |
| MRAs for all 10 romsets | done, byte-verified against the sim images |
| Controls — all six games, from MAME's INPUT_PORTS | done |
| Spinner (Zektor, Tac/Scan, Star Trek) | done, untested on hardware |
| Audio: Zektor AY-3-8912 | done |
| Audio: speech board (8035 + SP0250) + output filter | **done, verified** |
| Audio: Universal Sound Board (8035 + 3x 8253) | **done, verified** |
| Audio: discrete boards (Eliminator, Zektor, Space Fury) | done — behavioural, see below |
| DIP switches as MRA `<switches>` | done |
| Hiscore save | **not implemented** |
| **Runs on real hardware** | **yes** |

No present gate: derpyder's Tempest core needs one because Tempest redraws its
list ~250x/sec and the framebuffer cuts lists mid-draw. Sega walks the whole
list exactly once per 40 Hz EDGINT with `DRAW` asserted throughout — the same
shape as Star Wars and Asteroids, which feed `FRAME_DONE` straight in.

## Verification

Every finished module is checked against MAME rather than by inspection.

```
cd sim
make all        # all 17 of the below
make security   # 315-00xx scrambler vs MAME's sega_decrypt* functions
make ports      # LS253 matrix, spinner, elim4 demux, multiplier vs MAME
make color6     # 2-bit-per-gun DAC ladder, all 64 colours x 1024 levels
make geometry   # vector field -> framebuffer coordinate map
make sp0250     # LPC speech synthesiser vs MAME, bit-exact
make usbtimer   # 8253 PIT vs MAME, bit-exact
make usbnoise   # MM5837 noise source vs MAME, bit-exact
make usbfilter  # USB analog chain vs MAME's double-precision model
make xy         # vector generator vs the MAME-derived golden model
make xy1        # same, with the alternate phase-clock reading
make cpu        # hand-assembled Z80 code through the real tv80 core
make boot       # boot all six real game ROMs end to end

make audio      # not a test: records 30 s of each game's audio to WAV
```

`make boot` needs `sim/roms/<set>.rom`, built from MAME romsets by
`tools/build_rom.py`. `make xy` additionally picks up `sim/vramdumps/` if
present. Neither directory is committed — see `.gitignore`.

Current results:

```
sega_security_scramble: 458752 checked, 0 failed          # exhaustive
sega_ports:              24641 checked, 0 failed
vfb_dac_ladder:           4096 checked, 0 failed, worst error 1 LSB
sp0250:                 100000 samples, 0 failed, 128 of 128 DAC values
usb_timer:             6000000 comparisons, 0 failed
usb_noise:              400000 steps, 0 failed
usb_filter:             349999 samples, correlation 1.00000 vs MAME
sega_xy: sine PROM = real (roms/s-c.xyt-u39)
sega_xy: 48 real vector-RAM snapshots
sega_xy: 90 cases, 819710 golden samples, 0 failed
  coverage: beam-on 459842, clipped 201760, colour changes 4755,
            budget-limited cases 7, largest frame 53375 samples
segag80v_cpu: 6 vector-RAM writes observed in 268 clocks
  ok  scrambled write $E000 -> addr 000 data AA
  ok  scrambled write $E134 -> addr 184 data 55
  ok  scrambled write $E278 -> addr 278 data 5A
  ok  unscrambled LD (HL)   -> addr 334 data 99
  ok  IN ($F8) then write   -> addr 420 data F6
  ok  ISR write (interrupt) -> addr 520 data C3
wait-state timing: 0w=178 1w=223 2w=268 (deltas 45, 45)
  ok  one extra clock per memory cycle per wait state

boot (150 frames each, real ROMs; also coins up and checks the credit lands):
  elim2     66908 beam samples, 19 colours   PASS
  elim4     71923 beam samples, 19 colours   PASS
  spacfury  52747 beam samples, 31 colours   PASS
  zektor    57983 beam samples, 16 colours   PASS
  tacscan   41145 beam samples, 16 colours   PASS  + USB uploaded 4096 bytes
  startrek  17949 beam samples, 63 colours   PASS  + USB uploaded 4096 bytes
```

## Does it actually run the games?

Yes. `make boot` loads a real romset, runs the Z80 through its self-test into
attract mode, and checks the display list it builds and the beam path the X-Y
boards walk from it.

The strongest evidence is a direct comparison against MAME. A Lua write tap
(`tools/tap_vram.lua`) captures MAME's vector-RAM writes; the bench captures the
same stream from the RTL. **All 4000 writes are identical.**

One caveat that cost real debugging time and is worth writing down: MAME's write
tap sits on the CPU bus *upstream* of the driver's `decrypt_offset()`, so it
reports the address **before** the security chip scrambles it. Two writes
therefore look like divergences when the RTL is right. `LD ($E172),A` at PC
`$2E06` uses permutation B under 315-0070, giving `$E10E` — which is what the
RTL wrote and what actually lands in RAM.

Rendering the captured display list (`tools/render.cpp`) reproduces the games'
attract screens: Eliminator's arena with "PLAY ELIMINATOR © GREMLIN 1981",
Zektor's title and credits, Star Trek's three-colour logo.

`sim/golden/segag80v_golden.cpp` is a transcription of MAME's
`sega_generate_vector_list()`. The arithmetic is unchanged; the only deliberate
difference is output granularity — MAME emits a compressed endpoint list because
its renderer draws lines, while this model (and the RTL) emit every DDA step.
The bench drives both with identical vector RAM and requires the sample streams
to match exactly, on hand-built display lists, on lists placed to stay on
screen, on lists far too large for one 40 Hz frame, on pure noise, and — once
`sim/roms/` and `sim/vramdumps/` are populated — on **real display lists
captured from all six games** with the real `s-c.xyt-u39` sine PROM.

The security test is genuinely exhaustive: only `pc[0]` and one of `pc[1]`,
`pc[3]`, `pc[4]` can affect the result, so sweeping the low 8 bits of the PC
against all 256 data values covers the entire input space for all six chips.

`make cpu` runs hand-assembled Z80 code through the real tv80 core, because the
security chip depends on the CPU's actual opcode-fetch timing and cannot be
verified any other way. It covers the memory map, the scrambler in situ, an
`IN ($F8)` through the LS253 matrix, and an EDGINT interrupt reaching the IM 1
handler. Wait states are checked separately by building the same design at
`WAIT_STATES` 0, 1 and 2 and requiring the clock count to be linear — the run
must lengthen by exactly one clock per memory cycle per wait state. That check
caught a real bug: `wait_n` derived from an edge detect asserts a clock after
tv80 samples it in T2, so the design was silently running with no wait states
at all.

## Colour

Sega drives each gun from a 2-bit resistor ladder: 64 colours where the guns can
sit at different levels at once. `videodr0me_fb` stores 3-bit RGB plus a Z
intensity, which can only express hue x brightness.

A census of 576 real display lists dumped from MAME settled whether that
mattered: **42 of the 64 colours are non-proportional and cover 22% of all
beam-on samples**, led by `R3 G1 B0` orange at 8% on its own. So the renderer
colour path was widened to true 6-bit — five files, documented under "Local
modifications" in [`Research/vendored-sources.md`](Research/vendored-sources.md),
with the method and full results in
[`Research/colour-census.md`](Research/colour-census.md).

## Audio

All four sound boards are implemented, but they are **not equally trustworthy**
and the README should say so plainly:

| Board | Games | How it is verified |
|---|---|---|
| AY-3-8912 | Zektor | jt49, a standard part |
| Speech board — 8035 + SP0250 | Space Fury, Zektor, Star Trek | **SP0250 bit-exact vs MAME**; output filter transcribed from `nl_segaspeech.cpp` |
| Universal Sound Board — 8035 + 3x 8253 | Tac/Scan, Star Trek | **8253 and MM5837 bit-exact**; analog chain correlates **0.999587** with MAME's double-precision model on real gameplay |
| Discrete boards | Eliminator, Zektor, Space Fury | **behavioural reconstruction — nothing to diff against** |

The discrete boards are the weak link. MAME models them only as SPICE-style
netlists — 30 KB each of 555 timers, CA3080 transconductance amps and CD4011
one-shots — so there is no simplified model to port and no reference to check
against. What *is* faithful is the bit-to-sound map (from the netlist `ALIAS`
lines), the fact that the latch bits are **active low**, and the final mixer
weights, which were read off Sega drawing 800-3174 sheet 8 and show skitter and
enemy ship sitting 20 dB below everything else. The envelope times and pitches
are estimates.

Two divergences between MAME and the Sega drawings were found and are recorded
in [`HARDWARE-CHECKS.md`](HARDWARE-CHECKS.md): the speech board's **R19 is 270K
on drawing 800-0294, not MAME's 250k** (fixed here), and MAME's note that R20
"should be 470 Ohm" refers to a different, simpler drawing — 800-0294 shows
4.7K, which confirms the op-amp gain.

`make audio` runs a real game through the whole machine, coins up, presses
start, and records each board separately to WAV at 48 kHz. It is a listening
aid, not a pass/fail test, and it is how the speech filter was checked against a
real cabinet recording (spectral match 0.24 unfiltered, **0.84 filtered**).

**None of this has been heard through a speaker.** See
[`HARDWARE-CHECKS.md`](HARDWARE-CHECKS.md) §7.

## Open question

The one unresolved hardware detail is how fast the phase generator runs. MAME
charges 16 VCL clocks per phase and still carries a *"the games seem to run too
fast"* note in its header. Reading U51 (LS161) driving U50 (LS154) on
`XY_Timing_800-0161` sheet 7/7 suggests it may be one clock per phase. This sets
how much of the display list fits in a 40 Hz frame and how long the `DRAW` flag
the games poll stays asserted.

It is a parameter (`PHASE_CLKS`) and both readings pass their tests, so the
decision can wait until it can be measured against a booting game.

## Building

Quartus 17.0.x Lite, the standard MiSTer toolchain. Open
`Arcade-SegaG80V.qpf` and compile, or:

```
quartus_sh --flow compile Arcade-SegaG80V
```

The output is `output_files/Arcade-SegaG80V.rbf`. Copy it to `_Arcade/cores/`
on the SD card and put the `.mra` files in `_Arcade/`.

Requires the **32 MB SDRAM module** in addition to DDR3: `videodr0me_fb` keeps
its halo-alignment delay line in SDRAM.

MRAs are generated from the MAME driver so filenames and CRCs cannot drift:

```
python3 sim/tools/make_mra.py <path-to>/segag80v.cpp mra
```

`sim/tools/make_mra.py` and `sim/tools/build_rom.py` emit the same byte layout,
so what the MRA assembles on hardware is exactly what the simulation boots:

```
0x00000-0x0BFFF   48K program ROM
0x0C000-0x0C3FF   s-c.xyt-u39 sin/cos PROM
0x0C400-0x0CBFF   speech board 8035 program      (Space Fury, Zektor, Star Trek)
0x0CC00-0x10BFF   speech board LPC data
```

MRA `index 1` carries a single game-identifier byte; `rtl/sega_game_pkg.sv`
decodes it into the security chip, sound board, control panel and screen
orientation, so a new romset needs only an MRA.

## Layout

```
rtl/sega_security.sv     315-00xx address scrambler
rtl/xy/sega_xy.sv        vector generator (X-Y Control + X-Y Timing boards)
rtl/xy/sega_xy_top.sv    + vector RAM and sin/cos PROM
rtl/sega_ports.sv        LS253 input matrix, spinner, elim4 demux, multiplier
rtl/segag80v_cpu.sv      Z80, memory/IO map, wait states, interrupt chain
rtl/segag80v.sv          machine: CPU + X-Y + ROM + all four sound boards
rtl/sega_video.sv        mode timing, coordinate map, vfb_top
rtl/sega_geometry.sv     vector field -> framebuffer
rtl/sega_inputs.sv       control panel wiring
rtl/sega_game_pkg.sv     per-game configuration from the MRA id byte
rtl/sound/sega_ay.sv         Zektor AY-3-8912 (jt49), DC-blocked
rtl/sound/sega_speech.sv     speech board: 8035 + SP0250
rtl/sound/sp0250.sv          LPC synthesiser, bit-exact
rtl/sound/speech_filter.sv   speech board output filter
rtl/sound/sega_usb.sv        Universal Sound Board: 8035 + timers + noise
rtl/sound/usb_timer.sv       8253 PIT      usb_noise.sv   MM5837
rtl/sound/usb_filter.sv      USB analog chain, multiplier-free
rtl/sound/sega_discrete.sv   discrete boards + discrete_blocks.sv
Arcade-SegaG80V.sv       MiSTer top level
mra/                     one MRA per romset
rtl/videodr0me_fb/       vendored renderer — do not edit, see Research/
rtl/{tv80,i8035,tv48,jt49}/  vendored CPU and sound cores
sim/golden/              MAME-derived reference models
sim/tb/                  Verilator benches
docs/                    hardware reference, research, audio notes
Research/                pinned upstream commits, transcription notes
HARDWARE-CHECKS.md       what still needs eyes and ears on real hardware
```

## Documentation

| File | What it is |
|---|---|
| [`HARDWARE-CHECKS.md`](HARDWARE-CHECKS.md) | **start here for a hardware session** — what cannot be checked in simulation |
| [`docs/01-hardware-reference.md`](docs/01-hardware-reference.md) | the G-80 X-Y boards: memory map, vector generator, timing |
| [`docs/03-audio-plan.md`](docs/03-audio-plan.md) | all four sound boards, in detail |
| [`docs/04-component-catalog.md`](docs/04-component-catalog.md) | component inventory, upstream pins, and upgrade recommendations |
| [`docs/00-research-summary.md`](docs/00-research-summary.md) | the original survey: prior art, sources, scope |
| [`Research/colour-census.md`](Research/colour-census.md) | the data behind the 6-bit colour decision |
| [`Research/vendored-sources.md`](Research/vendored-sources.md) | pinned upstream commits and every local change to them |

## Credits

- **Videodr0me** — `videodr0me_fb` vector renderer and CRT pipeline, and the
  Asteroids / Star Wars / Major Havoc cores this is built on. If you enjoy the
  vector render effects, please support his work:
  **[buymeacoffee.com/videodr0me](https://buymeacoffee.com/videodr0me)**
- **Aaron Giles / MAME** — the gate-level analysis of the Sega vector generator
  in `segag80v_v.cpp`, without which this would be a much longer project.
- **derpyder** — the Tempest core, which showed how to graft a non-Atari game
  onto the chassis.
- **JimmyStones** — `i8035`, and **Arnim Laeuger's T48** core underneath it,
  needed for both Sega sound-board CPUs.
- **Jose Tejada (jotego)** — `jt49`, the AY-3-8912 used by Zektor.
- **Mark Jenison** — the Sega/Gremlin X-Y FAQ.

## Licence

GPL-3.0, inherited from the vendored Videodr0me sources.
