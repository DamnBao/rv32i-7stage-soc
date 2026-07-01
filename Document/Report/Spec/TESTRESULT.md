# TESTRESULT.md — Kết Quả Kiểm Thử RISC-V SoC

**Dự án:** CPU RV32I + Zicsr SoC với ngoại vi AXI-Lite và AHB-Lite  
**Ngày hoàn thành:** 2026-06-20  
**Simulator:** Icarus Verilog 12 (`iverilog -g2012 -Wall`)  
**Toolchain:** `riscv64-unknown-elf-gcc 13.2.0`

---

## Tổng Kết Nhanh

| Phase | Testbench | DUT | Test Count | Kết Quả |
|-------|-----------|-----|-----------|---------|
| **1** | 4 unit TBs | alu, branch_comp, register_file, id_decoder | 192 cases | **192/192 PASS** |
| **2** | 3 unit TBs | forwarding_unit, hazard_unit, async_fifo | 101 cases | **101/101 PASS** |
| **3** | tb_pipeline_cpu | soc_top (full CPU + mem) | 9 programs | **9/9 PASS** |
| **4a** | tb_axi_interface | axi_interface + slave model | 49 cases | **49/49 PASS** |
| **4b** | tb_ahb_interface | ahb_interface + CDC FIFOs + slave model | 29 cases | **29/29 PASS** |
| **4c** | tb_axi_full | axi_interface + axi_interconnect + 3×axi_sfr | 40 cases | **40/40 PASS** |
| **4d** | tb_ahb_full | ahb_interface + CDC + ahb_interconnect + 3×ahb_sfr | 35 cases | **35/35 PASS** |
| **5** | tb_pipeline_cpu | soc_top (full SoC + AXI/AHB) | 4 programs | **4/4 PASS** |
| **6a** | tb_soc_top | soc_top (batch 16 programs với reset) | 16 programs | **16/16 PASS** |
| **6b** | tb_compliance | soc_top (compliance framework) | 3 programs | **3/3 TEST_PASS** |
| **Tổng** | | | **446 cases + 32 programs** | **All PASS** |

---

## Bảng Tổng Kết Bugs Phát Hiện và Đã Sửa

| # | Bug | Phát hiện tại | Module sửa | Tác động nếu không sửa |
|---|-----|--------------|-----------|------------------------|
| B1 | Icarus không hỗ trợ named task args | Phase 2 (tb_forwarding) | Testbench only | Compile error |
| B2 | CDC FIFO: đọc `rd_data` sau khi advance pointer | Phase 2 (tb_async_fifo) | Testbench only | Đọc sai slot data |
| B3 | Gap-4 RAW hazard — WBR bypass thiếu | Phase 3 (prog_arithmetic) | `register_file.sv` | Dữ liệu sai khi WB và ID cùng cycle |
| B4 | IMEM synchronous + stall mismatch | Phase 3 (prog_forwarding) | `imem.sv` | Instruction bị mất/nhân đôi khi stall |
| B5 | CSR-use hazard stall quá muộn | Phase 3 (prog_csr) | `hazard_unit.sv` | CSR read nhận forwarding sai từ MEM1 |
| B6 | Ghost instruction từ IMEM sau zicsr_flush | Phase 3 (prog_ecall) | `imem.sv` | Illegal instruction spurious, infinite trap loop |
| B7 | Slave model AHB: mất track data_phase khi wait state | Phase 4b (tb_ahb_interface) | Testbench only | Test wait state cho kết quả sai |
| B8 | bus_stall + load_use đồng thời → LW bị cancel | Phase 5 (prog_axi_sfr) | `hazard_unit.sv` | LW không thực thi, bus read không diễn ra |

---

## Phase 1 — Unit Test: Combinational và Clocked Modules

**Mục tiêu:** Verify từng module leaf hoạt động đúng trước khi ghép pipeline.  
**Tổng kết:** **192/192 PASS**

---

### 1.1 tb_alu — 38/38 PASS

**DUT:** `RTL/alu.sv`  
**Loại:** Combinational  
**Interface:** `operand_a[31:0], operand_b[31:0], alu_op[3:0] → alu_result[31:0]`

**ALU Op encoding được test:**

| `alu_op` | Phép tính | Instruction sử dụng |
|----------|-----------|---------------------|
| `4'd0` | ADD | ADD, ADDI, LW/SW (addr calc), AUIPC, JAL |
| `4'd1` | SUB | SUB |
| `4'd2` | SLL | SLL, SLLI |
| `4'd3` | SLT | SLT, SLTI |
| `4'd4` | SLTU | SLTU, SLTIU |
| `4'd5` | XOR | XOR, XORI |
| `4'd6` | SRL | SRL, SRLI |
| `4'd7` | SRA | SRA, SRAI |
| `4'd8` | OR | OR, ORI |
| `4'd9` | AND | AND, ANDI |
| `4'd10` | PASSB | LUI (pass imm directly) |

**Test cases chi tiết theo nhóm:**

| Nhóm | # tests | Test cases tiêu biểu | Corner cases |
|------|---------|----------------------|--------------|
| ADD | 4 | 3+5=8, 100+(-1)=99 | Overflow wrap: `0xFFFF_FFFF + 1 = 0` |
| SUB | 3 | 5-3=2, 3-5=0xFFFF_FFFE | Underflow: `0 - 1 = 0xFFFF_FFFF` |
| SLL | 3 | 1<<4=16, 1<<0=1 | shamt[4:0]: `1 << 32 = 1 << 0 = 1` |
| SRL | 3 | 0x80000000>>1=0x40000000 | shamt[4:0]: `0xFFFF_FFFF >> 32 = same` |
| SRA | 4 | 8>>2=2 (positive) | `0x8000_0000 >>> 31 = 0xFFFF_FFFF` (sign extend) |
| SLT | 4 | 1<2=1, 2<1=0 | `0x8000_0000 < 1 = 1` (signed -2^31 < 1) |
| SLTU | 4 | 1<2=1 (unsigned) | `0x8000_0000 <u 1 = 0` (unsigned 2^31 > 1) |
| XOR | 3 | 0xF0F0^0x0F0F=0xFFFF, x^x=0 | |
| OR | 3 | 0xF0F0 OR 0x0F0F = 0xFFFF | |
| AND | 3 | 0xFFFF AND 0xF0F0 = 0xF0F0 | |
| PASSB | 2 | output = operand_b (LUI bypass) | operand_a ignored |
| Encoding | 2 | Default (unknown op) → 0 | |

---

### 1.2 tb_branch_comp — 25/25 PASS

**DUT:** `RTL/branch_comp.sv`  
**Loại:** Combinational  
**Interface:** `rs1_data[31:0], rs2_data[31:0], funct3[2:0], branch → branch_taken`

**funct3 mapping:**

| `funct3` | Instruction | Điều kiện taken |
|----------|-------------|-----------------|
| `3'b000` | BEQ | rs1 == rs2 |
| `3'b001` | BNE | rs1 != rs2 |
| `3'b100` | BLT | rs1 < rs2 (signed) |
| `3'b101` | BGE | rs1 >= rs2 (signed) |
| `3'b110` | BLTU | rs1 < rs2 (unsigned) |
| `3'b111` | BGEU | rs1 >= rs2 (unsigned) |

**Test cases chi tiết:**

