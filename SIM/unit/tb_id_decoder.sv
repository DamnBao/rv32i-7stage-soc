`timescale 1ns/1ps
// Instruction encoding reference (RV32I):
//   R-type: funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]
//   I-type: imm[31:20]    | rs1[19:15] | funct3[14:12] | rd[11:7]   | opcode[6:0]
//   S-type: imm[31:25]    | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[11:7] | opcode[6:0]
//   B-type: imm[31:25]    | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[11:7] | opcode[6:0]
//   U-type: imm[31:12]    | rd[11:7]   | opcode[6:0]
//   J-type: imm[31:12]    | rd[11:7]   | opcode[6:0]

module tb_id_decoder;

    logic [31:0] instr;
    logic [4:0]  rs1_addr, rs2_addr, rd_addr;
    logic [11:0] csr_addr;
    logic [2:0]  funct3;
    logic [31:0] imm;
    logic [3:0]  alu_op;
    logic        alu_src_a, alu_src_b;
    logic        branch, jump, jump_reg;
    logic        mem_read, mem_write;
    logic [1:0]  mem_size;
    logic        mem_ext, reg_write;
    logic [1:0]  wb_sel, csr_op;
    logic        csr_we, csr_imm_sel;
    logic        ecall, ebreak, mret, illegal_instr;

    id_decoder u_dut (.*);

    // ALU op localparams (phải khớp với alu.sv)
    localparam ALU_ADD   = 4'd0,  ALU_SUB   = 4'd1,  ALU_SLL = 4'd2,
               ALU_SLT   = 4'd3,  ALU_SLTU  = 4'd4,  ALU_XOR = 4'd5,
               ALU_SRL   = 4'd6,  ALU_SRA   = 4'd7,  ALU_OR  = 4'd8,
               ALU_AND   = 4'd9,  ALU_PASSB = 4'd10;

    int pass_cnt = 0, fail_cnt = 0;

    task automatic chk1(input string name, input logic a, e);
        if (a === e) begin $display("  PASS  %s", name); pass_cnt++; end
        else begin $display("  FAIL  %-40s exp=%b got=%b", name, e, a); fail_cnt++; end
    endtask

    task automatic chk2(input string name, input logic [1:0] a, e);
        if (a === e) begin $display("  PASS  %s", name); pass_cnt++; end
        else begin $display("  FAIL  %-40s exp=%0d got=%0d", name, e, a); fail_cnt++; end
    endtask

    task automatic chk4(input string name, input logic [3:0] a, e);
        if (a === e) begin $display("  PASS  %s", name); pass_cnt++; end
        else begin $display("  FAIL  %-40s exp=%0d got=%0d", name, e, a); fail_cnt++; end
    endtask

    task automatic chk5(input string name, input logic [4:0] a, e);
        if (a === e) begin $display("  PASS  %s", name); pass_cnt++; end
        else begin $display("  FAIL  %-40s exp=0x%02X got=0x%02X", name, e, a); fail_cnt++; end
    endtask

    task automatic chk32(input string name, input logic [31:0] a, e);
        if (a === e) begin $display("  PASS  %s", name); pass_cnt++; end
        else begin $display("  FAIL  %-40s exp=0x%08X got=0x%08X", name, e, a); fail_cnt++; end
    endtask

    task automatic set_instr(input logic [31:0] i);
        instr = i; #1;
    endtask

    initial begin
        $display("======= tb_id_decoder =======");

        // ────────────────────────────────────────────────────
        // LUI x1, 0x12345 → instr = 0x1234_50B7
        // expected: alu_src_b=1, alu_op=PASSB, reg_write=1, wb_sel=00
        //           imm=0x12345000, rd=1
        // ────────────────────────────────────────────────────
        $display("--- LUI x1, 0x12345 ---");
        set_instr(32'h1234_50B7);
        chk5 ("rd=1",          rd_addr,   5'd1);
        chk1 ("alu_src_b=1",   alu_src_b, 1'b1);
        chk1 ("alu_src_a=0",   alu_src_a, 1'b0);
        chk4 ("alu_op=PASSB",  alu_op,    ALU_PASSB);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk2 ("wb_sel=00",     wb_sel,    2'b00);
        chk32("imm=0x12345000",imm,       32'h1234_5000);
        chk1 ("branch=0",      branch,    1'b0);
        chk1 ("jump=0",        jump,      1'b0);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // AUIPC x2, 0xABCDE → instr = 0xABCDE117 (rd=2)
        // expected: alu_src_a=1, alu_src_b=1, alu_op=ADD, reg_write=1
        // imm = 0xABCDE000
        // ────────────────────────────────────────────────────
        $display("--- AUIPC x2, 0xABCDE ---");
        set_instr(32'hABCDE117);
        chk5 ("rd=2",          rd_addr,   5'd2);
        chk1 ("alu_src_a=1",   alu_src_a, 1'b1);
        chk1 ("alu_src_b=1",   alu_src_b, 1'b1);
        chk4 ("alu_op=ADD",    alu_op,    ALU_ADD);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk32("imm=0xABCDE000",imm,       32'hABCDE000);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // JAL x1, +4 → instr = 0x0040_00EF
        // expected: jump=1, jump_reg=0, reg_write=1, wb_sel=10 (PC+4)
        // ────────────────────────────────────────────────────
        $display("--- JAL x1, +4 ---");
        set_instr(32'h0040_00EF);
        chk1 ("jump=1",        jump,      1'b1);
        chk1 ("jump_reg=0",    jump_reg,  1'b0);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk2 ("wb_sel=10",     wb_sel,    2'b10);
        chk1 ("branch=0",      branch,    1'b0);
        chk32("imm=4",         imm,       32'd4);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // JALR x1, x2, 4 → instr = 0x0041_00E7
        // expected: jump=1, jump_reg=1, reg_write=1, wb_sel=10
        // ────────────────────────────────────────────────────
        $display("--- JALR x1, x2, 4 ---");
        set_instr(32'h0041_00E7);
        chk1 ("jump=1",        jump,      1'b1);
        chk1 ("jump_reg=1",    jump_reg,  1'b1);
        chk5 ("rs1=2",         rs1_addr,  5'd2);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk2 ("wb_sel=10",     wb_sel,    2'b10);
        chk32("imm=4",         imm,       32'd4);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // BEQ x1, x2, +8 → instr = 0x0020_8463
        // expected: branch=1, reg_write=0, imm=8
        // ────────────────────────────────────────────────────
        $display("--- BEQ x1, x2, +8 ---");
        set_instr(32'h0020_8463);
        chk1 ("branch=1",      branch,    1'b1);
        chk1 ("jump=0",        jump,      1'b0);
        chk1 ("reg_write=0",   reg_write, 1'b0);
        chk5 ("rs1=1",         rs1_addr,  5'd1);
        chk5 ("rs2=2",         rs2_addr,  5'd2);
        chk32("imm=8",         imm,       32'd8);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // LW x5, 8(x2) → instr = 0x0081_2283
        // expected: mem_read=1, reg_write=1, wb_sel=01, mem_size=10(word)
        //           mem_ext=0 (LW không dùng ext), alu_src_b=1, imm=8
        // ────────────────────────────────────────────────────
        $display("--- LW x5, 8(x2) ---");
        set_instr(32'h0081_2283);
        chk1 ("mem_read=1",    mem_read,  1'b1);
        chk1 ("mem_write=0",   mem_write, 1'b0);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk2 ("wb_sel=01",     wb_sel,    2'b01);
        chk2 ("mem_size=10",   mem_size,  2'b10); // word
        chk1 ("alu_src_b=1",   alu_src_b, 1'b1);
        chk5 ("rs1=2",         rs1_addr,  5'd2);
        chk5 ("rd=5",          rd_addr,   5'd5);
        chk32("imm=8",         imm,       32'd8);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // LH x1, 4(x3) → funct3=001, mem_size=01, mem_ext=1 (sign-ext)
        // instr: {12'd4, 5'd3, 3'b001, 5'd1, 7'b0000011}
        // ────────────────────────────────────────────────────
        $display("--- LH x1, 4(x3) ---");
        set_instr({12'd4, 5'd3, 3'b001, 5'd1, 7'b0000011});
        chk2 ("mem_size=01",   mem_size,  2'b01);  // halfword
        chk1 ("mem_ext=1",     mem_ext,   1'b1);   // signed

        // LHU x1, 4(x3) → funct3=101, mem_ext=0 (zero-ext)
        $display("--- LHU x1, 4(x3) ---");
        set_instr({12'd4, 5'd3, 3'b101, 5'd1, 7'b0000011});
        chk2 ("mem_size=01",   mem_size,  2'b01);  // halfword
        chk1 ("mem_ext=0",     mem_ext,   1'b0);   // unsigned

        // ────────────────────────────────────────────────────
        // SW x3, 12(x1) → instr = 0x0030_A623
        // expected: mem_write=1, reg_write=0, imm=12
        // ────────────────────────────────────────────────────
        $display("--- SW x3, 12(x1) ---");
        set_instr(32'h0030_A623);
        chk1 ("mem_write=1",   mem_write, 1'b1);
        chk1 ("mem_read=0",    mem_read,  1'b0);
        chk1 ("reg_write=0",   reg_write, 1'b0);
        chk5 ("rs1=1",         rs1_addr,  5'd1);
        chk5 ("rs2=3",         rs2_addr,  5'd3);
        chk32("imm=12",        imm,       32'd12);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // ADDI x3, x1, 42 → instr = 0x02A0_8193
        // expected: alu_src_b=1, alu_op=ADD, reg_write=1, imm=42
        // ────────────────────────────────────────────────────
        $display("--- ADDI x3, x1, 42 ---");
        set_instr(32'h02A0_8193);
        chk1 ("alu_src_b=1",   alu_src_b, 1'b1);
        chk1 ("alu_src_a=0",   alu_src_a, 1'b0);
        chk4 ("alu_op=ADD",    alu_op,    ALU_ADD);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk5 ("rs1=1",         rs1_addr,  5'd1);
        chk5 ("rd=3",          rd_addr,   5'd3);
        chk32("imm=42",        imm,       32'd42);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // SRAI x4, x5, 3 → funct7=0100000, funct3=101
        // instr: {7'b0100000, 5'd3, 5'd5, 3'b101, 5'd4, 7'b0010011}
        $display("--- SRAI x4, x5, 3 ---");
        set_instr({7'b0100000, 5'd3, 5'd5, 3'b101, 5'd4, 7'b0010011});
        chk4 ("alu_op=SRA",    alu_op,    ALU_SRA);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // SLLI con funct7 sai → phải báo illegal
        $display("--- SLLI with bad funct7 → illegal ---");
        set_instr({7'b0100000, 5'd3, 5'd5, 3'b001, 5'd4, 7'b0010011});
        chk1 ("illegal=1",     illegal_instr, 1'b1);

        // ────────────────────────────────────────────────────
        // ADD x4, x2, x3 → 0x0031_0233
        // ────────────────────────────────────────────────────
        $display("--- ADD x4, x2, x3 ---");
        set_instr(32'h0031_0233);
        chk4 ("alu_op=ADD",    alu_op,    ALU_ADD);
        chk1 ("alu_src_b=0",   alu_src_b, 1'b0);
        chk1 ("reg_write=1",   reg_write, 1'b1);
        chk5 ("rs1=2",         rs1_addr,  5'd2);
        chk5 ("rs2=3",         rs2_addr,  5'd3);
        chk5 ("rd=4",          rd_addr,   5'd4);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // SUB x5, x1, x2 → 0x4020_82B3
        $display("--- SUB x5, x1, x2 ---");
        set_instr(32'h4020_82B3);
        chk4 ("alu_op=SUB",    alu_op,    ALU_SUB);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ADD con funct7 sai → illegal
        $display("--- ADD with bad funct7 → illegal ---");
        set_instr({7'b0010000, 5'd2, 5'd1, 3'b000, 5'd1, 7'b0110011});
        chk1 ("illegal=1",     illegal_instr, 1'b1);

        // ────────────────────────────────────────────────────
        // ECALL → 0x0000_0073
        // ────────────────────────────────────────────────────
        $display("--- ECALL ---");
        set_instr(32'h0000_0073);
        chk1 ("ecall=1",       ecall,     1'b1);
        chk1 ("ebreak=0",      ebreak,    1'b0);
        chk1 ("mret=0",        mret,      1'b0);
        chk1 ("reg_write=0",   reg_write, 1'b0);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // EBREAK → 0x0010_0073
        // ────────────────────────────────────────────────────
        $display("--- EBREAK ---");
        set_instr(32'h0010_0073);
        chk1 ("ebreak=1",      ebreak,    1'b1);
        chk1 ("ecall=0",       ecall,     1'b0);
        chk1 ("reg_write=0",   reg_write, 1'b0);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // MRET → 0x3020_0073
        // ────────────────────────────────────────────────────
        $display("--- MRET ---");
        set_instr(32'h3020_0073);
        chk1 ("mret=1",        mret,      1'b1);
        chk1 ("ecall=0",       ecall,     1'b0);
        chk1 ("reg_write=0",   reg_write, 1'b0);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // CSRRW x1, mstatus, x2 → 0x3001_10F3
        // expected: csr_we=1, csr_op=01(RW), wb_sel=11, reg_write=1
        //           csr_imm_sel=0 (dùng rs1)
        // ────────────────────────────────────────────────────
        $display("--- CSRRW x1, mstatus, x2 ---");
        set_instr(32'h3001_10F3);
        chk1 ("csr_we=1",      csr_we,       1'b1);
        chk2 ("csr_op=01 RW",  csr_op,       2'b01);
        chk2 ("wb_sel=11",     wb_sel,        2'b11);
        chk1 ("reg_write=1",   reg_write,    1'b1);
        chk1 ("csr_imm_sel=0", csr_imm_sel,  1'b0);
        chk1 ("illegal=0",     illegal_instr, 1'b0);

        // ────────────────────────────────────────────────────
        // CSRRS x1, mie, x2 → csr_op=10, csr_we=1 (rs1≠0)
        // instr: {12'h304, 5'd2, 3'b010, 5'd1, 7'b1110011}
        // ────────────────────────────────────────────────────
        $display("--- CSRRS x1, mie, x2 (rs1=x2, csr_we=1) ---");
        set_instr({12'h304, 5'd2, 3'b010, 5'd1, 7'b1110011});
        chk1 ("csr_we=1",      csr_we,       1'b1);
        chk2 ("csr_op=10 RS",  csr_op,       2'b10);

        // ────────────────────────────────────────────────────
        // BUG FIX VERIFY: CSRRS x1, mie, x0 (rs1=x0) → csr_we=0 (spec §9.1)
        // instr: {12'h304, 5'd0, 3'b010, 5'd1, 7'b1110011}
        // ────────────────────────────────────────────────────
        $display("--- CSRRS x1, mie, x0 (rs1=x0 → csr_we=0) ---");
        set_instr({12'h304, 5'd0, 3'b010, 5'd1, 7'b1110011});
        chk1 ("csr_we=0 (suppressed)", csr_we, 1'b0);
        chk2 ("csr_op=10",     csr_op,       2'b10);
        chk1 ("reg_write=1",   reg_write,    1'b1);  // rd vẫn được đọc CSR

        // CSRRC x1, mie, x0 → csr_we=0
        $display("--- CSRRC x1, mie, x0 (rs1=x0 → csr_we=0) ---");
        set_instr({12'h304, 5'd0, 3'b011, 5'd1, 7'b1110011});
        chk1 ("csr_we=0 (suppressed)", csr_we, 1'b0);
        chk2 ("csr_op=11",     csr_op,       2'b11);

        // ────────────────────────────────────────────────────
        // CSRRWI x1, mtvec, 8 → csr_imm_sel=1, imm=zimm=8
        // instr: {12'h305, 5'd8, 3'b101, 5'd1, 7'b1110011}
        //   instr[14]=1 → csr_imm_sel=1; instr[19:15]=8 → zimm
        // ────────────────────────────────────────────────────
        $display("--- CSRRWI x1, mtvec, 8 ---");
        set_instr({12'h305, 5'd8, 3'b101, 5'd1, 7'b1110011});
        chk1 ("csr_imm_sel=1", csr_imm_sel,  1'b1);
        chk2 ("csr_op=01",     csr_op,       2'b01);
        chk1 ("csr_we=1",      csr_we,       1'b1);
        // imm = zimm = {27'd0, instr[19:15]} = 8
        chk32("imm=8 (zimm)",  imm,           32'd8);

        // ────────────────────────────────────────────────────
        // Illegal opcode → illegal_instr=1
        // ────────────────────────────────────────────────────
        $display("--- Illegal opcode 0xFFFF_FFFF ---");
        set_instr(32'hFFFF_FFFF);
        chk1 ("illegal=1",     illegal_instr, 1'b1);
        chk1 ("reg_write=0",   reg_write,    1'b0);

        $display("=================================");
        $display("RESULT: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0)
            $fatal(1, "tb_id_decoder: %0d test(s) FAILED", fail_cnt);
        else
            $display("tb_id_decoder: ALL PASSED");
        $finish;
    end

endmodule
