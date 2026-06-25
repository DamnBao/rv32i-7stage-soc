# Design / Simulation / Verification Coverage Summary
# Ngày đánh giá: 2026-06-25

Đánh giá mức độ hoàn thành của đề tài theo ba trục Design / Simulation / Verification.

## Bảng Tóm Tắt

| Hạng mục | Trạng thái | Ghi chú |
|----------|-----------|---------|
| CPU pipeline + hazards | ✅ Hoàn thành | 7 tầng, forwarding, CSR-use stall, precise exception |
| AXI-Lite write + read + IRQ | ✅ Hoàn thành | End-to-end qua PLIC, handler, MRET |
| AHB-Lite write + read + IRQ + CDC | ✅ Hoàn thành | Async FIFO gray code, 2-FF IRQ sync |
| PLIC arbitration + threshold | ✅ Hoàn thành | 31 unit cases + 3 system programs |
| Bus error (AXI write / BRESP SLVERR) | ✅ Hoàn thành | BRESP SLVERR → store_access_fault (mcause=7) |
| Bus error (AXI read / RRESP SLVERR) | ✅ Hoàn thành | prog_read_err.s: LW → RRESP SLVERR → mcause=5 — PASS |
| Bus error (AHB / HRESP ERROR) | ✅ Hoàn thành | prog_ahb_store/load_err.s: HRESP ERROR → mcause=7/5 — PASS |
| RV32I ISA compliance formal | ⚠️ Gap | riscv-arch-test (bộ test chính thức) chưa chạy |
| Synthesis / timing closure | 🔲 Optional | Chạy Yosys+OpenSTA để xác nhận 1GHz critical path |
| Concrete peripheral (UART/SPI...) | 🔲 Optional | Minh chứng kiến trúc "plug-in peripheral" |
| SVA assertions trong RTL | 🔲 Optional | Formal property checking, coverage closure |

## Giải thích

### ✅ Đã hoàn thành tốt
Tất cả các functional path chính đã được thiết kế, simulate, và verify:
- Pipeline 7 tầng với đầy đủ forwarding và hazard detection
- Giao tiếp AXI-Lite và AHB-Lite (đồng bộ và qua CDC)
- PLIC với 6 nguồn, ưu tiên, ngưỡng, claim/complete
- Exception và interrupt end-to-end (MEI, MSI, ECALL, EBREAK, MRET)

### ⚠️ Gap cần bổ sung (cho luận văn đầy đủ)

**Gap 1 — AXI read error (RRESP):**
RTL đã có path này (axi_interface.sv → axi_resp_err → mem1_stage → load_access_fault),
nhưng chưa có test program để exercise path đó.
Sửa: viết prog_read_err.s (LW từ error slave → mcause=5).

**Gap 2 — AHB bus error:**
ahb_sfr.sv luôn trả HRESP=OKAY. Cần một AHB error slave trong testbench
để test path HRESP=ERROR → load/store_access_fault.

**Gap 3 — RISC-V ISA compliance:**
prog_rv32i_shifts.s và prog_rv32i_compare.s là custom tests.
riscv-arch-test là bộ test chính thức của RISC-V Foundation (~200 cases).

### 🔲 Nice-to-have (không bắt buộc)
- Synthesis report: xác nhận timing constraint 1GHz
- UART/SPI peripheral: minh chứng SFR standard register map với logic thực
- SVA assertions: $assert property trong pipeline registers

## Lịch sử cập nhật

| Ngày | Thay đổi |
|------|---------|
| 2026-06-25 | Tạo bảng đánh giá ban đầu |
| 2026-06-25 | Gap 1 (AXI read error) → implement và PASS: prog_read_err.s, integ_bus_err 2/2 |
| 2026-06-25 | Gap 2 (AHB error) → implement và PASS: prog_ahb_store/load_err.s, integ_ahb_err 2/2 |
