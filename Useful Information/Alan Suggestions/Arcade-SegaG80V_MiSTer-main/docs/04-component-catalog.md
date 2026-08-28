# Sega G80V component catalog

Catalog of the major components in `Arcade-SegaG80V_MiSTer`, with a search of
the current MiSTer-devel sources for newer or better-supported alternatives.

Survey date: 2026-08-07.

The Sega core was cloned at `64e476d`. This report records exact upstream
commits where a component has a known source. “Latest” means the newest branch
head observed during this survey; “best” means the source that currently has
the strongest combination of compatibility, verification, and fit for this
core. Those are sometimes different.

## Executive recommendation

There is no obvious component that should be replaced wholesale today.

The current composition is sensible:

* Keep the Z80, 8035, and JT49 IP from `Arcade-SegaVICZ80_MiSTer`.
* Keep the Major Havoc version of Videodr0me’s framebuffer/CRT pipeline, with
  the Sega-specific six-bit color changes already present here.
* Keep the new Sega XY generator, security device, ports, and geometry logic;
  no MiSTer-devel equivalent was found, and each has a focused MAME or
  schematic-based test.
* Keep the local SP0250 and Universal Sound Board implementations, but treat
  the discrete audio model as approximate.
* Do not copy a newer `sys/` directory over this core. It contains substantial
  board-specific adaptations and needs a file-by-file rebase.

The highest-value follow-up is not an upgrade. It is adding cross-regression
tests for the MCS-48 CPU wrapper and the speech/USB board glue, followed by
replacing or improving the behavioural discrete-sound model if hardware
listening identifies problems.

## Component inventory

| Component | Current implementation | MiSTer-devel / upstream comparison | Recommendation |
|---|---|---|---|
| Z80 CPU | `rtl/tv80/` (`tv80_core`) | Exact source match to `Arcade-SegaVICZ80_MiSTer` at `16386ffec0bf548520d174538190c09ffa426368`. The standalone `MiSTer-devel/T80` head is older, `830fd0315f0af5cdbcb0e703f1cea3ce4e91f538`. | Keep current TV80. It is already the current source used by its MiSTer parent and is exercised by the Sega CPU/wait-state tests. |
| MCS-48 / 8035 CPU | `rtl/tv48/` plus wrapper `rtl/i8035/i8035.v` | Wrapper and TV48 files match the current SegaVICZ80 source. Donkey Kong and Donkey Kong Junior carry older VHDL `T48`/`i8035ip` integrations. The original `devsaurus/t48` project has a newer VHDL head, `837bd24f8a93275e0233c679b4f00e344bb4e912` (2025-10-05), but it is not a drop-in Verilog replacement. | Keep current wrapper for now. Cross-test against the current T48 regression suite before considering a re-conversion. |
| Sega clock tree | `rtl/sega_clocks.sv` | No shared MiSTer implementation found. Frequencies and enables are tied to the Sega schematics and the selected 12.096 MHz machine clock. | Keep local; verify on hardware if the phase-clock ambiguity remains relevant. |
| Sega security chips | `rtl/sega_security.sv` | No direct MiSTer-devel counterpart found. Models the 315-0062/63/64/70/76/82 families from MAME’s permutation tables. | Keep local. It has an exhaustive 458,752-case test against the MAME-derived reference. |
| Sega XY/vector generator | `rtl/xy/sega_xy.sv` and `sega_xy_top.sv` | No direct MiSTer-devel counterpart found. The implementation is a hardware reconstruction checked against the MAME vector-generator model and real vector-memory captures. | Keep local. This is core-specific IP, not a candidate for import from another arcade core. |
| CPU/memory/IO map | `rtl/segag80v_cpu.sv` and `rtl/segag80v.sv` | No shared G80V implementation exists in MiSTer-devel. The map, wait states, security placement, and interrupt path are Sega-specific. | Keep local; preserve the CPU, security, and boot tests together. |
| Input and ports | `rtl/sega_inputs.sv` and `rtl/sega_ports.sv` | No shared equivalent found. The code follows MAME input definitions and Sega LS253/spinner/multiplier behavior. | Keep local. The focused ports test is the relevant quality signal. |
| Coordinate/orientation mapping | `rtl/sega_geometry.sv` | No shared equivalent found. It maps Sega’s XY coordinates into the framebuffer and follows MAME orientation flags. | Keep local; the geometry test covers the mapping. |
| Video integration | `rtl/sega_video.sv` | No other G80V video path found. It connects the DDA beam samples, geometry, color, frame completion, and framebuffer. | Keep local. Changes should be made with the XY and renderer tests together. |
| Vector framebuffer and CRT pipeline | `rtl/videodr0me_fb/` | Based on `Videodr0me/Arcade-MajorHavoc_MiSTer` / `MiSTer-devel/Arcade-MajorHavoc_MiSTer` at `6933b85260dc4ccde8069d258dbfc595d28c3909`. The current Asteroids branch is newer overall (`ab07109809d87ffc54b9071c373993c8b2c7afdb`), but its renderer is a materially different variant. | Keep the Major Havoc base. Do not import Asteroids wholesale. Selectively review future renderer fixes. |
| Sega six-bit color path | `vfb_dac_ladder.sv` plus local changes to four framebuffer files | No upstream counterpart: this is the local adaptation from Videodr0me’s four-bit color path to Sega’s two bits per gun. | Keep local. The color ladder has exhaustive level/monotonicity checks. Rebase manually if the renderer changes. |
| MiSTer system framework | `sys/` | Origin recorded as `MiSTer-devel/Arcade-StarWars_MiSTer` at `5270c74394c3828500543845f76011f88226dbff`. Direct comparison with the current Star Wars checkout shows many local differences, including scaler, SD-detect, HPS status, scanline, subcarrier, and audio-control adaptations. | Treat the origin commit as provenance, not as a drop-in update. Maintain a local patch manifest and rebase individual files only. |
| AY-3-8912 / PSG | `rtl/jt49/` and `rtl/sound/sega_ay.sv` | `rtl/jt49/` is an exact match to the current SegaVICZ80 checkout at `16386ffec0bf548520d174538190c09ffa426368`. JT49 also appears in several other MiSTer cores, but no better Sega-specific fork was found. | Keep current JT49 and the local Sega bus/audio glue. |
| SP0250 speech synthesizer | `rtl/sound/sp0250.sv` and `sega_speech.sv` | No MiSTer-devel SP0250 implementation was found. The RTL is a local transcription of MAME’s `sp0250.cpp`; the board glue models the Sega 8035, ROM banking, DRQ, T0, and latch behavior. | Keep local. The decoder is bit-exact against the local MAME-derived golden model; hardware execution and speaker output still need validation. |
| Universal Sound Board digital core | `rtl/sound/sega_usb.sv` | No complete shared MiSTer USB-board implementation found. It uses the shared 8035, local 8253 timers, local MM5837 noise, and MAME-derived board glue. | Keep local. The digital timing and board sequencing have focused tests. |
| USB 8253 timers | `rtl/sound/usb_timer.sv` | No better shared 8253 implementation was found for this exact Sega board. This is intentionally limited to the modes used by the board program. | Keep local; its MAME comparison is stronger than importing a generic timer without the same write/clock ordering. |
| USB MM5837 noise | `rtl/sound/usb_noise.sv` | No shared matching implementation found. The polynomial and seed follow MAME. | Keep local; the 400,000-step comparison covers the seed and sequence. |
| USB analog filter chain | `rtl/sound/usb_filter.sv` | No shared equivalent found. It is a fixed-point implementation of MAME’s approximate double-precision filter chain. | Keep local, but classify it as approximation rather than bit-exact RTL. The current correlation test is the correct validation style. |
| Speech output filter | `rtl/sound/speech_filter.sv` | No shared implementation found. It follows MAME’s netlist topology with the Sega schematic correction for R19. | Keep local; validate by listening and, ideally, against a cabinet recording. |
| Discrete audio boards | `rtl/sound/sega_discrete.sv` and `discrete_blocks.sv` | No suitable MiSTer-devel implementation found. The source boards are analog netlists in MAME, not simple digital devices. | Keep the behavioural model but mark it lowest confidence. A netlist-derived model or hardware recording should drive future fixes. |
| ROM/MRA/build tooling | `mra/` and `sim/tools/` | Core-specific. The MRA and ROM builder are tied to the six G80V game sets and the custom ROM layout. | Keep local; verify generated images against MAME ROM CRCs after any change. |

