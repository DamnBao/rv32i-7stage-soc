// Address Adder — computes branch/jump target or load/store effective address.
//
// Base select:
//   branch, JAL  → PC + imm  (PC-relative)
//   JALR         → rs1 + imm (register-relative)
//   load/store   → rs1 + imm (register-relative, same path as JALR)
//
// Output:
//   branch/JAL/JALR → jump target fed to if1_stage via soc_top mux
//   load/store      → effective address fed to mem1_stage as addr_in

module addr_adder (
    input  logic [31:0] pc,
    input  logic [31:0] rs1_data,  // Forwarded rs1 (from forwarding MUX in ex_stage)
    input  logic [31:0] imm,       // Sign-extended immediate (imm_b/imm_j/imm_i/imm_s)
    input  logic        branch,
    input  logic        jump,
    input  logic        jump_reg,  // 1 if JALR

    output logic [31:0] addr_out   // Jump/branch target or load/store address
);

    logic        use_pc;
    logic [31:0] base;
    logic [31:0] sum;

    assign use_pc   = branch | (jump & ~jump_reg);
    assign base     = use_pc ? pc : rs1_data;
    assign sum      = base + imm;

    // RISC-V ISA §2.5: JALR clears bit[0] of the computed address so the
    // target is always instruction-aligned even if the immediate is odd.
    assign addr_out = jump_reg ? (sum & 32'hFFFF_FFFE) : sum;

endmodule