| Test | `rs1` | `rs2` | `funct3` | `branch` | Expected `taken` | Ý nghĩa |
|------|-------|-------|----------|----------|-----------------|---------|
| BEQ equal | 5 | 5 | 000 | 1 | 1 | rs1==rs2 |
| BEQ not equal | 5 | 6 | 000 | 1 | 0 | |
| BEQ but branch=0 | 5 | 5 | 000 | **0** | **0** | Gate: branch=0 không taken dù condition true |
| BNE not equal | 5 | 6 | 001 | 1 | 1 | |
| BNE equal | 5 | 5 | 001 | 1 | 0 | |
| BLT positive | 3 | 7 | 100 | 1 | 1 | 3 < 7 signed |
| BLT negative<positive | 0x8000_0000 | 1 | 100 | 1 | 1 | -2^31 < 1 signed |
| BLT positive<negative | 1 | 0xFFFF_FFFF | 100 | 1 | 0 | 1 > -1 signed |
| BGE equal | 5 | 5 | 101 | 1 | 1 | |
| BGE greater | 7 | 3 | 101 | 1 | 1 | |
| BGE less | 3 | 7 | 101 | 1 | 0 | |
| BLTU large<small | 0x8000_0000 | 1 | 110 | 1 | 0 | 2^31 >u 1 (unsigned!) |
| BLTU small<large | 1 | 0x8000_0000 | 110 | 1 | 1 | 1 <u 2^31 |
| BGEU large>=small | 0x8000_0000 | 1 | 111 | 1 | 1 | |
| BGEU equal | 0 | 0 | 111 | 1 | 1 | |
| ... | | | | | | (10 more) |

**Key insight:** BLT và BLTU với 0x8000_0000 là test quan trọng nhất — đây là giá trị mà signed và unsigned interpretation cho kết quả ngược nhau. Nhiều implementation sai ở đây.

---

### 1.3 tb_register_file — 17/17 PASS

**DUT:** `RTL/register_file.sv`  
**Loại:** Synchronous write (posedge clk), combinational read  
**Clock testbench:** 100MHz (10ns)  
**Interface:**
```
rs1_addr[4:0] → rs1_data[31:0]   (combinational, với WBR bypass)
rs2_addr[4:0] → rs2_data[31:0]   (combinational, với WBR bypass)
rd_addr[4:0], rd_data[31:0], we  (synchronous write)
```

**Test cases:**

| # | Điều kiện | Input | Expected output | Mục đích |
|---|-----------|-------|-----------------|---------|
| 1 | After reset | — | x0..x31 = 0 | Reset initializes all to 0 |
| 2 | Write x1 | rd=1, data=0xDEAD_BEEF, we=1 | rs1(1)=0xDEAD_BEEF | Basic write |
| 3 | Write x31 | rd=31, data=0xABCD_1234, we=1 | rs1(31)=0xABCD_1234 | High register |
| 4 | Write x15 | rd=15, data=0x1234_5678, we=1 | rs1(15)=0x1234_5678 | Mid register |
| 5 | Dual-port read | rs1=1, rs2=15 | rs1=DEAD_BEEF, rs2=12345678 | Simultaneous read |
| 6 | x0 hardwired | rd=0, data=0xFFFF_FFFF, we=1 | rs1(0)=0 | x0 không ghi được |
| 7 | we=0 | rd=5, data=0x12345, we=0 | rs1(5)=0 (unchanged) | Write disabled |
| 8 | Independent regs | x5=100, x6=200, x7=300 | Mỗi reg giữ nguyên giá trị riêng | No aliasing |
| 9 | WBR bypass — rs1 | rd=10, data=0xCAFE; rs1_addr=10 đồng thời | rs1=0xCAFE ngay (bypass) | Gap-4 RAW: WB và ID cùng cycle |
| 10 | WBR bypass — rs2 | rd=10, data=0xBEEF; rs2_addr=10 đồng thời | rs2=0xBEEF ngay | Gap-4 RAW rs2 |
| 11 | WBR bypass x0 exempt | rd=0, data=0xFFFF, we=1; rs1_addr=0 | rs1=0 (bypass không áp dụng x0) | x0 bypass exception |
| 12–17 | Mid-test reset | rst_n=0 giữa chừng | tất cả = 0 | Reset async |

**Bug B3 phát hiện và sửa tại đây:** Test #9 và #10 (WBR bypass). Trước khi fix, `rs1_data` = old value (từ `registers[rd]` chưa update do NB assignment) thay vì `rd_data`. Fix: thêm combinational bypass:
```sv
assign rs1_data = (we && rd_addr == rs1_addr && rs1_addr != 0) ? rd_data : registers[rs1_addr];
```

---

### 1.4 tb_id_decoder — 112/112 PASS

**DUT:** `RTL/id_decoder.sv`  
**Loại:** Combinational  
**Interface:** `instr[31:0] → 20+ output signals`

**Coverage theo nhóm lệnh:**

| Nhóm | # tests | Lệnh được test |
|------|---------|----------------|
| LUI/AUIPC | 4 | LUI, AUIPC — kiểm tra imm_u extraction |
| JAL/JALR | 4 | JAL (imm_j), JALR (imm_i, jump_reg=1) |
| Branch | 14 | BEQ, BNE, BLT, BGE, BLTU, BGEU — mỗi loại 2+ cases |
| Load | 15 | LW, LH, LHU, LB, LBU — kiểm tra mem_size, mem_ext |
| Store | 9 | SW, SH, SB — kiểm tra imm_s, mem_write |
| I-type ALU | 22 | ADDI, ANDI, ORI, XORI, SLLI, SRLI, SRAI, SLTI, SLTIU |
| R-type | 14 | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| CSR | 18 | CSRRW, CSRRS, CSRRC, CSRRWI, CSRRSI, CSRRCI |
| System | 8 | ECALL, EBREAK, MRET |
| Illegal | 4 | Opcode không hợp lệ → `illegal_instr=1` |

**Chi tiết test cases đáng chú ý:**

| Instruction | Encoding hex | Output được kiểm tra |
|-------------|-------------|----------------------|
| `LUI x1, 0x12345` | `32'h1234_50B7` | rd=1, imm=0x12345000, wb_sel=00 (ALU=PASSB), alu_src_b=1 |
| `AUIPC x2, 0xABCDE` | `32'hABCDE117` | rd=2, imm=0xABCDE000, alu_src_a=1 (PC) |
| `JAL x1, +4` | `32'h0040_00EF` | rd=1, imm=4, jump=1, wb_sel=10 (PC+4) |
| `JALR x1, x2, 4` | `32'h0041_00E7` | rd=1, rs1=2, imm=4, jump=1, jump_reg=1 |
| `BEQ x1, x2, +8` | `32'h0020_8463` | rs1=1, rs2=2, imm=8, branch=1, reg_write=0 |
| `LW x5, 8(x2)` | `32'h0081_2283` | rd=5, rs1=2, imm=8, mem_read=1, mem_size=10 (word), mem_ext=1 |
| `LHU x5, 0(x1)` | — | mem_size=01, **mem_ext=0** (zero-extend) |
| `LH x5, 0(x1)` | — | mem_size=01, **mem_ext=1** (sign-extend) |
| `SW x3, 12(x1)` | `32'h0030_A623` | rs1=1, rs2=3, imm=12, mem_write=1 |
| `ADDI x3, x1, 42` | `32'h02A0_8193` | rd=3, rs1=1, imm=42, alu_src_b=1 (imm) |
| `SUB x5, x1, x2` | `32'h4020_82B3` | funct7=0x20 → alu_op=SUB |
| `SRAI x1, x2, 3` | — | alu_op=7 (SRA), alu_src_b=1 (imm), imm=3 |
| `CSRRW x1, mstatus, x2` | `32'h3001_10F3` | csr_addr=0x300, csr_we=1, csr_op=01, csr_imm_sel=0 |
| `CSRRS x1, mie, x0` | — | **csr_we=0** (rs1=x0 không modify CSR — spec requirement) |
| `CSRRWI x1, mstatus, 8` | — | csr_imm_sel=1, imm=zimm (instr[19:15]=8) |
| `ECALL` | `32'h0000_0073` | ecall=1, reg_write=0 |
| `EBREAK` | `32'h0010_0073` | ebreak=1, reg_write=0 |
| `MRET` | `32'h3020_0073` | mret=1, reg_write=0 |
| `0xDEAD_BEEF` | (invalid) | illegal_instr=1, tất cả control=0 |

