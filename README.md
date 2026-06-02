# RPGA Companion Core

An open source SPI-controlled companion processor for the Lattice iCE5LP4K FPGA
on the RPGA Feather. The FPGA sits beside an RP2040 and exposes a tiny
RAM-backed CPU that CircuitPython can load, run, and inspect.

This version is centered around memory instead of fixed-function filters:

- 256 x 32 program RAM
- 256 x 32 data RAM
- tiny 8-register CPU
- SPI loader/debug register map
- SPI-mapped DSP-backed fixed-gain Kalman accelerator
- CPU IRQ output on `data_out`
- pulse timing counters for `P13` and `P20`

The goal is to trade scarce logic cells for iCE40 block RAM. The RAMs live in
[rtl/ram.v](rtl/ram.v) and directly instantiate `SB_RAM40_4K` blocks instead of
relying on inference. The program RAM uses two blocks and the data RAM uses two
blocks. The Kalman gain multiply lives in [rtl/dsp_mac16.v](rtl/dsp_mac16.v)
and directly instantiates one `SB_MAC16` block.

## Pin Map

| Signal | iCE pin | Direction | Purpose |
| --- | ---: | --- | --- |
| `SPI_SS` | 16 | input | SPI chip select, active low |
| `SPI_SCK` | 15 | input | SPI clock |
| `SPI_MOSI` | 17 | input | SPI data from RP2040 |
| `SPI_MISO` | 14 | output | SPI data to RP2040 |
| `clk` | 2 | input | RPGA Feather `F2`; external sideband clock, currently unused by the internal CPU clock |
| `enable` | 3 | input | RPGA Feather `F3`; legacy sideband input |
| `data` | 4 | input | RPGA Feather `F4`; legacy sideband input |
| `data_out` | 6 | output | IRQ output by default |
| `RGB[2:0]` | 41, 40, 39 | output | Direct `CONTROL[2:0]` or `CPU_OUT[2:0]` |
| `P13` | 13 | input | Direct input and pulse counter |
| `P20` | 20 | input | Direct input and pulse counter |

## SPI Protocol

SPI mode 0, MSB-first, six bytes per transfer:

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

## Register Map

| Address | Name | Access | Description |
| ---: | --- | --- | --- |
| `0x00` | `ID` | RO | Constant `0x52504741`, ASCII `RPGA` |
| `0x01` | `VERSION` | RO | Core version, currently `0x000D0000` |
| `0x02` | `SCRATCH` | RW | General 32-bit test register |
| `0x03` | `CONTROL` | RW | Bits `[2:0]` direct RGB, bit 8 legacy `data_out`, bit 9 CPU RGB |
| `0x04` | `GPIO_STATUS` | RO | Bit 0 is `P13`, bit 1 is `P20` |
| `0x05` | `COUNTER` | RO | Increments on the divided internal core clock |
| `0x06` | `SPI_COUNT` | RO | Counts completed 48-bit SPI transactions |
| `0x07` | `IRQ_STATUS` | RO | Bit 0 CPU IRQ, bit 1 pulse IRQ |
| `0x08` | `IRQ_ENABLE` | RW | IRQ enable mask driving `data_out` |
| `0x10` | `CPU_CONTROL` | WO | Bit 0 run edge, bit 1 halt, bit 2 reset |
| `0x11` | `CPU_STATUS` | RO | Bit 0 running, bit 1 halted, bit 2 zero, bit 3 CPU IRQ |
| `0x12` | `CPU_PC` | RO | Current 8-bit program counter |
| `0x13` | `CPU_START_PC` | RW | Start address used by run/reset |
| `0x14` | `CPU_STEPS` | RO | Executed instruction count since reset |
| `0x15` | `CPU_OUT` | RO | CPU output register |
| `0x16` | `CPU_R0` | RO | Debug view of register 0 |
| `0x17` | `CPU_R1` | RO | Debug view of register 1 |
| `0x18` | `CPU_R2` | RO | Debug view of register 2 |
| `0x19` | `CPU_R3` | RO | Debug view of register 3 |
| `0x20` | `IMEM_ADDR` | RW | SPI program RAM address |
| `0x21` | `IMEM_DATA` | RW | Program RAM data, auto-increments address on write |
| `0x22` | `DMEM_ADDR` | RW | SPI data RAM address |
| `0x23` | `DMEM_DATA` | RW | Data RAM data, auto-increments address on write |
| `0x30` | `PULSE_P13_COUNT` | RO | Edge count on `P13` sampled by the core clock |
| `0x31` | `PULSE_P20_COUNT` | RO | Edge count on `P20` sampled by the core clock |
| `0x32` | `PULSE_P13_PERIOD` | RO | Counter ticks between the last two `P13` edges |
| `0x33` | `PULSE_P20_PERIOD` | RO | Counter ticks between the last two `P20` edges |
| `0x34` | `PULSE_CONTROL` | WO | Bit 0 resets pulse counters |
| `0x40` | `KALMAN_CONTROL` | RW | Bit 0 enable, bit 1 reset state |
| `0x41` | `KALMAN_GAIN` | RW | Unsigned Q0.16 gain; correction uses one `SB_MAC16` |
| `0x42` | `KALMAN_PROCESS_NOISE` | Stub, reads `0` |
| `0x43` | `KALMAN_ESTIMATE` | RW | Signed Q16.16 estimate, stored internally as Q8.8 |
| `0x44` | `KALMAN_COVARIANCE` | Stub, reads `0` |
| `0x45` | `KALMAN_SAMPLE` | WO | Signed Q16.16 sample; writing updates the filter |
| `0x46` | `KALMAN_RESIDUAL` | RO | Signed Q16.16 previous residual, stored internally as Q8.8 |
| `0x47` | `KALMAN_COUNT` | RO | Number of accepted samples |

