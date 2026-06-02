# SPDX-License-Identifier: MIT
"""CircuitPython driver for the RPGA Companion Core SPI register bank."""

try:
    from micropython import const
except ImportError:
    const = lambda x: x

_CMD_READ = const(0x00)
_CMD_WRITE = const(0x80)

REG_ID = const(0x00)
REG_VERSION = const(0x01)
REG_SCRATCH = const(0x02)
REG_CONTROL = const(0x03)
REG_GPIO_STATUS = const(0x04)
REG_COUNTER = const(0x05)
REG_SPI_COUNT = const(0x06)
REG_IRQ_STATUS = const(0x07)
REG_IRQ_ENABLE = const(0x08)
REG_FIFO_STATUS = const(0x09)
REG_FIFO_WRITE = const(0x0A)
REG_FIFO_READ = const(0x0B)
REG_FIFO_CONTROL = const(0x0C)
REG_ALGO_CONTROL = const(0x10)
REG_ALGO_STATUS = const(0x11)
REG_ALGO_ENABLE = const(0x12)
REG_KALMAN_GAIN = const(0x13)
REG_KALMAN_PROCESS_NOISE = const(0x14)
REG_KALMAN_ESTIMATE = const(0x15)
REG_KALMAN_COVARIANCE = const(0x16)
REG_KALMAN_SAMPLE = const(0x17)
REG_KALMAN_RESIDUAL = const(0x18)
REG_KALMAN_COUNT = const(0x19)
REG_EMA_ALPHA = const(0x20)
REG_EMA_VALUE = const(0x21)
REG_EMA_SAMPLE = const(0x22)
REG_EMA_COUNT = const(0x23)
REG_THRESH_LOW = const(0x30)
REG_THRESH_HIGH = const(0x31)
REG_THRESH_FLAGS = const(0x32)
REG_THRESH_LOW_COUNT = const(0x33)
REG_THRESH_HIGH_COUNT = const(0x34)
REG_THRESH_LAST = const(0x35)
REG_STATS_CONTROL = const(0x40)
REG_STATS_COUNT = const(0x41)
REG_STATS_MIN = const(0x42)
REG_STATS_MAX = const(0x43)
REG_STATS_SUM_LO = const(0x44)
REG_STATS_SUM_HI = const(0x45)
REG_STATS_LAST = const(0x46)
REG_PULSE_P13_COUNT = const(0x50)
REG_PULSE_P20_COUNT = const(0x51)
REG_PULSE_P13_LAST = const(0x52)
REG_PULSE_P20_LAST = const(0x53)
REG_PULSE_CONTROL = const(0x54)
REG_PULSE_P13_PERIOD = const(0x55)
REG_PULSE_P20_PERIOD = const(0x56)
REG_PWM_CONTROL = const(0x60)
REG_PWM_PERIOD = const(0x61)
REG_PWM_DUTY_R = const(0x62)
REG_PWM_DUTY_G = const(0x63)
REG_PWM_DUTY_B = const(0x64)
REG_PWM_COUNTER = const(0x65)
REG_CRC_CONTROL = const(0x70)
REG_CRC_VALUE = const(0x71)
REG_CRC_DATA = const(0x72)
REG_CRC_SEED = const(0x73)
REG_MAILBOX_CONTROL = const(0x80)
REG_MAILBOX_STATUS = const(0x81)
REG_MAILBOX_COMMAND = const(0x82)
REG_MAILBOX_ARG0 = const(0x83)
REG_MAILBOX_ARG1 = const(0x84)
REG_MAILBOX_RESULT0 = const(0x85)
REG_MAILBOX_RESULT1 = const(0x86)

_Q16_SCALE = const(65536)
IRQ_FIFO_NOT_EMPTY = const(0x01)
IRQ_FIFO_OVERFLOW = const(0x02)
IRQ_THRESHOLD = const(0x04)
IRQ_MAILBOX_DONE = const(0x08)
IRQ_SAMPLE_PROCESSED = const(0x10)

ALGO_KALMAN = const(0x01)
ALGO_EMA = const(0x02)
ALGO_THRESHOLD = const(0x04)
ALGO_STATS = const(0x08)


