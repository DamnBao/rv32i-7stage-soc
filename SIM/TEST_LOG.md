# Test Log — RISC-V SoC Unit Tests

**Ngày hoàn thành Phase 1 + 2:** 2026-06-19  
**Ngày hoàn thành Phase 3:** 2026-06-20 (9 programs: +4 CSR/exception/interrupt)  
**Simulator:** Icarus Verilog 12 (`iverilog -g2012`)  
**Toolchain:** `riscv64-unknown-elf-gcc 13.2.0` (Ubuntu 24.04 apt)  
**Working directory:** `/home/baoslinux/riscv_soc_thesis/SIM/`

---

## Nhật Ký Session 2026-06-20 — Hoàn Thành Phase 3

### Bối cảnh

Phase 3 ban đầu có 5 programs (arithmetic, forwarding, load_store, branch_jump, csr) tất cả đã PASS từ ngày 19/06. Session này thêm 4 programs mới để test exception/interrupt và phát hiện + sửa một RTL bug nghiêm trọng trong `imem.sv`.

---

### Bug 4 Phát Hiện: Ghost Instruction từ IMEM sau zicsr_flush

#### Triệu chứng

`prog_ecall` (test ECALL + MRET) TIMEOUT sau 200.000 chu kỳ — không bao giờ đến EBREAK.

#### Quá trình debug

1. Tạo debug testbench `tb_ecall_debug.sv` với per-cycle display: `{wb_pc, wb_ecall, wb_mret, wb_ebreak, zicsr_flush, mepc}`.
2. Thêm 5 DMEM trace stores vào handler của `prog_ecall.s` để quan sát giá trị CSR thực tế.
3. Output cho thấy vòng lặp vô hạn: handler tại 0x44 → MRET → handler tại 0x44 → ... và `mcause=2` (Illegal Instruction) thay vì 11 (ECALL), `mepc=0x00` sau lần thứ 2.

#### Root cause (chi tiết)

Pipeline 7 tầng: khi MRET đang ở WB (chu kỳ C0044), IF1 đã chạy trước 6 chu kỳ và đang ở địa chỉ `0x94` (past end of binary — vùng không có instruction nào). `imem.sv` dùng `always_ff` (registered output, 1-cycle latency):

```sv
// TRƯỚC KHI SỬA — lỗi:
always_ff @(posedge clk) begin
    if (!stall)
        instr_out <= mem[word_addr];  // không có flush!
end
```

Tại posedge C0044 (lúc MRET đang ở WB và `zicsr_flush=1`):
- IMEM latch `mem[0x94>>2] = 0x00000000` (empty — nằm ngoài binary)
- `if1_if2_reg` bị flush → `pc_out = 0`

Chu kỳ C0045:
- `imem_instr = 0x00000000` → vào `if2_id_reg` → `id_decoder` decode `0x00000000` = illegal_instr=1
- (PC=0 + instr=0x00000000 là "ghost instruction")

Chu kỳ C0051 (7 chu kỳ sau flush):
- Ghost instruction đến WB → `take_exception=1` → `mepc=0x00`, `mcause=2`
- Pipeline redirect về `mtvec=0x44` → handler chạy lại với `mepc=0x00`
- Từ đó: infinite loop, không bao giờ đến EBREAK → TIMEOUT

**Lý do 5 programs trước không bị ảnh hưởng:** Chúng kết thúc bằng EBREAK, `$finish` được gọi trong vòng ~2 chu kỳ sau EBREAK — TRƯỚC KHI ghost instruction kịp lan đến WB (cần ~7 chu kỳ). Với `ctrl_flush` (branch taken), địa chỉ trong IMEM là instruction hợp lệ (không phải 0x00000000) nên không sinh `illegal_instr`.

#### Fix RTL

**`RTL/imem.sv`** — thêm port `flush`, output NOP khi flush:

```sv
// SAU KHI SỬA:
module imem #(...)(
    input  logic        clk,
    input  logic        stall,
    input  logic        flush,    // PORT MỚI
    input  logic [31:0] addr,
    output logic [31:0] instr_out
);
always_ff @(posedge clk) begin
    if (flush)
        instr_out <= 32'h0000_0013;  // addi x0,x0,0 = NOP, vô hại
    else if (!stall)
        instr_out <= mem[word_addr];
end
```

**`RTL/soc_top.sv`** — wire `flush_if1if2` vào `u_imem.flush`:

```sv
// TRƯỚC:
imem #(.SIZE_KB(64)) u_imem (
    .clk  (clk_cpu), .stall(stall_if1if2),
    .addr (if1_pc),  .instr_out(imem_instr)
);
// SAU:
imem #(.SIZE_KB(64)) u_imem (
    .clk  (clk_cpu), .stall(stall_if1if2),
    .flush(flush_if1if2),            // THÊM DÒNG NÀY
    .addr (if1_pc),  .instr_out(imem_instr)
);
```

`flush_if1if2 = zicsr_flush | ctrl_flush` — đã có sẵn trong hazard_unit, không cần thay đổi gì thêm.

#### Tại sao NOP (0x0000_0013) là đúng?

`addi x0, x0, 0`: rd=x0 (hardwired 0, không ghi), rs1=x0, imm=0. Không sinh exception, không modify register, không modify CSR. Pipeline xử lý xong và discard. Ghost instruction biến mất hoàn toàn.

---

### 4 Programs Mới Được Thêm

| Program | File | Kiểm tra gì |
|---------|------|------------|
| `prog_ecall.s` | `programs/prog_ecall.s` | ECALL sinh exception, mtvec setup, handler đọc mepc/mcause, advance mepc+4, MRET trả về đúng vị trí, mstatus.MIE restore sau MRET |
| `prog_interrupt_msi.s` | `programs/prog_interrupt_msi.s` | M-mode software interrupt (MSIP), vectored handler, xóa MIP.MSIP trong handler, MRET |
| `prog_interrupt_mei.s` | `programs/prog_interrupt_mei.s` | M-mode external interrupt từ AXI IRQ, vectored handler, xóa IRQ source, MRET |
| `prog_load_fault.s` | `programs/prog_load_fault.s` | Load access fault (load từ địa chỉ không hợp lệ), mcause=5, mepc đúng, handler MRET |

---

### Kết Quả Cuối Session

```
make p3_all

prog_arithmetic    → PASS  (94.5 ns)
prog_forwarding    → PASS  (52.5 ns)
prog_load_store    → PASS  (78.5 ns)
prog_branch_jump   → PASS  (79.5 ns)
prog_csr           → PASS  (103.5 ns)
prog_ecall         → PASS  (74.5 ns)
prog_interrupt_msi → PASS
prog_interrupt_mei → PASS
prog_load_fault    → PASS

9/9 PASS — Phase 3 hoàn thành
```

---

### Files Thay Đổi Trong Session Này

