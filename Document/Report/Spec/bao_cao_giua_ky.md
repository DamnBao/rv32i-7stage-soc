# BÁO CÁO GIỮA KỲ KHÓA LUẬN TỐT NGHIỆP

**Tên đề tài:** Thiết kế RISC-V kết nối AMBA AXI/AHB Bus để truy cập ngoại vi

**Sinh viên:** DamnBao

**Ngày báo cáo:** 29/06/2026

---

## 1. GIỚI THIỆU ĐỀ TÀI

### 1.1 Mục tiêu

Đề tài thiết kế và kiểm chứng một vi xử lý RISC-V 32-bit (RV32I + Zicsr) tích hợp trên chip (SoC), kết nối với ngoại vi qua hai chuẩn bus AMBA: **AXI-Lite** (đồng bộ với miền clock CPU) và **AHB-Lite** (bất đồng bộ qua CDC, thuộc miền clock riêng biệt). Thiết kế có **hai miền clock độc lập**: miền CPU và miền AHB, kết nối với nhau qua cơ chế Clock Domain Crossing (CDC). Toàn bộ RTL viết bằng **SystemVerilog synthesizable**, mô phỏng bằng **Icarus Verilog 12**, kiểm chứng hình thức bằng **SymbiYosys + Z3**.

### 1.2 Phạm vi và nội dung công việc

Các công việc thực hiện trong khóa luận bao gồm:

1. **Thiết kế RTL toàn bộ SoC:** CPU pipeline 7 tầng (IF1→IF2→ID→EX→MEM1→MEM2→WB), hazard unit, forwarding unit, Zicsr (CSR + exception/interrupt), PLIC, branch predictor, hai bus interface AXI/AHB, CDC FIFO, interconnect 1-to-3, và các ngoại vi thực tế (GPIO, Timer, UART).

2. **Kiểm tra chức năng đa tầng (DV):**
   - Unit test từng module với directed testbench
   - Integration test theo từng lớp bus (AXI standalone → AHB+CDC standalone → Full path với SFR thực)
   - System test qua `soc_top` đầy đủ với các chương trình assembly thực tế
   - Kiểm tra compliance RV32I theo bộ test chính thức riscv-arch-test
   - Kiểm chứng hình thức (Formal Verification) với SymbiYosys k-induction

3. **Tài liệu:** Viết báo cáo khóa luận (6 chương LaTeX), specification, testplan, testresult.

| Hạng mục | Mô tả |
|----------|-------|
| ISA | RISC-V RV32I + Zicsr (không có M/F/D extension) |
| Pipeline | 7 tầng in-order: IF1→IF2→ID→EX→MEM1→MEM2→WB |
| Clock domains | 2 miền clock độc lập (CPU domain và AHB domain) |
| Bộ nhớ | IMEM 64KB + DMEM 64KB (on-chip SRAM) |
| Bus | AXI-Lite × 3 slave + AHB-Lite × 3 slave |
| Ngoại vi | GPIO (AXI + AHB), Timer (AXI), UART 8N1 (AXI) |
| Interrupt | PLIC 6 nguồn, 3-bit priority, vectored mode |

---

## 2. CƠ SỞ LÝ THUYẾT

### 2.1 Kiến trúc RISC-V RV32I

RISC-V là kiến trúc tập lệnh (ISA) mã nguồn mở, thiết kế theo triết lý RISC với các đặc điểm nổi bật:

- **32 thanh ghi** dùng chung (x0–x31), x0 hardwired = 0 không thể ghi
- **6 định dạng lệnh:** R, I, S, B, U, J — mã hóa cố định 32-bit, không có lệnh có độ dài thay đổi
- **40 lệnh cơ bản RV32I** bao phủ số học, logic, load/store, branch, jump; cộng thêm phần mở rộng Zicsr (6 lệnh CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI)
- **Little-endian**, địa chỉ byte, load/store architecture (không có memory operand trong ALU instruction)

---

**[HÌNH 1 — Sơ đồ các định dạng lệnh RV32I: R / I / S / B / U / J encoding]**

```
+----------------------------------------------------------+
|                                                          |
|                   CHÈN HÌNH TẠI ĐÂY                     |
|         (RV32I instruction format encoding —             |
|          R / I / S / B / U / J với bit fields)          |
|                                                          |
+----------------------------------------------------------+
```

