import board
import busio
import digitalio
import time

from rpga_companion import (
    IRQ_CPU,
    RPGACompanion,
    add,
    halt,
    ldi,
    load,
    out,
    store,
)


spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
cs = digitalio.DigitalInOut(board.D10)
fpga = RPGACompanion(spi, cs)

print("core id:", hex(fpga.core_id))
print("version:", hex(fpga.version))

fpga.cpu_reset()
fpga.irq_enable = IRQ_CPU

# Program:
#   r0 = 0
#   r1 = data[0]
#   r2 = data[1]
#   r3 = r1 + r2
#   data[2] = r3
#   out = r3, raise CPU IRQ
#   halt
program = (
    ldi(0, 0),
    load(1, 0, 0),
    load(2, 0, 1),
    add(3, 1, 2),
    store(3, 0, 2),
    out(3, irq=True),
    halt(),
)

fpga.write_program(program)
fpga.write_data((123, 456), start=0)
fpga.cpu_run(0)

while fpga.cpu_status["running"]:
    time.sleep(0.01)

print("status:", fpga.cpu_status)
print("pc:", fpga.cpu_pc, "steps:", fpga.cpu_steps)
print("regs:", tuple(hex(value) for value in fpga.cpu_regs))
print("out:", fpga.cpu_out)
print("data[2]:", fpga.read_data_word(2))

fpga.use_cpu_rgb = True
print("pulse counts:", fpga.pulse_counts)
print("pulse periods:", fpga.pulse_periods)
