// ALU — 32-bit arithmetic/logic unit for the RV32I base ISA.
//
// alu_op encoding must match id_decoder.sv localparams exactly.
// shift_amt is extracted outside always_* to avoid Icarus constant-select warnings.

module alu (
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic [3:0]  alu_op,    // Operation select (see localparams below)

    output logic [31:0] alu_result
);

    // Operation codes — must stay in sync with id_decoder.sv
    localparam ALU_ADD   = 4'd0;
    localparam ALU_SUB   = 4'd1;
    localparam ALU_SLL   = 4'd2;
    localparam ALU_SLT   = 4'd3;
    localparam ALU_SLTU  = 4'd4;
    localparam ALU_XOR   = 4'd5;
    localparam ALU_SRL   = 4'd6;
    localparam ALU_SRA   = 4'd7;
    localparam ALU_OR    = 4'd8;
    localparam ALU_AND   = 4'd9;
    localparam ALU_PASSB = 4'd10;

    // Extract shift amount outside always_* (Icarus constant-select workaround)
    logic [4:0] shift_amt;
    assign shift_amt = operand_b[4:0];

    always_comb begin
        alu_result = 32'd0;  // default prevents latches
        case (alu_op)
            ALU_ADD:   alu_result = operand_a + operand_b;
            ALU_SUB:   alu_result = operand_a - operand_b;
            ALU_SLL:   alu_result = operand_a << shift_amt;
            ALU_SLT:   alu_result = ($signed(operand_a) < $signed(operand_b)) ? 32'd1 : 32'd0;
            ALU_SLTU:  alu_result = (operand_a < operand_b) ? 32'd1 : 32'd0;
            ALU_XOR:   alu_result = operand_a ^ operand_b;
            ALU_SRL:   alu_result = operand_a >> shift_amt;
            ALU_SRA:   alu_result = $unsigned($signed(operand_a) >>> shift_amt);
            ALU_OR:    alu_result = operand_a | operand_b;
            ALU_AND:   alu_result = operand_a & operand_b;
            ALU_PASSB: alu_result = operand_b;  // LUI: pass upper immediate, ignore A
            default:   alu_result = 32'd0;
        endcase
    end

endmodule
