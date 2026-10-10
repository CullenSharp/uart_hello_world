# AGENTS — uart_hello_world

Repo-local notes for working on this project. Workspace-wide Verilog
conventions live in `../../AGENTS.md`.

## Commands

`make test` is the bar before calling anything done: verilator lint, the
self-checking Icarus testbench, and the SymbiYosys runs. `make` builds
`build/hello_world.bin` only; `make prog` is what touches hardware. `make help`
lists everything.

Run `sby` from the repository root (via `make formal`), not from `formal/`.

## Invariants

- The greeting exists twice: `MESSAGE` in `rtl/hello_world.v` and `EXPECTED` in
  `sim/tb_hello_world.v`. Change both.
- CRLF is written as `8'h0D, 8'h0A`, never `\r\n`. Icarus parses `\r` as a
  literal `r`; see `docs/toolchain.md`.
- `sim/tb_hello_world.v` instantiates the design with `GAP_MS(2)`. Anything
  else about the simulated configuration must match synthesis.
- `constraints/hello_world.pcf` is trimmed to the ports the design actually
  has — nextpnr errors on `set_io` for a missing port. Grow it in step with the
  RTL; `constraints/go_board_reference.pcf` is the source to copy from.
- `all` deliberately does not program the board. Do not add `prog` to it.

## Toolchain gotchas

- Current sby wants `[tasks]` with `taskname: value` options. The older
  `[task name]` section headers are a hard error.
- sby `[files]` sources resolve from the invocation directory, and `[script]`
  lines name the copied basenames inside the work directory.
- Verilator lint runs `-Wall` with warnings as errors. The only waiver is
  `PROCASSINIT`, because power-on declaration initializers plus a synchronous
  reset are intentional here (iCE40 loads initial values from the bitstream).
  Do not add waivers without updating the comment in the makefile.
- Comparing a narrow register to a 32-bit expression trips `WIDTHEXPAND`; a
  32-bit expression in a sized `localparam` trips `WIDTHTRUNC`. Stage constants
  through a 32-bit `localparam` and slice, as the `*_FULL` constants do.

## Documentation

README plus `docs/` are user-facing: architecture, UART protocol, toolchain,
bring-up. User-visible behaviour changes need a matching doc edit and a
`CHANGELOG.md` entry. Bring-up claims must be marked as unverified until a
run on physical hardware backs them up.