class RPGACompanion:
    """Small SPI driver for the 32-bit RPGA companion register core."""

    def __init__(self, spi, cs, *, baudrate=1_000_000):
        self.spi = spi
        self.cs = cs
        self.baudrate = baudrate
        self.cs.switch_to_output(value=True)

    def read_u32(self, register):
        """Read a 32-bit big-endian register value."""
        tx = bytearray((_CMD_READ, register & 0xFF, 0x00, 0x00, 0x00, 0x00))
        rx = bytearray(6)
        self._transfer(tx, rx)
        return int.from_bytes(rx[2:6], "big")

    def write_u32(self, register, value):
        """Write a 32-bit big-endian register value."""
        value &= 0xFFFFFFFF
        tx = bytearray(6)
        tx[0] = _CMD_WRITE
        tx[1] = register & 0xFF
        tx[2:6] = value.to_bytes(4, "big")
        self._transfer(tx)

    def read_q16(self, register):
        """Read a signed Q16.16 fixed-point register as a float."""
        return self._from_q16(self.read_u32(register))

    def write_q16(self, register, value):
        """Write a float to a signed Q16.16 fixed-point register."""
        self.write_u32(register, self._to_q16(value))

    @property
    def core_id(self):
        return self.read_u32(REG_ID)

    @property
    def version(self):
        return self.read_u32(REG_VERSION)

    @property
    def scratch(self):
        return self.read_u32(REG_SCRATCH)

    @scratch.setter
    def scratch(self, value):
        self.write_u32(REG_SCRATCH, value)

    @property
    def rgb(self):
        return self.read_u32(REG_CONTROL) & 0x07

    @rgb.setter
    def rgb(self, value):
        current = self.read_u32(REG_CONTROL)
        self.write_u32(REG_CONTROL, (current & ~0x07) | (value & 0x07))

    @property
    def gpio_status(self):
        value = self.read_u32(REG_GPIO_STATUS)
        return {"P13": bool(value & 0x01), "P20": bool(value & 0x02)}

    @property
    def counter(self):
        return self.read_u32(REG_COUNTER)

    @property
    def spi_transaction_count(self):
        return self.read_u32(REG_SPI_COUNT)

    @property
    def irq_status(self):
        return self.read_u32(REG_IRQ_STATUS)

    @property
    def irq_enable(self):
        return self.read_u32(REG_IRQ_ENABLE)

    @irq_enable.setter
    def irq_enable(self, mask):
        self.write_u32(REG_IRQ_ENABLE, mask)

    def clear_irqs(self, mask=0xFFFFFFFF):
        self.write_u32(REG_IRQ_STATUS, mask)

    @property
    def fifo_status(self):
        value = self.read_u32(REG_FIFO_STATUS)
        return {
            "count": value & 0x1F,
            "full": bool(value & (1 << 8)),
            "empty": bool(value & (1 << 9)),
            "overflow": bool(value & (1 << 10)),
        }

    def fifo_write(self, value, *, process_now=False):
        self.write_q16(REG_FIFO_WRITE, value)
        if process_now:
            self.process_fifo_one()

    def fifo_peek(self):
        return self.read_q16(REG_FIFO_READ)

    def fifo_pop(self):
        self.write_u32(REG_FIFO_CONTROL, 0x01)

    def fifo_clear(self):
        self.write_u32(REG_FIFO_CONTROL, 0x02)

    def process_fifo_one(self):
        self.write_u32(REG_FIFO_CONTROL, 0x04)

    @property
    def algorithms_enabled(self):
        return bool(self.read_u32(REG_ALGO_CONTROL) & 0x01)

    @algorithms_enabled.setter
    def algorithms_enabled(self, value):
        control = self.read_u32(REG_ALGO_CONTROL)
        if value:
            control |= 0x01
        else:
            control &= ~0x01
        self.write_u32(REG_ALGO_CONTROL, control)

    @property
    def algorithm_mask(self):
        return self.read_u32(REG_ALGO_ENABLE)

    @algorithm_mask.setter
    def algorithm_mask(self, mask):
        self.write_u32(REG_ALGO_ENABLE, mask)

    def reset_kalman(self):
        """Reset FPGA-side processing state."""
        control = self.read_u32(REG_ALGO_CONTROL)
        self.write_u32(REG_ALGO_CONTROL, control | 0x02)
        self.write_u32(REG_ALGO_CONTROL, control & ~0x02)

    def reset_processing(self):
        """Reset all FPGA-side algorithm accumulators."""
        self.reset_kalman()

    def reset_stats(self):
        """Reset stats along with the processing accumulators."""
        self.write_u32(REG_STATS_CONTROL, 0x01)

    def reset_pulse_counters(self):
        self.write_u32(REG_PULSE_CONTROL, 0x01)

    def configure_kalman(
        self,
        *,
        gain=None,
        process_noise=None,
        estimate=None,
        covariance=None
    ):
        """Configure the scalar fixed-point Kalman-style estimator.

        Values are represented in hardware as signed Q16.16, except gain which
        is clamped to the range 0.0 through 0.999984.
        """
        if gain is not None:
            if gain < 0:
                gain = 0
            if gain >= 1:
                gain = 0.9999847412109375
            self.write_u32(REG_KALMAN_GAIN, int(gain * _Q16_SCALE) & 0xFFFFFFFF)
        if process_noise is not None:
            self.write_q16(REG_KALMAN_PROCESS_NOISE, process_noise)
        if estimate is not None:
            self.write_q16(REG_KALMAN_ESTIMATE, estimate)
        if covariance is not None:
            self.write_q16(REG_KALMAN_COVARIANCE, covariance)

    def push_kalman_sample(self, sample):
        """Push one sample into the FPGA filter and return the new estimate."""
        self.write_q16(REG_KALMAN_SAMPLE, sample)
        return self.kalman_estimate

    def configure_ema(self, *, alpha=None, value=None):
        if alpha is not None:
            if alpha < 0:
                alpha = 0
            if alpha >= 1:
                alpha = 0.9999847412109375
            self.write_u32(REG_EMA_ALPHA, int(alpha * _Q16_SCALE) & 0xFFFFFFFF)
        if value is not None:
            self.write_q16(REG_EMA_VALUE, value)

    def push_ema_sample(self, sample):
        self.write_q16(REG_EMA_SAMPLE, sample)
        return self.ema_value

    def configure_thresholds(self, low, high):
        self.write_q16(REG_THRESH_LOW, low)
        self.write_q16(REG_THRESH_HIGH, high)

    def clear_threshold_flags(self):
        self.write_u32(REG_THRESH_FLAGS, 0xFFFFFFFF)

    def set_rgb_pwm(self, *, period, red, green, blue, enable=True):
        self.write_u32(REG_PWM_PERIOD, max(1, int(period)))
        self.write_u32(REG_PWM_DUTY_R, int(red))
        self.write_u32(REG_PWM_DUTY_G, int(green))
        self.write_u32(REG_PWM_DUTY_B, int(blue))
        self.write_u32(REG_PWM_CONTROL, 1 if enable else 0)

    def disable_rgb_pwm(self):
        self.write_u32(REG_PWM_CONTROL, 0)

    def crc_reset(self, seed=None):
        if seed is not None:
            self.write_u32(REG_CRC_SEED, seed)
        self.write_u32(REG_CRC_CONTROL, 0x01)

    def crc_update_u32(self, value):
        self.write_u32(REG_CRC_DATA, value)
        return self.read_u32(REG_CRC_VALUE)

    def crc_update_bytes(self, data):
        word = 0
        count = 0
        for byte in data:
            word |= (byte & 0xFF) << (8 * count)
            count += 1
            if count == 4:
                self.write_u32(REG_CRC_DATA, word)
                word = 0
                count = 0
        if count:
            self.write_u32(REG_CRC_DATA, word)
        return self.read_u32(REG_CRC_VALUE)

    def mailbox_run(self, command, arg0=0, arg1=0):
        self.write_u32(REG_MAILBOX_COMMAND, command)
        self.write_u32(REG_MAILBOX_ARG0, arg0)
        self.write_u32(REG_MAILBOX_ARG1, arg1)
        self.write_u32(REG_MAILBOX_CONTROL, 0x01)
        return (self.read_u32(REG_MAILBOX_RESULT0), self.read_u32(REG_MAILBOX_RESULT1))

    def mailbox_process_sample(self, sample):
        result = self.mailbox_run(0x01, self._to_q16(sample), 0)
        return (self._from_q16(result[0]), result[1])

    def mailbox_status_summary(self):
        return self.mailbox_run(0x02)

    def mailbox_crc_preview(self, value):
        return self.mailbox_run(0x03, value, 0)[0]

    def mailbox_add_xor(self, arg0, arg1):
        return self.mailbox_run(0x04, arg0, arg1)

    def mailbox_pulse_summary(self):
        return self.mailbox_run(0x05)

    @property
    def kalman_gain(self):
        return self.read_u32(REG_KALMAN_GAIN) / _Q16_SCALE

    @property
    def kalman_estimate(self):
        return self.read_q16(REG_KALMAN_ESTIMATE)

    @property
    def kalman_covariance(self):
        return self.read_q16(REG_KALMAN_COVARIANCE)

    @property
    def kalman_residual(self):
        return self.read_q16(REG_KALMAN_RESIDUAL)

    @property
    def kalman_sample_count(self):
        return self.read_u32(REG_KALMAN_COUNT)

    @property
    def ema_value(self):
        return self.read_q16(REG_EMA_VALUE)

    @property
    def ema_sample_count(self):
        return self.read_u32(REG_EMA_COUNT)

    @property
    def threshold_flags(self):
        flags = self.read_u32(REG_THRESH_FLAGS)
        return {"low": bool(flags & 0x01), "high": bool(flags & 0x02)}

    @property
    def threshold_counts(self):
        return (self.read_u32(REG_THRESH_LOW_COUNT), self.read_u32(REG_THRESH_HIGH_COUNT))

    @property
    def threshold_last(self):
        return self.read_q16(REG_THRESH_LAST)

    @property
    def stats(self):
        count = self.read_u32(REG_STATS_COUNT)
        sum_raw = self.read_u32(REG_STATS_SUM_LO) | (self.read_u32(REG_STATS_SUM_HI) << 32)
        if sum_raw & (1 << 63):
            sum_raw -= 1 << 64
        total = sum_raw / _Q16_SCALE
        return {
            "count": count,
            "min": self.read_q16(REG_STATS_MIN),
            "max": self.read_q16(REG_STATS_MAX),
            "last": self.read_q16(REG_STATS_LAST),
            "sum": total,
            "mean": total / count if count else 0,
        }

    @property
    def pulse_counts(self):
        return {"P13": self.read_u32(REG_PULSE_P13_COUNT), "P20": self.read_u32(REG_PULSE_P20_COUNT)}

    @property
    def pulse_last_edges(self):
        return {"P13": self.read_u32(REG_PULSE_P13_LAST), "P20": self.read_u32(REG_PULSE_P20_LAST)}

    @property
    def pulse_periods(self):
        return {"P13": self.read_u32(REG_PULSE_P13_PERIOD), "P20": self.read_u32(REG_PULSE_P20_PERIOD)}

    @property
    def pwm_counter(self):
        return self.read_u32(REG_PWM_COUNTER)

    @property
    def crc_value(self):
        return self.read_u32(REG_CRC_VALUE)

    def _transfer(self, tx, rx=None):
        while not self.spi.try_lock():
            pass

        try:
            self.spi.configure(
                baudrate=self.baudrate,
                polarity=0,
                phase=0,
                bits=8,
            )
            self.cs.value = False
            if rx is None:
                self.spi.write(tx)
            else:
                self.spi.write_readinto(tx, rx)
            self.cs.value = True
        finally:
            self.cs.value = True
            self.spi.unlock()

    @staticmethod
    def _to_q16(value):
        raw = int(value * _Q16_SCALE)
        if raw < 0:
            raw = (1 << 32) + raw
        return raw & 0xFFFFFFFF

    @staticmethod
    def _from_q16(raw):
        raw &= 0xFFFFFFFF
        if raw & 0x80000000:
            raw -= 1 << 32
        return raw / _Q16_SCALE
