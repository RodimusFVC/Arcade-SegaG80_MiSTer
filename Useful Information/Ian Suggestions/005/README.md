# Sega 005 (1981) sound board in Verilog

An FPGA implementation of the sound board from Sega/Gremlin's *005*, drawing
number **834-0130**, part of the G-80 raster card cage.

Sources used:

* *005 Owner's Manual*, part 420-0692 — bill of materials for the sound board
  on manual pages 45–48 (PDF pages 47–50), schematics on PDF pages 71–73.
  <https://archive.org/details/arcademanual_005>
* MAME `src/mame/sega/segag80r.cpp` and `segag80r_a.cpp` for the
  reverse-engineered behaviour of the melody chain.

---

## 1. What is on the board

From the BOM (drawing 834-0130):

| Ref | Part no. | Device | Role |
|---|---|---|---|
| U5 | 315-0080 | 8255 PPI | CPU interface |
| U16 | 316-1286 | 2716 EPROM (EPR-1286) | tune sequence data, 2048x8 |
| U8 | 316-1302 | 6331 bipolar PROM (PR-5001) | note divisor table, 32x8 |
| U3, U21, U22, U27 | 314-0001 | NE555 | U3 = tempo; the other three sit in the effect circuits |
| U9 | 314-0075 | 74LS393 | tune address counter |
| U7, U15 | 314-0097 | 74LS161 | note frequency divider |
| U14 | 314-0250 | 74LS293 | output divider / waveshaper |
| U1, U2, U20 | 314-0016 | 74123 | one-shot envelopes |
| U13 | 315-0035 | MM5837 | noise source |
| U28, U30, U31, U32 | 313-0084 | MB4391 | VCAs |
| U29 | 315-0033 | CD4016 | analogue routing |
| U12, U18, U23, U25, U26 | 313-0034 | LM324 | filters and summing amp |
| Q1–Q6 | 482-0043 | 2SC458C | discrete gain stages |
| VR1–VR8 | 220-0196 | 50k trimmer | one level trim per voice |
| VR9 | 220-0197 | 500R trimmer | **melody pitch trim**, not a volume |
| U4, U6, U10, U11, U17, U19 | — | LS14, LS38, LS30, LS04, LS32, 7417 | glue |

Note there are **eight** 50k trimmers and **eight** voices (seven effects plus
the melody). Sheet 8 gives the assignment:

| VR1 | VR2 | VR3 | VR4 | VR5 | VR6 | VR7 | VR8 |
|---|---|---|---|---|---|---|---|
| small expl | large expl | missile | melody | pistol | whistle | bomb drop | helicopter |

Every voice reaches the summing node through an identical 51k (R125–R132) and
1µF, so the trimmers alone set the balance. The summing amp is U26 with
R118 10k in and R117 47k feedback, a gain of 4.7.

VR9 is worth calling out: despite the BOM listing it as "Vol Cont 500 Ohm", it
is **not** a volume control. It sits in the RC of the 74LS14 oscillator that
clocks the note divider, so it is the melody tuning trim.

## 2. CPU interface

The 8255 sits at Z80 I/O ports `$0C`–`$0F` in the G-80 map:

```
$0C  port A   effect triggers
$0D  port B   melody generator control
$0E  port C   unused
$0F  control
```

### Port A — effect triggers, all ACTIVE LOW

| Bit | Voice | Behaviour |
|---|---|---|
| A0 | Large explosion | one shot on falling edge |
| A1 | Small explosion | one shot on falling edge |
| A2 | Drop bomb | one shot on falling edge |
| A3 | Shoot / pistol | one shot on falling edge |
| A4 | Missile | one shot on falling edge |
| A5 | Helicopter | runs while low, stops on rising edge |
| A6 | Whistle | runs while low, stops on rising edge |
| A7 | — | unused |

### Port B — melody generator

| Bit | Function |
|---|---|
| B0–B3 | upper 4 bits of the 2716 address (tune page select) |
| B4 | 1 = hold the LS393 address counter and the divider at zero |
| B5 | 1 = 555 clocks the counter (auto), 0 = manual |
| B6 | manual clock, acts on the 0 -> 1 transition |
| B7 | unused |

## 3. Melody chain

