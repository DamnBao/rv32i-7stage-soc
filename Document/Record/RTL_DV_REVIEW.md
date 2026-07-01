# RTL & DV Review — RISC-V SoC Luận Văn

**Ngày:** 2026-06-28

---

## Đánh Giá Tổng Thể

| Tiêu chí | Trạng thái |
|----------|-----------|
| ISA completeness (RV32I) | 97% — 1 skip jal-01 (IMEM size 64KB vs 2MB yêu cầu) |
| Pipeline correctness | 90% — gap misaligned access (đã sửa) |
| Bus infrastructure | 100% |
| Peripheral coverage | 100% |
| Unit test coverage | 90% — directed-only, không có functional coverage |
| Integration test coverage | 80% |
| Formal verification | 70% — infra proven, datapath pipeline chưa formal |
| Synthesis-ready | 50% — synthesizable nhưng chưa FPGA/timing closure |

---

## Những Gì Đã Hoàn Thành Tốt

### RTL — Thiết Kế
- **Pipeline 7 tầng hoàn chỉnh** (~6,230 dòng SV synthesizable, 38 module): forwarding đầy đủ 4 gap, hazard unit, branch predictor 2-bit BHT+BTB
- **Bus infrastructure chuẩn:** AXI-Lite + AHB-Lite với CDC dual async FIFO — phần kỹ thuật phức tạp nhất đã được triển khai đúng
- **Peripheral ecosystem:** GPIO, Timer, UART, PLIC 6 nguồn — đủ để chứng minh SoC thực sự hoạt động
- **Coding discipline:** Không package, assign cho bit-select, async-assert/sync-deassert reset — nhất quán toàn bộ codebase

### DV — Kiểm Tra
- **Coverage theo chiều rộng:** 28 testbench, ~621+ directed test case, 30 assembly program, 4 lớp tích hợp
- **RV32I compliance 37/37:** Milestone thực sự có ý nghĩa — riscv-arch-test là bộ test chuẩn công nghiệp
- **Formal verification:** 7 property PROVED bằng k-induction (SymbiYosys + z3) — vượt mức kỳ vọng thông thường của luận văn. Phát hiện và sửa 1 RTL bug thực (UART TX)

---

## Gap Đã Sửa

### 1. Misaligned Access Detection ✅ (sửa 2026-06-28)

**Vấn đề:** `mem1_stage.sv` không detect misaligned load/store. RV32I spec yêu cầu:
- `LH`/`SH` tại địa chỉ lẻ → Load/Store Address Misaligned (mcause 4/6)
- `LW`/`SW` tại địa chỉ không chia hết 4 → Load/Store Address Misaligned (mcause 4/6)

**Sửa:**
- `mem1_stage.sv`: thêm `misaligned` detection; gating tất cả bus request bằng `~misaligned`; output `load_misaligned` / `store_misaligned`
- `mem1_mem2_reg.sv`, `mem2_stage.sv`, `mem2_wb_reg.sv`: propagate 2 signal mới qua pipeline
- `zicsr.sv`: thêm `wb_load_misaligned` / `wb_store_misaligned` inputs; mcause 4 / 6 trong exception handler
- `soc_top.sv`: wire tất cả signal mới

### 2. MTIP Thiếu ✅ (sửa 2026-06-28)

**Vấn đề:** `mip.MTIP` (bit 7) luôn = 0, dù Timer AXI có irq. Timer IRQ đi qua PLIC→MEIP, nên `mie.MTIE` không có tác dụng — deviation khỏi RISC-V Privileged Spec §3.1.9.

**Sửa:**
- `zicsr.sv`: thêm `mtip_in` port; `mip[7] = mtip_in`; `int_mti = mtip_in & mie_mtie`; mcause `{1'b1, 31'd7}` (MTI); vectored address `base+28`; interrupt priority MEI > MTI > MSI
- `soc_top.sv`: `mtip_wire = axi_S1_irq` (Timer AXI slave 1) → `mtip_in` của zicsr; giữ nguyên PLIC path cho backward compat

---

## Gap Còn Lại (Chưa Sửa)

### Mức Quan Trọng Cao — DV

| Gap | Chi tiết |
|-----|----------|
| **Formal — datapath** | `id_decoder`, `ex_stage`, `alu`, `mem1_stage`, `mem2_stage`, `ahb_interconnect`, `axi_interconnect` chưa có formal property. RVFI (`riscv-formal`) là gold standard nhưng ngoài phạm vi luận văn |
| **Precise exception formal** | Chỉ verified bằng 2 integration program. Property "không cancel bus transaction đang diễn ra" là critical invariant chưa được prove |
| **Functional coverage** | Icarus không support `covergroup`/`coverpoint`. Coverage hole vô hình — không biết corner case nào chưa test |

### Mức Quan Trọng Trung Bình

| Gap | Chi tiết |
|-----|----------|
| **FENCE/WFI** | FENCE decoded nhưng treated as NOP. Đúng cho in-order CPU nhưng nên document |
| **jal-01 skip** | 1.7MB test cần IMEM 2MB; thiết kế 64KB. Kiến trúc decision đúng, cần note trong thesis |
| **Out-of-range address** | `mem1_stage` có exception path nhưng chưa có dedicated test program |
| **Synthesis/FPGA** | RTL synthesizable nhưng chưa có FPGA target, không có timing closure, area/power numbers |

---

## Kết Luận

Thiết kế hoàn chỉnh và vững chắc ở mức RTL simulation — không có show-stopper bug đã biết, compliance pass, formal infra proven. Với phạm vi luận văn đại học, dự án đạt **trên mức yêu cầu rõ rệt**.

Nếu muốn nâng lên publication-quality: *(1)* nhắm tới 1 FPGA target để có utilization/timing report, *(2)* thêm RVFI wrapper để formal-verify datapath.