---

### 2.2 Pipeline 7 Tầng và các thành phần CPU

Pipeline in-order 7 tầng cho phép thực thi lý tưởng một lệnh mỗi chu kỳ (CPI lý tưởng = 1):

| Tầng | Chức năng chính |
|------|----------------|
| IF1 | Tính PC tiếp theo, tra BTB branch predictor |
| IF2 | Nhận instruction từ IMEM (registered output, 1-cycle latency) |
| ID | Giải mã lệnh, đọc register file |
| EX | ALU, Branch Comparator, Address Adder, Forwarding MUX |
| MEM1 | Address decode → DMEM / AXI / AHB / PLIC |
| MEM2 | Thu kết quả bus, load data alignment, bus error → exception |
| WB | Ghi kết quả về register file |

---

**[HÌNH 2 — Sơ đồ pipeline 7 tầng với forwarding paths, hazard unit và branch predictor]**

```
+----------------------------------------------------------+
|                                                          |
|                   CHÈN HÌNH TẠI ĐÂY                     |
|    (Pipeline 7 tầng: IF1→IF2→ID→EX→MEM1→MEM2→WB        |
|     với forwarding arrows, stall/flush control,          |
|     branch predictor lookup tại IF1, update tại EX)     |
|                                                          |
+----------------------------------------------------------+
```

---

**Hazard handling tổng hợp:**

| Loại Hazard | Cơ chế xử lý | Chu kỳ stall |
|-------------|-------------|-------------|
| RAW Gap-1/2/3 | Forwarding từ MEM1/MEM2/WB về đầu vào EX | 0 |
| RAW Gap-4 | WBR bypass trong register_file | 0 |
| Load-use | Hazard unit stall IF1..ID, bubble EX | 1 |
| CSR-use | Stall tùy khoảng cách giữa CSR write và đọc | 1–3 |
| Branch misprediction | Flush IF1/IF2 và IF2/ID (bp_mismatch) | 2 slot flushed |
| Bus stall | Stall toàn pipeline đến khi bus hoàn tất | N (variable) |

**Branch Predictor (2-bit BHT + BTB):**
Bộ dự đoán nhánh 2-level gồm 16-entry 2-bit saturating counter BHT (Branch History Table) và BTB (Branch Target Buffer). Dự đoán tại IF1 (combinational lookup), cập nhật tại EX khi có kết quả thực tế. Khi dự đoán sai (`bp_mismatch`), hazard_unit phát flush 2 pipeline slot.

**PLIC — Platform-Level Interrupt Controller:**
PLIC (theo spec SiFive) nhận ngắt từ 6 nguồn (3 từ AXI, 3 từ AHB), thực hiện priority arbitration (3-bit priority, loại trừ source có priority = 0) và threshold filtering. Kết quả là tín hiệu `meip_in` gửi về Zicsr. IRQ từ ngoại vi AHB được đồng bộ hóa qua `irq_sync2ff` (2-FF synchronizer, một instance độc lập mỗi nguồn) trước khi vào PLIC, để tránh metastability khi vượt biên giới clock domain.

**Zicsr — Control & Status Registers:**
6 CSR được implement: `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`. Hỗ trợ **vectored interrupt mode** (mỗi nguyên nhân một vector offset riêng), **precise exception** (pipeline không commit exception trong khi bus transaction đang in-flight), và xử lý `ECALL` / `MRET`.

### 2.3 AMBA AXI-Lite và AHB-Lite

**AXI-Lite (AMBA 4):** Giao thức handshake 5 kênh độc lập: Write Address (AW), Write Data (W), Write Response (B), Read Address (AR), Read Data (R). Mỗi kênh dùng cặp `VALID/READY` — nguồn phát VALID, bên nhận phát READY; transaction hoàn tất khi cả hai cùng HIGH. AXI-Lite phù hợp cho thanh ghi điều khiển (SFR) vì đơn giản và đồng bộ với miền clock CPU.

**AHB-Lite (AMBA 3):** Giao thức pipelined 2-phase: address phase (HTRANS, HADDR, HWRITE, HSIZE) và data phase (HWDATA/HRDATA, HREADY, HRESP). Shared bus với `HSEL` per-slave và `HREADYOUT` handshake. Hoạt động ở miền clock AHB riêng biệt.

