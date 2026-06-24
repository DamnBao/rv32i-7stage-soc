`timescale 1ns/1ps

module tb_alu;

    logic [31:0] operand_a, operand_b, alu_result;
    logic [3:0]  alu_op;

    alu u_dut (
        .operand_a  (operand_a),
        .operand_b  (operand_b),
        .alu_op     (alu_op),
        .alu_result (alu_result)
    );

    // ALU op encoding (khớp với alu.sv)
    localparam ADD   = 4'd0,  SUB   = 4'd1,  SLL   = 4'd2,
               SLT   = 4'd3,  SLTU  = 4'd4,  XOR   = 4'd5,
               SRL   = 4'd6,  SRA   = 4'd7,  OR    = 4'd8,
               AND   = 4'd9,  PASSB = 4'd10;

    int pass_cnt = 0, fail_cnt = 0;

    task automatic check(
        input string  name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual === expected) begin
            $display("  PASS  %-30s got=0x%08X", name, actual);
            pass_cnt++;
        end else begin
            $display("  FAIL  %-30s expected=0x%08X  got=0x%08X",
                     name, expected, actual);
            fail_cnt++;
        end
    endtask

    // Helper: drive và check (propagate #1 cho combinational)
    task automatic test(
        input string  name,
        input logic [3:0]  op,
        input logic [31:0] a, b,
        input logic [31:0] expected
    );
        alu_op    = op;
        operand_a = a;
        operand_b = b;
        #1;
        check(name, alu_result, expected);
    endtask

    initial begin
        $display("======= tb_alu =======");

        // ── ADD ──
        $display("--- ADD ---");
        test("5 + 3",              ADD, 32'd5,           32'd3,          32'd8);
        test("0 + 0",              ADD, 32'd0,           32'd0,          32'd0);
        test("overflow FF..F+1",   ADD, 32'hFFFF_FFFF,  32'd1,          32'd0);
        test("max + max",          ADD, 32'hFFFF_FFFF,  32'hFFFF_FFFF,  32'hFFFF_FFFE);

        // ── SUB ──
        $display("--- SUB ---");
        test("5 - 3",              SUB, 32'd5,           32'd3,          32'd2);
        test("0 - 1 (underflow)",  SUB, 32'd0,           32'd1,          32'hFFFF_FFFF);
        test("x - x = 0",         SUB, 32'hABCD_1234,  32'hABCD_1234,  32'd0);

        // ── SLL (Shift Left Logical) ──
        $display("--- SLL ---");
        test("1 << 0",             SLL, 32'd1,           32'd0,          32'd1);
        test("1 << 1",             SLL, 32'd1,           32'd1,          32'd2);
        test("1 << 31",            SLL, 32'd1,           32'd31,         32'h8000_0000);
        test("shamt only 5 bits",  SLL, 32'd1,           32'd32,         32'd1);  // 32 & 0x1F = 0

        // ── SRL (Shift Right Logical) ──
        $display("--- SRL ---");
        test("8 >> 1",             SRL, 32'd8,           32'd1,          32'd4);
        test("0x8000_0000 >> 1",   SRL, 32'h8000_0000,  32'd1,          32'h4000_0000);
        test("0xFFFF_FFFF >> 4",   SRL, 32'hFFFF_FFFF,  32'd4,          32'h0FFF_FFFF);
        test("shamt only 5 bits",  SRL, 32'hFFFF_FFFF,  32'd32,         32'hFFFF_FFFF); // shift 0

        // ── SRA (Shift Right Arithmetic) ──
        $display("--- SRA ---");
        test("4 >>> 1 (pos)",      SRA, 32'd4,           32'd1,          32'd2);
        test("0x8000_0000 >>> 1",  SRA, 32'h8000_0000,  32'd1,          32'hC000_0000);
        test("0x8000_0000 >>> 31", SRA, 32'h8000_0000,  32'd31,         32'hFFFF_FFFF);
        test("0xFFFF_FFFF >>> 1",  SRA, 32'hFFFF_FFFF,  32'd1,          32'hFFFF_FFFF);

        // ── SLT (Set Less Than, Signed) ──
        $display("--- SLT ---");
        test("1 < 2 => 1",         SLT, 32'd1,           32'd2,          32'd1);
        test("2 < 1 => 0",         SLT, 32'd2,           32'd1,          32'd0);
        test("0 < 0 => 0",         SLT, 32'd0,           32'd0,          32'd0);
        test("-1 < 0 => 1",        SLT, 32'hFFFF_FFFF,  32'd0,          32'd1);
        test("0x8000_0000 < 1=>1", SLT, 32'h8000_0000,  32'd1,          32'd1); // -2^31 < 1

        // ── SLTU (Set Less Than Unsigned) ──
        $display("--- SLTU ---");
        test("1 <u 2 => 1",        SLTU, 32'd1,          32'd2,          32'd1);
        test("2 <u 1 => 0",        SLTU, 32'd2,          32'd1,          32'd0);
        test("0x8000_0000<u 1=>0", SLTU, 32'h8000_0000, 32'd1,          32'd0); // 2^31 > 1 unsigned

        // ── XOR ──
        $display("--- XOR ---");
        test("0xF0 ^ 0x0F",        XOR, 32'h0000_00F0,  32'h0000_000F,  32'h0000_00FF);
        test("x ^ x = 0",          XOR, 32'hDEAD_BEEF,  32'hDEAD_BEEF,  32'd0);
        test("x ^ 0 = x",          XOR, 32'hABCD_1234,  32'd0,          32'hABCD_1234);

        // ── OR ──
        $display("--- OR ---");
        test("0xF0 | 0x0F",        OR,  32'h0000_00F0,  32'h0000_000F,  32'h0000_00FF);
        test("x | 0 = x",          OR,  32'hABCD_1234,  32'd0,          32'hABCD_1234);
        test("x | F..F = F..F",    OR,  32'h0000_0000,  32'hFFFF_FFFF,  32'hFFFF_FFFF);

        // ── AND ──
        $display("--- AND ---");
        test("0xFF & 0x0F",        AND, 32'h0000_00FF,  32'h0000_000F,  32'h0000_000F);
        test("x & 0 = 0",          AND, 32'hFFFF_FFFF,  32'd0,          32'd0);
        test("x & F..F = x",       AND, 32'hABCD_1234,  32'hFFFF_FFFF,  32'hABCD_1234);

        // ── PASSB (dành cho LUI) ──
        $display("--- PASSB ---");
        test("passb: a ignored",   PASSB, 32'hDEAD_BEEF, 32'hABCD_1234, 32'hABCD_1234);
        test("passb: b=0",         PASSB, 32'hFFFF_FFFF,  32'd0,         32'd0);

        // ── Kết quả ──
        $display("=======================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_alu: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_alu: ALL PASSED");
        $finish;
    end

endmodule