Program/data RAM reads are synchronous. After changing `IMEM_ADDR` or
`DMEM_ADDR`, perform a data read to receive the selected word.

## CPU ISA

Instructions are 32-bit words:

```text
[31:28] opcode
[27:25] rd
[24:22] rs
[21:19] rt
[15:0]  immediate
```

| Opcode | Mnemonic | Behavior |
| ---: | --- | --- |
| `0x0` | `NOP` | No operation |
| `0x1` | `LDI rd, imm` | Sign-extend 16-bit immediate into `rd` |
| `0x2` | `LOAD rd, [rs + imm8]` | Load data RAM word |
| `0x3` | `STORE rd, [rs + imm8]` | Store `rd` into data RAM |
| `0x4` | `ADD rd, rs, rt` | Add |
| `0x5` | `SUB rd, rs, rt` | Subtract |
| `0x6` | `AND rd, rs, rt` | Bitwise AND |
| `0x7` | `OR rd, rs, rt` | Bitwise OR |
| `0x8` | `XOR rd, rs, rt` | Bitwise XOR |
| `0x9` | `SHR rd, rs, imm5` | Logical shift right |
| `0xA` | `SHL rd, rs, imm5` | Logical shift left |
| `0xB` | `JMP imm8` | Jump |
| `0xC` | `JZ imm8` | Jump if zero flag is set |
| `0xD` | `JNZ imm8` | Jump if zero flag is clear |
| `0xE` | `OUT rd, irq` | Copy `rd` to `CPU_OUT`, optionally raise IRQ |
| `0xF` | `HALT` | Stop CPU and raise IRQ |

The CPU uses a small fetch/read/execute pipeline over synchronous RAM. Loads take
an extra cycle.

## Clocking

The core instantiates the iCE40 high-frequency oscillator at 48 MHz, divides it
by 3 in a tiny clock divider, and routes the divided clock through `SB_GB`:

```verilog
SB_HFOSC #(
    .CLKHF_DIV("0b00")
) SB_HFOSC_inst (
    .CLKHFEN(1'b1),
    .CLKHFPU(1'b1),
    .CLKHF(hfosc_clk)
);

SB_GB core_clk_buffer (
    .USER_SIGNAL_TO_GLOBAL_BUFFER(core_clk_div),
    .GLOBAL_BUFFER_OUTPUT(internal_clk)
);
```

