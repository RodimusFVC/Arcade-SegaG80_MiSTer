# Phase 0: colour census — result

**Date:** 2026-08-03
**Verdict: the renderer colour path must be widened to true 6-bit RGB. The
3-bit-hue + Z-brightness shortcut is not viable.**

## Question

Sega's G-80 vector hardware has 2 bits per gun (64 colours, binary intensity).
`videodr0me_fb` stores 3-bit RGB plus an 8-bit Z intensity per pixel:

```
pixel_data[15:0] = { rgb[2:0], draw_idx[3:0], 1'b0, z[7:0] }
```

A Sega colour survives that encoding only if all of its non-zero channels sit at
the same level — i.e. it is a pure hue at some brightness. `R=3 G=3 B=0` is fine
(yellow at full); `R=3 G=1 B=0` is not, because red and green need different
levels at the same time.

If the games only ever used proportional colours, the renderer could be left
completely untouched. That was worth checking before doing anything invasive.

## Method

1. `sim/tools/dump_vram.lua` runs under MAME 0.283 headless, inserts a coin,
   starts a game and snapshots vector RAM (`$E000-$EFFF`) every 25 frames.
2. 96 snapshots per game were taken over 60 emulated seconds, covering attract
   mode and gameplay: **576 real display lists** across all six romsets.
3. `sim/tools/census.cpp` walks each snapshot with the golden model using the
   real `s-c.xyt-u39` sine PROM, and counts the attribute colour of every
   beam-on sample.

## Result

**3,661,809 beam-on samples. 63 of the 64 possible colours are used.**

| Game | Colours used | Non-representable |
|---|---|---|
| Eliminator 2P | 19 | 6 |
| Eliminator 4P | 27 | 9 |
| Space Fury | 63 | 42 |
| Zektor | 27 | 7 |
| Tac/Scan | 39 | 23 |
| Star Trek | 62 | 41 |

**42 colours are non-representable, and they account for 22.17% of all beam-on
samples.** The worst offenders are not obscure:

| Colour | R G B | Share | Note |
|---|---|---|---|
| `34` | 3 1 0 | **8.09%** | orange — Eliminator and Zektor lean on it heavily |
| `07` | 0 1 3 | 3.10% | |
| `0B` | 0 2 3 | 2.98% | |
| `12` | 1 0 2 | 2.17% | |
| `13` | 1 0 3 | 1.63% | |
| `27` | 2 1 3 | 1.32% | |

Space Fury and Star Trek use essentially the whole palette — they fade objects
through per-channel ramps, which is exactly the pattern the shortcut cannot
express.

Dropping to hue + brightness would turn 8% of Eliminator's picture from orange
to either red or yellow. That is not an acceptable approximation.

## Consequence

Repack the framebuffer pixel to carry all six colour bits:

```
pixel_data[15:0] = { rgb[5:0], draw_idx[3:0], z[5:0] }
```

Sega's intensity is binary, so surrendering two bits of Z costs nothing here —
6 bits of brightness headroom is far more than the hardware can express.

Keep the change isolated so a renderer update from upstream can be rebased.

**Done** — the packing as built is `{rgb[5:0], draw_idx[2:0], z[7:1]}` out of
the rasteriser and `{rgb[5:0], fresh, energy[8:0]}` composed, with the per-gun
2-bit ladder pulled out into `vfb_dac_ladder.sv`. Every touched file is listed
under "Local modifications" in [`vendored-sources.md`](vendored-sources.md).

## Reproducing

```
# dump (needs MAME and the romsets)
cd <mame>
for g in elim2 elim4 spacfury zektor tacscan startrek; do
  SEGAVRAM_OUT=<repo>/sim/vramdumps/$g SEGAVRAM_EVERY=25 SEGAVRAM_COIN=1 \
  ./mame $g -rompath <roms> -video none -sound none -nothrottle \
     -seconds_to_run 60 -autoboot_script <repo>/sim/tools/dump_vram.lua \
     -autoboot_delay 0
done

# census
cd <repo>/sim
c++ -O2 -std=c++17 -Igolden tools/census.cpp golden/segag80v_golden.cpp -o census
./census roms/s-c.xyt-u39 vramdumps/*
```

## Side benefit

The same snapshots are now regression stimulus for the RTL bench. `make xy`
picks up `vramdumps/` automatically and replays real game display lists through
both the golden model and the RTL:

```
sega_xy: sine PROM = real (roms/s-c.xyt-u39)
sega_xy: 48 real vector-RAM snapshots
sega_xy: 90 cases, 819710 golden samples, 0 failed
```