| File | Thay đổi |
|------|---------|
| `RTL/imem.sv` | Thêm port `flush`; `always_ff` output NOP khi flush=1 |
| `RTL/soc_top.sv` | Wire `flush_if1if2` → `u_imem.flush` |
| `SIM/programs/prog_ecall.s` | Viết mới: ECALL/MRET test với DMEM trace stores |
| `SIM/programs/prog_interrupt_msi.s` | Viết mới: MSI interrupt test |
| `SIM/programs/prog_interrupt_mei.s` | Viết mới: MEI interrupt test |
| `SIM/programs/prog_load_fault.s` | Viết mới: load fault exception test |
| `SIM/TEST_LOG.md` | Cập nhật: thêm 4 programs, thêm Bug 4, cập nhật tổng kết |
| `CLAUDE.md` | Cập nhật: imem.sv status, Phase 3 = 9/9 PASS |

---

---

## Tổng Kết Nhanh

| Phase | Testbench | Module DUT | Tests | Kết quả |
|-------|-----------|------------|-------|---------|
| 1 | `unit/tb_alu.sv` | `alu.sv` | 38 | PASS |
| 1 | `unit/tb_branch_comp.sv` | `branch_comp.sv` | 25 | PASS |
| 1 | `unit/tb_register_file.sv` | `register_file.sv` | 17 | PASS |
| 1 | `unit/tb_id_decoder.sv` | `id_decoder.sv` | 112 | PASS |
| 2 | `unit/tb_forwarding_unit.sv` | `forwarding_unit.sv` | 19 | PASS |
| 2 | `unit/tb_hazard_unit.sv` | `hazard_unit.sv` | 60 | PASS |
| 2 | `unit/tb_async_fifo.sv` | `async_fifo.sv` | 22 | PASS |
| 3 | `integration/tb_pipeline_cpu.sv` | `soc_top.sv` (full pipeline) | 9 programs | PASS |
| 4a | `integration/tb_axi_interface.sv` | `axi_interface.sv` + `axi_slave_model.sv` | 49 | PASS |
| 4b | `integration/tb_ahb_interface.sv` | `ahb_interface.sv` + CDC FIFOs + `ahb_slave_model.sv` | 29 | PASS |
| 4c | `integration/tb_axi_full.sv` | `axi_interface.sv` + `axi_interconnect.sv` + 3×`axi_sfr.sv` | 40 | PASS |
| 4d | `integration/tb_ahb_full.sv` | `ahb_interface.sv` + CDC + `ahb_interconnect.sv` + 3×`ahb_sfr.sv` | 35 | PASS |
| 5 | `integration/tb_pipeline_cpu.sv` | `soc_top.sv` — AXI/AHB SFR + IRQ từ CPU | 4 programs | PASS |
| 6a | `system/tb_soc_top.sv` | `soc_top.sv` — batch runner 16 programs (Phase3+5+6) | 16 programs | PASS |
| 6b | `system/tb_compliance.sv` | `soc_top.sv` — compliance framework (shifts, compare, dmem_endurance) | 3 programs | PASS |
| **Total** | | | **446 + 32 progs** | **All PASS** |

---

## Cách Chạy Lại

```bash
cd /home/baoslinux/riscv_soc_thesis/SIM

# Chạy từng test
make unit_alu
make unit_branch
make unit_decoder
make unit_rf
make unit_fwd
make unit_haz
make unit_fifo

# Chạy tất cả Phase 1+2 cùng lúc
make unit_all
```

---

## Cách Bật VCD Để Xem Waveform

Mặc định testbench không dump VCD (chạy nhanh hơn). Để xem waveform trong GTKWave, thêm đoạn sau vào đầu `initial begin` của bất kỳ testbench nào:

```systemverilog
initial begin
    $dumpfile("unit/tb_XXX.vcd");
    $dumpvars(0, tb_XXX);      // dump toàn bộ hierarchy
    // ... test code ...
end
```

Sau đó:
```bash
make unit_XXX          # compile + chạy → sinh ra .vcd
gtkwave unit/tb_XXX.vcd &
```

**Lưu ý:** File `.vvp` đã có sẵn (không cần recompile nếu source không đổi). Có thể chạy thẳng `vvp unit/tb_XXX.vvp` sau khi thêm dump.

---

## Phase 1 — Combinational & Clocked Units

---

### tb_alu — 38 tests PASS

**Module:** `RTL/alu.sv`  
**Type:** Combinational  
**Clock:** Không có  

**Interface:**
```
operand_a [31:0], operand_b [31:0], alu_op [3:0] → alu_result [31:0]
```

**ALU Op Encoding:**

| Code | Op | Code | Op |
|------|----|------|----|
| `4'd0` | ADD | `4'd6` | SRL |
| `4'd1` | SUB | `4'd7` | SRA |
| `4'd2` | SLL | `4'd8` | OR |
| `4'd3` | SLT | `4'd9` | AND |
| `4'd4` | SLTU | `4'd10` | PASSB |
| `4'd5` | XOR | | |

**Test cases theo nhóm:**

| Nhóm | Test case đáng chú ý |
|------|----------------------|
| ADD | Overflow wrap: `0xFFFF_FFFF + 1 = 0` |
| SUB | Underflow: `0 - 1 = 0xFFFF_FFFF` |
| SLL | shamt chỉ lấy 5 bit: `1 << 32 = 1 << 0 = 1` |
| SRL | shamt chỉ lấy 5 bit: `0xFFFF_FFFF >> 32 = 0xFFFF_FFFF` |
| SRA | Sign extend: `0x8000_0000 >>> 31 = 0xFFFF_FFFF` |
| SLT | Signed: `0x8000_0000 < 1 = 1` (vì -2^31 < 1) |
| SLTU | Unsigned: `0x8000_0000 <u 1 = 0` (vì 2^31 > 1) |
| PASSB | Bỏ qua `operand_a`, output thẳng `operand_b` (dùng cho LUI) |

**Signals cần xem nếu fail:**  
`operand_a`, `operand_b`, `alu_op`, `alu_result`

---

### tb_branch_comp — 25 tests PASS

**Module:** `RTL/branch_comp.sv`  
**Type:** Combinational  
**Clock:** Không có  

**Interface:**
```
rs1_data [31:0], rs2_data [31:0], funct3 [2:0], branch → branch_taken
```

**Funct3 mapping:**

| funct3 | Instruction | So sánh |
|--------|-------------|---------|
| `3'b000` | BEQ | rs1 == rs2 |
| `3'b001` | BNE | rs1 != rs2 |
| `3'b100` | BLT | rs1 < rs2 (signed) |
| `3'b101` | BGE | rs1 >= rs2 (signed) |
| `3'b110` | BLTU | rs1 < rs2 (unsigned) |
| `3'b111` | BGEU | rs1 >= rs2 (unsigned) |

**Test cases đáng chú ý:**

