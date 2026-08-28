# Sega G80 vector on MiSTer — research summary

> **Note on `refs/` paths.** This document cites local research material
> — scanned Gremlin schematics, game manuals and MAME driver sources —
> that is not redistributed here. See
> [`docs/00-research-summary.md`](00-research-summary.md) for where each
> item came from, and `sim/tools/` for the scripts that regenerate the
> ROM-derived artefacts locally.


Date: 2026-08-03. All cited material is mirrored under `../refs/`.

> **This is the original survey, kept as a record of what was known before any
> code was written.** Its conclusions held up, but for the state of the core see
> [`../README.md`](../README.md). Two open questions it raises were answered
> later: the colour question by [`../Research/colour-census.md`](../Research/colour-census.md)
> (6-bit repack was necessary), and every "write it" in §5 has since been
> written.

---

## 1. Is anyone working on this?

**No.** As far as I can find, there is no Sega G80 vector FPGA project of any kind —
not on MiSTer, not on any other platform, not even a stalled one.

Evidence:

- GitHub repository search for `sega g80 vector fpga` returns **0 results**.
- Searches for `Zektor` / `Space Fury` / `Tac/Scan` / `Eliminator` combined with
  verilog/vhdl/fpga return no game implementations.
- The `MiSTer-devel` org has no G80 vector repo. The nearest Sega/Gremlin core,
  [`Arcade-SegaVICZ80_MiSTer`](https://github.com/MiSTer-devel/Arcade-SegaVICZ80_MiSTer)
  (JimmyStones), is **VIC Dual** raster hardware — Carnival, Head On, Pulsar. It
  explicitly does not cover G80 raster or vector.
- On the arcade-hardware side, the only related activity is
  [`smdjeff/sega-vector`](https://github.com/smdjeff/sega-vector), a bare-metal
  *software* dev kit for running homebrew on real G80 boards — the author's stated
  position is "not emulated, not MAME, no FPGA."
- Arcade-museum threads about G80 X-Y board replacement contain only
  "someone should build an FPGA replacement someday" — nothing shipped.

So this would be the first implementation of Sega's vector generator in hardware
since 1982. That also means there is no upstream to coordinate with, and no risk of
duplicating someone's in-flight work.

**Battlestar is not buildable.** "Battle Star" was an unreleased 1982 Sega/Gremlin
G80 vector conversion of Space Fury. A marquee survives; no board and no ROM has
ever surfaced, and it is absent from MAME. Note that *all* Space Fury boards are
silkscreened "Battle Star", which is why it keeps appearing in for-sale listings —
board markings are not evidence of a dump. Scope the project at the five dumped
titles: **Eliminator (2P/4P), Space Fury, Zektor, Tac/Scan, Star Trek**.

## 2. The rendering chassis you asked for

The developer is **Videodr0me**. Their vector work on MiSTer:

| Core | Notes |
|---|---|
| [`Arcade-Asteroids_MiSTer`](https://github.com/Videodr0me/Arcade-Asteroids_MiSTer) | Asteroids, Asteroids Deluxe, Lunar Lander. |
| [`Arcade-StarWars_MiSTer`](https://github.com/Videodr0me/Arcade-StarWars_MiSTer) | Star Wars, cycle-exact AVG. The best-documented integration. |
| [`Arcade-BlackWidow_MiSTer`](https://github.com/Videodr0me/Arcade-BlackWidow_MiSTer) | Black Widow / Gravitar. |
| [`Arcade-MajorHavoc_MiSTer`](https://github.com/Videodr0me/Arcade-MajorHavoc_MiSTer) | Dual-processor Major Havoc. |
| [`Arcade-Tempest_MiSTer`](https://github.com/Videodr0me/Arcade-Tempest_MiSTer) | Tempest. |

The reusable part is `rtl/videodr0me_fb/` — a tile-based vector-to-raster renderer
with a DDR3 framebuffer, an SDRAM-backed halo-alignment delay, and a CRT pipeline
(bloom, halo, phosphor decay LUTs, adaptive slot mask, Amplifone colour space, tone
mapping, dot scaling). Its `vfb_top` interface is small and game-agnostic:

```
X_VECTOR[10:0], Y_VECTOR[10:0], Z_VECTOR[7:0], COLOR[3:0]/RGB[2:0],
IS_DOT, BEAM_ON, FRAME_DONE, RENDER_WIDTH[11:0], RENDER_HEIGHT[11:0]
→ DDRAM + SDRAM + VGA out
```

**A game module's only job is to walk its own vector generator and emit one
`{x, y, z, colour, beam_on}` sample per `clk_12` tick, plus `FRAME_DONE` at the end
of the display list.** The Sega vector generator is a DDA that moves the beam by at
most one count per clock — this is precisely the feed the renderer wants, with no
line-drawing step in between.

## 3. Precedent: someone has already done this graft

[`derpyder/Arcade-Tempest_MiSTer`](https://github.com/derpyder/Arcade-Tempest_MiSTer)
built a Tempest core by hosting a new game module inside Videodr0me's Star Wars
project. Its README was useful as an early grafting reference:

- **Reused unchanged:** the vector framebuffer, the MISTER_FB scan-out, the audio
  chain, the OSD/DIP infrastructure, clock/CDC plumbing, `sys/`.
- **Written new:** the CPU + memory map (transcribed from the MAME driver), a
  game-specific vector generator, and a coordinate map into the framebuffer.

The Tempest list-accumulating present gate is not appropriate for Sega. Sega emits
one complete list per 40 Hz `FRAME_DONE`; the Major Havoc `vfb_buffer_controller`
and sparse `vfb_phosphor_compositor` provide the required inter-frame persistence
after completed frames.

## 4. Documentation situation — good

I did not expect the schematics to be this complete, but they are.

- **`refs/mame/segag80v_v.cpp` is the real prize.** Aaron Giles reverse-engineered
  the vector generator to the gate and wrote the model as a phase-by-phase
  narration, naming the schematic sheet and chip designator for every latch. It is
  an RTL specification that happens to be written in C++. Nothing comparable
  existed for Tempest when derpyder started.
- **Full X-Y board schematics are mirrored** in `refs/schematics/` at 300 dpi and
  are legible: X-Y Timing 800-0161 sheets 5–7 and X-Y Control 800-0163 sheets 5–6,
  from the Star Trek manual. I verified every chip MAME names against the drawings
  — U15–U20 position counters, U8 25LS14 multiplier, U2 attribute latch and its
  2-bit-per-gun resistor DACs, U10–U12 vector-address counters, U51/U50 phase
  generator, the 15.46848 MHz crystal and its ÷0x1F788 40 Hz chain. They agree.
- Universal Sound Board, Speech Board, CPU board and EPROM board schematics are
  mirrored too.
- Full game manuals for all five titles are in `refs/manuals/`.

## 5. Building blocks already available in open cores

| Need | Source | Repo |
|---|---|---|
| Z80 | `tv80` | `Arcade-SegaVICZ80_MiSTer` (or T80 from any MiSTer core) |
| **8035** (speech board *and* Universal Sound Board) | `rtl/i8035.v` | `Arcade-SegaVICZ80_MiSTer` |
| AY-3-8912 (Zektor) | `rtl/jt49/` | `Arcade-SegaVICZ80_MiSTer` |
| Vector renderer + CRT pipeline, including inter-frame decay | `rtl/videodr0me_fb/` | `Arcade-MajorHavoc_MiSTer` |
| MRA-driven ROM loading, hiscore save | `rtl/games.v`, `rtl/hiscore.v` | `Arcade-SegaVICZ80_MiSTer` |
| 8253 PIT (USB sound) | none found — write it | — |
| SP0250 LPC synth (speech) | none found in a MiSTer core — write it or start from MAME's `sp0250.cpp` | — |

Everything is GPL-compatible (the Videodr0me cores are GPL-3.0/GPL-2.0+).

**As built:** `tv80`, `i8035` (with Arnim Laeuger's T48 underneath) and `jt49`
were all reused as expected. The 8253 and SP0250 were written from MAME and are
bit-exact against it — `rtl/sound/usb_timer.sv` and `rtl/sound/sp0250.sv`. The
MM5837 noise source and both analog chains were also written from scratch.
**Hiscore save was not taken** and is still not implemented.

## 6. The one real design conflict

Sega's colour is **2 bits per gun, 64 colours, binary intensity**. Atari's AVG is
**1 bit per gun plus an 8-bit Z intensity**. The framebuffer stores 16 bits per
pixel as `{rgb[2:0], draw_idx[3:0], spare, z[7:0]}` — verified identical in both
the Star Wars and Asteroids copies — so there is exactly **one spare bit**, and
6-bit colour needs three more.

Two ways out:

1. Repack to `{rgb[5:0], draw_idx[3:0], z[5:0]}`. Sega's intensity is binary, so
   6 bits of Z headroom is generous. Touches `vfb_rasterizer`, `vfb_readout` and
   the colour resolution at the end of the pipeline.
2. Measure first: instrument MAME and count how many of the 64 attribute colours
   the five games actually emit. Early vector games often use a handful. If the
   used set collapses onto "hue × brightness", the existing 3-bit RGB + Z path
   carries it unchanged and the renderer is untouched.

Do (2) before committing to (1). It is an afternoon of work and may save the only
invasive change in the project.

**Answered:** the census was run over 576 real display lists and (1) was
necessary — 42 of the 64 colours are non-proportional, covering 22% of beam-on
samples. See [`../Research/colour-census.md`](../Research/colour-census.md).

## Sources

- [Videodr0me/Arcade-StarWars_MiSTer](https://github.com/Videodr0me/Arcade-StarWars_MiSTer)
- [Videodr0me/Arcade-Asteroids_MiSTer](https://github.com/Videodr0me/Arcade-Asteroids_MiSTer)
- [derpyder/Arcade-Tempest_MiSTer](https://github.com/derpyder/Arcade-Tempest_MiSTer)
- [derpyder/Arcade-StarWars_MiSTer](https://github.com/derpyder/Arcade-StarWars_MiSTer)
- [MiSTer-devel/Arcade-SegaVICZ80_MiSTer](https://github.com/MiSTer-devel/Arcade-SegaVICZ80_MiSTer)
- [smdjeff/sega-vector](https://github.com/smdjeff/sega-vector)
- [shupac800/sega-xy-diagnostic](https://github.com/shupac800/sega-xy-diagnostic)
- [Sega/Gremlin X-Y FAQ v1.6, Mark Jenison](http://www.mikesarcade.com/cgi-bin/spies.cgi?action=url&type=info&page=segaxyfaq1.6.txt)
- [System 16 — Sega G80 Vector Hardware](https://www.system16.com/hardware.php?id=686)
- [arcarc.xmission.com PDF manual archive](https://arcarc.xmission.com/PDF_Arcade_Manuals_and_Schematics/)
- [Arcade Museum — Battle Star](https://www.arcade-museum.com/Videogame/battle-star)
- [unMAMEd Sega Games](https://unmamed.mameworld.info/non_sega.html)
- [NEW CORE: Atari Star Wars (1983) — MiSTer FPGA Forum](https://misterfpga.org/viewtopic.php?t=10405)
- [NEW CORE: Asteroids, Asteroids Deluxe & Lunar Lander — MiSTer FPGA Forum](https://misterfpga.org/viewtopic.php?p=111134)
