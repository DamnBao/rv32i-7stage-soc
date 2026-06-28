# Testcase Documentation — RISC-V RV32I SoC (Luận Văn)

Tài liệu này liệt kê chi tiết từng testcase trong mỗi testbench, tương ứng với Sheet 10 của Excel.md (Test Phase Summary).

**Mức độ quan trọng:**
- **Critical** — Sai là fail toàn bộ design; kiểm tra tính đúng đắn ISA cốt lõi
- **High** — Bao gồm corner case, edge case, hoặc tính năng thiết yếu
- **Medium** — Bao gồm các tình huống đặc biệt, không ảnh hưởng golden path
- **Low** — Sanity check, kiểm tra hiển nhiên

**Cột Status:** PASS / FAIL / SKIP

---

---

## ═══ PHẦN 1: UNIT TESTS ═══

Mỗi section kiểm tra một module độc lập.

---

## 1.1 CPU Core — tb_alu · tb_branch_comp · tb_register_file · tb_id_decoder

### 1.1 tb_alu — ALU Unit Test

**Module under test:** `RTL/alu.sv`
**Số testcase:** 38 (mỗi `test()` = 1 testcase)
**Kết quả tổng:** 38/38 PASS

| TC# | Tên testcase              | Group  | Operand A    | Operand B    | alu_op | Kết quả kỳ vọng | Kết quả có được | Status | Mức độ |
|-----|--------------------------|--------|--------------|--------------|--------|-----------------|-----------------|--------|--------|
| 1   | 5 + 3                    | ADD    | 0x00000005   | 0x00000003   | 0000   | 0x00000008      | 0x00000008      | PASS   | Critical |
| 2   | 0 + 0                    | ADD    | 0x00000000   | 0x00000000   | 0000   | 0x00000000      | 0x00000000      | PASS   | High |
| 3   | 0xFFFFFFFF + 1 (overflow)| ADD    | 0xFFFFFFFF   | 0x00000001   | 0000   | 0x00000000      | 0x00000000      | PASS   | Critical |
| 4   | 0xFFFFFFFF + 0xFFFFFFFF  | ADD    | 0xFFFFFFFF   | 0xFFFFFFFF   | 0000   | 0xFFFFFFFE      | 0xFFFFFFFE      | PASS   | High |
| 5   | 5 - 3                    | SUB    | 0x00000005   | 0x00000003   | 0001   | 0x00000002      | 0x00000002      | PASS   | Critical |
| 6   | 0 - 1 (underflow)        | SUB    | 0x00000000   | 0x00000001   | 0001   | 0xFFFFFFFF      | 0xFFFFFFFF      | PASS   | Critical |
| 7   | x - x = 0               | SUB    | 0xABCD1234   | 0xABCD1234   | 0001   | 0x00000000      | 0x00000000      | PASS   | High |
| 8   | 1 << 0                   | SLL    | 0x00000001   | 0x00000000   | 0010   | 0x00000001      | 0x00000001      | PASS   | Critical |
| 9   | 1 << 1                   | SLL    | 0x00000001   | 0x00000001   | 0010   | 0x00000002      | 0x00000002      | PASS   | Critical |
| 10  | 1 << 31                  | SLL    | 0x00000001   | 0x0000001F   | 0010   | 0x80000000      | 0x80000000      | PASS   | Critical |
| 11  | SLL shamt 5 bits only (32→0) | SLL | 0x00000001  | 0x00000020   | 0010   | 0x00000001      | 0x00000001      | PASS   | High |
| 12  | 8 >> 1                   | SRL    | 0x00000008   | 0x00000001   | 0110   | 0x00000004      | 0x00000004      | PASS   | Critical |
| 13  | 0x80000000 >> 1 (MSB clear)| SRL  | 0x80000000   | 0x00000001   | 0110   | 0x40000000      | 0x40000000      | PASS   | Critical |
| 14  | 0xFFFFFFFF >> 4          | SRL    | 0xFFFFFFFF   | 0x00000004   | 0110   | 0x0FFFFFFF      | 0x0FFFFFFF      | PASS   | High |
| 15  | SRL shamt 5 bits only (32→0) | SRL | 0xFFFFFFFF  | 0x00000020   | 0110   | 0xFFFFFFFF      | 0xFFFFFFFF      | PASS   | High |
| 16  | 4 >>> 1 (positive)       | SRA    | 0x00000004   | 0x00000001   | 0111   | 0x00000002      | 0x00000002      | PASS   | Critical |
| 17  | 0x80000000 >>> 1 (sign ext)| SRA  | 0x80000000   | 0x00000001   | 0111   | 0xC0000000      | 0xC0000000      | PASS   | Critical |
| 18  | 0x80000000 >>> 31        | SRA    | 0x80000000   | 0x0000001F   | 0111   | 0xFFFFFFFF      | 0xFFFFFFFF      | PASS   | Critical |
| 19  | 0xFFFFFFFF >>> 1 (all ones)| SRA  | 0xFFFFFFFF   | 0x00000001   | 0111   | 0xFFFFFFFF      | 0xFFFFFFFF      | PASS   | High |
| 20  | 1 < 2 (signed) → 1      | SLT    | 0x00000001   | 0x00000002   | 0011   | 0x00000001      | 0x00000001      | PASS   | Critical |
| 21  | 2 < 1 (signed) → 0      | SLT    | 0x00000002   | 0x00000001   | 0011   | 0x00000000      | 0x00000000      | PASS   | Critical |
| 22  | 0 < 0 → 0               | SLT    | 0x00000000   | 0x00000000   | 0011   | 0x00000000      | 0x00000000      | PASS   | High |
| 23  | -1 < 0 (signed) → 1     | SLT    | 0xFFFFFFFF   | 0x00000000   | 0011   | 0x00000001      | 0x00000001      | PASS   | Critical |
| 24  | 0x80000000 < 1 (-2^31 signed)| SLT | 0x80000000  | 0x00000001   | 0011   | 0x00000001      | 0x00000001      | PASS   | Critical |
| 25  | 1 <u 2 (unsigned) → 1   | SLTU   | 0x00000001   | 0x00000002   | 0100   | 0x00000001      | 0x00000001      | PASS   | Critical |
| 26  | 2 <u 1 → 0              | SLTU   | 0x00000002   | 0x00000001   | 0100   | 0x00000000      | 0x00000000      | PASS   | Critical |
| 27  | 0x80000000 <u 1 → 0 (unsigned 2^31 > 1) | SLTU | 0x80000000 | 0x00000001 | 0100 | 0x00000000 | 0x00000000 | PASS | Critical |
| 28  | 0xF0 XOR 0x0F            | XOR    | 0x000000F0   | 0x0000000F   | 0101   | 0x000000FF      | 0x000000FF      | PASS   | Critical |
| 29  | x XOR x = 0             | XOR    | 0xDEADBEEF   | 0xDEADBEEF   | 0101   | 0x00000000      | 0x00000000      | PASS   | High |
| 30  | x XOR 0 = x             | XOR    | 0xABCD1234   | 0x00000000   | 0101   | 0xABCD1234      | 0xABCD1234      | PASS   | Medium |
| 31  | 0xF0 OR 0x0F            | OR     | 0x000000F0   | 0x0000000F   | 1000   | 0x000000FF      | 0x000000FF      | PASS   | Critical |
| 32  | x OR 0 = x              | OR     | 0xABCD1234   | 0x00000000   | 1000   | 0xABCD1234      | 0xABCD1234      | PASS   | Medium |
| 33  | 0 OR 0xFFFFFFFF = 0xFFFFFFFF | OR  | 0x00000000   | 0xFFFFFFFF   | 1000   | 0xFFFFFFFF      | 0xFFFFFFFF      | PASS   | Medium |
| 34  | 0xFF AND 0x0F           | AND    | 0x000000FF   | 0x0000000F   | 1001   | 0x0000000F      | 0x0000000F      | PASS   | Critical |
| 35  | x AND 0 = 0             | AND    | 0xFFFFFFFF   | 0x00000000   | 1001   | 0x00000000      | 0x00000000      | PASS   | Medium |
| 36  | x AND 0xFFFFFFFF = x    | AND    | 0xABCD1234   | 0xFFFFFFFF   | 1001   | 0xABCD1234      | 0xABCD1234      | PASS   | Medium |
| 37  | PASSB: operand_a bị bỏ qua | PASSB | 0xDEADBEEF | 0xABCD1234   | 1010   | 0xABCD1234      | 0xABCD1234      | PASS   | Critical |
| 38  | PASSB: b = 0            | PASSB  | 0xFFFFFFFF   | 0x00000000   | 1010   | 0x00000000      | 0x00000000      | PASS   | High |

---

### 1.2 tb_branch_comp — Branch Comparator Unit Test

**Module under test:** `RTL/branch_comp.sv`
**Số testcase:** 25 (mỗi `test()` = 1 testcase)
**Kết quả tổng:** 25/25 PASS

| TC# | Tên testcase                         | funct3 | rs1          | rs2          | branch | Kỳ vọng branch_taken | Có được | Status | Mức độ |
|-----|-------------------------------------|--------|--------------|--------------|--------|----------------------|---------|--------|--------|
| 1   | branch=0 gate: BEQ equal nhưng branch=0 | 000 | 0x00000005 | 0x00000005 | 0      | 0                    | 0       | PASS   | Critical |
| 2   | branch=0 gate: BNE diff nhưng branch=0  | 001 | 0x00000001 | 0x00000002 | 0      | 0                    | 0       | PASS   | Critical |
| 3   | BEQ: a == b → taken                  | 000    | 0x00000005   | 0x00000005   | 1      | 1                    | 1       | PASS   | Critical |
| 4   | BEQ: a != b → not taken              | 000    | 0x00000005   | 0x00000006   | 1      | 0                    | 0       | PASS   | Critical |
| 5   | BEQ: 0 == 0 → taken                  | 000    | 0x00000000   | 0x00000000   | 1      | 1                    | 1       | PASS   | High |
| 6   | BEQ: 0xFFFFFFFF == 0xFFFFFFFF → taken | 000   | 0xFFFFFFFF   | 0xFFFFFFFF   | 1      | 1                    | 1       | PASS   | High |
| 7   | BNE: a != b → taken                  | 001    | 0x00000001   | 0x00000002   | 1      | 1                    | 1       | PASS   | Critical |
| 8   | BNE: a == b → not taken              | 001    | 0x00000007   | 0x00000007   | 1      | 0                    | 0       | PASS   | Critical |
| 9   | BLT: 1 < 2 (signed) → taken         | 100    | 0x00000001   | 0x00000002   | 1      | 1                    | 1       | PASS   | Critical |
| 10  | BLT: 2 < 1 → not taken              | 100    | 0x00000002   | 0x00000001   | 1      | 0                    | 0       | PASS   | Critical |
| 11  | BLT: 0 == 0 → not taken             | 100    | 0x00000000   | 0x00000000   | 1      | 0                    | 0       | PASS   | High |
| 12  | BLT: -1 < 0 (signed) → taken        | 100    | 0xFFFFFFFF   | 0x00000000   | 1      | 1                    | 1       | PASS   | Critical |
| 13  | BLT: -2^31 < 1 (signed) → taken     | 100    | 0x80000000   | 0x00000001   | 1      | 1                    | 1       | PASS   | Critical |
| 14  | BLT: 1 < -1 (signed) → not taken    | 100    | 0x00000001   | 0xFFFFFFFF   | 1      | 0                    | 0       | PASS   | Critical |
| 15  | BGE: 2 >= 1 → taken                 | 101    | 0x00000002   | 0x00000001   | 1      | 1                    | 1       | PASS   | Critical |
| 16  | BGE: 0 >= 0 → taken                 | 101    | 0x00000000   | 0x00000000   | 1      | 1                    | 1       | PASS   | High |
| 17  | BGE: -1 >= 0 (signed) → not taken   | 101    | 0xFFFFFFFF   | 0x00000000   | 1      | 0                    | 0       | PASS   | Critical |
| 18  | BGE: 1 >= -1 (signed) → taken       | 101    | 0x00000001   | 0xFFFFFFFF   | 1      | 1                    | 1       | PASS   | Critical |
| 19  | BLTU: 1 <u 2 → taken                | 110    | 0x00000001   | 0x00000002   | 1      | 1                    | 1       | PASS   | Critical |
| 20  | BLTU: 2 <u 1 → not taken            | 110    | 0x00000002   | 0x00000001   | 1      | 0                    | 0       | PASS   | Critical |
| 21  | BLTU: 0x80000000 <u 1 → not (2^31 unsigned > 1) | 110 | 0x80000000 | 0x00000001 | 1 | 0              | 0       | PASS   | Critical |
| 22  | BLTU: 1 <u 0x80000000 → taken       | 110    | 0x00000001   | 0x80000000   | 1      | 1                    | 1       | PASS   | Critical |
| 23  | BGEU: 2 >=u 1 → taken               | 111    | 0x00000002   | 0x00000001   | 1      | 1                    | 1       | PASS   | Critical |
| 24  | BGEU: 0 >=u 0 → taken               | 111    | 0x00000000   | 0x00000000   | 1      | 1                    | 1       | PASS   | High |
| 25  | BGEU: 0x80000000 >=u 1 → taken (2^31 > 1) | 111 | 0x80000000 | 0x00000001 | 1  | 1                    | 1       | PASS   | Critical |

---

### 1.3 tb_register_file — Register File Unit Test

**Module under test:** `RTL/register_file.sv`
**Số testcase:** 17 (mỗi `check32()` = 1 testcase)
**Kết quả tổng:** 17/17 PASS

| TC# | Tên testcase                        | Thao tác              | Addr   | Data ghi     | Kỳ vọng đọc  | Có được      | Status | Mức độ |
|-----|------------------------------------|-----------------------|--------|--------------|--------------|--------------|--------|--------|
| 1   | x0 sau reset = 0                   | reset → read rs1      | x0     | —            | 0x00000000   | 0x00000000   | PASS   | Critical |
| 2   | x1 sau reset = 0                   | reset → read rs1      | x1     | —            | 0x00000000   | 0x00000000   | PASS   | High |
| 3   | x31 sau reset = 0                  | reset → read rs1      | x31    | —            | 0x00000000   | 0x00000000   | PASS   | High |
| 4   | Ghi x1 = 0xDEADBEEF, đọc lại      | write → read          | x1     | 0xDEADBEEF   | 0xDEADBEEF   | 0xDEADBEEF   | PASS   | Critical |
| 5   | Ghi x31 = 0xABCD1234, đọc lại     | write → read          | x31    | 0xABCD1234   | 0xABCD1234   | 0xABCD1234   | PASS   | High |
| 6   | Ghi x15 = 0x12345678, đọc lại     | write → read          | x15    | 0x12345678   | 0x12345678   | 0x12345678   | PASS   | High |
| 7   | x0 hardwired zero (ghi bị ignore)  | write(x0,0xFFFF…) → read | x0  | 0xFFFFFFFF   | 0x00000000   | 0x00000000   | PASS   | Critical |
| 8   | Dual-port read rs1 (x2)            | dual read             | x2     | —            | 0xAAAAAAAA   | 0xAAAAAAAA   | PASS   | Critical |
| 9   | Dual-port read rs2 (x3)            | dual read             | x3     | —            | 0x55555555   | 0x55555555   | PASS   | Critical |
| 10  | Dual-port read rs2 (x0) = 0        | dual read x0 via rs2  | x0     | —            | 0x00000000   | 0x00000000   | PASS   | High |
| 11  | we=0: ghi bị chặn (x4 = 0)        | we=0, no write        | x4     | 0xCAFEBABE   | 0x00000000   | 0x00000000   | PASS   | Critical |
| 12  | Độc lập x5 = 100                   | write → read          | x5     | 0x00000064   | 0x00000064   | 0x00000064   | PASS   | Medium |
| 13  | Độc lập x6 = 200                   | write → read          | x6     | 0x000000C8   | 0x000000C8   | 0x000000C8   | PASS   | Medium |
| 14  | Độc lập x7 = 300                   | write → read          | x7     | 0x0000012C   | 0x0000012C   | 0x0000012C   | PASS   | Medium |
| 15  | Mid-test reset: x1 về 0            | reset mid-test → read | x1     | —            | 0x00000000   | 0x00000000   | PASS   | High |
| 16  | Mid-test reset: x5 về 0            | reset mid-test → read | x5     | —            | 0x00000000   | 0x00000000   | PASS   | High |
| 17  | Mid-test reset: x31 về 0           | reset mid-test → read | x31    | —            | 0x00000000   | 0x00000000   | PASS   | High |

---

### 1.4 tb_id_decoder — Instruction Decoder Unit Test

**Module under test:** `RTL/id_decoder.sv`
**Số testcase:** 107 (mỗi `chk*()` = 1 testcase)
**Kết quả tổng:** 107/107 PASS

Bảng dưới nhóm theo instruction để dễ đọc; cột "Số TC" ghi số lần gọi `chk*()` thực tế của mỗi nhóm.

| Nhóm # | Instruction                            | Encoding (hex) | Số TC | Fields được kiểm tra                                    | Kỳ vọng (tóm tắt)                                               | Status | Mức độ |
|--------|----------------------------------------|----------------|-------|---------------------------------------------------------|------------------------------------------------------------------|--------|--------|
| 1      | LUI x1, 0x12345                        | 0x12345_0B7    | 10    | rd, alu_src_b, alu_src_a, alu_op, reg_write, wb_sel, imm, branch, jump, illegal | rd=1; alu_op=PASSB; imm=0x12345000; illegal=0         | PASS   | Critical |
| 2      | AUIPC x2, 0xABCDE                      | 0xABCDE_117    | 6     | rd, alu_src_a, alu_src_b, alu_op, reg_write, imm, illegal | alu_op=ADD; alu_src_a=1(PC); imm=0xABCDE000               | PASS   | Critical |
| 3      | JAL x1, +4                             | 0x00400_0EF    | 7     | jump, jump_reg, reg_write, wb_sel, branch, imm, illegal | jump=1; jump_reg=0; wb_sel=10(PC+4); imm=4                       | PASS   | Critical |
| 4      | JALR x1, x2, 4                         | 0x00410_0E7    | 7     | jump, jump_reg, rs1, reg_write, wb_sel, imm, illegal    | jump=1; jump_reg=1; rs1=2; wb_sel=10; imm=4                      | PASS   | Critical |
| 5      | BEQ x1, x2, +8                         | 0x00208_463    | 7     | branch, jump, reg_write, rs1, rs2, imm, illegal         | branch=1; reg_write=0; rs1=1; rs2=2; imm=8                       | PASS   | Critical |
| 6      | LW x5, 8(x2)                           | 0x00812_283    | 10    | mem_read, mem_write, reg_write, wb_sel, mem_size, alu_src_b, rs1, rd, imm, illegal | mem_read=1; wb_sel=01; mem_size=10(word); imm=8 | PASS   | Critical |
| 7      | LH x1, 4(x3)                           | constructed    | 2     | mem_size, mem_ext                                       | mem_size=01(half); mem_ext=1(signed)                             | PASS   | Critical |
| 8      | LHU x1, 4(x3)                          | constructed    | 2     | mem_size, mem_ext                                       | mem_size=01(half); mem_ext=0(unsigned)                           | PASS   | Critical |
| 9      | SW x3, 12(x1)                          | 0x0030A_623    | 7     | mem_write, mem_read, reg_write, rs1, rs2, imm, illegal  | mem_write=1; reg_write=0; rs1=1; rs2=3; imm=12                  | PASS   | Critical |
| 10     | ADDI x3, x1, 42                        | 0x02A08_193    | 8     | alu_src_b, alu_src_a, alu_op, reg_write, rs1, rd, imm, illegal | alu_op=ADD; alu_src_b=1; imm=42                         | PASS   | Critical |
| 11     | SRAI x4, x5, 3                         | constructed    | 2     | alu_op, illegal                                         | alu_op=SRA(0111); illegal=0                                      | PASS   | Critical |
| 12     | SLLI với funct7 sai → illegal          | constructed    | 1     | illegal                                                 | illegal=1                                                        | PASS   | High |
| 13     | ADD x4, x2, x3                         | 0x00310_233    | 6     | alu_op, alu_src_b, reg_write, rs1, rs2, rd, illegal     | alu_op=ADD; alu_src_b=0; rs1=2; rs2=3; rd=4                      | PASS   | Critical |
| 14     | SUB x5, x1, x2                         | 0x40208_2B3    | 2     | alu_op, illegal                                         | alu_op=SUB(0001); illegal=0                                      | PASS   | Critical |
| 15     | ADD với funct7 sai → illegal           | constructed    | 1     | illegal                                                 | illegal=1                                                        | PASS   | High |
| 16     | ECALL                                  | 0x00000_073    | 5     | ecall, ebreak, mret, reg_write, illegal                 | ecall=1; ebreak=0; mret=0; reg_write=0; illegal=0                | PASS   | Critical |
| 17     | EBREAK                                 | 0x00100_073    | 4     | ebreak, ecall, reg_write, illegal                       | ebreak=1; ecall=0; reg_write=0; illegal=0                        | PASS   | High |
| 18     | MRET                                   | 0x30200_073    | 4     | mret, ecall, reg_write, illegal                         | mret=1; ecall=0; reg_write=0; illegal=0                          | PASS   | Critical |
| 19     | CSRRW x1, mstatus, x2                  | 0x30011_0F3    | 6     | csr_we, csr_op, wb_sel, reg_write, csr_imm_sel, illegal | csr_we=1; csr_op=01(RW); wb_sel=11; csr_imm_sel=0                | PASS   | Critical |
| 20     | CSRRS x1, mie, x2 (rs1≠x0)            | constructed    | 2     | csr_we, csr_op                                          | csr_we=1; csr_op=10(RS)                                          | PASS   | Critical |
| 21     | CSRRS x1, mie, x0 (rs1=x0 → no write) | constructed    | 3     | csr_we, csr_op, reg_write                               | csr_we=0(suppressed); csr_op=10; reg_write=1(CSR read vẫn xảy ra) | PASS | Critical |
| 22     | CSRRC x1, mie, x0 (rs1=x0 → no write) | constructed    | 2     | csr_we, csr_op                                          | csr_we=0(suppressed); csr_op=11(RC)                              | PASS   | Critical |
| 23     | CSRRWI x1, mtvec, 8                    | constructed    | 4     | csr_imm_sel, csr_op, csr_we, imm                        | csr_imm_sel=1; csr_op=01; csr_we=1; imm=8(zimm)                 | PASS   | Critical |
| 24     | Illegal opcode 0xFFFFFFFF              | 0xFFFFFFFF     | 2     | illegal, reg_write                                      | illegal=1; reg_write=0                                           | PASS   | Critical |
| **Tổng** | —                                    | —              | **107** | —                                                    | —                                                                | **PASS** | — |

**Ghi chú quan trọng:**
- TC21 & TC22: CSRRS/CSRRC với rs1=x0 phải suppress csr_we (RV32I spec §9.1) để tránh side-effect không mong muốn vào CSR. Đây là chi tiết dễ bỏ sót nhất trong Zicsr implementation.
- TC12 & TC15: Illegal instruction detection cho encoding sai funct7 — bảo vệ tránh thực thi lệnh không hợp lệ.

---

### Tổng kết Phase 1

**Định nghĩa:** 1 testcase = 1 lần gọi `check()`/`chk*()` trong source — khớp với `pass_cnt` mà testbench tự in ra.

| Testbench        | Số testcase | PASS | FAIL | Tỷ lệ |
|-----------------|-------------|------|------|--------|
| tb_alu           | 38          | 38   | 0    | 100%   |
| tb_branch_comp   | 25          | 25   | 0    | 100%   |
| tb_register_file | 17          | 17   | 0    | 100%   |
| tb_id_decoder    | 107         | 107  | 0    | 100%   |
| **Tổng Phase 1** | **187**     | **187** | **0** | **100%** |

---

---

---

## 1.2 Pipeline Support — tb_forwarding_unit · tb_hazard_unit

### 1.5 tb_forwarding_unit — Forwarding Unit Unit Test

**Module under test:** `RTL/forwarding_unit.sv`
**Số testcase:** 19
**Kết quả tổng:** 19/19 PASS