| Test | Kết quả | Lý do |
|------|---------|-------|
| `branch=0` với BEQ equal | `taken=0` | Gate: `branch` phải=1 mới taken |
| BLT: `0x8000_0000 < 1` | `taken=1` | Signed: -2^31 < 1 |
| BLT: `1 < 0xFFFF_FFFF` | `taken=0` | Signed: 1 > -1 |
| BLTU: `0x8000_0000 <u 1` | `taken=0` | Unsigned: 2^31 > 1 |
| BLTU: `1 <u 0x8000_0000` | `taken=1` | Unsigned: 1 < 2^31 |

**Signals cần xem nếu fail:**  
`rs1_data`, `rs2_data`, `funct3`, `branch`, `branch_taken`

---

### tb_register_file — 17 tests PASS

**Module:** `RTL/register_file.sv`  
**Type:** Clocked (synchronous write, combinational read)  
**Clock:** 100MHz (10ns period, testbench nội bộ)  

**Interface:**
```
clk, rst_n
rs1_addr [4:0] → rs1_data [31:0]   (combinational)
rs2_addr [4:0] → rs2_data [31:0]   (combinational)
rd_addr [4:0], rd_data [31:0], we   (sync write @ posedge clk)
```

**Internal array:** `registers[0:31]` (tên đúng để truy cập từ testbench cấp trên)

**Test cases theo nhóm:**

| Nhóm | Test case đáng chú ý |
|------|----------------------|
| After reset | x0, x1, x31 đều = 0 |
| Write/read | x1=DEAD_BEEF, x31=ABCD_1234, x15=12345678 |
| x0 hardwired | Ghi `0xFFFF_FFFF` vào x0 → đọc lại = 0 |
| Dual-port | rs1=x2, rs2=x3 đọc đồng thời |
| we=0 | Ghi không xảy ra khi we=0 |
| Independent | x5=100, x6=200, x7=300 không ảnh hưởng nhau |
| Mid-test reset | rst_n=0 → tất cả về 0 |

**Signals cần xem nếu fail:**  
`clk`, `rst_n`, `rd_addr`, `rd_data`, `we`, `rs1_addr`, `rs1_data`, `rs2_addr`, `rs2_data`  
Hierarchy: `u_dut.registers[N]` để xem nội dung register N

---

### tb_id_decoder — 112 tests PASS

**Module:** `RTL/id_decoder.sv`  
**Type:** Combinational  
**Clock:** Không có  

**Interface (tóm tắt):**
```
instr [31:0] →
  rd [4:0], rs1 [4:0], rs2 [4:0]
  imm [31:0]
  alu_op [3:0], alu_src_a, alu_src_b
  reg_write, wb_sel [1:0]
  mem_read, mem_write, mem_size [1:0], mem_ext
  branch, jump, jump_reg
  csr_we, csr_op [1:0], csr_imm_sel
  ecall, ebreak, mret
  illegal
```

**Instruction encodings được test (tính tay):**

| Instruction | Binary hex | Chú thích |
|-------------|------------|-----------|
| `LUI x1, 0x12345` | `32'h1234_50B7` | rd=1 (0x0B7>>7=1) |
| `AUIPC x2, 0xABCDE` | `32'hABCDE117` | rd=2 |
| `JAL x1, +4` | `32'h0040_00EF` | imm=4 |
| `JALR x1, x2, 4` | `32'h0041_00E7` | jump_reg=1 |
| `BEQ x1, x2, +8` | `32'h0020_8463` | branch=1, imm=8 |
| `LW x5, 8(x2)` | `32'h0081_2283` | mem_size=10 |
| `LBU x5, 0(x1)` | (xem file) | mem_ext=1 |
| `LH x5, 0(x1)` | (xem file) | mem_ext=0 |
| `SW x3, 12(x1)` | `32'h0030_A623` | mem_write=1 |
| `ADDI x3, x1, 42` | `32'h02A0_8193` | alu_src_b=1, imm=42 |
| `ADD x4, x2, x3` | `32'h0031_0233` | R-type |
| `SUB x5, x1, x2` | `32'h4020_82B3` | funct7=0x20 |
| `CSRRW x1, mstatus, x2` | `32'h3001_10F3` | csr_we=1, csr_op=01 |
| `CSRRS x1, mie, x0` | (xem file) | **csr_we=0 vì rs1=x0** |
| `CSRRC x1, mie, x0` | (xem file) | **csr_we=0 vì rs1=x0** |
| `CSRRWI x1, mstatus, 8` | (xem file) | csr_imm_sel=1, imm=zimm |
| `ECALL` | `32'h0000_0073` | ecall=1 |
| `EBREAK` | `32'h0010_0073` | ebreak=1 |
| `MRET` | `32'h3020_0073` | mret=1 |

**Bug được verify:**
- CSRRS/CSRRC với rs1=x0: `csr_we` phải = 0 (không modify CSR khi rs1=x0)
- CSRRWI: `csr_imm_sel=1`, lấy `instr[19:15]` làm zero-extended immediate

**Signals cần xem nếu fail:**  
`instr`, và output tương ứng (xem danh sách interface trên)

---

## Phase 2 — Pipeline Control Units + CDC FIFO

---

### tb_forwarding_unit — 19 tests PASS

**Module:** `RTL/forwarding_unit.sv`  
**Type:** Combinational (pure priority chain)  
**Clock:** Không có  

**Interface:**
```
ex_rs1_addr [4:0], ex_rs2_addr [4:0]
mem1_rd_addr [4:0], mem1_reg_write
mem2_rd_addr [4:0], mem2_reg_write
wb_rd_addr [4:0],   wb_reg_write
→ fwd_sel_a [1:0], fwd_sel_b [1:0]
```

**Forward select encoding:**

| `fwd_sel` | Nguồn | Ý nghĩa |
|-----------|-------|---------|
| `2'b00` | NO_FWD | Lấy từ register file (no hazard) |
| `2'b01` | FWD_M1 | Forward từ MEM1 stage |
| `2'b10` | FWD_M2 | Forward từ MEM2 stage |
| `2'b11` | FWD_WB | Forward từ WB stage |

**Priority:** MEM1 > MEM2 > WB (khi nhiều stage cùng có rd match)

**Test cases đáng chú ý:**

| Test | Kết quả | Lý do |
|------|---------|-------|
| MEM1 match nhưng `mem1_reg_write=0` | NO_FWD | we=0 suppress |
| MEM2 match nhưng `mem2_reg_write=0` | FWD_WB (fallback) | Priority chain tiếp tục |
| `ex_rs1_addr=x0` | NO_FWD | x0 không forward |
| A=MEM1, B=MEM2 đồng thời | fwd_a=01, fwd_b=10 | 2 kênh độc lập |

**Lỗi phát hiện khi viết:**  
Icarus Verilog 12 không hỗ trợ named task arguments (`.rs1(val)` syntax). Đã sửa sang positional arguments.

