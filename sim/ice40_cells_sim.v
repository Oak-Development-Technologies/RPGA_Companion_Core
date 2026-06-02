`default_nettype none

module SB_HFOSC #(
    parameter CLKHF_DIV = "0b00"
) (
    input  wire CLKHFEN,
    input  wire CLKHFPU,
    output reg  CLKHF = 1'b0
);
    always begin
        #10;
        if (CLKHFEN && CLKHFPU) begin
            CLKHF = ~CLKHF;
        end else begin
            CLKHF = 1'b0;
        end
    end
endmodule

module SB_GB (
    input  wire USER_SIGNAL_TO_GLOBAL_BUFFER,
    output wire GLOBAL_BUFFER_OUTPUT
);
    assign GLOBAL_BUFFER_OUTPUT = USER_SIGNAL_TO_GLOBAL_BUFFER;
endmodule

module SB_RAM40_4K #(
    parameter READ_MODE = 0,
    parameter WRITE_MODE = 0
) (
    output reg  [15:0] RDATA,
    input  wire [10:0] RADDR,
    input  wire        RCLK,
    input  wire        RCLKE,
    input  wire        RE,
    input  wire [10:0] WADDR,
    input  wire        WCLK,
    input  wire        WCLKE,
    input  wire [15:0] WDATA,
    input  wire        WE,
    input  wire [15:0] MASK
);
    reg [15:0] mem [0:255];
    integer i;

    initial begin
        RDATA = 16'h0000;
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 16'h0000;
        end
    end

    always @(posedge WCLK) begin
        if (WCLKE && WE) begin
            mem[WADDR[10:3]] <= (WDATA & ~MASK) | (mem[WADDR[10:3]] & MASK);
        end
    end

    always @(posedge RCLK) begin
        if (RCLKE && RE) begin
            RDATA <= mem[RADDR[10:3]];
        end
    end
endmodule

module SB_MAC16 #(
    parameter NEG_TRIGGER = 1'b0,
    parameter C_REG = 1'b0,
    parameter A_REG = 1'b0,
    parameter B_REG = 1'b0,
    parameter D_REG = 1'b0,
    parameter TOP_8x8_MULT_REG = 1'b0,
    parameter BOT_8x8_MULT_REG = 1'b0,
    parameter PIPELINE_16x16_MULT_REG1 = 1'b0,
    parameter PIPELINE_16x16_MULT_REG2 = 1'b0,
    parameter TOPOUTPUT_SELECT = 2'b00,
    parameter TOPADDSUB_LOWERINPUT = 2'b00,
    parameter TOPADDSUB_UPPERINPUT = 1'b0,
    parameter TOPADDSUB_CARRYSELECT = 2'b00,
    parameter BOTOUTPUT_SELECT = 2'b00,
    parameter BOTADDSUB_LOWERINPUT = 2'b00,
    parameter BOTADDSUB_UPPERINPUT = 1'b0,
    parameter BOTADDSUB_CARRYSELECT = 2'b00,
    parameter MODE_8x8 = 1'b0,
    parameter A_SIGNED = 1'b0,
    parameter B_SIGNED = 1'b0
) (
    input  wire        CLK,
    input  wire        CE,
    input  wire [15:0] C,
    input  wire [15:0] A,
    input  wire [15:0] B,
    input  wire [15:0] D,
    input  wire        AHOLD,
    input  wire        BHOLD,
    input  wire        CHOLD,
    input  wire        DHOLD,
    input  wire        IRSTTOP,
    input  wire        IRSTBOT,
    input  wire        ORSTTOP,
    input  wire        ORSTBOT,
    input  wire        OLOADTOP,
    input  wire        OLOADBOT,
    input  wire        ADDSUBTOP,
    input  wire        ADDSUBBOT,
    input  wire        OHOLDTOP,
    input  wire        OHOLDBOT,
    input  wire        CI,
    input  wire        ACCUMCI,
    input  wire        SIGNEXTIN,
    output wire [31:0] O,
    output wire        CO,
    output wire        ACCUMCO,
    output wire        SIGNEXTOUT
);
    wire signed [16:0] a_signed = {A[15], A};
    wire signed [16:0] b_signed = {B[15], B};
    wire signed [16:0] a_mixed = A_SIGNED ? a_signed : $signed({1'b0, A});
    wire signed [16:0] b_mixed = B_SIGNED ? b_signed : $signed({1'b0, B});
    wire signed [33:0] product = a_mixed * b_mixed;

    assign O = product[31:0];
    assign CO = 1'b0;
    assign ACCUMCO = 1'b0;
    assign SIGNEXTOUT = product[32];
endmodule

`default_nettype wire
