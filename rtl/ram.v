`default_nettype none

module rpga_sync_ram #(
    parameter ADDR_WIDTH = 7,
    parameter DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] wdata,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output reg  [DATA_WIDTH-1:0] rdata
);
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

    always @(posedge clk) begin
        if (we) begin
            mem[waddr] <= wdata;
        end
        rdata <= mem[raddr];
    end
endmodule

module rpga_dual_port_ram #(
    parameter ADDR_WIDTH = 8,
    parameter DATA_WIDTH = 32
) (
    input  wire                  a_clk,
    input  wire                  a_we,
    input  wire [ADDR_WIDTH-1:0] a_addr,
    input  wire [DATA_WIDTH-1:0] a_wdata,
    output reg  [DATA_WIDTH-1:0] a_rdata,

    input  wire                  b_clk,
    input  wire                  b_we,
    input  wire [ADDR_WIDTH-1:0] b_addr,
    input  wire [DATA_WIDTH-1:0] b_wdata,
    output reg  [DATA_WIDTH-1:0] b_rdata
);
    reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

    always @(posedge a_clk) begin
        if (a_we) begin
            mem[a_addr] <= a_wdata;
        end
        a_rdata <= mem[a_addr];
    end

    always @(posedge b_clk) begin
        if (b_we) begin
            mem[b_addr] <= b_wdata;
        end
        b_rdata <= mem[b_addr];
    end
endmodule

module rpga_ice40_ram32_256 (
    input  wire        wclk,
    input  wire        we,
    input  wire [7:0]  waddr,
    input  wire [31:0] wdata,
    input  wire        rclk,
    input  wire [7:0]  raddr,
    output wire [31:0] rdata
);
    wire [15:0] rdata_lo;
    wire [15:0] rdata_hi;

    SB_RAM40_4K #(
        .READ_MODE(0),
        .WRITE_MODE(0)
    ) ram_lo (
        .RDATA(rdata_lo),
        .RADDR({raddr, 3'b000}),
        .RCLK(rclk),
        .RCLKE(1'b1),
        .RE(1'b1),
        .WADDR({waddr, 3'b000}),
        .WCLK(wclk),
        .WCLKE(1'b1),
        .WDATA(wdata[15:0]),
        .WE(we),
        .MASK(16'h0000)
    );

    SB_RAM40_4K #(
        .READ_MODE(0),
        .WRITE_MODE(0)
    ) ram_hi (
        .RDATA(rdata_hi),
        .RADDR({raddr, 3'b000}),
        .RCLK(rclk),
        .RCLKE(1'b1),
        .RE(1'b1),
        .WADDR({waddr, 3'b000}),
        .WCLK(wclk),
        .WCLKE(1'b1),
        .WDATA(wdata[31:16]),
        .WE(we),
        .MASK(16'h0000)
    );

    assign rdata = {rdata_hi, rdata_lo};
endmodule

`default_nettype wire
