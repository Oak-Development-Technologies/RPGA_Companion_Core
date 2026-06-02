`default_nettype none

module rpga_ice40_dsp_mul16_signed_unsigned (
    input  wire              clk,
    input  wire signed [15:0] a,
    input  wire        [15:0] b,
    output wire signed [31:0] y
);
    wire [31:0] mac_o;

    SB_MAC16 #(
        .NEG_TRIGGER(1'b0),
        .C_REG(1'b0),
        .A_REG(1'b0),
        .B_REG(1'b0),
        .D_REG(1'b0),
        .TOP_8x8_MULT_REG(1'b0),
        .BOT_8x8_MULT_REG(1'b0),
        .PIPELINE_16x16_MULT_REG1(1'b0),
        .PIPELINE_16x16_MULT_REG2(1'b0),
        .TOPOUTPUT_SELECT(2'b11),
        .TOPADDSUB_LOWERINPUT(2'b00),
        .TOPADDSUB_UPPERINPUT(1'b0),
        .TOPADDSUB_CARRYSELECT(2'b00),
        .BOTOUTPUT_SELECT(2'b11),
        .BOTADDSUB_LOWERINPUT(2'b00),
        .BOTADDSUB_UPPERINPUT(1'b0),
        .BOTADDSUB_CARRYSELECT(2'b00),
        .MODE_8x8(1'b0),
        .A_SIGNED(1'b1),
        .B_SIGNED(1'b0)
    ) mul (
        .CLK(clk),
        .CE(1'b1),
        .C(16'h0000),
        .A(a),
        .B(b),
        .D(16'h0000),
        .AHOLD(1'b0),
        .BHOLD(1'b0),
        .CHOLD(1'b0),
        .DHOLD(1'b0),
        .IRSTTOP(1'b0),
        .IRSTBOT(1'b0),
        .ORSTTOP(1'b0),
        .ORSTBOT(1'b0),
        .OLOADTOP(1'b0),
        .OLOADBOT(1'b0),
        .ADDSUBTOP(1'b0),
        .ADDSUBBOT(1'b0),
        .OHOLDTOP(1'b0),
        .OHOLDBOT(1'b0),
        .CI(1'b0),
        .ACCUMCI(1'b0),
        .SIGNEXTIN(1'b0),
        .O(mac_o),
        .CO(),
        .ACCUMCO(),
        .SIGNEXTOUT()
    );

    assign y = mac_o;
endmodule

`default_nettype wire
