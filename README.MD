<p align="center">
  <img src="Useful Information/AstroBlaster.png" width="800">
  <img src="Useful Information/005.png" width="800">
  <img src="Useful Information/MonsterBash.png" width="800">
  <img src="Useful Information/PigNewton.png" width="800">
  <img src="Useful Information/SindbadMystery.png" width="800">
  <img src="Useful Information/SpaceOdyssey.png" width="800">
</p>

<h1 align="center">SegaG80 FPGA Core</h1>

<p align="center">
  Arcade hardware implementation for MiSTer FPGA
</p>

---

## Overview

FPGA implementation of the **Sega G-80 raster** arcade platform (1981-1983), the
board family behind *Astro Blaster*, *005*, *Space Odyssey*, *Monster Bash*,
*Pig Newton* and *Sindbad Mystery*.

One core runs all six games; the `.mra` selects the title and configures the
hardware differences between them. All six are playable.

---

## Supported Games

| Game | Year | MAME set | Buttons | Status |
|---|---|---|---|---|
| Astro Blaster | 1981 | `astrob` | Shoot, Warp | Playable. Speech working; discrete sound board in progress |
| 005 | 1981 | `005` | Shoot | Playable. Silent - its sound board is not implemented |
| Space Odyssey | 1981 | `spaceod` | Fire, Bomb | Playable. Silent - discrete sound board not implemented |
| Monster Bash | 1982 | `monsterb` | Fire | Playable. Voice (uPD7751) working; music and effects not implemented |
| Pig Newton | 1983 | `pignewt` | Action | Playable. Sound effects working |
| Sindbad Mystery | 1983 | `sindbadm` | Action | Playable. Silent - its sound board is not implemented |

All six are vertical (ROT270) games, published by Sega.

> **Sound is the outstanding work on this core.** These games do not share a
> sound board - there are five different designs between them - so each one is a
> separate job rather than a single feature.

---

## Controls

Default MiSTer gamepad mapping. Every game uses the same layout; only the button
labels differ (see the table above).

| Input | Action |
|---|---|
| D-Pad / Joystick | Move |
| A | Button 1 |
| B | Button 2 (Astro Blaster, Space Odyssey) |
| Select | Insert Coin |
| Start | 1 Player Start |
| Right Shoulder | 2 Player Start |
| Left Shoulder | Pause |

### Service and self-test

These are two different switches on real hardware, and they are **not** the same
control:

| Key | Function |
|---|---|
| **F2** | Self-test - the red switch on the CPU board (drives the Z80 NMI) |
| **9** | Service credit - the panel service button |

---

## Hardware Implemented

- **Z80** main CPU with the platform's memory-write address scrambling
  (Sega 315-0062 / 0063 / 0070 / 0082 security chips)
- **Sega 315-5028 encrypted Z80** for Sindbad Mystery - opcode and data
  decryption performed on the fly, no pre-decrypted ROM image required
- **Foreground** character generator with CPU-writable character RAM and palette
- **Background boards**, three distinct designs:
  - Space Odyssey - 6 bitplanes, fixed RGB222 palette, CPU-clocked scroll
    counters, collision detect
  - Monster Bash - 2bpp page-scrolling tilemap
  - Pig Newton / Sindbad Mystery - 2bpp scrolling tilemaps
- **Sega speech board** (i8035 + SP0250) - Astro Blaster
- **Sega Universal Sound Board** (i8035) - Pig Newton
- **uPD7751 sample player** with i8243 expander - Monster Bash voice
- **Astro Blaster discrete sound board**, ported voice by voice from the
  Gremlin schematics
- Video Options menu with CRT and HDMI flip
- Per-game DIP switches exposed through the `.mra`

---

## ROM Requirements

ROM files are **not included**.

To use this core you must supply legally obtained ROM files.

- `.mra` files are provided in the `releases/` folder.
- Each `.mra` lists every required ROM together with its checksum.
- ROM `.zip` filenames follow the MAME naming convention.

For setup instructions and environment configuration, see the MiSTer Arcade ROM
guide:

https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms

---

## Credits

Sega G-80 raster hardware research is based on the MAME source
(`segag80r.cpp`, `segag80r_v.cpp`, `segag80r_a.cpp`, `segacrpt_device.cpp`) and
on the original Sega/Gremlin schematics.

Built on the [MiSTer](https://github.com/MiSTer-devel) framework.