## Upstream snapshot table

These are the relevant repository heads checked during the survey:

| Repository | Branch | Commit | Use in this core |
|---|---|---|---|
| [Arcade-SegaVICZ80_MiSTer](https://github.com/MiSTer-devel/Arcade-SegaVICZ80_MiSTer) | `main` | `16386ffec0bf548520d174538190c09ffa426368` | TV80, 8035 wrapper/TV48, JT49 |
| [Arcade-StarWars_MiSTer](https://github.com/MiSTer-devel/Arcade-StarWars_MiSTer) | `main` | `5270c74394c3828500543845f76011f88226dbff` | System framework provenance and older renderer lineage |
| [Arcade-MajorHavoc_MiSTer](https://github.com/MiSTer-devel/Arcade-MajorHavoc_MiSTer) | `master` | `6933b85260dc4ccde8069d258dbfc595d28c3909` | Current renderer base |
| [Arcade-Asteroids_MiSTer](https://github.com/MiSTer-devel/Arcade-Asteroids_MiSTer) | `master` | `ab07109809d87ffc54b9071c373993c8b2c7afdb` | Newer alternative renderer branch, not a drop-in |
| [Arcade-Tempest_MiSTer](https://github.com/MiSTer-devel/Arcade-Tempest_MiSTer) | `master` | `31c52ce5d81d5ceee5a902475df438312fe30aff` | Related vector-core reference |
| [Arcade-DonkeyKong_MiSTer](https://github.com/MiSTer-devel/Arcade-DonkeyKong_MiSTer) | default branch | `737a576b0b5510a71f0aea68a3d5b5560ed5d468` | Alternate MCS-48/T48 integration |
| [Arcade-DonkeyKongJunior_MiSTer](https://github.com/MiSTer-devel/Arcade-DonkeyKongJunior_MiSTer) | default branch | `162b08701603f0019b20e453c0381092d2c2ab61` | Alternate MCS-48/T48 integration |
| [T80](https://github.com/MiSTer-devel/T80) | `master` | `830fd0315f0af5cdbcb0e703f1cea3ce4e91f538` | Standalone Z80 reference; older than the SegaVICZ80 pin |
| [devsaurus/t48](https://github.com/devsaurus/t48) | `master` | `837bd24f8a93275e0233c679b4f00e344bb4e912` | Original/current T48 reference, VHDL rather than this core’s converted Verilog |

The public MiSTer-devel organization was also searched for direct matches to
the unique Sega G80V, SP0250, and framebuffer module names. No direct matching
implementation was found for the unique Sega blocks or SP0250. GitHub’s code
search API became rate-limited during the broad search, so “not found” should
be read as “no known counterpart found in this survey,” not as a proof that no
copy exists anywhere in the organization.

## Renderer comparison: Major Havoc versus Asteroids

The Asteroids repository is newer by commit date, but its renderer is not a
strict successor to the Major Havoc renderer. The two trees differ throughout
the framebuffer, halo, phosphor, SDRAM, readout, and profile modules. Asteroids
also adds an asynchronous FIFO and overlay path; Major Havoc has the
`vfb_layout_pkg`, phosphor timing/compositor, and tone-mapper structure used by
this Sega core.

For Sega G80V, the Major Havoc base remains the better fit because:

* it is the renderer already adapted and running in this core;
* its frame and source-tick model matches the Sega vector generator integration;
* its color path was generalized locally to preserve all six Sega color bits;
  and
* the local simulation and hardware timing work was performed against this
  variant.

The right upgrade process is to compare individual Asteroids fixes against the
Major Havoc files, port one change at a time, and rerun the color, geometry,
renderer, and hardware checks.

## CPU and MCS-48 comparison

The Z80 choice is straightforward: the current core is already using the exact
TV80 source from the current SegaVICZ80 parent. The standalone `T80` repository
has not moved since 2021, so it is not a newer implementation in practice.

The 8035 path is more nuanced. This core uses the Verilog-converted T48
implementation in `rtl/tv48/`, wrapped by `rtl/i8035/i8035.v`. Donkey Kong’s
`i8035ip.v` is an older wrapper around a VHDL T48 implementation, while the
upstream T48 project has a newer VHDL revision and its own extensive regression
suite. The upstream T48 source is a useful verification oracle, but replacing
the current converted tree would change clock-enable, RAM, pin-drive, and
external-bus integration at the same time.

Recommended procedure if the 8035 becomes suspect:

1. Run the Sega speech and USB ROMs through the current wrapper and capture
   instruction/bus traces.
2. Run the same traces through a current T48 8035 configuration.
3. Compare ALE, PSEN, RD, WR, P1, P2, T0, T1, and interrupt timing.
4. Only then consider regenerating or replacing the RTL.

## Verification status

The core’s existing tests provide a useful quality ranking:

| Area | Evidence in the current checkout |
|---|---|
| Sega security | Exhaustive permutation test against MAME-derived behavior |
| Sega ports | Focused LS253, spinner, Eliminator four-player, and multiplier test |
| Color ladder | All ladder levels, monotonicity, and worst-error checks |
| Geometry | Focused coordinate/orientation test |
| SP0250 | Sample comparison against a C++ MAME-derived model |
| USB timers | Multi-million-sample comparison against MAME-derived 8253 model |
| USB noise | 400,000-step comparison against MAME-derived MM5837 model |
| USB filter | Correlation/shape/headroom comparison against MAME’s floating-point chain |
| XY generator | MAME-derived golden model plus vector-memory snapshots |
| Z80/memory map | Hand-coded CPU tests, security writes, IRQ path, and wait-state linearity |
| Boot | End-to-end boot/attract checks for all six supported ROM images |
| Discrete audio | Behavioural only; no bit-exact reference exists |
| Physical audio | Not yet heard through a speaker according to the core README |

The relevant commands are documented in [`../README.md`](../README.md) and the
targets are defined in [`../sim/Makefile`](../sim/Makefile).

## Upgrade priorities

1. **Document the `sys/` fork.** Generate a deliberate local-patch list against
   Star Wars so future framework updates can be reviewed instead of guessed.
2. **Cross-check the MCS-48 wrapper.** Use the upstream T48 regression suite as
   an oracle for the exact speech and USB board traces.
3. **Add a real SP0250 board-level test.** The decoder is strong; the 8035 ROM,
   latch, DRQ, and output-filter path remain the practical risk.
4. **Listen to the audio.** The discrete sound model is the least certain part
   and cannot be selected by source comparison alone.
5. **Review renderer changes selectively.** Track Major Havoc and Asteroids
   updates, but rebase only individual fixes that preserve the Sega six-bit
   color and source-tick assumptions.