Forwarding priority: MEM1 > MEM2 > WB. Forward chỉ xảy ra khi `reg_write=1` và `rd_addr ≠ x0`.

| TC# | Scenario                                 | rs1 | rs2 | mem1_rd (we) | mem2_rd (we) | wb_rd (we) | Kỳ vọng fwd_sel_a | Kỳ vọng fwd_sel_b | Status | Mức độ |
|-----|------------------------------------------|-----|-----|--------------|--------------|------------|-------------------|-------------------|--------|--------|
| 1   | Không có match rs1                       | x1  | x2  | x5 (1)       | x6 (1)       | x7 (1)     | NO_FWD (00)       | —                 | PASS   | Critical |
| 2   | Không có match rs2                       | x1  | x2  | x5 (1)       | x6 (1)       | x7 (1)     | —                 | NO_FWD (00)       | PASS   | Critical |
| 3   | MEM1 thắng MEM2+WB (rs1)                | x3  | x9  | x3 (1)       | x3 (1)       | x3 (1)     | FWD_M1 (01)       | —                 | PASS   | Critical |
| 4   | MEM1 thắng MEM2+WB (rs2)                | x9  | x3  | x3 (1)       | x9 (1)       | x9 (1)     | —                 | FWD_M1 (01)       | PASS   | Critical |
| 5   | MEM1 we=0 → không forward (rs1)          | x3  | x9  | x3 (0)       | x9 (1)       | x9 (1)     | NO_FWD (00)       | —                 | PASS   | Critical |
| 6   | MEM2 thắng WB (rs1)                     | x4  | x5  | x9 (1)       | x4 (1)       | x4 (1)     | FWD_M2 (10)       | —                 | PASS   | Critical |
| 7   | MEM2 thắng WB (rs2)                     | x9  | x5  | x9 (1)       | x5 (1)       | x5 (1)     | —                 | FWD_M2 (10)       | PASS   | Critical |
| 8   | MEM2 we=0 → rơi xuống WB (rs1)          | x4  | x9  | x9 (1)       | x4 (0)       | x4 (1)     | FWD_WB (11)       | —                 | PASS   | High |
| 9   | WB forward (rs1)                        | x6  | x7  | x9 (1)       | x9 (1)       | x6 (1)     | FWD_WB (11)       | —                 | PASS   | Critical |
| 10  | WB forward (rs2)                        | x9  | x7  | x9 (1)       | x9 (1)       | x7 (1)     | —                 | FWD_WB (11)       | PASS   | Critical |
| 11  | WB we=0 → NO_FWD (rs1)                  | x6  | x9  | x9 (1)       | x9 (1)       | x6 (0)     | NO_FWD (00)       | —                 | PASS   | Critical |
| 12  | x0 không bao giờ forward (rs1)          | x0  | x0  | x0 (1)       | x0 (1)       | x0 (1)     | NO_FWD (00)       | —                 | PASS   | Critical |
| 13  | x0 không bao giờ forward (rs2)          | x0  | x0  | x0 (1)       | x0 (1)       | x0 (1)     | —                 | NO_FWD (00)       | PASS   | Critical |
| 14  | rs1=x5 match MEM1; rs2=x0 no match      | x5  | x0  | x5 (1)       | x9 (1)       | x9 (1)     | FWD_M1 (01)       | NO_FWD (00)       | PASS   | High |
| 15  | A=MEM1, B=MEM2 đồng thời               | x1  | x2  | x1 (1)       | x2 (1)       | x9 (1)     | FWD_M1 (01)       | FWD_M2 (10)       | PASS   | Critical |
| 16  | (tiếp TC15) B=MEM2 confirm              | x1  | x2  | x1 (1)       | x2 (1)       | x9 (1)     | —                 | FWD_M2 (10)       | PASS   | Critical |
| 17  | A=MEM2, B=WB đồng thời                 | x3  | x4  | x9 (1)       | x3 (1)       | x4 (1)     | FWD_M2 (10)       | FWD_WB (11)       | PASS   | Critical |
| 18  | (tiếp TC17) B=WB confirm                | x3  | x4  | x9 (1)       | x3 (1)       | x4 (1)     | —                 | FWD_WB (11)       | PASS   | Critical |

**Ghi chú:** TC12+TC13 kiểm tra invariant quan trọng: x0 (register zero) không bao giờ được forward dù rd_addr=x0 match — tránh propagate giá trị rác vào ALU.

---

### 1.6 tb_hazard_unit — Hazard Unit Unit Test

**Module under test:** `RTL/hazard_unit.sv`
**Số testcase:** 68
**Kết quả tổng:** 68/68 PASS

Quy ước output: `stall_*` giữ nguyên register, `flush_*` clear register về NOP/bubble.

| TC# | Scenario                              | Điều kiện kích hoạt                                  | Signals kỳ vọng (chỉ nêu các signal thay đổi)                                                       | Status | Mức độ |
|-----|---------------------------------------|------------------------------------------------------|-------------------------------------------------------------------------------------------------------|--------|--------|
| 1   | Idle: không có hazard                 | Tất cả inputs = 0                                    | Tất cả stall=0, tất cả flush=0 (14 checks)                                                           | PASS   | Critical |
| 2   | Load-use hazard (rs1 match)           | ex_mem_read=1, ex_rd=x3, id_rs1=x3                  | stall_pc=1, stall_if1_if2=1, stall_if2_id=1, stall_id_ex=0, stall_ex_mem1=0, flush_id_ex=1, flush_if1_if2=0, flush_if2_id=0 (8 checks) | PASS | Critical |
| 3   | Load-use hazard (rs2 match)           | ex_mem_read=1, ex_rd=x4, id_rs2=x4                  | stall_pc=1, flush_id_ex=1 (2 checks)                                                                 | PASS   | Critical |
| 4   | Load-use: rd=x0 → không stall        | ex_mem_read=1, ex_rd=x0, id_rs1=x0                  | stall_pc=0, flush_id_ex=0 (2 checks)                                                                 | PASS   | Critical |
| 5   | ex_mem_read=0 → không stall          | ex_mem_read=0, ex_rd=x3, id_rs1=x3                  | stall_pc=0 (1 check)                                                                                  | PASS   | High |
| 6   | BP mismatch: flush fetch stages      | bp_mismatch=1                                        | flush_if1_if2=1, flush_if2_id=1, flush_id_ex=1, flush_ex_mem1=0, stall_pc=0, stall_if1_if2=0 (6 checks) | PASS | Critical |
| 7   | Bus stall: đóng băng toàn pipeline   | bus_stall_req=1                                      | stall_pc=1, stall_if1_if2=1, stall_if2_id=1, stall_id_ex=1, stall_ex_mem1=1, stall_mem1_mem2=1, stall_mem2_wb=1, flush_if1_if2=0, flush_id_ex=0 (9 checks) | PASS | Critical |
| 8   | Zicsr flush: flush toàn pipeline     | zicsr_flush=1                                        | flush_pc=1, flush_if1_if2=1, flush_if2_id=1, flush_id_ex=1, flush_ex_mem1=1, flush_mem1_mem2=1, flush_mem2_wb=1, stall_pc=0 (8 checks) | PASS | Critical |
| 9   | Load-use + bp_mismatch đồng thời     | ex_mem_read=1, ex_rd=x5, id_rs1=x5, bp_mismatch=1  | stall_pc=1, flush_if1_if2=1, flush_id_ex=1 (3 checks)                                               | PASS   | High |
| 10  | Zicsr + bp_mismatch + load-use       | zicsr_flush=1, bp_mismatch=1, ex_mem_read=1, id_rs1 match | flush_ex_mem1=1, flush_mem2_wb=1 — zicsr flush thắng (2 checks)                                | PASS   | High |
| 11  | CSR-use: CSR tại EX, rs1 match       | ex_wb_sel=11, ex_reg_write=1, ex_rd=x6, id_rs1=x6  | stall_pc=1, stall_if1_if2=1, stall_if2_id=1, stall_id_ex=0, flush_id_ex=1 (5 checks)               | PASS   | Critical |
| 12  | CSR-use: CSR tại MEM1, rs2 match     | mem1_wb_sel=11, mem1_reg_write=1, mem1_rd=x7, id_rs2=x7 | stall_pc=1, flush_id_ex=1 (2 checks)                                                            | PASS   | Critical |
| 13  | CSR-use: CSR tại MEM2, rs1 match     | mem2_wb_sel=11, mem2_reg_write=1, mem2_rd=x8, id_rs1=x8 | stall_pc=1, flush_id_ex=1 (2 checks)                                                            | PASS   | Critical |
| 14  | CSR-use: rd=x0 → không stall         | mem1_wb_sel=11, mem1_reg_write=1, mem1_rd=x0, id_rs1=x0 | stall_pc=0, flush_id_ex=0 (2 checks)                                                            | PASS   | Critical |
| 15  | Bus stall loại bỏ CSR-use bubble     | bus_stall_req=1, ex_wb_sel=11, ex_reg_write=1, ex_rd=x6, id_rs1=x6 | stall_pc=1, flush_id_ex=0 (bus stall suppresses bubble) (2 checks)              | PASS   | High |

**Ghi chú quan trọng:**
- TC2: load-use stall chỉ freeze IF1/IF2/ID, KHÔNG freeze EX trở đi — EX vẫn tiến, nhận bubble (flush_id_ex=1).
- TC8: zicsr_flush là flush toàn bộ pipeline kể cả EX..WB, khác với bp_mismatch chỉ flush tới ID/EX.
- TC15: bus_stall đang giữ pipeline đứng yên — không thể vừa stall vừa insert bubble vào ID/EX, nên flush_id_ex bị suppress.

---


---

## 1.3 Memory \/ CDC — tb_async_fifo

### 1.7 tb_async_fifo — Async FIFO Unit Test

**Module under test:** `RTL/async_fifo_depth2.sv`
**Config:** DATA_WIDTH=8, depth=2, wr_clk=1GHz, rd_clk=500MHz (lệch pha 7ns để stress CDC)
**Số testcase:** 22
**Kết quả tổng:** 22/22 PASS

| TC# | Scenario                                  | Thao tác                              | Kỳ vọng                                      | Status | Mức độ |
|-----|-------------------------------------------|---------------------------------------|-----------------------------------------------|--------|--------|
| 1   | Sau reset: rd_empty=1                     | do_reset()                            | rd_empty=1                                    | PASS   | Critical |
| 2   | Ghi 1 word → empty clears                | write(0xAB) → sync_wait(4 rd_clk)    | rd_empty=0                                    | PASS   | Critical |
| 3   | Đọc lại đúng dữ liệu                     | fifo_read_check                       | rd_data=0xAB                                  | PASS   | Critical |
| 4   | Đọc xong → empty=1                       | sau khi đọc hết                       | rd_empty=1                                    | PASS   | Critical |
| 5   | Ghi 2 words (full), kiểm tra not empty   | write(0xCA), write(0xFE) → sync_wait | rd_empty=0                                    | PASS   | High |
| 6   | Đọc word đầu (0xCA) đúng thứ tự         | fifo_read_check                       | rd_data=0xCA; rd_empty=0 (còn 1 word)         | PASS   | Critical |
| 7   | Đọc word thứ hai (0xFE) đúng thứ tự     | fifo_read_check                       | rd_data=0xFE; rd_empty=1 (hết)               | PASS   | Critical |
| 8   | rd_en=1 khi empty không làm hỏng pointer | rd_en pulsed while empty → write(0x42) → read | rd_data=0x42 (pointer không bị advance sai) | PASS | Critical |
| 9   | Reset giữa chừng xóa toàn bộ state      | write(0xDE) → do_reset()              | rd_empty=1 sau reset                          | PASS   | High |
| 10  | Multi-write/read: B1 đơn lẻ              | write(0xB1) → read                    | rd_data=0xB1; rd_empty=1                     | PASS   | High |
| 11  | Multi-write/read: B2 và B3 liên tiếp    | write(0xB2), write(0xB3) → read B2   | rd_data=0xB2; rd_empty=0 (B3 pending)        | PASS   | High |
| 12  | Multi-write/read: đọc B3                 | read B3                               | rd_data=0xB3; rd_empty=1                     | PASS   | High |

**Ghi chú quan trọng:**
- TC8 kiểm tra tính ổn định pointer: nếu rd_ptr bị advance khi FIFO rỗng, word tiếp theo sẽ bị bỏ qua — đây là bug nghiêm trọng trong CDC FIFO.
- sync_wait(4 rd_clk) sau mỗi write đảm bảo 2-FF synchronizer đã propagate wr_ptr sang rd domain trước khi check rd_empty.
- Clock lệch pha 7ns nhằm stress worst-case metastability window của 2-FF synchronizer.

---

### Tổng kết Phase 2

| Testbench          | Số testcase | PASS | FAIL | Tỷ lệ |
|-------------------|-------------|------|------|--------|
| tb_forwarding_unit | 19          | 19   | 0    | 100%   |
| tb_hazard_unit     | 68          | 68   | 0    | 100%   |
| tb_async_fifo      | 22          | 22   | 0    | 100%   |
| **Tổng Phase 2**   | **109**     | **109** | **0** | **100%** |

---

---

## 1.4 EX Stage — tb_ex_stage

### Phase 8 Unit: tb_ex_stage (23 TC)

**DUT:** `RTL/ex_stage.sv` — wrapper chứa: `forwarding_unit` + MUX A/B + `alu` + `branch_comp` + `addr_adder`. Toàn bộ combinational.
**Cơ chế check:** `chk32()` cho 32-bit; `chk1()` cho 1-bit. Mỗi call = 1 testcase.

#### Group 1 — No forwarding: basic ALU và input select (6 TC)

| TC | Tên | Setup | Output được check | Kỳ vọng | Status |
|----|-----|-------|-------------------|---------|--------|
| T1a | no-fwd ADD rs1_fwd=rs1_data | rs1=5, rs2=3, ADD | ex_rs1_fwd | 0x5 | PASS |
| T1b | no-fwd ADD rs2_fwd=rs2_data | rs1=5, rs2=3, ADD | ex_rs2_fwd | 0x3 | PASS |
| T1c | no-fwd ADD result=8 | rs1=5, rs2=3, ADD | ex_alu_result | 0x8 | PASS |
| T2 | no-fwd SUB result=0xD | rs1=0x10, rs2=3, SUB | ex_alu_result | 0xD | PASS |
| T3 | alu_src_b=imm ADD result=107 | rs1=100, imm=7, src_b=imm | ex_alu_result | 107 | PASS |
| T4 | alu_src_a=PC ADD result=PC+imm | PC=0x1000, imm=0x10000, src_a=PC, src_b=imm | ex_alu_result | 0x0001_1000 | PASS |

#### Group 2 — Forwarding paths (7 TC)

| TC | Tên | Forwarding source | rs match | Kỳ vọng | Status |
|----|-----|------------------|---------|---------|--------|
| T5 | gap-1 rs1 fwd from MEM1 | MEM1 rd=x3, alu=0xABCD_1234 | rs1_addr=x3 | ex_rs1_fwd=0xABCD_1234 | PASS |
| T6 | gap-1 rs2 fwd from MEM1 | MEM1 rd=x5, alu=0xCAFE | rs2_addr=x5 | ex_rs2_fwd=0x0000_CAFE | PASS |
| T7 | gap-2 rs1 fwd MEM2 ALU (wb_sel=00) | MEM2 rd=x4, wb_sel=00, alu=0x1111_2222 | rs1_addr=x4 | ex_rs1_fwd=0x1111_2222 | PASS |
| T8 | gap-2 rs1 fwd MEM2 load (wb_sel=01) | MEM2 rd=x4, wb_sel=01, mem_rdata=0xBEEF_CAFE | rs1_addr=x4 | ex_rs1_fwd=0xBEEF_CAFE | PASS |
| T9 | gap-3 rs1 fwd from WB | WB rd=x6, wr_data=0xFACE_BABE | rs1_addr=x6 | ex_rs1_fwd=0xFACE_BABE | PASS |
| T10 | priority MEM1>MEM2 for rs1 | MEM1=0xAAAA, MEM2=0xBBBB; cả 2 match rs1 | rs1_addr=x7 | ex_rs1_fwd=0xAAAA_AAAA (MEM1 wins) | PASS |
| T11 | x0 not forwarded from MEM1 | MEM1 rd=x0, reg_write=1, alu=0xDEAD | rs1_addr=x0 | ex_rs1_fwd=0 (x0 không forward) | PASS |

#### Group 3 — Branch và jump (7 TC)

| TC | Tên | Instruction | Setup | Kỳ vọng | Status |
|----|-----|------------|-------|---------|--------|
| T12 | BEQ taken when rs1==rs2 | BEQ, branch=1 | rs1=5, rs2=5 | ex_branch_taken=1 | PASS |
| T13 | BEQ not taken when rs1!=rs2 | BEQ, branch=1 | rs1=5, rs2=6 | ex_branch_taken=0 | PASS |
| T14 | BNE taken when rs1!=rs2 | BNE, branch=1 | rs1=0xAA, rs2=0xBB | ex_branch_taken=1 | PASS |
| T15 | branch target = PC+imm | branch=1 | PC=0x2000, imm=16 | ex_jump_addr=0x2010 | PASS |
| T16 | JAL target = PC+(-16) | jump=1, jump_reg=0 | PC=0x4000, imm=-16 | ex_jump_addr=0x3FF0 | PASS |
| T17 | JALR target = (rs1+imm) & ~1 | jump=1, jump_reg=1 | rs1=0x100, imm=15 → 0x10F, bit0 mask | ex_jump_addr=0x010E | PASS |
| T18 | branch=0 → not taken despite equal | branch=0 | rs1=7, rs2=7, BEQ | ex_branch_taken=0 | PASS |

#### Group 4 — Combined forwarding + computation (3 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T19 | fwd rs1 MEM1, ADD with rs2_rf | rs1_fwd=MEM1=0x50, rs2_rf=0x10, ADD | ex_alu_result=0x60 | PASS |
| T20 | fwd rs1=MEM1 rs2=MEM2 BEQ taken | rs1_fwd=MEM1=0xAA, rs2_fwd=MEM2=0xAA; BEQ | ex_branch_taken=1 | PASS |
| T21 | JALR target using gap-3 fwd rs1 | rs1_fwd=WB=0x200, imm=1 → 0x201 → mask → 0x200 | ex_jump_addr=0x200 | PASS |

---

---

## 1.5 Branch Predictor — tb_branch_predictor

### Unit: tb_branch_predictor (23 TC)

**DUT:** `RTL/branch_predictor.sv` — 16-entry 2-bit saturating BHT + BTB. Lookup IF1 (combinational). Update tại EX (posedge).
**Interface:** `fetch_pc` → `{predict_taken, predict_target}`; `{update_en, update_pc, update_taken, update_target}`.
**Cơ chế check:** `chk()` cho 1-bit; `chk32()` cho 32-bit. Mỗi call = 1 TC.

#### Group 1 — Cold start (BTB empty) (2 TC)

| TC | Tên | PC lookup | Kỳ vọng | Status |
|----|-----|-----------|---------|--------|
| 1 | cold: predict_taken=0 | 0x100 | 0 (valid=0, miss) | PASS |
| 2 | cold PC2: predict_taken=0 | 0x200 | 0 | PASS |

#### Group 2 — First taken update (2 TC)

| TC | Tên | Update | Kỳ vọng | Status |
|----|-----|--------|---------|--------|
| 3 | after 1 taken: predict_taken=1 | PC=0x100, taken, target=0x200; BHT: 01→10 | 1 | PASS |
| 4 | after 1 taken: predict_target | — | 0x200 | PASS |

#### Group 3 — Second taken → strongly taken (2 TC)

| TC | Tên | Update | Kỳ vọng | Status |
|----|-----|--------|---------|--------|
| 5 | strong taken: predict_taken=1 | BHT: 10→11 | 1 | PASS |
| 6 | strong taken: predict_target | — | 0x200 | PASS |

#### Group 4 — Hysteresis: not-taken from 11→10 (1 TC)

| TC | Tên | Update | Kỳ vọng | Status |
|----|-----|--------|---------|--------|
| 7 | 11→10: still predict_taken=1 | not-taken; BHT 11→10 (còn taken) | 1 | PASS |

#### Group 5 — Second not-taken: 10→01 (1 TC)

| TC | Tên | Update | Kỳ vọng | Status |
|----|-----|--------|---------|--------|
| 8 | 10→01: predict_taken=0 | BHT 10→01 → weakly not-taken | 0 | PASS |

#### Group 6 — Saturation at 00 (2 TC)

| TC | Tên | Update | Kỳ vọng | Status |
|----|-----|--------|---------|--------|
| 9 | 00 saturated: predict_taken=0 | 01→00→00 (saturate) | 0 | PASS |
| 10 | 00→01: predict_taken=0 | 1 taken from 00 → 01 (weakly not-taken) | 0 | PASS |

#### Group 7 — Tag mismatch: same index, different PC (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 11 | tag mismatch: predict_taken=0 | PC=0x140 → index=0 (same), tag khác 0x100 → no hit | 0 | PASS |

#### Group 8 — Independent entries: different indices (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 12 | idx4: predict_taken=1 | update PC=0x110 (index=4), strongly taken | 1 | PASS |
| 13 | idx4: predict_target | target=0x500 | 0x500 | PASS |
| 14 | idx0 still 01: predict_taken=0 | PC=0x100 (index=0) không bị ảnh hưởng | 0 | PASS |

#### Group 9 — BTB target update (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 15 | updated target: predict_taken=1 | PC=0x120; 1st target=0xAA0, 2nd update target=0xBB0 | 1 | PASS |
| 16 | updated target: predict_target=BB0 | BTB overwritten với target mới | 0xBB0 | PASS |

#### Group 10 — update_en=0 suppresses update (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 17 | before: predict_taken=1 | confirm state của PC=0x120 | 1 | PASS |
| 18 | after no-update: still predict_taken=1 | update_en=0, update_taken=0 → không thay đổi | 1 | PASS |

#### Group 11 — Reset clears predictor (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 19 | after reset idx4: predict_taken=0 | rst_n=0 → 1; lookup 0x110 | 0 | PASS |
| 20 | after reset idx8: predict_taken=0 | lookup 0x120 | 0 | PASS |

#### Group 12 — Loop simulation: hysteresis under sustained taken (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 21 | loop after 10 taken: predict_taken=1 | 10× update taken; BHT → 11 (strongly taken) | 1 | PASS |
| 22 | loop: predict_target=0x1EC | backward branch target | 0x1EC | PASS |
| 23 | loop exit (11→10): still predict_taken=1 | 1× not-taken; BHT 11→10 (hysteresis: còn predict taken) | 1 | PASS |


---

## 1.6 Interrupt \/ CSR \/ PLIC — tb_irq_sync2ff · tb_plic · tb_zicsr

### New Unit 1: tb_irq_sync2ff (10 TC)

**DUT:** `RTL/irq_sync2ff.sv` — 2-FF synchronizer, 1 instance/AHB slave. CDC 500MHz→1GHz.
**Cơ chế check:** `check()` cho 1-bit. Clk = 1GHz.

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T1 | q=0 after reset | Sau do_reset 4 cycles | 0 | PASS |
| T2 | q=0 after 1 cycle (ff1 captures) | d=1; sau 1 posedge: ff1=1, q chưa cập nhật | 0 | PASS |
| T3 | q=1 after 2 cycles | Sau 2 posedge: q=1 (ff2 captures ff1) | 1 | PASS |
| T4 | q=1 still (1 cycle after d=0) | d=0; ff1 về 0 nhưng q vẫn 1 | 1 | PASS |
| T5 | q=0 after 2 cycles | Sau 2 posedge: q=0 | 0 | PASS |
| T6 | q=1 from 1-cycle pulse | d=1 cho đúng 1 posedge window; q nên lên sau 2 cycle | 1 | PASS |
| T7 | q=0 after pulse clears | Sau khi pulse kết thúc | 0 | PASS |
| T8 | q=0 immediately on async rst | rst_n=0 giữa chừng → q xuống ngay | 0 | PASS |
| T9 | q=0 after rst released, d=0 | Sau reset release, d=0 | 0 | PASS |
| T10 | q=1 sustained | d=1 giữ 5+ cycles | 1 | PASS |

