# CLAUDE.md — Context Dự Án RISC-V SoC (Luận Văn)

## Tổng Quan

CPU RV32I + Zicsr, pipeline 7 tầng in-order, tần số 1GHz. Kết nối ngoại vi qua AXI-Lite (1GHz, đồng bộ) và AHB-Lite (500MHz, bất đồng bộ qua CDC). Toàn bộ RTL viết bằng **SystemVerilog synthesizable**, mô phỏng bằng **Icarus Verilog**.

---

## Shortcut Commands

- **`*upd`** — Khi user nhập `*upd`: tự động commit tất cả thay đổi + cập nhật CLAUDE.md để phản ánh trạng thái mới nhất, rồi commit CLAUDE.md trong cùng một commit (hoặc commit riêng nếu cần). Không cần hỏi thêm.

---

## Quy Tắc Tài Liệu (Bắt Buộc)

- **Mỗi file `.md` phải có file `.docx` tương ứng và ngược lại.** Khi tạo hoặc sửa một file, phải tạo/cập nhật file còn lại ngay sau đó.
- Dùng `pandoc` để chuyển đổi:
  ```bash
  pandoc file.md -o file.docx        # md → docx
  pandoc file.docx -o file.md        # docx → md
  ```

---

## Quy Tắc Coding (Bắt Buộc)

- **Không dùng package.** Mọi `localparam` khai báo trực tiếp trong từng module.
- **Không dùng bit/part-select bên trong `always_*`** — Icarus báo lỗi. Phải bóc tách ra ngoài bằng `assign`:
  ```sv
  logic [1:0] instr_13_12;
  assign instr_13_12 = instr[13:12]; // ✓ dùng trong always_comb được
  ```
- **Reset: async assert, sync deassert** (dùng `reset_sync.sv`):
  ```sv
  always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin ... end
      else        begin ... end
  end
  ```
- Chỉ viết synthesizable constructs. Không dùng OOP, `$display` trong RTL.

---

## Kiến Trúc Pipeline 7 Tầng (@ 1GHz)

| Tầng | Chức năng |
|------|-----------|
| **IF1** | Tính PC tiếp theo, xuất địa chỉ thẳng vào IMEM |
| **IF2** | IMEM trả lệnh sau 1 chu kỳ, hội tụ với PC từ IF1/IF2 reg |
| **ID** | Giải mã lệnh (`id_decoder`), đọc register file |
| **EX** | ALU + Branch Comparator + Address Adder (bọc trong `ex_stage`) |
| **MEM1** | Address Decode → DMEM / AXI Interface / AHB Async FIFO |
| **MEM2** | Thu kết quả DMEM hoặc Response FIFO / AXI |
| **WB** | Ghi kết quả về register file |

**Pipeline registers:** IF1/IF2, IF2/ID, ID/EX, EX/MEM1, MEM1/MEM2, MEM2/WB.

**Forwarding Unit:** bypass dữ liệu từ MEM1, MEM2, WB ngược về đầu vào EX (nằm bên trong `ex_stage`).

---

## Memory Map

| Vùng | Địa chỉ bắt đầu | Địa chỉ kết thúc | Clock | Đặc tính |
|------|-----------------|------------------|-------|----------|
| IMEM | `0x0000_0000` | `0x0000_FFFF` | 1GHz | 64KB, sync, no stall |
| DMEM | `0x0001_0000` | `0x0001_FFFF` | 1GHz | 64KB, sync, no stall |
| AXI-Lite | `0x2000_0000` | `0x2FFF_FFFF` | 1GHz | 4KB/SFR, đồng bộ trực tiếp |
| AHB-Lite | `0x3000_0000` | `0x3FFF_FFFF` | 500MHz | 4KB/SFR, qua CDC Async FIFO |
| PLIC | `0x0C00_0000` | `0x0CFF_FFFF` | 1GHz | 6 sources, 1-cycle latency, no stall |

---

## Address Decoder tại MEM1 (Bit-slicing)

| Điều kiện | Hành động |
|-----------|-----------|
| `addr[31:16] == 16'h0001` | DMEM — không stall |
| `addr[31:24] == 8'h0C` | PLIC — không stall, 1-cycle latency, mem_src=2'b11 |
| `addr[31:28] == 4'h2` | AXI Interface — `bus_stall_req = 1` |
| `addr[31:28] == 4'h3` | AHB Async FIFO — `bus_stall_req = 1` |
| Không khớp | Exception → Zicsr (Load/Store Access Fault) |

