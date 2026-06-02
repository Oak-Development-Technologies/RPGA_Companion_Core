# RPGA Companion Core

An open source 32-bit SPI companion core for the Lattice iCE5LP4K FPGA on the
RPGA Feather. The FPGA is intended to sit beside an RP2040 and expose a small,
predictable register interface that CircuitPython can use immediately after the
bitstream is loaded.

This core provides a 32-bit SPI register bank, RGB LED control, direct input
status for two FPGA pins, a scratch register, a counter driven by the
RP2040-to-FPGA `clk` sideband pin, and a set of starter accelerator peripherals
for long-running sample processing.

## Pin Map

The constraints in [common/io.pcf](common/io.pcf) are mirrored from the
`ice40_spi_io_expander/common/io.pcf` sister repo.

| Signal | iCE pin | Direction | Purpose |
| --- | ---: | --- | --- |
| `SPI_SS` | 16 | input | SPI chip select, active low |
| `SPI_SCK` | 15 | input | SPI clock |
| `SPI_MOSI` | 17 | input | SPI data from RP2040 |
| `SPI_MISO` | 14 | output | SPI data to RP2040 |
| `clk` | 2 | input | Optional sideband clock for the counter register |
| `enable` | 3 | input | Sideband input, currently folded into `data_out` |
| `data` | 4 | input | Sideband input, currently folded into `data_out` |
| `data_out` | 6 | output | IRQ output by default; set `CONTROL[8]` for legacy `scratch[0] ^ enable ^ data` |
| `RGB[2:0]` | 41, 40, 39 | output | RGB LED control bits |
| `P13` | 13 | input | Direct input status bit 0 |
| `P20` | 20 | input | Direct input status bit 1 |

## SPI Protocol

The SPI slave uses mode 0: CPOL = 0, CPHA = 0. Transfers are MSB-first and
always six bytes long:

```text
byte 0: command
byte 1: register address
byte 2: data[31:24]
byte 3: data[23:16]
byte 4: data[15:8]
byte 5: data[7:0]
```

Commands:

| Command | Meaning |
| ---: | --- |
| `0x00` | Read 32-bit register |
| `0x80` | Write 32-bit register |

For reads, transmit zeroes in bytes 2 through 5 and read the returned 32-bit
big-endian value from MISO during those same four bytes.

For writes, transmit the 32-bit big-endian value in bytes 2 through 5. Writes
only affect writable registers; writes to read-only or unknown registers are
ignored.

## Register Map