---

---

### Phase 7 Unit: tb_plic (31 TC)

**DUT:** `RTL/plic.sv` — PLIC 6 sources, 3-bit priority, SiFive spec. Interface: `irq_src[5:0]`, `re/we/addr/wdata/rdata`, `meip`.
**Cơ chế check:** `chk1()` cho 1-bit; `plic_read_check()` cho 32-bit register (gọi `chk32()`). Mỗi call = 1 testcase.

#### Group 1 — Reset state (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC01 | meip=0 after reset | Sau do_reset, meip phải 0 | 0 | PASS |
| TC02 | CLAIM=0 after reset | CLAIM register (0x200004) phải 0 | 0x0 | PASS |

#### Group 2 — Register read/write (3 TC)

| TC | Tên | Địa chỉ | Write | Kỳ vọng | Status |
|----|-----|---------|-------|---------|--------|
| TC03 | PRIORITY[1] write/read=5 | 0x000004 | 5 | 0x5 | PASS |
| TC04 | ENABLE=2 write/read | 0x002000 | 2 | 0x2 | PASS |
| TC05 | THRESHOLD=3 write/read | 0x200000 | 3 | 0x3 | PASS |

#### Group 3 — IRQ raise → meip/pending/claim (3 TC)

**Setup:** PRIORITY[1]=5, ENABLE source 1, THRESHOLD=0; raise irq_src[0].

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC06 | meip=1 after source1 raise | irq_src[0]=1 → PLIC forward meip | 1 | PASS |
| TC07 | PENDING=2 (source1 set) | PENDING reg (0x001000); source 1 = bit[1] → value=2 | 0x2 | PASS |
| TC08 | CLAIM=1 (source1 wins) | CLAIM (0x200004) trả về winner ID | 0x1 | PASS |

#### Group 4 — Complete clears pending (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC09 | meip=0 after complete(1) | write COMPLETE=1 → pending[1] cleared | 0 | PASS |
| TC10 | PENDING=0 after complete | PENDING register về 0 | 0x0 | PASS |

#### Group 5 — Priority selection (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC11 | CLAIM=2 (pri5 beats pri3) | src1 pri=3, src2 pri=5; cả 2 raise đồng thời | 0x2 (src2 wins) | PASS |
| TC12 | CLAIM=1 (tie → lower ID wins) | src1 pri=3, src2 pri=3; tie-break | 0x1 (lower ID wins) | PASS |

#### Group 6 — Threshold blocking (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC13 | meip=0 when priority≤threshold | pri=2, threshold=3 → 2 > 3 false → blocked | 0 | PASS |
| TC14 | meip=1 after threshold lowered | threshold hạ xuống 1 → 2 > 1 → forward | 1 | PASS |

#### Group 7 — Enable mask (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC15 | meip=0 when source disabled | ENABLE=0 (all off); irq raise → pending set nhưng không forward | 0 | PASS |
| TC16 | meip=1 after re-enable | ENABLE=2 → source 1 active → meip | 1 | PASS |

#### Group 8 — Priority=0 disables source (1 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC17 | meip=0 when priority=0 | PRIORITY[1]=0 → source disabled dù ENABLE=1 và irq raise | 0 | PASS |

#### Group 9 — Multi-source claim sequence (4 TC)

**Setup:** src1 pri=5, src2 pri=3; cả 2 raise.

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC18 | first CLAIM=1 (pri5) | First claim: src1 (priority 5 > 3) wins | 0x1 | PASS |
| TC18b | meip=1 (source2 still pending) | Sau complete(1): src2 vẫn pending → meip vẫn | 1 | PASS |
| TC19 | second CLAIM=2 | Second claim: src2 | 0x2 | PASS |
| TC19b | meip=0 (all complete) | Sau complete(2): không còn pending | 0 | PASS |

#### Group 10 — AHB source (source 4 = irq_src[3]) (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC20 | meip=1 from AHB source4 | PRIORITY[4]=1, ENABLE bit[4]=1; raise irq_src[3] | 1 | PASS |
| TC20b | CLAIM=4 | CLAIM register trả về source 4 | 0x4 | PASS |
| TC21 | meip=0 after AHB complete | complete(4) → pending[4] cleared | 0 | PASS |

#### Group 11 — Rising-edge detection (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| TC22 | no re-trigger while irq stays high | complete(1) với irq_src[0] vẫn=1 → irq_src_prev=1 → no edge | 0 | PASS |
| TC22b | PENDING=0 (no re-trigger) | PENDING register xác nhận | 0x0 | PASS |
| TC23 | re-triggered after low→high | lower sau đó raise lại → rising edge detected | 1 | PASS |

#### Group 12 — All priority registers write/read (4 TC)

| TC | Tên | Địa chỉ | Write | Kỳ vọng | Status |
|----|-----|---------|-------|---------|--------|
| TC24a | PRI[1]=7 | 0x000004 | 7 | 0x7 | PASS |
| TC24b | PRI[3]=5 | 0x00000C | 5 | 0x5 | PASS |
| TC24c | PRI[6]=2 | 0x000018 | 2 | 0x2 | PASS |
| TC25 | ENABLE=0x7E (all 6 sources) | 0x002000 | 0x7E | 0x7E | PASS |

---

---

### New Unit 3: tb_zicsr (38 TC)

**DUT:** `RTL/zicsr.sv` — WB-stage CSR block: 6 CSR registers, exceptions, interrupts, MRET, vectored mode. Drive trực tiếp WB inputs, không cần full pipeline.
**Cơ chế check:** `check1()`, `check32()`. Clk = 1GHz.

#### Group 1 — Reset values (6 TC)

| TC | CSR | Kỳ vọng | Status |
|----|-----|---------|--------|
| T1 | mstatus | 0x0000_1800 (MPP=11, MIE=0) | PASS |
| T2 | mie | 0x0 | PASS |
| T3 | mtvec | 0x0 | PASS |
| T4 | mepc | 0x0 | PASS |
| T5 | mcause | 0x0 | PASS |
| T6 | zicsr_flush=0 at reset | 0 | PASS |

#### Group 2 — CSRRW write mtvec (1 TC)

| TC | Tên | Write | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T7 | mtvec written | 0xC000_0001 (vectored) | 0xC000_0001 | PASS |

#### Group 3 — CSRRS set bits in mie (1 TC)

| TC | Tên | Write mask | Kỳ vọng | Status |
|----|-----|-----------|---------|--------|
| T8 | mie bits set (MEIE+MTIE+MSIE) | 0x888 | 0x888 | PASS |

#### Group 4 — CSRRC clear bits (1 TC)

| TC | Tên | Clear mask | Kỳ vọng | Status |
|----|-----|-----------|---------|--------|
| T9 | MTIE cleared (MEIE+MSIE remain) | clear 0x80 (MTIE) | 0x808 | PASS |

#### Group 5 — CSRRWI immediate (1 TC)

| TC | Tên | Imm | Kỳ vọng | Status |
|----|-----|-----|---------|--------|
| T10 | mie = zimm(15) = 0x0F | 15 | 0x0000_000F | PASS |

#### Group 6 — ECALL exception (5 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T11 | flush on ecall | 1 | PASS |
| T12 | trap vector = mtvec_base (direct mode) | 0x0000_1000 | PASS |
| T13 | mepc = wb_pc | 0x0000_0100 | PASS |
| T14 | mcause=11 (ecall from M-mode) | 32'd11 | PASS |
| T15 | mstatus trap (MIE→0, MPIE saved, MPP=11) | 0x0000_1800 | PASS |

#### Group 7 — MRET (3 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T16 | flush on mret | 1 | PASS |
| T17 | zicsr_pc = mepc | 0x0000_0200 | PASS |
| T18 | mstatus after mret (MIE←MPIE=1) | 0x0000_1888 | PASS |

#### Group 8 — Load fault (3 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T19 | flush on load_fault | 1 | PASS |
| T20 | mcause=5 (load access fault) | 32'd5 | PASS |
| T21 | mepc=faulting pc | 0x0000_0050 | PASS |

#### Group 9 — Store fault (2 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T22 | flush on store_fault | 1 | PASS |
| T23 | mcause=7 (store access fault) | 32'd7 | PASS |

#### Group 10 — Illegal instruction (2 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T24 | flush on illegal | 1 | PASS |
| T25 | mcause=2 (illegal instruction) | 32'd2 | PASS |

#### Group 11 — MEI interrupt (5 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T26 | flush on MEI | meip_in=1, MIE=1, MEIE=1 | 1 | PASS |
| T27 | zicsr_pc = BASE+44 (MEI vectored) | mtvec=0x2001 (vectored); MEI offset=44 | 0x0000_202C | PASS |
| T28 | mepc = wb_pc+4 | interrupt PC saved | 0x0000_0084 | PASS |
| T29 | mcause=0x8000_000B | machine external interrupt | 0x8000_000B | PASS |
| T30 | mstatus MIE=0 in handler | MIE cleared on trap entry | 0x0000_1880 | PASS |

#### Group 12 — MSI interrupt (3 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T31 | flush on MSI | 1 | PASS |
| T32 | zicsr_pc = mtvec_base+12 (MSI vectored) | 0x0000_200C | PASS |
| T33 | mcause=0x8000_0003 | machine software interrupt | 0x8000_0003 | PASS |

#### Group 13 — bus_stall_req suppresses trap (1 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T34 | flush=0 when bus_stall_req | bus_stall=1, ecall=1 | flush=0 (precise exception: bus not interrupted) | PASS |

#### Group 14 — Exception priority over interrupt (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T35 | flush fires | ecall + meip_in đồng thời | 1 | PASS |
| T36 | ecall wins over MEI (cause=11) | exception priority > interrupt | mcause=11 | PASS |

#### Group 15 — MIP read-back (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T37 | mip.MSIP=1 readable | write mip MSIP=1 | 0x0000_0008 | PASS |
| T38 | mip.MEIP=1 from meip_in | meip_in=1 (read-only reflect) | 0x0000_0808 | PASS |

---

---

---

## 1.7 Peripheral Modules — tb_gpio_sfr · tb_timer_axi · tb_gpio_ahb · tb_uart_axi

### New Unit 2: tb_gpio_sfr (22 TC)

**DUT:** `RTL/gpio_sfr.sv` — AXI-Lite GPIO peripheral, wraps `axi_sfr` + edge-detect IRQ. Interface: 32-bit `gpio_in/gpio_out`, `irq`.
**Cơ chế check:** `check1()` cho 1-bit; `check32()` cho 32-bit. Clk = 100MHz.

#### Group 1 — Reset state (2 TC)

| TC | Tên | Kỳ vọng | Status |
|----|-----|---------|--------|
| T1 | irq=0 after reset | 0 | PASS |
| T2 | gpio_out=0 after reset | 0x0 | PASS |

#### Group 2 — PERIPH_ID (1 TC)

| TC | Tên | Địa chỉ | Kỳ vọng | Status |
|----|-----|---------|---------|--------|
| T3 | PERIPH_ID=0x47504900 | 0xFC | 0x4750_4900 ("GPI\0") | PASS |

#### Group 3 — GPIO output (OE control) (4 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T4 | gpio_out=0 (DATA1[0]=0 → OE off) | DATA0=0xABCDEF01; DATA1[0]=0 | gpio_out=0 | PASS |
| T5 | gpio_out=DATA0 when OE=1 | DATA1[0]=1 | gpio_out=0xABCDEF01 | PASS |
| T6 | gpio_out=0 when OE=0 | DATA1[0]=0 | gpio_out=0 | PASS |
| T7 | DATA0 read-back | AXI read DATA0 | 0xABCDEF01 | PASS |

#### Group 4 — STATUS = gpio_in (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T8 | STATUS=gpio_in (bit0=0 sync'd) | gpio_in=0xFE (bit0=0); đợi 4 cycles | 0xFE | PASS |
| T9 | STATUS bit0 sync'd=1 | gpio_in=0x12345679 (bit0=1); đợi 4 cycles | 0x1234_5679 | PASS |

#### Group 5 — Edge-detect IRQ (3 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T10 | irq=0 before edge | INTR_EN=1, gpio_in[0]=0 | 0 | PASS |
| T11 | irq=1 after gpio_in[0] rising edge | gpio_in[0]=1; đợi 4 cycles | 1 | PASS |
| T12 | INTR_STATE[0]=1 | AXI read INTR_STATE | 0x1 | PASS |

#### Group 6 — INTR_STATE W1C (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T13 | irq=0 after W1C | write INTR_STATE[0]=1 (W1C) | irq=0 | PASS |
| T14 | INTR_STATE=0 after W1C | AXI read | 0x0 | PASS |

#### Group 7 — INTR_TEST (3 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T15 | irq=1 via INTR_TEST | write INTR_TEST[0]=1, no hw event | irq=1 | PASS |
| T16 | INTR_STATE=1 via INTR_TEST | AXI read | 0x1 | PASS |
| T17 | irq=0 after clearing INTR_TEST state | W1C clear | irq=0 | PASS |

#### Group 8 — IRQ masking (2 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T18 | irq=0 when INTR_EN=0 despite pending | INTR_EN=0; rising edge | irq=0 | PASS |
| T19 | INTR_STATE set even when masked | AXI read INTR_STATE | 0x1 (pending nhưng masked) | PASS |

#### Group 9 — DATA write/read (3 TC)

| TC | Tên | Setup | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| T20 | DATA0 read-back | write 0xDEAD_BEEF | 0xDEAD_BEEF | PASS |
| T21 | DATA1 read-back | write 0xCAFE_0001 | 0xCAFE_0001 | PASS |
| T22 | gpio_out=DATA0 (OE=1) | DATA1[0]=1 → OE=1 | gpio_out=0xDEAD_BEEF | PASS |

---

---

### Unit: tb_timer_axi (23 TC)

**Testbench:** `SIM/unit/tb_timer_axi.sv`
**DUT:** `timer_axi` — AXI-Lite Timer (1GHz, AXI S1 = 0x2000_1000).
**Cơ chế:** prescaler+compare IRQ; DATA0=PRESCALER, DATA1=COMPARE, STATUS=timer_cnt; auto_reload via CTRL[1].
**Tasks:** `axi_write`, `axi_read`, `check32`, `check1` (standard AXI-Lite single-beat R/W).

#### T1 — Reset state (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 1 | irq=0 after reset | Kiểm tra irq=0 ngay sau reset | 0 | PASS |

#### T2 — PERIPH_ID (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 2 | PERIPH_ID=TIMR | Read offset 0xFC; 4 ASCII bytes "TIMR" = 0x5449_4D52 | 0x5449_4D52 | PASS |

#### T3 — Register write/read (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 3 | DATA0 (PRESCALER) read-back | Write 9 → read DATA0 | 9 | PASS |
| 4 | DATA1 (COMPARE) read-back | Write 100 → read DATA1 | 100 | PASS |
| 5 | CTRL read-back (3) | Write 3 (enable+auto_reload) → read CTRL | 3 | PASS |

#### T4 — Timer disabled (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 6 | STATUS=0 when disabled | Sau reset, 20 cycles, đọc STATUS; timer không chạy | 0 | PASS |
| 7 | irq=0 when disabled | irq không fire khi timer disabled | 0 | PASS |

#### T5 — Timer counts (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 8 | STATUS nonzero after enable | PRESCALER=0, COMPARE=50, CTRL=1; sau 5 cycles đọc STATUS | >0 | PASS |

#### T6 — Compare match → INTR_STATE (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 9 | INTR_STATE[0]=1 on compare match | PRESCALER=0, COMPARE=8, enable; chờ 20 cycles | 1 | PASS |

#### T7 — IRQ masking (enable) (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 10 | irq=1 with INTR_STATE set and INTR_ENABLE=1 | INTR_STATE[0] còn set từ T6; write INTR_ENABLE=1 | 1 | PASS |

#### T8 — IRQ masked (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 11 | irq=0 with INTR_ENABLE=0 | Write INTR_ENABLE=0; irq bị mask | 0 | PASS |

#### T9 — W1C clear INTR_STATE (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 12 | irq=1 before W1C | Re-enable INTR_ENABLE=1; irq phải=1 | 1 | PASS |
| 13 | irq=0 after W1C | Write 0x1 vào INTR_STATE (W1C bit0) | 0 | PASS |
| 14 | INTR_STATE=0 after W1C | Đọc lại INTR_STATE sau W1C | 0 | PASS |

#### T10 — INTR_TEST (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 15 | irq=1 via INTR_TEST | Write INTR_TEST=1; INTR_ENABLE=1; irq phải fire | 1 | PASS |
| 16 | INTR_STATE=1 via INTR_TEST | Đọc INTR_STATE sau INTR_TEST | 1 | PASS |
| 17 | irq=0 after clearing INTR_TEST state | W1C INTR_STATE; irq=0 | 0 | PASS |

#### T11 — Auto-reload (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 18 | INTR_STATE[0]=1 after auto_reload match | COMPARE=5, CTRL=3; chờ 30 cycles | 1 | PASS |
| 19 | STATUS ≤ COMPARE (auto_reload working) | timer_cnt reset sau compare-match khi auto_reload | ≤5 | PASS |

#### T12 — Counter runs past compare without auto_reload (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 20 | STATUS > COMPARE (no auto_reload) | COMPARE=3, CTRL=1 (no auto_reload); chờ 20 cycles; STATUS tiếp tục đếm | >3 | PASS |

#### T13 — Timer stops on disable (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 21 | Counter frozen after disable | Capture STATUS sau CTRL=0; chờ 10 cycles; đọc lại | Bằng cnt_before | PASS |

#### T14 — PRESCALER divides tick rate (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 22 | STATUS=1 after ~7 cycles with PRESCALER=4 | PRESCALER=4 → tick mỗi 5 cycles; đọc STATUS sau ~7 cycles | 1 | PASS |
| 23 | INTR_STATE[0]=1 with PRESCALER=4 | COMPARE=2; với PRESCALER=4 match tại cycle 15 | 1 | PASS |

---

---

### Unit: tb_gpio_ahb (21 TC)

**Testbench:** `SIM/unit/tb_gpio_ahb.sv`
**DUT:** `gpio_ahb` — AHB-Lite GPIO (500MHz, AHB S0 = 0x3000_0000).
**Cơ chế:** 2-FF sync cho gpio_in; edge-detect (rising/falling via DATA2[0]); DATA0=out value, DATA1[0]=OE.
**Tasks:** `ahb_write`, `ahb_read` (AHB non-pipelined: address phase → data phase); `check32`, `check1`.

#### G1 — Reset state (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 1 | irq=0 after reset | irq phải=0 sau rst_ahb_n | 0 | PASS |
| 2 | gpio_out=0 after reset | gpio_out phải=0 sau reset | 0 | PASS |

#### G2 — PERIPH_ID (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 3 | PERIPH_ID=GPIA | Read offset 0xFC; 4 ASCII "GPIA" = 0x4750_4941 | 0x4750_4941 | PASS |

#### G3 — gpio_out control (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 4 | gpio_out=0 (OE off) | Write DATA0=0xDEAD_BEEF; DATA1[0]=0; gpio_out phải=0 | 0 | PASS |
| 5 | gpio_out=DATA0 when OE=1 | Write DATA1=1 (OE on) | 0xDEAD_BEEF | PASS |
| 6 | gpio_out=0 when OE=0 | Write DATA1=0 (OE off) | 0 | PASS |

#### G4 — DATA0 read-back (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 7 | DATA0 read-back | Đọc DATA0 sau khi đã write 0xDEAD_BEEF | 0xDEAD_BEEF | PASS |

#### G5 — STATUS = sync'd gpio_in (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 8 | STATUS=0x55 after sync settle | gpio_in=0x55; chờ 4 cycles (2-FF sync settle); đọc STATUS | 0x55 | PASS |

#### G6 — Rising edge detect → INTR_STATE (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 9 | irq=0 before rising edge | INTR_EN=1; gpio_in[0]=0; irq=0 | 0 | PASS |
| 10 | irq=1 after gpio_in[0] rising edge | gpio_in[0] → 1; chờ 5 cycles | 1 | PASS |
| 11 | INTR_STATE[0]=1 on rising edge | Đọc INTR_STATE | 1 | PASS |

#### G7 — W1C clear (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 12 | irq=0 after W1C | Write 0x1 vào INTR_STATE (W1C) | 0 | PASS |
| 13 | INTR_STATE=0 after W1C | Đọc lại INTR_STATE | 0 | PASS |

#### G8 — IRQ masking (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 14 | irq=0 with INTR_EN=0 (masked) | INTR_EN=0; rising edge gpio_in[0]; irq=0 | 0 | PASS |
| 15 | INTR_STATE[0]=1 even when masked | INTR_STATE vẫn set dù irq bị mask | 1 | PASS |

#### G9 — INTR_TEST (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 16 | irq=1 via INTR_TEST | Write INTR_TEST=1; INTR_EN=1 | 1 | PASS |
| 17 | INTR_STATE=1 via INTR_TEST | Đọc INTR_STATE sau INTR_TEST | 1 | PASS |
| 18 | irq=0 after clearing INTR_TEST | W1C INTR_STATE | 0 | PASS |

#### G10 — Falling edge detect (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 19 | irq=1 on falling edge (DATA2[0]=1) | DATA2=1 (falling edge mode); gpio_in[0] 1→0 | 1 | PASS |
| 20 | INTR_STATE[0]=1 on falling edge | Đọc INTR_STATE | 1 | PASS |

#### G11 — No spurious IRQ (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 21 | INTR_STATE=0 when gpio_in stable | gpio_in=0xAAAA_AAAA stable; chờ 10 cycles | 0 | PASS |

---

---

### Unit: tb_uart_axi (27 TC)

**Testbench:** `SIM/unit/tb_uart_axi.sv`
**DUT:** `uart_axi` — AXI-Lite 8N1 UART (1GHz, AXI S2 = 0x2000_2000).
**Cơ chế:** TX FSM 4-state; RX FSM 4-state + 2-FF sync; baud_div=DATA0; DATA1 write=TX trigger; DATA2 read=RX data; INTR_STATE[0]=tx_done, [1]=rx_complete.
**Tasks:** `axi_write`, `axi_read`, `uart_rx_send` (drives uart_rx trực tiếp đúng 8N1 frame), `capture_tx_frame` (sample uart_tx per-bit), `check32`, `check1`.

#### U1 — Reset state (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 1 | uart_tx=1 (idle) after reset | TX line ở high (idle) sau reset | 1 | PASS |
| 2 | irq=0 after reset | irq=0 sau reset | 0 | PASS |

#### U2 — PERIPH_ID (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 3 | PERIPH_ID=UART | Read offset 0xFC; 4 ASCII "UART" = 0x5541_5254 | 0x5541_5254 | PASS |

#### U3 — Register write/read (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 4 | DATA0 (baud_div) read-back | Write BAUD_DIV=3 → read DATA0 | 3 | PASS |
| 5 | CTRL=0 read-back | Write CTRL=0 → read CTRL | 0 | PASS |

#### U4 — TX disabled when uart_en=0 (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 6 | uart_tx=1 (no TX when disabled) | CTRL=0; write DATA1 → TX không khởi động | 1 | PASS |

#### U5 — TX frame 0xA5 (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 7 | TX byte received = 0xA5 | Capture uart_tx frame trong fork; reconstruct byte | 0xA5 | PASS |
| 8 | start bit = 0 | tx_bits[0] phải=0 (start bit) | 0 | PASS |
| 9 | stop bit = 1 | tx_bits[9] phải=1 (stop bit) | 1 | PASS |

#### U6 — tx_busy STATUS[0] (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 10 | STATUS[0]=1 (tx_busy during TX) | Đọc STATUS ngay sau khi trigger TX (frame dài ~40 cycles) | 1 | PASS |
| 11 | uart_tx=1 (idle after TX) | Sau 60+ cycles, uart_tx trở về idle | 1 | PASS |

#### U7 — tx_done IRQ (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 12 | irq=1 after tx_done | INTR_EN=1 (bit0); chờ TX hoàn thành | 1 | PASS |
| 13 | INTR_STATE[0]=1 (tx_done) | Đọc INTR_STATE | 1 | PASS |

