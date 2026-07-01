# Test Plan — RISC-V RV32I+Zicsr SoC

Phiên bản: 2026-06-19  
RTL: 30 module SystemVerilog, 0 lỗi iverilog  
Simulator: Icarus Verilog + `$dumpfile`/VCD (hoặc GTKWave)

---

## Danh Sách Bug Đã Sửa (Trước Khi Test)

| # | File | Loại | Bug | Fix |
|---|------|------|-----|-----|
| 1 | `hazard_unit.sv` | **Critical** | `flush_id_ex` thiếu `\| ctrl_flush` — branch/jump luôn thực thi 1 lệnh sai sau nó (delay slot không có trong RV32I) | Thêm `\| ctrl_flush` |
| 2 | `zicsr.sv` | **Critical** | CSR op encoding mismatch: CSRRW thực hiện OR, CSRRS thực hiện AND-NOT, CSRRC thực hiện direct write | Swap case 2'b01↔default, 2'b10↔2'b11 |
| 3 | `zicsr.sv` | **Major** | `mepc = wb_pc` cho interrupt — lệnh tại WB commit ở cùng rising edge nên mret sẽ re-execute | `mepc = wb_pc + 4` cho take_interrupt |
| 4 | `id_decoder.sv` | **Major** | CSRRS/CSRRC với rs1=x0 vẫn assert `csr_we=1` vi phạm RISC-V spec §9.1 | Gate `csr_we=0` khi rs1=x0 cho RS/RC |

---

## Ghi Chú Thiết Kế (Không Phải Bug)

- **Sub-word AXI/AHB access**: `mem2_stage` hỗ trợ byte/half extraction dựa trên `alu_result[1:0]`. Ngoại vi SFR trả về 32-bit word — chỉ hỗ trợ **word-aligned access** (LW/SW). LB/LH/SB/SH vào AXI/AHB region có behavior không được định nghĩa.
- **MEM1 forward cho load**: `fwd_data_mem1 = exmem1_alu_result` (là load address khi load ở MEM1). An toàn vì load-use stall ngăn consumer tiến vào EX khi load ở MEM1.
- **Exception commit**: Lệnh gây exception (load_fault, store_fault) vẫn write rd với giá trị rác trước khi exception được xử lý. RISC-V spec cho phép giá trị rd là unpredictable sau trap.

---

## Cấu Trúc Testbench

```
tb/
  tb_alu.sv
  tb_branch_comp.sv
  tb_id_decoder.sv
  tb_register_file.sv
  tb_forwarding_unit.sv
  tb_hazard_unit.sv
  tb_async_fifo.sv
  tb_pipeline_cpu.sv          ← integration: IF1..WB + control
  tb_axi_if.sv
  tb_ahb_if.sv
  tb_soc_top.sv               ← full-system smoke test
```

---

## NHÓM 1 — Unit Tests (Combinational/Simple Sequential)

### 1.1 ALU (`tb_alu.sv`)

**DUT:** `alu.sv`

| Test Case | operand_a | operand_b | alu_op | Expected result | Ghi chú |
|-----------|-----------|-----------|--------|-----------------|---------|
| ADD basic | 5 | 3 | ADD(0) | 8 | |
| ADD overflow | 0xFFFFFFFF | 1 | ADD | 0x00000000 | Wrap around |
| SUB | 10 | 3 | SUB(1) | 7 | |
| SUB borrow | 3 | 10 | SUB | 0xFFFFFFF9 | Negative |
| SLL | 1 | 4 | SLL(2) | 16 | Shift left 4 |
| SLL max | 1 | 31 | SLL | 0x80000000 | |
| SLT signed | -1 | 0 | SLT(3) | 1 | -1 < 0 |
| SLT false | 5 | 3 | SLT | 0 | |
| SLTU unsigned | 0xFFFFFFFF | 0 | SLTU(4) | 0 | unsigned > 0 |
| XOR | 0xA | 0x6 | XOR(5) | 0xC | |
| SRL | 0x80000000 | 4 | SRL(6) | 0x08000000 | Logical right |
| SRA | 0x80000000 | 4 | SRA(7) | 0xF8000000 | Arithmetic right |
| OR | 0x5 | 0xA | OR(8) | 0xF | |
| AND | 0xF | 0xA | AND(9) | 0xA | |
| PASSB (LUI) | X | 0xDEAD0000 | PASSB(10) | 0xDEAD0000 | Ignore operand_a |

