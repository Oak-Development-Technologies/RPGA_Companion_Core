import board
import busio
import digitalio
import time

from rpga_companion import (
    ALGO_EMA,
    ALGO_STATS,
    ALGO_THRESHOLD,
    IRQ_SAMPLE_PROCESSED,
    IRQ_THRESHOLD,
    RPGACompanion,
)


spi = busio.SPI(board.SCK, MOSI=board.MOSI, MISO=board.MISO)
cs = digitalio.DigitalInOut(board.D10)
fpga = RPGACompanion(spi, cs)

print("core id:", hex(fpga.core_id))
print("version:", hex(fpga.version))

fpga.scratch = 0x12345678
print("scratch:", hex(fpga.scratch))

fpga.algorithm_mask = ALGO_EMA | ALGO_THRESHOLD | ALGO_STATS
fpga.irq_enable = IRQ_THRESHOLD | IRQ_SAMPLE_PROCESSED
fpga.configure_ema(alpha=0.25, value=0.0)
fpga.configure_thresholds(low=9.8, high=10.8)
fpga.reset_processing()

for sample in (10.0, 10.5, 9.75, 11.0, 10.25):
    fpga.fifo_write(sample)
    fpga.process_fifo_one()
    print(
        "sample:",
        sample,
        "ema:",
        fpga.ema_value,
        "threshold:",
        fpga.threshold_flags,
        "irq:",
        hex(fpga.irq_status),
    )
    fpga.clear_irqs()

print("stats:", fpga.stats)
print("pulse counts:", fpga.pulse_counts)
print("pulse periods:", fpga.pulse_periods)

fpga.set_rgb_pwm(period=256, red=32, green=128, blue=255)
print("pwm counter:", fpga.pwm_counter)
fpga.disable_rgb_pwm()

while True:
    for color in range(8):
        fpga.rgb = color
        print("gpio:", fpga.gpio_status, "counter:", fpga.counter)
        time.sleep(0.25)