`internal_clk` is about 16 MHz and drives the CPU, RAM ports, system counter,
and pulse timing. SPI still uses `SPI_SCK` for the serial register interface.
Only the divider itself runs from the raw 48 MHz oscillator.

## Kalman Accelerator

The Kalman block is separate from the tiny CPU and is controlled directly over
SPI. To fit the U4K fabric budget, it is now a Kalman-like fixed-gain estimator:
it keeps estimate, residual, and sample count, but drops covariance tracking.
The SPI API uses signed Q16.16, but the internal estimator state is narrowed to
signed Q8.8 to save logic. This keeps roughly `-128.0` to `+127.996` of useful
range with 1/256 resolution:

```text
residual = sample - estimate
correction = (residual * gain_q0_16) >> 16
estimate = estimate + correction
```

For example, `gain=0.125` writes `0x2000` to `KALMAN_GAIN`. The correction
multiply is an explicit signed-residual by unsigned-gain `SB_MAC16` instance,
which should show up as DSP usage in the oss-cad-suite synthesis report.

## Build

Install and activate oss-cad-suite, then run:

```sh
make
```

The Makefile defaults to:

```make
DEVICE ?= u4k
PACKAGE ?= sg48
FREQ ?= 16
```

The synthesis command includes `synth_ice40 -dsp -abc2`. The place-and-route
and timing targets default to 16 MHz.

## Simulation

The repo includes a cocotb bench for the SPI register interface, CPU loader/run
path, data RAM, IRQ output, and DSP-backed Kalman update. The bench uses
behavioral simulation stubs for the iCE40 hard macros in [sim/ice40_cells_sim.v](sim/ice40_cells_sim.v).

Install cocotb and a supported Verilog simulator, such as Icarus Verilog, then
run:

```sh
make sim
```

The default cocotb simulator is `icarus`; override it with `SIM=...` if needed:

```sh
make sim SIM=verilator
```

## CircuitPython Usage

Copy [circuitpython/rpga_companion.py](circuitpython/rpga_companion.py), the
Oakdevtech IcePython library, and the built bitstream to your CircuitPython
board. The runnable example expects the bitstream at `top.bin`; copy or rename
`build/rpga_companion_core.bin` to that name on CIRCUITPY. The RPGA Feather
example programs the FPGA before opening the companion SPI register interface:

```python
import board
import busio
import digitalio
import oakdevtech_icepython
import time

from rpga_companion import RPGACompanion, add, halt, ldi, load, out, store

spi = busio.SPI(clock=board.F_SCK, MOSI=board.F_MOSI, MISO=board.F_MISO)
iceprog = oakdevtech_icepython.Oakdevtech_icepython(
    spi, board.F_CSN, board.F_RST, "top.bin"
)
iceprog.program_fpga()

sideband_clk = digitalio.DigitalInOut(board.F2)
sideband_enable = digitalio.DigitalInOut(board.F3)
sideband_data = digitalio.DigitalInOut(board.F4)
sideband_clk.switch_to_output(value=False)
sideband_enable.switch_to_output(value=False)
sideband_data.switch_to_output(value=False)

cs = digitalio.DigitalInOut(board.F_CSN)
fpga = RPGACompanion(spi, cs)

program = (
    ldi(0, 0),
    load(1, 0, 0),
    load(2, 0, 1),
    add(3, 1, 2),
    store(3, 0, 2),
    out(3, irq=True),
    halt(),
)

fpga.cpu_reset()
fpga.write_program(program)
fpga.write_data((123, 456), start=0)
fpga.cpu_run(0)

while fpga.cpu_status["running"]:
    pass

print(fpga.cpu_out)
print(fpga.read_data_word(2))

fpga.configure_kalman(gain=0.125, process_noise=0.01, estimate=0.0, covariance=1.0)
print(fpga.push_kalman_sample(10.0))
```

There is also a runnable example at
[circuitpython/example.py](circuitpython/example.py).