Bóc tách bus: `slave_id = addr[27:12]`, `reg_offset = addr[11:0]`.

---

## CDC: Dual Async FIFO (Depth = 2)

- **Request FIFO (1GHz → 500MHz):** 67-bit = Address(32) + WriteData(32) + Control(3: R/W + HSIZE)
- **Response FIFO (500MHz → 1GHz):** 33-bit = ReadData(32) + HRESP(1)
- Gray code bắt buộc, depth tối thiểu = 2 (lũy thừa 2)
- **Không có `full` flag** — CPU bị stall cứng khi giao dịch nên không thể overflow
- Chỉ dùng `empty` flag để trigger ở mỗi chiều

---

## Khối Zicsr

- CSR: `mstatus`, `mie`, `mtvec`, `mepc`, `mcause`, `mip`
- Interrupt mode: **Vectored** (mỗi nguyên nhân có offset riêng)
- `meip_in` (từ PLIC) → `mip.MEIP` (read-only); PLIC đã arbitrate 6 nguồn
- AHB irq → **3×`irq_sync2ff` (1GHz, per-source, trong soc_top)** → PLIC → Zicsr
- AXI irq → PLIC → Zicsr (đồng bộ 1GHz, không cần sync)
- **Precise Exception:** không được hủy ngang giao dịch bus đang diễn ra
- Lỗi bus (HRESP/BRESP) → đẩy thẳng về Zicsr → sinh Exception

---

## Chip Boundary — External Peripheral Interface

`soc_top` không chứa SFR nội bộ và **không chứa bất kỳ logic datapath nào** — chỉ có port declarations, wire declarations, và module instances. Bất kỳ peripheral nào tuân thủ SFR Standard đều cắm vào được mà không cần sửa RTL trong chip.

```
                ┌─────────────────────────────┐
clk_cpu ───────►│                             │◄── axi_S0_irq / S1 / S2
clk_ahb ───────►│   soc_top                   │══► AXI-Lite slave ports × 3
rst_n ─────────►│   (CPU + bus infrastructure)│══► AHB-Lite slave ports × 3
                │                             │◄── ahb_S0_irq_i / S1 / S2
                │                             │──► rst_cpu_n_o / rst_ahb_n_o
                └─────────────────────────────┘
                           (chip boundary)
                  External peripherals plug in here
```

**Outputs từ soc_top:**
- `rst_cpu_n_o`, `rst_ahb_n_o` — reset đã sync, peripheral dùng để reset FF của mình
- `axi_S{0,1,2}_*` — AXI-Lite slave port đầy đủ (AWADDR, WDATA, ARADDR, RDATA, ...)
- `ahb_HADDR_o`, `ahb_HSIZE_o`, `ahb_HTRANS_o`, `ahb_HWRITE_o`, `ahb_HWDATA_o` — shared AHB bus
- `ahb_S{0,1,2}_HSEL_o`, `ahb_S{0,1,2}_HREADY_o` — per-slave AHB select

**Inputs vào soc_top:**
- `axi_S{0,1,2}_AWREADY`, `WREADY`, `BRESP`, `BVALID`, `ARREADY`, `RDATA`, `RRESP`, `RVALID`
- `axi_S{0,1,2}_irq` — IRQ từ AXI peripheral (đồng bộ 1GHz)
- `ahb_S{0,1,2}_HREADYOUT_i`, `HRDATA_i`, `HRESP_i`, `irq_i` — từ AHB peripheral (500MHz)

---

## SFR Standard Register Map (OpenTitan-inspired)

Mọi peripheral muốn kết nối với `soc_top` phải implement register map này:

| Offset | Tên | Access | Mô tả |
|--------|-----|--------|-------|
| `0x00` | `CTRL` | RW | `bit[0]` = enable; bits[31:1] = peripheral-specific |
| `0x04` | `STATUS` | RO | Trạng thái read-only do peripheral drive |
| `0x08` | `INTR_ENABLE` | RW | Mask từng nguồn IRQ |
| `0x0C` | `INTR_STATE` | RW1C | Pending flags — ghi 1 để clear |
| `0x10` | `INTR_TEST` | WO | Ghi 1 để force-set `INTR_STATE` (debug/test) |
| `0x14` | `DATA0` | RW | General-purpose (peripheral-specific) |
| `0x18` | `DATA1` | RW | |
| `0x1C` | `DATA2` | RW | |
| `0xFC` | `PERIPH_ID` | RO | Hardcoded peripheral identifier (parameterized) |

