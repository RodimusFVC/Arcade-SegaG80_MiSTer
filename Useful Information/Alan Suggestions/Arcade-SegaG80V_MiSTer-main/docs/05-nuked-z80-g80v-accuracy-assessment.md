# Nuked Z80 and Sega G80V accuracy assessment

Reviewed 2026-08-07.

This assessment asks a system-level question: what can the decap-derived Nuked
NMOS Z80 do for the G80V core, beyond being a difficult CPU replacement? The
focus is vector RAM ownership, CPU bus timing, arbitration, wait states,
refresh/refetch behavior, priorities, and the possibility that demo-loop
glitches are caused by an incorrectly updated vector list.

## Bottom line

Nuked Z80 is worth evaluating for the accuracy path, but it is not an automatic
solution to G80 vector-RAM arbitration. It can provide a more faithful model of
the Z80's own phase-level behavior and make the external memory problem easier
to observe. It cannot decide which device owns the X-Y RAM, when the CPU should
wait, or what happens when the CPU and vector generator request the same RAM
slot.

The largest likely accuracy improvement is therefore not a CPU swap by itself.
It is the combination of:

1. a phase-accurate CPU bus;
2. a single-port or explicitly arbitrated vector-RAM model; and
3. a `DRAW` signal whose duration matches the real X-Y board.

## What Nuked actually provides