**Signals cần xem nếu fail:**  
`ex_rs1_addr`, `ex_rs2_addr`, `mem1_rd_addr`, `mem1_reg_write`, `mem2_rd_addr`, `mem2_reg_write`, `wb_rd_addr`, `wb_reg_write`, `fwd_sel_a`, `fwd_sel_b`

---

### tb_hazard_unit — 60 tests PASS

**Module:** `RTL/hazard_unit.sv`  
**Type:** Combinational (tất cả `assign`)  
**Clock:** Không có  

**Interface:**
```
bus_stall_req, ex_mem_read, ex_rd_addr [4:0]
id_rs1_addr [4:0], id_rs2_addr [4:0]
branch_taken, jump, zicsr_flush
→ stall_pc, flush_pc
  stall_if1_if2, flush_if1_if2
  stall_if2_id,  flush_if2_id
  stall_id_ex,   flush_id_ex
  stall_ex_mem1, flush_ex_mem1
  stall_mem1_mem2, flush_mem1_mem2
  stall_mem2_wb,   flush_mem2_wb
```

**Hazard behaviors:**

| Hazard | Stall | Flush | Ghi chú |
|--------|-------|-------|---------|
| Idle | Tất cả=0 | Tất cả=0 | |
| Load-use (rs1 match) | PC, IF1/IF2, IF2/ID | ID/EX (bubble) | EX..WB không stall |
| Load-use (rs2 match) | PC, IF1/IF2, IF2/ID | ID/EX | Giống rs1 |
| Load-use rd=x0 | Không | Không | x0 không hazard |
| ex_mem_read=0 | Không | Không | Chỉ load gây hazard |
| Branch taken | Không | IF1/IF2, IF2/ID, ID/EX | 3 tầng fetch flush |
| Jump | Không | IF1/IF2, IF2/ID, ID/EX | Giống branch |
| Bus stall | Tất cả=1 | Tất cả=0 | Pipeline đứng yên |
| Zicsr flush | Không | Tất cả=1 | Toàn bộ pipeline flush |

**Test cases đặc biệt:**

| Test | Kết quả | Ghi chú |
|------|---------|---------|
| Load-use + branch | stall+flush IF, flush ID/EX | Cả hai cùng active |
| Zicsr + branch + load-use | flush_ex_mem1=1, flush_mem2_wb=1 | Zicsr wins toàn bộ |

**Signals cần xem nếu fail:**  
Tất cả input và các intermediate signal: `load_use_stall`, `ctrl_flush` (trong RTL)

---

### tb_async_fifo — 22 tests PASS

**Module:** `RTL/async_fifo.sv` (module name: `async_fifo_depth2`)  
**Type:** Dual-clock CDC FIFO (depth=2, Gray code)  
**Clock:** wr_clk=10ns (1GHz), rd_clk=20ns+7ns_offset (500MHz stress CDC)  

**Interface:**
```
wr_clk, wr_rst_n, wr_en, wr_data [DW-1:0]
rd_clk, rd_rst_n, rd_en, rd_data [DW-1:0], rd_empty
(Không có wr_full — CPU bị stall cứng nên không overflow)
```

**Cơ chế bên trong:**
- `rd_data = mem[rd_ptr_bin[0]]` — **combinational**, hiển thị head item trước khi advance
- rd_ptr chỉ advance khi `rd_en=1 && !rd_empty` tại `posedge rd_clk`
- wr_ptr_gray sync sang rd domain qua 2-FF: cần **tối thiểu 2 posedge rd_clk** sau write
- Gray code: ptr=00→gray 00, 01→01, 10→11, 11→10

**Test cases:**

| Test | Mô tả | Pass |
|------|-------|------|
| After reset | rd_empty=1 | ✓ |
| Write 0xAB → sync_wait(4) | rd_empty=0 | ✓ |
| Read 0xAB, check empty=1 | rd_data check trước khi advance | ✓ |
| Write 2 words (CA, FE) | rd_empty=0, đọc theo thứ tự | ✓ |
| rd_en=1 khi empty | Pointer không advance, sau write vẫn đọc đúng | ✓ |
| Reset giữa chừng | rd_empty về 1 | ✓ |
| Multi-write/read (B1, B2, B3) | Interleaved transactions | ✓ |

**Timing pattern đúng (quan trọng):**

```
❌ SAI: rd_en=1 → @posedge → data = rd_data   // ptr đã advance, data là slot tiếp theo!
✓ ĐÚNG:
    @(negedge rd_clk); #1; check rd_data;     // đọc TRƯỚC khi advance (combinational)
    rd_en = 1;                                 // set trên negedge
    @(posedge rd_clk);                         // advance tại posedge
    @(negedge rd_clk); rd_en = 0;
```

**Lý do ban đầu fail (6/17):**  
`rd_data` bị đọc SAU khi pointer advance → thấy dữ liệu của slot tiếp theo thay vì slot hiện tại.

**Signals cần xem nếu fail:**  
`wr_clk`, `rd_clk`, `wr_en`, `wr_data`, `rd_en`, `rd_data`, `rd_empty`  
Internal: `u_dut.wr_ptr_bin`, `u_dut.rd_ptr_bin`, `u_dut.wr_ptr_gray`, `u_dut.rd_ptr_gray`, `u_dut.wr_ptr_gray_sync1`, `u_dut.wr_ptr_gray_sync2`, `u_dut.mem[0]`, `u_dut.mem[1]`

**GTKWave tip cho CDC FIFO:**  
Tách wr_clk và rd_clk thành 2 clock group để dễ theo dõi crossing. Quan sát wr_ptr_gray → sync1 → sync2 để verify latency 2 cycle.

---

## Phase 3 — Pipeline CPU Integration Tests

**Testbench:** `integration/tb_pipeline_cpu.sv`  
**DUT:** `soc_top.sv` (full 7-stage pipeline, IMEM/DMEM, AXI/AHB stubs)  
**Halt mechanism:** `addi x31, x0, 1; ebreak` (PASS) hoặc `addi x31, x0, 0; ebreak` (FAIL)  
**Clock:** CPU = 1GHz, AHB = 500MHz  

### Kết Quả

| Program | Chức năng kiểm tra | Thời gian kết thúc | Kết quả |
|---------|--------------------|--------------------|---------|
| `prog_arithmetic` | ADD, SUB, ADDI, LUI, gap-4 RAW hazard | 94.5 ns | **PASS** |
| `prog_forwarding` | MEM1/MEM2/WB forwarding, load-use 1-cycle stall | 52.5 ns | **PASS** |
| `prog_load_store` | LW/SW/LB/SB/LH/SH, forwarding qua load | 78.5 ns | **PASS** |
| `prog_branch_jump` | BEQ/BNE/BLT/BGE/JAL/JALR, branch flush | 79.5 ns | **PASS** |
| `prog_csr` | CSRRW/CSRRS/CSRRC, CSR-use 3-cycle stall | 103.5 ns | **PASS** |
| `prog_ecall` | ECALL trap, mtvec, mepc, mcause, MRET, mstatus restore | 74.5 ns | **PASS** |
| `prog_interrupt_msi` | M-mode software interrupt, vectored handler, MIP/MIE clear | — | **PASS** |
| `prog_interrupt_mei` | M-mode external interrupt (AXI IRQ), vectored, MRET | — | **PASS** |
| `prog_load_fault` | Load access fault (bad addr → exception), mepc, mcause=5 | — | **PASS** |

