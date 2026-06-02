# SPDX-License-Identifier: MIT
"""CircuitPython driver for the RPGA Companion Core tiny CPU."""

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

REG_CPU_CONTROL = const(0x10)
REG_CPU_STATUS = const(0x11)
REG_CPU_PC = const(0x12)
REG_CPU_START_PC = const(0x13)
REG_CPU_STEPS = const(0x14)
REG_CPU_OUT = const(0x15)
REG_CPU_R0 = const(0x16)
REG_CPU_R1 = const(0x17)
REG_CPU_R2 = const(0x18)
REG_CPU_R3 = const(0x19)

REG_IMEM_ADDR = const(0x20)
REG_IMEM_DATA = const(0x21)
REG_DMEM_ADDR = const(0x22)
REG_DMEM_DATA = const(0x23)

REG_PULSE_P13_COUNT = const(0x30)
REG_PULSE_P20_COUNT = const(0x31)
REG_PULSE_P13_PERIOD = const(0x32)
REG_PULSE_P20_PERIOD = const(0x33)
REG_PULSE_CONTROL = const(0x34)

REG_KALMAN_CONTROL = const(0x40)
REG_KALMAN_GAIN = const(0x41)
REG_KALMAN_PROCESS_NOISE = const(0x42)
REG_KALMAN_ESTIMATE = const(0x43)
REG_KALMAN_COVARIANCE = const(0x44)
REG_KALMAN_SAMPLE = const(0x45)
REG_KALMAN_RESIDUAL = const(0x46)
REG_KALMAN_COUNT = const(0x47)

IRQ_CPU = const(0x01)
IRQ_PULSE = const(0x02)
_Q16_SCALE = const(65536)


class RPGACompanion:
    """SPI loader/debugger for the RAM-backed RPGA tiny CPU."""

    def __init__(self, spi, cs, *, baudrate=1_000_000):
        self.spi = spi
        self.cs = cs
        self.baudrate = baudrate
        self.cs.switch_to_output(value=True)

    def read_u32(self, register):
        tx = bytearray((_CMD_READ, register & 0xFF, 0, 0, 0, 0))
        rx = bytearray(6)
        self._transfer(tx, rx)
        return int.from_bytes(rx[2:6], "big")

    def write_u32(self, register, value):
        value &= 0xFFFFFFFF
        tx = bytearray(6)
        tx[0] = _CMD_WRITE
        tx[1] = register & 0xFF
        tx[2:6] = value.to_bytes(4, "big")
        self._transfer(tx)

    def read_q16(self, register):
        return self._from_q16(self.read_u32(register))

    def write_q16(self, register, value):
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
    def use_cpu_rgb(self):
        return bool(self.read_u32(REG_CONTROL) & (1 << 9))

    @use_cpu_rgb.setter
    def use_cpu_rgb(self, value):
        current = self.read_u32(REG_CONTROL)
        if value:
            current |= 1 << 9
        else:
            current &= ~(1 << 9)
        self.write_u32(REG_CONTROL, current)

    @property
    def gpio_status(self):
        value = self.read_u32(REG_GPIO_STATUS)
        return {"P13": bool(value & 0x01), "P20": bool(value & 0x02)}

    @property
    def counter(self):
        return self.read_u32(REG_COUNTER)

    @property
    def irq_status(self):
        return self.read_u32(REG_IRQ_STATUS)

    @property
    def irq_enable(self):
        return self.read_u32(REG_IRQ_ENABLE)

    @irq_enable.setter
    def irq_enable(self, mask):
        self.write_u32(REG_IRQ_ENABLE, mask)

    def cpu_reset(self):
        self.write_u32(REG_CPU_CONTROL, 0x04)
        self.write_u32(REG_CPU_CONTROL, 0x00)

    def cpu_run(self, start_pc=0):
        self.write_u32(REG_CPU_CONTROL, 0x00)
        self.write_u32(REG_CPU_START_PC, start_pc)
        self.write_u32(REG_CPU_CONTROL, 0x01)

    def cpu_halt(self):
        self.write_u32(REG_CPU_CONTROL, 0x02)

    def cpu_idle(self):
        self.write_u32(REG_CPU_CONTROL, 0x00)

    @property
    def cpu_status(self):
        value = self.read_u32(REG_CPU_STATUS)
        return {
            "running": bool(value & 0x01),
            "halted": bool(value & 0x02),
            "zero": bool(value & 0x04),
            "irq": bool(value & 0x08),
        }

    @property
    def cpu_pc(self):
        return self.read_u32(REG_CPU_PC) & 0xFF

    @property
    def cpu_steps(self):
        return self.read_u32(REG_CPU_STEPS)

    @property
    def cpu_out(self):
        return self.read_u32(REG_CPU_OUT)

    @property
    def cpu_regs(self):
        return (
            self.read_u32(REG_CPU_R0),
            self.read_u32(REG_CPU_R1),
            self.read_u32(REG_CPU_R2),
            self.read_u32(REG_CPU_R3),
        )

    def write_program(self, words, start=0):
        self.write_u32(REG_IMEM_ADDR, start & 0xFF)
        for word in words:
            self.write_u32(REG_IMEM_DATA, word)

    def read_program_word(self, address):
        self.write_u32(REG_IMEM_ADDR, address & 0xFF)
        return self.read_u32(REG_IMEM_DATA)

    def write_data(self, words, start=0):
        self.write_u32(REG_DMEM_ADDR, start & 0xFF)
        for word in words:
            self.write_u32(REG_DMEM_DATA, word)

    def read_data_word(self, address):
        self.write_u32(REG_DMEM_ADDR, address & 0xFF)
        return self.read_u32(REG_DMEM_DATA)

    def reset_pulse_counters(self):
        self.write_u32(REG_PULSE_CONTROL, 0x01)

    @property
    def pulse_counts(self):
        return {"P13": self.read_u32(REG_PULSE_P13_COUNT), "P20": self.read_u32(REG_PULSE_P20_COUNT)}

    @property
    def pulse_periods(self):
        return {"P13": self.read_u32(REG_PULSE_P13_PERIOD), "P20": self.read_u32(REG_PULSE_P20_PERIOD)}

    def reset_kalman(self):
        control = self.read_u32(REG_KALMAN_CONTROL)
        self.write_u32(REG_KALMAN_CONTROL, control | 0x02)
        self.write_u32(REG_KALMAN_CONTROL, control & ~0x02)

    def configure_kalman(self, *, gain=None, process_noise=None, estimate=None, covariance=None):
        if gain is not None:
            if gain < 0:
                gain = 0
            if gain >= 1:
                gain = 0.9999847412109375
            self.write_u32(REG_KALMAN_GAIN, int(gain * _Q16_SCALE) & 0xFFFF)
        if process_noise is not None:
            self.write_q16(REG_KALMAN_PROCESS_NOISE, process_noise)
        if estimate is not None:
            self.write_q16(REG_KALMAN_ESTIMATE, estimate)
        if covariance is not None:
            self.write_q16(REG_KALMAN_COVARIANCE, covariance)

    def push_kalman_sample(self, sample):
        self.write_q16(REG_KALMAN_SAMPLE, sample)
        return self.kalman_estimate

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
    def kalman_count(self):
        return self.read_u32(REG_KALMAN_COUNT)

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


