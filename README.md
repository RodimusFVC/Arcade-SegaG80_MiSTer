# Arcade-SegaG80_MiSTer

A MiSTer FPGA port of Sega's G-80 raster arcade platform, initial target
**Astro Blaster (1981)**.

## Status

**Phase 2 bring-up, April 2026** — Astro Blaster boots and is playable.
Audio is an approximation, not a netlist-accurate port. Speech is a stub
(port decode only; no speech synthesis). Other G-80 raster games
(005, Space Odyssey, Monster Bash, Pig Newton, Sindbad Mystery) are
framework-only and not yet playable. G-80 vector games are tracked
separately under a Phase 4 roadmap.

## Credits

- Port to MiSTer: Rodimus, 2026.
- Based on MAME's segag80r driver by Aaron Giles (and many contributors).
- Uses MiSTer framework scaffolding (hps_io, arcade_video, screen_rotate,
  pause, hiscore) from the Ace / OzOnE / Artemio Urbina / Kitrinx
  collaboration on the Time Pilot/Blue Print family of cores.

## ROM loading

ROMs are loaded via an MRA file that packs the following layout into
ioctl index 0 (48 KB total):

| Offset    | ROM file        | Size   |
|-----------|-----------------|--------|
| 0x0000    | 828.u25         | 0x0800 |
| 0x0800    | 829.u1          | 0x0800 |
| 0x1000    | 830.u2          | 0x0800 |
| 0x1800    | 831.u3          | 0x0800 |
| 0x2000    | 832.u4          | 0x0800 |
| 0x2800    | 833.u5          | 0x0800 |
| 0x3000    | 834.u6          | 0x0800 |
| 0x3800    | 913a.prom-u7    | 0x0800 |
| 0x4000    | 835.u8 … etc.   |        |

See `releases/Astro_Blaster.mra` for the exact file list and hashes.

## Key implementation constants (from MAME)

| Quantity            | Value         | Source                        |
|---------------------|---------------|-------------------------------|
| Master video clock  | 15.46848 MHz  | `segag80r.cpp:130`            |
| Z80 CPU clock       | / 4           | `segag80r.cpp:1059`           |
| Pixel clock         | / 3           | `segag80r.cpp:132`            |
| Active resolution   | 256 × 224     | `segag80r.cpp:134-140`        |
| Refresh rate        | ~60.1 Hz      | derived                       |
| Z80 wait states     | 2 per access  | `segag80r.cpp:145`            |
| Security chip       | 315-0062      | `segag80_m.cpp` (`decrypt62`) |

## Building

Requires Quartus Prime 17.0.x (Cyclone V edition). Open
`Arcade-SegaG80_MiSTer.qpf` and compile.

## Known approximations

- **Audio**: simplified synthetic channels replacing the Astro Blaster
  discrete analog board. Effects sound in the right ballpark but are not
  accurate. A netlist-accurate port is future work.
- **Speech**: not implemented. Port $38 / $3B writes are absorbed silently.
- **Character bitmap fetch**: placeholder palette indexing (see
  `rtl/segag80_video.sv` TODO). If the frame shows correct tilemap
  layout but wrong pixels, the bitplane stride constants need confirmation
  against MAME's `charlayout`.
- **Cocktail mode flip**: controlled by SW1:6 in DIP, but the screen
  flipping path is only validated for upright. Cocktail-flipped play is
  untested.

## Reporting issues

If something doesn't work, please include:
1. MRA file and CRC of ROM set used.
2. Exact sequence of button presses / DIP settings that reproduces.
3. If possible, a photo of the screen.