#### U8 — W1C (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 14 | irq=0 after W1C | Write 0x1 vào INTR_STATE (W1C bit0) | 0 | PASS |
| 15 | INTR_STATE=0 after W1C | Đọc lại INTR_STATE | 0 | PASS |

#### U9 — INTR_TEST (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 16 | INTR_STATE=3 via INTR_TEST | Write INTR_TEST=3 (force cả bit0 và bit1) | 3 | PASS |
| 17 | irq=1 via INTR_TEST | INTR_EN=1; irq phải fire | 1 | PASS |
| 18 | irq=0 after clearing | W1C toàn bộ INTR_STATE | 0 | PASS |

#### U10 — TX busy guard (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 19 | STATUS[0]=1 (tx_busy) | Đọc STATUS ngay sau trigger TX | 1 | PASS |
| 20 | uart_tx=1 (idle after busy-guard TX) | Write 2nd DATA1 khi busy bị block; TX hoàn thành bình thường | 1 | PASS |

#### U11 — RX frame 0xC3 (3 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 21 | DATA2 = 0xC3 after RX | uart_rx_send(0xC3); đọc DATA2 | 0xC3 | PASS |
| 22 | INTR_STATE[1]=1 (rx_complete) | Đọc INTR_STATE sau RX | 2 (bit1) | PASS |
| 23 | irq=1 after rx_complete | INTR_EN=2 (bit1); irq phải fire | 1 | PASS |

#### U12 — RX W1C (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 24 | irq=0 after RX W1C | Write 0x2 vào INTR_STATE (W1C bit1) | 0 | PASS |

#### U13 — RX masked (2 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 25 | irq=0 with RX masked | INTR_EN=0; uart_rx_send(0xAA); irq=0 | 0 | PASS |
| 26 | DATA2=0xAA (RX stored even when masked) | RX data vẫn được lưu dù irq bị mask | 0xAA | PASS |

#### U14 — UART loopback (1 TC)

| TC | Tên | Mô tả | Kỳ vọng | Status |
|----|-----|-------|---------|--------|
| 27 | Loopback TX byte = 0x6F | TX 0x6F; capture_tx_frame trong fork | 0x6F | PASS |

---


---

## ═══ PHẦN 2: INTEGRATION TESTS ═══

Kiểm tra nhiều module phối hợp với nhau, chưa full SoC.

---

## Phase 3 — Integration: tb_pipeline_cpu (9 programs)

**Testbench:** `SIM/integration/tb_pipeline_cpu.sv`
**Cơ chế:** Mỗi program chạy trên full SoC (`soc_top`). Kết thúc bằng `EBREAK`; testbench đọc `x31`: `1` = PASS, `0` = FAIL (hoặc timeout 200000 cycles = FAIL).
**Số testcase:** 9 (mỗi program = 1 testcase)
**Kết quả tổng:** 9/9 PASS

---

### Phase 3 — Testcase 1: prog_arithmetic

**File:** `SIM/programs/prog_arithmetic.s`
**Mục tiêu:** Kiểm tra các phép toán ALU R-type và I-type chạy đúng trong pipeline 7 tầng (không cần forwarding phức tạp).

| # | Phép toán kiểm tra | Input | Kỳ vọng | Cách verify | Status | Mức độ |
|---|-------------------|-------|---------|-------------|--------|--------|
| 1 | ADD (R-type)    | x1=10, x2=20 | x3=30 | `bne x3,x4,fail` | PASS | Critical |
| 2 | SUB (R-type)    | x2=20, x1=10 | x5=10 | `bne x5,x1,fail` | PASS | Critical |
| 3 | AND (R-type)    | 0x0F & 0xFF | x8=0x0F | `bne x8,x6,fail` | PASS | Critical |
| 4 | OR  (R-type)    | 0x0F \| 0xFF | x9=0xFF | `bne x9,x7,fail` | PASS | Critical |
| 5 | XOR (R-type)    | 0xFF ^ 0xFF | x10=0 | `bne x10,x0,fail` | PASS | Critical |
| 6 | SLL (R-type)    | 1 << 1 | x12=2 | `bne x12,x13,fail` | PASS | Critical |
| 7 | SRL (R-type)    | 8 >> 1 | x16=4 | `bne x16,x17,fail` | PASS | Critical |
| 8 | SRA (R-type)    | -4 >> 1 (signed) | x20=-2 | `bne x20,x21,fail` | PASS | Critical |
| 9 | SLT (R-type)    | -1 < 0 (signed) | x23=1 | `bne x23,x24,fail` | PASS | Critical |
| 10 | SLTU (R-type)  | 1 <u 0 → false | x26=0 | `bne x26,x0,fail` | PASS | Critical |

**Ghi chú:** 10 self-check `bne...fail` bên trong program; verdict duy nhất là x31=1 tại EBREAK.

---

### Phase 3 — Testcase 2: prog_forwarding

**File:** `SIM/programs/prog_forwarding.s`
**Mục tiêu:** Kiểm tra forwarding unit hoạt động đúng ở tất cả gap (0/1/2) trong pipeline 7 tầng; bao gồm forward vào branch comparator và forward sau load-use stall.

| # | Tình huống forwarding | Cơ chế | Kỳ vọng | Status | Mức độ |
|---|----------------------|--------|---------|--------|--------|
| 1 | MEM1 forward (gap 0) | `addi x1,x0,5` → `addi x2,x1,3` | x2=8 | PASS | Critical |
| 2 | MEM2 forward (gap 1) | `addi x4,...` + 1 NOP + `addi x6,x4,5` | x6=15 | PASS | Critical |
| 3 | WB forward (gap 2)   | `addi x8,...` + 2 NOP + `addi x11,x8,5` | x11=25 | PASS | Critical |
| 4 | Double forward (rs1+rs2) | x13 từ MEM2, x14 từ MEM1 → `add x15,x13,x14` | x15=10 | PASS | Critical |
| 5 | Chain forward         | x17→x18→x19, mỗi instruction liên tiếp | x19=3 | PASS | Critical |
| 6 | Forward vào branch comparator | `addi x21,x0,42` → `beq x21,x0,fail` | branch NOT taken | PASS | High |
| 7 | Load-use stall + MEM2 forward | LW x24 → 1 bubble → `add x25,x24,x24` | x25=198 | PASS | Critical |

---

### Phase 3 — Testcase 3: prog_load_store

**File:** `SIM/programs/prog_load_store.s`
**Mục tiêu:** Kiểm tra đầy đủ các instruction memory access (SW, LW, SB, LB, LBU, SH, LH, LHU) với sign-extension và zero-extension, bao gồm load-use stall.

| # | Instruction | Input | Kỳ vọng | Status | Mức độ |
|---|------------|-------|---------|--------|--------|
| 1 | SW + LW    | store 0xAB, load | x3=0xAB (với 1 bubble load-use) | PASS | Critical |
| 2 | SW(-1) + LW | store -1 (0xFFFFFFFF), load | x3=0xFFFFFFFF | PASS | Critical |
| 3 | SB + LBU   | store 0xFF byte, LBU | x3=255 (zero-extend) | PASS | Critical |
| 4 | SB + LB    | store 0xFF byte, LB | x5=-1 (sign-extend) | PASS | Critical |
| 5 | SH + LHU   | store 0xFFFF half, LHU | x3=65535 (zero-extend) | PASS | Critical |
| 6 | SH + LH    | store 0xFFFF half, LH | x5=-1 (sign-extend) | PASS | Critical |
| 7 | SB + LBU vs LB (positive) | store 100=0x64 | LBU=100, LB=100 (no sign bit) | PASS | High |
| 8 | SH + LHU vs LH (positive) | store 1000=0x3E8 | LHU=1000, LH=1000 (no sign bit) | PASS | High |

---

### Phase 3 — Testcase 4: prog_branch_jump

**File:** `SIM/programs/prog_branch_jump.s`
**Mục tiêu:** Kiểm tra tất cả 6 branch type (taken/not-taken) + JAL + JALR + backward branch (loop).

| # | Instruction | Điều kiện | Kỳ vọng | Status | Mức độ |
|---|------------|-----------|---------|--------|--------|
| 1 | BEQ taken    | x1=x2=5 | nhảy đến `beq_ok` | PASS | Critical |
| 2 | BEQ not taken | x1=5 ≠ x3=6 | không nhảy, tiếp tục | PASS | Critical |
| 3 | BNE taken    | x1≠x3 | nhảy đến `bne_ok` | PASS | Critical |
| 4 | BNE not taken | x1=x2=5 | không nhảy | PASS | Critical |
| 5 | BLT taken (signed) | -1 < 0 | nhảy đến `blt_ok` | PASS | Critical |
| 6 | BLT not taken (signed) | 0 < -1 → false | không nhảy | PASS | Critical |
| 7 | BGE taken    | 0 >= -1 | nhảy đến `bge_ok` | PASS | Critical |
| 8 | BGE not taken | -1 >= 0 → false | không nhảy | PASS | Critical |
| 9 | BGE equal case | 5 >= 5 | nhảy đến `bge_eq` | PASS | Critical |
| 10 | BLTU taken (unsigned) | 1 <u 0xFFFFFFFF | nhảy đến `bltu_ok` | PASS | Critical |
| 11 | BLTU not taken | 0xFFFFFFFF <u 1 → false | không nhảy | PASS | Critical |
| 12 | BGEU taken   | 0xFFFFFFFF >=u 1 | nhảy đến `bgeu_ok` | PASS | Critical |
| 13 | JAL x0 (pure jump) | — | nhảy đến `jal0_land` | PASS | Critical |
| 14 | Backward branch (loop 5×) | counter=5 | accumulator=5 sau vòng lặp | PASS | High |
| 15 | JALR         | x14=auipc+16, JALR x15,x14,0 | jump đến jalr_target, x15=link addr | PASS | Critical |

---

### Phase 3 — Testcase 5: prog_csr

**File:** `SIM/programs/prog_csr.s`
**Mục tiêu:** Kiểm tra đầy đủ 6 CSR instruction (CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI) bao gồm semantics read-modify-write, rs1=x0 suppression, và immediate form.

| # | Instruction | Hành động | Kỳ vọng | Status | Mức độ |
|---|------------|-----------|---------|--------|--------|
| 1 | CSRRS mie, x0 | read mie, no write (rs1=x0) | x1=0 (mie reset=0) | PASS | Critical |
| 2 | CSRRW mie, x2=8 | old→x3, mie←8 | x3=0 (old), mie=8 | PASS | Critical |
| 3 | CSRRS mie, x0 | read back | x4=8 | PASS | Critical |
| 4 | CSRRS mie, x5=0x80 | set MTIE; old→x6 | x6=8 (old), mie=0x88 | PASS | Critical |
| 5 | CSRRS mie, x0 | read back | x8=0x88 | PASS | Critical |
| 6 | CSRRC mie, x2=8 | clear MSIE; old→x9 | x9=0x88 (old), mie=0x80 | PASS | Critical |
| 7 | CSRRS mie, x0 | read back | x10=0x80 | PASS | Critical |
| 8 | CSRRWI mie, imm=8 | write imm; old→x11 | x11=0x80 (old), mie=8 | PASS | Critical |
| 9 | CSRRS mie, x0 | read back | x12=8 | PASS | Critical |
| 10 | CSRRSI mie, imm=16 | set via imm; old→x13 | x13=8, mie=0x18 | PASS | Critical |
| 11 | CSRRS mie, x0 | read back | x15=0x18 | PASS | Critical |
| 12 | CSRRCI mie, imm=8 | clear via imm; old→x16 | x16=0x18, mie=0x10 | PASS | Critical |
| 13 | CSRRS mie, x0 | read back | x18=0x10 | PASS | Critical |
| 14 | CSRRW mtvec, 0x40 | write mtvec; old→x20 | x20=0 (reset), mtvec=0x40 | PASS | Critical |
| 15 | CSRRS mtvec, x0 | read back | x21=0x40 | PASS | Critical |
| 16 | CSRRC mtvec, x0 | read only (rs1=x0) | x22=0x40 (unchanged) | PASS | Critical |

---

### Phase 3 — Testcase 6: prog_ecall

**File:** `SIM/programs/prog_ecall.s`
**Mục tiêu:** Kiểm tra precise exception cho ECALL: trap vào handler, mcause=11, mepc trỏ đúng, mstatus.MIE=0 trong trap, MRET khôi phục trạng thái.

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | ECALL trigger trap | Handler được gọi (không execute tiếp sau ECALL) | PASS | Critical |
| 2 | mcause = 11 (M-mode ECALL) | x20=11 | PASS | Critical |
| 3 | mepc = địa chỉ ECALL | x21 = addr(ecall_target) | PASS | Critical |
| 4 | mstatus.MIE=0 trong trap | x9=0 (MIE bị clear khi trap) | PASS | Critical |
| 5 | MRET trả về đúng (mepc+4) | Resume tại `addi x3,x0,1` sau ECALL | PASS | Critical |
| 6 | mstatus.MIE khôi phục sau MRET | x5 & 8 == 8 | PASS | Critical |

---

### Phase 3 — Testcase 7: prog_interrupt_msi

**File:** `SIM/programs/prog_interrupt_msi.s`
**Mục tiêu:** Kiểm tra software interrupt (MSI): set mip.MSIP, interrupt fires đúng thời điểm, handler verify mcause=0x80000003, clear interrupt, MRET.

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | Interrupt fires sau khi set mip.MSIP + mie.MSIE + mstatus.MIE | Thực thi `msi_handler` | PASS | Critical |
| 2 | mcause = 0x80000003 (interrupt bit=1, cause=3) | x20=0x80000003 | PASS | Critical |
| 3 | mstatus.MIE=0 trong trap | x23=0 | PASS | Critical |
| 4 | mip.MSIP cleared, MRET trả về đúng, x28=1 | x28=1 sau MRET | PASS | Critical |

---

### Phase 3 — Testcase 8: prog_interrupt_mei

**File:** `SIM/programs/prog_interrupt_mei.s`
**Mục tiêu:** Kiểm tra machine external interrupt (MEI) qua PLIC: set priority/enable/threshold, trigger AXI SFR0 IRQ qua INTR_TEST, PLIC claim, mcause=0x8000000B, MRET.

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | PLIC init + AXI IRQ trigger fires MEI | Thực thi `mei_handler` (không reach `j fail`) | PASS | Critical |
| 2 | mcause = 0x8000000B (interrupt bit=1, cause=11) | x20=0x8000000B | PASS | Critical |
| 3 | mstatus.MIE=0 trong trap | x23=0 | PASS | Critical |
| 4 | MRET trả về `pass` (mepc override) | x31=1 tại EBREAK | PASS | Critical |

---

### Phase 3 — Testcase 9: prog_load_fault

**File:** `SIM/programs/prog_load_fault.s`
**Mục tiêu:** Kiểm tra precise exception cho load access fault: load từ unmapped address (0x40000000), mcause=5, mepc trỏ đúng instruction, MRET redirect đến `pass`.

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | Load fault trigger trap | Handler được gọi (không execute tiếp sau LW) | PASS | Critical |
| 2 | mcause = 5 (load access fault) | x20=5 | PASS | Critical |
| 3 | mepc = địa chỉ LW instruction | x22 = addr(load_instr) | PASS | Critical |
| 4 | mstatus.MIE=0 trong trap | x25=0 | PASS | Critical |
| 5 | MRET redirect đến `pass` | x31=1 tại EBREAK | PASS | Critical |

---

### Tổng kết Phase 3

| Testcase | Program | Số self-check nội bộ | PASS | FAIL | Mức độ |
|---------|---------|----------------------|------|------|--------|
| 1 | prog_arithmetic    | 10 | PASS | 0 | Critical |
| 2 | prog_forwarding    | 7  | PASS | 0 | Critical |
| 3 | prog_load_store    | 10 | PASS | 0 | Critical |
| 4 | prog_branch_jump   | 15 | PASS | 0 | Critical |
| 5 | prog_csr           | 16 | PASS | 0 | Critical |
| 6 | prog_ecall         | 6  | PASS | 0 | Critical |
| 7 | prog_interrupt_msi | 4  | PASS | 0 | Critical |
| 8 | prog_interrupt_mei | 4  | PASS | 0 | Critical |
| 9 | prog_load_fault    | 5  | PASS | 0 | Critical |
| **Tổng Phase 3** | — | **77 self-checks** | **9/9** | **0** | **Critical** |

**Ghi chú định nghĩa:** Testcase đơn vị của Phase 3 là **1 program** (tb_pipeline_cpu chỉ báo PASS/FAIL per-program, không có `pass_cnt`). Cột "self-check nội bộ" là số `bne...fail` branch trong assembly, không phải testcase của testbench.

---

---

---

## Phase 4a — Integration: tb_axi_interface (49 testcases)

**Testbench:** `SIM/integration/tb_axi_interface.sv`
**DUT:** `RTL/axi_interface.sv` kết nối với `axi_slave_model`
**Cơ chế:** `pass_cnt` tăng mỗi lần gọi `pass_if()`. Mỗi `do_write()` = 2 TC (WSTRB + resp_err); mỗi `do_read()` = 2 TC (RDATA + resp_err); một số call thêm 1 TC kiểm tra `cap_wdata`/`cap_awaddr`/`cap_araddr`.
**Số testcase:** 49
**Kết quả tổng:** 49/49 PASS

---

### Group 1 — Basic Write / Read (TC 1–24)

| TC | Loại | Địa chỉ | Input | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|------|---------|-------|---------|---------|--------|--------|
| 1 | Write word | 0x2000_0000 | DEADBEEF, size=2 | WSTRB | 4'b1111 | PASS | Critical |
| 2 | Write word | 0x2000_0000 | inject_err=0 | resp_err | 0 | PASS | Critical |
| 3 | Read word | 0x2000_0000 | — | resp_rdata | 0xDEAD_BEEF | PASS | Critical |
| 4 | Read word | 0x2000_0000 | inject_err=0 | resp_err | 0 | PASS | Critical |
| 5 | Write word | 0x2000_0004 | CAFEF00D, size=2 | WSTRB | 4'b1111 | PASS | Critical |
| 6 | Write word | 0x2000_0004 | inject_err=0 | resp_err | 0 | PASS | Critical |
| 7 | Read word | 0x2000_0004 | — | resp_rdata | 0xCAFE_F00D | PASS | Critical |
| 8 | Read word | 0x2000_0004 | inject_err=0 | resp_err | 0 | PASS | Critical |
| 9 | Write half @ offset 0 | 0x2000_0008 | 0x0000ABCD, size=1 | WSTRB | 4'b0011 | PASS | Critical |
| 10 | Write half @ offset 0 | 0x2000_0008 | inject_err=0 | resp_err | 0 | PASS | Critical |
| 11 | Write half @ offset 2 | 0x2000_000A | 0x00001234, size=1 | WSTRB | 4'b1100 | PASS | Critical |
| 12 | Write half @ offset 2 | 0x2000_000A | inject_err=0 | resp_err | 0 | PASS | Critical |
| 13 | Write byte @ offset 0 | 0x2000_000C | 0xAA, size=0 | WSTRB | 4'b0001 | PASS | Critical |
| 14 | Write byte @ offset 0 | 0x2000_000C | inject_err=0 | resp_err | 0 | PASS | Critical |
| 15 | Write byte @ offset 1 | 0x2000_000D | 0xBB, size=0 | WSTRB | 4'b0010 | PASS | Critical |
| 16 | Write byte @ offset 1 | 0x2000_000D | inject_err=0 | resp_err | 0 | PASS | Critical |
| 17 | Write byte @ offset 2 | 0x2000_000E | 0xCC, size=0 | WSTRB | 4'b0100 | PASS | Critical |
| 18 | Write byte @ offset 2 | 0x2000_000E | inject_err=0 | resp_err | 0 | PASS | Critical |
| 19 | Write byte @ offset 3 | 0x2000_000F | 0xDD, size=0 | WSTRB | 4'b1000 | PASS | Critical |
| 20 | Write byte @ offset 3 | 0x2000_000F | inject_err=0 | resp_err | 0 | PASS | Critical |
| 21 | Write + BRESP SLVERR | 0x2000_0010 | inject_bresp_err=1 | WSTRB | 4'b1111 | PASS | High |
| 22 | Write + BRESP SLVERR | 0x2000_0010 | inject_bresp_err=1 | resp_err | 1 (lỗi báo lên CPU) | PASS | High |
| 23 | Read + RRESP SLVERR | 0x2000_0000 | inject_rresp_err=1 | resp_rdata | 0xDEAD_BEEF | PASS | High |
| 24 | Read + RRESP SLVERR | 0x2000_0000 | inject_rresp_err=1 | resp_err | 1 | PASS | High |

---

### Group 2 — WDATA Byte/Half Replication (TC 25–39)

AXI interface nhân bản byte/half lên 32 bit để slave đọc đúng byte lane. Kiểm tra cả WSTRB + resp_err + `cap_wdata`.

| TC | Loại | Địa chỉ | req_wdata | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|------|---------|-----------|---------|---------|--------|--------|
| 25 | Write word @ 0x20 | 0x2000_0020 | 0xBEEF_CAFE | WSTRB | 4'b1111 | PASS | High |
| 26 | Write word @ 0x20 | — | — | resp_err | 0 | PASS | High |
| 27 | WDATA word | — | 0xBEEF_CAFE | cap_wdata | 0xBEEF_CAFE (không đổi) | PASS | High |
| 28 | Write half @ offset 0 | 0x2000_0024 | 0x0000_FACE | WSTRB | 4'b0011 | PASS | High |
| 29 | Write half @ offset 0 | — | — | resp_err | 0 | PASS | High |
| 30 | WDATA half replication | — | lower 16=FACE | cap_wdata | 0xFACE_FACE | PASS | High |
| 31 | Write half @ offset 2 | 0x2000_0026 | 0x0000_BABE | WSTRB | 4'b1100 | PASS | High |
| 32 | Write half @ offset 2 | — | — | resp_err | 0 | PASS | High |
| 33 | WDATA half replication | — | lower 16=BABE | cap_wdata | 0xBABE_BABE | PASS | High |
| 34 | Write byte @ offset 0 | 0x2000_0028 | 0x0000_0042 | WSTRB | 4'b0001 | PASS | High |
| 35 | Write byte @ offset 0 | — | — | resp_err | 0 | PASS | High |
| 36 | WDATA byte replication | — | byte=0x42 | cap_wdata | 0x4242_4242 | PASS | High |
| 37 | Write byte @ offset 1 | 0x2000_0029 | 0x0000_00AB | WSTRB | 4'b0010 | PASS | High |
| 38 | Write byte @ offset 1 | — | — | resp_err | 0 | PASS | High |
| 39 | WDATA byte replication | — | byte=0xAB | cap_wdata | 0xABAB_ABAB | PASS | High |

---

### Group 3 — Address Propagation (TC 40–45)

Kiểm tra AWADDR và ARADDR trên bus khớp với địa chỉ CPU gửi xuống.

| TC | Loại | Địa chỉ CPU | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|------|------------|---------|---------|--------|--------|
| 40 | Write | 0x2000_002C | WSTRB | 4'b1111 | PASS | Medium |
| 41 | Write | 0x2000_002C | resp_err | 0 | PASS | Medium |
| 42 | AWADDR propagation | 0x2000_002C | cap_awaddr | 0x2000_002C | PASS | Critical |
| 43 | Read | 0x2000_002C | resp_rdata | 0xDEAD_C0DE | PASS | Medium |
| 44 | Read | 0x2000_002C | resp_err | 0 | PASS | Medium |
| 45 | ARADDR propagation | 0x2000_002C | cap_araddr | 0x2000_002C | PASS | Critical |

---

### Group 4 — Sequential Write-then-Read (TC 46–49)

| TC | Loại | Địa chỉ | Data | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|------|---------|------|---------|---------|--------|--------|
| 46 | Write | 0x2000_0030 | 0x5A5A_A5A5 | WSTRB | 4'b1111 | PASS | Medium |
| 47 | Write | 0x2000_0030 | — | resp_err | 0 | PASS | Medium |
| 48 | Read | 0x2000_0030 | — | resp_rdata | 0x5A5A_A5A5 | PASS | Medium |
| 49 | Read | 0x2000_0030 | — | resp_err | 0 | PASS | Medium |

---

### Tổng kết Phase 4a

