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
    wire hfosc_clk;
    wire internal_clk;
    reg [1:0] clk_div_phase = 2'd0;
    reg core_clk_div = 1'b0;

    reg [31:0] sys_counter = 32'd0;

    SB_HFOSC #(
        .CLKHF_DIV("0b00")
    ) SB_HFOSC_inst (
        .CLKHFEN(1'b1),
        .CLKHFPU(1'b1),
        .CLKHF(hfosc_clk)
    );

    always @(posedge hfosc_clk) begin
        if (clk_div_phase == 2'd2) begin
            clk_div_phase <= 2'd0;
        end else begin
            clk_div_phase <= clk_div_phase + 2'd1;
        end

        core_clk_div <= (clk_div_phase == 2'd0);
    end

    SB_GB core_clk_buffer (
        .USER_SIGNAL_TO_GLOBAL_BUFFER(core_clk_div),
        .GLOBAL_BUFFER_OUTPUT(internal_clk)
    );

    always @(posedge internal_clk) begin
        sys_counter <= sys_counter + 32'd1;
    end

    assign RGB = control[9] ? cpu_out[2:0] : control[2:0];
    assign data_out = control[8] ? (scratch[0] ^ enable ^ data) : irq_out;

    rpga_spi_registers registers (
        .clk(internal_clk),
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

    localparam [7:0] REG_KALMAN_CONTROL = 8'h40;
    localparam [7:0] REG_KALMAN_GAIN = 8'h41;
    localparam [7:0] REG_KALMAN_PROCESS_NOISE = 8'h42;
    localparam [7:0] REG_KALMAN_ESTIMATE = 8'h43;
    localparam [7:0] REG_KALMAN_COVARIANCE = 8'h44;
    localparam [7:0] REG_KALMAN_SAMPLE = 8'h45;
    localparam [7:0] REG_KALMAN_RESIDUAL = 8'h46;
    localparam [7:0] REG_KALMAN_COUNT = 8'h47;

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
    reg imem_req_sck = 1'b0;
    reg dmem_req_sck = 1'b0;
    reg [7:0] imem_waddr_sck = 8'h00;
    reg [7:0] dmem_waddr_sck = 8'h00;
    reg [31:0] imem_wdata_sck = 32'h00000000;
    reg [31:0] dmem_wdata_sck = 32'h00000000;
    reg [2:0] imem_req_sync = 3'b000;
    reg [2:0] dmem_req_sync = 3'b000;
    reg [7:0] imem_waddr_clk = 8'h00;
    reg [7:0] dmem_waddr_clk = 8'h00;
    reg [31:0] imem_wdata_clk = 32'h00000000;
    reg [31:0] dmem_wdata_clk = 32'h00000000;
    wire imem_we_clk = imem_req_sync[2] ^ imem_req_sync[1];
    wire dmem_spi_we_clk = dmem_req_sync[2] ^ dmem_req_sync[1];

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
    wire dmem_we_clk = cpu_dmem_we | dmem_spi_we_clk;
    wire [7:0] dmem_waddr_clk_mux = cpu_dmem_we ? cpu_dmem_addr : dmem_waddr_clk;
    wire [31:0] dmem_wdata_clk_mux = cpu_dmem_we ? cpu_dmem_wdata : dmem_wdata_clk;

    reg p13_d = 1'b0;
    reg p20_d = 1'b0;
    reg [31:0] p13_edges = 32'h00000000;
    reg [31:0] p20_edges = 32'h00000000;
    reg [31:0] p13_last_edge = 32'h00000000;
    reg [31:0] p20_last_edge = 32'h00000000;
    reg [31:0] p13_period = 32'h00000000;
    reg [31:0] p20_period = 32'h00000000;
    reg pulse_reset = 1'b0;

    reg kalman_enable = 1'b1;
    reg [15:0] kalman_gain = 16'h2000;
    reg signed [15:0] kalman_estimate = 16'sh0000;
    reg signed [15:0] kalman_residual = 16'sh0000;
    reg [15:0] kalman_covariance = 16'h0100;
    reg [15:0] kalman_process_noise = 16'h0001;
    reg [15:0] kalman_count = 16'h0000;
    wire signed [15:0] kalman_next_sample;
    wire signed [15:0] kalman_next_delta;
    wire signed [31:0] kalman_gain_product;
    wire signed [15:0] kalman_correction;
    wire [31:0] kalman_covariance_product;
    wire [15:0] kalman_covariance_drop;
    wire [16:0] kalman_covariance_after_gain;
    wire [16:0] kalman_covariance_next;

    assign miso = ss ? 1'bz : miso_bit;
    assign irq_out = |(irq_status & irq_enable);
    assign kalman_next_sample = q16_to_q8(spi_write_value);
    assign kalman_next_delta = kalman_next_sample - kalman_estimate;
    assign kalman_correction = kalman_gain_product[31:16];
    assign kalman_covariance_drop = kalman_covariance_product[31:16];
    assign kalman_covariance_after_gain = (kalman_covariance > kalman_covariance_drop) ? (kalman_covariance - kalman_covariance_drop) : 17'd0;
    assign kalman_covariance_next = kalman_covariance_after_gain + kalman_process_noise;

    wire [7:0] imem_raddr = cpu_running ? cpu_imem_addr : imem_addr_spi;
    wire [7:0] dmem_raddr = cpu_running ? cpu_dmem_addr : dmem_addr_spi;

    assign imem_rdata_spi = cpu_running ? 32'h00000000 : cpu_imem_rdata;
    assign dmem_rdata_spi = cpu_running ? 32'h00000000 : cpu_dmem_rdata;

    rpga_ice40_ram32_256 program_ram (
        .wclk(clk),
        .we(imem_we_clk),
        .waddr(imem_waddr_clk),
        .wdata(imem_wdata_clk),
        .rclk(clk),
        .raddr(imem_raddr),
        .rdata(cpu_imem_rdata)
    );

    rpga_ice40_ram32_256 data_ram (
        .wclk(clk),
        .we(dmem_we_clk),
        .waddr(dmem_waddr_clk_mux),
        .wdata(dmem_wdata_clk_mux),
        .rclk(clk),
        .raddr(dmem_raddr),
        .rdata(cpu_dmem_rdata)
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

    rpga_ice40_dsp_mul16_signed_unsigned kalman_mul (
        .clk(sck),
        .a(kalman_next_delta),
        .b(kalman_gain),
        .y(kalman_gain_product)
    );

    rpga_ice40_dsp_mul16_unsigned_unsigned kalman_covariance_mul (
        .clk(sck),
        .a(kalman_covariance),
        .b(kalman_gain),
        .y(kalman_covariance_product)
    );

    always @(posedge clk) begin
        p13_d <= p13;
        p20_d <= p20;
        imem_req_sync <= {imem_req_sync[1:0], imem_req_sck};
        dmem_req_sync <= {dmem_req_sync[1:0], dmem_req_sck};
        imem_waddr_clk <= imem_waddr_sck;
        dmem_waddr_clk <= dmem_waddr_sck;
        imem_wdata_clk <= imem_wdata_sck;
        dmem_wdata_clk <= dmem_wdata_sck;

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
                REG_VERSION: read_register = 32'h000E0000;
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
                REG_KALMAN_CONTROL: read_register = {31'd0, kalman_enable};
                REG_KALMAN_GAIN: read_register = {16'd0, kalman_gain};
                REG_KALMAN_PROCESS_NOISE: read_register = uq8_to_q16(kalman_process_noise);
                REG_KALMAN_ESTIMATE: read_register = q8_to_q16(kalman_estimate);
                REG_KALMAN_COVARIANCE: read_register = uq8_to_q16(kalman_covariance);
                REG_KALMAN_SAMPLE: read_register = 32'h00000000;
                REG_KALMAN_RESIDUAL: read_register = q8_to_q16(kalman_residual);
                REG_KALMAN_COUNT: read_register = {16'd0, kalman_count};
                default: read_register = 32'h00000000;
            endcase
        end
    endfunction

    function [31:0] q8_to_q16;
        input signed [15:0] value;
        begin
            q8_to_q16 = {{8{value[15]}}, value, 8'd0};
        end
    endfunction

    function signed [15:0] q16_to_q8;
        input [31:0] value;
        begin
            q16_to_q8 = value[23:8];
        end
    endfunction

    function [31:0] uq8_to_q16;
        input [15:0] value;
        begin
            uq8_to_q16 = {8'd0, value, 8'd0};
        end
    endfunction

    function [15:0] q16_to_uq8;
        input [31:0] value;
        begin
            q16_to_uq8 = value[31] ? 16'h0000 : (|value[30:24] ? 16'hffff : value[23:8]);
        end
    endfunction

    task reset_kalman;
        begin
            kalman_estimate <= 16'sh0000;
            kalman_residual <= 16'sh0000;
            kalman_covariance <= 16'h0100;
            kalman_count <= 16'h0000;
        end
    endtask

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
                        REG_IMEM_DATA: begin
                            imem_waddr_sck <= imem_addr_spi;
                            imem_wdata_sck <= write_value;
                            imem_req_sck <= !imem_req_sck;
                            imem_addr_spi <= imem_addr_spi + 8'd1;
                        end
                        REG_DMEM_ADDR: dmem_addr_spi <= write_value[7:0];
                        REG_DMEM_DATA: begin
                            dmem_waddr_sck <= dmem_addr_spi;
                            dmem_wdata_sck <= write_value;
                            dmem_req_sck <= !dmem_req_sck;
                            dmem_addr_spi <= dmem_addr_spi + 8'd1;
                        end
                        REG_PULSE_CONTROL: begin
                            if (write_value[0]) begin
                                pulse_reset <= 1'b1;
                            end
                        end
                        REG_KALMAN_CONTROL: begin
                            kalman_enable <= write_value[0];
                            if (write_value[1]) begin
                                reset_kalman;
                            end
                        end
                        REG_KALMAN_GAIN: kalman_gain <= write_value[15:0];
                        REG_KALMAN_PROCESS_NOISE: kalman_process_noise <= q16_to_uq8(write_value);
                        REG_KALMAN_ESTIMATE: kalman_estimate <= q16_to_q8(write_value);
                        REG_KALMAN_COVARIANCE: kalman_covariance <= q16_to_uq8(write_value);
                        REG_KALMAN_SAMPLE: begin
                            if (kalman_enable) begin
                                kalman_residual <= kalman_next_delta;
                                kalman_estimate <= kalman_estimate + kalman_correction;
                                kalman_covariance <= kalman_covariance_next[16] ? 16'hffff : kalman_covariance_next[15:0];
                                kalman_count <= kalman_count + 16'd1;
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
