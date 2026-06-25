// Branch Comparator — evaluates B-type branch conditions at the EX stage.
//
// Comparisons are factored out of always_comb to avoid Icarus Verilog's
// "constant select" warning that fires when $signed cast appears inside always_*.
//
// branch_taken → hazard_unit, which flushes IF1/IF2 and IF2/ID on the next cycle.

module branch_comp (
    input  logic [31:0] rs1_data,   // Forwarded rs1 (from forwarding MUX in ex_stage)
    input  logic [31:0] rs2_data,   // Forwarded rs2
    input  logic [2:0]  funct3,     // Branch type field
    input  logic        branch,     // 1 if B-type instruction (gate: non-branches output 0)

    output logic        branch_taken
);

    logic eq;
    logic slt;  // Signed less than
    logic ult;  // Unsigned less than

    assign eq  = (rs1_data == rs2_data);
    assign slt = ($signed(rs1_data) < $signed(rs2_data));
    assign ult = (rs1_data < rs2_data);

    always_comb begin
        branch_taken = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: branch_taken =  eq;   // BEQ
                3'b001: branch_taken = ~eq;   // BNE
                3'b100: branch_taken =  slt;  // BLT
                3'b101: branch_taken = ~slt;  // BGE
                3'b110: branch_taken =  ult;  // BLTU
                3'b111: branch_taken = ~ult;  // BGEU
                default: branch_taken = 1'b0;
            endcase
        end
    end

endmodule