| Testbench | Số testcase | PASS | FAIL | Tỷ lệ |
|-----------|-------------|------|------|--------|
| tb_axi_interface | 49 | 49 | 0 | 100% |

---

---

---

## Phase 4b — Integration: tb_ahb_interface (29 testcases)

**Testbench:** `SIM/integration/tb_ahb_interface.sv`
**DUT:** `RTL/ahb_interface.sv` + 2× `async_fifo_depth2` (req 67-bit + resp 33-bit) + `ahb_slave_model`
**Cơ chế:** `pass_cnt` tăng mỗi `chk()`/`chk3()`/`chk32()`. CDC thực: wr_clk=1GHz, rd_clk=500MHz lệch pha 0.7ns.
**Số testcase:** 29
**Kết quả tổng:** 29/29 PASS

---

### Group 1 — Basic Transactions (TC 1–15)

| TC | Tag | Giao dịch | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-----|----------|---------|---------|--------|--------|
| 1  | T1 err        | Word write 0xAABB_CCDD @ 0x3000_0000 | resp err | 0 | PASS | Critical |
| 2  | T2 HSIZE      | — | cap_hsize | 3 (word) | PASS | Critical |
| 3  | T3 HWRITE     | — | cap_hwrite | 1 (write) | PASS | Critical |
| 4  | T4 HWDATA     | — | cap_hwdata | 0xAABB_CCDD | PASS | Critical |
| 5  | T5 err        | Word read @ 0x3000_0000 | resp err | 0 | PASS | Critical |
| 6  | T6 RDATA      | — | rdata | 0xAABB_CCDD (read-back) | PASS | Critical |
| 7  | T7 HWRITE     | — | cap_hwrite | 0 (read) | PASS | Critical |
| 8  | T8 err        | Half-word write @ 0x3000_0004 | resp err | 0 | PASS | Critical |
| 9  | T9 HSIZE      | size=1 (half) | cap_hsize | 1 | PASS | Critical |
| 10 | T10 err       | Byte write @ 0x3000_0008 | resp err | 0 | PASS | Critical |
| 11 | T11 HSIZE     | size=0 (byte) | cap_hsize | 0 | PASS | Critical |
| 12 | T12 hresp_err | inject_err=1, read | resp err | 1 (HRESP ERROR → resp FIFO) | PASS | High |
| 13 | T13 err       | Write 0xDEAD_1234 @ 0x3000_0004 | resp err | 0 | PASS | Medium |
| 14 | T14 err       | Read back @ 0x3000_0004 | resp err | 0 | PASS | Medium |
| 15 | T15 RDATA     | — | rdata | 0xDEAD_1234 | PASS | Medium |

---

### Group 2 — Wait State / HREADY=0 (TC 16–24)

AHB slave có thể kéo `HREADY=0` trong data phase. DUT phải giữ HWDATA ổn định và chờ.

| TC | Tag | Tình huống | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-----|-----------|---------|---------|--------|--------|
| 16 | T16 wait_wr err   | Word write + insert_wait=1 | resp err | 0 | PASS | High |
| 17 | T17 wait_wr HSIZE | — | cap_hsize | 2 (word) | PASS | High |
| 18 | T18 wait_wr HWDATA| — | cap_hwdata | 0xCAFE_BABE (không corrupted) | PASS | High |
| 19 | T19 wait_rb err   | Read back @ 0x3000_0010 | resp err | 0 | PASS | High |
| 20 | T20 wait_rb RDATA | — | rdata | 0xCAFE_BABE | PASS | High |
| 21 | T21 wait_rd err   | Read @ 0x3000_0000 + insert_wait=1 | resp err | 0 | PASS | High |
| 22 | T22 wait_rd RDATA | — | rdata | 0xAABB_CCDD (từ T1) | PASS | High |
| 23 | T23 HADDR         | HADDR @ address phase của read vừa trên | cap_haddr | 0x3000_0000 | PASS | Critical |
| 24 | T24 err+wait      | inject_err=1 + insert_wait=1 | resp err | 1 (HRESP ERROR vẫn báo đúng) | PASS | High |

---

### Group 3 — Sequential Back-to-Back (TC 25–29)

| TC | Tag | Giao dịch | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-----|----------|---------|---------|--------|--------|
| 25 | T25 seq_w1 err | Write 0x1111_2222 @ 0x3000_0018 | resp err | 0 | PASS | High |
| 26 | T26 seq_w2 err | Write 0x3333_4444 @ 0x3000_001C | resp err | 0 | PASS | High |
| 27 | T27 seq_r1     | Read @ 0x3000_0018 | rdata | 0x1111_2222 | PASS | High |
| 28 | T28 seq_r2     | Read @ 0x3000_001C | rdata | 0x3333_4444 | PASS | High |
| 29 | T29 req_rd_en_idle | Sau khi idle (5 AHB cycles) | req_rd_en | 0 (không đọc FIFO khi rỗng) | PASS | High |

---

### Tổng kết Phase 4b

| Testbench | Số testcase | PASS | FAIL | Tỷ lệ |
|-----------|-------------|------|------|--------|
| tb_ahb_interface | 29 | 29 | 0 | 100% |

---


---

## Phase 4c — Integration: tb_axi_full (47 testcases)

**Testbench:** `SIM/integration/tb_axi_full.sv`
**DUT:** `axi_interface` → `axi_interconnect` → 3× `axi_sfr` (Standard Register Map)
**Cơ chế:** `pass_cnt` tăng theo `pass_if()`. `do_write`=1 TC (resp_err); `do_read`=2 TC (rdata+err); các IRQ check là `pass_if` riêng lẻ.
**Số testcase:** 47
**Kết quả tổng:** 47/47 PASS

---

### Group 1 — Address Decode: CTRL @ mỗi slave (TC 1–9)

Kiểm tra interconnect decode đúng addr[27:12] → S0/S1/S2; write+read-back CTRL (offset 0x00).

| TC | Slave | Địa chỉ | Data | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-------|---------|------|---------|---------|--------|--------|
| 1  | S0 | 0x2000_0000 | 0xAABB_1100 (write) | resp_err | 0 | PASS | Critical |
| 2  | S0 | 0x2000_0000 | read back | resp_rdata | 0xAABB_1100 | PASS | Critical |
| 3  | S0 | 0x2000_0000 | — | resp_err | 0 | PASS | Critical |
| 4  | S1 | 0x2000_1000 | 0xCCDD_2200 (write) | resp_err | 0 | PASS | Critical |
| 5  | S1 | 0x2000_1000 | read back | resp_rdata | 0xCCDD_2200 | PASS | Critical |
| 6  | S1 | 0x2000_1000 | — | resp_err | 0 | PASS | Critical |
| 7  | S2 | 0x2000_2000 | 0xEEFF_3300 (write) | resp_err | 0 | PASS | Critical |
| 8  | S2 | 0x2000_2000 | read back | resp_rdata | 0xEEFF_3300 | PASS | Critical |
| 9  | S2 | 0x2000_2000 | — | resp_err | 0 | PASS | Critical |

---

### Group 2 — IRQ: INTR_ENABLE + INTR_TEST + W1C (TC 10–24)

Sequence: enable bit0, force via INTR_TEST, kiểm tra `axi_irq`; sau đó W1C clear INTR_STATE, kiểm tra irq rơi. Lần lượt với S0, S1, S2.

| TC | Hành động | Địa chỉ | Data | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-----------|---------|------|---------|---------|--------|--------|
| 10 | S0 INTR_ENABLE[0]=1 | 0x2000_0008 | 0x1 | resp_err | 0 | PASS | Critical |
| 11 | S0 INTR_TEST[0]=1 → set INTR_STATE[0] | 0x2000_0010 | 0x1 | resp_err | 0 | PASS | Critical |
| 12 | axi_irq check (S0 active) | — | — | axi_irq | 1 | PASS | Critical |
| 13 | S1 INTR_ENABLE[0]=1 | 0x2000_1008 | 0x1 | resp_err | 0 | PASS | Critical |
| 14 | S1 INTR_TEST[0]=1 | 0x2000_1010 | 0x1 | resp_err | 0 | PASS | Critical |
| 15 | axi_irq check (S0+S1 active) | — | — | axi_irq | 1 | PASS | Critical |
| 16 | S0 INTR_STATE W1C clear | 0x2000_000C | 0x1 | resp_err | 0 | PASS | Critical |
| 17 | axi_irq check (S1 still active) | — | — | axi_irq | 1 (OR logic) | PASS | Critical |
| 18 | S1 INTR_STATE W1C clear | 0x2000_100C | 0x1 | resp_err | 0 | PASS | Critical |
| 19 | axi_irq check (all cleared) | — | — | axi_irq | 0 | PASS | Critical |
| 20 | S2 INTR_ENABLE[0]=1 | 0x2000_2008 | 0x1 | resp_err | 0 | PASS | Critical |
| 21 | S2 INTR_TEST[0]=1 | 0x2000_2010 | 0x1 | resp_err | 0 | PASS | Critical |
| 22 | axi_irq check (S2 active) | — | — | axi_irq | 1 | PASS | Critical |
| 23 | S2 INTR_STATE W1C clear | 0x2000_200C | 0x1 | resp_err | 0 | PASS | Critical |
| 24 | axi_irq check (all cleared) | — | — | axi_irq | 0 | PASS | Critical |

---

### Group 3 — Multi-register trong Slave 0: DATA0/1/2 (TC 25–33)

Kiểm tra 3 thanh ghi DATA (offset 0x14/0x18/0x1C) trong cùng một slave hoạt động độc lập.

| TC | Địa chỉ | Data | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|---------|------|---------|---------|--------|--------|
| 25 | 0x2000_0014 (DATA0 write) | 0x1111_AAAA | resp_err | 0 | PASS | High |
| 26 | 0x2000_0018 (DATA1 write) | 0x2222_BBBB | resp_err | 0 | PASS | High |
| 27 | 0x2000_001C (DATA2 write) | 0x3333_CCCC | resp_err | 0 | PASS | High |
| 28 | 0x2000_0014 (DATA0 read)  | — | resp_rdata | 0x1111_AAAA | PASS | High |
| 29 | 0x2000_0014 | — | resp_err | 0 | PASS | High |
| 30 | 0x2000_0018 (DATA1 read)  | — | resp_rdata | 0x2222_BBBB | PASS | High |
| 31 | 0x2000_0018 | — | resp_err | 0 | PASS | High |
| 32 | 0x2000_001C (DATA2 read)  | — | resp_rdata | 0x3333_CCCC | PASS | High |
| 33 | 0x2000_001C | — | resp_err | 0 | PASS | High |

---

### Group 4 — Cross-slave Isolation (TC 34–45)

Ghi DATA0 vào S0 và S2 với giá trị khác nhau; verify S1 không bị ảnh hưởng, S0 CTRL/S2 CTRL còn giá trị từ Group 1.

| TC | Địa chỉ | Hành động | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|---------|----------|---------|---------|--------|--------|
| 34 | 0x2000_0014 | S0 DATA0 write 0xF0F0_AAAA | resp_err | 0 | PASS | High |
| 35 | 0x2000_2014 | S2 DATA0 write 0x0F0F_BBBB | resp_err | 0 | PASS | High |
| 36 | 0x2000_0014 | S0 DATA0 read | resp_rdata | 0xF0F0_AAAA (không bị S2 ghi đè) | PASS | High |
| 37 | 0x2000_0014 | — | resp_err | 0 | PASS | High |
| 38 | 0x2000_2014 | S2 DATA0 read | resp_rdata | 0x0F0F_BBBB | PASS | High |
| 39 | 0x2000_2014 | — | resp_err | 0 | PASS | High |
| 40 | 0x2000_1014 | S1 DATA0 read (never written) | resp_rdata | 0x0000_0000 (reset) | PASS | High |
| 41 | 0x2000_1014 | — | resp_err | 0 | PASS | High |
| 42 | 0x2000_0000 | S0 CTRL read | resp_rdata | 0xAABB_1100 (từ Group 1, không đổi) | PASS | High |
| 43 | 0x2000_0000 | — | resp_err | 0 | PASS | High |
| 44 | 0x2000_2000 | S2 CTRL read | resp_rdata | 0xEEFF_3300 (từ Group 1) | PASS | High |
| 45 | 0x2000_2000 | — | resp_err | 0 | PASS | High |

---

### Bonus — PERIPH_ID Read (TC 46–47)

| TC | Địa chỉ | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|---------|---------|---------|--------|--------|
| 46 | 0x2000_00FC | resp_rdata | 0x5346_5230 (default PERIPH_ID_VAL "SFR0") | PASS | Medium |
| 47 | 0x2000_00FC | resp_err | 0 | PASS | Medium |

---

### Tổng kết Phase 4c

| Testbench | Số testcase | PASS | FAIL | Tỷ lệ |
|-----------|-------------|------|------|--------|
| tb_axi_full | 47 | 47 | 0 | 100% |

---

---

---

## Phase 4d — Integration: tb_ahb_full (38 testcases)

**Testbench:** `SIM/integration/tb_ahb_full.sv`
**DUT:** 2× `async_fifo_depth2` (CDC) → `ahb_interface` → `ahb_interconnect` → 3× `ahb_sfr`
**Cơ chế:** `pass_cnt` tăng mỗi `pass_if()`. `do_txn` không tự tăng — `tnum` increment và `pass_if` gọi thủ công sau mỗi transaction. CDC thực: clk_1g=1GHz, clk_ahb=500MHz lệch 0.7ns.
**Số testcase:** 38
**Kết quả tổng:** 38/38 PASS

---

### Group 1 — Address Decode: CTRL @ mỗi slave (TC 1–9)

Kiểm tra `ahb_interconnect` decode đúng `addr[27:12]` → S0/S1/S2 qua CDC path.

| TC | Slave | Địa chỉ | Hành động | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-------|---------|----------|---------|---------|--------|--------|
| 1  | S0 | 0x3000_0000 | Write 0xAABB_CCDD | err | 0 | PASS | Critical |
| 2  | S0 | 0x3000_0000 | Read back | err | 0 | PASS | Critical |
| 3  | S0 | 0x3000_0000 | — | rdata | 0xAABB_CCDD | PASS | Critical |
| 4  | S1 | 0x3000_1000 | Write 0x1122_3344 | err | 0 | PASS | Critical |
| 5  | S1 | 0x3000_1000 | Read back | err | 0 | PASS | Critical |
| 6  | S1 | 0x3000_1000 | — | rdata | 0x1122_3344 | PASS | Critical |
| 7  | S2 | 0x3000_2000 | Write 0x5566_7788 | err | 0 | PASS | Critical |
| 8  | S2 | 0x3000_2000 | Read back | err | 0 | PASS | Critical |
| 9  | S2 | 0x3000_2000 | — | rdata | 0x5566_7788 | PASS | Critical |

---

### Group 2 — IRQ: INTR_ENABLE + INTR_TEST + W1C (TC 10–24)

Tương tự Phase 4c nhưng qua AHB CDC path. Sau mỗi write cần `repeat(2) @posedge clk_ahb` để tín hiệu irq propagate qua AHB domain trước khi sample.

| TC | Hành động | Địa chỉ | Data | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|-----------|---------|------|---------|---------|--------|--------|
| 10 | S0 INTR_ENABLE[0]=1 | 0x3000_0008 | 0x1 | err | 0 | PASS | Critical |
| 11 | S0 INTR_TEST[0]=1 → set INTR_STATE[0] | 0x3000_0010 | 0x1 | err | 0 | PASS | Critical |
| 12 | ahb_irq check (S0 active) | — | — | ahb_irq | 1 | PASS | Critical |
| 13 | S1 INTR_ENABLE[0]=1 | 0x3000_1008 | 0x1 | err | 0 | PASS | Critical |
| 14 | S1 INTR_TEST[0]=1 | 0x3000_1010 | 0x1 | err | 0 | PASS | Critical |
| 15 | ahb_irq check (S0+S1) | — | — | ahb_irq | 1 (OR) | PASS | Critical |
| 16 | S0 INTR_STATE W1C | 0x3000_000C | 0x1 | err | 0 | PASS | Critical |
| 17 | ahb_irq check (S1 still active) | — | — | ahb_irq | 1 | PASS | Critical |
| 18 | S1 INTR_STATE W1C | 0x3000_100C | 0x1 | err | 0 | PASS | Critical |
| 19 | ahb_irq check (all cleared) | — | — | ahb_irq | 0 | PASS | Critical |
| 20 | S2 INTR_ENABLE[0]=1 | 0x3000_2008 | 0x1 | err | 0 | PASS | Critical |
| 21 | S2 INTR_TEST[0]=1 | 0x3000_2010 | 0x1 | err | 0 | PASS | Critical |
| 22 | ahb_irq check (S2 active) | — | — | ahb_irq | 1 | PASS | Critical |
| 23 | S2 INTR_STATE W1C | 0x3000_200C | 0x1 | err | 0 | PASS | Critical |
| 24 | ahb_irq check (all cleared) | — | — | ahb_irq | 0 | PASS | Critical |

---

### Group 3 — Multi-register trong Slave 1: DATA0/DATA1 (TC 25–30)

| TC | Địa chỉ | Hành động | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|---------|----------|---------|---------|--------|--------|
| 25 | 0x3000_1014 (DATA0) | Write 0xDEAD_BEEF | err | 0 | PASS | High |
| 26 | 0x3000_1018 (DATA1) | Write 0xCAFE_BABE | err | 0 | PASS | High |
| 27 | 0x3000_1014 (DATA0) | Read back | err | 0 | PASS | High |
| 28 | 0x3000_1014 | — | rdata | 0xDEAD_BEEF | PASS | High |
| 29 | 0x3000_1018 (DATA1) | Read back | err | 0 | PASS | High |
| 30 | 0x3000_1018 | — | rdata | 0xCAFE_BABE | PASS | High |

---

### Group 4 — Cross-slave Isolation (TC 31–38)

| TC | Địa chỉ | Hành động | Kiểm tra | Kỳ vọng | Status | Mức độ |
|----|---------|----------|---------|---------|--------|--------|
| 31 | 0x3000_0014 | S0 DATA0 write 0xF0F0_AAAA | err | 0 | PASS | High |
| 32 | 0x3000_2014 | S2 DATA0 write 0x0F0F_BBBB | err | 0 | PASS | High |
| 33 | 0x3000_0014 | S0 DATA0 read | err | 0 | PASS | High |
| 34 | 0x3000_0014 | — | rdata | 0xF0F0_AAAA (không bị S2 ghi đè) | PASS | High |
| 35 | 0x3000_2014 | S2 DATA0 read | err | 0 | PASS | High |
| 36 | 0x3000_2014 | — | rdata | 0x0F0F_BBBB | PASS | High |
| 37 | 0x3000_0000 | S0 CTRL read (còn từ Group 1) | err | 0 | PASS | High |
| 38 | 0x3000_0000 | — | rdata | 0xAABB_CCDD (không đổi) | PASS | High |

---

### Tổng kết Phase 4d

| Testbench | Số testcase | PASS | FAIL | Tỷ lệ |
|-----------|-------------|------|------|--------|
| tb_ahb_full | 38 | 38 | 0 | 100% |

---

---

---

## Phase 5 — Integration: tb_pipeline_cpu (4 programs)

**Testbench:** `SIM/integration/tb_pipeline_cpu.sv` (cùng harness với Phase 3)
**Mục tiêu:** Kiểm tra full path CPU → AXI/AHB bus → SFR peripheral; và IRQ path ngược từ peripheral → PLIC → Zicsr → trap handler.
**Số testcase:** 4 (mỗi program = 1 testcase, verdict x31==1 tại EBREAK)
**Kết quả tổng:** 4/4 PASS

---

### Phase 5 — Testcase 1: prog_axi_sfr

**File:** `SIM/programs/prog_axi_sfr.s`
**Mục tiêu:** CPU ghi/đọc AXI SFR DATA registers qua full pipeline (SW→AXI stall→LW); kiểm tra cross-slave isolation.

| # | Hành động | Slave | Offset | Data | Self-check | Status | Mức độ |
|---|-----------|-------|--------|------|-----------|--------|--------|
| 1 | SW+LW DATA0 | S0 | 0x14 | 0xDEAD_BEEF | `bne t2,t1,fail` | PASS | Critical |
| 2 | SW+LW DATA1 | S0 | 0x18 | 0x1234_5678 | `bne t2,t1,fail` | PASS | Critical |
| 3 | SW+LW DATA0 | S1 | 0x14 | 0xCAFE_BABE | `bne t5,t4,fail` | PASS | Critical |
| 4 | SW+LW DATA0 | S2 | 0x14 | 0x5A5A_A5A5 | `bne t5,t4,fail` | PASS | Critical |
| 5 | Cross-slave: S0 DATA0 after S1/S2 writes | S0 | 0x14 | vẫn 0xDEAD_BEEF | `bne t2,t1,fail` | PASS | High |
| 6 | Cross-slave: S0 DATA1 unchanged | S0 | 0x18 | vẫn 0x1234_5678 | `bne t2,t1,fail` | PASS | High |

**Ghi chú:** Mỗi SW/LW qua AXI gây `bus_stall_req=1`, pipeline freeze đến khi `resp_valid`. Load-use hazard xảy ra sau LW → 1 bubble thêm.

---

### Phase 5 — Testcase 2: prog_ahb_sfr

**File:** `SIM/programs/prog_ahb_sfr.s`
**Mục tiêu:** Tương tự prog_axi_sfr nhưng qua AHB CDC path (1GHz→500MHz→1GHz), kiểm tra latency round-trip và data integrity.

| # | Hành động | Slave | Offset | Data | Self-check | Status | Mức độ |
|---|-----------|-------|--------|------|-----------|--------|--------|
| 1 | SW+LW DATA0 | S0 | 0x14 | 0xABCD_1234 | `bne t2,t1,fail` | PASS | Critical |
| 2 | SW+LW DATA1 | S0 | 0x18 | 0x5566_7788 | `bne t2,t1,fail` | PASS | Critical |
| 3 | SW+LW DATA0 | S1 | 0x14 | 0x9988_AABB | `bne t5,t4,fail` | PASS | Critical |
| 4 | SW+LW DATA0 | S2 | 0x14 | 0x1122_3344 | `bne t5,t4,fail` | PASS | Critical |
| 5 | Cross-slave: S0 DATA0 unchanged | S0 | 0x14 | vẫn 0xABCD_1234 | `bne t2,t1,fail` | PASS | High |
| 6 | Cross-slave: S0 DATA1 unchanged | S0 | 0x18 | vẫn 0x5566_7788 | `bne t2,t1,fail` | PASS | High |

**Ghi chú:** CDC round-trip ~2× AHB cycle ≈ 4 CPU cycles. `bus_stall_req` giữ pipeline đến khi resp FIFO không rỗng.

---

### Phase 5 — Testcase 3: prog_axi_irq

**File:** `SIM/programs/prog_axi_irq.s`
**Mục tiêu:** Kiểm tra AXI IRQ end-to-end: INTR_TEST force → `axi_irq` → PLIC → `meip_in` → Zicsr MEI trap → handler.

**Chuỗi sự kiện:**
1. Khởi tạo PLIC: source 1 = axi_S0, PRIORITY=1, ENABLE bit[1]=1, THRESHOLD=0
2. Enable MEIE (mie[11]) + MIE (mstatus[3])
3. SW INTR_ENABLE[0]=1 → AXI stall
4. SW INTR_TEST[0]=1 → AXI stall → `axi_irq` rises → PLIC pending → `meip_in`=1
5. 5×NOP bridge PLIC latency → MEI trap fires
6. Handler: verify mcause, clear IRQ, MRET → `pass`

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | Interrupt fires (không reach `j fail`) | Handler được gọi | PASS | Critical |
| 2 | mcause = 0x8000_000B (MEI, cause=11) | x20 = 0x8000_000B | PASS | Critical |
| 3 | mstatus.MIE = 0 trong trap | x23 = 0 | PASS | Critical |
| 4 | W1C clear + disable MEIE + MRET → `pass` | x31 = 1 | PASS | Critical |

---

### Phase 5 — Testcase 4: prog_ahb_irq

