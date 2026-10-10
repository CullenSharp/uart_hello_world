# Toolchain

Everything here runs on the open-source iCE40 flow from the oss-cad-suite. No
Lattice tools are involved at any stage.

## The pipeline

```text
  rtl/*.v ──yosys──> build/hello_world.json ──nextpnr-ice40──> build/hello_world.asc
                                                                 │
                                       build/hello_world.bin <──icepack
                                                  │
                                              iceprog ──> board SPI flash
```

| Stage | Tool | Input | Output | What it does |
| --- | --- | --- | --- | --- |
| Synthesis | Yosys | `rtl/*.v` | `.json` | Translates Verilog into iCE40 LUTs, flip-flops and carry chains |
| Place & route | nextpnr-ice40 | `.json`, `.pcf` | `.asc` | Chooses physical cells, routes them, maps ports to pins, checks timing |
| Pack | icepack | `.asc` | `.bin` | Converts the ASCII bitstream into the bytes the flash stores |
| Program | iceprog | `.bin` | — | Writes the flash over the on-board FTDI and resets the FPGA |

The `.pcf` is only consulted at place & route, which is why a typo in a pin
number surfaces late in the build rather than at synthesis.

The constraints file is deliberately trimmed to the three pins this design
drives. nextpnr fails on a `set_io` that names a port the design does not have,
so the full board pinout lives alongside it in
`constraints/go_board_reference.pcf` for copy-paste when the design grows.

## Make targets

| Target | Effect |
| --- | --- |
| `make` | Build `build/hello_world.bin`. Does **not** touch the board |
| `make syn` / `pnr` / `pack` | Individual pipeline stages, as real file dependencies |
| `make prog` | Flash the bitstream to the board |
| `make sim` | Compile and run the self-checking testbench |
| `make wave` | Same, with a VCD, then open gtkwave |
| `make lint` | Verilator lint of the RTL |
| `make formal` | SymbiYosys BMC and cover runs |
| `make test` | `lint` + `sim` + `formal` — the bar before calling work done |
| `make clean` | Remove build products and formal work directories |
| `make help` | One-line summary of all of the above |

The three pipeline stages are declared as real file rules with prerequisites, so
rebuilding after a one-line edit to `rtl/uart_tx.v` only redoes what is actually
stale, and `make -j` is safe. `syn`, `pnr` and `pack` are aliases kept for
consistency with the sibling projects in `~/git/verilog`.

Note that `make` stops at the bitstream while `make prog` is what reaches for
hardware. That is a deliberate change from the sibling `cs_go_sw2led` makefile,
where `make` both builds and programs — convenient, but surprising when you just
wanted to check that something still compiles.

Tools can be overridden without editing the makefile:

```sh
make NEXTPNR=/opt/nextpnr/bin/nextpnr-ice40 sim
```

## Verification in detail

**Lint.** `verilator --lint-only -Wall` runs with warnings as errors. The one
waiver is `PROCASSINIT`, because this design intentionally declares a power-on
value *and* assigns the register in a reset branch — the iCE40 takes the
power-on value from the bitstream, and the reset makes restart behaviour
explicit. The reasoning is recorded in the makefile next to the flag so it
cannot silently become a habit.

**Simulation.** Icarus compiles the RTL together with `sim/tb_hello_world.v`.
The testbench does not peek at internal state; it models a terminal. It waits
for the falling edge of each start bit, samples at `1.5` bit periods, then every
bit period after that, checks the stop bit is high, and compares the byte against
the expected message. It runs for two full messages so the message-boundary and
gap logic is exercised, and it independently counts LED transitions to confirm
the heartbeat. Failure uses `$fatal`, so `make sim` returns non-zero and is safe
to wire into CI.

The testbench instantiates the design with `GAP_MS(2)` instead of the shipped
500 ms. That is the only difference from hardware; baud, framing, message and LED
behaviour are identical. A full run takes about 4.6 ms of simulated time and
under a second of wall time.

**Formal.** `formal/uart_tx.sby` runs two tasks against
`formal/uart_tx_props.v`:

- `bmc` — bounded model check to depth 64 proving the line idles high whenever
  the transmitter is not active, that an in-flight frame never exceeds
  `10 * CLKS_PER_BIT` cycles, and that a frame which does finish lasted exactly
  that many.
- `cover` — confirms a complete frame is actually reachable, so the assertions
  are not passing vacuously.

The harness instantiates `uart_tx` with `CLKS_PER_BIT = 4`, making a full frame
only 40 cycles deep and keeping the proof fast — both tasks finish in about a
second. The state machine structure does not depend on the constant, so what is
proven at 4 carries over to the shipped 217; the sim and the synthesis are what
confirm the specific value.

## Tool versions

Recorded from the oss-cad-suite dated **20260926**:

| Tool | Version |
| --- | --- |
| Yosys | 0.69+154 |
| nextpnr-ice40 | 0.11.1-33-g1aea87ab |
| Icarus Verilog | 14.0 (devel, s20260301) |
| Verilator | 5.053 devel |
| SymbiYosys | v0.69 |
| IceStorm | `icepack`, `iceprog` from the same suite |

If a build behaves oddly after a suite upgrade, check versions here first.

## Toolchain quirks encountered

These cost real time during development and are worth not rediscovering:

- **`\r` in a string literal is not portable.** Icarus parses `"a\r\n"` as
  `a` + `r` + LF, not a carriage return. The greeting therefore spells out
  `8'h0D, 8'h0A` explicitly. Yosys and Verilator were never given the chance to
  disagree, because the escape is gone.
- **SymbiYosys config syntax changed.** Current sby uses a `[tasks]` section
  listing task names, with options written as `taskname: value`. The older
  `[task name]` section headers are rejected outright.
- **sby's `[files]` sources resolve from the invocation directory**, and the
  design is read from a copied `src/` inside the work directory. Paths in the
  `[script]` section therefore name the *copied* basename, not the original
  path, and `[files]` does the mapping. Run `make formal` from the repository
  root.
- **Width warnings are easier to fix than to waive.** Comparing a narrow
  register against a 32-bit constant expression is legal but trips
  `WIDTHEXPAND`; assigning a 32-bit expression into a sized `localparam` trips
  `WIDTHTRUNC`. Staging the constant through a 32-bit `localparam` and slicing
  it satisfies both without weakening the lint run.

## Reading a waveform

```sh
make wave
```

produces `build/hello_world.vcd` and opens gtkwave. The signals worth
looking at first are `dut.r_Phase` (the sequencer), `dut.uart_tx_i.r_State`
(the frame FSM), and `o_UART_TX`. Zooming to one byte shows the start bit,
eight data bits and the stop bit laid out against the 8.68 µs bit period.