**Note quan trọng:** CSRRS/CSRRC với `rs1=x0`: theo RISC-V spec, khi rs1=x0, CSR **không được modify** (chỉ đọc). `csr_we` phải =0. Đây là edge case thường bị bỏ qua.

---

## Phase 2 — Unit Test: Control Units và CDC FIFO

**Tổng kết:** **101/101 PASS**

---

### 2.1 tb_forwarding_unit — 19/19 PASS

**DUT:** `RTL/forwarding_unit.sv`  
**Loại:** Combinational (pure priority chain)  
**Interface:**
```
ex_rs1_addr[4:0], ex_rs2_addr[4:0]        ← lệnh đang ở EX cần đọc
mem1_rd_addr[4:0], mem1_reg_write          ← lệnh ở MEM1 có ghi không
mem2_rd_addr[4:0], mem2_reg_write          ← lệnh ở MEM2 có ghi không
wb_rd_addr[4:0],   wb_reg_write            ← lệnh ở WB có ghi không
→ fwd_sel_a[1:0], fwd_sel_b[1:0]
```

**Forward selector:**

| Giá trị | Nguồn dữ liệu | Khi nào |
|---------|---------------|---------|
| `2'b00` | NO_FWD — Register file | Không hazard, hoặc x0 |
| `2'b01` | FWD_MEM1 | Gap-1: lệnh kề trước đang ở MEM1 |
| `2'b10` | FWD_MEM2 | Gap-2: lệnh cách 2 đang ở MEM2 |
| `2'b11` | FWD_WB | Gap-3: lệnh cách 3 đang ở WB |

**Test cases chi tiết:**

| # | rs addr | MEM1 rd/we | MEM2 rd/we | WB rd/we | Expected fwd_sel_a | Lý do |
|---|---------|-----------|-----------|---------|-------------------|-------|
| 1 | rs1=0 | — | — | — | NO_FWD | x0 không forward |
| 2 | rs1=5 | rd=5, we=1 | — | — | FWD_MEM1 | Match MEM1 |
| 3 | rs1=5 | rd=5, **we=0** | rd=5, we=1 | — | FWD_MEM2 | MEM1 suppress (we=0), fallthrough |
| 4 | rs1=5 | — | rd=5, we=1 | — | FWD_MEM2 | Match MEM2 |
| 5 | rs1=5 | — | rd=5, **we=0** | rd=5, we=1 | FWD_WB | MEM2 suppress, fallthrough |
| 6 | rs1=5 | — | — | rd=5, we=1 | FWD_WB | Match WB |
| 7 | rs1=5 | rd=**3** | rd=**4** | rd=**6** | NO_FWD | Không match |
| 8 | rs1=5 | rd=5, we=1 | rd=5, we=1 | rd=5, we=1 | **FWD_MEM1** | Priority: MEM1 wins |
| 9 | rs1=5 | rd=**3**, we=1 | rd=5, we=1 | rd=5, we=1 | **FWD_MEM2** | MEM1 miss → MEM2 wins |
| 10 | rs2=7 | rd=7, we=1 | — | — | fwd_sel_b=FWD_MEM1 | B channel independent |
| 11 | rs1=5, rs2=7 | rd=5, we=1 | rd=7, we=1 | — | fwd_a=01, fwd_b=10 | Hai kênh đồng thời |
| 12–19 | ... | | | | | Additional combinations |

**Bug trong testbench (B1):** Icarus Verilog 12 không hỗ trợ named task arguments:
```sv
// SAI — Icarus compile error:
check_forward(.rs_addr(5), .mem1_rd(5), .mem1_we(1), .expected(FWD_MEM1));

// ĐÚNG — positional args:
check_forward(5, 5, 1, 0, 0, 0, 0, 0, FWD_MEM1, FWD_NONE);
```
Đây là hạn chế của Icarus 12, không phải lỗi RTL.

---

### 2.2 tb_hazard_unit — 60/60 PASS

**DUT:** `RTL/hazard_unit.sv`  
**Loại:** Combinational (tất cả `assign` statements)  
**Interface:** Xem SPEC.md mục 6.2

**Test cases theo loại hazard:**

#### Nhóm 1: Baseline (10 tests)

| # | Điều kiện | Expected outputs |
|---|-----------|-----------------|
| 1 | Tất cả input = 0 | Tất cả stall=0, flush=0 |
| 2 | bus_stall=1, rest=0 | stall_pc=1, stall_if1if2=1...stall_mem1mem2=1; flush=0 |
| 3 | zicsr_flush=1 | flush_if1if2=1...flush_mem2wb=1; stall=0 |
| 4 | branch_taken=1 | flush_if1if2=1, flush_if2id=1, flush_idex=1; stall=0 |
| 5 | jump=1 | Giống branch_taken |
| 6 | branch+jump đồng thời | flush IF/IF2/ID giống branch |
| ... | | |

#### Nhóm 2: Load-Use Hazard (15 tests)

| # | Điều kiện | Expected |
|---|-----------|---------|
| 10 | ex_mem_read=1, ex_rd=5, id_rs1=5 | stall_pc=1, stall_if1if2=1, stall_if2id=1; flush_idex=1 (bubble EX) |
| 11 | ex_mem_read=1, ex_rd=5, id_rs2=5 | Giống — rs2 hazard |
| 12 | ex_mem_read=1, ex_rd=5, id_rs1≠5, id_rs2≠5 | Không stall |
| 13 | ex_mem_read=1, **ex_rd=0** | Không stall (x0 không hazard) |
| 14 | **ex_mem_read=0**, ex_rd=5, id_rs1=5 | Không stall (chỉ load gây load-use) |
| 15–24 | RS1/RS2 combinations | Theo logic OR |

#### Nhóm 3: CSR-Use Hazard (15 tests)

| # | Điều kiện | Expected stall |
|---|-----------|---------------|
| 25 | ex_wb_sel=11, ex_reg_write=1, ex_rd=5, id_rs1=5 | stall_pc,if1if2,if2id (3-cycle stall) |
| 26 | mem1_wb_sel=11, mem1_reg_write=1, mem1_rd=5, id_rs1=5 | stall (2-cycle) |
| 27 | mem2_wb_sel=11, mem2_reg_write=1, mem2_rd=5, id_rs1=5 | stall (1-cycle) |
| 28 | ex_wb_sel=11, reg_write=0 | Không stall |
| 29 | ex_wb_sel≠11 (00/01/10), reg_write=1 | Không CSR stall |
| ... | | |

#### Nhóm 4: Combination Tests (20 tests)

| # | Điều kiện | Expected |
|---|-----------|---------|
| 40 | load_use + branch_taken đồng thời | stall IF/ID + flush IF/IF2/ID |
| 41 | bus_stall + load_use | stall_all; **flush_idex=0** (bus_stall suppresses!) |
| 42 | zicsr_flush + branch_taken | flush_all (zicsr wins) |
| 43 | zicsr_flush + bus_stall | flush_all (zicsr có ưu tiên) |
| 44–60 | Additional edge cases | |

**Note về test #41** (Bug B8 context): Khi cả `bus_stall` và `load_use` active, `flush_id_ex` phải = 0. Sau fix, hazard_unit đúng: `flush_id_ex = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush`.

---

### 2.3 tb_async_fifo — 22/22 PASS

**DUT:** `RTL/async_fifo_depth2` (depth=2, Gray-code pointer)  
**Loại:** Dual-clock CDC FIFO  
**Clock testbench:** `wr_clk=10ns` (100MHz), `rd_clk=20ns + 7ns offset` (stress CDC)

**Lý do chọn 7ns phase offset:** Tạo ra quan hệ bất đồng bộ không giống bất kỳ multiple nào của cả hai clock, đảm bảo test CDC thực sự (không phải "lucky" timing).