**Clock Domain Crossing (CDC):** Do AHB hoạt động ở miền clock riêng biệt (thấp hơn CPU), tất cả dữ liệu vượt biên giới được truyền qua **Dual Async FIFO (depth=2)** sử dụng **Gray code pointer** để tránh metastability:

- **Request FIFO** (CPU clock → AHB clock): 67-bit = Address(32) + WriteData(32) + Control(3: R/W, HSIZE)
- **Response FIFO** (AHB clock → CPU clock): 33-bit = ReadData(32) + HRESP(1)

---

**[HÌNH 3 — Sơ đồ tổng thể SoC: CPU + AXI + AHB + CDC FIFO + PLIC + Peripherals]**

```
+----------------------------------------------------------+
|                                                          |
|                   CHÈN HÌNH TẠI ĐÂY                     |
|    (SoC block diagram: soc_top với CPU pipeline,         |
|     AXI interconnect + 3 AXI slaves,                    |
|     AHB interconnect + CDC FIFO + 3 AHB slaves,         |
|     PLIC 6 nguồn, Zicsr, IRQ sync2ff)                   |
|                                                          |
+----------------------------------------------------------+
```

---

### 2.4 SFR Standard Register Map

Mọi ngoại vi trong thiết kế tuân thủ một chuẩn register map thống nhất (lấy cảm hứng từ OpenTitan), đảm bảo khả năng cắm vào `soc_top` mà không cần sửa RTL:

| Offset | Tên | Access | Mô tả |
|--------|-----|--------|-------|
| 0x00 | CTRL | RW | bit[0]=enable; bits[31:1]=specific |
| 0x04 | STATUS | RO | Trạng thái read-only |
| 0x08 | INTR_ENABLE | RW | Mask từng nguồn IRQ |
| 0x0C | INTR_STATE | RW1C | Pending flags — ghi 1 để clear |
| 0x10 | INTR_TEST | WO | Force-set INTR_STATE (debug/test) |
| 0x14–0x1C | DATA0–DATA2 | RW | General-purpose (peripheral-specific) |
| 0xFC | PERIPH_ID | RO | Peripheral identifier hardcoded |

**IRQ rule:** `irq = |(INTR_STATE & INTR_ENABLE)` — IRQ chỉ active khi có pending flag AND được enable.

---

## 3. TIẾN ĐỘ THỰC HIỆN — RTL DESIGN

### 3.1 Tổng quan

Toàn bộ **38 module SystemVerilog** (~6.318 dòng) trong thư mục `RTL/` đã hoàn thành synthesis-clean và đi vào simulation đầy đủ.

---

**[HÌNH 4 — Memory map địa chỉ và sơ đồ Address Decoder tại MEM1]**

```
+----------------------------------------------------------+
|                                                          |
|                   CHÈN HÌNH TẠI ĐÂY                     |
|    (Memory map: IMEM 0x0000_0000–0x0000_FFFF,           |
|     DMEM 0x0001_0000–0x0001_FFFF,                       |
|     PLIC 0x0C00_0000–0x0CFF_FFFF,                       |
|     AXI  0x2000_0000–0x2FFF_FFFF,                       |
|     AHB  0x3000_0000–0x3FFF_FFFF)                       |
|                                                          |
+----------------------------------------------------------+
```

---

### 3.2 Các nhóm module RTL

**Nhóm CPU Core:**

| Nhóm | Các module | Số file | Trạng thái |
|------|-----------|---------|-----------|
| Pipeline stages (7 tầng) | `if1_stage`, `if2_stage`, `id_decoder`, `register_file`, `ex_stage`, `mem1_stage`, `mem2_stage`, `wb_stage` | 8 | ✅ Hoàn thành |
| Pipeline registers (6 cặp) | `if1_if2_reg`, `if2_id_reg`, `id_ex_reg`, `ex_mem1_reg`, `mem1_mem2_reg`, `mem2_wb_reg` | 6 | ✅ Hoàn thành |
| Sub-units trong EX stage | `alu`, `branch_comp`, `addr_adder`, `forwarding_unit` | 4 | ✅ Hoàn thành |
| Hazard & Branch Predict | `hazard_unit`, `branch_predictor` | 2 | ✅ Hoàn thành |
| Memory | `imem` (64KB + NOP-on-flush), `dmem` (64KB) | 2 | ✅ Hoàn thành |
| Interrupt & Exception | `zicsr`, `plic` | 2 | ✅ Hoàn thành |
| Reset | `reset_sync` (async-assert / sync-deassert) | 1 | ✅ Hoàn thành |

