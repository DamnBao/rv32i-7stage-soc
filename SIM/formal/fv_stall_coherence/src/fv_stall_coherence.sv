// Formal verification: Pipeline Stall Coherence
//
// Proves that when hazard_unit asserts stall (but not flush) for a pipeline
// register, that register's outputs are UNCHANGED at the next clock edge.
//
// Three pipeline registers are checked in one wrapper:
//
//   P_IF1IF2_STALL : IF1/IF2 reg holds when stall_if1_if2=1 && flush_if1_if2=0
//   P_IF2ID_STALL  : IF2/ID  reg holds when stall_if2_id=1  && flush_if2_id=0
//   P_IDEX_STALL   : ID/EX   reg holds when stall_id_ex=1   && flush_id_ex=0
//                    (covers all fields: data + control + BP metadata)
//
// Two flush-correctness properties verify the NOP-bubble path:
//
//   P_IF1IF2_FLUSH : flush_if1_if2=1 → next cycle: pc=0, bp_taken=0, bp_target=0
//   P_IF2ID_FLUSH  : flush_if2_id=1  → next cycle: pc=0, instr=NOP, bp cleared
//
// One hazard_unit symmetry property:
//
//   P_STALL_SYMMETRY : stall_if1_if2 == stall_if2_id at all times
//                      (both derive from the same fetch_stall | bus_stall_req)
//
// All hazard_unit primary inputs are fully symbolic so the solver explores
// every possible hazard combination (load-use, CSR-use, bus stall, branch
// mismatch, trap flush).
//
// depth=8 is sufficient: $past()-based properties are proved at depth 2;
// extra depth gives the induction step more context.

