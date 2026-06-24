# Bảng Decode — id_decoder

Tài liệu này mô tả logic giải mã lệnh trong `id_decoder.sv` theo dạng bảng, thay thế cho flowchart case(opcode) vốn rất lớn khi vẽ.

---

## Bảng 1 — Tín Hiệu Điều Khiển Chính (theo opcode)

| Lệnh    | Opcode      | imm | alu\_src\_a | alu\_src\_b | alu\_op      | branch | jump | jump\_reg | reg\_write | wb\_sel |
|---------|-------------|-----|------------|------------|--------------|--------|------|-----------|------------|---------|
| LUI     | `011_0111`  | U   | rs1        | imm        | PASSB        | 0      | 0    | 0         | 1          | ALU     |
| AUIPC   | `001_0111`  | U   | **PC**     | imm        | ADD          | 0      | 0    | 0         | 1          | ALU     |
| JAL     | `110_1111`  | J   | —          | —          | —            | 0      | 1    | 0         | 1          | PC+4    |
| JALR    | `110_0111`  | I   | —          | —          | —            | 0      | 1    | **1**     | 1          | PC+4    |
| BRANCH  | `110_0011`  | B   | —          | —          | —            | **1**  | 0    | 0         | 0          | —       |
| LOAD    | `000_0011`  | I   | rs1        | imm        | ADD          | 0      | 0    | 0         | 1          | **MEM** |
| STORE   | `010_0011`  | S   | rs1        | imm        | ADD          | 0      | 0    | 0         | 0          | —       |
| OP-IMM  | `001_0011`  | I   | rs1        | imm        | f(funct3,f7) | 0      | 0    | 0         | 1          | ALU     |
| OP      | `011_0011`  | —   | rs1        | **rs2**    | f(funct3,f7) | 0      | 0    | 0         | 1          | ALU     |
| FENCE   | `000_1111`  | —   | —          | —          | —            | 0      | 0    | 0         | 0          | —       |
| SYSTEM  | `111_0011`  | I/Z | —          | —          | —            | 0      | 0    | 0         | \*         | **CSR** |

> `—` = don't-care (tín hiệu mặc định 0/ADD giữ nguyên, không ảnh hưởng đến kết quả)  
> `\*` SYSTEM: `reg_write = 1` chỉ khi funct3 ≠ 000 (tức là lệnh CSR, không phải ecall/ebreak/mret)

---

## Bảng 2 — Tín Hiệu Memory (LOAD / STORE)

| Lệnh  | funct3 | mem\_size  | mem\_ext      | Ghi chú              |
|-------|--------|-----------|---------------|----------------------|
| LB    | `000`  | `00` byte  | 1 (sign-ext)  | Load Byte signed     |
| LH    | `001`  | `01` half  | 1 (sign-ext)  | Load Halfword signed |
| LW    | `010`  | `10` word  | — (don't care)| Load Word            |
| LBU   | `100`  | `00` byte  | 0 (zero-ext)  | Load Byte unsigned   |
| LHU   | `101`  | `01` half  | 0 (zero-ext)  | Load Halfword unsigned|
| SB    | `000`  | `00` byte  | —             | Store Byte           |
| SH    | `001`  | `01` half  | —             | Store Halfword       |
| SW    | `010`  | `10` word  | —             | Store Word           |

> `mem_size = funct3[1:0]` (tức `instr[13:12]`)  
> `mem_ext  = ~funct3[2]`  (tức `~instr[14]`) — chỉ áp dụng cho LOAD

---

## Bảng 3 — Tín Hiệu CSR / Exception (SYSTEM opcode)

| funct3 | csr\_addr / imm12 | Lệnh    | csr\_we | csr\_op | csr\_imm\_sel | reg\_write | ecall | ebreak | mret |
|--------|-------------------|---------|---------|---------|--------------|------------|-------|--------|------|
| `000`  | `12'h000`         | ECALL   | 0       | —       | —            | 0          | **1** | 0      | 0    |
| `000`  | `12'h001`         | EBREAK  | 0       | —       | —            | 0          | 0     | **1**  | 0    |
| `000`  | `12'h302`         | MRET    | 0       | —       | —            | 0          | 0     | 0      | **1**|
| `001`  | csr\_addr         | CSRRW   | 1       | `01`    | 0 (rs1)      | 1          | 0     | 0      | 0    |
| `010`  | csr\_addr         | CSRRS   | \*      | `10`    | 0 (rs1)      | 1          | 0     | 0      | 0    |
| `011`  | csr\_addr         | CSRRC   | \*      | `11`    | 0 (rs1)      | 1          | 0     | 0      | 0    |
| `101`  | csr\_addr         | CSRRWI  | 1       | `01`    | **1 (zimm)** | 1          | 0     | 0      | 0    |
| `110`  | csr\_addr         | CSRRSI  | \*      | `10`    | **1 (zimm)** | 1          | 0     | 0      | 0    |
| `111`  | csr\_addr         | CSRRCI  | \*      | `11`    | **1 (zimm)** | 1          | 0     | 0      | 0    |

> `\*` CSRRS/CSRRC và dạng I: `csr_we = 0` nếu `rs1_addr == x0` (theo RISC-V spec §9.1 — không ghi CSR khi source = 0 để tránh side-effect)

---

## Bảng 4 — ALU Op Decode (OP-IMM và OP)

### OP-IMM (`opcode = 001_0011`, src_b = imm)

| funct3 | funct7      | Lệnh   | alu\_op |
|--------|-------------|--------|---------|
| `000`  | —           | ADDI   | ADD     |
| `010`  | —           | SLTI   | SLT     |
| `011`  | —           | SLTIU  | SLTU    |
| `100`  | —           | XORI   | XOR     |
| `110`  | —           | ORI    | OR      |
| `111`  | —           | ANDI   | AND     |
| `001`  | `000_0000`  | SLLI   | SLL     |
| `101`  | `000_0000`  | SRLI   | SRL     |
| `101`  | `010_0000`  | SRAI   | SRA     |

### OP (`opcode = 011_0011`, src_b = rs2)

| funct3 | funct7      | Lệnh | alu\_op |
|--------|-------------|------|---------|
| `000`  | `000_0000`  | ADD  | ADD     |
| `000`  | `010_0000`  | SUB  | SUB     |
| `001`  | `000_0000`  | SLL  | SLL     |
| `010`  | `000_0000`  | SLT  | SLT     |
| `011`  | `000_0000`  | SLTU | SLTU    |
| `100`  | `000_0000`  | XOR  | XOR     |
| `101`  | `000_0000`  | SRL  | SRL     |
| `101`  | `010_0000`  | SRA  | SRA     |
| `110`  | `000_0000`  | OR   | OR      |
| `111`  | `000_0000`  | AND  | AND     |

---

## Bảng 5 — Điều Kiện illegal\_instr

| Lệnh   | Điều kiện sinh illegal\_instr                         |
|--------|------------------------------------------------------|
| JALR   | `funct3 ≠ 000`                                       |
| BRANCH | `funct3 ∈ {010, 011}`                                |
| LOAD   | `funct3 ∈ {011, 110, 111}`                           |
| STORE  | `funct3 > 010`                                       |
| OP-IMM | SLLI/SRLI/SRAI với `funct7` không hợp lệ            |
| OP     | Tổ hợp `(funct3, funct7)` không thuộc RV32I          |
| SYSTEM | `funct3 == 000` nhưng `csr_addr ∉ {000, 001, 302}`  |
| default| opcode không khớp bất kỳ nhóm nào ở trên            |
