# RPGA Companion Core

An open source 32-bit SPI companion core for the Lattice iCE5LP4K FPGA on the
RPGA Feather. The FPGA sits beside an RP2040 and exposes a compact register
interface for low-latency sample handling and small hardware-side chores.

This version is intentionally trimmed for the U4K-class resource budget. The
core keeps the highest value features per logic cell: SPI registers, IRQ flags,
a 128-word sample FIFO, shift-based EMA smoothing, threshold detection, simple
stats, pulse timing on `P13`/`P20`, and RGB PWM. The earlier Kalman, CRC32, and
mailbox blocks were removed because they cost too much fabric for the
iCE5LP4K.

## Pin Map

The constraints in [common/io.pcf](common/io.pcf) are mirrored from the
`ice40_spi_io_expander/common/io.pcf` sister repo.

| Signal | iCE pin | Direction | Purpose |
| --- | ---: | --- | --- |
| `SPI_SS` | 16 | input | SPI chip select, active low |
| `SPI_SCK` | 15 | input | SPI clock |
| `SPI_MOSI` | 17 | input | SPI data from RP2040 |
| `SPI_MISO` | 14 | output | SPI data to RP2040 |
| `clk` | 2 | input | Sideband clock for counters, pulse timing, and PWM |
| `enable` | 3 | input | Legacy sideband input |
| `data` | 4 | input | Legacy sideband input |
| `data_out` | 6 | output | IRQ output by default; set `CONTROL[8]` for legacy output |
| `RGB[2:0]` | 41, 40, 39 | output | RGB LED bits or PWM outputs |
| `P13` | 13 | input | Direct input and pulse counter |
| `P20` | 20 | input | Direct input and pulse counter |

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

Sample values use signed Q16.16 fixed-point format.

## Register Map

| Address | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `ID` | RO | Constant `0x52504741`, ASCII `RPGA` |
| `0x01` | `VERSION` | RO | Core version, currently `0x00060000` |
| `0x02` | `SCRATCH` | RW | General 32-bit test register |
| `0x03` | `CONTROL` | RW | Bits `[2:0]` drive RGB when PWM is off; bit 8 selects legacy `data_out` |
| `0x04` | `GPIO_STATUS` | RO | Bit 0 is `P13`, bit 1 is `P20` |
| `0x05` | `COUNTER` | RO | Increments on `clk` |
| `0x06` | `SPI_COUNT` | RO | Counts completed 48-bit SPI transactions |
| `0x07` | `IRQ_STATUS` | RW1C | IRQ flags; write `1` bits to clear |
| `0x08` | `IRQ_ENABLE` | RW | IRQ enable mask driving `data_out` |
| `0x09` | `FIFO_STATUS` | RO | Bits `[8:0]` count, bit 9 full, bit 10 empty, bit 11 overflow |
| `0x0A` | `FIFO_WRITE` | WO | Push one Q16.16 sample into the 128-word FIFO |
| `0x0B` | `FIFO_READ` | RO | Peek oldest FIFO sample |
| `0x0C` | `FIFO_CONTROL` | WO | Bit 0 pop, bit 1 clear, bit 2 process one sample |
| `0x10` | `ALGO_CONTROL` | RW | Bit 0 enables processing, bit 1 resets processing, bit 8 processes one FIFO sample |
| `0x11` | `ALGO_STATUS` | RO | Low bits mirror enabled algorithm slots |
| `0x12` | `ALGO_ENABLE` | RW | Bit 0 EMA, bit 1 threshold, bit 2 stats |
| `0x20` | `EMA_ALPHA` | RW | EMA shift amount, where update is `ema += (sample - ema) >> shift` |
| `0x21` | `EMA_VALUE` | RW | Signed Q16.16 current EMA value |
| `0x22` | `SAMPLE` | WO | Process one signed Q16.16 sample immediately |
| `0x23` | `SAMPLE_COUNT` | RO | Number of processed samples |
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
| `0x61` | `PWM_PERIOD` | RW | 16-bit PWM period in `clk` cycles |
| `0x62` | `PWM_DUTY_R` | RW | 16-bit red duty |
| `0x63` | `PWM_DUTY_G` | RW | 16-bit green duty |
| `0x64` | `PWM_DUTY_B` | RW | 16-bit blue duty |
| `0x65` | `PWM_COUNTER` | RO | Current 16-bit PWM counter value |

IRQ bits:

| Bit | Meaning |
| ---: | --- |
| 0 | FIFO not empty |
| 1 | FIFO overflow |
| 2 | Threshold hit |
| 3 | Sample processed |

## Build

Install and activate oss-cad-suite, then run:

```sh
make
```

The Makefile defaults to:

```make
DEVICE ?= u4k
PACKAGE ?= sg48
```

The Yosys command enables `synth_ice40 -dsp` so future narrow multiplies can map
to hard multiplier resources where the selected iCE40 target supports them.
This pruned core currently avoids general multipliers and uses a shift-based EMA
to reduce LUT pressure.

The FIFO storage lives in [rtl/ram.v](rtl/ram.v) as a synchronous 128x32 RAM
with a block-RAM inference attribute. In the Yosys/nextpnr reports, this should
show up as inferred iCE40 RAM, such as `ICESTORM_RAM`/`SB_RAM40_4K`, instead of
distributed registers or LUT memory.

## CircuitPython Usage

Copy [circuitpython/rpga_companion.py](circuitpython/rpga_companion.py) to your
CircuitPython board.

```python
import board
import busio
import digitalio

from rpga_companion import ALGO_EMA, ALGO_STATS, ALGO_THRESHOLD, RPGACompanion

spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
cs = digitalio.DigitalInOut(board.D10)
fpga = RPGACompanion(spi, cs)

print(hex(fpga.core_id))      # 0x52504741
print(hex(fpga.version))      # 0x00060000

fpga.algorithm_mask = ALGO_EMA | ALGO_THRESHOLD | ALGO_STATS
fpga.configure_ema(alpha=0.25, value=0.0)
fpga.configure_thresholds(low=9.8, high=10.8)
fpga.reset_processing()

for sample in (10.0, 10.5, 9.75, 11.0, 10.25):
    fpga.fifo_write(sample)
    fpga.process_fifo_one()
    print(sample, fpga.ema_value, fpga.threshold_flags)

print(fpga.stats)
print(fpga.pulse_counts, fpga.pulse_periods)
fpga.set_rgb_pwm(period=256, red=32, green=128, blue=255)
```

There is also a runnable example at
[circuitpython/example.py](circuitpython/example.py).