**IRQ rule:** `irq = |(INTR_STATE & INTR_ENABLE)`

**Address decode:** `AWADDR[7:2]` (AXI) hoặc `HADDR[7:2]` (AHB) — 6-bit index.

---

## Phân Nhóm Module

### Nhóm CPU (1GHz) — trong soc_top
`if1_stage`, `if2_stage`, `id_decoder`, `register_file`, pipeline registers (if1_if2_reg, if2_id_reg, id_ex_reg, ...), **`ex_stage`** (bọc: forwarding_unit + alu + branch_comp + addr_adder + MUXes), Hazard Unit, Zicsr, **PLIC** (6 sources, 3-bit priority, SiFive spec)

### Nhóm AXI (1GHz) — trong soc_top
`axi_interface`, `axi_interconnect` (address decode 3 slaves, OR irq lines)

### Nhóm AHB (CDC + 500MHz) — trong soc_top
`async_fifo_depth2` (Request + Response), `reset_sync` ×2, **`irq_sync2ff` ×3** (2-FF sync AHB IRQs → 1GHz, per-source), `ahb_interface`, `ahb_interconnect`

### External Peripherals (ngoài soc_top, cắm vào slave ports)
`axi_sfr` — generic AXI-Lite SFR, implement SFR standard; tham số `PERIPH_ID_VAL`
`ahb_sfr` — generic AHB-Lite SFR, implement SFR standard
`gpio_sfr` — AXI-Lite GPIO peripheral: `DATA0`→`gpio_out`, `gpio_in`→`STATUS`, edge-detect IRQ
`timer_axi` — AXI-Lite Timer (1GHz, AXI S1 = 0x2000_1000): prescaler+compare IRQ; PERIPH_ID="TIMR"
`gpio_ahb` — AHB-Lite GPIO (500MHz, AHB S0 = 0x3000_0000): 2-FF sync, edge-detect IRQ; PERIPH_ID="GPIA"
`uart_axi` — AXI-Lite 8N1 UART (1GHz): TX via DATA1 write, RX to DATA2; baud_div=DATA0; PERIPH_ID="UART"

---

## Trạng Thái Hiện Tại (các file đã có trong RTL/)