### 1.2 Branch Comparator (`tb_branch_comp.sv`)

**DUT:** `branch_comp.sv`

| Test Case | rs1 | rs2 | funct3 | branch | Expected branch_taken |
|-----------|-----|-----|--------|--------|-----------------------|
| BEQ true | 5 | 5 | 000 | 1 | 1 |
| BEQ false | 5 | 6 | 000 | 1 | 0 |
| BNE true | 5 | 6 | 001 | 1 | 1 |
| BNE false | 5 | 5 | 001 | 1 | 0 |
| BLT true | -1 | 0 | 100 | 1 | 1 | signed |
| BLT false | 0 | -1 | 100 | 1 | 0 | |
| BGE true | 0 | -1 | 101 | 1 | 1 | |
| BLTU true | 0 | 1 | 110 | 1 | 1 | unsigned |
| BLTU false | 0xFFFFFFFF | 0 | 110 | 1 | 0 | |
| BGEU true | 0xFFFFFFFF | 0 | 111 | 1 | 1 | |
| branch=0 | any | any | 000 | 0 | 0 | branch disabled |

### 1.3 Instruction Decoder (`tb_id_decoder.sv`)

**DUT:** `id_decoder.sv`

Construct test vectors bằng cách encode instruction bits thủ công. Verify từng trường output.

| Instruction | Encoding | Kiểm tra |
|-------------|----------|----------|
| `ADD x1,x2,x3` | 0x002080B3 | rs1=2,rs2=3,rd=1, alu_op=ADD, reg_write=1, wb_sel=00 |
| `SUB x1,x2,x3` | 0x402080B3 | alu_op=SUB |
| `ADDI x1,x2,5` | 0x00510093 | alu_src_b=1, imm=5 |
| `LUI x5,0xABCDE` | 0xABCDE2B7 | alu_op=PASSB, alu_src_b=1, imm=0xABCDE000 |
| `AUIPC x5,0x1` | 0x00001297 | alu_src_a=1, alu_src_b=1, imm=0x1000 |
| `JAL x1,+8` | 0x008000EF | jump=1, jump_reg=0, imm=8, wb_sel=10 |
| `JALR x1,x2,4` | 0x00410067 | jump=1, jump_reg=1, imm=4, wb_sel=10 |
| `BEQ x1,x2,+8` | 0x00208463 | branch=1, funct3=000, imm=8 |
| `LW x1,4(x2)` | 0x00412083 | mem_read=1, mem_size=10, mem_ext=1, wb_sel=01 |
| `LBU x1,0(x2)` | 0x00014083 | mem_size=00, mem_ext=0 |
| `SW x1,4(x2)` | 0x00112223 | mem_write=1, mem_size=10 |
| `CSRRW x1,mtvec,x2` | 0x30511073 | csr_addr=0x305, csr_we=1, csr_op=01, wb_sel=11 |
| `CSRRS x1,mtvec,x0` | 0x30502073 | csr_we=0 (rs1=x0, không được write) |
| `CSRRC x1,mtvec,x0` | 0x30503073 | csr_we=0 (rs1=x0) |
| `CSRRSI x1,mtvec,0` | 0x30506073 | csr_we=0 (imm=0) |
| `ECALL` | 0x00000073 | ecall=1 |
| `EBREAK` | 0x00100073 | ebreak=1 |
| `MRET` | 0x30200073 | mret=1 |
| Illegal (funct3=011 trong BRANCH) | 0x00018063 | illegal_instr=1 |
| Undefined opcode | 0x00000002 | illegal_instr=1 |

### 1.4 Register File (`tb_register_file.sv`)

