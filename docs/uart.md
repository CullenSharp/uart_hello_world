# UART protocol and timing

The line carries **8N1**: eight data bits, no parity, one stop bit. There is no
flow control and no clock line — both ends have to agree on the baud rate
upfront, and that agreement is the only thing that makes the link work.

## What one byte looks like

```text
  idle   start    D0  D1  D2  D3  D4  D5  D6  D7   stop   idle
   1  ─────┐                                                             
           └──────────────────────── 8 bit times ─────────────────────┐   
                                                                      └── 
            ▲                                                        ▲    
            │ low for exactly one bit time                           │ high
            └─ the receiver triggers on this falling edge            └────
```

The line idles high, so a receiver notices a byte by the falling edge of the
start bit. Data goes out least significant bit first, which is why `D0` comes
first in the diagram. The stop bit gives the line a guaranteed high period
before the next start edge, and it doubles as the receiver's resynchronisation
point — a receiver that has drifted a little re-aligns on every byte rather than
accumulating error across a message.

A frame is therefore **10 bit times**, which at 115200 baud is 86.8 µs. The
15-byte greeting takes 1302 µs, about 1.3 ms, and the link can move 11 520 bytes
per second in this configuration.

## Deriving the clock count

The Go Board's oscillator runs at exactly 25 MHz, so one clock cycle is 40 ns.
A bit at 115200 baud lasts

```text
1 / 115200 = 8.6806 µs = 217.0139 clock cycles
```

You cannot have a fractional number of clock cycles, so the design truncates to
`CLKS_PER_BIT = 217`. That is a deliberate choice to round down rather than up;
either would work, and 217 is what the value rounds to.

The line rate that actually comes out is

```text
25 000 000 / 217 = 115 207.4 baud          (+0.0064 % error)
```

## Why 0.0064% is plenty

A UART receiver samples each bit at its centre, and tolerates a total
mismatch — its own oscillator versus the transmitter's, plus start-bit
detection error — of roughly **±2% to ±3%** before it starts reading the wrong
value. That budget is consumed by the *accumulated* drift across the frame, not
by the per-bit rate error alone.

Because the error is one-sided and constant, it accumulates linearly. Over the
10 bit times of a frame:

```text
per-bit rate error      0.0064 %
accumulated over 10 bits 0.064 % of one bit time
```

So at the very last sample point the receiver's idea of "centre of the stop
bit" is off by about six hundredths of one bit period — roughly **thirty to
fifty times smaller** than the budget, and that is the worst case in the whole
frame. Both ends would have to be badly mistuned for this link to fail.

Working it the other way round is also reassuring: the transmitter's bit period
is 8680 ns against an ideal 8680.6 ns, so the entire frame is 5.6 ns shorter
than a textbook frame. At 40 ns per clock cycle, that is not even a third of one
clock cycle over the whole byte.

## Changing the baud rate

Baud is a parameter of `hello_world`, and `CLKS_PER_BIT` is derived from it:

```verilog
parameter integer CLK_FREQ_HZ = 25_000_000,
parameter integer BAUD        = 115_200,
```

Change `BAUD` and the divider, the timing, and the synthesis all follow. For a
sanity check before committing, the error is `CLKS_PER_BIT * BAUD / CLK_FREQ_HZ
- 1`, and anything under about 1% is comfortable. 9600 gives 2604 clocks per bit
and an error of -0.0009%; 1 000 000 gives 25 and an error of 0%. Do not go so
high that `CLKS_PER_BIT` drops below about 4, or the counter stops having enough
resolution to matter.

One thing that does *not* change with `BAUD`: the receiver side. This design
only transmits, so there is no `uart_rx` to keep in sync. If you add one, give
it the same `CLKS_PER_BIT` and sample at mid-bit.