| File | Trạng thái |
|------|-----------|
| `branch_predictor.sv` | Hoàn thành (16-entry 2-bit BHT + BTB; lookup IF1 combinational; update at EX) |
| `reset_sync.sv` | Hoàn thành |
| `async_fifo.sv` | Hoàn thành |
| `irq_sync2ff.sv` | Hoàn thành (2-FF synchronizer; dùng cho AHB IRQ CDC 500MHz→1GHz, 1 instance/slave) |
| `if1_stage.sv` | Hoàn thành (thêm bp_redirect + bp_target; priority: flush > stall > bp_redirect > PC+4) |
| `if1_if2_reg.sv` | Hoàn thành (thêm bp_taken + bp_target fields; cleared on flush) |
| `imem.sv` | Hoàn thành (đã sửa bug mảng 64KB; thêm `stall` giữ output; thêm `flush` output NOP khi zicsr_flush để chặn ghost illegal_instr) |
| `if2_stage.sv` | Hoàn thành (thêm bp_taken + bp_target pass-through) |
| `if2_id_reg.sv` | Hoàn thành (thêm bp_taken + bp_target fields; cleared on flush) |
| `register_file.sv` | Hoàn thành (English header; gap-4 RAW WBR bypass explained) |
| `id_decoder.sv` | Hoàn thành (English header; encoding tables documented) |
| `id_ex_reg.sv` | Hoàn thành (thêm bp_taken + bp_target fields; cleared on flush) |
| `alu.sv` | Hoàn thành (English header; shift_amt Icarus workaround noted) |
| `addr_adder.sv` | Hoàn thành (English header; JALR bit[0] mask — ISA §2.5 reference) |
| `branch_comp.sv` | Hoàn thành (English header; Icarus constant-select workaround noted) |
| `forwarding_unit.sv` | Hoàn thành |
| `ex_stage.sv` | Hoàn thành (EX wrapper: forwarding_unit + MUXes + alu + branch_comp + addr_adder; không có logic trong soc_top) |
| `ex_mem1_reg.sv` | Hoàn thành (English header; stall/flush semantics) |
| `mem1_stage.sv` | Hoàn thành (PLIC decode: addr[31:24]==0x0C, plic_re/we/addr/wdata, mem_src=2'b11) |
| `dmem.sv` | Hoàn thành |
| `mem1_mem2_reg.sv` | Hoàn thành (English header; mem_src comment: 2'b11=PLIC fixed; precise exception note) |
| `mem2_stage.sv` | Hoàn thành (load/store fault signals; plic_rdata input; mem_src=2'b11 mux) |
| `mem2_wb_reg.sv` | Hoàn thành (English header; stall/flush semantics) |
| `wb_stage.sv` | Hoàn thành |
| `hazard_unit.sv` | Hoàn thành (thay branch_taken+jump bằng bp_mismatch; ctrl_flush=bp_mismatch) |
| `zicsr.sv` | Hoàn thành (port meip_in từ PLIC; 6 CSR regs, vectored) |
| `plic.sv` | Hoàn thành (6 sources, 3-bit priority, threshold, claim/complete; MMIO 0x0C000000; 1-cycle latency) |
| `ahb_interface.sv` | Hoàn thành |
| `ahb_interconnect.sv` | Hoàn thành (3 slaves, addr[27:12] decode) |
| `ahb_sfr.sv` | Hoàn thành (Standard Register Map; HADDR[7:2]; AHB pipeline capture) |
| `axi_interface.sv` | Hoàn thành |
| `axi_interconnect.sv` | Hoàn thành (3 slaves, addr[27:12] decode) |
| `axi_sfr.sv` | Hoàn thành (Standard Register Map; irq=|(INTR_STATE&INTR_ENABLE)) |
| `gpio_sfr.sv` | Hoàn thành (AXI-Lite peripheral; STATUS=gpio_in; edge-detect irq; DATA0=gpio_out) |
| `timer_axi.sv` | Hoàn thành (AXI-Lite Timer; self-contained; PRESCALER=DATA0, COMPARE=DATA1, STATUS=counter; compare-match IRQ) |
| `gpio_ahb.sv` | Hoàn thành (AHB-Lite GPIO; 2-FF sync; edge-detect on gpio_in[0]; DATA0=out value, DATA1[0]=OE, DATA2[0]=edge type) |
| `uart_axi.sv` | Hoàn thành (AXI-Lite 8N1 UART; TX FSM 4-state; RX FSM 4-state + 2-FF sync; baud_div=DATA0; tx→DATA1 trigger; rx→DATA2; INTR_STATE[1]=rx,[0]=tx; PERIPH_ID="UART") |
| `soc_top.sv` | Hoàn thành (thêm branch_predictor instance; bp_mismatch/bp_correct_pc; prediction metadata wires qua pipeline) |

---

## Trạng Thái Testing

| Phase | Testbench | Kết quả |
|-------|-----------|---------|
| Phase 1 | Unit: alu, branch_comp, register_file, id_decoder | 192/192 PASS |
| Phase 2 | Unit: forwarding_unit, hazard_unit, async_fifo | 114/114 PASS (hazard: 73 total) |
| Phase 3 | Integration: tb_pipeline_cpu (9 programs qua soc_top) | 9/9 PASS |
| Phase 4a | tb_axi_interface (axi_interface + slave model) | 49/49 PASS |
| Phase 4b | tb_ahb_interface (ahb_interface + CDC FIFOs + slave model) | 29/29 PASS |
| Phase 4c | tb_axi_full (axi_interface + axi_interconnect + 3×axi_sfr — Standard Map) | 47/47 PASS |
| Phase 4d | tb_ahb_full (ahb_interface + CDC + ahb_interconnect + 3×ahb_sfr — Standard Map) | 38/38 PASS |
| Phase 5 | tb_pipeline_cpu (4 programs: AXI/AHB SFR write/read + AXI/AHB IRQ via INTR_TEST) | 4/4 PASS |
| Phase 6a | tb_soc_top (batch runner: tất cả **20 programs** qua soc_top với reset) | **20/20 PASS** |
| Phase 6b | tb_compliance (compliance framework: shifts, compare, dmem_endurance) | 3/3 TEST_PASS |
| Phase 7 | unit: tb_plic (31); system: prog_plic_basic + priority + threshold | 31/31 + 3/3 PASS |
| Phase 8 | unit: tb_ex_stage (23); system: prog_csr_hazard (CSR-use stall gaps 0–4) | 23/23 + 1/1 PASS |
| New unit | tb_irq_sync2ff (10), tb_gpio_sfr (22), tb_zicsr (38) | 70/70 PASS |
| integ_bus_err | tb_soc_bus_err: BRESP SLVERR→store_fault(mcause=7); RRESP SLVERR→load_fault(mcause=5) | 2/2 PASS |
| integ_ahb_err | tb_soc_ahb_err: AHB HRESP ERROR→store_fault(mcause=7); HRESP ERROR→load_fault(mcause=5) | 2/2 PASS |
| rv32i_compliance | riscv-arch-test old-framework-2.x: 37/37 PASS; 1 SKIP (jal-01 ~1.7MB, cần 2MB IMEM) | **37/37 PASS** |
| branch_pred | unit: tb_branch_predictor (23 cases BHT/BTB cold/warm/hysteresis/tag/reset); system: prog_branch_pred (4 tests: loop/JAL/nested/alternating) | **23/23 + 1/1 PASS** |
| periph | tb_periph: prog_timer (Timer AXI compare-match IRQ, PLIC src 2); prog_gpio_ahb (GPIO AHB loopback 0x55 + INTR_TEST IRQ, PLIC src 4); prog_uart (UART TX/RX loopback 0x55 + dual IRQ, PLIC src 3) | **3/3 PASS** |
| unit_periph | tb_timer_axi (23), tb_gpio_ahb (21), tb_uart_axi (27) — peripheral unit tests | **71/71 PASS** |
| formal_verify | SymbiYosys k-induction (smtbmc z3): P_REG_X0 (register_file, depth=15); P_GRAY+P_FIFO_DATA (async_fifo, depth=12); P_8N1+P_TX_PULSE+P_RX_PULSE+P_RX_BIT_CNT (uart_axi, depth=20); P_AXI_HANDSHAKE (axi_interface, depth=10); P_PLIC_PRIORITY (plic, depth=10); P_WBR+P_RF_SEQ (register_file, depth=5); P_STALL_COHERENCE+P_FLUSH (hazard_unit+3 pipeline regs, depth=8); ~30 assertions tổng; Phát hiện + sửa 1 RTL bug (UART TX) | **7/7 PROVED** |

**Lệnh chạy:**
```bash
cd SIM && make p3_all          # Phase 3: 9 programs
make integ_axi                 # Phase 4a: AXI interface
make integ_ahb                 # Phase 4b: AHB interface
make integ_axi_full            # Phase 4c: AXI full path
make integ_ahb_full            # Phase 4d: AHB full path
make p5_all                    # Phase 5: 4 programs AXI/AHB SFR + IRQ
make system                    # Phase 6a+7+8: batch runner 20 programs
make p6_compliance             # Phase 6b: compliance programs
make p6_all                    # Phase 6: cả 6a + 6b
make unit_plic                 # Phase 7: PLIC unit test (31 cases)
make unit_ex                   # Phase 8: EX stage unit test (23 cases)
make unit_irq_sync             # New: irq_sync2ff unit test (10 cases)
make unit_gpio                 # New: gpio_sfr unit test (22 cases)
make unit_zicsr                # New: zicsr unit test (38 cases)
make unit_all                  # Tất cả unit tests (Phase 1+2+7+8+new+branch_pred+periph)
make unit_bp                   # Branch predictor unit test (23 cases)
make unit_timer                # Timer AXI unit test (23 cases)
make unit_gpio_ahb             # GPIO AHB unit test (21 cases)
make unit_uart                 # UART AXI unit test (27 cases)
make unit_periph               # Cả 3 peripheral unit tests (71 cases)
make p0_branch_pred            # Branch prediction system test (4 programs)
make periph_timer              # Task 1: Timer AXI compare-match IRQ test
make periph_gpio               # Task 1: GPIO AHB loopback + INTR_TEST IRQ test
make periph_uart               # Task 1: UART AXI TX/RX loopback + dual IRQ test
make periph_all                # Task 1: cả 3 peripheral tests
make integ_bus_err             # Bus error integration test
make integ_ahb_err             # AHB bus error integration test
make rv32i_compliance          # RV32I formal compliance (riscv-arch-test)
make formal_all                # Task 2: tất cả 7 formal verification jobs (7/7 PROVED)
make formal_stall              # Formal: pipeline stall coherence (hazard_unit + 3 regs)
make formal_x0                 # Formal: register_file x0 immutability
make formal_fifo               # Formal: async_fifo Gray-code + memory integrity
make formal_uart               # Formal: uart_axi 8N1 + pulse + bit-cnt
make formal_axi                # Formal: axi_interface VALID stability (AXI §A3.2.1)
make formal_plic               # Formal: plic priority encoder correctness
make formal_reg_wbr            # Formal: register_file WBR bypass + sequential read
make p3_wave_csr               # dump VCD để debug Phase 3
```
Chi tiết xem `SIM/TEST_LOG.md`.

---

## Hazard Coverage (Pipeline 7 tầng)

| Hazard | Cơ chế | Cycles stall |
|--------|--------|-------------|
| Gap-1 RAW | MEM1 forwarding | 0 |
| Gap-2 RAW | MEM2 forwarding | 0 |
| Gap-3 RAW | WB forwarding | 0 |
| Gap-4 RAW | WBR bypass trong register_file | 0 |
| Load-use | hazard_unit: stall IF1..ID, bubble EX | 1 |
| CSR-use | hazard_unit: stall IF1..ID khi CSR@EX/MEM1/MEM2 | 3/2/1 |
| Branch predicted correctly | không flush (0 penalty) | 0 |
| Branch mispredicted | flush IF1/IF2 và IF2/ID (bp_mismatch) | 2 slots flushed |
| Bus stall | stall toàn pipeline | N (đến khi xong) |

---

## Trạng Thái Báo Cáo Khóa Luận

**Thư mục:** `Document/Requirement/`

| File | Trạng thái |
|------|-----------|
| `Content/chapter1.tex` | Hoàn thành — Giới thiệu (bối cảnh, mục tiêu, phương pháp, công cụ) |
| `Content/chapter2.tex` | Hoàn thành — Tổng quan nghiên cứu (FE310, OpenTitan, VexRiscv, PicoRV32, bảng so sánh) |
| `Content/chapter3.tex` | Hoàn thành — Cơ sở lý thuyết (RV32I, pipeline, AXI, AHB, CDC, PLIC) |
| `Content/chapter4.tex` | Hoàn thành — Thiết kế & triển khai (7-stage pipeline, bus FSM, CDC FIFO, PLIC, Zicsr, SFR) |
| `Content/chapter5.tex` | Hoàn thành — Kết quả thực nghiệm (tất cả phase; bảng compliance 38 tests; ~17 trang) |
| `Content/chapter6.tex` | Hoàn thành — Kết luận (tóm tắt, hạn chế, hướng phát triển) |
| `Appendix/tomtat.tex` | Hoàn thành — Tóm tắt tiếng Việt + Abstract tiếng Anh |
| `References/references.bib` | Hoàn thành — 16 tài liệu tham khảo (riscv-spec, AXI, AHB, PLIC, CDC, v.v.) |
| `myacronyms.sty` | Hoàn thành — 24 acronym (SoC, PLIC, CDC, AXI, AHB, ISA, CPU, ALU, v.v.) |
| `main.tex` | Hoàn thành — Cập nhật tên đề tài và bộ môn |
| `thesis_draft.docx` | Hoàn thành — Bản nháp DOCX (pandoc via markdown) |
| `thesis_draft.md` | Hoàn thành — Bản nháp Markdown trung gian |

**Tên đề tài:** THIẾT KẾ VÀ KIỂM CHỨNG VI XỬ LÝ RISC-V TÍCH HỢP TRÊN CHIP (SoC) VỚI GIAO DIỆN AXI-Lite VÀ AHB-Lite

**Còn thiếu (user bổ sung sau):** 12 placeholder hình trong các chapter .tex (block diagram, waveform, FSM diagram)