**Nhóm Bus Infrastructure:**

| Nhóm | Các module | Số file | Trạng thái |
|------|-----------|---------|-----------|
| AXI-Lite | `axi_interface` (master FSM), `axi_interconnect` (1-to-3 decode + IRQ OR) | 2 | ✅ Hoàn thành |
| AHB-Lite | `ahb_interface` (master FSM), `ahb_interconnect` (1-to-3 HSEL) | 2 | ✅ Hoàn thành |
| CDC & Sync | `async_fifo` (depth=2, Gray code), `irq_sync2ff` (2-FF per-source) | 2 | ✅ Hoàn thành |

**Nhóm Ngoại vi (External Peripherals):**

| Module | Bus | Chức năng | Trạng thái |
|--------|-----|-----------|-----------|
| `axi_sfr` / `ahb_sfr` | AXI / AHB | Generic SFR (Standard Register Map) | ✅ Hoàn thành |
| `gpio_sfr` | AXI-Lite | GPIO: output drive, input capture, edge-detect IRQ | ✅ Hoàn thành |
| `timer_axi` | AXI-Lite | Timer: prescaler + compare-match IRQ, self-clearing | ✅ Hoàn thành |
| `gpio_ahb` | AHB-Lite | GPIO AHB: 2-FF input sync, edge-detect, OE control | ✅ Hoàn thành |
| `uart_axi` | AXI-Lite | UART 8N1: TX/RX 4-state FSM, baud divider, dual IRQ | ✅ Hoàn thành |
| `soc_top` | — | Top-level integration (1.275 dòng) | ✅ Hoàn thành |

**→ 38/38 module hoàn thành (100% RTL)**

---

## 4. TIẾN ĐỘ THỰC HIỆN — DESIGN VERIFICATION (DV)

### 4.1 Chiến lược kiểm tra

Chiến lược DV được tổ chức thành 5 tầng từ thấp lên cao:

```
         ┌──────────────┐
         │   FORMAL     │  ← SymbiYosys k-induction (13 jobs, 30+ assertions)
         └──────────────┘
       ┌──────────────────┐
       │   COMPLIANCE     │  ← riscv-arch-test 37/37 PASS
       └──────────────────┘
     ┌──────────────────────┐
     │   SYSTEM TEST        │  ← 34 assembly programs qua soc_top đầy đủ
     └──────────────────────┘
   ┌──────────────────────────┐
   │   INTEGRATION TEST       │  ← 6 testbench, 167 cases
   └──────────────────────────┘
 ┌──────────────────────────────┐
 │        UNIT TESTS            │  ← 16 testbench, ~524 cases
 └──────────────────────────────┘
```

### 4.2 Unit Tests

| Testbench | Module được test | Cases | Kết quả |
|-----------|----------------|-------|---------|
| `tb_alu` | `alu` | 48 | ✅ PASS |
| `tb_branch_comp` | `branch_comp` | 24 | ✅ PASS |
| `tb_register_file` | `register_file` | 72 | ✅ PASS |
| `tb_id_decoder` | `id_decoder` | 48 | ✅ PASS |
| `tb_forwarding_unit` | `forwarding_unit` | 29 | ✅ PASS |
| `tb_hazard_unit` | `hazard_unit` | 73 | ✅ PASS |
| `tb_async_fifo` | `async_fifo` | 12 | ✅ PASS |
| `tb_plic` | `plic` | 31 | ✅ PASS |
| `tb_ex_stage` | `ex_stage` | 23 | ✅ PASS |
| `tb_irq_sync2ff` | `irq_sync2ff` | 10 | ✅ PASS |
| `tb_gpio_sfr` | `gpio_sfr` | 22 | ✅ PASS |
| `tb_zicsr` | `zicsr` | 38 | ✅ PASS |
| `tb_branch_predictor` | `branch_predictor` | 23 | ✅ PASS |
| `tb_timer_axi` | `timer_axi` | 23 | ✅ PASS |
| `tb_gpio_ahb` | `gpio_ahb` | 21 | ✅ PASS |
| `tb_uart_axi` | `uart_axi` | 27 | ✅ PASS |
| **Tổng** | **16 testbench** | **~524** | **✅ 100% PASS** |

