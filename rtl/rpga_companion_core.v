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
    wire [2:0] rgb_out;

    reg [31:0] sys_counter = 32'd0;

    always @(posedge clk) begin
        sys_counter <= sys_counter + 32'd1;
    end

    assign RGB = rgb_out;
    assign data_out = control[8] ? (scratch[0] ^ enable ^ data) : irq_out;

    rpga_spi_registers registers (
        .clk(clk),
        .ss(SPI_SS),
        .sck(SPI_SCK),
        .mosi(SPI_MOSI),
        .miso(SPI_MISO),
        .scratch(scratch),
        .control(control),
        .rgb_out(rgb_out),
        .irq_out(irq_out),
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
    output wire [2:0] rgb_out,
    output wire irq_out,
    input  wire p13,
    input  wire p20,
    input  wire [31:0] gpio_status,
    input  wire [31:0] sys_counter
);
    localparam [7:0] CMD_READ  = 8'h00;
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
    localparam [7:0] REG_FIFO_STATUS = 8'h09;
    localparam [7:0] REG_FIFO_WRITE = 8'h0A;
    localparam [7:0] REG_FIFO_READ = 8'h0B;
    localparam [7:0] REG_FIFO_CONTROL = 8'h0C;

    localparam [7:0] REG_ALGO_CONTROL = 8'h10;
    localparam [7:0] REG_ALGO_STATUS = 8'h11;
    localparam [7:0] REG_ALGO_ENABLE = 8'h12;
    localparam [7:0] REG_KALMAN_GAIN = 8'h13;
    localparam [7:0] REG_KALMAN_PROCESS_NOISE = 8'h14;
    localparam [7:0] REG_KALMAN_ESTIMATE = 8'h15;
    localparam [7:0] REG_KALMAN_COVARIANCE = 8'h16;
    localparam [7:0] REG_KALMAN_SAMPLE = 8'h17;
    localparam [7:0] REG_KALMAN_RESIDUAL = 8'h18;
    localparam [7:0] REG_KALMAN_COUNT = 8'h19;

    localparam [7:0] REG_EMA_ALPHA = 8'h20;
    localparam [7:0] REG_EMA_VALUE = 8'h21;
    localparam [7:0] REG_EMA_SAMPLE = 8'h22;
    localparam [7:0] REG_EMA_COUNT = 8'h23;

    localparam [7:0] REG_THRESH_LOW = 8'h30;
    localparam [7:0] REG_THRESH_HIGH = 8'h31;
    localparam [7:0] REG_THRESH_FLAGS = 8'h32;
    localparam [7:0] REG_THRESH_LOW_COUNT = 8'h33;
    localparam [7:0] REG_THRESH_HIGH_COUNT = 8'h34;
    localparam [7:0] REG_THRESH_LAST = 8'h35;

    localparam [7:0] REG_STATS_CONTROL = 8'h40;
    localparam [7:0] REG_STATS_COUNT = 8'h41;
    localparam [7:0] REG_STATS_MIN = 8'h42;
    localparam [7:0] REG_STATS_MAX = 8'h43;
    localparam [7:0] REG_STATS_SUM_LO = 8'h44;
    localparam [7:0] REG_STATS_SUM_HI = 8'h45;
    localparam [7:0] REG_STATS_LAST = 8'h46;

    localparam [7:0] REG_PULSE_P13_COUNT = 8'h50;
    localparam [7:0] REG_PULSE_P20_COUNT = 8'h51;
    localparam [7:0] REG_PULSE_P13_LAST = 8'h52;
    localparam [7:0] REG_PULSE_P20_LAST = 8'h53;
    localparam [7:0] REG_PULSE_CONTROL = 8'h54;
    localparam [7:0] REG_PULSE_P13_PERIOD = 8'h55;
    localparam [7:0] REG_PULSE_P20_PERIOD = 8'h56;

    localparam [7:0] REG_PWM_CONTROL = 8'h60;
    localparam [7:0] REG_PWM_PERIOD = 8'h61;
    localparam [7:0] REG_PWM_DUTY_R = 8'h62;
    localparam [7:0] REG_PWM_DUTY_G = 8'h63;
    localparam [7:0] REG_PWM_DUTY_B = 8'h64;
    localparam [7:0] REG_PWM_COUNTER = 8'h65;

    localparam [7:0] REG_CRC_CONTROL = 8'h70;
    localparam [7:0] REG_CRC_VALUE = 8'h71;
    localparam [7:0] REG_CRC_DATA = 8'h72;
    localparam [7:0] REG_CRC_SEED = 8'h73;

    localparam [7:0] REG_MAILBOX_CONTROL = 8'h80;
    localparam [7:0] REG_MAILBOX_STATUS = 8'h81;
    localparam [7:0] REG_MAILBOX_COMMAND = 8'h82;
    localparam [7:0] REG_MAILBOX_ARG0 = 8'h83;
    localparam [7:0] REG_MAILBOX_ARG1 = 8'h84;
    localparam [7:0] REG_MAILBOX_RESULT0 = 8'h85;
    localparam [7:0] REG_MAILBOX_RESULT1 = 8'h86;

    localparam [4:0] IRQ_FIFO_NOT_EMPTY = 5'd0;
    localparam [4:0] IRQ_FIFO_OVERFLOW = 5'd1;
    localparam [4:0] IRQ_THRESHOLD = 5'd2;
    localparam [4:0] IRQ_MAILBOX_DONE = 5'd3;
    localparam [4:0] IRQ_SAMPLE_PROCESSED = 5'd4;

    reg [5:0] bit_count = 6'd0;
    reg [7:0] command = 8'h00;
    reg [7:0] address = 8'h00;
    reg [31:0] write_shift = 32'h00000000;
    reg [31:0] read_shift = 32'h00000000;
    reg [31:0] read_value = 32'h00000000;
    reg [31:0] write_value = 32'h00000000;
    reg [31:0] transaction_count = 32'h00000000;
    reg miso_bit = 1'b0;

    reg [31:0] irq_status = 32'h00000000;
    reg [31:0] irq_enable = 32'h00000000;

    reg [31:0] fifo [0:15];
    reg [3:0] fifo_rd = 4'd0;
    reg [3:0] fifo_wr = 4'd0;
    reg [4:0] fifo_count = 5'd0;

    reg [31:0] algo_control = 32'h00000001;
    reg [31:0] algo_enable = 32'h0000000F;
    reg [31:0] kalman_gain = 32'h00008000;
    reg signed [31:0] kalman_process_noise = 32'sh00000100;
    reg signed [31:0] kalman_estimate = 32'sh00000000;
    reg signed [31:0] kalman_covariance = 32'sh00010000;
    reg signed [31:0] kalman_residual = 32'sh00000000;
    reg [31:0] kalman_count = 32'h00000000;

    reg [31:0] ema_alpha = 32'h00002000;
    reg signed [31:0] ema_value = 32'sh00000000;
    reg [31:0] ema_count = 32'h00000000;

    reg signed [31:0] threshold_low = -32'sd65536;
    reg signed [31:0] threshold_high = 32'sd65536;
    reg [31:0] threshold_flags = 32'h00000000;
    reg [31:0] threshold_low_count = 32'h00000000;
    reg [31:0] threshold_high_count = 32'h00000000;
    reg signed [31:0] threshold_last = 32'sh00000000;

    reg [31:0] stats_count = 32'h00000000;
    reg signed [31:0] stats_min = 32'sh7FFFFFFF;
    reg signed [31:0] stats_max = 32'sh80000000;
    reg signed [63:0] stats_sum = 64'sh0000000000000000;
    reg signed [31:0] stats_last = 32'sh00000000;

    reg p13_d = 1'b0;
    reg p20_d = 1'b0;
    reg [31:0] p13_edges = 32'h00000000;
    reg [31:0] p20_edges = 32'h00000000;
    reg [31:0] p13_last_edge = 32'h00000000;
    reg [31:0] p20_last_edge = 32'h00000000;
    reg [31:0] p13_period = 32'h00000000;
    reg [31:0] p20_period = 32'h00000000;
    reg pulse_reset = 1'b0;

    reg [31:0] pwm_control = 32'h00000000;
    reg [31:0] pwm_period = 32'h00000100;
    reg [31:0] pwm_duty_r = 32'h00000080;
    reg [31:0] pwm_duty_g = 32'h00000080;
    reg [31:0] pwm_duty_b = 32'h00000080;
    reg [31:0] pwm_counter = 32'h00000000;

    reg [31:0] crc_value = 32'hFFFFFFFF;
    reg [31:0] crc_seed = 32'hFFFFFFFF;

    reg [31:0] mailbox_control = 32'h00000000;
    reg [31:0] mailbox_status = 32'h00000000;
    reg [31:0] mailbox_command = 32'h00000000;
    reg [31:0] mailbox_arg0 = 32'h00000000;
    reg [31:0] mailbox_arg1 = 32'h00000000;
    reg [31:0] mailbox_result0 = 32'h00000000;
    reg [31:0] mailbox_result1 = 32'h00000000;

    reg signed [31:0] sample_value = 32'sh00000000;
    reg signed [31:0] residual_next = 32'sh00000000;
    reg signed [31:0] estimate_next = 32'sh00000000;
    reg signed [31:0] covariance_predicted = 32'sh00000000;
    reg signed [63:0] estimate_correction = 64'sh0000000000000000;
    reg signed [63:0] covariance_correction = 64'sh0000000000000000;
    reg signed [63:0] ema_correction = 64'sh0000000000000000;
    reg signed [63:0] sample_extended = 64'sh0000000000000000;

    assign miso = ss ? 1'bz : miso_bit;
    assign irq_out = |(irq_status & irq_enable);
    assign rgb_out = pwm_control[0] ? {
        (pwm_counter < pwm_duty_r),
        (pwm_counter < pwm_duty_g),
        (pwm_counter < pwm_duty_b)
    } : control[2:0];

    always @(posedge clk) begin
        p13_d <= p13;
        p20_d <= p20;

        if (pulse_reset) begin
            p13_edges <= 32'h00000000;
            p20_edges <= 32'h00000000;
            p13_last_edge <= 32'h00000000;
            p20_last_edge <= 32'h00000000;
            p13_period <= 32'h00000000;
            p20_period <= 32'h00000000;
        end else begin
            if (p13 != p13_d) begin
                p13_edges <= p13_edges + 32'd1;
                p13_period <= sys_counter - p13_last_edge;
                p13_last_edge <= sys_counter;
            end

            if (p20 != p20_d) begin
                p20_edges <= p20_edges + 32'd1;
                p20_period <= sys_counter - p20_last_edge;
                p20_last_edge <= sys_counter;
            end
        end

        if (pwm_control[0]) begin
            if (pwm_counter >= pwm_period - 32'd1) begin
                pwm_counter <= 32'd0;
            end else begin
                pwm_counter <= pwm_counter + 32'd1;
            end
        end else begin
            pwm_counter <= 32'd0;
        end
    end

    function [31:0] fifo_status_word;
        begin
            fifo_status_word = {21'd0, irq_status[IRQ_FIFO_OVERFLOW], (fifo_count == 5'd0), (fifo_count == 5'd16), 3'd0, fifo_count};
        end
    endfunction

    function [31:0] next_crc32;
        input [31:0] crc_in;
        input [31:0] data_in;
        integer i;
        reg [31:0] crc;
        begin
            crc = crc_in ^ data_in;
            for (i = 0; i < 32; i = i + 1) begin
                if (crc[0]) begin
                    crc = (crc >> 1) ^ 32'hEDB88320;
                end else begin
                    crc = crc >> 1;
                end
            end
            next_crc32 = crc;
        end
    endfunction

    function [31:0] read_register;
        input [7:0] reg_address;
        begin
            case (reg_address)
                REG_ID: read_register = 32'h52504741; // "RPGA"
                REG_VERSION: read_register = 32'h00040000;
                REG_SCRATCH: read_register = scratch;
                REG_CONTROL: read_register = control;
                REG_GPIO_STATUS: read_register = gpio_status;
                REG_COUNTER: read_register = sys_counter;
                REG_SPI_COUNT: read_register = transaction_count;
                REG_IRQ_STATUS: read_register = irq_status;
                REG_IRQ_ENABLE: read_register = irq_enable;
                REG_FIFO_STATUS: read_register = fifo_status_word();
                REG_FIFO_WRITE: read_register = 32'h00000000;
                REG_FIFO_READ: read_register = (fifo_count == 5'd0) ? 32'h00000000 : fifo[fifo_rd];
                REG_FIFO_CONTROL: read_register = 32'h00000000;
                REG_ALGO_CONTROL: read_register = algo_control;
                REG_ALGO_STATUS: read_register = {24'd0, algo_enable[7:0]};
                REG_ALGO_ENABLE: read_register = algo_enable;
                REG_KALMAN_GAIN: read_register = kalman_gain;
                REG_KALMAN_PROCESS_NOISE: read_register = kalman_process_noise;
                REG_KALMAN_ESTIMATE: read_register = kalman_estimate;
                REG_KALMAN_COVARIANCE: read_register = kalman_covariance;
                REG_KALMAN_SAMPLE: read_register = 32'h00000000;
                REG_KALMAN_RESIDUAL: read_register = kalman_residual;
                REG_KALMAN_COUNT: read_register = kalman_count;
                REG_EMA_ALPHA: read_register = ema_alpha;
                REG_EMA_VALUE: read_register = ema_value;
                REG_EMA_SAMPLE: read_register = 32'h00000000;
                REG_EMA_COUNT: read_register = ema_count;
                REG_THRESH_LOW: read_register = threshold_low;
                REG_THRESH_HIGH: read_register = threshold_high;
                REG_THRESH_FLAGS: read_register = threshold_flags;
                REG_THRESH_LOW_COUNT: read_register = threshold_low_count;
                REG_THRESH_HIGH_COUNT: read_register = threshold_high_count;
                REG_THRESH_LAST: read_register = threshold_last;
                REG_STATS_CONTROL: read_register = 32'h00000000;
                REG_STATS_COUNT: read_register = stats_count;
                REG_STATS_MIN: read_register = stats_min;
                REG_STATS_MAX: read_register = stats_max;
                REG_STATS_SUM_LO: read_register = stats_sum[31:0];
                REG_STATS_SUM_HI: read_register = stats_sum[63:32];
                REG_STATS_LAST: read_register = stats_last;
                REG_PULSE_P13_COUNT: read_register = p13_edges;
                REG_PULSE_P20_COUNT: read_register = p20_edges;
                REG_PULSE_P13_LAST: read_register = p13_last_edge;
                REG_PULSE_P20_LAST: read_register = p20_last_edge;
                REG_PULSE_CONTROL: read_register = 32'h00000000;
                REG_PULSE_P13_PERIOD: read_register = p13_period;
                REG_PULSE_P20_PERIOD: read_register = p20_period;
                REG_PWM_CONTROL: read_register = pwm_control;
                REG_PWM_PERIOD: read_register = pwm_period;
                REG_PWM_DUTY_R: read_register = pwm_duty_r;
                REG_PWM_DUTY_G: read_register = pwm_duty_g;
                REG_PWM_DUTY_B: read_register = pwm_duty_b;
                REG_PWM_COUNTER: read_register = pwm_counter;
                REG_CRC_CONTROL: read_register = 32'h00000000;
                REG_CRC_VALUE: read_register = ~crc_value;
                REG_CRC_DATA: read_register = 32'h00000000;
                REG_CRC_SEED: read_register = ~crc_seed;
                REG_MAILBOX_CONTROL: read_register = mailbox_control;
                REG_MAILBOX_STATUS: read_register = mailbox_status;
                REG_MAILBOX_COMMAND: read_register = mailbox_command;
                REG_MAILBOX_ARG0: read_register = mailbox_arg0;
                REG_MAILBOX_ARG1: read_register = mailbox_arg1;
                REG_MAILBOX_RESULT0: read_register = mailbox_result0;
                REG_MAILBOX_RESULT1: read_register = mailbox_result1;
                default: read_register = 32'h00000000;
            endcase
        end
    endfunction

    task clear_fifo;
        begin
            fifo_rd <= 4'd0;
            fifo_wr <= 4'd0;
            fifo_count <= 5'd0;
            irq_status[IRQ_FIFO_NOT_EMPTY] <= 1'b0;
            irq_status[IRQ_FIFO_OVERFLOW] <= 1'b0;
        end
    endtask

    task fifo_push;
        input [31:0] value;
        begin
            if (fifo_count == 5'd16) begin
                irq_status[IRQ_FIFO_OVERFLOW] <= 1'b1;
            end else begin
                fifo[fifo_wr] <= value;
                fifo_wr <= fifo_wr + 4'd1;
                fifo_count <= fifo_count + 5'd1;
                irq_status[IRQ_FIFO_NOT_EMPTY] <= 1'b1;
            end
        end
    endtask

    task fifo_pop;
        begin
            if (fifo_count != 5'd0) begin
                fifo_rd <= fifo_rd + 4'd1;
                fifo_count <= fifo_count - 5'd1;
                if (fifo_count == 5'd1) begin
                    irq_status[IRQ_FIFO_NOT_EMPTY] <= 1'b0;
                end
            end
        end
    endtask

    task reset_processing;
        begin
            kalman_estimate <= 32'sh00000000;
            kalman_covariance <= 32'sh00010000;
            kalman_residual <= 32'sh00000000;
            kalman_count <= 32'h00000000;
            ema_value <= 32'sh00000000;
            ema_count <= 32'h00000000;
            threshold_flags <= 32'h00000000;
            threshold_low_count <= 32'h00000000;
            threshold_high_count <= 32'h00000000;
            threshold_last <= 32'sh00000000;
            stats_count <= 32'h00000000;
            stats_min <= 32'sh7FFFFFFF;
            stats_max <= 32'sh80000000;
            stats_sum <= 64'sh0000000000000000;
            stats_last <= 32'sh00000000;
        end
    endtask

    task process_sample;
        input signed [31:0] sample;
        begin
            sample_value = sample;

            if (algo_control[0] && algo_enable[0]) begin
                residual_next = sample_value - kalman_estimate;
                estimate_correction = residual_next * $signed({16'd0, kalman_gain[15:0]});
                estimate_next = kalman_estimate + (estimate_correction >>> 16);
                covariance_predicted = kalman_covariance + kalman_process_noise;
                covariance_correction = covariance_predicted * $signed({16'd0, kalman_gain[15:0]});
                kalman_estimate <= estimate_next;
                kalman_covariance <= covariance_predicted - (covariance_correction >>> 16);
                kalman_residual <= residual_next;
                kalman_count <= kalman_count + 32'd1;
            end

            if (algo_control[0] && algo_enable[1]) begin
                if (ema_count == 32'd0) begin
                    ema_value <= sample_value;
                end else begin
                    ema_correction = (sample_value - ema_value) * $signed({16'd0, ema_alpha[15:0]});
                    ema_value <= ema_value + (ema_correction >>> 16);
                end
                ema_count <= ema_count + 32'd1;
            end

            if (algo_control[0] && algo_enable[2]) begin
                threshold_last <= sample_value;
                threshold_flags <= 32'h00000000;
                if (sample_value < threshold_low) begin
                    threshold_flags[0] <= 1'b1;
                    threshold_low_count <= threshold_low_count + 32'd1;
                    irq_status[IRQ_THRESHOLD] <= 1'b1;
                end
                if (sample_value > threshold_high) begin
                    threshold_flags[1] <= 1'b1;
                    threshold_high_count <= threshold_high_count + 32'd1;
                    irq_status[IRQ_THRESHOLD] <= 1'b1;
                end
            end

            if (algo_control[0] && algo_enable[3]) begin
                sample_extended = {{32{sample_value[31]}}, sample_value};
                stats_last <= sample_value;
                if (stats_count == 32'd0) begin
                    stats_min <= sample_value;
                    stats_max <= sample_value;
                    stats_sum <= sample_extended;
                end else begin
                    if (sample_value < stats_min) begin
                        stats_min <= sample_value;
                    end
                    if (sample_value > stats_max) begin
                        stats_max <= sample_value;
                    end
                    stats_sum <= stats_sum + sample_extended;
                end
                stats_count <= stats_count + 32'd1;
            end

            irq_status[IRQ_SAMPLE_PROCESSED] <= 1'b1;
        end
    endtask

    task run_mailbox;
        begin
            mailbox_status <= 32'h00000001;
            case (mailbox_command[7:0])
                8'h00: begin
                    mailbox_result0 <= 32'h00000000;
                    mailbox_result1 <= 32'h00000000;
                end
                8'h01: begin
                    process_sample(mailbox_arg0);
                    mailbox_result0 <= mailbox_arg0;
                    mailbox_result1 <= stats_count + 32'd1;
                end
                8'h02: begin
                    mailbox_result0 <= fifo_status_word();
                    mailbox_result1 <= {16'd0, algo_enable[15:0]};
                end
                8'h03: begin
                    mailbox_result0 <= next_crc32(crc_value, mailbox_arg0);
                    mailbox_result1 <= 32'h00000000;
                end
                8'h04: begin
                    mailbox_result0 <= mailbox_arg0 + mailbox_arg1;
                    mailbox_result1 <= mailbox_arg0 ^ mailbox_arg1;
                end
                8'h05: begin
                    mailbox_result0 <= {p13_edges[15:0], p20_edges[15:0]};
                    mailbox_result1 <= p13_period;
                end
                default: begin
                    mailbox_result0 <= 32'hFFFFFFFF;
                    mailbox_result1 <= mailbox_command;
                end
            endcase
            mailbox_status <= 32'h00000002;
            irq_status[IRQ_MAILBOX_DONE] <= 1'b1;
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
                    write_value = {write_shift[30:0], mosi};
                    case (address)
                        REG_SCRATCH: scratch <= write_value;
                        REG_CONTROL: control <= write_value;
                        REG_IRQ_STATUS: irq_status <= irq_status & ~write_value;
                        REG_IRQ_ENABLE: irq_enable <= write_value;
                        REG_FIFO_WRITE: begin
                            fifo_push(write_value);
                            if (algo_control[8]) begin
                                process_sample(write_value);
                            end
                        end
                        REG_FIFO_CONTROL: begin
                            if (write_value[0]) begin
                                fifo_pop;
                            end
                            if (write_value[1]) begin
                                clear_fifo;
                            end
                            if (write_value[2] && fifo_count != 5'd0) begin
                                process_sample(fifo[fifo_rd]);
                                fifo_pop;
                            end
                        end
                        REG_ALGO_CONTROL: begin
                            algo_control <= write_value & 32'hFFFFFDFD;
                            if (write_value[1]) begin
                                reset_processing;
                            end
                            if (write_value[8] && fifo_count != 5'd0) begin
                                process_sample(fifo[fifo_rd]);
                                fifo_pop;
                            end
                        end
                        REG_ALGO_ENABLE: algo_enable <= write_value;
                        REG_KALMAN_GAIN: kalman_gain <= write_value;
                        REG_KALMAN_PROCESS_NOISE: kalman_process_noise <= write_value;
                        REG_KALMAN_ESTIMATE: kalman_estimate <= write_value;
                        REG_KALMAN_COVARIANCE: kalman_covariance <= write_value;
                        REG_KALMAN_SAMPLE: process_sample(write_value);
                        REG_EMA_ALPHA: ema_alpha <= write_value;
                        REG_EMA_VALUE: ema_value <= write_value;
                        REG_EMA_SAMPLE: process_sample(write_value);
                        REG_THRESH_LOW: threshold_low <= write_value;
                        REG_THRESH_HIGH: threshold_high <= write_value;
                        REG_THRESH_FLAGS: threshold_flags <= threshold_flags & ~write_value;
                        REG_STATS_CONTROL: begin
                            if (write_value[0]) begin
                                reset_processing;
                            end
                        end
                        REG_PULSE_CONTROL: begin
                            if (write_value[0]) begin
                                pulse_reset <= 1'b1;
                            end
                        end
                        REG_PWM_CONTROL: pwm_control <= write_value;
                        REG_PWM_PERIOD: pwm_period <= (write_value == 32'd0) ? 32'd1 : write_value;
                        REG_PWM_DUTY_R: pwm_duty_r <= write_value;
                        REG_PWM_DUTY_G: pwm_duty_g <= write_value;
                        REG_PWM_DUTY_B: pwm_duty_b <= write_value;
                        REG_CRC_CONTROL: begin
                            if (write_value[0]) begin
                                crc_value <= crc_seed;
                            end
                        end
                        REG_CRC_VALUE: crc_value <= ~write_value;
                        REG_CRC_DATA: crc_value <= next_crc32(crc_value, write_value);
                        REG_CRC_SEED: begin
                            crc_seed <= ~write_value;
                            crc_value <= ~write_value;
                        end
                        REG_MAILBOX_CONTROL: begin
                            mailbox_control <= write_value;
                            if (write_value[0]) begin
                                run_mailbox;
                            end
                            if (write_value[1]) begin
                                mailbox_status <= 32'h00000000;
                                irq_status[IRQ_MAILBOX_DONE] <= 1'b0;
                            end
                        end
                        REG_MAILBOX_COMMAND: mailbox_command <= write_value;
                        REG_MAILBOX_ARG0: mailbox_arg0 <= write_value;
                        REG_MAILBOX_ARG1: mailbox_arg1 <= write_value;
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
