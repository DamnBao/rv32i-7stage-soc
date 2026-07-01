`timescale 1ns/1ps

module tb_branch_comp;

    logic [31:0] rs1_data, rs2_data;
    logic [2:0]  funct3;
    logic        idex_branch;
    logic        actual_redirect;

    // Addr/prediction/jump ports — tied off; not exercised by comparison tests
    logic        idex_jump      = 1'b0;
    logic        idex_jump_reg  = 1'b0;
    logic [31:0] idex_pc        = 32'h0;
    logic [31:0] idex_imm       = 32'h0;
    logic        idex_bp_taken  = 1'b0;
    logic [31:0] idex_bp_target = 32'h0;
    logic        bus_stall_req  = 1'b0;
    logic [31:0] jump_addr;
    logic        bp_mismatch;
    logic [31:0] bp_correct_pc;
    logic        bp_update_en;

    branch_unit u_dut (
        .rs1_data       (rs1_data),
        .rs2_data       (rs2_data),
        .funct3         (funct3),
        .idex_branch    (idex_branch),
        .idex_jump      (idex_jump),
        .idex_jump_reg  (idex_jump_reg),
        .idex_pc        (idex_pc),
        .idex_imm       (idex_imm),
        .idex_bp_taken  (idex_bp_taken),
        .idex_bp_target (idex_bp_target),
        .bus_stall_req  (bus_stall_req),
        .jump_addr      (jump_addr),
        .actual_redirect(actual_redirect),
        .bp_mismatch    (bp_mismatch),
        .bp_correct_pc  (bp_correct_pc),
        .bp_update_en   (bp_update_en)
    );

    int pass_cnt = 0, fail_cnt = 0;

    task automatic check(
        input string name,
        input logic  actual,
        input logic  expected
    );
        if (actual === expected) begin
            $display("  PASS  %-40s got=%b", name, actual);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-40s expected=%b  got=%b", name, expected, actual);
            fail_cnt++;
        end
    endtask

    task automatic test(
        input string  name,
        input logic [2:0]  f3,
        input logic [31:0] a, b,
        input logic        br,
        input logic        expected
    );
        funct3       = f3;
        rs1_data     = a;
        rs2_data     = b;
        idex_branch  = br;
        #1;
        check(name, actual_redirect, expected);
    endtask

    initial begin
        $display("======= tb_branch_comp =======");

        // ── branch=0: luôn không taken ──
        $display("--- branch=0 gate ---");
        test("BEQ equal but branch=0",  3'b000, 32'd5, 32'd5, 1'b0, 1'b0);
        test("BNE diff  but branch=0",  3'b001, 32'd1, 32'd2, 1'b0, 1'b0);

        // ── BEQ (funct3=000) ──
        $display("--- BEQ ---");
        test("BEQ: a==b => taken",      3'b000, 32'd5,           32'd5,          1'b1, 1'b1);
        test("BEQ: a!=b => not taken",  3'b000, 32'd5,           32'd6,          1'b1, 1'b0);
        test("BEQ: 0==0 => taken",      3'b000, 32'd0,           32'd0,          1'b1, 1'b1);
        test("BEQ: neg==neg => taken",  3'b000, 32'hFFFF_FFFF,   32'hFFFF_FFFF,  1'b1, 1'b1);

        // ── BNE (funct3=001) ──
        $display("--- BNE ---");
        test("BNE: a!=b => taken",      3'b001, 32'd1,           32'd2,          1'b1, 1'b1);
        test("BNE: a==b => not taken",  3'b001, 32'd7,           32'd7,          1'b1, 1'b0);

        // ── BLT signed (funct3=100) ──
        $display("--- BLT (signed) ---");
        test("BLT: 1 < 2 => taken",     3'b100, 32'd1,           32'd2,          1'b1, 1'b1);
        test("BLT: 2 < 1 => not taken", 3'b100, 32'd2,           32'd1,          1'b1, 1'b0);
        test("BLT: 0==0 => not taken",  3'b100, 32'd0,           32'd0,          1'b1, 1'b0);
        test("BLT: -1 < 0 => taken",    3'b100, 32'hFFFF_FFFF,   32'd0,          1'b1, 1'b1);
        test("BLT: -2^31 < 1 => taken", 3'b100, 32'h8000_0000,   32'd1,          1'b1, 1'b1);
        test("BLT: 1 < -1 => not",      3'b100, 32'd1,           32'hFFFF_FFFF,  1'b1, 1'b0);

        // ── BGE signed (funct3=101) ──
        $display("--- BGE (signed) ---");
        test("BGE: 2 >= 1 => taken",    3'b101, 32'd2,           32'd1,          1'b1, 1'b1);
        test("BGE: 0 >= 0 => taken",    3'b101, 32'd0,           32'd0,          1'b1, 1'b1);
        test("BGE: -1 >= 0 => not",     3'b101, 32'hFFFF_FFFF,   32'd0,          1'b1, 1'b0);
        test("BGE: 1 >= -1 => taken",   3'b101, 32'd1,           32'hFFFF_FFFF,  1'b1, 1'b1);

        // ── BLTU unsigned (funct3=110) ──
        $display("--- BLTU (unsigned) ---");
        test("BLTU: 1 <u 2 => taken",   3'b110, 32'd1,           32'd2,          1'b1, 1'b1);
        test("BLTU: 2 <u 1 => not",     3'b110, 32'd2,           32'd1,          1'b1, 1'b0);
        test("BLTU: 0x80..0 <u 1 =>no", 3'b110, 32'h8000_0000,   32'd1,          1'b1, 1'b0);
        test("BLTU: 1 <u 0x80..0 =>yes",3'b110, 32'd1,           32'h8000_0000,  1'b1, 1'b1);

        // ── BGEU unsigned (funct3=111) ──
        $display("--- BGEU (unsigned) ---");
        test("BGEU: 2 >=u 1 => taken",  3'b111, 32'd2,           32'd1,          1'b1, 1'b1);
        test("BGEU: 0 >=u 0 => taken",  3'b111, 32'd0,           32'd0,          1'b1, 1'b1);
        test("BGEU: 0x80..0>=u 1 =>yes",3'b111, 32'h8000_0000,   32'd1,          1'b1, 1'b1);

        $display("==============================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_branch_comp: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_branch_comp: ALL PASSED");
        $finish;
    end

endmodule