**Cơ chế bên trong FIFO (quan trọng để hiểu test):**
- `rd_data` là **combinational** — hiển thị ngay head slot khi có data, không cần đợi rd_en
- `rd_ptr` advance tại `posedge rd_clk` khi `rd_en=1 && !rd_empty`
- `wr_ptr_gray` cần **tối thiểu 2 posedge rd_clk** để đồng bộ sang rd domain

**Pattern đọc đúng:**
```
Timing:
                              ┌─ check rd_data (combinational) TRƯỚC khi advance
@(negedge rd_clk); check(rd_data, expected);
rd_en = 1;
@(posedge rd_clk);   ← ptr advances HERE
@(negedge rd_clk); rd_en = 0;
```

**Test cases:**

| # | Mô tả | Input sequence | Expected | Ghi chú |
|---|-------|----------------|---------|---------|
| 1 | After reset | — | rd_empty=1 | |
| 2 | Write 0xAB | wr_en=1, wr_data=0xAB | — | |
| 3 | Wait CDC settle | repeat(4) @posedge rd_clk | rd_empty=0 | ≥2 cycles needed |
| 4 | Read check | rd_data | 0xAB | Đọc trước advance |
| 5 | Advance + empty | rd_en=1, @posedge | rd_empty=1 | |
| 6 | Write 2 slots | wr 0xCA, wr 0xFE | rd_empty=0 after sync | |
| 7 | Read 0xCA | rd_data check | 0xCA | FIFO order preserved |
| 8 | Read 0xFE | rd_data check | 0xFE | |
| 9 | rd_en when empty | rd_en=1 but empty | ptr không advance | |
| 10 | After empty rd_en | Write 0x11, sync | rd_data=0x11 | Ptr đúng sau spurious rd_en |
| 11 | Reset mid-operation | rst both, rd_empty | rd_empty=1 | |
| 12–22 | Interleaved write/read | Multiple transactions B1,B2,B3 | In-order | |

**Bug B2 trong testbench (ban đầu 6/17 FAIL):** Testbench đọc `rd_data` SAU `@(posedge rd_clk)` khi `rd_en=1`, lúc đó `rd_ptr` đã advance sang slot tiếp theo → đọc sai. Fix: đọc `rd_data` trên `negedge` TRƯỚC khi set `rd_en`:
```sv
// SAI:
rd_en = 1; @(posedge rd_clk); check(rd_data, 0xAB);  // rd_data = slot 1, không phải slot 0!

// ĐÚNG:
@(negedge rd_clk); check(rd_data, 0xAB);  // combinational: slot 0 hiện đang ở đầu
rd_en = 1; @(posedge rd_clk); rd_en = 0;  // advance sang slot 1
```

---

## Phase 3 — Integration Test: Full CPU Pipeline

**Testbench:** `SIM/integration/tb_pipeline_cpu.sv`  
**DUT:** `RTL/soc_top.sv` (full 7-stage pipeline + IMEM 64KB + DMEM 64KB)  
**Clock:** CPU=1GHz, AHB=500MHz (phase offset 0.3ns)  
**Halt mechanism:** `addi x31, x0, 1; ebreak` (PASS) | `addi x31, x0, 0; ebreak` (FAIL)  
**Timeout:** 200,000 ns  
**Tổng kết:** **9/9 PASS**

---

### 3.1 prog_arithmetic — PASS (94.5ns)

**Mục tiêu:** Verify tất cả lệnh arithmetic và logic, cùng gap-4 RAW hazard.

**Các lệnh/tình huống được test:**

| Lệnh | Test case | Điều kiện verify |
|------|-----------|-----------------|
| `ADDI` | x1=0+5=5, x2=5+(-3)=2 | Immediate sign-extend âm |
| `ADD` | x3=x1+x2=7 | Register-register |
| `SUB` | x4=x1-x2=3 | |
| `LUI` | x5=0x12345<<12 | Upper immediate |
| `AUIPC` | x6=PC+0x1000 | PC-relative |
| `AND` | x7=0xFF00 AND 0x0FF0=0x0F00 | |
| `OR` | x8=0xFF00 OR 0x0FF0=0xFFF0 | |
| `XOR` | x9=0xFF00 XOR 0xFF00=0 | x XOR x = 0 |
| `SLL` | x10=1<<4=16 | |
| `SRL` | x11=0x80000000>>1=0x40000000 | Zero-extend |
| `SRA` | x12=0x80000000>>>1=0xC0000000 | Sign-extend |
| `SLT` | x13=(-1<0)=1 | Signed |
| `SLTU` | x14=(0<0xFFFFFFFF)=1 | Unsigned |
| **Gap-4 RAW** | `ADD x3,x1,x2` → [3 lệnh không dùng x3] → `ADD x5,x3,x0` | x3 phải đúng ở gap-4 |

**Bug B3 phát hiện:** `prog_arithmetic` FAIL tại t=27.5ns vì gap-4 RAW: `ADD` ghi x3 ở WB, đồng thời cycle sau `ADD x5,x3,x0` ở ID đọc x3 — non-blocking assignment khiến register file cũ. Fix: WBR bypass trong `register_file.sv`.

---

### 3.2 prog_forwarding — PASS (52.5ns)

**Mục tiêu:** Stress test MEM1/MEM2/WB forwarding và load-use 1-cycle stall.

| Tình huống | Dãy lệnh | Hazard | Mechanism |
|-----------|----------|--------|-----------|
| Gap-1 (MEM1 fwd) | `ADD x1,x2,x3` → `ADD x4,x1,x0` | x1 ở MEM1 khi x4 cần | MEM1→EX bypass |
| Gap-2 (MEM2 fwd) | `ADD x1,...` → NOP → `ADD x4,x1,x0` | x1 ở MEM2 | MEM2→EX bypass |
| Gap-3 (WB fwd) | `ADD x1,...` → NOP → NOP → `ADD x4,x1,x0` | x1 ở WB | WB→EX bypass |
| Gap-4 (WBR) | `ADD x1,...` → [3 NOPs] → `ADD x4,x1,x0` | x1 đã ghi RF | RF WBR bypass |
| Load-use | `LW x5, 0(a0)` → `ADD x6,x5,x0` | x5 từ DMEM chưa có | 1-cycle stall + MEM2 fwd |
| LW + gap-1 | `LW x5,...` → NOP → `ADD x6,x5,x0` | gap-2 từ load | MEM2 forwarding đủ (no stall) |

**Bug B4 phát hiện:** `prog_forwarding` FAIL — sau load-use stall, IMEM output không đồng bộ với PC (IMEM đọc PC+4 trong stall cycle, sau đó IF2 nhận wrong instruction). Fix: thêm `stall` input vào `imem.sv`.

---

### 3.3 prog_load_store — PASS (78.5ns)

**Mục tiêu:** Verify Load/Store với DMEM, bao gồm byte/half/word sizes và sign/zero extension.

| Lệnh | Địa chỉ | Data ghi | Expected khi đọc lại |
|------|---------|---------|----------------------|
| `SW` 0xABCD1234 → DMEM[0] | 0x10000 | 0xABCD_1234 | LW=0xABCD_1234 |
| `SH` 0xBEEF → DMEM[4]+0 | 0x10004 | 0xBEEF | LH=sign_ext(0xBEEF)=0xFFFF_BEEF |
| `SH` 0xBEEF → DMEM[4]+2 | 0x10006 | 0xBEEF | LHU=0x0000_BEEF (upper half đọc) |
| `SB` 0xAB → DMEM[8]+0 | 0x10008 | 0xAB | LB=sign_ext(0xAB)=0xFFFF_FFAB |
| `SB` 0xAB → DMEM[8]+1 | 0x10009 | 0xAB | LBU=0x0000_00AB |
| Forwarding qua load | SW then LW same addr | — | LW kết quả đúng dù gap-1 stall |

**Verify sign vs zero extend:**
- `LB 0xAB` → 0xFFFF_FFAB (bit 7 = 1 → sign-extend với 1s)
- `LBU 0xAB` → 0x0000_00AB (zero-extend)
- `LH 0xBEEF` → 0xFFFF_BEEF (bit 15 = 1 → sign-extend)
- `LHU 0xBEEF` → 0x0000_BEEF (zero-extend)