```
        NE555 U3
        R5=15k  R4=4k7  C120=1u5
        f = 1.44 / ((R5 + 2*R4) * C) = 39.344 Hz
              |
              |  held in RESET while 2716 D5 = 0
              v
        74LS393 U9    8-bit counter, async CLR from port B bit 4
              |
              |  counter[7:1]   <-- note the divide by two
              v
        2716 U16  addr = { PB[3:0], counter[7:1] }
              |
              +--> D[4:0]  PROM address
              +--> D5      555 run / reset
              +--> D6,D7   unused / unknown
              v
        6331 U8   32x8  ->  reload value N
              |
              v
        74LS161 x2  U7,U15   8-bit counter, reloads N on overflow
              |              period = 256 - N ticks
              |  carry
              v
        74LS293 U14   carry clocks the QB stage (i.e. +2 per carry)
              |
              |  QB through R34 27k, QD through R50 15k
              v
        C33 .1u / R135 10k / C34 .01u    159 Hz HP, 1592 Hz LP
              |
              v
        MB4391 U32 (VCA)  ->  mixer
              ^
              |
        U2 74123 (R7 47k, C14 3.3u -> 0.70 s), retriggered by the 555,
        then D2 / R12 470R / C27 1u / R10,R11 470k
```

The LS161 clock, which I could not identify from the BOM alone, is a **74LS14
Schmitt relaxation oscillator**: U4 with R134 (220R) in series with VR9 (500R)
and C9 (4700pF).

```
f = 1 / (0.8 * R * C)
R = 220R  ->  1.21 MHz        (pot at minimum)
R = 470R  ->   566 kHz        (pot centred)
R = 720R  ->   369 kHz        (pot at maximum)
```

Because QB and QD are both in the sum, the waveform repeats every eight
carries, so the perceived pitch is the QD rate:

```
f_note = f_osc / (8 * (256 - N))
```

With the pot centred that spans about 276 Hz (N=0) up to a couple of kHz over
the useful part of the table — a sensible three-octave melody range. QB sits a
fourth harmonic above and is partly rolled off by the 1592 Hz low pass, which
is what gives the voice its hollow, slightly reedy character.

Two consequences worth knowing:

* Because QB and QD are mixed, the melody voice is not a plain square wave —
  it contains the fundamental and a component at a quarter of that rate, which
  is what gives the tune its slightly hollow, reedy character.
* Because the 555 is held in reset while ROM data bit 5 is low, a `D5 = 0` byte
  is an end-of-phrase marker: the sequencer stops dead and waits for the CPU to
  either reset it (B4) or hand-clock it (B6).
* The melody VCA is opened by a retriggerable 0.70 s one-shot fed from the
  tempo 555, so the voice stays open while the tune is clocking and fades out
  about a second after it halts. No CPU action is needed to mute it.

## 4. Files

```
rtl/sega005_sound.v    top level: PPI, ROMs, mixer, sigma-delta output
rtl/melody_gen.v       the chain above, gate for gate
rtl/i8255_mode0.v      mode-0 subset of the 8255
rtl/mm5837_noise.v     17-bit LFSR noise source + env_gen
rtl/fx_bank.v          the seven effect voices, from sheets 8 and 9
rtl/svf.v              state variable filter, models the LM324 sections
sim/tb_sega005.v       testbench, writes audio.txt
epr-1286.hex           PLACEHOLDER tune ROM
pr-5001.hex            PLACEHOLDER divisor PROM
```

## 5. Build and simulate

```sh
iverilog -g2005 -o tb sim/tb_sega005.v rtl/*.v
./tb                    # writes audio.txt, one decimal sample per line @48 kHz
```

For synthesis, instantiate `sega005_sound` and point `ROM_FILE` / `PROM_FILE`
at your hex images. `rom_sync` infers block RAM on Vivado, Quartus and Yosys.
Everything is plain Verilog-2001 with no vendor primitives.

```verilog
sega005_sound #(
    .CLK_HZ       (50_000_000),
    .LS161_CLK_HZ (100_000),
    .ROM_FILE     ("epr-1286.hex"),
    .PROM_FILE    ("pr-5001.hex")
) snd (
    .clk(clk), .rst_n(rst_n),
    .cs_n(io_cs_n), .wr_n(io_wr_n), .rd_n(io_rd_n),
    .cpu_addr(cpu_a[1:0]), .cpu_din(cpu_do), .cpu_dout(snd_do),
    .audio(audio16), .audio_pwm(audio_pin)
);
```

## 6. Parameters you will want to touch

