// EX Stage: Forwarding Resolution + ALU Input Select + ALU + Branch + Address
//
// This module wraps all combinational logic that executes in the EX pipeline
// stage, keeping soc_top free of any datapath logic.
//
// Internal structure:
//   1. forwarding_unit  — determines which bypass path covers each operand
//   2. Forwarding MUX   — selects final rs1/rs2 values (register file vs bypass)
//   3. ALU input MUX    — selects ALU_A (rs1 or PC) and ALU_B (rs2 or imm)
//   4. alu              — computes ALU result
//   5. branch_comp      — evaluates branch condition
//   6. addr_adder       — computes branch/jump target or load/store address
//
// Forwarding priority (highest first): MEM1 > MEM2 > WB
// fwd_data_mem2 is computed here: if instruction at MEM2 is a load (wb_sel==01)
// use mem_rdata, else use alu_result — consistent with forwarding_unit priority.
//
// Outputs ex_rs1_fwd and ex_rs2_fwd are passed to EX/MEM1 register so that:
//   - ex_rs1_fwd feeds CSR write source (rs1_data field in mem1_stage)
//   - ex_rs2_fwd feeds store data (rs2_data field in mem1_stage)

module ex_stage (
    //── FROM ID/EX PIPELINE REGISTER ─────────────────────────────
    input  logic [31:0] idex_pc,
    input  logic [31:0] idex_rs1_data,   // Register file read (pre-bypass)
    input  logic [31:0] idex_rs2_data,   // Register file read (pre-bypass)
    input  logic [31:0] idex_imm,
    input  logic [4:0]  idex_rs1_addr,
    input  logic [4:0]  idex_rs2_addr,
    input  logic [3:0]  idex_alu_op,
    input  logic        idex_alu_src_a,  // 0=rs1, 1=PC
    input  logic        idex_alu_src_b,  // 0=rs2, 1=imm
    input  logic [2:0]  idex_funct3,
    input  logic        idex_branch,
    input  logic        idex_jump,
    input  logic        idex_jump_reg,   // 1=JALR (use rs1 as base, mask bit 0)

    //── FORWARDING SOURCE: GAP-1 (EX/MEM1 register output) ───────
    input  logic [4:0]  mem1_rd_addr,
    input  logic        mem1_reg_write,
    input  logic [31:0] mem1_alu_result,

    //── FORWARDING SOURCE: GAP-2 (MEM1/MEM2 reg + MEM2 stage) ───
    // wb_sel selects which value to forward: 2'b01=load rdata, else alu_result
    input  logic [4:0]  mem2_rd_addr,
    input  logic        mem2_reg_write,
    input  logic [1:0]  mem2_wb_sel,
    input  logic [31:0] mem2_alu_result,
    input  logic [31:0] mem2_mem_rdata,

    //── FORWARDING SOURCE: GAP-3 (WB stage write-back value) ─────
    input  logic [4:0]  wb_rd_addr,
    input  logic        wb_reg_write,
    input  logic [31:0] wb_wr_data,

    //── OUTPUTS: BYPASSED REGISTER VALUES ────────────────────────
    output logic [31:0] ex_rs1_fwd,      // Forwarded rs1 → EX/MEM1 rs1_data (CSR src)
    output logic [31:0] ex_rs2_fwd,      // Forwarded rs2 → EX/MEM1 rs2_data (store data)

    //── OUTPUTS: COMPUTATION RESULTS ─────────────────────────────
    output logic [31:0] ex_alu_result,
    output logic        ex_branch_taken,
    output logic [31:0] ex_jump_addr     // Branch/jump target → if1_stage (via hazard/zicsr mux)
);

    //=========================================================
    // 1. Forwarding Unit — select bypass path per operand
    //=========================================================
    logic [1:0] fwd_sel_a, fwd_sel_b;

    forwarding_unit u_fwd (
        .ex_rs1_addr    (idex_rs1_addr),    // input:  rs1 address at EX stage
        .ex_rs2_addr    (idex_rs2_addr),    // input:  rs2 address at EX stage
        .mem1_rd_addr   (mem1_rd_addr),     // input:  rd address at MEM1 (gap-1)
        .mem1_reg_write (mem1_reg_write),   // input:  MEM1 instruction writes rd
        .mem2_rd_addr   (mem2_rd_addr),     // input:  rd address at MEM2 (gap-2)
        .mem2_reg_write (mem2_reg_write),   // input:  MEM2 instruction writes rd
        .wb_rd_addr     (wb_rd_addr),       // input:  rd address at WB  (gap-3)
        .wb_reg_write   (wb_reg_write),     // input:  WB instruction writes rd
        .fwd_sel_a      (fwd_sel_a),        // output: bypass select for rs1
        .fwd_sel_b      (fwd_sel_b)         // output: bypass select for rs2
    );

    //=========================================================
    // 2. Forwarding Data Sources
    //=========================================================
    // Gap-2 MUX: load instructions forward mem_rdata; others forward alu_result
    logic [31:0] fwd_data_mem2;
    assign fwd_data_mem2 = (mem2_wb_sel == 2'b01) ? mem2_mem_rdata : mem2_alu_result;

    //=========================================================
    // 3. Forwarding MUX — resolve final operand values
    //    fwd_sel: 2'b00=register file, 01=MEM1, 10=MEM2, 11=WB
    //=========================================================
    always_comb begin
        case (fwd_sel_a)
            2'b01:   ex_rs1_fwd = mem1_alu_result;
            2'b10:   ex_rs1_fwd = fwd_data_mem2;
            2'b11:   ex_rs1_fwd = wb_wr_data;
            default: ex_rs1_fwd = idex_rs1_data;
        endcase
    end

    always_comb begin
        case (fwd_sel_b)
            2'b01:   ex_rs2_fwd = mem1_alu_result;
            2'b10:   ex_rs2_fwd = fwd_data_mem2;
            2'b11:   ex_rs2_fwd = wb_wr_data;
            default: ex_rs2_fwd = idex_rs2_data;
        endcase
    end

    //=========================================================
    // 4. ALU Input Select
    //    A: PC (AUIPC/JAL) or forwarded rs1 (everything else)
    //    B: imm (immediate-type) or forwarded rs2 (register-type)
    //=========================================================
    logic [31:0] ex_alu_a, ex_alu_b;
    assign ex_alu_a = idex_alu_src_a ? idex_pc     : ex_rs1_fwd;
    assign ex_alu_b = idex_alu_src_b ? idex_imm    : ex_rs2_fwd;

    //=========================================================
    // 5. ALU
    //=========================================================
    alu u_alu (
        .operand_a (ex_alu_a),        // input:  ALU operand A
        .operand_b (ex_alu_b),        // input:  ALU operand B
        .alu_op    (idex_alu_op),     // input:  operation select
        .alu_result(ex_alu_result)    // output: result → EX/MEM1 + forwarding
    );

    //=========================================================
    // 6. Branch Comparator
    //=========================================================
    branch_comp u_bcomp (
        .rs1_data    (ex_rs1_fwd),       // input:  forwarded rs1
        .rs2_data    (ex_rs2_fwd),       // input:  forwarded rs2
        .funct3      (idex_funct3),      // input:  branch type (BEQ/BNE/BLT/BGE/BLTU/BGEU)
        .branch      (idex_branch),      // input:  1 if B-type instruction
        .branch_taken(ex_branch_taken)   // output: 1 if branch condition true → hazard_unit
    );

    //=========================================================
    // 7. Address Adder (branch/jump target OR load/store address)
    //=========================================================
    addr_adder u_aadd (
        .pc      (idex_pc),          // input:  current PC (for branch/JAL)
        .rs1_data(ex_rs1_fwd),       // input:  forwarded rs1 (for JALR/load/store)
        .imm     (idex_imm),         // input:  sign-extended immediate
        .branch  (idex_branch),      // input:  1 if B-type
        .jump    (idex_jump),        // input:  1 if JAL or JALR
        .jump_reg(idex_jump_reg),    // input:  1 if JALR (mask bit[0] of result)
        .addr_out(ex_jump_addr)      // output: target address → if1_stage (via soc_top mux)
    );

endmodule