---

### 3.4 prog_branch_jump — PASS (79.5ns)

**Mục tiêu:** Verify tất cả branch conditions và jump instructions, bao gồm branch penalty (2-cycle flush).

| Lệnh | Điều kiện test | Expect |
|------|---------------|--------|
| `BEQ` | rs1==rs2 | Jump (flush 2 slots) |
| `BEQ` | rs1≠rs2 | Fall-through |
| `BNE` | rs1≠rs2 | Jump |
| `BLT` | rs1<rs2 signed | Jump |
| `BGE` | rs1>=rs2 signed | Jump |
| `BLTU` | rs1<rs2 unsigned | Jump |
| `BGEU` | rs1>=rs2 unsigned | Jump |
| `JAL x1, label` | — | PC←label, x1=PC+4 |
| `JALR x1, x2, 4` | — | PC←(x2+4)&~1, x1=PC+4 |
| Nested branches | Branch → branch target → branch | PC tracking qua nhiều jumps |

**2-cycle branch penalty verify:** Sau `BEQ` taken, 2 instructions đã vào IF1/IF2 bị flush (NOP bubble). Nếu flush không đúng, sai instruction sẽ chạy tiếp và corrupt x31.

---

### 3.5 prog_csr — PASS (103.5ns)

**Mục tiêu:** Verify đọc/ghi CSR và CSR-use hazard (3-cycle stall).

| CSR | Lệnh test | Verify |
|-----|-----------|--------|
| `mstatus` | CSRRW ghi, CSRRS đọc | Bit MIE (bit 3) |
| `mie` | CSRRS set MSIE bit | mie[3]=1 |
| `mtvec` | CSRRW ghi address | Lưu đúng |
| `CSRRWI` | immediate operand | rd=old CSR, CSR=zimm |
| CSR-use stall | `CSRRW x3, mie, x2` → `BNE x3, x0, fail` | x3 = old mie (trước khi ghi) |

**Tình huống CSR-use stall (3 cycles):**
```
Cycle N:   CSRRW @ EX
Cycle N+1: CSRRW @ MEM1 (stall BNE ở ID — cycle 1)
Cycle N+2: CSRRW @ MEM2 (stall BNE ở ID — cycle 2)
Cycle N+3: CSRRW @ WB → zicsr trả csr_rdata (BNE vào EX nhận WB forwarding đúng)
```

**Bug B5 phát hiện:** `prog_csr` FAIL — `BNE x3, x0, fail` nhảy vào fail dù x3 đúng. Root cause: stall ban đầu chỉ kiểm tra CSR tại MEM1/MEM2, không phải EX → lệnh kế đã vào EX và nhận `mem1_alu_result` (không phải CSR data) qua MEM1 forwarding sai. Fix: thêm `csr_stall_ex` (kiểm tra khi CSR đang ở EX).

---

### 3.6 prog_ecall — PASS (74.5ns)

**Mục tiêu:** Verify ECALL trap, zicsr state machine, MRET.

**Trình tự thực thi:**
```
1. Setup: mtvec ← handler_addr (vectored, mode=01)
           mie ← 0 (no interrupt)
2. ECALL:  mcause ← 0x0000_000B (M-mode ECALL)
           mepc   ← PC of ECALL
           mstatus.MPIE ← MIE; MIE ← 0
           PC ← mtvec_base + 4×11 = handler
3. Handler: verify mcause==0x0000_000B
            verify mepc==PC_of_ECALL
            MRET
4. MRET:   PC ← mepc (= PC_of_ECALL)
           mstatus.MIE ← MPIE
5. Resume: lệnh sau ECALL tiếp tục
```

**Bug B6 phát hiện — Ghost Instruction từ IMEM:**

Root cause chi tiết: Tại cycle C khi MRET ở WB và `zicsr_flush=1`:
- IMEM (synchronous) latch `mem[PC_cũ]` = 0x00000000 (past end of binary)
- `if1_if2_reg` bị flush → pc=0