**File:** `SIM/programs/prog_ahb_irq.s`
**Mục tiêu:** Kiểm tra AHB IRQ end-to-end qua CDC path: INTR_TEST → `ahb_irq` (500MHz) → 2-FF sync (1GHz) → PLIC source 4 → MEI trap.

**Chuỗi sự kiện:**
1. Khởi tạo PLIC: source 4 = ahb_S0, PRIORITY=1, ENABLE bit[4]=1, THRESHOLD=0
2. Enable MEIE + MIE
3. SW INTR_ENABLE[0]=1 → AHB CDC stall
4. SW INTR_TEST[0]=1 → AHB CDC stall → `ahb_irq_raw`=1 (500MHz) → 2-FF sync → PLIC → `meip_in`=1
5. 7×NOP bridge (2-FF sync 2cy + PLIC 1cy = 3cy tổng) → MEI trap fires
6. Handler: verify mcause, W1C clear INTR_STATE (AHB write), disable MEIE, MRET

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | Interrupt fires qua 2-FF sync (không reach `j fail`) | Handler được gọi | PASS | Critical |
| 2 | mcause = 0x8000_000B | x20 = 0x8000_000B | PASS | Critical |
| 3 | mstatus.MIE = 0 trong trap | x23 = 0 | PASS | Critical |
| 4 | W1C clear (AHB) + disable MEIE + MRET → `pass` | x31 = 1 | PASS | Critical |

**Ghi chú:** AHB IRQ phải qua `irq_sync2ff` (2-FF synchronizer trong soc_top) trước khi vào PLIC — thêm ~2 CPU cycles latency so với AXI IRQ.

---

### Tổng kết Phase 5

| Testcase | Program | Số self-check nội bộ | PASS | FAIL | Mức độ |
|---------|---------|----------------------|------|------|--------|
| 1 | prog_axi_sfr | 6 | PASS | 0 | Critical |
| 2 | prog_ahb_sfr | 6 | PASS | 0 | Critical |
| 3 | prog_axi_irq | 4 | PASS | 0 | Critical |
| 4 | prog_ahb_irq | 4 | PASS | 0 | Critical |
| **Tổng Phase 5** | — | **20 self-checks** | **4/4** | **0** | **Critical** |

---

---

---

## Bus Error Integration Tests — tb_soc_bus_err + tb_soc_ahb_err (4 TC)

**Testbench AXI:** `SIM/integration/tb_soc_bus_err.sv`
**Testbench AHB:** `SIM/integration/tb_soc_ahb_err.sv`
**Số testcase tổng:** 4 (2 AXI + 2 AHB)
**Kết quả:** 4/4 PASS

**Cơ chế:** Single-program runner (`+HEX=`). Verdict: x31==1 tại EBREAK. S0 trong mỗi testbench được thay thế bằng error slave; S1/S2 là SFR bình thường.

---

### tb_soc_bus_err — AXI Error Slave (2 TC)

**Error slave S0:** `AWREADY=WREADY=ARREADY=1` (accept ngay); BVALID/RVALID sau 1 cycle với `BRESP/RRESP=2'b10` (SLVERR).

| TC | Program | Fault path | Self-checks | Kỳ vọng | Status |
|----|---------|-----------|-------------|---------|--------|
| 1 | `prog_bus_err` | SW→AXI S0→BRESP=SLVERR→store_access_fault→mcause=7 | 3 (`j fail` miss + mcause==7 + mepc≠0) | x31=1 | PASS |
| 2 | `prog_read_err` | LW←AXI S0→RRESP=SLVERR→load_access_fault→mcause=5 | 3 (`j fail` miss + mcause==5 + mepc≠0) | x31=1 | PASS |

**Path chi tiết (TC1):** `SW@MEM1` → bus_stall (AXI FSM) → BRESP=SLVERR → `axi_interface.bus_err=1` → `mem1_stage.store_fault=1` → propagate MEM2/WB → `zicsr.take_exception` → `zicsr_flush` → handler tại `mtvec`.

**Path chi tiết (TC2):** `LW@MEM1` → bus_stall → RRESP=SLVERR → `axi_resp_err=1` → `mem1_stage.load_fault=1` → WB → `zicsr` → handler.

---

### tb_soc_ahb_err — AHB Error Slave (2 TC)

**Error slave S0 (AHB-Lite 2-cycle error protocol):**
- State `ERR_C1`: `HREADYOUT=0`, `HRESP=1` — extend bus, signal error
- State `ERR_C2`: `HREADYOUT=1`, `HRESP=1` — release bus, confirm error
- `ahb_interface` đọc {HRESP, HRDATA} vào resp_fifo khi HREADY=1 (ERR_C2); `resp_fifo[32]=1` → `bus_err=1`

| TC | Program | Fault path | Self-checks | Kỳ vọng | Status |
|----|---------|-----------|-------------|---------|--------|
| 1 | `prog_ahb_store_err` | SW→AHB S0→HRESP=ERROR (2-cycle)→store_access_fault→mcause=7 | 3 (`j fail` miss + mcause==7 + mepc≠0) | x31=1 | PASS |
| 2 | `prog_ahb_load_err` | LW←AHB S0→HRESP=ERROR (2-cycle)→load_access_fault→mcause=5 | 3 (`j fail` miss + mcause==5 + mepc≠0) | x31=1 | PASS |

**Điểm khác AXI vs AHB:**
- AXI error: 1-cycle latency (BVALID/RVALID sau AWREADY/ARREADY)
- AHB error: 2-cycle latency (ERR_C1: stall bus; ERR_C2: confirm + push vào resp_fifo)
- Cả 2 đều là **precise exception**: bus transaction phải hoàn thành trước khi zicsr flush pipeline

---



---

## ═══ PHẦN 3: SYSTEM TESTS ═══

Kiểm tra full soc_top với real peripherals; programs chạy trên CPU thật.

---

## Phase 6a — System Batch: tb_soc_top (20 programs)

**Testbench:** `SIM/system/tb_soc_top.sv`
**Cơ chế:** Batch runner — chạy tuần tự 20 programs trong 1 lần mô phỏng. Giữa mỗi program: DMEM[0..16383] zeroed, IMEM reload, full reset 10 cycles. Verdict per-program: x31==1 tại EBREAK, hoặc TIMEOUT 200000 cycles = FAIL.
**Số testcase:** 20
**Kết quả tổng:** 20/20 PASS

**Khác với tb_pipeline_cpu (Phase 3/5):** tb_soc_top dọn sạch DMEM giữa các run — tránh state contamination, quan trọng cho các program dùng DMEM (prog_plic_priority, prog_csr_hazard).

---

### Programs 1–13 (đã documented tại Phase 3 và Phase 5)

| # | Program | Ref | Mục tiêu | Status |
|---|---------|-----|---------|--------|
| 1 | prog_arithmetic | Phase 3 TC1 | R-type/I-type ALU ops | PASS |
| 2 | prog_forwarding | Phase 3 TC2 | Pipeline forwarding gap 0/1/2 | PASS |
| 3 | prog_load_store | Phase 3 TC3 | LW/LH/LB/LHU/LBU/SW/SH/SB | PASS |
| 4 | prog_branch_jump | Phase 3 TC4 | 6 branch types + JAL + JALR | PASS |
| 5 | prog_csr | Phase 3 TC5 | CSRRW/RS/RC/RWI/RSI/RCI | PASS |
| 6 | prog_ecall | Phase 3 TC6 | ECALL → trap → MRET | PASS |
| 7 | prog_interrupt_msi | Phase 3 TC7 | MSI (mip.MSIP) → handler → MRET | PASS |
| 8 | prog_interrupt_mei | Phase 3 TC8 | MEI via PLIC + AXI SFR INTR_TEST | PASS |
| 9 | prog_load_fault | Phase 3 TC9 | Load access fault (0x4000_0000) | PASS |
| 10 | prog_axi_sfr | Phase 5 TC1 | AXI SFR DATA write/read + isolation | PASS |
| 11 | prog_ahb_sfr | Phase 5 TC2 | AHB SFR DATA write/read (CDC) | PASS |
| 12 | prog_axi_irq | Phase 5 TC3 | AXI IRQ → PLIC → MEI trap | PASS |
| 13 | prog_ahb_irq | Phase 5 TC4 | AHB IRQ → 2-FF sync → PLIC → MEI trap | PASS |

---

### Phase 6a — Testcase 14: prog_rv32i_shifts

**File:** `SIM/programs/prog_rv32i_shifts.s`
**Mục tiêu:** Kiểm tra đầy đủ 6 shift instruction với các shamt đặc biệt (0, 1, 31, 33≡1).

| # | Instruction | Input | Kỳ vọng | Status | Mức độ |
|---|------------|-------|---------|--------|--------|
| 1 | SLLI t1,t0,0 | 1 | 1 (shift 0) | PASS | Critical |
| 2 | SLLI t1,t0,4 | 1 | 16 | PASS | Critical |
| 3 | SLLI t1,t0,31 | 1 | 0x8000_0000 (MSB set) | PASS | Critical |
| 4 | SRLI t1,t0,1 | 0x8000_0000 | 0x4000_0000 (logical, zero fill) | PASS | Critical |
| 5 | SRLI t1,t0,31 | 0x8000_0000 | 1 | PASS | Critical |
| 6 | SRLI t1,t0,0 | 0x8000_0000 | 0x8000_0000 (unchanged) | PASS | Critical |
| 7 | SRAI t1,t0,1 | 0x8000_0000 (neg) | 0xC000_0000 (sign replicated) | PASS | Critical |
| 8 | SRAI t1,t0,31 | 0x8000_0000 (neg) | 0xFFFF_FFFF | PASS | Critical |
| 9 | SRAI t1,t0,2 | 8 (positive) | 2 (same as SRLI for positive) | PASS | High |
| 10 | SLL t1,t0,t3 | 1, shamt=4 | 16 | PASS | Critical |
| 11 | SLL t1,t0,t3 | 1, shamt=0 | 1 (unchanged) | PASS | High |
| 12 | SLL t1,t0,t3 | 1, shamt=33 (33 mod 32=1) | 2 | PASS | High |
| 13 | SRL t1,t0,t3 | 0x8000_0000, shamt=4 | 0x0800_0000 | PASS | Critical |
| 14 | SRL t1,t0,t3 | 0x8000_0000, shamt=31 | 1 | PASS | Critical |
| 15 | SRA t1,t0,t3 | 0x8000_0000, shamt=4 | 0xF800_0000 | PASS | Critical |
| 16 | SRA t1,t0,t3 | 0x8000_0000, shamt=31 | 0xFFFF_FFFF | PASS | Critical |
| 17 | SRA t1,t0,t3 | 8 (positive), shamt=2 | 2 | PASS | High |

---

### Phase 6a — Testcase 15: prog_rv32i_compare

**File:** `SIM/programs/prog_rv32i_compare.s`
**Mục tiêu:** Kiểm tra SLT/SLTU/SLTI/SLTIU với signed/unsigned semantics và AUIPC.

| # | Instruction | Input | Kỳ vọng | Status | Mức độ |
|---|------------|-------|---------|--------|--------|
| 1 | SLT | -1 < 0 (signed) | 1 | PASS | Critical |
| 2 | SLT | 0 < -1 (signed) | 0 | PASS | Critical |
| 3 | SLT | 5 < 5 | 0 (equal) | PASS | High |
| 4 | SLT | 3 < 7 | 1 | PASS | Critical |
| 5 | SLTU | 0xFFFFFFFF < 0 (unsigned) | 0 | PASS | Critical |
| 6 | SLTU | 0 < 0xFFFFFFFF (unsigned) | 1 | PASS | Critical |
| 7 | SLTU | 0 < 0 | 0 | PASS | High |
| 8 | SLTU | 3 < 7 (unsigned) | 1 | PASS | Critical |
| 9 | SLTI | 5 < 10 | 1 | PASS | Critical |
| 10 | SLTI | 5 < 5 | 0 | PASS | High |
| 11 | SLTI | 5 < -1 (signed imm) | 0 | PASS | Critical |
| 12 | SLTI | -1 < 0 | 1 | PASS | Critical |
| 13 | SLTI | -1 < -2 | 0 | PASS | High |
| 14 | SLTIU | 5 < 10 (unsigned) | 1 | PASS | Critical |
| 15 | SLTIU | 5 < 0 (unsigned) | 0 | PASS | Critical |
| 16 | SLTIU | 5 < 5 | 0 | PASS | High |
| 17 | SLTIU | 100 < -1 (= 0xFFFFFFFF unsigned) | 1 | PASS | Critical |
| 18 | AUIPC sequential | 2 consecutive auipc | t1 = t0 + 4 | PASS | Critical |
| 19 | AUIPC với imm=1 | auipc t0,1 vs auipc t1,0 | t0 = t1 + 0x1000 - 4 | PASS | Critical |

---

### Phase 6a — Testcase 16: prog_dmem_endurance

**File:** `SIM/programs/prog_dmem_endurance.s`
**Mục tiêu:** Ghi 64 word vào DMEM với pattern byte-replicated (i→0x0i0i0i0i), đọc lại và verify từng word. Kiểm tra DMEM integrity và pipeline store→load forwarding trong loop.

| Giai đoạn | Hành động | Số self-check | Status | Mức độ |
|-----------|----------|---------------|--------|--------|
| Write phase | Ghi pattern(i)=byte_rep(i) vào addr[DMEM+i*4], i=0..63 | 0 (ghi, không verify) | — | Critical |
| Read phase | Đọc lại và so sánh từng word với expected pattern | 64 lần `bne t5,t6,fail` | PASS | Critical |

**Pattern:** `pattern(i) = i | (i<<8) | (i<<16) | (i<<24)` — i chạy từ 0 đến 63 (6-bit). Ví dụ i=1 → 0x01010101, i=63 → 0x3F3F3F3F.

---

### Phase 6a — Testcase 17: prog_plic_basic

**File:** `SIM/programs/prog_plic_basic.s`
**Mục tiêu:** Kiểm tra PLIC claim/complete flow cơ bản. Source 2 (priority 5) và source 1 (priority 1) enabled; trigger source 2 → PLIC grant source 2; handler claim, complete, W1C, MRET.

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | MEI trap fires (không reach `j fail`) | Handler được gọi | PASS | Critical |
| 2 | mcause = 0x8000_000B | Đúng MEI cause | PASS | Critical |
| 3 | CLAIM register trả về 2 (higher priority source thắng) | x12 = 2 | PASS | Critical |

---

### Phase 6a — Testcase 18: prog_plic_priority

**File:** `SIM/programs/prog_plic_priority.s`
**Mục tiêu:** Force 2 IRQ đồng thời (src1 priority=1, src2 priority=2), kiểm tra PLIC grant theo thứ tự priority: claim1=2 → claim2=1 → claim3=0.

**Chuỗi:** Trigger cả 2 → interrupt → handler (3 lần claim tuần tự) → MRET về `after_handler` → verify DMEM.

| # | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|---------|---------|--------|--------|
| 1 | mcause = 0x8000_000B | MEI, đúng | PASS | Critical |
| 2 | Claim 1 = 2 (highest priority wins) | x21 = 2 | PASS | Critical |
| 3 | Claim 2 = 1 (source 1 still pending after complete 2) | x22 = 1 | PASS | Critical |
| 4 | Claim 3 = 0 (no more pending) | x23 = 0 | PASS | Critical |
| 5 | DMEM[0] = 2 (verify first claim stored) | x13 = 2 | PASS | Critical |
| 6 | DMEM[4] = 1 | x14 = 1 | PASS | Critical |
| 7 | DMEM[8] = 0 | x15 = 0 | PASS | Critical |

---

### Phase 6a — Testcase 19: prog_plic_threshold

**File:** `SIM/programs/prog_plic_threshold.s`
**Mục tiêu:** Kiểm tra PLIC threshold filtering theo 3 phase: threshold=2 (block tất cả) → threshold=1 (src2 fires) → threshold=0 (src1 fires). Handler chạy đúng 2 lần tổng cộng.

| # | Phase | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|-------|---------|---------|--------|--------|
| 1 | Phase 0: threshold=2 | `bne x29,x0,fail` sau 10 NOP | x29=0 (no interrupt) | PASS | Critical |
| 2 | Phase 1: threshold=1 | Handler: mcause = 0x8000_000B | Đúng | PASS | Critical |
| 3 | Phase 1: threshold=1 | Handler: claim = 2 (src2 priority=2 > threshold=1) | x23=2 | PASS | Critical |
| 4 | Phase 1: x29==1 | `bne x29,x8,fail` | x29=1 sau 1 handler run | PASS | Critical |
| 5 | Phase 2: threshold=0 | Handler: mcause = 0x8000_000B | Đúng | PASS | Critical |
| 6 | Phase 2: threshold=0 | Handler: claim = 1 (src1 priority=1 > threshold=0) | x23=1 | PASS | Critical |
| 7 | Phase 2: x29==2 | `bne x29,x8,fail` | x29=2 sau 2 handler runs | PASS | Critical |

---

### Phase 6a — Testcase 20: prog_csr_hazard

**File:** `SIM/programs/prog_csr_hazard.s`
**Mục tiêu:** Kiểm tra `hazard_unit` stall CSR-use ở gap 0/1/2 và không stall ở gap 3/4 (WB forward + RF WBR bypass). Mỗi group: csrr vào register, dùng register sau N NOP, verify giá trị đúng.

| # | Group | Gap (NOP) | Stall cycles | Kiểm tra | Kỳ vọng | Status | Mức độ |
|---|-------|-----------|-------------|---------|---------|--------|--------|
| 1 | G1 | 0 | 3 stalls | `add x4,x3,x0` dùng x3 ngay | x4=0x1234_5670 | PASS | Critical |
| 2 | G2 | 1 | 2 stalls | `add x7,x6,x0` sau 1 NOP | x7=0x1234_5670 | PASS | Critical |
| 3 | G3 | 2 | 1 stall | `add x9,x8,x0` sau 2 NOP | x9=0x1234_5670 | PASS | Critical |
| 4 | G4 | 3 | 0 (WB forward) | `add x11,x10,x0` sau 3 NOP | x11=0x1234_5670 | PASS | Critical |
| 5 | G5 | 4 | 0 (RF WBR bypass) | `add x13,x12,x0` sau 4 NOP | x13=0x1234_5670 | PASS | Critical |
| 6 | G6 | rd=x0 | 0 (no stall) | `csrw mepc, x5` → `add x14,x5,x0` | x14=0x1234_5670 | PASS | High |
| 7 | G7: CSRRW old value | 0 | 3 stalls | `add x17,x15,x0` gap-0 sau CSRRW | x17=0x1234_5670 (old value) | PASS | Critical |
| 8 | G7: mepc updated | — | — | `csrr x18,mepc` | x18=0xABCDE_000 | PASS | Critical |
| 9 | G8: CSRRS | 0 | stall | mie sau CSRRS set MSIE | x22=0x8 | PASS | High |

---

### Tổng kết Phase 6a

| # | Program | Số self-check nội bộ | PASS | FAIL | Mức độ |
|---|---------|----------------------|------|------|--------|
| 1–13 | (đã documented Phase 3+5) | ~77 tổng | PASS | 0 | Critical |
| 14 | prog_rv32i_shifts | 17 | PASS | 0 | Critical |
| 15 | prog_rv32i_compare | 19 | PASS | 0 | Critical |
| 16 | prog_dmem_endurance | 64 (loop) | PASS | 0 | Critical |
| 17 | prog_plic_basic | 3 | PASS | 0 | Critical |
| 18 | prog_plic_priority | 7 | PASS | 0 | Critical |
| 19 | prog_plic_threshold | 7 | PASS | 0 | Critical |
| 20 | prog_csr_hazard | 9 | PASS | 0 | Critical |
| **Tổng Phase 6a** | — | **~203 self-checks** | **20/20** | **0** | **Critical** |

---

---

## Phase 6b — Compliance Framework: tb_compliance (3 programs)

**Testbench:** `SIM/system/tb_compliance.sv`
**Cơ chế:** Single-program compliance runner, nhận `+HEX=<path>`. Output machine-parseable: in ra `TEST_PASS` hoặc `TEST_FAIL` (exit code 0/1) — thiết kế để script (`run_one_test.sh`) parse. Verdict: x31==1 tại EBREAK = PASS; x31≠1 hoặc timeout 200000 cycles = FAIL.
**Số testcase:** 3
**Kết quả tổng:** 3/3 TEST_PASS

**Khác với tb_soc_top:** `tb_compliance` chạy 1 program/lần (không batch, không DMEM zeroed giữa các run). Output `TEST_PASS`/`TEST_FAIL` (uppercase, parseable) thay vì `PASS`/`FAIL` thông thường.

**Khác với tb_pipeline_cpu:** Cùng cơ chế single-program, nhưng `tb_compliance` có đầy đủ SoC peripherals (3 AXI SFR + 3 AHB SFR) — đảm bảo DUT là full SoC giống sản phẩm cuối, không chỉ CPU core.

---

### Danh sách programs Phase 6b

| TC | Program | File tham chiếu | Mục tiêu | Self-checks | Status |
|----|---------|----------------|---------|-------------|--------|
| 1 | prog_rv32i_shifts | Phase 6a TC14 | SLLI/SRLI/SRAI/SLL/SRL/SRA — shift semantics và shamt modulo 32 | 17 | TEST_PASS |
| 2 | prog_rv32i_compare | Phase 6a TC15 | SLT/SLTU/SLTI/SLTIU signed vs unsigned; AUIPC PC-relative | 19 | TEST_PASS |
| 3 | prog_dmem_endurance | Phase 6a TC16 | DMEM 64-word write/read-back với byte-replicated patterns | 64 (loop) | TEST_PASS |

**Lý do chọn 3 programs này:** Đây là các instruction quan trọng chưa có trong compliance test formal (riscv-arch-test) tại thời điểm viết, hoặc cần kiểm tra DMEM integrity riêng. Sau này được bổ sung vào `tb_soc_top` (Phase 6a programs 14–16) để chạy trong batch.

> Chi tiết self-check của từng program xem Phase 6a (TC 14, 15, 16) — cùng program, cùng binary.

---

---


---

## 3.3 PLIC System Tests

### Phase 7 System: prog_plic_basic / priority / threshold (3 TC)

| TC | Program | Ref | Mục tiêu | Status |
|----|---------|-----|---------|--------|
| 1 | prog_plic_basic | Phase 6a TC17 | PLIC claim/complete flow cơ bản; src2 priority thắng | PASS |
| 2 | prog_plic_priority | Phase 6a TC18 | 2 IRQ đồng thời; 3 lần claim theo thứ tự priority | PASS |
| 3 | prog_plic_threshold | Phase 6a TC19 | Threshold filter 3 phase: block → src2 → src1 | PASS |

> Chi tiết self-check từng program xem Phase 6a TC17–TC19.

---

---

---

## 3.4 CSR Hazard System Test

### Phase 8 System: prog_csr_hazard (1 TC)

| TC | Program | Ref | Mục tiêu | Status |
|----|---------|-----|---------|--------|
| 1 | prog_csr_hazard | Phase 6a TC20 | CSR-use stall gaps 0–4: 3/2/1/0/0 stalls; CSRRW old-value; CSRRS | PASS |

> Chi tiết 9 self-checks xem Phase 6a TC20.

---


---

## 3.5 Peripheral System Tests — tb_periph

### System: tb_periph (3 programs)

**Testbench:** `SIM/system/tb_periph.sv`
**Cơ chế:** Single-program runner (`+HEX=`); verdict x31==1 tại EBREAK = PASS. Sử dụng full `soc_top` với real peripherals bên ngoài.
**Testbench wire:** uart_tx → uart_rx (loopback), gpio_out → gpio_in (loopback via soc_top ports).

| # | Program | Makefile target | Mô tả luồng |
|---|---------|----------------|-------------|
| 1 | `prog_timer` | `periph_timer` | Timer AXI (PLIC src 2): PRESCALER=0, COMPARE=20; IRQ handler xác nhận mcause=0x8000_000B + PLIC claim=2 + W1C INTR_STATE → pass |
| 2 | `prog_gpio_ahb` | `periph_gpio` | GPIO AHB (PLIC src 4): Write DATA0=0x55, OE=1; verify STATUS=0x55 (loopback); force IRQ via INTR_TEST; handler claim=4 → pass |
| 3 | `prog_uart` | `periph_uart` | UART AXI (PLIC src 3): TX 0x55 (loopback → RX); handler xử lý tx_done trước (MRET→spin), rồi rx_complete: verify DATA2=0x55 → pass |