### 4.3 Integration Tests

Testbench integration được tổ chức theo ba lớp từ đơn giản đến phức tạp:

**Lớp 1 — Bus interface đơn lẻ với slave model mô phỏng:**

| Testbench | Cấu hình DUT | Nội dung kiểm tra | Kết quả |
|-----------|-------------|-------------------|---------|
| `tb_axi_interface` | `axi_interface` + AXI slave model | Write/Read transaction hoàn chỉnh; VALID không được deassert trước READY (AXI §A3.2.1); BRESP=SLVERR và RRESP=SLVERR propagate đúng; back-to-back transaction | ✅ 49/49 |
| `tb_ahb_interface` | `ahb_interface` + Async FIFO × 2 + AHB slave model | Write/Read qua CDC; Gray-code pointer không có glitch; HRESP=ERROR propagate về CPU; pipeline 2-phase address/data đúng thứ tự; response latency đo được | ✅ 29/29 |

**Lớp 2 — Full bus path: interface + interconnect + SFR thực:**

| Testbench | Cấu hình DUT | Nội dung kiểm tra | Kết quả |
|-----------|-------------|-------------------|---------|
| `tb_axi_full` | `axi_interface` + `axi_interconnect` + 3×`axi_sfr` | Address decode đúng slave theo `addr[27:12]`; ghi slave A không ảnh hưởng slave B/C; INTR_STATE set/clear qua INTR_TEST; IRQ masking qua INTR_ENABLE; PERIPH_ID readback đúng | ✅ 47/47 |
| `tb_ahb_full` | `ahb_interface` + CDC FIFO × 2 + `ahb_interconnect` + 3×`ahb_sfr` | Toàn bộ CDC path (Request + Response FIFO); per-slave HSEL exclusive; HREADY handshake; SFR Standard Map đầy đủ qua AHB | ✅ 38/38 |

**Lớp 3 — Bus error injection qua soc_top đầy đủ:**

| Testbench | Lỗi được inject | Kết quả kiểm tra | Kết quả |
|-----------|----------------|-----------------|---------|
| `tb_soc_bus_err` | AXI BRESP=SLVERR (store fault); AXI RRESP=SLVERR (load fault) | `mcause`=7 (Store/AMO Access Fault) và `mcause`=5 (Load Access Fault) được set đúng; `mepc` trỏ đúng lệnh gây lỗi; handler nhận đúng và MRET trả về | ✅ 2/2 |
| `tb_soc_ahb_err` | AHB HRESP=ERROR (store fault); AHB HRESP=ERROR (load fault) | Như trên nhưng qua CDC path; lỗi được truyền trong Response FIFO (HRESP bit) về CPU | ✅ 2/2 |

### 4.4 System Tests (Assembly Programs qua soc_top)

34 assembly programs biên dịch bằng `riscv64-unknown-elf-gcc 13.2.0`, chạy toàn bộ qua `soc_top` trong `tb_pipeline_cpu.sv`:

| Nhóm | Programs | Nội dung kiểm tra | Kết quả |
|------|---------|-------------------|---------|
| **CPU cơ bản** | `prog_arithmetic`, `prog_forwarding`, `prog_load_store`, `prog_branch_jump` | Phép tính RV32I, forwarding gap 1–4, load/store B/H/W signed/unsigned, branch/JAL/JALR | ✅ 4/4 |
| **Exception & Interrupt** | `prog_ecall`, `prog_interrupt_msi`, `prog_interrupt_mei`, `prog_load_fault`, `prog_misaligned`, `prog_mtip` | ECALL→handler→MRET; software interrupt (MSIP); external interrupt (AXI IRQ); load access fault; misaligned address exception; MTIP timer interrupt | ✅ 6/6 |
| **CSR** | `prog_csr`, `prog_csr_hazard` | CSR CSRRW/CSRRS/CSRRC/immediate variants; CSR-use stall gaps 0–4 | ✅ 2/2 |
| **Bus AXI** | `prog_axi_sfr`, `prog_axi_irq`, `prog_bus_err` | SFR write/read qua AXI; IRQ via INTR_TEST → PLIC → handler; SLVERR → exception | ✅ 3/3 |
| **Bus AHB** | `prog_ahb_sfr`, `prog_ahb_irq`, `prog_oob_addr` | SFR write/read qua CDC; IRQ via INTR_TEST; OOB address → access fault | ✅ 3/3 |
| **PLIC** | `prog_plic_basic`, `prog_plic_priority`, `prog_plic_threshold` | Claim/complete flow; priority arbitration giữa 2 nguồn đồng thời; threshold filtering | ✅ 3/3 |
| **Ngoại vi thực** | `prog_timer`, `prog_gpio_ahb`, `prog_uart` | Timer compare-match IRQ → handler; GPIO AHB loopback 0x55 + edge IRQ; UART TX/RX loopback 0x55 + dual IRQ (TX-done + RX-ready) | ✅ 3/3 |
| **Branch Predictor** | `prog_branch_pred` (4 sub-tests) | Warm-up loop BHT (81.8% hit); BTB cold miss; nested loop; adversarial alternating pattern (47.6%) | ✅ 1/1 |
| **Metrics** | `prog_forwarding` (CPI), `prog_fib`, `prog_ahb_sfr` (latency) | CPI=1.100; Fibonacci CPI=1.182 (80% branch hit); AHB latency avg=9.4 CPU cycles | ✅ 3/3 |
| **Compliance prep** | `prog_rv32i_shifts`, `prog_rv32i_compare`, `prog_dmem_endurance`, `prog_fence_wfi` | Shift corner cases; compare ops; DMEM endurance 1000 write/read; FENCE/WFI xử lý như NOP | ✅ 4/4 |

### 4.5 RV32I Formal Compliance (riscv-arch-test)

Bộ test compliance chính thức RISC-V Foundation (old-framework-2.x), so sánh signature memory output với reference model:

| Kết quả | Số test | Ghi chú |
|---------|---------|---------|
| ✅ PASS | 37 | Tất cả test RV32I + Zicsr nằm trong phạm vi IMEM 64KB |
| ⚠️ SKIP | 1 (`jal-01`) | Framework sinh binary ~1.7MB để test toàn bộ jump offset range ±1MB. IMEM thiết kế là 64KB (phù hợp với mục tiêu on-chip SRAM thực tế). Đây là giới hạn kích thước IMEM testbench, không phải lỗi RTL — lệnh JAL đã được kiểm tra đầy đủ trong `prog_branch_jump` và 3 compliance test JAL khác |
| ❌ FAIL | 0 | |

**→ 37/37 PASS** trong phạm vi thiết kế; 0 lỗi RTL.

### 4.6 Formal Verification (SymbiYosys k-induction)

Sử dụng **SymbiYosys + Z3 4.13.3 + Yosys**, phương pháp **k-induction**: chứng minh thuộc tính đúng với mọi trạng thái khởi đầu và mọi đầu vào có thể — không phụ thuộc test vector cụ thể, bao phủ không gian trạng thái vô hạn.

---

**[HÌNH 5 — Luồng kiểm chứng hình thức: RTL → Yosys → SMT2 → Z3 → PROVED/FAIL]**

```
+----------------------------------------------------------+
|                                                          |
|                   CHÈN HÌNH TẠI ĐÂY                     |
|    (Formal verification flow:                            |
|     RTL + Assertions → Yosys synthesis →                 |
|     SMT2 encoding → Z3 solver →                         |
|     Basecase (BMC) + Induction step → PROVED)           |
|                                                          |
+----------------------------------------------------------+
```

---

**Batch 1 — 7 jobs (make formal_all):**

