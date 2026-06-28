// Formal verification: id_decoder instruction class encoding correctness
//
// Proves structural invariants of the instruction decoder for all 2^32 possible
// 32-bit encodings.  These properties are the machine-checked analog of the
// encoding tables in the id_decoder header comment.
//
// Properties proved (8):
//   P_LOAD_CLASS     : LOAD opcode  → mem_read=1, mem_write=0
//   P_STORE_CLASS    : STORE opcode → mem_read=0, mem_write=1, reg_write=0
//   P_BRANCH_NO_MEM  : BRANCH opcode → mem_read=0, mem_write=0, reg_write=0
//   P_BRANCH_NO_JUMP : BRANCH opcode → jump=0  (branch/jump mutually exclusive)
//   P_JAL_CLASS      : JAL opcode → jump=1, jump_reg=0, reg_write=1, wb_sel=10
//   P_MEM_MUTEX      : ~(mem_read & mem_write) for ALL 32-bit encodings
//   P_OP_NOREG       : STORE/BRANCH → reg_write=0 (no rd write-back)
//   P_UNKNOWN_SAFE   : unknown opcode → no arch state change
//                      (mem_read=0, mem_write=0, reg_write=0, csr_we=0,
//                       branch=0, jump=0)

`timescale 1ns/1ps
module fv_decoder (
    input logic clk,
    input logic rst_n
);

    // Symbolic (unconstrained) instruction word
    logic [31:0] instr;

    // DUT outputs
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [11:0] csr_addr;
    logic [2:0]  funct3;
    logic [31:0] imm;
    logic [3:0]  alu_op;
    logic        alu_src_a, alu_src_b;
    logic        branch, jump, jump_reg;
    logic        mem_read, mem_write;
    logic [1:0]  mem_size;
    logic        mem_ext;
    logic        reg_write;
    logic [1:0]  wb_sel;
    logic        csr_we;
    logic [1:0]  csr_op;
    logic        csr_imm_sel;
    logic        ecall, ebreak, mret, illegal_instr;

    id_decoder dut (
        .instr        (instr),
        .rs1_addr     (rs1_addr),
        .rs2_addr     (rs2_addr),
        .rd_addr      (rd_addr),
        .csr_addr     (csr_addr),
        .funct3       (funct3),
        .imm          (imm),
        .alu_op       (alu_op),
        .alu_src_a    (alu_src_a),
        .alu_src_b    (alu_src_b),
        .branch       (branch),
        .jump         (jump),
        .jump_reg     (jump_reg),
        .mem_read     (mem_read),
        .mem_write    (mem_write),
        .mem_size     (mem_size),
        .mem_ext      (mem_ext),
        .reg_write    (reg_write),
        .wb_sel       (wb_sel),
        .csr_we       (csr_we),
        .csr_op       (csr_op),
        .csr_imm_sel  (csr_imm_sel),
        .ecall        (ecall),
        .ebreak       (ebreak),
        .mret         (mret),
        .illegal_instr(illegal_instr)
    );

    // Opcode field (bits [6:0])
    logic [6:0] opcode;
    assign opcode = instr[6:0];

    // Valid opcode set for RV32I+Zicsr
    logic opcode_valid;
    assign opcode_valid =
        (opcode == 7'b0110111) || // LUI
        (opcode == 7'b0010111) || // AUIPC
        (opcode == 7'b1101111) || // JAL
        (opcode == 7'b1100111) || // JALR
        (opcode == 7'b1100011) || // BRANCH
        (opcode == 7'b0000011) || // LOAD
        (opcode == 7'b0100011) || // STORE
        (opcode == 7'b0010011) || // OP-IMM
        (opcode == 7'b0110011) || // OP
        (opcode == 7'b0001111) || // FENCE
        (opcode == 7'b1110011);   // SYSTEM

    // P_LOAD_CLASS: LOAD opcode → mem_read=1, mem_write=0
    always @(posedge clk)
        if (opcode == 7'b0000011)
            assert (mem_read == 1'b1 && mem_write == 1'b0);

    // P_STORE_CLASS: STORE opcode → mem_read=0, mem_write=1, reg_write=0
    always @(posedge clk)
        if (opcode == 7'b0100011)
            assert (mem_read == 1'b0 && mem_write == 1'b1 && reg_write == 1'b0);

    // P_BRANCH_NO_MEM: BRANCH opcode → no memory access, no register write
    always @(posedge clk)
        if (opcode == 7'b1100011)
            assert (mem_read == 1'b0 && mem_write == 1'b0 && reg_write == 1'b0);

    // P_BRANCH_NO_JUMP: branch and jump signals are mutually exclusive
    always @(posedge clk)
        if (opcode == 7'b1100011)
            assert (jump == 1'b0);

    // P_JAL_CLASS: JAL → jump=1, jump_reg=0, reg_write=1, wb_sel=2'b10 (PC+4)
    always @(posedge clk)
        if (opcode == 7'b1101111)
            assert (jump == 1'b1 && jump_reg == 1'b0 && reg_write == 1'b1 && wb_sel == 2'b10);

    // P_MEM_MUTEX: mem_read and mem_write can never both be asserted for ANY encoding
    always @(posedge clk)
        assert (~(mem_read & mem_write));

    // P_OP_NOREG: STORE and BRANCH never write a destination register
    always @(posedge clk)
        if (opcode == 7'b0100011 || opcode == 7'b1100011)
            assert (reg_write == 1'b0);

    // P_UNKNOWN_SAFE: unrecognised opcode produces no architectural state change.
    // (mem_read=0, mem_write=0, reg_write=0, csr_we=0, branch=0, jump=0)
    // This proves the decoder is safe even against malformed instruction encodings.
    always @(posedge clk)
        if (!opcode_valid)
            assert (mem_read == 1'b0 && mem_write == 1'b0 && reg_write == 1'b0 &&
                    csr_we == 1'b0 && branch == 1'b0 && jump == 1'b0);

endmodule
