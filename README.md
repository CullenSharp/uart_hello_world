# uart_hello_world

Prints `Hello, World!` over the UART on a **Nandland Go Board** (Lattice
iCE40HX1K-VQ100). The greeting repeats about twice a second and the first LED
toggles each time it is sent, so you get both a serial line and a heartbeat you
can see across the room.

Everything is built with the open-source iCE40 toolchain: Yosys, nextpnr-ice40,
IceStorm, Icarus Verilog, Verilator and SymbiYosys.

```text
$ picocom -b 115200 /dev/ttyUSB1
Hello, World!
Hello, World!
```

## Quick start

```sh
make          # synthesize, place & route, pack -> build/hello_world.bin
make prog     # write the bitstream to the board's SPI flash with iceprog
make sim      # run the testbench; it decodes the UART and prints the greeting
make test     # lint + sim + formal, the full pre-land bar
```

Open a terminal at **115200 8N1** on the board's second serial device and you
will see the greeting arrive. `make help` lists every target. The full
walkthrough, including terminal settings and what to do when something goes
wrong, is in [docs/bringup.md](docs/bringup.md).

## Design in one paragraph

A parameterised `uart_tx` module turns a byte plus a valid strobe into a
standard 8N1 frame, counting clock cycles per bit rather than seconds so it
works at any clock frequency. The `hello_world` top level holds the greeting as
one packed vector, walks a small three-state sequencer through it one byte at a
time, then idles for a configurable gap and starts again. That separation is
the whole design: the transmitter knows nothing about the message, and the top
level knows nothing about bit timing. [docs/architecture.md](docs/architecture.md)
has the state diagrams and the reasoning behind each decision.

The numbers that matter: 25 MHz clock, 115200 baud, 217 clocks per bit, which
works out to 115207.4 baud on the wire — an error of +0.006%, about 450 times
smaller than the ~2-3% budget a UART receiver gives you. See
[docs/uart.md](docs/uart.md) for the derivation.

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/hello_world.v` | Top level: message sequencer, gap timer, LED heartbeat |
| `rtl/uart_tx.v` | Reusable 8N1 UART transmitter |
| `constraints/hello_world.pcf` | The three pins this design drives |
| `constraints/go_board_reference.pcf` | Full official Go Board pinout, reference only |
| `sim/tb_hello_world.v` | Self-checking testbench with a UART receiver model |
| `formal/` | SymbiYosys properties and config for the transmitter |
| `docs/` | Architecture, UART protocol, toolchain, board bring-up |
| `build/` | Generated; every artifact the tools produce lands here |

## Verification

Three independent checks, all wired up as `make` targets:

- **Lint** — `verilator --lint-only -Wall`. Warnings are errors except for
  `PROCASSINIT`, which is waived deliberately (see the makefile for why).
- **Simulation** — Icarus runs a testbench that models a real terminal: it
  waits for each start bit, samples at the centre of every bit, checks the stop
  bit, and compares all 15 received bytes against the expected greeting for
  two consecutive messages. It also checks that the LED toggled exactly twice.
- **Formal** — SymbiYosys proves over a bounded trace that the transmitter's
  line idles high whenever nothing is being sent, that a frame never runs long,
  and that a frame that finishes lasted exactly `10 * CLKS_PER_BIT` cycles, with
  a cover property showing a complete frame is reachable.

All three currently pass. Current build numbers: **129 / 1280 logic cells
(10%)**, 3 of 72 IO pins, and a critical path of 6.6 ns — 151.6 MHz achievable
against the 25 MHz target.

## Status

The RTL has been linted, simulated, formally checked, and synthesized all the
way to a `.bin` bitstream. It has **not** yet been programmed to a physical Go
Board, so the bring-up guide describes the expected behaviour rather than a
confirmed run. The first hardware session is what `docs/bringup.md` is written
for.

## Documentation

- [docs/architecture.md](docs/architecture.md) — modules, state machines, and
  why the design is shaped the way it is
- [docs/uart.md](docs/uart.md) — the 8N1 protocol and the baud-rate arithmetic
- [docs/toolchain.md](docs/toolchain.md) — the build pipeline and every make
  target, plus the toolchain quirks worth knowing
- [docs/bringup.md](docs/bringup.md) — programming the board and opening a
  terminal, with troubleshooting
