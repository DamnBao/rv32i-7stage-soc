`timescale 1ns/1ps

// Unit test for ex_stage: forwarding resolution, ALU input select, ALU,
// branch comparator, and address adder — all combinational.

module tb_ex_stage;

    // ── Inputs from ID/EX pipeline register ──────────────────────────────
    logic [31:0] idex_pc;
    logic [31:0] idex_rs1_data, idex_rs2_data, idex_imm;
    logic [4:0]  idex_rs1_addr, idex_rs2_addr;
    logic [3:0]  idex_alu_op;
    logic        idex_alu_src_a, idex_alu_src_b;
    logic [2:0]  idex_funct3;
    logic        idex_branch, idex_jump, idex_jump_reg;

    // ── Forwarding source: gap-1 (MEM1) ──────────────────────────────────
    logic [4:0]  mem1_rd_addr;
    logic        mem1_reg_write;
    logic [31:0] mem1_alu_result;

    // ── Forwarding source: gap-2 (MEM2) ──────────────────────────────────
    logic [4:0]  mem2_rd_addr;
    logic        mem2_reg_write;
    logic [1:0]  mem2_wb_sel;
    logic [31:0] mem2_alu_result, mem2_mem_rdata;

    // ── Forwarding source: gap-3 (WB) ────────────────────────────────────
    logic [4:0]  wb_rd_addr;
    logic        wb_reg_write;
    logic [31:0] wb_wr_data;

    // ── Outputs ───────────────────────────────────────────────────────────
    logic [31:0] ex_rs1_fwd, ex_rs2_fwd;
    logic [31:0] ex_alu_result;
    logic [31:0] ex_jump_addr;
    logic        ex_actual_redirect, bp_mismatch, bp_update_en;
    logic [31:0] bp_correct_pc;

    ex_stage u_dut (
        .idex_pc          (idex_pc),
        .idex_rs1_data    (idex_rs1_data),
        .idex_rs2_data    (idex_rs2_data),
        .idex_imm         (idex_imm),
        .idex_rs1_addr    (idex_rs1_addr),
        .idex_rs2_addr    (idex_rs2_addr),
        .idex_alu_op      (idex_alu_op),
        .idex_alu_src_a   (idex_alu_src_a),
        .idex_alu_src_b   (idex_alu_src_b),
        .idex_funct3      (idex_funct3),
        .idex_branch      (idex_branch),
        .idex_jump        (idex_jump),
        .idex_jump_reg    (idex_jump_reg),
        .idex_bp_taken    (1'b0),
        .idex_bp_target   (32'h0),
        .bus_stall_req    (1'b0),
        .mem1_rd_addr     (mem1_rd_addr),
        .mem1_reg_write   (mem1_reg_write),
        .mem1_alu_result  (mem1_alu_result),
        .mem2_rd_addr     (mem2_rd_addr),
        .mem2_reg_write   (mem2_reg_write),
        .mem2_wb_sel      (mem2_wb_sel),
        .mem2_alu_result  (mem2_alu_result),
        .mem2_mem_rdata   (mem2_mem_rdata),
        .wb_rd_addr       (wb_rd_addr),
        .wb_reg_write     (wb_reg_write),
        .wb_wr_data       (wb_wr_data),
        .ex_rs1_fwd       (ex_rs1_fwd),
        .ex_rs2_fwd       (ex_rs2_fwd),
        .ex_alu_result    (ex_alu_result),
        .ex_jump_addr     (ex_jump_addr),
        .ex_actual_redirect(ex_actual_redirect),
        .bp_mismatch      (bp_mismatch),
        .bp_correct_pc    (bp_correct_pc),
        .bp_update_en     (bp_update_en)
    );

    // ALU op constants (from alu.sv encoding)
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_PASSB= 4'd10;

    // Branch funct3 constants
    localparam BEQ  = 3'b000;
    localparam BNE  = 3'b001;
    localparam BLT  = 3'b100;

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk32(input string name, input logic [31:0] got, exp);
        if (got === exp) begin
            $display("  PASS  %-50s got=%08h", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-50s exp=%08h  got=%08h", name, exp, got);
            fail_cnt++;
        end
    endtask

    task automatic chk1(input string name, input logic got, exp);
        if (got === exp) begin
            $display("  PASS  %-50s got=%b", name, got);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-50s exp=%b  got=%b", name, exp, got);
            fail_cnt++;
        end
    endtask

    // Reset all inputs to a benign idle state
    task automatic idle();
        idex_pc        = 32'h0000_1000;
        idex_rs1_data  = 32'h0000_0010;  // x1 = 0x10
        idex_rs2_data  = 32'h0000_0020;  // x2 = 0x20
        idex_imm       = 32'd0;
        idex_rs1_addr  = 5'd1;
        idex_rs2_addr  = 5'd2;
        idex_alu_op    = ALU_ADD;
        idex_alu_src_a = 0;   // A = rs1
        idex_alu_src_b = 0;   // B = rs2
        idex_funct3    = BEQ;
        idex_branch    = 0;
        idex_jump      = 0;
        idex_jump_reg  = 0;
        mem1_rd_addr   = 5'd0;
        mem1_reg_write = 0;
        mem1_alu_result= 32'd0;
        mem2_rd_addr   = 5'd0;
        mem2_reg_write = 0;
        mem2_wb_sel    = 2'b00;
        mem2_alu_result= 32'd0;
        mem2_mem_rdata = 32'd0;
        wb_rd_addr     = 5'd0;
        wb_reg_write   = 0;
        wb_wr_data     = 32'd0;
        #1;
    endtask

    initial begin
        $display("======= tb_ex_stage =======");

        // ── Group 1: No forwarding — basic ALU and input select ──────────
        $display("--- G1: No forwarding ---");

        // T1: ADD using register file values (no forward)
        idle();
        idex_rs1_data = 32'h0000_0005;
        idex_rs2_data = 32'h0000_0003;
        idex_alu_op   = ALU_ADD;
        #1;
        chk32("T1: no-fwd ADD rs1_fwd=rs1_data",        ex_rs1_fwd,    32'h5);
        chk32("T1: no-fwd ADD rs2_fwd=rs2_data",        ex_rs2_fwd,    32'h3);
        chk32("T1: no-fwd ADD result=8",                 ex_alu_result, 32'h8);

        // T2: SUB
        idle();
        idex_rs1_data = 32'h0000_0010;
        idex_rs2_data = 32'h0000_0003;
        idex_alu_op   = ALU_SUB;
        #1;
        chk32("T2: no-fwd SUB result=0xD",               ex_alu_result, 32'hD);

        // T3: ALU src_b = imm (ADDI path)
        idle();
        idex_rs1_data  = 32'h0000_0064;  // 100
        idex_imm       = 32'h0000_0007;  // imm=7
        idex_alu_src_b = 1;              // B = imm
        idex_alu_op    = ALU_ADD;
        #1;
        chk32("T3: alu_src_b=imm ADD result=107",        ex_alu_result, 32'd107);

        // T4: ALU src_a = PC (AUIPC: PC + imm)
        idle();
        idex_pc        = 32'h0000_1000;
        idex_imm       = 32'h0001_0000;  // imm = 0x10000
        idex_alu_src_a = 1;              // A = PC
        idex_alu_src_b = 1;              // B = imm
        idex_alu_op    = ALU_ADD;
        #1;
        chk32("T4: alu_src_a=PC ADD result=PC+imm",      ex_alu_result, 32'h0001_1000);

        // ── Group 2: Forwarding paths ─────────────────────────────────────
        $display("--- G2: Forwarding ---");

        // T5: Gap-1 rs1 forward from MEM1
        idle();
        idex_rs1_addr  = 5'd3;
        idex_rs1_data  = 32'hDEAD_BEEF;  // stale RF value
        mem1_rd_addr   = 5'd3;           // match rs1
        mem1_reg_write = 1;
        mem1_alu_result= 32'hABCD_1234;  // gap-1 forward value
        #1;
        chk32("T5: gap-1 rs1 fwd from MEM1",             ex_rs1_fwd, 32'hABCD_1234);

        // T6: Gap-1 rs2 forward from MEM1
        idle();
        idex_rs2_addr  = 5'd5;
        idex_rs2_data  = 32'hDEAD_BEEF;  // stale
        mem1_rd_addr   = 5'd5;
        mem1_reg_write = 1;
        mem1_alu_result= 32'h0000_CAFE;
        #1;
        chk32("T6: gap-1 rs2 fwd from MEM1",             ex_rs2_fwd, 32'h0000_CAFE);

        // T7: Gap-2 rs1 from MEM2 ALU result (wb_sel != 01)
        idle();
        idex_rs1_addr  = 5'd4;
        idex_rs1_data  = 32'hDEAD_BEEF;
        mem2_rd_addr   = 5'd4;
        mem2_reg_write = 1;
        mem2_wb_sel    = 2'b00;         // not a load → use alu_result
        mem2_alu_result= 32'h1111_2222;
        mem2_mem_rdata = 32'hFFFF_FFFF; // should NOT be forwarded
        #1;
        chk32("T7: gap-2 rs1 fwd MEM2 ALU (wb_sel=00)",  ex_rs1_fwd, 32'h1111_2222);

        // T8: Gap-2 rs1 from MEM2 load rdata (wb_sel == 01)
        idle();
        idex_rs1_addr  = 5'd4;
        idex_rs1_data  = 32'hDEAD_BEEF;
        mem2_rd_addr   = 5'd4;
        mem2_reg_write = 1;
        mem2_wb_sel    = 2'b01;         // load → use mem_rdata
        mem2_alu_result= 32'hFFFF_FFFF; // should NOT be forwarded
        mem2_mem_rdata = 32'hBEEF_CAFE;
        #1;
        chk32("T8: gap-2 rs1 fwd MEM2 load (wb_sel=01)", ex_rs1_fwd, 32'hBEEF_CAFE);

        // T9: Gap-3 rs1 from WB
        idle();
        idex_rs1_addr  = 5'd6;
        idex_rs1_data  = 32'hDEAD_BEEF;
        wb_rd_addr     = 5'd6;
        wb_reg_write   = 1;
        wb_wr_data     = 32'hFACE_BABE;
        #1;
        chk32("T9: gap-3 rs1 fwd from WB",               ex_rs1_fwd, 32'hFACE_BABE);

        // T10: Priority — MEM1 wins over MEM2 when both match rs1
        idle();
        idex_rs1_addr  = 5'd7;
        mem1_rd_addr   = 5'd7; mem1_reg_write = 1; mem1_alu_result = 32'hAAAA_AAAA;
        mem2_rd_addr   = 5'd7; mem2_reg_write = 1; mem2_alu_result = 32'hBBBB_BBBB;
        #1;
        chk32("T10: priority MEM1>MEM2 for rs1",          ex_rs1_fwd, 32'hAAAA_AAAA);

        // T11: x0 not forwarded even if mem1 has rd=x0 reg_write=1
        idle();
        idex_rs1_addr  = 5'd0;      // rs1 = x0
        idex_rs1_data  = 32'd0;     // RF always returns 0 for x0
        mem1_rd_addr   = 5'd0;      // rd=x0 — should NOT forward
        mem1_reg_write = 1;
        mem1_alu_result= 32'hDEAD_BEEF;
        #1;
        chk32("T11: x0 not forwarded from MEM1",          ex_rs1_fwd, 32'd0);

        // ── Group 3: Branch and jump ──────────────────────────────────────
        $display("--- G3: Branch/Jump ---");

        // T12: BEQ taken (rs1 == rs2, both = 5)
        idle();
        idex_rs1_data  = 32'd5;
        idex_rs2_data  = 32'd5;
        idex_funct3    = BEQ;
        idex_branch    = 1;
        #1;
        chk1("T12: BEQ taken when rs1==rs2",              ex_actual_redirect, 1'b1);

        // T13: BEQ not taken (rs1 != rs2)
        idle();
        idex_rs1_data  = 32'd5;
        idex_rs2_data  = 32'd6;
        idex_funct3    = BEQ;
        idex_branch    = 1;
        #1;
        chk1("T13: BEQ not taken when rs1!=rs2",          ex_actual_redirect, 1'b0);

        // T14: BNE taken (rs1 != rs2)
        idle();
        idex_rs1_data  = 32'hAA;
        idex_rs2_data  = 32'hBB;
        idex_funct3    = BNE;
        idex_branch    = 1;
        #1;
        chk1("T14: BNE taken when rs1!=rs2",              ex_actual_redirect, 1'b1);

        // T15: Branch target = PC + imm (independent of taken/not-taken)
        idle();
        idex_pc        = 32'h0000_2000;
        idex_imm       = 32'h0000_0010;  // imm=16
        idex_branch    = 1;
        #1;
        chk32("T15: branch target = PC+imm",              ex_jump_addr, 32'h0000_2010);

        // T16: JAL target = PC + imm (jump=1, jump_reg=0)
        idle();
        idex_pc        = 32'h0000_4000;
        idex_imm       = 32'hFFFF_FFF0;  // imm=-16 (signed)
        idex_jump      = 1;
        idex_jump_reg  = 0;              // JAL
        #1;
        chk32("T16: JAL target = PC+(-16)",               ex_jump_addr, 32'h0000_3FF0);

        // T17: JALR target = rs1 + imm, bit[0] masked
        idle();
        idex_rs1_data  = 32'h0000_0100;
        idex_imm       = 32'h0000_000F;  // imm=15 → rs1+imm=0x10F → mask bit0 → 0x10E
        idex_jump      = 1;
        idex_jump_reg  = 1;              // JALR
        #1;
        chk32("T17: JALR target = (rs1+imm) & ~1",        ex_jump_addr, 32'h0000_010E);

        // T18: branch=0 → not taken even if condition true
        idle();
        idex_rs1_data  = 32'd7;
        idex_rs2_data  = 32'd7;
        idex_funct3    = BEQ;
        idex_branch    = 0;             // not a branch instruction
        #1;
        chk1("T18: branch=0 → not taken despite equal",   ex_actual_redirect, 1'b0);

        // ── Group 4: Forwarded value used in ALU / branch comp ───────────
        $display("--- G4: Combined forwarding + computation ---");

        // T19: Forward rs1 from MEM1, rs2 from RF → ADD
        idle();
        idex_rs1_addr  = 5'd8;
        idex_rs1_data  = 32'hDEAD_BEEF;  // stale
        idex_rs2_data  = 32'h0000_0010;
        mem1_rd_addr   = 5'd8;
        mem1_reg_write = 1;
        mem1_alu_result= 32'h0000_0050;  // forward value
        idex_alu_op    = ALU_ADD;
        #1;
        chk32("T19: fwd rs1 MEM1, ADD with rs2_rf",       ex_alu_result, 32'h0000_0060);

        // T20: Forward both rs1 and rs2 from MEM1 → BEQ taken
        idle();
        idex_rs1_addr  = 5'd9;
        idex_rs2_addr  = 5'd10;
        idex_rs1_data  = 32'hDEAD;  // stale
        idex_rs2_data  = 32'hBEEF;  // stale
        mem1_rd_addr   = 5'd9;      // only MEM1 can forward one at a time — test rs1
        mem1_reg_write = 1;
        mem1_alu_result= 32'h00AA;
        mem2_rd_addr   = 5'd10;     // MEM2 forward rs2
        mem2_reg_write = 1;
        mem2_wb_sel    = 2'b00;
        mem2_alu_result= 32'h00AA;  // same value → BEQ should be taken
        idex_funct3    = BEQ;
        idex_branch    = 1;
        #1;
        chk1("T20: fwd rs1=MEM1 rs2=MEM2 BEQ taken",     ex_actual_redirect, 1'b1);

        // T21: JALR target computed from forwarded rs1 (gap-3 WB)
        idle();
        idex_rs1_addr  = 5'd11;
        idex_rs1_data  = 32'hDEAD_BEEF;  // stale
        wb_rd_addr     = 5'd11;
        wb_reg_write   = 1;
        wb_wr_data     = 32'h0000_0200;
        idex_imm       = 32'h0000_0001;  // imm=1 → rs1+imm=0x201 → mask bit0 → 0x200
        idex_jump      = 1;
        idex_jump_reg  = 1;
        #1;
        chk32("T21: JALR target using gap-3 fwd rs1",     ex_jump_addr, 32'h0000_0200);

        $display("===========================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_ex_stage: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_ex_stage: ALL PASSED");
        $finish;
    end

endmodule