**Self-check pattern (mỗi program):**
- Kiểm tra `mcause == 0x8000_000B` trong handler (Machine External Interrupt)
- Kiểm tra PLIC CLAIM == đúng source ID
- Kiểm tra data nếu có (gpio loopback 0x55, uart rx 0x55)
- Redirect mepc → pass; `addi x31, x0, 1; ebreak`

**Kết quả:** 3/3 PASS

---

## 3.6 Branch Predictor System Test

### System: prog_branch_pred (1 TC)

**Testbench:** `tb_pipeline_cpu` — single-program runner, verdict x31==1.
**Mục tiêu:** Kiểm tra branch predictor end-to-end trong full pipeline (IF1 lookup → EX update → flush khi mispredict).

**Program chứa 4 test patterns nội bộ:**

| Pattern | Mô tả | Self-check | Kỳ vọng |
|---------|-------|-----------|---------|
| Test 1 | Loop backward branch 10 lần (taken 9×, not-taken 1×); sum=55 | bne t0,t2,fail | t0=55 |
| Test 2 | JAL 2 lần cùng PC: BTB miss lần 1, hit lần 2 | bne t3,t2,fail | t3=2 |
| Test 3 | Nested loop 3×5=15 iterations | bne t4,t2,fail | t4=15 |
| Test 4 | Alternating taken/not-taken 8 lần; sum=12 (4×1+4×2) | bne a0,t2,fail | a0=12 |

**Verdict:** x31==1 tại EBREAK → **PASS**

---

---

## 3.6.1 Branch Predictor Hit-Rate Metrics


**Testbench:** `SIM/system/tb_metrics.sv` → chạy `prog_branch_pred` qua `soc_top`
**Mục tiêu:** Đo hit rate của branch predictor (16-entry 2-bit BHT + BTB) theo từng pattern branch thực tế.

**Cấu hình predictor:**
- 16-entry BHT, 2-bit saturating counter (trạng thái: SN / WN / WT / ST)
- BTB (Branch Target Buffer): cùng 16 entry, indexed bởi PC[5:2]
- Lookup: combinational tại IF1 (predict taken nếu BHT ≥ WT và BTB hit)
- Update: tại EX trên `posedge clk` sau khi biết kết quả thực tế (`bp_mismatch`)

| Test | Mô tả | Số branch events | Hit rate | Phân tích |
|------|-------|-----------------|----------|-----------|
| T1 | Loop backward branch (taken 9×, not-taken 1×) | ~11 | 81.8% | BHT warm sau iteration 1; miss đúng 1 lần khi exit loop |
| T2 | JAL indirect — BTB cold (2 lần JAL cùng PC) | ~6 | 16.7% | Lần 1: BTB miss (2-cycle penalty); lần 2: BTB hit sau update |
| T3 | Nested loop (outer 3×, inner 5×) | ~19 | 68.4% | Inner BHT warm; outer re-entry gây conflict do index collision |
| T4 | Alternating taken/not-taken (8 lần) | ~21 | 47.6% | Worst-case cho 2-bit hysteresis; predictor dao động WN↔WT |
| **Tổng** | **Overall — 57 branch events** | **57** | **57.9%** | Workload đa dạng thực tế |

**Ghi chú:** Hit rate T2=16.7% là kỳ vọng — test được thiết kế để stress BTB cold start, không phải để có hit rate cao. T4=47.6% là xấp xỉ random do pattern adversarial với 2-bit counter.

---

---

## 3.7 Performance Metrics — tb_metrics


**Testbench:** `SIM/system/tb_metrics.sv`
**Loại:** Observability / performance measurement — **không phải correctness testbench**.
**Không có `pass_cnt`**: Testbench không đếm testcase, không emit PASS/FAIL per-check. Kiểm tra correctness chỉ bằng cách in WARNING nếu x31≠1 tại EBREAK (không fatal).
**Kết quả:** 4 programs chạy đến EBREAK, x31==1 (không warning).

**Cơ chế hoạt động:** Probe hierarchical signals trong `u_soc` để đếm: `total_cycles`, `instr_retired`, `stall_load_use_cycles`, `stall_csr_cycles`, `stall_bus_cycles`, `bp_mispredictions`. In kết quả tổng hợp dưới dạng bảng metrics.

---

### Danh sách programs và metrics thu được

| # | Program | Mục tiêu đo | Kết quả chính |
|---|---------|-----------|--------------|
| 1 | `prog_forwarding` | CPI + stall breakdown | CPI=1.100 (1 load-use stall); 0 bus stall, 0 CSR stall |
| 2 | `prog_branch_pred` | Branch predictor hit rate per test pattern | T1=81.8%(loop), T2=16.7%(BTB cold), T3=68.4%(nested), T4=47.6%(adversarial); overall=57.9% (57 branches) |
| 3 | `prog_ahb_sfr` | AHB CDC transaction latency | avg=9.4 CPU cycles (min=9, max=10, 10 transactions) |
| 4 | `prog_fib` | IPC under realistic Fibonacci workload | CPI=1.182 (18 load-use stalls, 80% branch hit) |

**Stall counter mechanism:**
- `load_use_stall` / `csr_use_stall` đọc từ `u_soc.u_haz.*`
- AHB latency = `bus_stall_req` rising → falling edge per transaction
- Branch hit rate = `(total_branches - bp_mismatch) / total_branches`

> Metrics này được báo cáo trong Chương 5 của luận văn (kết quả thực nghiệm).

---

---

### 3.7.1 Bảng hiệu năng tổng hợp


**Testbench:** `SIM/system/tb_metrics.sv` (4 programs qua `soc_top`)
**Cơ chế probe:** Đọc hierarchical signals từ `u_soc.u_haz.*` và `u_soc.*` để đếm stall cycles, instructions retired, mispredictions.

| Program | Mô tả workload | CPI | IPC | Load-use stalls | CSR-use stalls | Bus stalls | Branch mispred |
|---------|---------------|-----|-----|----------------|---------------|-----------|---------------|
| `prog_forwarding` | ALU-heavy, test forwarding paths — không có load-use | 1.100 | 0.909 | 1 | 0 | 0 | 0 |
| `prog_branch_pred` | 57 branches, 4 patterns | — | — | — | 0 | 0 | 57.9% hit → 42.1% miss |
| `prog_ahb_sfr` | 10 AHB SFR transactions qua CDC FIFO | — | — | 0 | 0 | avg 9.4 cycles/txn | 0 |
| `prog_fib` | Fibonacci recursive — realistic mixed workload | 1.182 | 0.846 | 18 | 0 | 0 | 80% branch hit |

**Chỉ số hệ thống:**

| Metric | Giá trị | Nguồn |
|--------|---------|-------|
| Branch misprediction penalty | 2 cycles/miss (flush IF1/IF2 + IF2/ID) | Hazard unit `bp_mismatch` |
| Load-use stall penalty | 1 cycle (stall IF1..ID, bubble EX) | Hazard unit `fetch_stall` |
| CSR-use stall | 1–3 cycles (gap-1→3; gap-4 dùng WBR bypass) | Hazard unit `csr_stall` |
| AHB CDC latency | avg 9.4 CPU cycles (min=9, max=10) | 1GHz CPU / 500MHz AHB round-trip |

**Cách đo AHB latency:** Đếm số `clk_cpu` từ `bus_stall_req` rising → falling edge mỗi transaction. 10 transactions, kết quả: 9 lần × 9 cycles + 1 lần × 10 cycles = avg 9.4.

---

---

## 3.10 Exception & MTIP System Tests (D2 + D3)

**Mục tiêu:** Kiểm tra end-to-end hai gap RTL mới được thêm trong session này.

### D2 — prog_misaligned: Misaligned Address Exception

**Testbench:** `system/tb_periph.vvp` (+HEX) | **Make:** `make integ_misaligned`
**DUT:** `mem1_stage.sv` — phần `is_mem_access_valid` và `load/store_misaligned_out` → `mem1_mem2_reg` → `mem2_wb_reg` → `zicsr`
**Verdict:** x31==1 tại EBREAK → **PASS**

**Cơ chế:** Trap handler kiểm tra `mcause`, tăng counter, đặt `mepc = mepc+4` (skip instruction lỗi), rồi `mret`. Main loop kiểm tra `counter == 4`.

**Buffer DMEM:** `0x0001_0010` (16-byte aligned → các lần offset tạo ra địa chỉ lẻ / 2-byte aligned).

| TC | Instruction | Địa chỉ (offset từ buffer) | Lý do misaligned | mcause kỳ vọng | Kết quả |
|----|-------------|---------------------------|-----------------|---------------|---------|
| 1  | LH x0, 1(x2) | buffer+1 (byte-odd)      | addr[0]=1 khi mem_size=halfword | 4 (Load Addr Misaligned)  | PASS |
| 2  | LW x0, 2(x2) | buffer+2 (2B-aligned)    | addr[1:0]=10 khi mem_size=word  | 4 (Load Addr Misaligned)  | PASS |
| 3  | SH x0, 1(x2) | buffer+1 (byte-odd)      | addr[0]=1 khi mem_size=halfword | 6 (Store Addr Misaligned) | PASS |
| 4  | SW x0, 2(x2) | buffer+2 (2B-aligned)    | addr[1:0]=10 khi mem_size=word  | 6 (Store Addr Misaligned) | PASS |

**Ghi chú:**
- Misaligned detection nằm hoàn toàn ở `mem1_stage` (combinational, trước khi gửi bất kỳ bus request nào)
- `load_misaligned_out / store_misaligned_out` được pipe qua `mem1_mem2_reg → mem2_wb_reg` để đến Zicsr tại WB stage
- Byte access (`mem_size=00`) không bao giờ misaligned dù địa chỉ bất kỳ — không được test riêng vì formal đã prove (`P_BYTE_ALWAYS_ALIGNED`)

---

### D3 — prog_mtip: Machine Timer Interrupt via MTIP Path

**Testbench:** `system/tb_periph.vvp` (+HEX) | **Make:** `make integ_mtip`
**DUT:** `zicsr.sv` — path `mtip_in` → `mip[7]` → `int_mti` (distinct from MEIP path)
**Verdict:** x31==1 tại EBREAK → **PASS**

**Cơ chế:** Bật MTIE (mie[7]=1) nhưng KHÔNG bật MEIE (mie[11]=0). PLIC không được cấu hình (priority[1]=0, threshold=0 → không forward MEIP). Khi timer fire: `axi_S1_irq` → `soc_top mtip_wire` → `zicsr.mtip_in` → `mip[7]` → `int_mti=1` → interrupt taken.

| TC | Bước kiểm tra | Kỳ vọng | Kết quả |
|----|--------------|---------|---------|
| 1  | mcause sau interrupt | 0x8000_0007 (bit31=1 interrupt, cause=7 MTI) | PASS |
| 2  | mip[7] trong handler | 1 (MTIP đang pending) | PASS |
| 3  | Không có MEIP | PLIC không được cấu hình → meip_in=0; mcause không phải 0xB | PASS |

**Setup timer:** `lui x4, 0x20001` → base=0x2000_1000; PRESCALER=0 (tick mỗi cycle), COMPARE=20, INTR_ENABLE=1, CTRL=1; sau đó `csrrs mie, MTIE`; `csrrs mstatus, MIE`.

**Handler:** Verify `mcause==0x8000_0007`, verify `mip[7]==1`, stop timer (CTRL=0), W1C INTR_STATE, disable MTIE, `csrw mepc, pass; mret`.

**Điểm quan trọng:** Test này chứng minh path MTIP hoạt động **độc lập** với PLIC/MEIP — hai cơ chế có thể kích hoạt riêng biệt tùy `mie` bits.

---

## 3.8 IRQ \/ Exception Coverage


**Mục tiêu:** Xác nhận tất cả nguồn ngắt và exception được xử lý đúng đến đích (mcause, mepc, PLIC claim/complete, MRET).

| Nguồn / Sự kiện | Loại | mcause | Test cover | Kết quả |
|-----------------|------|--------|-----------|---------|
| Machine External Interrupt (MEI) | Interrupt | 0x8000_000B (=11) | `prog_plic_basic`, `prog_timer`, `prog_gpio_ahb`, `prog_uart` | PASS |
| **Machine Timer Interrupt (MTIP)** | **Interrupt** | **0x8000_0007 (=7)** | **`prog_mtip`** (mie[7]=MTIE only; axi_S1_irq→mtip_in→mip[7]) | **PASS** |
| Illegal Instruction | Exception | 2 | `tb_zicsr` | PASS |
| **Load Address Misaligned** | **Exception** | **4** | **`prog_misaligned`** (LH/LW tại địa chỉ lẻ) | **PASS** |
| Load Access Fault — AXI SLVERR | Exception | 5 | `tb_soc_bus_err` (prog_read_err) | PASS |
| **Store Address Misaligned** | **Exception** | **6** | **`prog_misaligned`** (SH/SW tại địa chỉ lẻ) | **PASS** |
| Store Access Fault — AXI SLVERR | Exception | 7 | `tb_soc_bus_err` (prog_bus_err) | PASS |
| Load Access Fault — AHB HRESP ERROR | Exception | 5 | `tb_soc_ahb_err` (prog_ahb_load_err) | PASS |
| Store Access Fault — AHB HRESP ERROR | Exception | 7 | `tb_soc_ahb_err` (prog_ahb_store_err) | PASS |
| ECALL from M-mode | Exception | 11 | `tb_zicsr`, `prog_csr_hazard` | PASS |
| MRET (trap return) | System | — | `tb_zicsr`, `prog_plic_basic`, tất cả IRQ programs | PASS |
| PLIC priority arbitration (6 sources) | HW logic | — | `tb_plic` (31 cases), `formal_plic` (P_PLIC_PRIORITY) | PASS |
| IRQ CDC — AHB 500MHz → 1GHz | CDC sync | — | `tb_irq_sync2ff` (10 cases), `prog_gpio_ahb` | PASS |

**Cơ chế xử lý exception đặc biệt:**

| Scenario | Hành vi | Test |
|----------|---------|------|
| Bus transaction đang diễn ra → exception | Precise: pipeline stall cho đến khi transaction xong (bus_stall_req=0), sau đó mới flush | `tb_soc_bus_err`, `tb_soc_ahb_err` |
| AHB 2-cycle ERROR protocol | ERR_C1: HREADYOUT=0,HRESP=1 → ERR_C2: HREADYOUT=1,HRESP=1 → CPU nhận HRESP→exception | `tb_soc_ahb_err` |
| Multiple IRQ sources | PLIC arbitrate: winner = highest priority source > threshold; CPU claim/complete handshake | `prog_plic_priority`, `prog_plic_threshold` |
| PLIC threshold masking | IRQ không đến CPU nếu priority ≤ threshold | `prog_plic_threshold` | 

---

---

## 3.9 Peripheral Feature Coverage


**Mục tiêu:** Tổng hợp tất cả feature của từng peripheral đã được test và kết quả.

### timer_axi (AXI-Lite Timer, PLIC src 2)

| Feature | Test | Kết quả |
|---------|------|---------|
| PERIPH_ID = 0x5449_4D52 ("TIMR") | tb_timer_axi T2 | PASS |
| CTRL[0] = enable / disable counter | tb_timer_axi T4, T5, T13 | PASS |
| CTRL[1] = auto_reload | tb_timer_axi T11, T12 | PASS |
| DATA0 = PRESCALER (divides tick rate) | tb_timer_axi T3, T14 | PASS |
| DATA1 = COMPARE (compare-match threshold) | tb_timer_axi T3, T6 | PASS |
| STATUS = timer_cnt (read-only) | tb_timer_axi T4, T5, T11, T12 | PASS |
| INTR_STATE[0] set on compare-match | tb_timer_axi T6 | PASS |
| INTR_ENABLE masking | tb_timer_axi T7, T8 | PASS |
| W1C clear INTR_STATE | tb_timer_axi T9 | PASS |
| INTR_TEST force-set | tb_timer_axi T10 | PASS |
| End-to-end IRQ → PLIC → Zicsr → handler | prog_timer | PASS |

### gpio_ahb (AHB-Lite GPIO, PLIC src 4)

| Feature | Test | Kết quả |
|---------|------|---------|
| PERIPH_ID = 0x4750_4941 ("GPIA") | tb_gpio_ahb G2 | PASS |
| DATA0 = gpio_out value | tb_gpio_ahb G3, G4 | PASS |
| DATA1[0] = OE (output enable) | tb_gpio_ahb G3 | PASS |
| DATA2[0] = edge_type (0=rising, 1=falling) | tb_gpio_ahb G10 | PASS |
| STATUS = sync'd gpio_in (2-FF sync) | tb_gpio_ahb G5 | PASS |
| Rising edge detect → INTR_STATE | tb_gpio_ahb G6 | PASS |
| Falling edge detect → INTR_STATE | tb_gpio_ahb G10 | PASS |
| INTR_ENABLE masking | tb_gpio_ahb G8 | PASS |
| W1C clear INTR_STATE | tb_gpio_ahb G7 | PASS |
| INTR_TEST force-set | tb_gpio_ahb G9 | PASS |
| No spurious IRQ when gpio_in stable | tb_gpio_ahb G11 | PASS |
| AHB pipeline protocol (addr phase → data phase) | All G tests | PASS |
| Loopback + INTR_TEST IRQ → PLIC → handler | prog_gpio_ahb | PASS |

### uart_axi (AXI-Lite 8N1 UART, PLIC src 3)

| Feature | Test | Kết quả |
|---------|------|---------|
| PERIPH_ID = 0x5541_5254 ("UART") | tb_uart_axi U2 | PASS |
| DATA0 = baud_div (bit period = baud_div+1 cycles) | tb_uart_axi U3, U5 | PASS |
| CTRL[0] = uart_en (TX guard) | tb_uart_axi U4 | PASS |
| TX frame: start(0) + 8 data bits LSB-first + stop(1) | tb_uart_axi U5, formal P_8N1 | PASS |
| STATUS[0] = tx_busy during TX | tb_uart_axi U6 | PASS |
| TX busy guard: 2nd write blocked khi tx_busy | tb_uart_axi U10 | PASS |
| INTR_STATE[0] = tx_done, pulse 1 cycle | tb_uart_axi U7, formal P_TX_PULSE | PASS |
| RX 2-FF sync (uart_rx) | tb_uart_axi U11 | PASS |
| RX frame sampling (mid-bit sample point) | tb_uart_axi U11, formal P_8N1 | PASS |
| DATA2 = received byte | tb_uart_axi U11, U13 | PASS |
| INTR_STATE[1] = rx_complete, pulse 1 cycle | tb_uart_axi U11, formal P_RX_PULSE | PASS |
| RX bit counter ≤ 8 | formal P_RX_BIT_CNT | PROVED |
| INTR_ENABLE masking | tb_uart_axi U13 | PASS |
| W1C clear INTR_STATE | tb_uart_axi U8, U12 | PASS |
| INTR_TEST force-set | tb_uart_axi U9 | PASS |
| TX/RX loopback + dual IRQ → PLIC → handler | prog_uart | PASS |

---



---

## ═══ PHẦN 4: RV32I ISA COMPLIANCE ═══

---

## Phase 19 — RV32I ISA Compliance (riscv-arch-test)

**Framework:** riscv-arch-test old-framework-2.x (signature-based compliance)
**Runner:** `SIM/compliance/run_compliance.sh` (bash)
**Testbench:** `SIM/compliance/tb_compliance_run.sv`
**DUT:** `soc_top` với tham số `IMEM_SIZE_KB=512` (mở rộng cho compliance tests)
**Kết quả:** **37/37 PASS, 1 SKIP** (jal-01 ~1.7MB > 512KB IMEM), **0 FAIL**

Compliance không dùng `pass_cnt`; đơn vị đo là **test case = 1 .S file**. Verdict = signature exact match với `reference_output`.

---

### Cơ chế hoạt động

```
tests/src/<instr>-01.S ──[gcc]──► .elf ──[objcopy]──► .hex + .dmem.hex
                                   │
                              [nm] extract begin_signature / end_signature
                                   │
                         tb_compliance_run.vvp
                          (+HEX, +SIG_BEGIN, +SIG_END, +SIG_FILE)
                                   │
                         soc_top (512KB IMEM)
                         $readmemh → run → EBREAK detected → dump DMEM[sig_begin..sig_end]
                                   │
                               .sig file ──[diff]──► tests/references/<instr>-01.reference_output
                                   │
                          PASS (diff empty) / SIG_MISMATCH / SKIP(IMEM)
```

**Signature format:** Mỗi word 32-bit trên 1 dòng, lowercase 8-hex, khớp với output của Spike ISA simulator.

**Luồng xử lý đặc biệt:**
- Nếu test có `.data` section (load/store tests): extract thêm `dmem_hex` (rebased từ 0x10000 → 0x0) và pre-load vào DMEM
- Nếu code section > 512KB: SKIP(IMEM) — không phải FAIL
- X-bits trong DMEM (uninitialized words): ghi 0 vào signature (đúng với behavior của Spike)
- Timeout: 5M cycles (đủ cho các test có code lớn)

---

### Danh sách 38 Compliance Tests

| # | Test | Nhóm lệnh | Kết quả | Ghi chú |
|---|------|-----------|---------|---------|
| 1 | add-01 | R-type ALU | PASS | |
| 2 | addi-01 | I-type ALU | PASS | |
| 3 | and-01 | R-type ALU | PASS | |
| 4 | andi-01 | I-type ALU | PASS | |
| 5 | auipc-01 | U-type | PASS | PC-relative upper immediate |
| 6 | beq-01 | Branch | PASS | |
| 7 | bge-01 | Branch | PASS | Signed compare |
| 8 | bgeu-01 | Branch | PASS | Unsigned compare |
| 9 | blt-01 | Branch | PASS | Signed compare |
| 10 | bltu-01 | Branch | PASS | Unsigned compare |
| 11 | bne-01 | Branch | PASS | |
| 12 | fence-01 | Misc | PASS | NOP trong impl không có fence |
| 13 | jal-01 | J-type | **SKIP** | ~1.7MB > 512KB IMEM |
| 14 | jalr-01 | I-type Jump | PASS | |
| 15 | lb-align-01 | Load | PASS | Signed byte load |
| 16 | lbu-align-01 | Load | PASS | Unsigned byte load |
| 17 | lh-align-01 | Load | PASS | Signed halfword load |
| 18 | lhu-align-01 | Load | PASS | Unsigned halfword load |
| 19 | lui-01 | U-type | PASS | Upper immediate |
| 20 | lw-align-01 | Load | PASS | Word load |
| 21 | or-01 | R-type ALU | PASS | |
| 22 | ori-01 | I-type ALU | PASS | |
| 23 | sb-align-01 | Store | PASS | Byte store |
| 24 | sh-align-01 | Store | PASS | Halfword store |
| 25 | sll-01 | R-type Shift | PASS | |
| 26 | slli-01 | I-type Shift | PASS | |
| 27 | slt-01 | R-type ALU | PASS | Set-less-than signed |
| 28 | slti-01 | I-type ALU | PASS | |
| 29 | sltiu-01 | I-type ALU | PASS | Unsigned |
| 30 | sltu-01 | R-type ALU | PASS | Unsigned |
| 31 | sra-01 | R-type Shift | PASS | Arithmetic right shift |
| 32 | srai-01 | I-type Shift | PASS | |
| 33 | srl-01 | R-type Shift | PASS | Logical right shift |
| 34 | srli-01 | I-type Shift | PASS | |
| 35 | sub-01 | R-type ALU | PASS | |
| 36 | sw-align-01 | Store | PASS | Word store |
| 37 | xor-01 | R-type ALU | PASS | |
| 38 | xori-01 | I-type ALU | PASS | |

**Tổng: 37 PASS / 1 SKIP / 0 FAIL**

---

### Ghi chú về jal-01 (SKIP)