| Address | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `ID` | RO | Constant `0x52504741`, ASCII `RPGA` |
| `0x01` | `VERSION` | RO | Core version, currently `0x00040000` |
| `0x02` | `SCRATCH` | RW | General 32-bit test register |
| `0x03` | `CONTROL` | RW | Bits `[2:0]` drive RGB when PWM is off; bit 8 selects legacy `data_out` |
| `0x04` | `GPIO_STATUS` | RO | Bit 0 is `P13`, bit 1 is `P20` |
| `0x05` | `COUNTER` | RO | Increments on the `clk` sideband input |
| `0x06` | `SPI_COUNT` | RO | Counts completed 48-bit SPI transactions |
| `0x07` | `IRQ_STATUS` | RW1C | Interrupt flags; write `1` bits to clear |
| `0x08` | `IRQ_ENABLE` | RW | Interrupt enable mask driving `data_out` |
| `0x09` | `FIFO_STATUS` | RO | Count plus empty/full/overflow flags |
| `0x0A` | `FIFO_WRITE` | WO | Push one signed Q16.16 sample |
| `0x0B` | `FIFO_READ` | RO | Peek oldest FIFO sample |
| `0x0C` | `FIFO_CONTROL` | WO | Bit 0 pop, bit 1 clear, bit 2 process one sample |
| `0x10` | `ALGO_CONTROL` | RW | Bit 0 enables processing, bit 1 resets processing state, bit 8 processes one FIFO sample |
| `0x11` | `ALGO_STATUS` | RO | Low byte mirrors enabled algorithm slots |
| `0x12` | `ALGO_ENABLE` | RW | Bit 0 Kalman, bit 1 EMA, bit 2 threshold, bit 3 stats |
| `0x13` | `KALMAN_GAIN` | RW | Fixed gain as unsigned Q0.16, `0x8000` = 0.5 |
| `0x14` | `KALMAN_PROCESS_NOISE` | RW | Signed Q16.16 covariance increment per sample |
| `0x15` | `KALMAN_ESTIMATE` | RW | Signed Q16.16 current estimate |
| `0x16` | `KALMAN_COVARIANCE` | RW | Signed Q16.16 current covariance |
| `0x17` | `KALMAN_SAMPLE` | WO | Signed Q16.16 sample input; writing triggers processing |
| `0x18` | `KALMAN_RESIDUAL` | RO | Signed Q16.16 previous sample minus previous estimate |
| `0x19` | `KALMAN_COUNT` | RO | Number of accepted Kalman samples |
| `0x20` | `EMA_ALPHA` | RW | EMA alpha as unsigned Q0.16 |
| `0x21` | `EMA_VALUE` | RW | Signed Q16.16 current EMA value |
| `0x22` | `EMA_SAMPLE` | WO | Signed Q16.16 sample input; writing triggers processing |
| `0x23` | `EMA_COUNT` | RO | Number of accepted EMA samples |
| `0x30` | `THRESH_LOW` | RW | Signed Q16.16 low threshold |
| `0x31` | `THRESH_HIGH` | RW | Signed Q16.16 high threshold |
| `0x32` | `THRESH_FLAGS` | RW1C | Bit 0 below low, bit 1 above high |
| `0x33` | `THRESH_LOW_COUNT` | RO | Number of low threshold hits |
| `0x34` | `THRESH_HIGH_COUNT` | RO | Number of high threshold hits |
| `0x35` | `THRESH_LAST` | RO | Last threshold-tested sample |
| `0x40` | `STATS_CONTROL` | WO | Bit 0 resets processing stats |
| `0x41` | `STATS_COUNT` | RO | Number of stats samples |
| `0x42` | `STATS_MIN` | RO | Signed Q16.16 minimum |
| `0x43` | `STATS_MAX` | RO | Signed Q16.16 maximum |
| `0x44` | `STATS_SUM_LO` | RO | Low word of signed Q48.16 sum |
| `0x45` | `STATS_SUM_HI` | RO | High word of signed Q48.16 sum |
| `0x46` | `STATS_LAST` | RO | Last sample included in stats |
| `0x50` | `PULSE_P13_COUNT` | RO | Edge count on `P13` sampled by `clk` |
| `0x51` | `PULSE_P20_COUNT` | RO | Edge count on `P20` sampled by `clk` |
| `0x52` | `PULSE_P13_LAST` | RO | `COUNTER` value at last `P13` edge |
| `0x53` | `PULSE_P20_LAST` | RO | `COUNTER` value at last `P20` edge |
| `0x54` | `PULSE_CONTROL` | WO | Bit 0 resets pulse counters and periods |
| `0x55` | `PULSE_P13_PERIOD` | RO | Counter ticks between the last two `P13` edges |
| `0x56` | `PULSE_P20_PERIOD` | RO | Counter ticks between the last two `P20` edges |
| `0x60` | `PWM_CONTROL` | RW | Bit 0 enables RGB PWM |
| `0x61` | `PWM_PERIOD` | RW | PWM period in `clk` cycles |
| `0x62` | `PWM_DUTY_R` | RW | Red duty in `clk` cycles |
| `0x63` | `PWM_DUTY_G` | RW | Green duty in `clk` cycles |
| `0x64` | `PWM_DUTY_B` | RW | Blue duty in `clk` cycles |
| `0x65` | `PWM_COUNTER` | RO | Current PWM counter value |
| `0x70` | `CRC_CONTROL` | WO | Bit 0 resets CRC32 state |
| `0x71` | `CRC_VALUE` | RO | Current finalized CRC32 |
| `0x72` | `CRC_DATA` | WO | Fold one 32-bit word into CRC32 |
| `0x73` | `CRC_SEED` | RW | Finalized CRC seed value, default `0x00000000` |
| `0x80` | `MAILBOX_CONTROL` | RW | Bit 0 runs command, bit 1 clears done |
| `0x81` | `MAILBOX_STATUS` | RO | Bit 1 indicates done |
| `0x82` | `MAILBOX_COMMAND` | RW | Command ID |
| `0x83` | `MAILBOX_ARG0` | RW | Command argument 0 |
| `0x84` | `MAILBOX_ARG1` | RW | Command argument 1 |
| `0x85` | `MAILBOX_RESULT0` | RO | Command result 0 |
| `0x86` | `MAILBOX_RESULT1` | RO | Command result 1 |

## Accelerator Block

The accelerator registers are meant to be a small pattern for FPGA-side
long-term processing: configure state over SPI, stream samples into a FIFO or
write-only sample register, and poll compact state/results when the RP2040 needs
them.

The included scalar filter uses signed Q16.16 fixed-point values for samples,
estimate, covariance, process noise, and residual. `KALMAN_GAIN` is unsigned
Q0.16. On each `KALMAN_SAMPLE` write, the FPGA performs:

```text
residual = sample - estimate
estimate = estimate + gain * residual
covariance = (covariance + process_noise) -
             gain * (covariance + process_noise)
```

This behaves like a configurable fixed-gain 1D Kalman-style estimator. It avoids
a hardware divider, which keeps the design small on an iCE5LP4K, while still
offloading the repetitive fixed-point update loop from CircuitPython.

The included algorithm slots are:

| Bit | Slot | Purpose |
| ---: | --- | --- |
| 0 | Kalman | Fixed-gain scalar estimator |
| 1 | EMA | Exponential moving average |
| 2 | Threshold | Low/high window detector with counters |
| 3 | Stats | Count, min, max, and signed 64-bit sum |

IRQ bits are:

| Bit | Meaning |
| ---: | --- |
| 0 | FIFO not empty |
| 1 | FIFO overflow |
| 2 | Threshold hit |
| 3 | Mailbox command done |
| 4 | Sample processed |

Ideas 6 through 10 are implemented as small peripherals:

| Feature | Registers | Notes |
| --- | --- | --- |
| Stats accumulator | `0x40`-`0x46` | Tracks count, min, max, last, sum, and driver-side mean |
| Pulse timing | `0x50`-`0x56` | Counts edges and records last period in `clk` ticks |
| RGB PWM | `0x60`-`0x65` | Uses `clk` as the PWM timebase |
| CRC32 | `0x70`-`0x73` | IEEE reflected polynomial `0xEDB88320`, one word per write |
| Mailbox | `0x80`-`0x86` | Small command/argument/result interface |

Mailbox commands:

| Command | Result |
| ---: | --- |
| `0x00` | No-op |
| `0x01` | Process `ARG0` as one Q16.16 sample; returns sample and expected stats count |
| `0x02` | Return FIFO status and enabled algorithm mask |
| `0x03` | Preview CRC32 after folding `ARG0` |
| `0x04` | Return `ARG0 + ARG1` and `ARG0 ^ ARG1` |
| `0x05` | Return packed pulse edge counts and latest `P13` period |

## Build

Install and activate oss-cad-suite, then run:

```sh
make
```

The default target produces:

```text
build/rpga_companion_core.bin
```

The Makefile defaults to:

```make
DEVICE ?= up5k
PACKAGE ?= sg48
```

If your installed nextpnr target uses a different package or device spelling for
the exact FPGA on the RPGA Feather, override those at build time:

```sh
make DEVICE=up5k PACKAGE=sg48
```

Other useful targets:

```sh
make timing
make prog
make clean
```

`make prog` uses `iceprog` and assumes the FPGA programming path is wired for
that tool.

## CircuitPython Usage

Copy [circuitpython/rpga_companion.py](circuitpython/rpga_companion.py) to your
CircuitPython board, then instantiate the driver with your SPI bus and chip
select pin.

```python
import board
import busio
import digitalio

from rpga_companion import RPGACompanion

spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
cs = digitalio.DigitalInOut(board.D10)

fpga = RPGACompanion(spi, cs, baudrate=1_000_000)

print(hex(fpga.core_id))      # 0x52504741
print(hex(fpga.version))      # 0x00040000

fpga.scratch = 0x12345678
print(hex(fpga.scratch))

fpga.rgb = 0b101
print(fpga.gpio_status)
print(fpga.counter)

fpga.algorithm_mask = 0x0F
fpga.configure_kalman(gain=0.125, process_noise=0.01, estimate=0.0, covariance=1.0)
fpga.configure_ema(alpha=0.25, value=0.0)
fpga.configure_thresholds(low=9.8, high=10.8)
fpga.reset_kalman()

for sample in (10.0, 10.5, 9.75, 11.0, 10.25):
    fpga.fifo_write(sample)
    fpga.process_fifo_one()
    print(sample, fpga.kalman_estimate, fpga.ema_value, fpga.threshold_flags)

print(fpga.stats)
print(fpga.pulse_counts, fpga.pulse_periods)

fpga.set_rgb_pwm(period=256, red=32, green=128, blue=255)
fpga.crc_reset(seed=0)
print(hex(fpga.crc_update_u32(0x12345678)))
print(hex(fpga.crc_update_bytes(b"RPGA")))
print(fpga.mailbox_add_xor(0x1234, 0x00FF))
```

There is also a runnable example at
[circuitpython/example.py](circuitpython/example.py).

## Repository Layout

```text
rtl/rpga_companion_core.v       Verilog top-level and SPI register bank
common/io.pcf                   RPGA Feather iCE pin constraints
circuitpython/rpga_companion.py CircuitPython driver
circuitpython/example.py        Minimal CircuitPython example
Makefile                        oss-cad-suite build flow
```