| Job | Module | Thuộc tính chứng minh | Depth | Kết quả |
|-----|--------|----------------------|-------|---------|
| `fv_reg_x0` | `register_file` | x0 luôn đọc ra 0; ghi vào x0 bị bỏ qua (3 assertions) | 15 | ✅ PROVED |
| `fv_fifo_gray` | `async_fifo` | Gray code pointer chỉ đổi 1 bit mỗi transition; dữ liệu không bị hỏng qua CDC | 12 | ✅ PROVED |
| `fv_uart_proto` | `uart_axi` | 8N1 frame boundary đúng; start/stop bit đúng thời điểm; bit-count chính xác | 20 | ✅ PROVED |
| `fv_axi_handshake` | `axi_interface` | VALID không được deassert trước khi có READY (AXI spec §A3.2.1) | 10 | ✅ PROVED |
| `fv_plic_priority` | `plic` | Source có priority cao nhất luôn được chọn khi trên threshold | 10 | ✅ PROVED |
| `fv_reg_wbr` | `register_file` | WBR bypass đúng (write-before-read cùng cycle); sequential read nhất quán | 5 | ✅ PROVED |
| `fv_stall_coherence` | `hazard_unit` + 3 pipeline regs | Khi stall: tất cả upstream registers không advance; khi flush: downstream bị clear | 8 | ✅ PROVED |

**Batch 2 — 6 jobs (commits D1–D6):**

| Job | Module | Thuộc tính chứng minh | Kết quả |
|-----|--------|----------------------|---------|
| `fv_alu` | `alu` | 12 phép toán (ADD/SUB/AND/OR/XOR/SLT/SLTU/SLL/SRL/SRA/PASSB) đúng với mọi đầu vào 32-bit | ✅ PROVED |
| `fv_decoder` | `id_decoder` | Decode đúng opcode → control signals cho mọi encoding RV32I hợp lệ | ✅ PROVED |
| `fv_mem1_addr` | `mem1_stage` | Address routing đúng region (DMEM/AXI/AHB/PLIC/OOB) theo address bits | ✅ PROVED |
| `fv_axi_route` | `axi_interconnect` | Đúng AXI slave được chọn theo `addr[27:12]` cho mọi địa chỉ trong range | ✅ PROVED |
| `fv_ahb_route` | `ahb_interconnect` | Đúng HSEL assert per-slave; không overlap; địa chỉ OOB không chọn bất kỳ slave nào | ✅ PROVED |
| `fv_precise_exc` | `mem1/mem2/zicsr` | Pipeline không commit exception trong khi bus transaction đang in-flight; exception chỉ xảy ra sau khi bus hoàn tất | ✅ PROVED |

**→ Tổng: 13/13 formal jobs PROVED** (~30 individual assertions)

### 4.7 Performance Metrics

| Chỉ số | Giá trị | Điều kiện đo |
|--------|---------|-------------|
| CPI (forwarding-heavy) | 1.100 | 1 load-use stall per 10 lệnh |
| CPI (Fibonacci) | 1.182 | 18 load-use stalls, 80% branch hit |
| Branch hit rate (loop đơn) | 81.8% | BHT warm, single-loop workload |
| Branch hit rate (mixed) | 57.9% | 57 branches, mixed pattern |
| AHB latency (avg) | 9.4 CPU cycles | 10 transactions (min=9, max=10) |

---

## 5. TỔNG HỢP TIẾN ĐỘ

| Hạng mục | Kế hoạch | Thực hiện | % Hoàn thành |
|----------|---------|----------|-------------|
| RTL — CPU Pipeline (25 module) | 25 | 25 | **100%** |
| RTL — Bus & CDC (6 module) | 6 | 6 | **100%** |
| RTL — External Peripherals (7 module) | 7 | 7 | **100%** |
| DV — Unit Tests | 16 testbench | 16 TB (~524 cases) | **100%** |
| DV — Integration Tests | 6 testbench | 6 TB (167 cases) | **100%** |
| DV — System Tests | ~20 programs | 34 programs | **90%** |
| DV — RV32I Compliance | 38 tests | 37/37 + 1 SKIP | **90%** |
| DV — Formal Verification | 7 jobs ban đầu | 13 jobs PROVED | **90%** |
| Tài liệu (LaTeX thesis) | 6 chương | 6 chương + appendix | **90%** |

```
RTL Design        ████████████████████  100%
Unit Testing      ████████████████████  100%
Integration Test  ████████████████████  100%
System Test       ██████████████████░░   90%
Compliance        ██████████████████░░   90%
Formal Verify     ██████████████████░░   90%
Documentation     ██████████████████░░   90%
────────────────────────────────────────────
Tổng thể (scope) ████████████████████   ~97%
```