def instr(opcode, rd=0, rs=0, rt=0, imm=0):
    return (
        ((opcode & 0xF) << 28)
        | ((rd & 0x7) << 25)
        | ((rs & 0x7) << 22)
        | ((rt & 0x7) << 19)
        | (imm & 0xFFFF)
    )


def nop():
    return instr(0x0)


def ldi(rd, imm):
    return instr(0x1, rd=rd, imm=imm)


def load(rd, rs, offset=0):
    return instr(0x2, rd=rd, rs=rs, imm=offset)


def store(rd, rs, offset=0):
    return instr(0x3, rd=rd, rs=rs, imm=offset)


def add(rd, rs, rt):
    return instr(0x4, rd=rd, rs=rs, rt=rt)


def sub(rd, rs, rt):
    return instr(0x5, rd=rd, rs=rs, rt=rt)


def bitand(rd, rs, rt):
    return instr(0x6, rd=rd, rs=rs, rt=rt)


def bitor(rd, rs, rt):
    return instr(0x7, rd=rd, rs=rs, rt=rt)


def bitxor(rd, rs, rt):
    return instr(0x8, rd=rd, rs=rs, rt=rt)


def shr(rd, rs, amount):
    return instr(0x9, rd=rd, rs=rs, imm=amount)


def shl(rd, rs, amount):
    return instr(0xA, rd=rd, rs=rs, imm=amount)


def jmp(address):
    return instr(0xB, imm=address)


def jz(address):
    return instr(0xC, imm=address)


def jnz(address):
    return instr(0xD, imm=address)


def out(rd, irq=True):
    return instr(0xE, rd=rd, imm=1 if irq else 0)


def halt():
    return instr(0xF)
