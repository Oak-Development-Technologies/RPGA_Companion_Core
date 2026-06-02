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

`default_nettype wire
