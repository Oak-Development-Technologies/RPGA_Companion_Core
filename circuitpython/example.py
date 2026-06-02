import board
import busio
import digitalio
import time

from rpga_companion import (
    ALGO_EMA,
    ALGO_KALMAN,
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

fpga.algorithm_mask = ALGO_KALMAN | ALGO_EMA | ALGO_THRESHOLD | ALGO_STATS
fpga.irq_enable = IRQ_THRESHOLD | IRQ_SAMPLE_PROCESSED
fpga.configure_kalman(gain=0.125, process_noise=0.01, estimate=0.0, covariance=1.0)
fpga.configure_ema(alpha=0.25, value=0.0)
fpga.configure_thresholds(low=9.8, high=10.8)
fpga.reset_kalman()

for sample in (10.0, 10.5, 9.75, 11.0, 10.25):
    fpga.fifo_write(sample)
    fpga.process_fifo_one()
    print(
        "sample:",
        sample,
        "kalman:",
        fpga.kalman_estimate,
        "ema:",
        fpga.ema_value,
        "threshold:",
        fpga.threshold_flags,
        "irq:",
        hex(fpga.irq_status),
    )
    fpga.clear_irqs()

print("stats:", fpga.stats)
fpga.crc_reset()
print("crc:", hex(fpga.crc_update_u32(0x12345678)))
print("mailbox:", fpga.mailbox_run(0x02))

while True:
    for color in range(8):
        fpga.rgb = color
        print("gpio:", fpga.gpio_status, "counter:", fpga.counter)
        time.sleep(0.25)
