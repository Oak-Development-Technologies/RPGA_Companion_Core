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
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

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
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:(1 << ADDR_WIDTH)-1];

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

`default_nettype wire