`timescale 1ns/1ps
module fv_stall_coherence (
    input logic clk,
    input logic rst_n
);

    // ================================================================
    // 1.  Symbolic hazard_unit inputs
    // ================================================================
    logic        bus_stall_req;
    logic        ex_mem_read;
    logic [4:0]  ex_rd_addr;
    logic [1:0]  ex_wb_sel;
    logic        ex_reg_write;
    logic [1:0]  mem1_wb_sel;
    logic [4:0]  mem1_rd_addr;
    logic        mem1_reg_write;
    logic [1:0]  mem2_wb_sel;
    logic [4:0]  mem2_rd_addr;
    logic        mem2_reg_write;
    logic [4:0]  id_rs1_addr;
    logic [4:0]  id_rs2_addr;
    logic        bp_mismatch;
    logic        zicsr_flush;

    // ── hazard_unit outputs ───────────────────────────────────────
    logic stall_if1_if2, stall_if2_id, stall_id_ex;
    logic stall_ex_mem1, stall_mem1_mem2, stall_mem2_wb;
    logic flush_if1_if2, flush_if2_id, flush_id_ex;
    logic flush_ex_mem1, flush_mem1_mem2, flush_mem2_wb;
    logic stall_pc, flush_pc;

    hazard_unit u_hz (
        .bus_stall_req   (bus_stall_req),
        .ex_mem_read     (ex_mem_read),
        .ex_rd_addr      (ex_rd_addr),
        .ex_wb_sel       (ex_wb_sel),
        .ex_reg_write    (ex_reg_write),
        .mem1_wb_sel     (mem1_wb_sel),
        .mem1_rd_addr    (mem1_rd_addr),
        .mem1_reg_write  (mem1_reg_write),
        .mem2_wb_sel     (mem2_wb_sel),
        .mem2_rd_addr    (mem2_rd_addr),
        .mem2_reg_write  (mem2_reg_write),
        .id_rs1_addr     (id_rs1_addr),
        .id_rs2_addr     (id_rs2_addr),
        .bp_mismatch     (bp_mismatch),
        .zicsr_flush     (zicsr_flush),
        .stall_if1_if2   (stall_if1_if2),
        .stall_if2_id    (stall_if2_id),
        .stall_id_ex     (stall_id_ex),
        .stall_ex_mem1   (stall_ex_mem1),
        .stall_mem1_mem2 (stall_mem1_mem2),
        .stall_mem2_wb   (stall_mem2_wb),
        .flush_if1_if2   (flush_if1_if2),
        .flush_if2_id    (flush_if2_id),
        .flush_id_ex     (flush_id_ex),
        .flush_ex_mem1   (flush_ex_mem1),
        .flush_mem1_mem2 (flush_mem1_mem2),
        .flush_mem2_wb   (flush_mem2_wb),
        .stall_pc        (stall_pc),
        .flush_pc        (flush_pc)
    );

    // ── P_STALL_SYMMETRY: stall_if1_if2 and stall_if2_id are always equal.
    // Both are assigned (bus_stall_req | fetch_stall); a divergence would mean
    // one fetch stage freezes while the other advances — silent data corruption.
    always @(posedge clk) begin
        if (rst_n) begin
            assert(stall_if1_if2 == stall_if2_id);
            assert(flush_if1_if2 == flush_if2_id);
        end
    end

    // ================================================================
    // 2.  IF1/IF2 Pipeline Register
    // ================================================================
    logic [31:0] pc_if1, bp_target_if1;
    logic        bp_taken_if1;

    logic [31:0] pc_if2, bp_target_if2;
    logic        bp_taken_if2;

    if1_if2_reg u_if1if2 (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (stall_if1_if2),
        .flush        (flush_if1_if2),
        .pc_in        (pc_if1),
        .bp_taken_in  (bp_taken_if1),
        .bp_target_in (bp_target_if1),
        .pc_out       (pc_if2),
        .bp_taken_out (bp_taken_if2),
        .bp_target_out(bp_target_if2)
    );

    // P_IF1IF2_STALL: all outputs hold when stall=1 and flush=0 last cycle
    always @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(stall_if1_if2) && !$past(flush_if1_if2)) begin
                assert(pc_if2        == $past(pc_if2));
                assert(bp_taken_if2  == $past(bp_taken_if2));
                assert(bp_target_if2 == $past(bp_target_if2));
            end
        end
    end

    // P_IF1IF2_FLUSH: on flush, outputs clear to NOP (pc=0, bp cleared)
    always @(posedge clk) begin
        if (rst_n && $past(rst_n) && $past(flush_if1_if2)) begin
            assert(pc_if2        == 32'd0);
            assert(bp_taken_if2  == 1'b0);
            assert(bp_target_if2 == 32'd0);
        end
    end

    // ================================================================
    // 3.  IF2/ID Pipeline Register
    // ================================================================
    logic [31:0] pc_if2_in, instr_if2_in, bp_target_if2_in;
    logic        bp_taken_if2_in;

    logic [31:0] pc_id, instr_id, bp_target_id;
    logic        bp_taken_id;

    if2_id_reg u_if2id (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall        (stall_if2_id),
        .flush        (flush_if2_id),
        .pc_in        (pc_if2_in),
        .instr_in     (instr_if2_in),
        .bp_taken_in  (bp_taken_if2_in),
        .bp_target_in (bp_target_if2_in),
        .pc_out       (pc_id),
        .instr_out    (instr_id),
        .bp_taken_out (bp_taken_id),
        .bp_target_out(bp_target_id)
    );

    // P_IF2ID_STALL: all outputs hold when stall=1 and flush=0 last cycle
    always @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(stall_if2_id) && !$past(flush_if2_id)) begin
                assert(pc_id        == $past(pc_id));
                assert(instr_id     == $past(instr_id));
                assert(bp_taken_id  == $past(bp_taken_id));
                assert(bp_target_id == $past(bp_target_id));
            end
        end
    end

    // P_IF2ID_FLUSH: on flush, pc=0, instr=ADDI x0,x0,0 (NOP), bp cleared
    localparam [31:0] INSTR_NOP = 32'h0000_0013;
    always @(posedge clk) begin
        if (rst_n && $past(rst_n) && $past(flush_if2_id)) begin
            assert(pc_id        == 32'd0);
            assert(instr_id     == INSTR_NOP);
            assert(bp_taken_id  == 1'b0);
            assert(bp_target_id == 32'd0);
        end
    end

    // ================================================================
    // 4.  ID/EX Pipeline Register
    //     stall_id_ex = bus_stall_req only (load-use uses flush_id_ex).
    //     When stall=1 && flush=0: ALL fields must hold.
    // ================================================================
    logic [31:0] pc_ex_in, rs1_ex_in, rs2_ex_in, imm_ex_in, bp_tgt_ex_in;
    logic [4:0]  rs1a_ex_in, rs2a_ex_in, rd_ex_in;
    logic [11:0] csr_ex_in;
    logic [2:0]  fn3_ex_in;
    logic [3:0]  alu_op_ex_in;
    logic        alu_sa_in, alu_sb_in, br_in, jmp_in, jmpr_in;
    logic        mr_in, mw_in, me_in;
    logic [1:0]  ms_in;
    logic        rw_in, csr_we_in, csr_is_in, ec_in, eb_in, mret_in, ill_in, bpt_in;
    logic [1:0]  wb_in, cop_in;
    logic [31:0] bp_tgt_id_in;

    logic [31:0] pc_ex, rs1_ex, rs2_ex, imm_ex, bp_tgt_ex;
    logic [4:0]  rs1a_ex, rs2a_ex, rd_ex;
    logic [11:0] csr_ex;
    logic [2:0]  fn3_ex;
    logic [3:0]  alu_op_ex;
    logic        alu_sa, alu_sb, br_ex, jmp_ex, jmpr_ex;
    logic        mr_ex, mw_ex, me_ex;
    logic [1:0]  ms_ex;
    logic        rw_ex, csr_we_ex, csr_is_ex, ec_ex, eb_ex, mret_ex, ill_ex, bpt_ex;
    logic [1:0]  wb_ex, cop_ex;

    id_ex_reg u_idex (
        .clk              (clk),
        .rst_n            (rst_n),
        .stall            (stall_id_ex),
        .flush            (flush_id_ex),
        .pc_in            (pc_ex_in),
        .rs1_data_in      (rs1_ex_in),
        .rs2_data_in      (rs2_ex_in),
        .imm_in           (imm_ex_in),
        .rs1_addr_in      (rs1a_ex_in),
        .rs2_addr_in      (rs2a_ex_in),
        .rd_addr_in       (rd_ex_in),
        .csr_addr_in      (csr_ex_in),
        .funct3_in        (fn3_ex_in),
        .alu_op_in        (alu_op_ex_in),
        .alu_src_a_in     (alu_sa_in),
        .alu_src_b_in     (alu_sb_in),
        .branch_in        (br_in),
        .jump_in          (jmp_in),
        .jump_reg_in      (jmpr_in),
        .mem_read_in      (mr_in),
        .mem_write_in     (mw_in),
        .mem_size_in      (ms_in),
        .mem_ext_in       (me_in),
        .reg_write_in     (rw_in),
        .wb_sel_in        (wb_in),
        .csr_we_in        (csr_we_in),
        .csr_op_in        (cop_in),
        .csr_imm_sel_in   (csr_is_in),
        .ecall_in         (ec_in),
        .ebreak_in        (eb_in),
        .mret_in          (mret_in),
        .illegal_instr_in (ill_in),
        .bp_taken_in      (bpt_in),
        .bp_target_in     (bp_tgt_id_in),
        .pc_out           (pc_ex),
        .rs1_data_out     (rs1_ex),
        .rs2_data_out     (rs2_ex),
        .imm_out          (imm_ex),
        .rs1_addr_out     (rs1a_ex),
        .rs2_addr_out     (rs2a_ex),
        .rd_addr_out      (rd_ex),
        .csr_addr_out     (csr_ex),
        .funct3_out       (fn3_ex),
        .alu_op_out       (alu_op_ex),
        .alu_src_a_out    (alu_sa),
        .alu_src_b_out    (alu_sb),
        .branch_out       (br_ex),
        .jump_out         (jmp_ex),
        .jump_reg_out     (jmpr_ex),
        .mem_read_out     (mr_ex),
        .mem_write_out    (mw_ex),
        .mem_size_out     (ms_ex),
        .mem_ext_out      (me_ex),
        .reg_write_out    (rw_ex),
        .wb_sel_out       (wb_ex),
        .csr_we_out       (csr_we_ex),
        .csr_op_out       (cop_ex),
        .csr_imm_sel_out  (csr_is_ex),
        .ecall_out        (ec_ex),
        .ebreak_out       (eb_ex),
        .mret_out         (mret_ex),
        .illegal_instr_out(ill_ex),
        .bp_taken_out     (bpt_ex),
        .bp_target_out    (bp_tgt_ex)
    );

    // P_IDEX_STALL: when stall=1 and flush=0, ALL fields hold.
    // This covers every data and control field so no silent corruption
    // can occur in the instruction packet traversing the pipeline.
    always @(posedge clk) begin
        if (rst_n && $past(rst_n)) begin
            if ($past(stall_id_ex) && !$past(flush_id_ex)) begin
                // ── data fields ─────────────────────────────────────
                assert(pc_ex   == $past(pc_ex));
                assert(rs1_ex  == $past(rs1_ex));
                assert(rs2_ex  == $past(rs2_ex));
                assert(imm_ex  == $past(imm_ex));
                assert(rs1a_ex == $past(rs1a_ex));
                assert(rs2a_ex == $past(rs2a_ex));
                assert(rd_ex   == $past(rd_ex));
                assert(csr_ex  == $past(csr_ex));
                assert(fn3_ex  == $past(fn3_ex));
                // ── ALU / branch control ─────────────────────────────
                assert(alu_op_ex == $past(alu_op_ex));
                assert(alu_sa    == $past(alu_sa));
                assert(alu_sb    == $past(alu_sb));
                assert(br_ex     == $past(br_ex));
                assert(jmp_ex    == $past(jmp_ex));
                assert(jmpr_ex   == $past(jmpr_ex));
                // ── memory control ───────────────────────────────────
                assert(mr_ex == $past(mr_ex));
                assert(mw_ex == $past(mw_ex));
                assert(ms_ex == $past(ms_ex));
                assert(me_ex == $past(me_ex));
                // ── writeback / CSR / exception control ──────────────
                assert(rw_ex     == $past(rw_ex));
                assert(wb_ex     == $past(wb_ex));
                assert(csr_we_ex == $past(csr_we_ex));
                assert(cop_ex    == $past(cop_ex));
                assert(csr_is_ex == $past(csr_is_ex));
                assert(ec_ex     == $past(ec_ex));
                assert(eb_ex     == $past(eb_ex));
                assert(mret_ex   == $past(mret_ex));
                assert(ill_ex    == $past(ill_ex));
                // ── branch prediction metadata ───────────────────────
                assert(bpt_ex    == $past(bpt_ex));
                assert(bp_tgt_ex == $past(bp_tgt_ex));
            end
        end
    end

    // P_IDEX_FLUSH: on flush, all hazard-relevant control signals clear to 0.
    // (Data fields are intentionally left as-is; reg_write=0 prevents WB.)
    always @(posedge clk) begin
        if (rst_n && $past(rst_n) && $past(flush_id_ex)) begin
            assert(br_ex     == 1'b0);
            assert(jmp_ex    == 1'b0);
            assert(mr_ex     == 1'b0);
            assert(mw_ex     == 1'b0);
            assert(rw_ex     == 1'b0);
            assert(csr_we_ex == 1'b0);
            assert(ec_ex     == 1'b0);
            assert(eb_ex     == 1'b0);
            assert(mret_ex   == 1'b0);
            assert(ill_ex    == 1'b0);
        end
    end

    // Ensure the solver starts from a known reset state
    initial assume(!rst_n);

endmodule