### Cách Chạy

```bash
cd /home/baoslinux/riscv_soc_thesis/SIM

# Build tất cả programs và chạy 9 test
make p3_all

# Chạy từng program
make p3_arithmetic
make p3_forwarding
make p3_load_store
make p3_branch_jump
make p3_csr
make p3_ecall
make p3_msi
make p3_mei
make p3_load_fault

# Recompile nếu RTL thay đổi
rm -f integration/tb_pipeline_cpu.vvp && make p3_all
```

### Hướng Dẫn Mở Waveform

**Bước 1:** Tạo VCD dump:
```bash
# Cú pháp: make p3_wave_<tên_program>
make p3_wave_arithmetic
make p3_wave_forwarding
make p3_wave_load_store
make p3_wave_branch_jump
make p3_wave_csr
```
File VCD xuất ra tại `integration/wave_<tên>.vcd`.

**Bước 2:** Mở GTKWave:
```bash
gtkwave integration/wave_arithmetic.vcd &
```

**Bước 3:** Signal groups cần add vào GTKWave (drag từ hierarchy `tb_pipeline_cpu.u_soc`):

| Group | Signals |
|-------|---------|
| **Clock/Reset** | `clk_cpu`, `rst_n` |
| **PC / Fetch** | `u_soc.if1_pc`, `u_soc.imem_instr`, `u_soc.if2_instr` |
| **Stall/Flush** | `u_soc.stall_if1if2`, `u_soc.stall_if2id`, `u_soc.flush_idex`, `u_soc.bus_stall_req` |
| **Decode** | `u_soc.id_rs1_addr`, `u_soc.id_rs2_addr`, `u_soc.id_rd_addr` |
| **EX** | `u_soc.idex_rd_addr`, `u_soc.idex_wb_sel`, `u_soc.ex_alu_result`, `u_soc.ex_branch_taken` |
| **Forwarding** | `u_soc.u_fwd.fwd_sel_a`, `u_soc.u_fwd.fwd_sel_b` |
| **MEM1/MEM2** | `u_soc.exmem1_rd_addr`, `u_soc.exmem1_wb_sel`, `u_soc.mem1mem2_rd_addr` |
| **WB** | `u_soc.wb_reg_write`, `u_soc.wb_rd_addr`, `u_soc.wb_wr_data`, `u_soc.wb_ebreak` |
| **RF** | `u_soc.u_rf.registers[31]` (x31 = kết quả PASS/FAIL) |
| **CSR** *(prog_csr)* | `u_soc.u_zicsr.csr_rdata`, `u_soc.u_zicsr.mie`, `u_soc.u_zicsr.mstatus` |

**Tip debug theo loại lỗi:**

| Triệu chứng | Nguyên nhân thường gặp | Signal cần xem |
|-------------|------------------------|----------------|
| `x31=0`, kết thúc sớm | Branch nhảy vào fail path | `ex_branch_taken`, `fwd_sel_a/b`, `idex_rd_addr` |
| `x31=0`, timeout | Pipeline bị stall vô hạn | `bus_stall_req`, `stall_if1if2` |
| Kết quả ALU sai | Forwarding sai (sai nguồn) | `fwd_sel_a/b`, `exmem1_alu_result`, `mem1mem2_alu_result` |
| PC không nhảy đúng | Branch target sai | `if1_pc` sau khi `ex_branch_taken=1` |
| CSR value sai | CSR stall không đủ cycle | `idex_wb_sel`, `stall_if1if2`, `u_zicsr.csr_rdata` |

### Bugs RTL Tìm Được Trong Phase 3

#### Bug 1: Gap-4 RAW hazard — `register_file.sv`

**Triệu chứng:** `prog_arithmetic` FAIL, x31=0 tại t=27.5ns.

**Root cause:** Trong pipeline 7-tầng, WB (ghi vào RF tại posedge) và ID (đọc RF combinationally trong cùng chu kỳ) coincide tại gap=4. Non-blocking assignment NB khiến `registers[rd]` chưa cập nhật khi ID đọc trong cùng time-step → ID thấy giá trị cũ.

**Fix:** Thêm WBR bypass combinational trong `register_file.sv`:
```sv
logic we_valid;
assign we_valid = we && (rd_addr != 5'd0);
assign rs1_data = (rs1_addr == 5'd0)             ? 32'd0   :
                  (we_valid && rd_addr == rs1_addr) ? rd_data :
                  registers[rs1_addr];
```

---

#### Bug 2: Synchronous IMEM + Stall mismatch — `imem.sv`

**Triệu chứng:** `prog_forwarding` FAIL — một instruction bị mất, một instruction xuất hiện hai lần → branch target sai.

**Root cause:** IMEM là synchronous (1-cycle latency). Khi load-use stall xảy ra:
- `if1_if2_reg` bị freeze tại địa chỉ N.
- IMEM đã nhận PC=N+4 ở chu kỳ trước stall → tại posedge của stall cycle, IMEM latch output = instruction tại N+4.
- Khi stall giải phóng, IF2 nhận instruction[N+4] ghép với PC[N] (sai) → branch target = PC[N] + imm → sai.

**Fix:** Thêm input `stall` vào `imem.sv`; hold output khi `stall=1`:
```sv
always_ff @(posedge clk) begin
    if (!stall)
        instr_out <= mem[word_addr];
end
```
Wire `stall_if1if2` → `imem.stall` trong `soc_top.sv`.

---

#### Bug 3: CSR-use hazard stall quá muộn — `hazard_unit.sv`

**Triệu chứng:** `prog_csr` FAIL — `csrrw x3, mie, x2` (rd=old mie=0) theo sau bởi `bne x3, x0, fail`: BNE thấy x3=8 (sai) thay vì 0 → branch nhảy vào fail.

