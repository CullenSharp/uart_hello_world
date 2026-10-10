# Bring-up

One micro-USB cable does all three jobs on the Go Board: power, programming and
serial. That is the on-board **FT2232H** — a dual-channel FTDI where channel A
speaks the MPSSE protocol `iceprog` uses to write the SPI flash, and channel B
is wired to the FPGA's UART pins (73 = RX, 74 = TX). You never connect a separate
programmer or a USB-serial adapter.

This guide has not been run against a physical board yet — it is written for the
first hardware session. Everything up to the `.bin` file is verified; see
[toolchain.md](toolchain.md) for what that covers.

## What you need

- A Nandland Go Board and a micro-USB cable
- The oss-cad-suite on your `PATH` (for `iceprog`), or any IceStorm install
- A terminal program: `picocom`, `minicom`, `screen`, or Tera Term / PuTTY

## 1. Build and flash

```sh
make          # -> build/hello_world.bin
make prog
```

A healthy `iceprog` run ends like this:

```text
init..
cdone: high
reset..
cdone: low
flash ID: 0x20 0x20 0x11 0x00
file size: 32220
erase 64kB sector at 0x000000..
programming..
reading..
VERIFY OK
cdone: high
Bye.
```

`VERIFY OK` and `cdone: high` at the end are the two things that matter. The
FPGA reloads from flash immediately, so the design starts running without a
power cycle. It also survives a power cycle, since the bitstream is in flash.

## 2. Find the serial device

Channel A (the programming side) and channel B (the UART) both enumerate, so
there are two candidate device nodes. The UART is the second one.

```sh
ls -l /dev/serial/by-id/
```

That listing is stable across reboots and ports, unlike raw `/dev/ttyUSB*`
numbers, which depend on enumeration order and shift when you move the cable to
a different physical port. Pick the entry whose port suffix is `port1`.

```sh
# something like:
usb-FTDI_FT2232H_...-port0    <- channel A, programming (leave alone)
usb-FTDI_FT2232H_...-port1    <- channel B, UART (this one)
```

If you are on macOS the nodes look like `/dev/tty.usbserial-...-1`; on Windows
it appears as a COM port in Device Manager.

## 3. Open a terminal

```sh
picocom -b 115200 /dev/ttyUSB1
```

or with `screen`:

```sh
screen /dev/ttyUSB1 115200
# leave with Ctrl-A then K, then Y
```

The settings must match the design exactly:

| Setting | Value |
| --- | --- |
| Baud rate | 115200 |
| Data bits | 8 |
| Parity | none |
| Stop bits | 1 |
| Flow control | none |
| Local echo | off |

Local echo should be off, and that is a feature: `screen` and `picocom` do not
echo by default, so **every character you see came from the FPGA**. If you see
nothing at all, the board is genuinely not transmitting — it is not your
terminal eating the output.

## 4. What you should see

```text
Hello, World!
Hello, World!
Hello, World!
```

One line every ~501 ms, repeating forever. The CR LF terminator means each
greeting lands on its own line even on a terminal that only honours the CR.

At the same time, **LED 1 blinks at roughly 1 Hz** — it toggles once per
completed message, and since messages arrive twice a second the full blink
period is about 1.003 s. That gives you a two-part signal:

- LED blinking but no serial text → the design is configured and running, and
  the problem is on the serial path (wrong device node, wrong baud, terminal
  settings).
- Serial text but no blink → the serial path works and you are almost certainly
  looking at the wrong LED or a board variant; the heartbeat is driven by the
  same sequencer that sends the bytes.
- Neither → the design is not running. Re-run `make prog` and check `VERIFY OK`.

## Troubleshooting

**`iceprog` says it cannot find an iCE FTDI device.**
The FTDI is there but the driver is wrong. On Linux `iceprog` needs to reach the
device through libftdi; if the `ftdi_sio` kernel driver has claimed it and
access fails, unbind it or blacklist it. On Windows the FTDI needs WinUSB
assigned with Zadig rather than the stock VCP driver — note that this also
disables the COM-port behaviour the terminal needs, so you trade one for the
other and will want the VCP driver back for step 3.

**`iceprog` reports `Found difference between flash and file!`**
You are flashing something that is not a packed bitstream. Run `make` first so
`icepack` has produced `build/hello_world.bin`, rather than pointing `iceprog`
at the `.asc` or `.json`.

**Terminal shows garbage instead of the greeting.**
Baud mismatch. Almost always the terminal is at a different rate than 115200,
or it has flow control set to something other than none. The FPGA's rate is
+0.0064% off nominal (see [uart.md](uart.md)), which no terminal will notice —
so if characters arrive mangled, the fault is the settings, not the timing.

**Terminal shows nothing at all.**
Work down the list: is the LED blinking? Did `make prog` end with `VERIFY OK`?
Are you on `port1` rather than `port0`? Is flow control off? Try `picocom`
rather than a GUI terminal, since it makes local echo and flow control easy to
rule out.

**Programming fails only while a terminal is open.**
Some combinations of drivers do not like the two channels being used at once.
Close the terminal, flash, then reopen it. On Linux this is usually unnecessary,
but it is the first thing to try if programming behaves erratically.

**`Permission denied` opening the serial port.**
Your user is not in the group that owns the device — `dialout` on most
distributions:

```sh
sudo usermod -aG dialout $USER
```

then log out and back in.

**Nothing is attached at all.**
Everything above the bitstream can be checked without hardware:

```sh
make test
```

which runs lint, the self-checking simulation (it prints the greeting) and the
formal proofs.