| Parameter | Default | Why |
|---|---|---|
| `LS161_CLK_HZ` | 566 000 | VR9 setting; legal range 369k–1.21M |
| `NOISE_HZ` | 40 000 | MM5837 internal oscillator, supply dependent |
| `DIV2_ADDR` | 1 | 1 matches the schematic, 0 matches MAME (tune runs 2x fast) |
| `W_QB`, `W_QD` | 14000, 25200 | fixed by R34 27k and R50 15k, ratio 0.556 : 1 |
| `VR1_..VR8_` | various | the eight trimmers |
| `AUDIO_HZ` | 48 000 | rate at which every filter and envelope runs |

## 7. Voice-by-voice derivation

All values from sheets 8 and 9. The filter sections are all the same
multiple-feedback topology, so `f0 = 1/(2*pi*C*sqrt(R_in*R_fb))` and
`Q = 0.5*sqrt(R_fb/R_in)`.

| Voice | Source | Section | f0 | Envelope |
|---|---|---|---|---|
| Noise 1 | U13 MM5837 | U18 buffer, R55 100k / R56 10k | — | — |
| Noise 2 | Noise 1 | U23, R93 10k / R92 100k / C70,C71 .01u | 503 Hz, Q 1.58 | — |
| Large expl | Noise 1 | U18, R53,R54 15k / C52,C53 .047u | 226 Hz | U2 74123 0.21 s, then C25 1u / 500k |
| Small expl | Noise 1 | U18, R44,R45 10k / C47,C48 .039u | 408 Hz | C28 .47u / R18 470k, τ 0.22 s |
| Missile | Noise 2 | U23, R91 10k / R86 47k / C67,C68 .01u | 734 Hz, Q 1.08 | C26 1u / R23 470k, τ 0.47 s |
| Pistol | Noise 2 | U25, R62 10k / R63 100k / C55,C56 .022u | 229 Hz, Q 1.58 | U20 74123 0.21 s, C64 10u / R80 10k |
| Helicopter | Noise 2 chopped | U22 NE555, R97 10k / R98 150k / D9 / C75 .68u | 13.3 Hz, 6% duty | C46 10u / R40 100k, τ 1.0 s |
| Whistle | U27 NE555 | R114 1k / R113 15k / C91 .022u | 2112 Hz | gated via U29 CD4016 |
| Bomb drop | swept osc | R71 22k / C59 4700p, swept by Q2 | 1.5 kHz falling | U21 NE555 sweep gate |

The helicopter chopper is worth a note. D9 across R98 makes the 555 charge
through R97 alone and discharge through R98, so the output is high for
`0.693 * 10k * .68u` = 4.7 ms and low for `0.693 * 150k * .68u` = 70.7 ms.
That is 13.3 Hz at about 6% duty — a short blade slap rather than a symmetric
chop, which is why the real thing sounds like a rotor and not a tremolo.

The whistle's 555 has its CON pin driven from the U26 network (R115, R116 22k
with C79, C93 2.2µ, about 3.3 Hz), so the pitch warbles rather than sitting
still.

## 7b. What is still open

**The 6331 PROM at U8 has never been dumped.** MAME carries a reconstruction
flagged `BAD_DUMP`. The `pr-5001.hex` here is my own placeholder, generated as
an equal-tempered chromatic scale from the now-known relation
`f = 566000 / (8 * (256 - N))`. Until someone reads a real one, the tune plays
the right rhythm with the wrong notes. Thirty-two bytes on a 16-pin socket.

**Two readings I am less sure of.** The U2 74123 trigger on sheet 7 looks like
it comes from the tempo 555 output, which is both musically sensible and
consistent with the rest of the circuit, but the trace is hard to follow at
this scan resolution. And the pistol section could be a high pass rather than
the band pass I have assumed; 229 Hz is low for a stun-gun zap, so if it sounds
wrong, try the `hp` output of `f_pis` instead of `bp`.

**Everything else now comes from the schematics rather than from guesswork.**

## 8. Next steps, roughly in order of payoff

1. Dump the real 6331 at U8. Thirty-two bytes, and it is the missing piece for
   everyone, not just this project.
2. Replace the placeholder tune ROM with the real EPR-1286
   (`fbe0d501` / `bfa277689790f835d8a43be4beee0581e1096bcc`).
3. Compare against a real board and trim `LS161_CLK_HZ` to match VR9, then the
   per-voice `VR*` levels.
4. Resolve the two open readings in section 7b.
