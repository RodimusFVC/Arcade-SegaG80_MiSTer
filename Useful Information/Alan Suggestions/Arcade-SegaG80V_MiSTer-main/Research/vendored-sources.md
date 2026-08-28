# Vendored sources — pinned commits

Vendored on 2026-08-03. Do not edit vendored trees in place unless the change is
listed under "Local modifications" below, so upstream updates can be rebased.

| Path in this repo | Upstream | Commit |
|---|---|---|
| `rtl/videodr0me_fb/` | [Videodr0me/Arcade-MajorHavoc_MiSTer](https://github.com/Videodr0me/Arcade-MajorHavoc_MiSTer) `rtl/videodr0me_fb/` | see below |
| `sys/` | [Videodr0me/Arcade-StarWars_MiSTer](https://github.com/Videodr0me/Arcade-StarWars_MiSTer) `sys/` | `5270c74394c3828500543845f76011f88226dbff` |
| `rtl/tv80/` | [MiSTer-devel/Arcade-SegaVICZ80_MiSTer](https://github.com/MiSTer-devel/Arcade-SegaVICZ80_MiSTer) `rtl/tv80/` | `16386ffec0bf548520d174538190c09ffa426368` |
| `rtl/i8035/i8035.v` | same | same |
| `rtl/jt49/` | same | same |

Licences: the Videodr0me cores are GPL-3.0 / GPL-2.0+; `tv80` is MIT; `jt49` is
GPL-3.0. This core is therefore GPL-3.0.

## Renderer interface as vendored (Asteroids revision)

`vfb_top` vector inputs:

```
input  [10:0] X_VECTOR, Y_VECTOR
input  [7:0]  Z_VECTOR
input  [3:0]  COLOR        // Asteroids passes {Rhi, Rlo, G, B}
input         IS_DOT, BEAM_ON
input         FRAME_DONE
input  [11:0] RENDER_WIDTH, RENDER_HEIGHT
```

Framebuffer pixel packing (`vfb_rasterizer.sv` → `vfb_readout.sv`):

```
pixel_data[15:0] = { rgb[2:0], draw_idx[3:0], 1'b0, z[7:0] }
```

One spare bit at [8]. Sega needs 6-bit colour (2 bits/gun). The repack that
buys it is recorded under "Local modifications" below; the census that decided
it was necessary is in [`colour-census.md`](colour-census.md).

## Renderer: migrated from Asteroids to Major Havoc

Videodr0me pointed out that Havoc's renderer, not Asteroids', is the most
advanced: more OSD options, a different halo, and `vfb_layout_pkg.sv`. It is
also **125 MHz instead of Asteroids' 128.52 MHz**, which he flagged as a
timing-sensitivity difference — and this core had inherited the 128.52 PLL,
which is the likely reason it needed `SEED 3` to close.

Two structural gains beyond the effects:

* **`clk_source` + `source_tick` replace the fixed `clk_12`.** The phosphor
  timing measures the EOF period *in source ticks*, so it self-calibrates to
  whatever rate the vector generator runs at. Sega's is 2.578 MHz against
  Atari's ~12 MHz, so this removes a hardcoded assumption rather than working
  around it — `segag80v` now exports `vec_tick` and the renderer paces itself
  from the real VCL rate.
* **Havoc already carries 4-bit colour** ({strong red, fine red, green, blue}),
  with a proper DAC model — `calibrated_dac_level`, `fine`/`main`/`shoulder`
  levels and `expand_highlights`. That is a far better base for Sega's 6-bit
  than Asteroids' flat 3-bit mask.

Clocking now mirrors Havoc: the framework PLL supplies 125/10/50 MHz and a
separate `sega_clocks` PLL supplies the 12.096 MHz machine domain, exactly as
`major_havoc_clocks.sv` does for its AVG.

## Local modifications

**6-bit colour** (2026-08-03, reworked onto Havoc). Mandated by the Phase 0
census — see `colour-census.md`: 42 of the 64 Sega colours cannot be expressed
as hue x brightness and they cover 22% of all beam-on samples.

Videodr0me on the intensity/colour trade: *"reducing the intensity bits to gain
the RGB 6 bit encoding was absolutely the right call."*

Rather than bypassing his DAC model, the change **generalises it**. Major Havoc
has two red bits against 1-bit green and blue, so only red had a level ladder,
inline in `vfb_readout`. The Sega X-Y Control board drives all three guns from
identical 2-bit ladders (6.2k/12k, drawing 800-0163 sheet 6/6), so the ladder
is pulled out into `vfb_dac_ladder.sv` and applied per channel.

Stored pixel layouts, both still exactly 16 bits:

```
rasterised  { rgb[5:0], draw_idx[2:0], z[7:1] }      (was { rgb[3:0], draw_idx[2:0], 1'b0, z[7:0] })
composed    { rgb[5:0], fresh,         energy[8:0] } (was { rgb[3:0], fresh, 2'd0, energy[8:0] })
```

| File | Change |
|---|---|
| `vfb_top.sv` | `COLOR` 4 -> 6 bits |
| `vfb_rasterizer.sv` | `COLOR` 4 -> 6; FIFO word 36 -> 38 bits; colour registers widened; `pixel_data` repacked |
| `vfb_readout.sv` | decode `rgb` from `[15:10]`, `draw_idx` from `[9:7]`, Z expanded from `[6:0]`; the red-only fine/main split replaced by a per-gun ladder |
| `vfb_phosphor_compositor.sv` | colour registers 4 -> 6 bits; `stored_pixel` repacked |
| `vfb_dac_ladder.sv` | **new** — the 2-bit-per-gun ladder, 0 / 1/3 / 2/3 / 1 |

Two follow-on timing changes in `vfb_readout.sv`, found on hardware:

* The shoulder add feeding the ladder is registered ahead of it, and the level
  registers carry `preserve, dont_retime`. Three guns through a ladder behind a
  10-bit add was the critical path at 125 MHz — Havoc only had it on red.
* `READ_ADVANCE` 9 -> 10. That pipeline stage makes the datapath 11 registers
  deep against Havoc's 10, and the sync/blank shift register is tapped to match
  the datapath depth. Left at 9 the picture sits one pixel right of its own
  blanking, losing the rightmost column.

Verified by `make color6`: all 1024 DAC levels x 4 gun levels against an exact
model of the ladder, worst error 1 LSB, with levels 0 and 3 exact and
monotonicity checked in both arguments.

If upstream `videodr0me_fb` moves, rebase these five files; nothing else in the
renderer was touched.