---

## 6. NHỮNG GÌ CHƯA THỰC HIỆN

### 6.1 Còn thiếu trong RTL

| Hạng mục | Chi tiết |
|----------|---------|
| **FENCE.I** | FENCE.I (instruction-cache flush) hiện xử lý như NOP. Không có I-cache trong thiết kế nên không ảnh hưởng chức năng, nhưng chưa có test đặc thù |
| **Misaligned access hardware handler** | Pipeline hiện raise exception cho mọi misaligned access; chưa có hardware misalignment handler tự chia thành nhiều transaction |

### 6.2 Còn thiếu trong DV (ưu tiên cao)

| Hạng mục | Chi tiết | Ưu tiên |
|----------|---------|---------|
| **Formal: AHB FSM liveness** | Chưa có property k-induction chứng minh AHB transaction luôn terminate (không deadlock, không stuck) trong mọi trường hợp HREADY/HRESP | **Cao** |
| **Formal: Interrupt end-to-end priority** | Chưa chứng minh hình thức rằng interrupt source có priority cao nhất luôn được handle trước, xuyên suốt PLIC → Zicsr → pipeline commit | **Cao** |
| **Formal: CDC no data loss** | Chưa có property độc lập chứng minh không mất dữ liệu khi đọc/ghi gần biên giới FIFO empty/full với mọi tổ hợp clock phase | **Trung bình** |
| **System test: nested interrupt** | Chưa có test program cho trường hợp interrupt xảy ra trong khi đang trong interrupt handler (nested interrupt) | **Trung bình** |
| **System test: multi-source IRQ đồng thời** | Chưa test kịch bản nhiều nguồn IRQ active cùng một lúc để xác minh PLIC arbitration dưới tải thực | **Trung bình** |
| **Compliance: jal-01** | Cần tăng IMEM lên ≥2MB hoặc patch framework để test jump offset range cực lớn | **Thấp** |
| **Coverage-driven verification** | Chưa có code/functional coverage report (Icarus Verilog không hỗ trợ coverage; cần Verilator hoặc commercial simulator) | **Thấp** |

### 6.3 Ngoài phạm vi đề tài

| Hạng mục | Lý do không thực hiện |
|----------|----------------------|
| FPGA/ASIC Synthesis & Timing closure | Cần EDA tools thương mại (Vivado, Design Compiler); ngoài scope simulation-based |
| Power analysis | Cần gate-level netlist sau synthesis |
| RV32IM (Multiply/Divide extension) | Không cam kết trong đề cương; có thể mở rộng sau |
| Cache (I$/D$) | Tăng độ phức tạp pipeline đáng kể; ngoài scope đề tài |

---

## 7. KẾT LUẬN

Đề tài đã hoàn thành **toàn bộ RTL** (38/38 module, ~6.318 dòng SystemVerilog) và **hầu hết DV** theo chiến lược 5 tầng: unit (524 cases), integration (167 cases), system (34 programs), RV32I compliance (37/37), formal k-induction (13 jobs PROVED). Các task DV còn thiếu tập trung vào formal verification bổ sung (AHB liveness, interrupt end-to-end, CDC no-loss) và một số system test nâng cao (nested interrupt, multi-source IRQ đồng thời).

---

**[HÌNH 6 — Waveform GTKWave: AHB transaction qua CDC FIFO — Request→Response latency]**

```
+----------------------------------------------------------+
|                                                          |
|                   CHÈN HÌNH TẠI ĐÂY                     |
|    (GTKWave screenshot: AHB write/read transaction,      |
|     CDC FIFO Request (push) → Response (pop),           |
|     9-10 CPU cycle latency measurement)                  |
|                                                          |
+----------------------------------------------------------+
```

---

*Báo cáo tổng hợp từ mã nguồn tại `/home/baoslinux/riscv_soc_thesis/` — branch `main`, commit `22ced7d`, ngày 29/06/2026.*

**Thống kê mã nguồn:**

| Thành phần | Số file | Số dòng |
|-----------|---------|---------|
| RTL (SystemVerilog) | 38 | ~6.318 |
| Testbench (unit + integration) | 22 | ~5.466 |
| Formal specs (.sv + .sby) | 26 | ~1.616 |
| Assembly programs (.s) | 34 | — |
