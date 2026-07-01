// Formal verification: ALU arithmetic/logic correctness
//
// Proves that each alu_op produces the arithmetically correct output for all
// 32-bit inputs.  The ALU is purely combinational so depth=3 with k-induction
// is more than enough — the solver sees every possible (a, b, op) combination.
//
// Properties proved (12):
//   P_ADD      : ALU_ADD  → result = a + b  (mod 2^32)
//   P_SUB      : ALU_SUB  → result = a - b  (mod 2^32)
//   P_AND      : ALU_AND  → result = a & b
//   P_OR       : ALU_OR   → result = a | b
//   P_XOR      : ALU_XOR  → result = a ^ b
//   P_SLT      : ALU_SLT  → result = ($signed(a) < $signed(b)) ? 1 : 0
//   P_SLTU     : ALU_SLTU → result = (a < b) ? 1 : 0
//   P_SLL      : ALU_SLL  → result = a << b[4:0]
//   P_SRL      : ALU_SRL  → result = a >> b[4:0]
//   P_SRA      : ALU_SRA  → result = $signed(a) >>> b[4:0]  (sign-extending)
//   P_SRA_SIGN : ALU_SRA with negative a, shift>0 → result[31] = 1
//   P_PASSB    : ALU_PASSB → result = b  (used by LUI)

`timescale 1ns/1ps
module fv_alu (
    input logic clk,
    input logic rst_n
);

    // Symbolic (unconstrained) inputs
    logic [31:0] operand_a, operand_b;
    logic [3:0]  alu_op;

    // DUT output
    logic [31:0] alu_result;

    // alu_src_a=0, alu_src_b=0: bypass the input MUX, operand_a/b feed ALU directly
    alu dut (
        .rs1_fwd   (operand_a),
        .rs2_fwd   (operand_b),
        .pc_in     (32'h0),
        .imm_in    (32'h0),
        .alu_src_a (1'b0),
        .alu_src_b (1'b0),
        .alu_op    (alu_op),
        .alu_result(alu_result)
    );

    // ALU opcodes (must match alu.sv)
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

    logic [4:0] shift_amt;
    assign shift_amt = operand_b[4:0];

    // P_ADD
    always @(posedge clk)
        if (alu_op == ALU_ADD)
            assert (alu_result == operand_a + operand_b);

    // P_SUB
    always @(posedge clk)
        if (alu_op == ALU_SUB)
            assert (alu_result == operand_a - operand_b);

    // P_AND
    always @(posedge clk)
        if (alu_op == ALU_AND)
            assert (alu_result == (operand_a & operand_b));

    // P_OR
    always @(posedge clk)
        if (alu_op == ALU_OR)
            assert (alu_result == (operand_a | operand_b));

    // P_XOR
    always @(posedge clk)
        if (alu_op == ALU_XOR)
            assert (alu_result == (operand_a ^ operand_b));

    // P_SLT — signed less-than
    always @(posedge clk)
        if (alu_op == ALU_SLT)
            assert (alu_result == ($signed(operand_a) < $signed(operand_b) ? 32'd1 : 32'd0));

    // P_SLTU — unsigned less-than
    always @(posedge clk)
        if (alu_op == ALU_SLTU)
            assert (alu_result == (operand_a < operand_b ? 32'd1 : 32'd0));

    // P_SLL
    always @(posedge clk)
        if (alu_op == ALU_SLL)
            assert (alu_result == (operand_a << shift_amt));

    // P_SRL
    always @(posedge clk)
        if (alu_op == ALU_SRL)
            assert (alu_result == (operand_a >> shift_amt));

    // P_SRA — arithmetic right shift (sign-extending)
    always @(posedge clk)
        if (alu_op == ALU_SRA)
            assert (alu_result == $unsigned($signed(operand_a) >>> shift_amt));

    // P_SRA_SIGN — negative input stays negative after SRA with any nonzero shift
    always @(posedge clk)
        if (alu_op == ALU_SRA && operand_a[31] && shift_amt > 5'd0)
            assert (alu_result[31] == 1'b1);

    // P_PASSB — used by LUI (pass upper immediate, ignore A)
    always @(posedge clk)
        if (alu_op == ALU_PASSB)
            assert (alu_result == operand_b);

endmodule