The official [Nuked-MD-FPGA repository](https://github.com/nukeykt/Nuked-MD-FPGA)
describes its goal as an accurate Verilog recreation of the Mega Drive chipset
using decapped-chip photographs. The project targets an NMOS Z80; its author
reported that the Z80 was tested on a real Mega Drive board and passed
SMS-ZEXALL. That is strong evidence for the implementation, but it is not proof
that the G80 cabinet used the identical Z80 mask or that every G80-specific
board interaction is the same.

The [Nuked `z80.v`](https://github.com/nukeykt/Nuked-MD-FPGA/blob/main/z80.v)
module is materially different from TV80/T80:

| Property | Current G80V | Nuked Z80 |
|---|---|---|
| CPU style | T-state/microcode RTL | Gate/latch-oriented NMOS recreation |
| Clocking | Host clock plus `ce_cpu` | Separate `MCLK` and Z80 phase `CLK` |
| Bus outputs | Registered active-low signals | Explicit bus values plus `*_z` drive controls |
| M1/refresh | Exposed through the TV80 bus model | Generated inside the reconstructed phase logic |
| WAIT | External counter feeds `wait_n` | WAIT participates in the phase/latch network |
| BUSRQ/BUSAK | BUSRQ tied inactive in G80V | Modeled by the CPU core |
| Provenance | Generic compatible Z80 RTL | NMOS die shots, decap analysis, and VisualZ80 references |

Nuked can improve the CPU-side observability of:

* exact M1/opcode-fetch boundaries;
* refresh timing;
* WAIT sampling and release;
* address and data bus drive/release windows;
* interrupt acknowledge;
* NMI and reset sequencing;
* BUSRQ/BUSAK behavior; and
* NMOS-specific flags or bus quirks.

It does not contain a G80 vector-RAM arbiter. Its BUSRQ facility is also not a
substitute for the G80 X-Y board's RAM scheduling: BUSRQ releases the entire Z80
bus, while the G80 problem is primarily access to one shared RAM subsystem.

## Is vector-RAM contention real?

It is a credible hardware failure mechanism.

The G80 X-Y system uses the same 4K vector RAM for Z80 display-list writes and
vector-generator reads. The game software polls `DRAW` before changing the
list. The MAME driver exposes vector RAM as the display-list memory and reports
`DRAW` according to whether the vector pass is still active. See the upstream
[G80 memory map and vector-RAM handler](https://github.com/mamedev/mame/blob/master/src/mame/sega/segag80v.cpp).

The current MiSTer implementation intentionally simplifies this. In
[`rtl/xy/sega_xy_top.sv`](../rtl/xy/sega_xy_top.sv), the CPU and vector
generator use independent ports of an inferred FPGA RAM. CPU accesses receive a
fixed wait count in
[`rtl/segag80v_cpu.sv`](../rtl/segag80v_cpu.sv), but the wait is not generated
by actual X-Y RAM ownership.

That has two consequences:

1. The FPGA can service CPU and vector-generator accesses independently even
   where the original board would serialize them.
2. If both ports touch the same address on one FPGA edge, the inferred RAM's
   read-during-write behavior may differ between simulation and hardware.

Therefore, a wrong or partially updated vector list is possible in the real
hardware model, even though the current implementation does not explicitly
model a RAM conflict.

## Most likely causes of the demo-loop glitch

This is an engineering hypothesis, not a measured probability. My current
weighting is:

| Candidate | Weight | Reason |
|---|---:|---|
| Incorrect `DRAW` duration or vector phase timing | 40% | The CPU may begin rewriting the list while the generator is still consuming it. The phase-clock interpretation is already an open G80V question. |
| Missing single-port vector-RAM arbitration | 30% | Dual-port RAM hides conflicts and leaves same-edge read/write behavior undefined at the FPGA RAM level. |
| CPU transaction/security/write-edge timing | 20% | The `$32` address scrambler and vector-RAM writes depend on exact opcode-fetch and write boundaries. |
| A TV80-specific undocumented NMOS difference | 10% | Possible, but less likely until a TV80/Nuked trace shows a real divergence. |

The existing boot and vector tests are valuable, but matching MAME's write stream
does not eliminate this problem. MAME's display-list model does not reproduce
the physical shared-RAM bus conflict, and MAME's `DRAW` signal is represented as
a time comparison rather than a board-level RAM grant.

## How Nuked helps each requested area

### Vector RAM

Indirectly. Nuked gives a better request timeline, but the RAM needs a new
arbiter around it.

### CPU timing

Potentially substantially. Nuked's phase/latch model should be a better oracle
for the exact point at which M1, MREQ, RD, WR, and refresh become active.

### Arbitration

Not automatically. Arbitration is outside the CPU. We would need to implement
the G80 X-Y RAM schedule separately.

### Wait states

Potentially substantially. Instead of applying two fixed waits to every memory
access, the wrapper could hold WAIT until the requested RAM slot is granted.
Nuked's phase-level WAIT behavior would make the release point more faithful.

### Refetches and refresh

Nuked makes these easier to inspect. A Z80 WAIT normally holds the current bus
cycle; it does not simply refetch the opcode. The relevant distinctions are
M1 opcode fetches, refresh cycles, prefixed fetches, block-instruction cycles,
and interrupt acknowledge cycles. Nuked could reveal whether the current
security hook is one phase early or late.

### Priorities

The priority decision is external. The important G80 priority is likely
vector-generator RAM slots versus CPU RAM requests, not Mega Drive-style
68K/Z80 bus ownership. The correct mechanism is probably a RAM grant plus WAIT,
not BUSRQ.

## Biggest changes required to exploit Nuked fully

### 1. Replace the clock-enable CPU arrangement

The current G80V uses a 12.096 MHz host clock and advances TV80 with a
fractional `ce_cpu`. Nuked expects a stable `MCLK` plus a correctly related Z80
phase clock.

A full-fidelity arrangement would need a clock plan resembling:

```text
15.46848 MHz G80 board crystal
        ├── Z80 phase clock: 3.86712 MHz
        ├── vector-generator clock
        └── faster MCLK for Nuked's latch evaluation
```

The exact implementation could use a PLL and one coherent domain, or a
separate CPU domain with carefully designed crossings. Feeding a one-cycle
clock enable directly into Nuked's `CLK` input should not be assumed correct.

### 2. Add an explicit Nuked bus adapter

Nuked provides address, data, control signals, and separate output-enable
signals. FPGA internal tri-states should be converted to explicit drive enables
and resolved muxes:

```text
cpu_address_drive
cpu_data_drive
cpu_mem_request
cpu_io_request
cpu_read
cpu_write
cpu_refresh
```

This adapter is also the right place to expose a normalized CPU bus trace.

### 3. Replace fixed WAIT with transaction-specific WAIT

The current wrapper uses a fixed wait counter for memory accesses. A more
accurate model should distinguish:

* ROM accesses;
* work RAM accesses;
* vector RAM accesses;
* USB shared RAM accesses; and
* refresh cycles.

For vector RAM, WAIT should stay asserted until the X-Y arbiter grants the
actual CPU transaction. The CPU address, data, and write intent must remain
stable throughout the wait.

### 4. Implement a real vector-RAM arbiter

The largest system change would be replacing the current independent RAM ports
with an explicit ownership model:

```text
X-Y phase clock
      ↓
vector RAM scheduler
      ├── generator read slot
      └── CPU access / WAIT release
```

The arbiter should expose debug signals such as:

```text
xy_ram_grant
cpu_ram_grant
cpu_ram_waiting
xy_ram_addr
cpu_ram_addr
same_address_collision
cpu_write_commit
xy_read_commit
```

The phase schedule should remain parameterized until the schematics and
hardware observations settle which device wins each slot.

### 5. Move security handling to the transaction boundary

The security logic should consume the exact opcode-fetch event, opcode address,
opcode data, and following write transaction. It should scramble the address
only when the `$32` condition is satisfied, then hold the resulting address
through the physical write commit.

Nuked's M1/address/write timing could make this more accurate, but the security
logic still belongs in the G80 bus wrapper, not inside the CPU.

### 6. Instrument `DRAW` and list mutation together

The most useful failure trace should record:

```text
CPU PC
CPU address/data
M1/MREQ/RD/WR/RFSH
WAIT
DRAW
frame_start
vector-generator state
generator RAM address
CPU RAM address
CPU write commit
same-address collision
```

When the demo fails, compare the first divergent CPU write, the final vector-RAM
image, and the addresses consumed by the vector generator. This will tell us
whether the list was corrupted, read at the wrong time, or merely rendered with
the wrong phase/budget.

## Recommended migration plan

### Phase 1: CPU trace oracle

Run the same small programs through TV80 and Nuked and compare every phase:

* `LD (nn),A`;
* `LD (HL),A`;
* `IN`/`OUT`;
* prefixes and indexed operations;
* block instructions;
* `EI`, `DI`, and `HALT`;
* IM 1 interrupt acknowledge;
* NMI;
* WAIT inserted at every possible T-state; and
* repeated vector-RAM-style writes.

Normalize Nuked's tri-state outputs into TV80-style bus signals and record
address, data, M1, MREQ, IORQ, RD, WR, refresh, WAIT, and interrupt state.

### Phase 2: Nuked behind the current G80 wrapper

Use Nuked with the existing fixed waits and dual-port RAM. If the demo glitch
does not change, the CPU core is probably not the primary cause. If the vector
write stream changes, compare the first divergent write and its security state.

### Phase 3: Shared vector RAM

Add the single-port/arbitrated RAM model and dynamic WAIT. This is the step most
likely to reproduce the original G80 board behavior.

### Phase 4: Validate `DRAW`

Measure the time from `EDGINT` to `DRAW` deassertion, count vector-RAM reads,
record CPU writes while `DRAW` is high, and verify that the demo software's list
rewrite begins only after the generator has released the RAM.

## Pros and cons

### Advantages

* Better candidate for exact NMOS Z80 phase behavior.
* Explicit bus-drive and bus-release windows.
* More useful M1, refresh, WAIT, reset, and interrupt traces.
* Could expose errors hidden by TV80's normalized bus model.
* Provides a high-fidelity reference against which TV80 and the G80 wrapper can
  be tested.

### Costs and risks

* It is not a drop-in TV80 replacement.
* The clocking model is substantially more demanding.
* The FPGA wrapper must resolve tri-state buses explicitly.
* Resource use and timing closure need to be measured on the DE10-Nano.
* The Nuked target is a Mega Drive NMOS Z80, not a proven G80 Z80 die.
* It does not implement G80 vector-RAM arbitration.
* A CPU replacement could obscure the real problem if `DRAW` or X-Y timing is
  wrong.
* The current TV80 already passes the G80 security, wait-linearity, boot, and
  display-list tests, so replacing it before tracing would discard useful
  validated behavior.

## Recommendation

Keep TV80 temporarily, add a TV80-versus-Nuked bus-trace harness, and use Nuked
as a high-fidelity NMOS oracle first.

The production upgrade should be considered successful only if it combines the
Nuked CPU timing with a real G80 vector-RAM scheduler and a measured `DRAW`
window. A Nuked-only CPU swap is worthwhile as an experiment, but it is unlikely
to fix a corrupted display list if the underlying problem is the current
dual-port RAM and fixed-wait architecture.
