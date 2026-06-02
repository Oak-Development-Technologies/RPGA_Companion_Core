`default_nettype none

module rpga_companion_core (
    input  wire clk,
    input  wire enable,
    input  wire data,
    output wire data_out,

    input  wire SPI_SS,
    input  wire SPI_SCK,
    input  wire SPI_MOSI,
    output wire SPI_MISO,

    output wire [2:0] RGB,
    input  wire P13,
    input  wire P20
);
    wire [31:0] scratch;
    wire [31:0] control;
    wire irq_out;
    wire [31:0] cpu_out;

    reg [31:0] sys_counter = 32'd0;

    always @(posedge clk) begin
        sys_counter <= sys_counter + 32'd1;
    end

    assign RGB = control[9] ? cpu_out[2:0] : control[2:0];
    assign data_out = control[8] ? (scratch[0] ^ enable ^ data) : irq_out;

    rpga_spi_registers registers (
        .clk(clk),
        .ss(SPI_SS),
        .sck(SPI_SCK),
        .mosi(SPI_MOSI),
        .miso(SPI_MISO),
        .scratch(scratch),
        .control(control),
        .irq_out(irq_out),
        .cpu_out(cpu_out),
        .p13(P13),
        .p20(P20),
        .gpio_status({30'd0, P20, P13}),
        .sys_counter(sys_counter)
    );
endmodule

module rpga_spi_registers (
    input  wire clk,
    input  wire ss,
    input  wire sck,
    input  wire mosi,
    output wire miso,

    output reg  [31:0] scratch = 32'h00000000,
    output reg  [31:0] control = 32'h00000000,
    output wire irq_out,
    output wire [31:0] cpu_out,
    input  wire p13,
    input  wire p20,
    input  wire [31:0] gpio_status,
    input  wire [31:0] sys_counter
);
    localparam [7:0] CMD_READ = 8'h00;
    localparam [7:0] CMD_WRITE = 8'h80;

    localparam [7:0] REG_ID = 8'h00;
    localparam [7:0] REG_VERSION = 8'h01;
    localparam [7:0] REG_SCRATCH = 8'h02;
    localparam [7:0] REG_CONTROL = 8'h03;
    localparam [7:0] REG_GPIO_STATUS = 8'h04;
    localparam [7:0] REG_COUNTER = 8'h05;
    localparam [7:0] REG_SPI_COUNT = 8'h06;
    localparam [7:0] REG_IRQ_STATUS = 8'h07;
    localparam [7:0] REG_IRQ_ENABLE = 8'h08;

    localparam [7:0] REG_CPU_CONTROL = 8'h10;
    localparam [7:0] REG_CPU_STATUS = 8'h11;
    localparam [7:0] REG_CPU_PC = 8'h12;
    localparam [7:0] REG_CPU_START_PC = 8'h13;
    localparam [7:0] REG_CPU_STEPS = 8'h14;
    localparam [7:0] REG_CPU_OUT = 8'h15;
    localparam [7:0] REG_CPU_R0 = 8'h16;
    localparam [7:0] REG_CPU_R1 = 8'h17;
    localparam [7:0] REG_CPU_R2 = 8'h18;
    localparam [7:0] REG_CPU_R3 = 8'h19;

    localparam [7:0] REG_IMEM_ADDR = 8'h20;
    localparam [7:0] REG_IMEM_DATA = 8'h21;
    localparam [7:0] REG_DMEM_ADDR = 8'h22;
    localparam [7:0] REG_DMEM_DATA = 8'h23;

    localparam [7:0] REG_PULSE_P13_COUNT = 8'h30;
    localparam [7:0] REG_PULSE_P20_COUNT = 8'h31;
    localparam [7:0] REG_PULSE_P13_PERIOD = 8'h32;
    localparam [7:0] REG_PULSE_P20_PERIOD = 8'h33;
    localparam [7:0] REG_PULSE_CONTROL = 8'h34;

    localparam IRQ_CPU = 0;
    localparam IRQ_PULSE = 1;

    reg [5:0] bit_count = 6'd0;
    reg [7:0] command = 8'h00;
    reg [7:0] address = 8'h00;
    reg [31:0] write_shift = 32'h00000000;
    reg [31:0] read_shift = 32'h00000000;
    reg [31:0] read_value = 32'h00000000;
    reg [31:0] write_value = 32'h00000000;
    reg [31:0] transaction_count = 32'h00000000;
    reg miso_bit = 1'b0;

    reg [15:0] irq_enable = 16'h0000;
    reg cpu_irq_latched = 1'b0;
    reg pulse_irq_latched = 1'b0;
    wire [15:0] irq_status = {14'd0, pulse_irq_latched, cpu_irq_latched};

    reg [7:0] imem_addr_spi = 8'h00;
    reg [7:0] dmem_addr_spi = 8'h00;
    wire [31:0] imem_rdata_spi;
    wire [31:0] dmem_rdata_spi;
    wire [31:0] spi_write_value = {write_shift[30:0], mosi};
    wire imem_we_spi = !ss && (bit_count == 6'd47) && (command == CMD_WRITE) && (address == REG_IMEM_DATA);
    wire dmem_we_spi = !ss && (bit_count == 6'd47) && (command == CMD_WRITE) && (address == REG_DMEM_DATA);

    reg [2:0] cpu_control = 3'b000;
    reg [7:0] cpu_start_pc = 8'h00;
    wire cpu_running;
    wire cpu_halted;
    wire cpu_zero;
    wire cpu_irq;
    wire [7:0] cpu_pc;
    wire [31:0] cpu_steps;
    wire [31:0] cpu_r0;
    wire [31:0] cpu_r1;
    wire [31:0] cpu_r2;
    wire [31:0] cpu_r3;
    wire [7:0] cpu_imem_addr;
    wire [31:0] cpu_imem_rdata;
    wire [7:0] cpu_dmem_addr;
    wire cpu_dmem_we;
    wire [31:0] cpu_dmem_wdata;
    wire [31:0] cpu_dmem_rdata;

    reg p13_d = 1'b0;
    reg p20_d = 1'b0;
    reg [31:0] p13_edges = 32'h00000000;
    reg [31:0] p20_edges = 32'h00000000;
    reg [31:0] p13_last_edge = 32'h00000000;
    reg [31:0] p20_last_edge = 32'h00000000;
    reg [31:0] p13_period = 32'h00000000;
    reg [31:0] p20_period = 32'h00000000;
    reg pulse_reset = 1'b0;

    assign miso = ss ? 1'bz : miso_bit;
    assign irq_out = |(irq_status & irq_enable);

    rpga_dual_port_ram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32)
    ) program_ram (
        .a_clk(sck),
        .a_we(imem_we_spi),
        .a_addr(imem_addr_spi),
        .a_wdata(spi_write_value),
        .a_rdata(imem_rdata_spi),
        .b_clk(clk),
        .b_we(1'b0),
        .b_addr(cpu_imem_addr),
        .b_wdata(32'h00000000),
        .b_rdata(cpu_imem_rdata)
    );

    rpga_dual_port_ram #(
        .ADDR_WIDTH(8),
        .DATA_WIDTH(32)
    ) data_ram (
        .a_clk(sck),
        .a_we(dmem_we_spi),
        .a_addr(dmem_addr_spi),
        .a_wdata(spi_write_value),
        .a_rdata(dmem_rdata_spi),
        .b_clk(clk),
        .b_we(cpu_dmem_we),
        .b_addr(cpu_dmem_addr),
        .b_wdata(cpu_dmem_wdata),
        .b_rdata(cpu_dmem_rdata)
    );

    rpga_tiny_cpu cpu (
        .clk(clk),
        .reset(cpu_control[2]),
        .run(cpu_control[0]),
        .halt_req(cpu_control[1]),
        .start_pc(cpu_start_pc),
        .imem_addr(cpu_imem_addr),
        .imem_rdata(cpu_imem_rdata),
        .dmem_addr(cpu_dmem_addr),
        .dmem_we(cpu_dmem_we),
        .dmem_wdata(cpu_dmem_wdata),
        .dmem_rdata(cpu_dmem_rdata),
        .running(cpu_running),
        .halted(cpu_halted),
        .zero(cpu_zero),
        .irq(cpu_irq),
        .pc(cpu_pc),
        .steps(cpu_steps),
        .out_reg(cpu_out),
        .r0(cpu_r0),
        .r1(cpu_r1),
        .r2(cpu_r2),
        .r3(cpu_r3)
    );

    always @(posedge clk) begin
        p13_d <= p13;
        p20_d <= p20;

        if (cpu_control[2]) begin
            cpu_irq_latched <= 1'b0;
        end else if (cpu_irq) begin
            cpu_irq_latched <= 1'b1;
        end

        if (pulse_reset) begin
            p13_edges <= 32'h00000000;
            p20_edges <= 32'h00000000;
            p13_last_edge <= 32'h00000000;
            p20_last_edge <= 32'h00000000;
            p13_period <= 32'h00000000;
            p20_period <= 32'h00000000;
            pulse_irq_latched <= 1'b0;
        end else begin
            if (p13 != p13_d) begin
                p13_edges <= p13_edges + 32'd1;
                p13_period <= sys_counter - p13_last_edge;
                p13_last_edge <= sys_counter;
                pulse_irq_latched <= 1'b1;
            end

            if (p20 != p20_d) begin
                p20_edges <= p20_edges + 32'd1;
                p20_period <= sys_counter - p20_last_edge;
                p20_last_edge <= sys_counter;
                pulse_irq_latched <= 1'b1;
            end
        end
    end

    function [31:0] read_register;
        input [7:0] reg_address;
        begin
            case (reg_address)
                REG_ID: read_register = 32'h52504741;
                REG_VERSION: read_register = 32'h00070000;
                REG_SCRATCH: read_register = scratch;
                REG_CONTROL: read_register = control;
                REG_GPIO_STATUS: read_register = gpio_status;
                REG_COUNTER: read_register = sys_counter;
                REG_SPI_COUNT: read_register = transaction_count;
                REG_IRQ_STATUS: read_register = {16'd0, irq_status};
                REG_IRQ_ENABLE: read_register = {16'd0, irq_enable};
                REG_CPU_CONTROL: read_register = {29'd0, cpu_control};
                REG_CPU_STATUS: read_register = {28'd0, cpu_irq, cpu_zero, cpu_halted, cpu_running};
                REG_CPU_PC: read_register = {24'd0, cpu_pc};
                REG_CPU_START_PC: read_register = {24'd0, cpu_start_pc};
                REG_CPU_STEPS: read_register = cpu_steps;
                REG_CPU_OUT: read_register = cpu_out;
                REG_CPU_R0: read_register = cpu_r0;
                REG_CPU_R1: read_register = cpu_r1;
                REG_CPU_R2: read_register = cpu_r2;
                REG_CPU_R3: read_register = cpu_r3;
                REG_IMEM_ADDR: read_register = {24'd0, imem_addr_spi};
                REG_IMEM_DATA: read_register = imem_rdata_spi;
                REG_DMEM_ADDR: read_register = {24'd0, dmem_addr_spi};
                REG_DMEM_DATA: read_register = dmem_rdata_spi;
                REG_PULSE_P13_COUNT: read_register = p13_edges;
                REG_PULSE_P20_COUNT: read_register = p20_edges;
                REG_PULSE_P13_PERIOD: read_register = p13_period;
                REG_PULSE_P20_PERIOD: read_register = p20_period;
                REG_PULSE_CONTROL: read_register = 32'h00000000;
                default: read_register = 32'h00000000;
            endcase
        end
    endfunction

    always @(posedge sck or posedge ss) begin
        if (ss) begin
            bit_count <= 6'd0;
            write_shift <= 32'h00000000;
            pulse_reset <= 1'b0;
        end else begin
            if (bit_count < 6'd8) begin
                command <= {command[6:0], mosi};
            end else if (bit_count < 6'd16) begin
                address <= {address[6:0], mosi};
            end else if (bit_count < 6'd48) begin
                write_shift <= {write_shift[30:0], mosi};
            end

            if (bit_count == 6'd47) begin
                transaction_count <= transaction_count + 32'd1;
                if (command == CMD_WRITE) begin
                    write_value = spi_write_value;
                    case (address)
                        REG_SCRATCH: scratch <= write_value;
                        REG_CONTROL: control <= write_value;
                        REG_IRQ_ENABLE: irq_enable <= write_value[15:0];
                        REG_CPU_CONTROL: cpu_control <= write_value[2:0];
                        REG_CPU_START_PC: cpu_start_pc <= write_value[7:0];
                        REG_IMEM_ADDR: imem_addr_spi <= write_value[7:0];
                        REG_IMEM_DATA: imem_addr_spi <= imem_addr_spi + 8'd1;
                        REG_DMEM_ADDR: dmem_addr_spi <= write_value[7:0];
                        REG_DMEM_DATA: dmem_addr_spi <= dmem_addr_spi + 8'd1;
                        REG_PULSE_CONTROL: begin
                            if (write_value[0]) begin
                                pulse_reset <= 1'b1;
                            end
                        end
                        default: begin
                        end
                    endcase
                end
            end

            if (bit_count != 6'd63) begin
                bit_count <= bit_count + 6'd1;
            end
        end
    end

    always @(negedge sck or posedge ss) begin
        if (ss) begin
            miso_bit <= 1'b0;
            read_shift <= 32'h00000000;
        end else if (bit_count == 6'd16) begin
            read_value = read_register(address);
            read_shift <= read_value;
            miso_bit <= read_value[31];
        end else if (bit_count > 6'd16 && bit_count < 6'd49) begin
            miso_bit <= read_shift[30];
            read_shift <= {read_shift[30:0], 1'b0};
        end else begin
            miso_bit <= 1'b0;
        end
    end
endmodule

`default_nettype wire
