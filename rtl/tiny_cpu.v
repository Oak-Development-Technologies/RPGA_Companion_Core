`default_nettype none

module rpga_tiny_cpu (
    input  wire        clk,
    input  wire        reset,
    input  wire        run,
    input  wire        halt_req,
    input  wire [7:0]  start_pc,

    output reg  [7:0]  imem_addr = 8'h00,
    input  wire [31:0] imem_rdata,

    output reg  [7:0]  dmem_addr = 8'h00,
    output reg         dmem_we = 1'b0,
    output reg  [31:0] dmem_wdata = 32'h00000000,
    input  wire [31:0] dmem_rdata,

    output reg         running = 1'b0,
    output reg         halted = 1'b1,
    output reg         zero = 1'b0,
    output reg         irq = 1'b0,
    output reg  [7:0]  pc = 8'h00,
    output reg  [31:0] steps = 32'h00000000,
    output reg  [31:0] out_reg = 32'h00000000,
    output wire [31:0] r0,
    output wire [31:0] r1,
    output wire [31:0] r2,
    output wire [31:0] r3
);
    localparam [2:0] ST_FETCH_ADDR = 3'd0;
    localparam [2:0] ST_FETCH_READ = 3'd1;
    localparam [2:0] ST_EXEC = 3'd2;
    localparam [2:0] ST_LOAD_WAIT = 3'd3;

    localparam [3:0] OP_NOP = 4'h0;
    localparam [3:0] OP_LDI = 4'h1;
    localparam [3:0] OP_LOAD = 4'h2;
    localparam [3:0] OP_STORE = 4'h3;
    localparam [3:0] OP_ADD = 4'h4;
    localparam [3:0] OP_SUB = 4'h5;
    localparam [3:0] OP_AND = 4'h6;
    localparam [3:0] OP_OR = 4'h7;
    localparam [3:0] OP_XOR = 4'h8;
    localparam [3:0] OP_SHR = 4'h9;
    localparam [3:0] OP_SHL = 4'hA;
    localparam [3:0] OP_JMP = 4'hB;
    localparam [3:0] OP_JZ = 4'hC;
    localparam [3:0] OP_JNZ = 4'hD;
    localparam [3:0] OP_OUT = 4'hE;
    localparam [3:0] OP_HALT = 4'hF;

    reg [2:0] state = ST_FETCH_ADDR;
    reg [31:0] instr = 32'h00000000;
    reg [31:0] regs [0:7];
    reg [2:0] load_rd = 3'd0;
    reg [31:0] result = 32'h00000000;
    reg run_d = 1'b0;

    wire [3:0] opcode = instr[31:28];
    wire [2:0] rd = instr[27:25];
    wire [2:0] rs = instr[24:22];
    wire [2:0] rt = instr[21:19];
    wire [15:0] imm16 = instr[15:0];
    wire signed [31:0] simm = {{16{imm16[15]}}, imm16};

    assign r0 = regs[0];
    assign r1 = regs[1];
    assign r2 = regs[2];
    assign r3 = regs[3];

    integer i;

    always @(posedge clk) begin
        dmem_we <= 1'b0;
        run_d <= run;

        if (reset) begin
            pc <= start_pc;
            imem_addr <= start_pc;
            dmem_addr <= 8'h00;
            running <= 1'b0;
            halted <= 1'b1;
            zero <= 1'b0;
            irq <= 1'b0;
            steps <= 32'h00000000;
            out_reg <= 32'h00000000;
            run_d <= 1'b0;
            state <= ST_FETCH_ADDR;
            for (i = 0; i < 8; i = i + 1) begin
                regs[i] <= 32'h00000000;
            end
        end else if (halt_req) begin
            running <= 1'b0;
            halted <= 1'b1;
            state <= ST_FETCH_ADDR;
        end else if (run && !run_d && !running) begin
            pc <= start_pc;
            imem_addr <= start_pc;
            running <= 1'b1;
            halted <= 1'b0;
            irq <= 1'b0;
            state <= ST_FETCH_ADDR;
        end else if (running) begin
            case (state)
                ST_FETCH_ADDR: begin
                    imem_addr <= pc;
                    state <= ST_FETCH_READ;
                end
                ST_FETCH_READ: begin
                    instr <= imem_rdata;
                    pc <= pc + 8'd1;
                    state <= ST_EXEC;
                end
                ST_EXEC: begin
                    steps <= steps + 32'd1;
                    case (opcode)
                        OP_NOP: begin
                            state <= ST_FETCH_ADDR;
                        end
                        OP_LDI: begin
                            regs[rd] <= simm;
                            zero <= (simm == 32'sd0);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_LOAD: begin
                            dmem_addr <= regs[rs][7:0] + imm16[7:0];
                            load_rd <= rd;
                            state <= ST_LOAD_WAIT;
                        end
                        OP_STORE: begin
                            dmem_addr <= regs[rs][7:0] + imm16[7:0];
                            dmem_wdata <= regs[rd];
                            dmem_we <= 1'b1;
                            state <= ST_FETCH_ADDR;
                        end
                        OP_ADD: begin
                            result = regs[rs] + regs[rt];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_SUB: begin
                            result = regs[rs] - regs[rt];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_AND: begin
                            result = regs[rs] & regs[rt];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_OR: begin
                            result = regs[rs] | regs[rt];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_XOR: begin
                            result = regs[rs] ^ regs[rt];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_SHR: begin
                            result = regs[rs] >> imm16[4:0];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_SHL: begin
                            result = regs[rs] << imm16[4:0];
                            regs[rd] <= result;
                            zero <= (result == 32'h00000000);
                            state <= ST_FETCH_ADDR;
                        end
                        OP_JMP: begin
                            pc <= imm16[7:0];
                            state <= ST_FETCH_ADDR;
                        end
                        OP_JZ: begin
                            if (zero) begin
                                pc <= imm16[7:0];
                            end
                            state <= ST_FETCH_ADDR;
                        end
                        OP_JNZ: begin
                            if (!zero) begin
                                pc <= imm16[7:0];
                            end
                            state <= ST_FETCH_ADDR;
                        end
                        OP_OUT: begin
                            out_reg <= regs[rd];
                            irq <= imm16[0];
                            state <= ST_FETCH_ADDR;
                        end
                        OP_HALT: begin
                            running <= 1'b0;
                            halted <= 1'b1;
                            irq <= 1'b1;
                            state <= ST_FETCH_ADDR;
                        end
                        default: begin
                            state <= ST_FETCH_ADDR;
                        end
                    endcase
                end
                ST_LOAD_WAIT: begin
                    regs[load_rd] <= dmem_rdata;
                    zero <= (dmem_rdata == 32'h00000000);
                    state <= ST_FETCH_ADDR;
                end
                default: begin
                    state <= ST_FETCH_ADDR;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
