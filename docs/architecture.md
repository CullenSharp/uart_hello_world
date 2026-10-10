# Architecture

Two modules, one responsibility each. The transmitter knows how to put a byte on
a wire; the top level knows which byte comes next and how long to wait between
greetings.

```text
                       +--------------------------------------+
 i_Clk (25 MHz) ------>| hello_world                          |
                       |                                      |
                       |   MESSAGE = "Hello, World!" CRLF     |
                       |        |                             |
                       |   +----v-----+    +-----------+      |
                       |   | sequencer|---o| uart_tx   |----o--> o_UART_TX
                       |   | P_SEND   |    | CLKS_PER  |      |    (pin 74)
                       |   | P_WAIT   |    | BIT = 217 |      |
                       |   | P_GAP    |    +-----------+      |
                       |   +----+-----+                       |
                       |        o                            |
                       +--------|-----------------------------+
                                v
                            o_LED_1 (pin 56)
```

## `rtl/uart_tx.v`

A four-state Moore-style machine driven by a single cycle counter:

```text
        i_DV high                      CLKS_PER_BIT reached
  IDLE -------------> START -------------------------------> DATA
   ^                                                            |
   |                    stop bit done                           | bit 7 done
   +----------- STOP <-----------------------------------------+
                 |
                 +---- o_Done pulse, back to IDLE
```

- **IDLE** holds the line high and watches for `i_DV`. When it arrives the byte
  is latched into a shift register, the line drops, and the start bit begins on
  that very clock edge.
- **START** holds the line low for exactly `CLKS_PER_BIT` cycles.
- **DATA** shifts the byte right one position per bit period, so the least
  significant bit goes out first as 8N1 requires. The next bit is read out of
  `r_Shift[1]` *before* the shift is applied, which keeps the assignment and the
  shift coherent on the same edge.
- **STOP** holds the line high for one bit period, then pulses `o_Done`.

Three outputs describe the handshake: `o_Active` is high for the entire frame,
`o_Done` is a single-cycle pulse at its end, and `i_DV` is only sampled in IDLE
so a requester can hold it without accidentally starting a second frame.

Everything is expressed in clock cycles per bit rather than seconds. Set
`CLKS_PER_BIT` to whatever `clock / baud` rounds to and the module is correct at
any frequency — the formal harness uses `CLKS_PER_BIT = 4` precisely because the
structure does not depend on the value.

## `rtl/hello_world.v`

The top level carries three parameters: `CLK_FREQ_HZ`, `BAUD`, and `GAP_MS`.
Everything else, including `CLKS_PER_BIT`, is derived, so changing the baud rate
is a one-line edit that propagates correctly.

The message lives in a single packed vector with the leftmost character in the
most-significant byte:

```verilog
localparam [MSG_LEN*8-1:0] MESSAGE = {"Hello, World!", 8'h0D, 8'h0A};
```

A small sequencer walks it:

```text
  P_SEND --byte accepted--> P_WAIT --byte done--> P_SEND
     ^                                                |
     |                    last byte done              |
     +---------------- P_GAP <------------------------+
                         |
                         +--gap elapsed--> P_SEND (index back at 0)
```

`P_SEND` asserts `i_DV` and waits for the transmitter to raise `o_Active` before
dropping it, which guarantees the strobe is exactly long enough to be seen.
`P_WAIT` waits on `o_Done` rather than on `o_Active` falling, because those two
signals overlap for a cycle at the end of a frame and reading the wrong one
would advance the sequencer early.

## Design decisions worth knowing

**Power-on reset, not a reset button.** The Go Board exposes no reset pin, so
the design leans on how iCE40 devices actually work: Yosys writes every
register's declared initial value into the bitstream and the FPGA comes out of
configuration already in a known state. A 16-cycle power-on counter then holds
`uart_tx` in reset to make the start explicit and to keep the module reusable in
designs that do have a reset. This is why the registers carry both a
declaration initializer and a synchronous reset branch, which is exactly what
the waived `PROCASSINIT` lint warning is about.

**CRLF written as explicit bytes.** Not every Verilog front end recognises the
`\r` escape inside a string literal — Icarus does not, and silently produces
`r` instead of a carriage return. Spelling the terminator as `8'h0D, 8'h0A`
costs nothing and behaves identically in Icarus, Verilator and Yosys.

**Width-staged compare constants.** Comparing a narrow register against a
32-bit integer expression is legal Verilog but trips Verilator's width
warnings. The constants are therefore staged through a 32-bit `localparam` and
sliced down to the register's width, so every operand in a comparison matches.
It is a few extra lines, and it means `-Wall` stays on rather than being turned
down.

**The repeat gap is a parameter.** On hardware `GAP_MS` defaults to 500 ms,
which puts the heartbeat near 1 Hz. The testbench overrides it to 2 ms so a full
two-message run simulates in about 4.6 ms instead of a second. Baud, framing,
message contents and LED behaviour are identical between simulation and
synthesis — only the idle time differs.

## Costs

| Resource | Used | Available | Share |
| --- | --- | --- | --- |
| Logic cells | 129 | 1280 | 10% |
| IO pins | 3 | 72 | 4% |
| Global buffers | 2 | 8 | 25% |
| Block RAM | 0 | 16 | 0% |

Critical path is 6.6 ns, so the design closes at 151.6 MHz against a 25 MHz
requirement — roughly six times the margin needed. The gap counter is the bulk
of the area, at 24 bits wide for a 500 ms interval.
