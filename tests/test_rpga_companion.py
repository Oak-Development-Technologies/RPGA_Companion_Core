import cocotb
from cocotb.triggers import Timer


CMD_READ = 0x00
CMD_WRITE = 0x80

REG_ID = 0x00
REG_VERSION = 0x01
REG_SCRATCH = 0x02
REG_CONTROL = 0x03
REG_GPIO_STATUS = 0x04
REG_IRQ_STATUS = 0x07
REG_IRQ_ENABLE = 0x08

REG_CPU_CONTROL = 0x10
REG_CPU_STATUS = 0x11
REG_CPU_STEPS = 0x14
REG_CPU_OUT = 0x15
REG_IMEM_ADDR = 0x20
REG_IMEM_DATA = 0x21
REG_DMEM_ADDR = 0x22
REG_DMEM_DATA = 0x23

REG_KALMAN_GAIN = 0x41
REG_KALMAN_PROCESS_NOISE = 0x42
REG_KALMAN_ESTIMATE = 0x43
REG_KALMAN_COVARIANCE = 0x44
REG_KALMAN_SAMPLE = 0x45
REG_KALMAN_RESIDUAL = 0x46
REG_KALMAN_COUNT = 0x47

IRQ_CPU = 0x01


def instr(opcode, rd=0, rs=0, rt=0, imm=0):
    return (
        ((opcode & 0xF) << 28)
        | ((rd & 0x7) << 25)
        | ((rs & 0x7) << 22)
        | ((rt & 0x7) << 19)
        | (imm & 0xFFFF)
    )


def ldi(rd, imm):
    return instr(0x1, rd=rd, imm=imm)


def load(rd, rs, offset=0):
    return instr(0x2, rd=rd, rs=rs, imm=offset)


def store(rd, rs, offset=0):
    return instr(0x3, rd=rd, rs=rs, imm=offset)


def add(rd, rs, rt):
    return instr(0x4, rd=rd, rs=rs, rt=rt)


def out(rd, irq=True):
    return instr(0xE, rd=rd, imm=1 if irq else 0)


def halt():
    return instr(0xF)


def to_q16(value):
    raw = int(value * 65536)
    return raw & 0xFFFFFFFF


def from_q16(raw):
    raw &= 0xFFFFFFFF
    if raw & 0x80000000:
        raw -= 1 << 32
    return raw / 65536


class SpiHost:
    def __init__(self, dut, half_period_ns=125):
        self.dut = dut
        self.half_period_ns = half_period_ns

    async def init(self):
        self.dut.SPI_SS.value = 1
        self.dut.SPI_SCK.value = 0
        self.dut.SPI_MOSI.value = 0
        self.dut.clk.value = 0
        self.dut.enable.value = 0
        self.dut.data.value = 0
        self.dut.P13.value = 0
        self.dut.P20.value = 0
        await Timer(1, units="us")

    async def transfer(self, command, register, value=0):
        tx = [command & 0xFF, register & 0xFF]
        tx.extend(int(value & 0xFFFFFFFF).to_bytes(4, "big"))
        rx_bits = []

        self.dut.SPI_SS.value = 0
        await Timer(self.half_period_ns, units="ns")

        for byte in tx:
            for bit_index in range(7, -1, -1):
                self.dut.SPI_MOSI.value = (byte >> bit_index) & 1
                await Timer(self.half_period_ns, units="ns")
                self.dut.SPI_SCK.value = 1
                await Timer(self.half_period_ns, units="ns")
                self.dut.SPI_SCK.value = 0
                rx_bits.append(int(self.dut.SPI_MISO.value))

        await Timer(self.half_period_ns, units="ns")
        self.dut.SPI_SS.value = 1
        self.dut.SPI_MOSI.value = 0
        await Timer(2, units="us")

        rx = 0
        for bit in rx_bits[16:48]:
            rx = (rx << 1) | bit
        return rx

    async def read_u32(self, register):
        return await self.transfer(CMD_READ, register)

    async def write_u32(self, register, value):
        await self.transfer(CMD_WRITE, register, value)


@cocotb.test()
async def spi_registers_scratch_and_gpio(dut):
    spi = SpiHost(dut)
    await spi.init()

    assert await spi.read_u32(REG_ID) == 0x52504741
    assert await spi.read_u32(REG_VERSION) == 0x000E0000

    await spi.write_u32(REG_SCRATCH, 0xA5A55A5A)
    assert await spi.read_u32(REG_SCRATCH) == 0xA5A55A5A

    dut.P13.value = 1
    dut.P20.value = 0
    await Timer(2, units="us")
    assert await spi.read_u32(REG_GPIO_STATUS) == 0x00000001

    await spi.write_u32(REG_CONTROL, 0x00000005)
    await Timer(1, units="us")
    assert int(dut.RGB.value) == 0x5


@cocotb.test()
async def cpu_loads_program_and_raises_irq(dut):
    spi = SpiHost(dut)
    await spi.init()

    program = (
        ldi(0, 0),
        load(1, 0, 0),
        load(2, 0, 1),
        add(3, 1, 2),
        store(3, 0, 2),
        out(3, irq=True),
        halt(),
    )

    await spi.write_u32(REG_CPU_CONTROL, 0x04)
    await spi.write_u32(REG_CPU_CONTROL, 0x00)
    await spi.write_u32(REG_IMEM_ADDR, 0)
    for word in program:
        await spi.write_u32(REG_IMEM_DATA, word)

    await spi.write_u32(REG_DMEM_ADDR, 0)
    await spi.write_u32(REG_DMEM_DATA, 123)
    await spi.write_u32(REG_DMEM_DATA, 456)

    await spi.write_u32(REG_IRQ_ENABLE, IRQ_CPU)
    await spi.write_u32(REG_CPU_CONTROL, 0x01)

    for _ in range(100):
        status = await spi.read_u32(REG_CPU_STATUS)
        if (status & 0x01) == 0 and (status & 0x02):
            break
    else:
        raise AssertionError("CPU did not halt")

    assert await spi.read_u32(REG_CPU_OUT) == 579
    assert await spi.read_u32(REG_CPU_STEPS) == len(program)
    assert await spi.read_u32(REG_IRQ_STATUS) & IRQ_CPU
    assert int(dut.data_out.value) == 1

    await spi.write_u32(REG_DMEM_ADDR, 2)
    await spi.read_u32(REG_DMEM_DATA)
    assert await spi.read_u32(REG_DMEM_DATA) == 579


@cocotb.test()
async def kalman_uses_q0_16_gain(dut):
    spi = SpiHost(dut)
    await spi.init()

    await spi.write_u32(REG_KALMAN_GAIN, 0x2000)
    await spi.write_u32(REG_KALMAN_PROCESS_NOISE, to_q16(0.25))
    await spi.write_u32(REG_KALMAN_ESTIMATE, to_q16(0.0))
    await spi.write_u32(REG_KALMAN_COVARIANCE, to_q16(1.0))
    await spi.write_u32(REG_KALMAN_SAMPLE, to_q16(8.0))

    assert await spi.read_u32(REG_KALMAN_GAIN) == 0x2000
    assert from_q16(await spi.read_u32(REG_KALMAN_PROCESS_NOISE)) == 0.25
    assert from_q16(await spi.read_u32(REG_KALMAN_RESIDUAL)) == 8.0
    assert from_q16(await spi.read_u32(REG_KALMAN_ESTIMATE)) == 1.0
    assert from_q16(await spi.read_u32(REG_KALMAN_COVARIANCE)) == 1.125
    assert await spi.read_u32(REG_KALMAN_COUNT) == 1