| Test Case | Mô tả |
|-----------|-------|
| x0 luôn = 0 | Write 0xDEADBEEF vào x0; read lại phải = 0 |
| Write-read | Write 0x1234 vào x1; read lại cycle sau |
| No stall issue | Write x1 cycle N, read x1 cycle N+1 |
| Multiple regs | Write x1..x31 với giá trị khác nhau, verify từng reg |
| After reset | Tất cả reg = 0 sau rst_n deassert |

---

## NHÓM 2 — Pipeline Unit Tests

### 2.1 Forwarding Unit (`tb_forwarding_unit.sv`)

**Test priority: MEM1 > MEM2 > WB > none**

| Scenario | EX rs | MEM1 rd | MEM2 rd | WB rd | Expected fwd_sel_a |
|----------|-------|---------|---------|-------|-------------------|
| No hazard | x1 | x2 | x3 | x4 | 00 (no fwd) |
| MEM1 match | x1 | x1 | x1 | x1 | 01 (MEM1 wins) |
| MEM2 match, MEM1 no | x1 | x2 | x1 | x1 | 10 (MEM2) |
| WB only | x1 | x2 | x3 | x1 | 11 (WB) |
| rd=x0 no fwd | x0 | x0 | x0 | x0 | 00 (x0 never forwarded) |
| reg_write=0 no fwd | x1 | x1(rw=0) | x0 | x0 | 00 |

### 2.2 Hazard Unit (`tb_hazard_unit.sv`)

| Scenario | Input | Expected Output |
|----------|-------|-----------------|
| Load-Use: ex_mem_read=1, rd match rs1 | ex_rd=x1, id_rs1=x1 | stall_pc/if1if2/if2id=1, flush_id_ex=1 |
| Load-Use: rd match rs2 | ex_rd=x1, id_rs2=x1 | stall=1, flush_id_ex=1 |
| Load-Use: rd=x0 no stall | ex_rd=x0, any rs | no stall |
| Branch taken flush | branch_taken=1 | flush_if1if2=1, flush_if2id=1, flush_id_ex=1 |
| Jump flush | jump=1 | flush_if1if2=1, flush_if2id=1, flush_id_ex=1 |
| Zicsr flush | zicsr_flush=1 | ALL flush signals=1 |
| Bus stall | bus_stall_req=1 | ALL stall signals=1, no flush |
| Bus stall + zicsr | both=1 | all stall=1, all flush=1 |

