# Arcade-SegaG80_MiSTer

A MiSTer FPGA port of Sega's G-80 raster arcade platform, initial target
**Astro Blaster (1981)**.

## Credits

- Port to MiSTer: Rodimus, 2026.
- Based on MAME's segag80r driver by Aaron Giles (and many contributors).
- Uses MiSTer framework scaffolding (hps_io, arcade_video, screen_rotate,
  pause, hiscore) from the Ace / OzOnE / Artemio Urbina / Kitrinx
  collaboration on the Time Pilot/Blue Print family of cores.


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