Cycle C+1: `imem_instr = 0x00000000` vào `if2_id_reg` → `id_decoder` decode `0x00000000` là `illegal_instr=1` (opcode = 7'b0000000 không hợp lệ) → zicsr nhận illegal_instr ở WB ~7 cycle sau → spurious exception → mepc ghi đè 0 → handler loop vô hạn.

Fix: thêm `flush` input vào IMEM:
```sv
always_ff @(posedge clk) begin
    if (flush)       instr_out <= 32'h0000_0013;  // NOP (addi x0,x0,0) — opcode hợp lệ
    else if (!stall) instr_out <= mem[word_addr];
end
```
NOP (0x0000_0013) là lựa chọn đúng — đây là instruction hợp lệ, không trigger bất kỳ exception nào, ghi vào x0 (no-effect).

---

### 3.7 prog_interrupt_msi — PASS

**Mục tiêu:** Verify M-mode Software Interrupt (MSI) từ phần mềm.

**Trình tự:**
```
1. Setup mtvec (vectored), mie.MSIE=1, mstatus.MIE=1
2. Ghi mip.MSIP=1 bằng CSRRS (phần mềm tự tạo interrupt)
3. Interrupt pending detect: mcause=0x8000_0003
4. Handler: verify mcause, clear mip.MSIP bằng CSRRC
5. MRET → resume
6. Verify: x31=1 (PASS)
```

**Verify trong handler:**
- `mcause` == `0x8000_0003` (interrupt=1, code=3=MSI)
- `mstatus.MIE` == 0 (tắt global interrupt khi trong handler)
- `mstatus.MPIE` == 1 (lưu giá trị MIE cũ = 1)

---

### 3.8 prog_interrupt_mei — PASS

**Mục tiêu:** Verify M-mode External Interrupt (MEI) qua AXI IRQ line.

**Trình tự:**
```
1. Setup mtvec, mie.MEIE=1, mstatus.MIE=1
2. SW vào AXI SFR REG7 để set irq (địa chỉ 0x2000_001C)
3. CPU cần ~4-6 cycle AXI stall để hoàn thành SW
4. Sau đó: axi_irq=1 → zicsr detect → trap
5. mcause=0x8000_000B
6. Handler: clear IRQ (SW 0 vào REG7), MRET
```

**Điều kiện đặc biệt:** Interrupt detect chỉ khi `bus_stall_req=0` (không trap giữa AXI transaction).

---

### 3.9 prog_load_fault — PASS

**Mục tiêu:** Verify Load Access Fault exception khi đọc địa chỉ không decode được.

**Trình tự:**
```
1. Setup mtvec, handler
2. LW từ địa chỉ 0x4000_0000 (không trong memory map)
   → mem1_stage: load_fault=1 (không match DMEM/AXI/AHB)
   → Signal propagate MEM1→MEM2→WB
3. WB: wb_load_fault=1 → zicsr: mcause=0x0000_0005 (Load Access Fault)
4. mepc = PC of faulting LW
5. Handler verify mcause==5, verify mepc đúng
6. MRET → x31=1
```

---

## Phase 4 — Integration Test: Bus Interfaces

**Tổng kết:** **153/153 PASS**

---

### 4.1 Phase 4a: AXI-Lite Interface — 49/49 PASS

**Testbench:** `SIM/integration/tb_axi_interface.sv`  
**DUT:** `axi_interface.sv` + `models/axi_slave_model.sv`  
**Clock:** 1GHz (synchronous)

**Slave model behavior:**
- `AWREADY=WREADY=ARREADY=1` constant (immediate accept)
- Write: latch tại `posedge clk` khi `AWVALID && WVALID`; `BVALID=1` chu kỳ sau
- Read: latch ARADDR; `RVALID=1` + `RDATA=mem[addr]` chu kỳ sau
- Error inject: `inject_bresp_err=1` → `BRESP=2'b10` (SLVERR)

**Test cases chi tiết:**

| Group | Tests | Tình huống | Verify |
|-------|-------|-----------|--------|
| G1: Basic | T1–T2 | Word write 0xDEAD_BEEF | `axi_resp_valid=1`, `resp_err=0` |
| G1 | T3–T4 | Word read-back | `resp_rdata=0xDEAD_BEEF`, `resp_err=0` |
| G1 | T5–T8 | Second write+read 0xCAFE_F00D | Không clobber slot cũ |
| G1 | T9–T10 | Half-word write at offset 0 | `WSTRB=4'b0011` (bytes 0,1) |
| G1 | T11–T12 | Half-word write at offset 2 | `WSTRB=4'b1100` (bytes 2,3) |
| G1 | T13–T20 | Byte writes at offsets 0,1,2,3 | `WSTRB=0001/0010/0100/1000` |
| G1 | T21–T22 | BRESP error inject | `resp_err=1` |
| G1 | T23–T24 | RRESP error inject | `resp_err=1` |
| G2: Data | T25 | Word WDATA = full req_wdata | `WDATA=req_wdata` (no modification) |
| G2 | T26–T27 | Half-word WDATA replication | `WDATA={hw16, hw16}` (ARM convention) |
| G2 | T28–T29 | Byte WDATA replication | `WDATA={byte×4}` |
| G3: Addr | T30 | AWADDR propagation | `AWADDR == axi_req_addr` |
| G3 | T31 | ARADDR propagation | `ARADDR == axi_req_addr` |
| G4: Seq | T32–T33 | Sequential write then read | Independent transactions |

**AXI Timing verify:**
- Write: T0=AWVALID+WVALID; T1=AWREADY+WREADY (handshake); T2=BVALID; T3=BREADY+`resp_valid=1` → 3 cycles
- Read: T0=ARVALID; T1=ARREADY; T2=RVALID+RDATA; T3=RREADY+`resp_valid=1` → 3 cycles

---

### 4.2 Phase 4b: AHB-Lite Interface — 29/29 PASS

**Testbench:** `SIM/integration/tb_ahb_interface.sv`  
**DUT:** `async_fifo_depth2` (req, 67b) + `ahb_interface.sv` + `async_fifo_depth2` (resp, 33b) + `models/ahb_slave_model.sv`  
**Clock:** `clk_1g=10ns` (write side), `clk_ahb=20ns + 7ns offset` (AHB domain)

**FIFO payload format:**
- Request: `{addr[31:0], wdata[31:0], write[0], size[1:0]}` = 67 bits
- Response: `{HRESP[0], HRDATA[31:0]}` = 33 bits

**Latency từ write đến response:** ~12 cycle @1GHz:
- Request FIFO write: 1 cycle
- CDC 1GHz→500MHz: 2 clk_ahb = 4 clk_1g
- AHB transaction (ADDR+DATA): 2 clk_ahb = 4 clk_1g
- Response FIFO CDC 500MHz→1GHz: 2 clk_1g
- Response read: 1 cycle

**Test cases chi tiết:**

| Group | Tests | Tình huống | Verify |
|-------|-------|-----------|--------|
| G1: Basic | T1–T4 | Word write | `err=0`, `HSIZE=2`, `HWRITE=1`, `HWDATA` captured correctly |
| G1 | T5–T7 | Word read-back | `err=0`, `HRDATA=0xAABBCCDD`, `HWRITE=0` |
| G1 | T8–T9 | Half-word write | `HSIZE=1` |
| G1 | T10–T11 | Byte write | `HSIZE=0` |
| G1 | T12 | HRESP error | `resp_err=1` propagates through FIFO |
| G1 | T13–T15 | Write+read 0xDEAD_1234 | Round-trip data integrity |
| G2: Wait | T16–T18 | Wait state write (`HREADY=0` for 1 cycle) | `HWDATA` captured khi `HREADY=1`, `err=0` |
| G2 | T19–T20 | Read after wait-state write | Data integrity maintained |
| G2 | T21–T22 | Wait state read | `HRDATA` correct, `err=0` |
| G2 | T23 | HADDR propagation | `HADDR == req_addr` |
| G2 | T24 | Error + wait state | `err=1` still propagates correctly |
| G3: Seq | T25–T28 | 2 sequential writes + 2 reads | Independent transactions, no cross-contamination |
| G3 | T29 | `req_rd_en` idle | = 0 khi không có pending request |

**Bug B7 phát hiện:** Slave model cũ dùng `HTRANS[1]` để set `data_phase`. Khi `insert_wait=1` (HREADY=0), `HTRANS=IDLE` → `data_phase=0` ngay → slave mất track. Fix: 2-state FSM (IDLE/DATA), `data_phase` chỉ clear khi `HREADY=1` trong DATA state.

---

### 4.3 Phase 4c: AXI Full Path — 40/40 PASS

**Testbench:** `SIM/integration/tb_axi_full.sv`  
**DUT:** `axi_interface + axi_interconnect + 3×axi_sfr`  
**Clock:** 1GHz

**Slave addresses:**

| Slave | Địa chỉ | `addr[27:12]` |
|-------|---------|--------------|
| S0 | 0x2000_0000 | 0x0000 |
| S1 | 0x2000_1000 | 0x0001 |
| S2 | 0x2000_2000 | 0x0002 |

**Test cases chi tiết:**

| Group | Tests | Tình huống | Verify |
|-------|-------|-----------|--------|
| G1: Decode | T1–T3 | Write 0x1111_1111 to S0, S1, S2 | Mỗi slave nhận đúng data |
| G1 | T4–T6 | Read back S0, S1, S2 | Đúng 0x1111_1111 từ đúng slave |
| G1 | T7–T9 | Write 0xAAAA_5555, 0xBBBB_6666, 0xCCCC_7777 | Mỗi slave nhận giá trị riêng |
| G2: IRQ | T10–T12 | Set REG7[0]=1 trên S0, S1, S2 | `axi_irq` assert (OR của 3 irqs) |
| G2 | T13–T15 | Clear REG7[0]=0 trên từng slave | `axi_irq` deassert sau khi tất cả clear |
| G2 | T16–T18 | Partial clear (chỉ clear 1, 2 slave) | `axi_irq` vẫn=1 cho đến khi tất cả=0 |
| G2 | T19–T21 | IRQ via REG7 reads | read-back REG7[0]=1 và =0 |
| G3: Multi-reg | T22–T24 | 3 reg writes S0: REG0=A, REG3=B, REG6=C | Không aliasing trong slave |
| G3 | T25–T27 | Read back REG0, REG3, REG6 | A, B, C đúng |
| G3 | T28–T30 | REG7 (offset 0x1C) write+read | IRQ register đúng |
| G4: Isolation | T31–T33 | Write S1 REG0 = 0xDEAD; read S2 REG0 | S2 REG0 = 0 (unaffected) |
| G4 | T34–T36 | Write S2 REG5 = 0xBEEF; read S0 REG5 | S0 REG5 = 0 (unaffected) |
| G4 | T37–T40 | Cross-slave read-back matrix | Tất cả isolation confirmed |

---

### 4.4 Phase 4d: AHB Full Path — 35/35 PASS

**Testbench:** `SIM/integration/tb_ahb_full.sv`  
**DUT:** `ahb_interface + 2×async_fifo + ahb_interconnect + 3×ahb_sfr`  
**Clock:** 1GHz ↔ CDC ↔ 500MHz

**Test structure** tương tự 4c nhưng với latency AHB+CDC (~12 cycle/transaction):

| Group | Tests | Tình huống | Ghi chú |
|-------|-------|-----------|---------|
| G1: Decode | T1–T6 | Write+read 3 slaves | Wait for CDC settle after each transaction |
| G2: IRQ | T7–T9 | Set REG7[0]=1 | IRQ settle qua 500MHz domain cần 2 clk_ahb |
| G2 | T10–T12 | Clear IRQ | |
| G2 | T13–T15 | Partial IRQ clear | |
| G3: Multi-reg | T16–T22 | 2 writes + 2 reads S0 | |
| G4: Isolation | T23–T35 | Cross-slave isolation | |

**AHB IRQ timing note:** `ahb_sfr.irq` ở 500MHz domain cần 2 cycle clk_ahb để settle (combinational từ REG7[0]), rồi testbench phải wait CDC từ 500MHz→1GHz nếu quan sát irq từ 1GHz side.

---

## Phase 5 — Full SoC Integration: CPU + Bus

**Testbench:** `SIM/integration/tb_pipeline_cpu.sv` (reuse Phase 3 TB)  
**DUT:** `soc_top.sv` — toàn bộ SoC (CPU + AXI + AHB + CDC)  
**Tổng kết:** **4/4 PASS**

---

### Bug B8 — Simultaneous bus_stall + load_use → LW Cancel (Phase 5)

Đây là bug quan trọng nhất trong dự án, phát hiện ở Phase 5.

**Triệu chứng:** `prog_axi_sfr` và `prog_ahb_sfr` FAIL với `x31=0` tại `bne` đầu tiên sau `lw`.

**Đoạn code gây ra bug (trong prog_axi_sfr.s):**
```asm
    sw    t0, 0(a0)        # SW to AXI SFR (a0=0x2000_0000)
    # Pipeline state khi sw ở MEM1 (bus_stall=1):
    #   MEM1: sw (bus_stall_req=1)
    #   EX:   lw (chuẩn bị AXI read)
    #   ID:   bne t1, t2, fail  ← dùng kết quả lw
    lw    t1, 0(a0)        # LW from AXI SFR
    bne   t1, t2, fail
```

**Cycle-by-cycle trace của bug:**

| Cycle | IF1 | ID | EX | MEM1 | MEM2 | Stall/Flush signals |
|-------|-----|----|----|------|------|---------------------|
| N | bne | lw | sw | — | — | — |
| N+1 | ... | bne | **lw** | **sw(bus_stall)** | — | `stall_id_ex=1` (bus), `flush_id_ex=1` (load_use) |
| N+2 | ... | bne | **NOP** ← BUG | sw(bus_stall) | — | flush thắng, lw bị cancel! |

**Root cause:** Trong `id_ex_reg.sv`, branch `else if (flush)` được check TRƯỚC `else if (!stall)`. Khi cả `stall_id_ex=1` và `flush_id_ex=1`: flush thắng → ID/EX cleared → lw không bao giờ đến MEM1 → AXI AR handshake không xảy ra → `lw` không có data → `t1=0`.

**Fix trong `hazard_unit.sv`:**
```sv
// TRƯỚC (sai):
assign flush_id_ex = zicsr_flush | fetch_stall | ctrl_flush;

// SAU (đúng):
assign flush_id_ex = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush;
```

**Lý do `ctrl_flush` (branch) KHÔNG bị suppress:** Branch taken flush là đúng ngay cả khi bus_stall — wrong-path instructions cần bị cancel, không phụ thuộc vào bus state.

**Verify sau fix:**
- `make p3_all` → 9/9 PASS (không regression)
- `make p5_all` → 4/4 PASS

---

### 5.1 prog_axi_sfr — PASS (75.5ns)

**Trình tự test:**

```asm
# 1. Write 0xABCD1234 vào S0-REG0 (0x2000_0000)
    lui   a0, 0x20000
    lui   t0, 0xABCD1
    addi  t0, t0, 0x234
    sw    t0, 0(a0)        # AXI write stall ~4 cycle

# 2. Read-back và verify
    lw    t1, 0(a0)        # AXI read stall ~4 cycle
    bne   t1, t0, fail     # Verify read == write

# 3. Write tới S1 (0x2000_1000)
    addi  a1, a0, 0x1000
    sw    t0, 0(a1)

# 4. Verify S0 không bị ảnh hưởng bởi S1 write
    lw    t2, 0(a0)        # Read S0 lại
    bne   t2, t0, fail     # S0 vẫn = 0xABCD1234

# 5. Tương tự cho S2
    ...
```

**Điều kiện được verify:** Data integrity write→read, cross-slave isolation (write S1 không affect S0/S2), 3 slaves hoạt động độc lập.

---

### 5.2 prog_ahb_sfr — PASS (149.5ns)

Tương tự `prog_axi_sfr` nhưng với địa chỉ AHB (0x3000_0000+) và latency lớn hơn (~12 cycle/transaction do CDC). Thời gian 149.5ns dài hơn 75.5ns của AXI là do:
- Mỗi AHB transaction: ~12 cycle @1GHz vs ~4 cycle @1GHz của AXI
- Có 6 transactions (3 write + 3 read) → ~72 cycle AHB vs ~24 cycle AXI

---

### 5.3 prog_axi_irq — PASS (60.5ns)

**Trình tự:**
```asm
# Setup
    csrw  mtvec, handler_addr     # Vectored mode
    csrsi mie, 0x800              # MEIE=1
    csrsi mstatus, 0x8            # MIE=1

# Trigger IRQ
    lui   a0, 0x20000
    addi  t0, x0, 1
    sw    t0, 0x1C(a0)            # AXI REG7[0]=1 → axi_irq=1

# Handler (tại mtvec_base + 4*11):
handler_mei:
    csrr  t0, mcause
    addi  t1, x0, 0x8000000B     # Expected: MEI
    bne   t0, t1, fail
    # Clear IRQ
    sw    x0, 0x1c(a0)
    mret
```

**Verify trong handler:**
- `mcause == 0x8000_000B` (interrupt + MEI code 11)
- `mstatus.MIE == 0` (global interrupt disabled trong handler)
- IRQ clear hoạt động: `sw x0` → `axi_irq=0`
- MRET khôi phục đúng MIE

---

### 5.4 prog_ahb_irq — PASS (74.5ns)

Tương tự `prog_axi_irq` nhưng:
- Địa chỉ SFR: `0x3000_001C` (AHB S0 REG7)
- IRQ path: `ahb_sfr.irq → 2-FF sync (1GHz) → zicsr.ahb_irq_sync2`
- **Phải có ≥5 NOPs sau SW** để IRQ propagate qua CDC + 2-FF sync:

```asm
    sw    t0, 0x1c(a0)    # AHB write REG7[0]=1 (~12 cycle AHB stall)
    nop                   # Sau khi stall giải phóng: chờ CDC settle
    nop                   # clk_ahb domain: irq=1 (combinational từ REG7)
    nop                   # CDC 500MHz→1GHz: 2 clk_cpu cycles
    nop                   # 2-FF sync trong zicsr: 2 thêm clk_cpu
    nop                   # Safety margin
    # Interrupt arrives now
```

---

## Phase 6 — System Test và Compliance Framework

**Tổng kết:** **16/16 PASS (batch) + 3/3 TEST_PASS (compliance)**

---

### 6.1 Phase 6a: System Batch Test — 16/16 PASS

**Testbench:** `SIM/system/tb_soc_top.sv`  
**DUT:** `soc_top.sv`  
**Đặc điểm:** Full SoC reset + DMEM clear giữa mỗi program, 200,000 cycle timeout

**Output thực tế:**
```
=== System Test: 16 programs ===

PASS  [programs/prog_arithmetic.hex]
PASS  [programs/prog_forwarding.hex]
PASS  [programs/prog_load_store.hex]
PASS  [programs/prog_branch_jump.hex]
PASS  [programs/prog_csr.hex]
PASS  [programs/prog_ecall.hex]
PASS  [programs/prog_interrupt_msi.hex]
PASS  [programs/prog_interrupt_mei.hex]
PASS  [programs/prog_load_fault.hex]
PASS  [programs/prog_axi_sfr.hex]
PASS  [programs/prog_ahb_sfr.hex]
PASS  [programs/prog_axi_irq.hex]
PASS  [programs/prog_ahb_irq.hex]
PASS  [programs/prog_rv32i_shifts.hex]
PASS  [programs/prog_rv32i_compare.hex]
PASS  [programs/prog_dmem_endurance.hex]

=== SYSTEM TEST: 16/16 PASS ===
ALL PASS
```

**Ý nghĩa của Phase 6a:** Đây là test duy nhất chạy toàn bộ 16 programs với reset thực sự giữa mỗi run (thay vì chỉ reload IMEM). Điều này verify rằng:
1. SoC reset hoàn toàn sạch state giữa các programs
2. DMEM clear ngăn data residue từ program trước ảnh hưởng program sau
3. AXI/AHB peripheral cũng reset đúng (SFR về 0)
4. Pipeline không còn stale state sau reset

---

### 6.2 Phase 6b: Compliance Programs — 3/3 TEST_PASS

**Testbench:** `SIM/system/tb_compliance.sv`  
**Output format:** `TEST_PASS` / `TEST_FAIL` (machine-parseable cho scripts/run_one_test.sh)  
**Plusarg:** `+HEX=<path>`  
**Timeout:** 200,000ns

#### prog_rv32i_shifts — TEST_PASS

**Coverage:** Tất cả 6 shift instructions với edge cases

| Instruction | Test case | Expected |
|-------------|-----------|---------|
| `SLLI t1, t0, 0` | 1 << 0 | 1 (no shift) |
| `SLLI t1, t0, 4` | 1 << 4 | 16 |
| `SLLI t1, t0, 31` | 1 << 31 | 0x8000_0000 |
| `SRLI t1, t0, 1` | 0x80000000 >> 1 | 0x4000_0000 (zero-extend) |
| `SRLI t1, t0, 31` | 0x80000000 >> 31 | 1 |
| `SRLI t1, t0, 0` | unchanged | same |
| `SRAI t1, t0, 1` | 0x80000000 >>> 1 | 0xC000_0000 (sign-extend) |
| `SRAI t1, t0, 31` | 0x80000000 >>> 31 | 0xFFFF_FFFF |
| `SRAI t1, t0, 2` | 8 >>> 2 | 2 (positive, same as SRL) |
| `SLL t1, t0, t3` | 1 << 4 (reg) | 16 |
| `SLL t1, t0, t3` | 1 << 0 | 1 |
| `SLL t1, t0, t3` | t3=33: 1 << (33 mod 32=1) | 2 (amount masked to 5 bits) |
| `SRL t1, t0, t3` | 0x80000000 >> 4 | 0x0800_0000 |
| `SRL t1, t0, t3` | t3=31 | 1 |
| `SRA t1, t0, t3` | 0x80000000 >>> 4 | 0xF800_0000 |
| `SRA t1, t0, t3` | t3=31 | 0xFFFF_FFFF |
| `SRA t1, t0, t3` | 8 >>> 2 (positive) | 2 |

**Tại sao test `amount mod 32`:** RISC-V spec yêu cầu shift amount chỉ lấy lower 5 bits của rs2. Việc shift bằng rs2=33 phải cho kết quả giống shift bằng 1. Bug thường xảy ra ở implementation dùng full register width cho shamt.

#### prog_rv32i_compare — TEST_PASS

**Coverage:** SLT/SLTU/SLTI/SLTIU edge cases + AUIPC

| Instruction | Test case | Expected | Ý nghĩa |
|-------------|-----------|---------|---------|
| `SLT t2, t0, t1` | t0=0xFFFFFFFF(-1), t1=0 | 1 | Signed: -1 < 0 |
| `SLT t2, t1, t0` | t1=0, t0=-1 | 0 | Signed: 0 > -1 |
| `SLT t2, t0, t1` | t0=t1=5 | 0 | Equal: not less than |
| `SLTU t2, t0, t1` | t0=0xFFFFFFFF, t1=0 | 0 | Unsigned: max > 0 |
| `SLTU t2, t1, t0` | t1=0, t0=0xFFFFFFFF | 1 | Unsigned: 0 < max |
| `SLTI t1, t0, 10` | t0=5 | 1 | 5 < 10 |
| `SLTI t1, t0, -1` | t0=5 | 0 | 5 không < -1 signed |
| `SLTI t1, t0, 0` | t0=-1 | 1 | -1 < 0 |
| `SLTI t1, t0, -2` | t0=-1 | 0 | -1 không < -2 |
| `SLTIU t1, t0, 0` | t0=5 | 0 | 5 không < 0 unsigned |
| `SLTIU t1, t0, -1` | t0=100 | 1 | 100 < 0xFFFFFFFF unsigned |
| `AUIPC t0, 0` → `AUIPC t1, 0` | consecutive | t1 = t0 + 4 | PC-relative verify |
| `AUIPC t0, 1` → `AUIPC t1, 0` | imm=1 | t0 = t1 + 0x1000 - 4 | Offset 0x1000 |

**Key test — signed vs unsigned 0xFFFFFFFF:**
- SLT: `0xFFFFFFFF < 0` = 1 (signed: -1 < 0)
- SLTU: `0xFFFFFFFF < 0` = 0 (unsigned: 4294967295 > 0)
Đây là corner case thường bị implement sai: dùng signed comparator cho SLTU hoặc ngược lại.

#### prog_dmem_endurance — TEST_PASS

**Coverage:** Stress test 64 consecutive DMEM addresses (256 bytes)

**Pattern:** `pattern(i) = byte_i × 0x01010101`:
- i=0: 0x0000_0000
- i=1: 0x0101_0101
- i=63: 0x3F3F_3F3F

**Write phase:** Store 64 patterns vào `DMEM[0x10000]` đến `DMEM[0x100FC]`

**Read phase:** Load lại 64 values và compare với recomputed pattern

**Verify:** Tất cả 64 địa chỉ (từ DMEM base offset 0 đến offset 252) hoạt động đúng. Đảm bảo không có aliasing, không có address decode error trong DMEM 64KB.

**Hazard coverage trong loop:**
- `slli t3, t1, 2` (shift index) → `add t4, t0, t3` (addr calc): gap-1, MEM1 forwarding
- `sw t5, 0(t4)`: t4 từ `add` ở gap-1 → MEM1 forwarding cho address
- `lw t5, 0(t4)` → [5 instructions gap] → `bne t5, t6, fail`: gap-5, no hazard

---

## Phụ Lục — Signals Hữu Ích Khi Debug

### Signals Quan Trọng Trong soc_top

| Signal | Path | Ý nghĩa |
|--------|------|---------|
| `wb_ebreak` | `u_soc.wb_ebreak` | EBREAK đang ở WB — halt condition |
| `x31` | `u_soc.u_rf.registers[31]` | Pass/Fail register |
| PC hiện tại | `u_soc.if1_stage_pc` | Program Counter |
| Instruction ở ID | `u_soc.if2id_instr` | Lệnh đang được decode |
| `bus_stall_req` | `u_soc.bus_stall_req` | Bus stall active |
| `zicsr_flush` | `u_soc.zicsr_flush` | Trap/MRET flush |
| `mcause` | `u_soc.u_zicsr.mcause` | Nguyên nhân trap |
| `mepc` | `u_soc.u_zicsr.mepc` | PC khi trap |
| Forwarding sel | `u_soc.u_fwd.fwd_sel_a/b` | Forwarding mux selection |

### Commands Debug Nhanh

```bash
# Chạy một program với VCD dump:
make p3_wave_csr          # → integration/wave_csr.vcd

# Chạy compliance với debug info (TEST_FAIL sẽ in mepc/mcause):
vvp system/tb_compliance.vvp +HEX=programs/prog_csr.hex

# Rebuild RTL và chạy lại Phase 3:
rm integration/tb_pipeline_cpu.vvp && make p3_all

# Full regression:
make unit_all && make p3_all && make integ_axi integ_ahb integ_axi_full integ_ahb_full && make p5_all && make p6_all
```