**Điểm quan trọng cần verify:** `flush_id_ex = 1` khi `ctrl_flush=1` (bug fix #1).

### 2.3 Async FIFO (`tb_async_fifo.sv`)

**DUT:** `async_fifo_depth2 #(.DATA_WIDTH(8))` (test với width nhỏ)

| Test Case | Mô tả |
|-----------|-------|
| Reset state | `rd_empty=1` sau reset |
| Single write then read | Write 1 item, check empty clears; read, empty returns |
| Gray code pointer | Verify wr_ptr_gray/rd_ptr_gray increment theo Gray code sau mỗi write/read |
| Empty flag timing | `rd_empty` phải deassert sau khi wr_ptr_gray được sync (2 clk_rd cycles sau write) |
| Full → not overflow | Depth=2: write 2 items (không có full flag — giả định CPU stall ngăn write 3) |
| Clock domain crossing | wr_clk=10ns, rd_clk=23ns (prime ratio để tránh alignment) |
| Back-to-back reads | Write 2, read 2 back-to-back |

**Verify Gray code cụ thể:**
- Initial: wr_ptr_gray = 2'b00
- After 1 write: wr_ptr_gray = 2'b01 (gray(1) = 01)
- After 2 writes: wr_ptr_gray = 2'b11 (gray(2) = 11)

---

## NHÓM 3 — Pipeline Integration Tests

### 3.1 CPU Pipeline (`tb_pipeline_cpu.sv`)

Instantiate toàn bộ CPU pipeline: IF1→WB + hazard_unit + forwarding_unit + zicsr + imem + dmem. Nạp chương trình vào IMEM, observe regfile.

#### 3.1.1 Arithmetic Sequence

```asm
ADDI x1, x0, 10    # x1 = 10
ADDI x2, x0, 5     # x2 = 5
ADD  x3, x1, x2    # x3 = 15
SUB  x4, x1, x2    # x4 = 5
```
**Expected:** x3=15, x4=5 sau WB cycle tương ứng.

#### 3.1.2 Data Hazard — Forwarding

```asm
ADDI x1, x0, 1
ADD  x2, x1, x1    # x2 = x1 + x1 = 2 (cần fwd từ EX/MEM1)
ADD  x3, x2, x1    # x3 = x2 + x1 = 3 (cần fwd từ MEM1/MEM2)
ADD  x4, x3, x1    # x4 = x3 + x1 = 4
```
**Expected:** x2=2, x3=3, x4=4 — verify không có stall bất cần thiết.

#### 3.1.3 Data Hazard — Load-Use Stall

```asm
ADDI x1, x0, 0x10000  # x1 = base DMEM addr
SW   x0, 0(x1)        # mem[0x10000] = 0
ADDI x5, x0, 42
SW   x5, 0(x1)        # mem[0x10000] = 42
LW   x2, 0(x1)        # x2 = mem[0x10000] = 42
ADD  x3, x2, x0       # ← load-use hazard: cần stall 1 cycle
```
**Expected:** x3=42. Verify đúng 1 cycle stall (pipeline clock count tăng đúng).

#### 3.1.4 Branch — BEQ Taken

```asm
ADDI x1, x0, 5
ADDI x2, x0, 5
BEQ  x1, x2, +8   # taken (skip next instruction)
ADDI x3, x0, 99   # ← phải bị flush (KHÔNG execute)
ADDI x3, x0, 1    # ← phải execute
```
**Expected:** x3=1 (NOT 99). Verify flush_if1if2 và flush_id_ex cao đúng 1 cycle.

#### 3.1.5 Branch — BNE Not Taken

```asm
ADDI x1, x0, 5
ADDI x2, x0, 6
BNE  x1, x2, +8   # not taken (x1 ≠ x2)
ADDI x3, x0, 7    # ← phải execute
```
**Expected:** x3=7.

#### 3.1.6 JAL / JALR

```asm
JAL x1, +8        # x1 = PC+4, jump to PC+8
ADDI x2, x0, 99  # ← bị flush
ADDI x2, x0, 1   # ← target: execute
```
**Expected:** x2=1, x1=PC_of_JAL+4.

#### 3.1.7 LUI / AUIPC

```asm
LUI  x1, 0xABCDE       # x1 = 0xABCDE000
AUIPC x2, 1            # x2 = PC + 0x1000
ADD  x3, x1, x2        # x3 = 0xABCDE000 + PC + 0x1000
```
**Expected:** Verify bit-exact.

#### 3.1.8 DMEM Load-Store (Word, Half, Byte)

```asm
# Word
ADDI x1, x0, 0x10000
ADDI x5, x0, 0x1234ABCD (via LUI+ADDI)
SW   x5, 0(x1)
LW   x2, 0(x1)          # x2 = 0x1234ABCD

# Halfword (LH sign extends)
SH   x5, 4(x1)
LH   x3, 4(x1)          # x3 = sign_extend(0xABCD) = 0xFFFFABCD

# Byte (LBU zero extends)
SB   x5, 8(x1)
LBU  x4, 8(x1)          # x4 = 0x000000CD
```
**Expected:** verify từng kết quả.

#### 3.1.9 SLT / SLTU / Shifts

```asm
ADDI x1, x0, -1        # x1 = 0xFFFFFFFF
ADDI x2, x0, 1
SLT  x3, x1, x2        # x3 = 1 (signed: -1 < 1)
SLTU x4, x1, x2        # x4 = 0 (unsigned: 0xFFFFFFFF > 1)
SRL  x5, x1, x2        # x5 = 0x7FFFFFFF (logical right shift 1)
SRA  x6, x1, x2        # x6 = 0xFFFFFFFF (arith right shift 1, sign preserved)
```

---

## NHÓM 4 — CSR và Exception/Interrupt Tests

### 4.1 CSR Read-Write Operations (`tb_pipeline_cpu.sv` — CSR section)

**Prerequisite:** Nạp mtvec = 0x0000_0100 (handler địa chỉ).

| Test | Instruction | Expected |
|------|-------------|---------|
| CSRRW write + read | `CSRRW x1, mtvec, x2` (x2=0x100) | mtvec=0x100, x1=prev_mtvec |
| CSRRS set bits | Write mtvec=0x100; `CSRRS x0, mtvec, x3` (x3=4) | mtvec=0x104 |
| CSRRC clear bits | `CSRRC x0, mtvec, x3` (x3=4) | mtvec=0x100 |
| CSRRSI immediate | `CSRRSI x0, mie, 8` | mie[3]=1 (MSIE bit set) |
| CSRRCI immediate | `CSRRCI x0, mie, 8` | mie[3]=0 |
| CSRRS x0 no write | Write mtvec=0x100; `CSRRS x0, mtvec, x0` | mtvec unchanged=0x100 (bug fix #4) |

**Critical: CSR op correctness (bug fix #2)**
Trước fix: CSRRW thực hiện OR, CSRRS thực hiện AND-NOT (wrong).
Verify sau fix: CSRRW(mtvec=0x100, x2=0x200) → mtvec=0x200 (NOT 0x300).

### 4.2 ECALL Exception

```asm
# Setup
LI   x1, 0x200       # x1 = mtvec address
CSRRW x0, mtvec, x1  # mtvec = 0x200 (handler)
LI   x2, 8
CSRRW x0, mstatus, x2  # mstatus.MIE = 1

ECALL                 # Trigger ecall exception
```

**Handler ở 0x200:**
```asm
CSRRW x10, mepc, x0   # x10 = mepc (phải = addr của ECALL)
CSRRW x11, mcause, x0 # x11 = mcause (phải = 11 = ecall from M-mode)
MRET                   # return to mepc
```
**Expected:**
- Sau ECALL: PC nhảy đến 0x200
- `mepc = addr_of_ECALL`
- `mcause = 32'd11`
- `mstatus.MIE = 0`, `mstatus.MPIE = 1`
- Sau MRET: PC = mepc, `mstatus.MIE = 1`

### 4.3 Interrupt — Machine External Interrupt (MEI)

```asm
LI   x1, 0x400       # x1 = mtvec base
ORI  x1, x1, 1       # x1 = 0x401 (vectored mode)
CSRRW x0, mtvec, x1  # mtvec = 0x401 (vectored)
LI   x2, 0x800
CSRRW x0, mie, x2    # mie.MEIE = 1 (enable ext interrupt)
LI   x2, 8
CSRRW x0, mstatus, x2  # mstatus.MIE = 1

# Spin loop
LOOP: JAL x0, LOOP   # ← interrupt fires during this loop
```

**Stimulus:** Assert `axi_irq=1` hoặc `ahb_irq=1` trong khi spin loop đang chạy.

**Expected:**
- PC nhảy đến `mtvec_base + 4*11 = 0x400 + 44 = 0x42C` (vectored MEI)
- `mepc = LOOP_addr + 4` (instruction AFTER the JAL that was at WB when interrupt fired — bug fix #3)
- `mcause = {1, 31'd11}` = 0x8000000B
- `mstatus.MIE = 0`
- Sau MRET: PC = mepc, tiếp tục tại LOOP_addr+4

### 4.4 Interrupt — Machine Software Interrupt (MSI)

```asm
CSRRW x0, mtvec, x1  # mtvec = 0x400 (vectored)
LI x2, 8
CSRRW x0, mie, x2    # mie.MSIE = 1 (enable software interrupt)  
LI x3, 8
CSRRW x0, mstatus, x3  # mstatus.MIE = 1
CSRRSI x0, mip, 8    # mip.MSIP = 1 → trigger MSI immediately
NOP                   # ← interrupt should fire at next WB
```

**Expected:**
- PC → `mtvec_base + 4*3 = 0x400 + 12 = 0x40C` (vectored MSI)
- `mcause = {1, 31'd3}` = 0x80000003

### 4.5 Precise Exception — Bus Stall + Exception

```asm
LW x1, 0(x0)         # Load from 0x0000_0000 — valid IMEM region (access fault)
                      # (hoặc từ một unmapped address)
```

**Test:** khi `bus_stall_req=0` và load_fault propagates đến WB, Zicsr mới xử lý.
- Verify: không flush pipeline trong khi bus_stall_req=1
- Verify: `load_access_fault = 1` → `mcause = 32'd5`

### 4.6 MRET

```asm
# Simulate trap manually:
LI x1, 0x300
CSRRW x0, mepc, x1   # mepc = 0x300
MRET                  # PC → 0x300, restore mstatus
```
**Expected:** PC = 0x300, `mstatus.MIE = mstatus.MPIE`.

---

## NHÓM 5 — Bus Interface Tests

### 5.1 AXI Interface (`tb_axi_if.sv`)

Instantiate `axi_interface` với AXI slave model (behavioural, 2-cycle latency).

| Test Case | Mô tả |
|-----------|-------|
| Word Write | axi_req_we=1, size=10(word) → AWVALID+WVALID, WSTRB=1111, BRESP=00 |
| Word Read | axi_req_we=0 → ARVALID, check RDATA, resp_valid |
| Half Write low | addr[1]=0, size=01 → WSTRB=0011, WDATA[15:0]=data |
| Half Write high | addr[1]=1, size=01 → WSTRB=1100, WDATA[31:16]=data |
| Byte Write @ offset 0 | addr[1:0]=00, size=00 → WSTRB=0001 |
| Byte Write @ offset 3 | addr[1:0]=11, size=00 → WSTRB=1000 |
| Slow slave | AWREADY delayed 3 cycles → check no resp_valid until handshake |
| AW before W | AWVALID first, WVALID delayed → both_done trigger |
| W before AW | WVALID first, AWVALID delayed → both_done trigger |
| Error response | BRESP=01 → axi_resp_err=1 |

### 5.2 AHB Interface (`tb_ahb_if.sv`)

Instantiate `ahb_interface` với AHB slave model (behavioral).

| Test Case | Mô tả |
|-----------|-------|
| Write (0-wait) | FIFO entry → HADDR/HWRITE/HTRANS=NONSEQ, HWDATA cycle sau |
| Read (0-wait) | HREADY=1 immediate → resp_wr_en, HRDATA captured |
| Wait states | HREADY=0 held 2 cycles → FSM stays DATA_ST until HREADY=1 |
| Error response | HRESP=1 → resp_wr_data[32]=1 (HRESP bit) |
| Back-to-back | 2 requests sequentially |
| HSIZE encoding | size=00 → HSIZE=3'b000 (byte); size=10 → HSIZE=3'b010 (word) |

### 5.3 AXI Interconnect (`tb_axi_xbar.sv`)

| Test Case | Mô tả |
|-----------|-------|
| Route to S0 | AWADDR=0x2000_0004 → S0_AWVALID=1, S1/S2_AWVALID=0 |
| Route to S1 | AWADDR=0x2001_0000 → S1_AWVALID=1 |
| Route to S2 | ARADDR=0x2002_0000 → S2_ARVALID=1 |
| IRQ aggregation | irq0=1 → axi_irq=1; irq1=1 → axi_irq=1; all=0 → 0 |
| AR/AW sel register | AR accepted → ar_sel_reg locked; R data mux đúng slave |

---

## NHÓM 6 — Full-System Smoke Tests (`tb_soc_top.sv`)

Instantiate `soc_top` với 2 clock: `clk_cpu` (period=10ns), `clk_ahb` (period=20ns).

### 6.1 AXI SFR Write-Read

```c
// Equivalent assembly
SW  x1, 0(AXI_SFR0_BASE)   // Write REG0 of SFR0
LW  x2, 0(AXI_SFR0_BASE)   // Read back → x2 = x1
```
AXI_SFR0_BASE = 0x2000_0000

**Expected:** x2 = x1. Verify bus_stall_req asserted during transaction.

### 6.2 AHB SFR Write-Read

```c
SW  x1, 0(AHB_SFR0_BASE)   // Write REG0 của AHB SFR0
LW  x2, 0(AHB_SFR0_BASE)   // Read back
```
AHB_SFR0_BASE = 0x3000_0000

**Expected:** x2 = x1 (qua CDC path — latency cao hơn). Verify pipeline stall trong suốt AHB transaction.

### 6.3 AXI IRQ Path

1. Write 0x1 vào AXI_SFR0[7] (IRQ register): `SW x1, 0x1C(AXI_SFR0_BASE)`
2. Enable MEI: `CSRRSI x0, mie, 0x800`; Enable MIE: `CSRRSI x0, mstatus, 8`
3. Spin loop
4. **Verify:** `axi_irq` goes high → Zicsr sees → PC jumps to vectored handler

### 6.4 AHB IRQ Path (CDC)

1. Write 0x1 vào AHB_SFR0[7]
2. **Verify:** `ahb_irq_raw` goes high (500MHz domain); 2-FF sync in Zicsr delays 2 `clk_cpu` cycles; then interrupt fires.

### 6.5 DMEM Endurance

Write 64 consecutive words to DMEM (0x10000..0x1003F), read back all. Verify no corruption.

---

## NHÓM 7 — Edge Cases và Regression

| # | Test | Mô tả |
|---|------|-------|
| E1 | x0 write | `ADD x0, x1, x2` — x0 must remain 0 after writeback |
| E2 | JALR bit-0 mask | JALR target must have bit-0 cleared per spec |
| E3 | Branch delay slot | Verify instruction AFTER branch does NOT execute when taken (flush_id_ex=ctrl_flush fix) |
| E4 | Back-to-back branches | Two consecutive branches — second should handle correctly |
| E5 | Load-use + branch | Load followed by branch that uses load result — verify stall + correct branch eval |
| E6 | CSRRW x0 | CSRRW with rd=x0 reads CSR but x0 stays 0 |
| E7 | mip read-only MEIP | Attempt to write mip via CSRRW — MEIP bit must not change |
| E8 | mepc alignment | mepc always bits[1:0]=0 after trap |
| E9 | Interrupt during load | Load to AXI in progress (bus_stall=1); interrupt pending → waits for bus done |
| E10 | DMEM boundary | Write/read word at addr 0x1FFFC (last word in DMEM 64KB) |
| E11 | IMEM non-execute | IMEM does not execute write requests (verify dmem_we=0 for IMEM addresses) |
| E12 | Double exception | ecall với illegal_instr false simultaneously → mcause priority: illegal > ebreak > load > store > ecall |

---

## Tiêu Chí Pass/Fail

| Mức | Định nghĩa |
|-----|-----------|
| **PASS** | Tất cả register values khớp expected sau đúng số cycles |
| **FAIL-LOGIC** | Kết quả sai (wrong register value, wrong CSR, wrong exception) |
| **FAIL-TIMING** | Đúng kết quả nhưng sai số cycle (stall count sai) |
| **FAIL-DEADLOCK** | Pipeline không tiến sau X cycles |

---

## Gợi Ý Tổ Chức Testbench

```systemverilog
// Template testbench dùng task-based approach
module tb_xxx;
    // Instantiate DUT
    // Clock gen
    // Reset task
    // Check task với $display + pass/fail counter
    // Dump VCD: $dumpfile("tb_xxx.vcd"); $dumpvars(0, tb_xxx);
    initial begin
        run_test_cases;
        $display("PASS: %0d / FAIL: %0d", pass_cnt, fail_cnt);
        $finish;
    end
endmodule
```

---

## Thứ Tự Khuyến Nghị

1. ✅ Unit: ALU, Branch Comp, Decoder, RegFile
2. ✅ Unit: Forwarding, Hazard, Async FIFO
3. ✅ Integration: Pipeline — arithmetic, forwarding, load-use stall
4. ✅ Integration: Pipeline — branch/jump (verify flush_id_ex fix)
5. ✅ Integration: Pipeline — DMEM load/store
6. ✅ CSR: CSRRW/RS/RC operations (verify CSR op fix)
7. ✅ Exception: ECALL, load_fault
8. ✅ Interrupt: MEI, MSI, mepc+4 verify
9. ✅ Bus: AXI interface, AHB interface
10. ✅ Full system: SoC smoke tests