**Root cause:** CSR instruction (wb_sel=2'b11) chỉ xuất kết quả (old CSR value) tại WB stage qua `zicsr.csr_rdata`. Stall ban đầu chỉ kiểm tra khi CSR đang ở MEM1/MEM2 — nhưng lúc đó lệnh phụ thuộc đã vào EX và nhận MEM1 forwarding sai (ALU result, không phải old CSR value).

**Fix:** Thêm `csr_stall_ex` kiểm tra khi CSR đang ở **EX** (dùng `idex_wb_sel==2'b11`), stall lệnh kế trong ID TRƯỚC khi nó vào EX. Tổng 3-cycle stall:
- Cycle 1: CSR @ EX → stall dep. @ ID
- Cycle 2: CSR @ MEM1 → stall dep. @ ID  
- Cycle 3: CSR @ MEM2 → stall dep. @ ID
- Cycle 4: CSR @ WB → WB forwarding đúng → dep. vào EX với giá trị đúng

```sv
assign csr_stall_ex = (ex_wb_sel == 2'b11) && ex_reg_write &&
                      (ex_rd_addr != 5'd0) &&
                      ((ex_rd_addr == id_rs1_addr) || (ex_rd_addr == id_rs2_addr));
```

---

## Cấu Trúc File SIM/

```
SIM/
├── Makefile
├── TEST_LOG.md                  ← file này
├── link_default.ld              ← linker script cho RISC-V programs
├── unit/
│   ├── tb_alu.sv + .vvp
│   ├── tb_branch_comp.sv + .vvp
│   ├── tb_register_file.sv + .vvp
│   ├── tb_id_decoder.sv + .vvp
│   ├── tb_forwarding_unit.sv + .vvp
│   ├── tb_hazard_unit.sv + .vvp
│   └── tb_async_fifo.sv + .vvp
├── integration/
│   ├── tb_pipeline_cpu.sv + .vvp   ← Phase 3 testbench
│   └── wave_*.vcd                  ← tạo bởi make p3_wave_<prog>
├── system/                          ← Phase 4+5 (chưa có)
├── programs/
│   ├── prog_arithmetic.s + .hex    ← Phase 3 programs
│   ├── prog_forwarding.s + .hex
│   ├── prog_load_store.s + .hex
│   ├── prog_branch_jump.s + .hex
│   └── prog_csr.s + .hex
└── models/                          ← AXI/AHB slave models
```

---

## Bugs Tìm Thấy Và Đã Sửa

| Bug | Phát hiện trong | Mô tả | Fix |
|-----|-----------------|-------|-----|
| Icarus named task args | `tb_forwarding_unit.sv` | Icarus 12 không hỗ trợ `.portname(val)` trong task call | Dùng positional args |
| CDC read timing | `tb_async_fifo.sv` | Đọc `rd_data` sau posedge rd_en → ptr đã advance, đọc sai slot | Đọc `rd_data` trên negedge trước khi assert rd_en |
| Gap-4 RAW (WBR hazard) | `prog_arithmetic` | Pipeline 7-tầng: WB và ID xảy ra cùng posedge (gap=4); NB assignment khiến ID đọc giá trị cũ | Thêm WBR bypass combinational trong `register_file.sv` |
| Sync IMEM stall mismatch | `prog_forwarding` | Khi load-use stall, IMEM đọc địa chỉ tiếp theo trong khi `if1_if2_reg` bị freeze → IF2 nhận sai instruction sau khi stall giải phóng | Thêm input `stall` cho `imem.sv`; giữ output khi stall=1 |
| CSR-use hazard (late stall) | `prog_csr` | CSR instruction chỉ trả kết quả (old CSR value) tại WB qua `csr_rdata`. Stall phải kích hoạt khi CSR đang ở EX (không phải MEM1) để chặn lệnh kế TRƯỚC KHI vào EX với MEM1 forwarding sai | Thêm `csr_stall_ex` trong `hazard_unit.sv` (kiểm tra `idex_wb_sel==2'b11`); tổng stall 3 cycle (EX→MEM1→MEM2) |
| IMEM ghost instruction | `prog_ecall` | Sau `zicsr_flush` (ECALL/MRET/exception), IMEM (registered output) latch `mem[PC_cũ]` tại posedge flush → chu kỳ sau output là 0x00000000 (past end of binary) → `id_decoder` decode là `illegal_instr=1` → spurious exception ở WB ~7 cycle sau, ghi đè mepc=0 → handler loop vô hạn | Thêm input `flush` cho `imem.sv`; khi `flush=1` output NOP `32'h0000_0013` thay vì latch từ mem; wire `flush_if1if2` → `imem.flush` trong `soc_top.sv` |

---

## Phase Tiếp Theo

| Phase | Testbench | Mô tả |
|-------|-----------|-------|
| ~~4a~~ | ~~`integration/tb_axi_interface.sv`~~ | ~~AXI-Lite interface~~ | **DONE** |
| ~~4b~~ | ~~`integration/tb_ahb_interface.sv`~~ | ~~AHB-Lite interface với CDC FIFO~~ | **DONE** |
| ~~4c~~ | ~~`integration/tb_axi_full.sv`~~ | ~~AXI interface + interconnect + 3 SFRs~~ | **DONE** |
| ~~4d~~ | ~~`integration/tb_ahb_full.sv`~~ | ~~AHB interface via CDC + interconnect + 3 SFRs~~ | **DONE** |
| ~~**5**~~ | ~~`integration/tb_pipeline_cpu.sv` (4 programs)~~ | ~~Full SoC: CPU thực thi AXI/AHB SFR write/read + interrupt~~ | **DONE** |
| **6** | `system/tb_soc_top.sv` | Full SoC integration |
| **6** | `system/tb_compliance.sv` | RISC-V ACT compliance (ebreak + x31 halt mechanism) |

---

## Phase 4 — Bus Interface Unit Tests

**Ngày hoàn thành:** 2026-06-20

### Phase 4a: AXI-Lite Interface

**Testbench:** `integration/tb_axi_interface.sv`
**DUT:** `axi_interface.sv` + `models/axi_slave_model.sv`
**Clock:** 1GHz (đồng bộ, không CDC)

**Cơ chế slave model:**
- `AWREADY=WREADY=ARREADY=1` luôn (immediate handshake)
- Write: latch data với byte-enables tại posedge khi `AWVALID && WVALID`; assert `BVALID` chu kỳ tiếp
- Read: latch `ARADDR` tại posedge `ARVALID`; assert `RVALID + RDATA` chu kỳ tiếp
- Error injection: `inject_bresp_err` → `BRESP=2'b10`; `inject_rresp_err` → `RRESP=2'b10`

**Timing:** Write = 3 cycles (IDLE→WR_PHASE→WR_RESP+complete); Read = 3 cycles (IDLE→RD_ADDR→RD_DATA+complete)

**Kết quả: 49/49 PASS** (cập nhật sau khi bổ sung test WDATA alignment + address propagation)

| Group | Test | Kiểm tra | Kết quả |
|-------|------|---------|---------|
| 1 | T1-T2 | Word write: WSTRB=1111, resp_err=0 | PASS |
| 1 | T3-T4 | Word read-back: RDATA=DEADBEEF | PASS |
| 1 | T5-T8 | Second write+read (CAFEF00D) | PASS |
| 1 | T9-T10 | Half-word offset 0: WSTRB=0011 | PASS |
| 1 | T11-T12 | Half-word offset 2: WSTRB=1100 | PASS |
| 1 | T13-T20 | Byte writes offsets 0-3: WSTRB=0001/0010/0100/1000 | PASS |
| 1 | T21-T22 | BRESP error: resp_err=1 | PASS |
| 1 | T23-T24 | RRESP error: resp_err=1 | PASS |
| 2 | T25 | Word WDATA = req_wdata (no alignment) | PASS |
| 2 | T26 | Half-word WDATA replication: {low16, low16} | PASS |
| 2 | T27 | Half-word at offset 2: same replication | PASS |
| 2 | T28 | Byte WDATA replication: {byte×4} | PASS |
| 2 | T29 | Byte at offset 1: {byte×4} | PASS |
| 3 | T30 | AWADDR propagation = request address | PASS |
| 3 | T31 | ARADDR propagation = request address | PASS |
| 4 | T32-T33 | Sequential write+read (new slot) | PASS |

**Lệnh chạy:**
```bash
make integ_axi
```

---

### Phase 4b: AHB-Lite Interface

**Testbench:** `integration/tb_ahb_interface.sv`
**DUT:** `ahb_interface.sv` + `async_fifo_depth2` (×2) + `models/ahb_slave_model.sv`
**Clock:** 1GHz (1GHz write side) ↔ CDC ↔ 500MHz (AHB domain)

**Cấu trúc testbench:**
- Request FIFO (67-bit, DATA_WIDTH=67): `clk_1g` write side → `clk_ahb` read side
- Response FIFO (33-bit, DATA_WIDTH=33): `clk_ahb` write side → `clk_1g` read side
- AHB slave: 2-state FSM (IDLE/DATA), `HREADY=0` trong 1 cycle khi `insert_wait=1`, memory array 8×32-bit, error injection
- Capture AHB signals tại `posedge clk_ahb` khi `HTRANS=2'b10` (address phase) và khi `HREADY=1` (data completion)

**FIFO payload:**
- Req: `{addr[31:0], wdata[31:0], write[0], size[1:0]}` = 67 bits — khớp `req_rd_data[66:35/34:3/2/1:0]` trong `ahb_interface.sv`
- Resp: `{HRESP[0], HRDATA[31:0]}` = 33 bits

**Latency 1GHz→resp:** ~12 chu kỳ 1GHz (req CDC 4cy + AHB txn 2×500MHz + resp CDC 4cy)

**Kết quả: 29/29 PASS** (cập nhật sau khi bổ sung wait state + sequential + HADDR tests)

**Bug phát hiện trong slave model cũ:** Slave ban đầu dùng `HTRANS[1]` để track data_phase, nhưng khi `insert_wait=1` (HREADY=0), `data_phase←0` ngay ở cycle đầu của data phase (vì HTRANS=IDLE) → slave mất track, không thể hoàn thành transaction. Fix: dùng 2-state FSM IDLE/DATA, data_phase chỉ cleared khi `HREADY=1` trong DATA state.

| Group | Test | Kiểm tra | Kết quả |
|-------|------|---------|---------|
|------|---------|---------|
| T1-T4 | Word write: err=0, HSIZE=2, HWRITE=1, HWDATA correct | PASS |
| T5-T7 | Word read-back: err=0, RDATA=AABBCCDD, HWRITE=0 | PASS |
| T8-T9 | Half-word write: err=0, HSIZE=1 | PASS |
| 1 | T1-T4 | Word write: err, HSIZE=2, HWRITE=1, HWDATA | PASS |
| 1 | T5-T7 | Word read-back: err, RDATA, HWRITE=0 | PASS |
| 1 | T8-T9 | Half-word write: err, HSIZE=1 | PASS |
| 1 | T10-T11 | Byte write: err, HSIZE=0 | PASS |
| 1 | T12 | HRESP error: resp err=1 | PASS |
| 1 | T13-T15 | Write+read (DEAD1234) | PASS |
| 2 | T16-T18 | Wait state write: err=0, HSIZE correct, HWDATA captured at HREADY=1 | PASS |
| 2 | T19-T20 | Read back after wait-state write: data integrity | PASS |
| 2 | T21-T22 | Wait state read: err=0, HRDATA correct | PASS |
| 2 | T23 | HADDR propagation: cap_haddr = request address | PASS |
| 2 | T24 | HRESP error + wait state: err=1 still propagates | PASS |
| 3 | T25-T28 | 2 sequential writes + 2 read-backs: data independent | PASS |
| 3 | T29 | req_rd_en idle: goes 0 when no request pending | PASS |

**Lệnh chạy:**
```bash
make integ_ahb
```

---

### Phase 4c: AXI Full Path (Interface + Interconnect + 3 SFRs)

**Testbench:** `integration/tb_axi_full.sv`
**DUT:** `axi_interface.sv` + `axi_interconnect.sv` + 3×`axi_sfr.sv`
**Clock:** 1GHz (fully synchronous)

**Cấu hình:**
- Slave 0 base: `0x2000_0000` (addr[27:12] == 0x0000)
- Slave 1 base: `0x2000_1000` (addr[27:12] == 0x0001)
- Slave 2 base: `0x2000_2000` (addr[27:12] == 0x0002)

**Key insight về địa chỉ:** `addr[27:12] == N` tương ứng địa chỉ offset `N << 12` từ bus base. Do đó Slave 1 tại `0x2000_1000` (không phải `0x2001_0000`).

**Kết quả: 40/40 PASS**

| Group | Tests | Kiểm tra |
|-------|-------|---------|
| 1 (addr decode) | T1-T9 | Write+read-back lên mỗi slave; verify đúng slave nhận data |
| 2 (IRQ) | T10-T21 | Set/clear REG7[0] trên từng slave → axi_irq OR output |
| 3 (multi-reg) | T22-T30 | 3 reg writes + read-backs trên Slave 0 |
| 4 (isolation) | T31-T40 | Write slave 1 → read slave 2 = 0; cross-slave separation |

**Lệnh chạy:**
```bash
make integ_axi_full
```

---

### Phase 4d: AHB Full Path (Interface via CDC + Interconnect + 3 SFRs)

**Testbench:** `integration/tb_ahb_full.sv`
**DUT:** `ahb_interface.sv` + 2×`async_fifo_depth2` + `ahb_interconnect.sv` + 3×`ahb_sfr.sv`
**Clock:** 1GHz (CPU side) ↔ CDC ↔ 500MHz (AHB domain)

**Cấu hình:**
- Slave 0 base: `0x3000_0000` (addr[27:12] == 0x0000)
- Slave 1 base: `0x3000_1000` (addr[27:12] == 0x0001)
- Slave 2 base: `0x3000_2000` (addr[27:12] == 0x0002)

**Kết quả: 35/35 PASS**

| Group | Tests | Kiểm tra |
|-------|-------|---------|
| 1 (addr decode) | T1-T6 | Write+read-back lên mỗi slave; verify đúng slave nhận data |
| 2 (IRQ) | T7-T15 | Set/clear REG7[0] trên từng slave → ahb_irq OR output; IRQ settle qua 500MHz domain cần 2 chu kỳ AHB |
| 3 (multi-reg) | T16-T22 | 2 reg writes + read-backs trên Slave 0 |
| 4 (isolation) | T23-T35 | Write slave 1 → read slave 2 = 0; cross-slave separation |

**Lệnh chạy:**
```bash
make integ_ahb_full
```

---

## Nhật Ký Session 2026-06-20 — Phase 5: Full SoC Integration (CPU + AXI/AHB)

### Bug Phát Hiện: Simultaneous bus_stall + load_use_stall → LW Bị Cancel

#### Triệu chứng

`prog_axi_sfr` và `prog_ahb_sfr` FAIL với `x31=0` ngay tại `bne` đầu tiên sau `lw` (AXI/AHB read). `x7 = 0x00000000` dù AXI write đã thành công.

#### Root cause

Khi `sw` đang ở MEM1 (bus_stall=1), `lw` đang ở EX và `bne` đang ở ID:
- `bus_stall_req=1` → `stall_id_ex=1` (hold ID/EX)  
- `load_use_stall=1` (lw@EX, bne@ID, cùng rd) → `flush_id_ex=1`  

Trong `id_ex_reg.sv`: `else if (flush)` được kiểm trước `else if (!stall)` → **flush thắng**, ID/EX bị clear thành NOP → **lw bị hủy khỏi pipeline**. AXI read (AR handshake) không bao giờ xảy ra. `x7 = 0`.

#### Fix: `hazard_unit.sv` line 124

```sv
// TRƯỚC:
assign flush_id_ex = zicsr_flush | fetch_stall | ctrl_flush;

// SAU:
assign flush_id_ex = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush;
```

**Logic sau khi fix:**
1. Khi `bus_stall=1` và `load_use=1` đồng thời: `flush_id_ex=0` (suppressed). `lw` giữ ở EX.
2. Khi `sw` hoàn thành (`bus_stall→0`): `fetch_stall & ~bus_stall_req = 1` → `flush_id_ex=1` fire đúng. `lw` advance từ EX → MEM1 (bắt đầu AXI read stall). Bubble ở EX. `bne` giữ ở ID.
3. Khi AXI read hoàn thành: `lw` ở MEM2 (có data). `bne` từ ID → EX. **MEM2 forwarding** cấp `x7` đúng → branch pass. ✓

**Kiểm tra không phá vỡ Phase 3:** `make p3_all` → 9/9 PASS sau khi fix.

---

### Phase 5: Full SoC Integration Tests

**Testbench:** `integration/tb_pipeline_cpu.sv` (tái dụng tb từ Phase 3)
**DUT:** `soc_top.sv` (full SoC — CPU + AXI + AHB + CDC)
**Lệnh:** `make p5_all`

**Kết quả: 4/4 PASS**

| Program | Mô tả | Thời gian | Kết quả |
|---------|-------|-----------|---------|
| `prog_axi_sfr.s` | CPU write/read AXI SFR (3 slaves, cross-isolation) | 75.5 ns | **PASS** |
| `prog_ahb_sfr.s` | CPU write/read AHB SFR (3 slaves, cross-isolation) via CDC | 149.5 ns | **PASS** |
| `prog_axi_irq.s` | AXI SFR REG7[0]=1 → axi_irq → MEI trap → handler verify + clear | 60.5 ns | **PASS** |
| `prog_ahb_irq.s` | AHB SFR REG7[0]=1 → 2-FF sync → ahb_irq → MEI trap → handler verify + clear | 74.5 ns | **PASS** |

**4/4 PASS — Phase 5 hoàn thành**

**Chi tiết kiểm tra:**

| Program | Các điều kiện được verify |
|---------|--------------------------|
| `prog_axi_sfr` | Write 0xABCD1234 → read-back == 0xABCD1234; multi-slave isolation; 3 slaves độc lập |
| `prog_ahb_sfr` | Write/read qua CDC FIFO (1GHz→500MHz→1GHz); AHB wait-state handled bởi bus_stall |
| `prog_axi_irq` | mcause == 0x8000_000B; mstatus.MIE == 0 trong handler; clear IRQ; MRET về pass |
| `prog_ahb_irq` | Như trên + 2-FF synchronizer latency handled bởi 5 NOP sau SW |

**Files cập nhật:**
- `RTL/hazard_unit.sv` — Fix: suppress fetch_stall flush khi bus_stall_req active
- `SIM/programs/prog_axi_sfr.s` — Phase 5 program (mới)
- `SIM/programs/prog_ahb_sfr.s` — Phase 5 program (mới)
- `SIM/programs/prog_axi_irq.s` — Phase 5 program (mới)
- `SIM/programs/prog_ahb_irq.s` — Phase 5 program (mới)
- `SIM/Makefile` — p5_axi_sfr, p5_ahb_sfr, p5_axi_irq, p5_ahb_irq, p5_all targets

---

## Nhật Ký Session 2026-06-20 — Phase 6: System Test + Compliance Framework

### Phase 6a: System Batch Test

Testbench `system/tb_soc_top.sv` chạy toàn bộ 16 programs (Phase 3 + 5 + 6) qua `soc_top` với reset giữa mỗi chương trình. DMEM được clear giữa mỗi run để isolation.

**Kết quả `make system`:**

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

### Phase 6b: Compliance Programs

3 programs mới kiểm tra coverage ISA bị thiếu trong Phase 3:

| Program | Coverage |
|---------|----------|
| `prog_rv32i_shifts` | SLL/SRL/SRA/SLLI/SRLI/SRAI với shift=0, shift=31, sign-extension, amount mod 32 |
| `prog_rv32i_compare` | SLT/SLTU/SLTI/SLTIU với 0xFFFFFFFF (signed -1 vs unsigned max); AUIPC |
| `prog_dmem_endurance` | 64 consecutive SW+LW, xác nhận toàn bộ DMEM address range |

**Kết quả `make p6_compliance`:**
```
=== prog_rv32i_shifts ===  TEST_PASS
=== prog_rv32i_compare ===  TEST_PASS
=== prog_dmem_endurance ===  TEST_PASS
```

**Files thêm mới:**
- `SIM/programs/prog_rv32i_shifts.s`
- `SIM/programs/prog_rv32i_compare.s`
- `SIM/programs/prog_dmem_endurance.s`
- `SIM/system/tb_soc_top.sv` — batch testbench 16 programs
- `SIM/system/tb_compliance.sv` — compliance framework (TEST_PASS/TEST_FAIL output)
- `SIM/scripts/run_one_test.sh` — ELF→hex→simulate runner
- `SIM/Makefile` — `system`, `p6_compliance`, `compliance_compile`, `compliance`, `p6_all` targets
