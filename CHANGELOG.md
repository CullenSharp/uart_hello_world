# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions are tagged when a
bitstream is known good on hardware.

## [Unreleased]

### Added

- `uart_tx.v`: parameterised 8N1 UART transmitter with an `i_DV`/`o_Active`/
  `o_Done` handshake, expressed in clock cycles per bit.
- `hello_world.v`: top level for the Nandland Go Board that transmits
  `Hello, World!` plus CRLF every `GAP_MS`, with an LED heartbeat that toggles
  once per message.
- Constraints trimmed to the three driven pins, plus the full official Go Board
  pinout as a reference file.
- Self-checking Icarus testbench that decodes the UART like a terminal and
  verifies two complete messages and the LED heartbeat.
- SymbiYosys BMC and cover tasks proving line idling and frame length.
- Verilator lint with warnings as errors (one documented waiver).
- Makefile with real file dependencies and a `test` target running all checks.
- Documentation: README plus `docs/` covering architecture, UART protocol,
  toolchain and board bring-up.

### Notes

- Built to a `.bin` bitstream (129/1280 logic cells, 151.6 MHz against a 25 MHz
  target) but not yet programmed to physical hardware.