- Test vector jal-01 của riscv-arch-test tạo ra code ~1.7MB để kiểm thử toàn bộ range của offset 20-bit (±1MB). Vượt 512KB IMEM của testbench.
- Functionality của JAL đã được xác nhận qua: `prog_branch_pred` (JAL BTB test), `prog_csr` (các lệnh gọi hàm), và các Phase 3/5/6 system programs.
- SKIP không ảnh hưởng đến compliance rating — đây là giới hạn phần cứng (IMEM size), không phải lỗi implementation.

---

### Tham chiếu chéo — RV32I Instruction Coverage

| Nhóm lệnh | Số instruction | Compliance tests | Testbench bổ sung |
|-----------|---------------|-----------------|-------------------|
| R-type ALU (add/sub/and/or/xor/slt/sltu) | 7 | 7 PASS | tb_alu (Phase 1) |
| R-type Shift (sll/srl/sra) | 3 | 3 PASS | tb_alu, prog_rv32i_shifts |
| I-type ALU (addi/andi/ori/xori/slti/sltiu) | 6 | 6 PASS | tb_alu |
| I-type Shift (slli/srli/srai) | 3 | 3 PASS | tb_alu, prog_rv32i_shifts |
| U-type (lui/auipc) | 2 | 2 PASS | tb_id_decoder |
| Branch (beq/bne/blt/bge/bltu/bgeu) | 6 | 6 PASS | tb_branch_comp, prog_branch_jump |
| Jump (jal/jalr) | 2 | 1 PASS + 1 SKIP | prog_branch_pred (JAL) |
| Load (lb/lbu/lh/lhu/lw) | 5 | 5 PASS | prog_load_store |
| Store (sb/sh/sw) | 3 | 3 PASS | prog_load_store |
| Misc (fence) | 1 | 1 PASS | — |

**Tổng RV32I instructions: 38; Compliance coverage: 37/38 (97.4%)**

---

---


---

## ═══ PHẦN 5: FORMAL VERIFICATION ═══

---

## Phase 18 — Formal Verification (SymbiYosys, smtbmc z3)

**Công cụ:** SymbiYosys + smtbmc (z3 backend), k-induction mode (`mode: prove`).
**Tổng quan:** 7 sby jobs, ~29 individual `assert()` calls, nhóm thành 13 named properties. **7/7 PROVED.**
**Ghi chú:** Phát hiện và sửa 1 RTL bug trong `uart_axi` (TX FSM) trong quá trình chứng minh.

Formal verification không có `pass_cnt`; đơn vị đo là **property PROVED** (k-induction đủ depth). Mỗi job được chạy bằng `make formal_<name>` (xem CLAUDE.md cho lệnh).

---

### Job 1: formal_x0 — register_file x0 immutability

**File:** `SIM/formal/fv_reg_x0.sby` + `fv_reg_x0.sv`
**DUT:** `register_file`
**Depth:** 15 | **Method:** k-induction | **Result:** PROVED

**Property P_REG_X0** (3 assertions nhóm thành 1 invariant):

| Assert | Mô tả | Logic |
|--------|-------|-------|
| P1 | rs1 port: đọc x0 luôn trả 0 | `(rs1_addr != 0) \|\| (rs1_data == 0)` |
| P2 | rs2 port: đọc x0 luôn trả 0 | `(rs2_addr != 0) \|\| (rs2_data == 0)` |
| P3 | Ghi vào rd_addr==0 không làm bẩn x0 | Sau `$past(we && rd_addr==0)`: P1 và P2 vẫn đúng |

**Cơ chế:** Combinational read path hard-codes `(rs1_addr==0) ? 0 : reg[rs1_addr]`. K-induction chứng minh invariant giữ cho mọi reachable state với symbolic inputs.

---

### Job 2: formal_fifo — async_fifo Gray-code + data integrity

**File:** `SIM/formal/fv_fifo_gray.sby` + `fv_fifo_gray.sv`
**DUT:** `async_fifo_depth2` (DATA_WIDTH=8, single-clock model cho proof)
**Depth:** 12 | **Method:** k-induction | **Result:** PROVED

**Properties (assertions trong `async_fifo.sv` dưới `` `ifdef FORMAL ``):**

| Property | Mô tả | Logic |
|----------|-------|-------|
| P_GRAY | Gray-code pointer: consecutive values differ bởi đúng 1 bit | `$countones(wr_ptr_gray ^ $past(wr_ptr_gray)) <= 1` |
| P_FIFO_DATA | Dữ liệu ra = dữ liệu đã push (FIFO integrity) | `rd_data == mem[rd_ptr_bin]` khi FIFO not empty |

**Lý do single-clock:** P_GRAY thuộc write domain; single-clock model không ảnh hưởng đến tính đúng của proof.

---

### Job 3: formal_uart — uart_axi 8N1 protocol invariants

**File:** `SIM/formal/fv_uart_proto.sby` + `fv_uart_proto.sv`
**DUT:** `uart_axi` (fully symbolic AXI master + uart_rx)
**Depth:** 20 | **Method:** k-induction | **Result:** PROVED

**4 named properties (assertions trong `uart_axi.sv` dưới `` `ifdef FORMAL ``):**

| Property | Mô tả | Logic |
|----------|-------|-------|
| P_8N1 | Frame boundary semantics: IDLE→high, START→low, STOP→high | `(tx_state==IDLE → uart_tx==1)` và `(tx_state==START → uart_tx==0)` và `(tx_state==STOP → uart_tx==1)` |
| P_TX_PULSE | tx_done pulse đúng 1 cycle sau hoàn thành | `tx_done` pulse width == 1 cycle |
| P_RX_PULSE | rx_done pulse đúng 1 cycle | Tương tự P_TX_PULSE cho RX path |
| P_RX_BIT_CNT | Bit counter không vượt quá 8 | `rx_bit_cnt <= 4'd8` at all times |

**RTL bug tìm thấy:** Formal phát hiện TX FSM có thể enter trạng thái invalid; đã sửa trong `uart_axi.sv` trước khi proof hoàn thành.

---

### Job 4: formal_axi — axi_interface VALID stability

**File:** `SIM/formal/fv_axi_handshake.sby` + `fv_axi_handshake.sv`
**DUT:** `axi_interface` (symbolic CPU request + symbolic slave responses)
**Depth:** 10 | **Method:** k-induction | **Result:** PROVED

**Property P_AXI_HANDSHAKE** (3 assertions theo AXI4-Lite §A3.2.1):

| Assert | Mô tả | Logic |
|--------|-------|-------|
| P_AXI_AR | ARVALID stable đến khi handshake | `$past(ARVALID) && !$past(ARREADY) → ARVALID` |
| P_AXI_AW | AWVALID stable đến khi handshake | `$past(AWVALID) && !$past(AWREADY) → AWVALID` |
| P_AXI_W | WVALID stable đến khi handshake | `$past(WVALID) && !$past(WREADY) → WVALID` |

**Rủi ro nếu vi phạm:** Master de-assert VALID khi slave đang chờ → deadlock giao dịch.

---

### Job 5: formal_plic — PLIC priority encoder correctness

**File:** `SIM/formal/fv_plic_priority.sby` + `fv_plic_priority.sv`
**DUT:** `plic` (fully symbolic irq_src, priority, enable, threshold)
**Depth:** 10 | **Method:** k-induction | **Result:** PROVED

**Property P_PLIC_PRIORITY** (4 assertions nhóm thành 1 invariant):

| Assert | Mô tả | Logic |
|--------|-------|-------|
| P_WINNER_BOUND | winner_id luôn trong [0..6] | `winner_id <= 6` |
| P_WINNER_ACTIVE | Nếu có winner, source đó phải đang active | `winner_id != 0 → src_active[winner_id]` |
| P_WINNER_OPTIMAL | Winner có priority cao nhất trong tất cả active sources | `∀ i: src_active[i] → priority[i] <= win_pri` |
| P_MEIP | meip đúng khi có winner vượt threshold | `meip == (winner_id != 0)` |

---

### Job 6: formal_reg_wbr — register_file WBR bypass + sequential read

**File:** `SIM/formal/fv_reg_wbr.sby` + `fv_reg_wbr.sv`
**DUT:** `register_file`
**Depth:** 5 | **Method:** k-induction | **Result:** PROVED

**2 properties (cả rs1 và rs2 port):**

| Property | Mô tả | Logic |
|----------|-------|-------|
| P_WBR | Same-cycle bypass: ghi và đọc cùng địa chỉ trong 1 cycle → rs_data == rd_data ngay lập tức (combinational) | `we && rd_addr != 0 && rs1_addr == rd_addr → rs1_data == rd_data` |
| P_RF_SEQ | Next-cycle read: cycle N+1 đọc cùng địa chỉ đã ghi ở cycle N → trả đúng giá trị | `$past(we) && rs1_addr == $past(rd_addr) && !(we && rd_addr == $past(rd_addr)) → rs1_data == $past(rd_data)` |

**Symmetric assertions trên rs2 port** cũng được chứng minh (4 `assert()` tổng cho job này).
**Ý nghĩa:** Chứng minh pipeline không bao giờ đọc stale value — GAP-0 WBR bypass và GAP-1 từ MEM đều được bảo đảm bởi formal.

---

### Job 7: formal_stall — Pipeline stall coherence

**File:** `SIM/formal/fv_stall_coherence.sby` + `fv_stall_coherence.sv`
**DUT:** `hazard_unit` + `if1_if2_reg` + `if2_id_reg` + `id_ex_reg`
**Depth:** 8 | **Method:** k-induction | **Result:** PROVED

**2 named properties (7 individual `assert()` blocks):**

#### P_STALL_COHERENCE — Registers giữ nguyên khi stall

| Assert | Mô tả | Logic |
|--------|-------|-------|
| P_STALL_SYMMETRY | stall_if1_if2 == stall_if2_id (cùng nguồn gốc) | `stall_if1_if2 == stall_if2_id` và `flush_if1_if2 == flush_if2_id` |
| P_IF1IF2_STALL | IF1/IF2 reg giữ nguyên khi stall=1, flush=0 | `$past(stall && !flush) → {pc, bp_taken, bp_target} không thay đổi` |
| P_IF2ID_STALL | IF2/ID reg giữ nguyên khi stall=1, flush=0 | Tương tự, bao gồm `instr` field |
| P_IDEX_STALL | ID/EX reg giữ TẤT CẢ field khi stall=1, flush=0 | 29 signal fields: pc, rs1, rs2, imm, alu_op, branch, mem_*, reg_write, csr_*, exception flags, bp metadata |

#### P_FLUSH — Registers cleared đúng khi flush

| Assert | Mô tả | Logic |
|--------|-------|-------|
| P_IF1IF2_FLUSH | IF1/IF2 reg → pc=0, bp_taken=0, bp_target=0 sau flush | `$past(flush_if1_if2) → {pc, bp_taken, bp_target} == 0` |
| P_IF2ID_FLUSH | IF2/ID reg → pc=0, instr=NOP (0x13), bp cleared | `$past(flush_if2_id) → pc=0, instr=0x0000_0013, bp=0` |
| P_IDEX_FLUSH | ID/EX reg → tất cả control signals cleared sau flush | branch=0, jump=0, mem_read=0, mem_write=0, reg_write=0, csr_we=0, ec/eb/mret/ill=0 |

**Lưu ý P_IDEX_STALL:** Wrapper instantiate `id_ex_reg` với toàn bộ 30+ ports (data + control + BP metadata) — đây là job phức tạp nhất, xác nhận không có field nào bị bỏ sót khi stall.

---

---

### Job 8: formal_alu — ALU arithmetic/logic correctness (D1)

**File:** `SIM/formal/fv_alu.sby` + `fv_alu.sv`
**DUT:** `alu`
**Depth:** 3 | **Method:** k-induction | **Result:** PROVED

**12 properties — mỗi alu_op cho đúng kết quả với mọi `(operand_a, operand_b)` 32-bit symbolic:**

| Property | alu_op | Assertion |
|----------|--------|-----------|
| P_ADD  | 0000 | `result == operand_a + operand_b` |
| P_SUB  | 0001 | `result == operand_a - operand_b` |
| P_AND  | 1001 | `result == operand_a & operand_b` |
| P_OR   | 1000 | `result == operand_a \| operand_b` |
| P_XOR  | 0101 | `result == operand_a ^ operand_b` |
| P_SLT  | 0011 | `result == ($signed(a) < $signed(b)) ? 1 : 0` |
| P_SLTU | 0100 | `result == (a < b) ? 1 : 0` |
| P_SLL  | 0010 | `result == a << shift_amt (5-bit)` |
| P_SRL  | 0110 | `result == a >> shift_amt` |
| P_SRA  | 0111 | `result == $signed(a) >>> shift_amt` |
| P_SRA_SIGN | 0111 | `a[31] && shift_amt > 0 → result[31] == 1` (sign extension) |
| P_PASSB | 1010 | `result == operand_b` (ignores a) |

---

### Job 9: formal_decoder — id_decoder encoding invariants (D1)

**File:** `SIM/formal/fv_decoder.sby` + `fv_decoder.sv`
**DUT:** `id_decoder`
**Depth:** 3 | **Method:** k-induction | **Result:** PROVED
**Input:** `instr[31:0]` symbolic (tất cả 2³² encodings có thể)

**8 properties:**

| Property | Mô tả | Logic |
|----------|-------|-------|
| P_LOAD_CLASS | Load instructions → mem_read=1, mem_write=0, reg_write=1 | `opcode==LOAD → mem_read=1` |
| P_STORE_CLASS | Store instructions → mem_write=1, mem_read=0, reg_write=0 | `opcode==STORE → mem_write=1` |
| P_BRANCH_NO_MEM | Branch → no memory access | `opcode==BRANCH → !mem_read && !mem_write` |
| P_BRANCH_NO_JUMP | Branch và jump không đồng thời | `!(branch && jump)` |
| P_JAL_CLASS | JAL → jump=1, jump_reg=0, reg_write=1 | xác nhận JAL encoding |
| **P_MEM_MUTEX** | **Không instruction nào có cả mem_read=1 và mem_write=1** | `assert(!(mem_read & mem_write))` — chứng minh cho MỌI 2³² encoding |
| P_OP_NOREG | OP-Imm → alu_src_b=imm (không phải reg) | `opcode==OPIMM → alu_src_b=1` |
| **P_UNKNOWN_SAFE** | **Opcode không nhận diện → không thay đổi arch state** | unknown opcode → `mem_read=0 & mem_write=0 & reg_write=0 & csr_we=0 & branch=0 & jump=0` |

**Điểm quan trọng:** P_MEM_MUTEX chứng minh rằng `mem_read & mem_write` là bất biến 0 với mọi 32-bit instruction encoding — đây là precondition cho assumption trong `fv_mem1_addr`.

---

### Job 10: formal_mem1_addr — mem1_stage address decode + misaligned (D1)

**File:** `SIM/formal/fv_mem1_addr.sby` + `fv_mem1_addr.sv`
**DUT:** `mem1_stage`
**Depth:** 5 | **Method:** k-induction | **Result:** PROVED
**Assumption:** `assume(!(mem_read_in & mem_write_in))` — guaranteed bởi P_MEM_MUTEX từ formal_decoder.

**6 properties:**

| Property | Mô tả | Logic |
|----------|-------|-------|
| P_BUS_MUTEX | Chỉ 1 interface bus được request tại một thời điểm | `dmem_re & axi_req_valid = 0`; `dmem_re & req_fifo_wr_en = 0`; `axi_req_valid & req_fifo_wr_en = 0`; và tương tự cho write |
| P_MISALIGN_BLOCK | Misaligned access không được phép reach bất kỳ bus nào | `is_mem_access & is_misaligned → dmem_re=0 & dmem_we=0 & axi_req_valid=0 & req_fifo_wr_en=0 & plic_re=0 & plic_we=0` |
| P_MISALIGN_LOAD_FLAG | Misaligned load set load_misaligned_out=1 | `is_misaligned & mem_read_in → load_misaligned_out=1` |
| P_MISALIGN_STORE_FLAG | Misaligned store set store_misaligned_out=1 | `is_misaligned & mem_write_in → store_misaligned_out=1` |
| P_BYTE_ALWAYS_ALIGNED | Byte access (mem_size=00) không bao giờ misaligned | `mem_size=00 → load_misaligned_out=0 & store_misaligned_out=0` |
| P_FAULT_MUTEX | load_access_fault và store_access_fault không đồng thời | `!(load_access_fault & store_access_fault)` |

**Ghi chú:** P_MISALIGN_FAULT_MUTEX (misaligned và fault không đồng thời cho cùng instruction) là pipeline-level invariant, không thể prove tại module boundary — giải thích chi tiết trong fv_mem1_addr.sv.

---

### Job 11: formal_axi_route — AXI interconnect routing correctness (D1)

**File:** `SIM/formal/fv_axi_route.sby` + `fv_axi_route.sv`
**DUT:** `axi_interconnect`
**Depth:** 5 | **Method:** k-induction | **Result:** PROVED

**6 properties — mọi symbolic 32-bit address:**

| Property | Mô tả |
|----------|-------|
| P_AW_MUTEX | Tại mỗi cycle: chỉ 1 trong {S0_AWVALID, S1_AWVALID, S2_AWVALID} có thể =1 |
| P_AR_MUTEX | Tại mỗi cycle: chỉ 1 trong {S0_ARVALID, S1_ARVALID, S2_ARVALID} có thể =1 |
| P_AW_ROUTE_S0 | M_AWVALID & addr[27:12]==0x0000 → S0_AWVALID=1, S1=0, S2=0 |
| P_AW_ROUTE_S1 | M_AWVALID & addr[27:12]==0x0001 → S1_AWVALID=1, S0=0, S2=0 |
| P_AR_ROUTE_S0 | M_ARVALID & addr[27:12]==0x0000 → S0_ARVALID=1, S1=0, S2=0 |
| P_AR_ROUTE_S2 | M_ARVALID & addr[27:12]==0x0002 → S2_ARVALID=1, S0=0, S1=0 |

---

### Job 12: formal_ahb_route — AHB interconnect routing correctness (D1)

**File:** `SIM/formal/fv_ahb_route.sby` + `fv_ahb_route.sv`
**DUT:** `ahb_interconnect`
**Depth:** 5 | **Method:** k-induction | **Result:** PROVED

**5 properties:**

| Property | Mô tả |
|----------|-------|
| P_AHB_HSEL_MUTEX | Chỉ 1 trong {HSEL0, HSEL1, HSEL2} có thể =1 tại mỗi cycle |
| P_AHB_ROUTE_S0 | HTRANS[1]=1 & HADDR[27:12]==0x0000 → HSEL0=1, HSEL1=0, HSEL2=0 |
| P_AHB_ROUTE_S1 | HTRANS[1]=1 & HADDR[27:12]==0x0001 → HSEL1=1, HSEL0=0, HSEL2=0 |
| P_AHB_ROUTE_S2 | HTRANS[1]=1 & HADDR[27:12]==0x0002 → HSEL2=1, HSEL0=0, HSEL1=0 |
| P_AHB_IDLE_NO_SEL | HTRANS[1]=0 (IDLE/BUSY) → HSEL0=0 & HSEL1=0 & HSEL2=0 |

---

---

### Job 13: formal_precise_exc — Precise Exception Invariant (D4)

**File:** `SIM/formal/fv_precise_exc.sby` + `fv_precise_exc.sv`
**DUT:** `zicsr`
**Depth:** 5 | **Method:** k-induction | **Result:** PROVED

**Bối cảnh:** RISC-V Privileged Spec yêu cầu "precise exceptions" — không có side effect từ instruction sau instruction lỗi. Với bus transaction: khi `bus_stall_req=1` (AXI/AHB transaction đang chờ response), exception hay interrupt không được phép flush pipeline và cancel transaction đang dở.

**RTL implementation (zicsr.sv):**
```
take_exception = any_exception & ~bus_stall_req      ← gated
take_interrupt = ~any_exc & mstatus_mie & irq & ~bus_stall_req  ← gated
zicsr_flush    = take_exception | take_interrupt | wb_mret
```
`wb_mret` KHÔNG bị gate bởi `~bus_stall_req` — đây là thiết kế đúng vì MRET là control instruction, không có memory side effect.

**6 properties:**

| Property | Assertion | Ý nghĩa |
|----------|-----------|---------|
| P_BUS_STALL_GATE | `bus_stall_req → (zicsr_flush == wb_mret)` | Core invariant: trong bus stall, chỉ MRET có thể flush |
| P_MRET_FLUSH | `wb_mret → zicsr_flush` | MRET luôn flush (không gate bởi bus_stall) |
| P_EXC_FLUSH | `any_exc & !bus_stall_req → zicsr_flush` | Completeness: exception + bus idle → flush (không bị drop) |
| P_EXC_HELD | `bus_stall_req & any_exc & !wb_mret → !zicsr_flush` | Exception pending trong bus stall → flush=0 |
| P_FLUSH_IDLE_BUS | `zicsr_flush & !wb_mret → !bus_stall_req` | Contrapositive: non-MRET flush → bus phải rảnh |
| P_NO_DOUBLE_GATE | `bus_stall_req & any_exc & !wb_mret → !zicsr_flush` | Strongest: bus stall + exc + no MRET → strictly no flush |

**Ghi chú kỹ thuật:**
- `any_exc` được derive trong formal wrapper bằng cách mirror chính xác assignment trong zicsr.sv (7 exception signals OR'd lại)
- Hierarchical references đến internal signals không được Yosys resolve khi dùng SymbiYosys — properties được viết hoàn toàn qua DUT ports
- P_EXC_HELD và P_NO_DOUBLE_GATE là cùng logic nhưng phát biểu theo 2 hướng khác nhau để rõ ràng hơn về semantic
- Properties 1, 4, 5, 6 cùng nắm bắt một invariant từ các góc nhìn khác nhau; mỗi cái có giá trị documentation riêng

---

### Tổng kết Formal Verification

| Job | DUT | Properties | Assertions | Depth | Kết quả |
|-----|-----|-----------|-----------|-------|---------|
| formal_x0 | register_file | P_REG_X0 | 3 | 15 | PROVED |
| formal_fifo | async_fifo_depth2 | P_GRAY + P_FIFO_DATA | 2 | 12 | PROVED |
| formal_uart | uart_axi | P_8N1 + P_TX_PULSE + P_RX_PULSE + P_RX_BIT_CNT | 6 | 20 | PROVED |
| formal_axi | axi_interface | P_AXI_HANDSHAKE | 3 | 10 | PROVED |
| formal_plic | plic | P_PLIC_PRIORITY | 4 | 10 | PROVED |
| formal_reg_wbr | register_file | P_WBR + P_RF_SEQ | 4 | 5 | PROVED |
| formal_stall | hazard_unit + 3 regs | P_STALL_COHERENCE + P_FLUSH | 7 | 8 | PROVED |
| **formal_alu** | **alu** | **P_ADD..P_PASSB (12 props)** | **12** | **3** | **PROVED** |
| **formal_decoder** | **id_decoder** | **P_LOAD_CLASS..P_UNKNOWN_SAFE (8 props)** | **8** | **3** | **PROVED** |
| **formal_mem1_addr** | **mem1_stage** | **P_BUS_MUTEX..P_FAULT_MUTEX (6 props)** | **6** | **5** | **PROVED** |
| **formal_axi_route** | **axi_interconnect** | **P_AW_MUTEX..P_AR_ROUTE_S2 (6 props)** | **6** | **5** | **PROVED** |
| **formal_ahb_route** | **ahb_interconnect** | **P_HSEL_MUTEX..P_IDLE_NO_SEL (5 props)** | **5** | **5** | **PROVED** |
| **formal_precise_exc** | **zicsr** | **P_BUS_STALL_GATE..P_NO_DOUBLE_GATE (6 props)** | **6** | **5** | **PROVED** |
| **Tổng** | | **19 named groups** | **~73** | | **13/13 PROVED** |

**Ghi chú:** Phát hiện và sửa 1 RTL bug trong `uart_axi` (TX FSM) trong quá trình chạy formal.
**D1 datapath (Jobs 8–12):** Chứng minh tính đúng đắn của các module datapath/routing — bổ sung cho Jobs 1–7 tập trung vào infrastructure/protocol invariants.
**D4 (Job 13):** Chứng minh invariant "precise exception" — bus transaction không bị abort bởi exception/interrupt, mà phải chờ đến khi bus_stall_req=0.

---


