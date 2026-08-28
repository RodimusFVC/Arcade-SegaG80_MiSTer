# Sega/Gremlin G80 "X-Y" vector hardware — implementation reference

> **Note on `refs/` paths.** This document cites local research material
> — scanned Gremlin schematics, game manuals and MAME driver sources —
> that is not redistributed here. See
> [`docs/00-research-summary.md`](00-research-summary.md) for where each
> item came from, and `sim/tools/` for the scripts that regenerate the
> ROM-derived artefacts locally.


Everything below is derived from two mutually-confirming sources held locally:
`refs/mame/segag80v*.cpp` (Aaron Giles' gate-level MAME model) and
`refs/schematics/*.png` (Gremlin drawings 800-0161 / 800-0163, from the Star Trek
manual). Where they disagree or where MAME is ambiguous, it is called out.

---

## 1. Board set

The "Convert-a-Game" cage is modular; the same three boards run all five games and
only the EPROMs, sound board, security chip and control panel change.

| Board | Drawing | Role |
|---|---|---|
| CPU Board | 800-0107 | Z80, 2× 2114 work RAM, address decode, 6331 PROM at U15 |
| 2716 EPROM Board | 800-0151 | up to 48 KB program ROM |
| **X-Y Control Board** | 800-0163 | 4K×8 vector RAM, display-list address generation, length multiplier, attribute/colour latch, CPU bus interface |
| **X-Y Timing Board** | 800-0161 | master clock + phase generator, angle arithmetic, sin/cos PROM, X/Y position counters, DACs, blanking |
| Sound board | varies | see §7 |
| Speech board | 800-0294 | 8035 + SP0250 (Space Fury, Zektor, Star Trek) |

## 2. Clocks

Single 15.46848 MHz crystal (Y1, X-Y Timing sheet 7/7) feeds everything:

```
VECTOR_CLOCK = 15'468'480 Hz          crystal
Z80          = VECTOR_CLOCK / 4       = 3'867'120 Hz   (+2 wait states on every access)
U34_CLOCK    = VECTOR_CLOCK / 3       = 5'156'160 Hz   interrupt chain
VCL_CLOCK    = U34_CLOCK / 2          = 2'578'080 Hz   vector generator step clock
U51_CLOCK    = VCL_CLOCK / 16         =   161'130 Hz   full 16-phase cycle
EDGINT/IRQ   = U34_CLOCK / 0x1F788    =        40.0 Hz exactly (128904 × 40)
```

**40 Hz frame rate.** That is the redraw rate of the whole display list, and it is
close enough to Star Wars' ~40.5 Hz that Videodr0me's phosphor-decay divider
constants (`DRAW_IDX_DIV_1X` etc. in `vfb_top.sv`) are already in the right range.

> **Open timing question.** MAME charges `1/U51_CLOCK` (6.21 µs) per *phase*, i.e.
> 16 VCL periods per phase, so a 10-phase symbol header costs 62 µs and ~400
> symbols fill a frame. If U51 is actually clocked directly by VCL — which is what
> "LS161 at U51 → LS154 at U50" implies — a phase is 0.388 µs and the budget is
> 16× larger. MAME's `segag80v.cpp` header still carries the note *"the games seem
> to run too fast"*. Resolve this by tracing U51 pin 2 on
> `XY_Timing_800-0161_sheet7of7.png` before freezing the RTL, and validate against
> the `DRAW` flag timing that the games poll (see §5).

## 3. Memory and I/O map

```
0000-07FF   ROM   (CPU board U25)
0800-BFFF   ROM   (EPROM board U1..U23)
C800-CFFF   RAM   2K work RAM      — writes go through the security scrambler
D000-DFFF   RAM   USB program RAM  — Tac/Scan + Star Trek only, also scrambled
E000-EFFF   RAM   4K vector RAM    — writes also scrambled; shared with the vector generator
```

I/O ports (`global_mask 0xFF`):

| Port | Dir | Function |
|---|---|---|
| `$38` | W | speech data (Space Fury, Zektor, Star Trek) |
| `$3B` | W | speech control |
| `$3C-$3D` | W | AY-3-8912 (Zektor only) |
| `$3E-$3F` | W | sound board latches (Eliminator/Zektor/Space Fury) |
| `$3F` | R/W | USB status / data (Star Trek) |
| `$BC` | R | unknown |
| `$BD-$BE` | W | CPU multiplier operands (25LS14 at U43, X-Y Control sheet 6/6) |
| `$BE` | R | multiplier result, low byte then high byte |
| `$BF` | W | interrupt enable (`0x04` enables) |
| `$F8-$FB` | R | mangled input/DIP matrix (see §6) |
| `$F8` | W | spinner / player select (Zektor, Tac/Scan, Star Trek, Elim 4P) |
| `$F9` | W | coin counters (mirrored at `$FD`) |
| `$FC` | R | spinner or 4-player inputs |

**Security chip (315-00xx).** Not opcode encryption — an *address* scrambler on RAM
writes. When the Z80 fetches opcode `$32` (`LD (nnnn),A`), the low byte of the
target address is permuted before the store. One of four permutations (A/B/C/D) is
chosen by two bits of the *PC of that opcode*:

| Game | Chip | PC bits selecting the permutation |
|---|---|---|
| Eliminator 2P | 315-0070 | `pc & 0x09` |
| Eliminator 4P | 315-0076 | `pc & 0x09` |
| Space Fury | 315-0064 | `pc & 0x03` |
| Zektor | 315-0082 | `pc & 0x11` |
| Tac/Scan | 315-0076 | `pc & 0x09` |
| Star Trek | 315-0064 | `pc & 0x03` |
| Advisor (bootleg) | none | — |

The four permutations are pure combinational bit shuffles of the low byte
(`sega_decrypt62/63/64/70/76/82` in `refs/mame/segag80_m.cpp`) — about 20 lines of
Verilog plus a 2-bit selector latched at opcode fetch.

## 4. The vector generator

### 4.1 Display-list format

Two levels: a **symbol list** walked linearly from vector RAM offset 0, and per
symbol a **vector list** at an arbitrary 12-bit address in the same RAM.

Symbol header — 10 bytes, one per phase 0–9:

| Byte | Phase | Latched into | Meaning |
|---|---|---|---|
| 0 | 0 | — | bit 0 = draw this symbol; **bit 7 = end of display list** |
| 1 | 1 | U15/U16 | X position, low byte |
| 2 | 2 | U17 | X position, high 3 bits (bit 2 is replicated into bit 3) |
| 3 | 3 | U18/U19 | Y position, low byte |
| 4 | 4 | U20 | Y position, high 3 bits (bit 2 replicated into bit 3) |
| 5 | 5 | U10/U11 | vector-list address, low byte |
| 6 | 6 | U12 | vector-list address, high 4 bits |
| 7 | 7 | U55 (LS374) | symbol rotation angle, low byte |
| 8 | 8 | U26 (LS74) | symbol angle, high 2 bits |
| 9 | 9 | U8 (25LS14) | scale factor |

Vector record — 4 bytes, phases 10–14:

| Byte | Phase | Latched into | Meaning |
|---|---|---|---|
| 0 | 10 | U2 (LS374) | bit 0 = beam on; bits 1–6 = colour RRGGBB; **bit 7 = end of symbol**, and it also sets U52 so the phase counter reloads to 0 (new symbol) instead of 10 (next vector) |
| 1 | 11 | U6/U7 → U8 | length; multiplied by scale, 9 MSBs → length counters U15–U17 |
| 2 | 12 | U56 (LS374) | vector angle, low byte |
| 3 | 13/14 | — | vector angle, high 2 bits |

So a symbol is *position + rotation + scale + a pointer to a reusable shape*. This
is why Sega's games can rotate and scale sprites cheaply — the rotation happens in
the vector generator, not on the Z80.

### 4.2 Angle → step vector

The sum `symangle + vecangle` (10 bits) addresses the 1K sine PROM at U39
(`s-c.xyt-u39`). A0 is tied to ground, so only even byte addresses are used:

```
deltax = sintable[ ((vecangle + symangle)         & 0x1FF) << 1 ]
deltay = sintable[ ((vecangle + symangle + 0x100) & 0x1FF) << 1 ]
```

The `+0x100` is what separates cos from sin; bit 9 of each sum is the sign,
latched into `D/UX` / `D/UY` at the end of phases 13 and 14 and driving the
up/down inputs of the position counters.

### 4.3 The DDA walk

Once per VCL clock, for `length` counts:

```
xaccum += deltax + (deltax >> 7);        // U44/U45 adders; bit 7 is the round-in carry
curx   += (xaccum >> 8) or -= …          // carry-out clocks U15/U16/U17
xaccum &= 0xFF;
yaccum += deltay + (deltay >> 7);        // U46/U47
cury   += (yaccum >> 8) or -= …          // clocks U18/U19/U20
yaccum &= 0xFF;
```

The position counters therefore move by at most **one count per VCL clock**, which
is exactly the "one pixel per clock" feed the MiSTer vector framebuffer wants.

### 4.4 Clipping / blanking

Position is 12-bit; the visible field is 10-bit. Per axis:

```
v = (raw & 0x7FF) ^ 0x200
if      (v & 0x600) == 0x200 : v = 0x000, clipped
else if (v & 0x600) == 0x400 : v = 0x3FF, clipped
else                         : v &= 0x3FF
```

While clipped the beam is blanked but the accumulators keep running — objects
sliding off the edge of the screen must clip, not wrap. On the schematic this is
the `BOX`/`BOY` XOR terms at U29 combining through U53 into **`BOS`**
(X-Y Timing sheet 5/7), which gates the Z axis.

Vector space is 1024 × 1024. MAME's visible window is x 512..1536, y 608..1440 →
**1025 × 833** after the coordinate offset.

### 4.5 Colour

Attribute bits 1–6 are two bits each of R, G and B — `color222`, 64 colours. On
X-Y Control sheet 6/6, U2's outputs drive 74LS09 open-collector gates into 6.2 K /
12 K resistor pairs and 1N914s, one pair per gun: a 2-bit weighted DAC per channel.
Intensity is **binary** — the beam is either on at full brightness or off. There is
no Z-axis intensity channel like Atari's AVG.

This is the one place where the Sega hardware does not fit the existing MiSTer
vector chassis unchanged; see the plan, §3.

## 5. Interrupts and the DRAW flag

```
IRQ  = (COINA_ff | COINB_ff | SERVICE_pulse | EDGINT_ff)
```

`EDGINT` is the 40 Hz divider output. All the flip-flops are cleared by `INTCL`,
which the Z80 asserts on interrupt acknowledge. `$BF` bit 2 is the master enable.
The service switch additionally pulses **NMI**.

Separately, **`DRAW`** (P1.13, readable as bit `0x20` of port `$F8`) is high while
the vector generator is still walking the display list. Games poll it to avoid
rewriting vector RAM under the beam. Getting `DRAW`'s duty cycle right is what the
open timing question in §2 is about, and it is the most likely source of
"runs too fast / too slow" symptoms in a port.

## 6. Inputs

Ports `$F8-$FB` return a transposed matrix — each read gathers one bit from each of
four physical byte sources:

```
        offset 0    offset 1   offset 2   offset 3
  D7    COINA         n/c        n/c        n/c
  D6    COINB        P1.13      P1.14       n/c
  D5    SERVICE      P1.15      P1.16      P1.17
  D4    P1.18        P1.19      P1.20      P1.21
  D3    SW1.8        SW1.7      SW1.6      SW1.5
  D2    SW1.4        SW1.3      SW1.2      SW1.1
  D1    SW2.8        SW2.7      SW2.6      SW2.5
  D0    SW2.4        SW2.3      SW2.2      SW2.1
```

The **spinner** (Zektor, Tac/Scan, Star Trek) is not a quadrature reading. Port
`$FC` returns `~((count << 1) | sign)` — a monotonically increasing count with
direction in bit 0. The self-test expects the number to increase whichever way you
turn. Eliminator 4-player instead demuxes players 3/4 and the four coin inputs
through `$F8` bit 3 + select bits 0–2.

## 7. Audio

| Game | Sound hardware | MAME model |
|---|---|---|
| Eliminator | discrete analog board 800-3174, latches at `$3E/$3F` | netlist `NETLIST_START(elim)` in `nl_elim.cpp` |
| Zektor | discrete board 800-3249 **+ AY-3-8912** at `$3C/$3D` | netlist `NETLIST_START(zektor)` in `nl_elim.cpp` |
| Space Fury | discrete board, latches `$3E/$3F` | `nl_spacfury.cpp` |
| Space Fury / Zektor / Star Trek | Speech board 800-0294: 8035 @ 3.12 MHz + **SP0250** LPC | `segaspeech.cpp` |
| Tac/Scan, Star Trek | **Universal Sound Board 800-0377**: 8035 @ 6 MHz, 3× 8253 PIT, DACs, MM5837 noise, analog filters. Program RAM is shared with the main Z80 at `$D000-$DFFF`. | `segausb.cpp` + `nl_segausb.cpp` |

Note MAME's `segag80v.h` still `#include`s `tms5110.h`; the real speech chip is the
**SP0250** (`segaspeech.cpp` includes `sound/sp0250.h`). Only the Italian *Advisor*
bootleg uses a TMS5100, and it is unimplemented.

## 8. Game list

| MAME set | Year | Security | Sound | Controls |
|---|---|---|---|---|
| `elim2`, `elim2a`, `elim2c` | 1981 | 315-0070 | discrete | 2 players, buttons |
| `elim4`, `elim4p` | 1981 | 315-0076 | discrete | 4 players, demuxed |
| `spacfury`, `spacfurya`, `spacfuryb` | 1981 | 315-0064 | discrete + speech | joystick |
| `spacfurybl` (Advisor) | — | none | discrete + TMS5100 (unimpl.) | |
| `zektor` | 1982 | 315-0082 | discrete + AY-3-8912 + speech | spinner |
| `tacscan` | 1982 | 315-0076 | USB | spinner, ROT270 |
| `startrek` | 1982 | 315-0064 | USB + speech | spinner |

**Battlestar / "Battle Star" is not implementable.** It is an unreleased 1982
Sega/Gremlin G80 vector conversion of Space Fury. A marquee survives; no boards and
no ROMs have ever been dumped, and it appears on the unMAMEd "most wanted" list. It
is absent from the MAME driver. Complicating identification: *all* Space Fury
boards are silkscreened "Battle Star", so board markings are not evidence a dump
exists.
