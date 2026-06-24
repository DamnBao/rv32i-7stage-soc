# CLAUDE.md — Context Dự Án RISC-V SoC (Luận Văn)

## Tổng Quan

CPU RV32I + Zicsr, pipeline 7 tầng in-order, tần số 1GHz. Kết nối ngoại vi qua AXI-Lite (1GHz, đồng bộ) và AHB-Lite (500MHz, bất đồng bộ qua CDC). Toàn bộ RTL viết bằng **SystemVerilog synthesizable**, mô phỏng bằng **Icarus Verilog**.

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
| **EX** | ALU + Branch Comparator + Address Adder |
| **MEM1** | Address Decode → DMEM / AXI Interface / AHB Async FIFO |
| **MEM2** | Thu kết quả DMEM hoặc Response FIFO / AXI |
| **WB** | Ghi kết quả về register file |

**Pipeline registers:** IF1/IF2, IF2/ID, ID/EX, EX/MEM1, MEM1/MEM2, MEM2/WB.

**Forwarding Unit:** bypass dữ liệu từ MEM1, MEM2, WB ngược về đầu vào EX.

---

## Memory Map

| Vùng | Địa chỉ bắt đầu | Địa chỉ kết thúc | Clock | Đặc tính |
|------|-----------------|------------------|-------|----------|
| IMEM | `0x0000_0000` | `0x0000_FFFF` | 1GHz | 64KB, sync, no stall |
| DMEM | `0x0001_0000` | `0x0001_FFFF` | 1GHz | 64KB, sync, no stall |
| AXI-Lite | `0x2000_0000` | `0x2FFF_FFFF` | 1GHz | 4KB/SFR, đồng bộ trực tiếp |
| AHB-Lite | `0x3000_0000` | `0x3FFF_FFFF` | 500MHz | 4KB/SFR, qua CDC Async FIFO |

---

## Address Decoder tại MEM1 (Bit-slicing)

| Điều kiện | Hành động |
|-----------|-----------|
| `addr[31:16] == 16'h0001` | DMEM — không stall |
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
- AHB irq → **2-FF Synchronizer (1GHz)** → Zicsr (bộ sync nằm trong nhóm CPU/Zicsr)
- AXI irq → kết nối trực tiếp (cùng miền 1GHz)
- **Precise Exception:** không được hủy ngang giao dịch bus đang diễn ra
- Lỗi bus (HRESP/BRESP) → đẩy thẳng về Zicsr → sinh Exception

---

## Phân Nhóm Module

### Nhóm CPU (1GHz)
`if1_stage`, `if2_stage`, `id_decoder`, `register_file`, `alu`, pipeline registers (if1_if2_reg, if2_id_reg, id_ex_reg, ...), Hazard Unit, Forwarding Unit, Zicsr (bao gồm 2-FF sync)

### Nhóm AXI (1GHz)
AXI-Lite Interface, AXI Interconnect, AXI peripheral SFRs

### Nhóm AHB (CDC + 500MHz)
`async_fifo` (Request + Response), `reset_sync`, AHB-Lite Interface FSM, AHB Interconnect, AHB peripheral SFRs

---

## Trạng Thái Hiện Tại (các file đã có trong RTL/)

| File | Trạng thái |
|------|-----------|
| `reset_sync.sv` | Hoàn thành |
| `async_fifo.sv` | Hoàn thành |
| `if1_stage.sv` | Hoàn thành |
| `if1_if2_reg.sv` | Hoàn thành |
| `imem.sv` | Hoàn thành (đã sửa bug mảng 64KB; thêm `stall` giữ output; thêm `flush` output NOP khi zicsr_flush để chặn ghost illegal_instr) |
| `if2_stage.sv` | Hoàn thành |
| `if2_id_reg.sv` | Hoàn thành |
| `register_file.sv` | Hoàn thành (thêm WBR bypass combinational cho gap-4 RAW hazard) |
| `id_decoder.sv` | Hoàn thành (đã sửa bug bit-select Icarus) |
| `id_ex_reg.sv` | Hoàn thành (đã vá: thêm csr_imm_sel_in/out) |
| `alu.sv` | Hoàn thành |
| `addr_adder.sv` | Hoàn thành |
| `branch_comp.sv` | Hoàn thành |
| `ex_mem1_reg.sv` | Hoàn thành |
| `mem1_stage.sv` | Hoàn thành |
| `dmem.sv` | Hoàn thành |
| `mem1_mem2_reg.sv` | Hoàn thành (có load/store fault signals) |
| `mem2_stage.sv` | Hoàn thành (có load/store fault signals) |
| `mem2_wb_reg.sv` | Hoàn thành |
| `wb_stage.sv` | Hoàn thành |
| `hazard_unit.sv` | Hoàn thành (CSR-use stall; **fix Phase 5: suppress fetch_stall flush khi bus_stall_req=1** để tránh cancel lệnh LW khi SW+LW đồng thời stall) |
| `forwarding_unit.sv` | Hoàn thành |
| `zicsr.sv` | Hoàn thành (2-FF sync AHB IRQ, 6 CSR regs, vectored) |
| `ahb_interface.sv` | Hoàn thành |
| `ahb_interconnect.sv` | Hoàn thành (3 slaves, addr[27:12] decode) |
| `ahb_sfr.sv` | Hoàn thành (8×32-bit regs, IRQ = REG7[0]) |
| `axi_interface.sv` | Hoàn thành |
| `axi_interconnect.sv` | Hoàn thành (3 slaves, addr[27:12] decode) |
| `axi_sfr.sv` | Hoàn thành (8×32-bit regs, IRQ = REG7[0]) |
| `soc_top.sv` | Hoàn thành (30 modules, 0 errors; wire stall→imem, CSR-use ports→hazard_unit) |

---

## Trạng Thái Testing

| Phase | Testbench | Kết quả |
|-------|-----------|---------|
| Phase 1 | Unit: alu, branch_comp, register_file, id_decoder | 192/192 PASS |
| Phase 2 | Unit: forwarding_unit, hazard_unit, async_fifo | 101/101 PASS |
| Phase 3 | Integration: tb_pipeline_cpu (9 programs qua soc_top) | 9/9 PASS |
| Phase 4a | tb_axi_interface (axi_interface + slave model) | 49/49 PASS |
| Phase 4b | tb_ahb_interface (ahb_interface + CDC FIFOs + slave model) | 29/29 PASS |
| Phase 4c | tb_axi_full (axi_interface + axi_interconnect + 3×axi_sfr) | 40/40 PASS |
| Phase 4d | tb_ahb_full (ahb_interface + CDC + ahb_interconnect + 3×ahb_sfr) | 35/35 PASS |
| Phase 5 | tb_pipeline_cpu (4 programs: AXI/AHB SFR write/read + AXI/AHB IRQ) | 4/4 PASS |
| Phase 6a | tb_soc_top (batch runner: tất cả 16 programs Phase3+5+6 qua soc_top với reset) | 16/16 PASS |
| Phase 6b | tb_compliance (compliance framework: shifts, compare, dmem_endurance) | 3/3 TEST_PASS |

**Lệnh chạy:**
```bash
cd SIM && make p3_all          # Phase 3: 9 programs
make integ_axi                 # Phase 4a: AXI interface
make integ_ahb                 # Phase 4b: AHB interface
make integ_axi_full            # Phase 4c: AXI full path
make integ_ahb_full            # Phase 4d: AHB full path
make p5_all                    # Phase 5: 4 programs AXI/AHB SFR + IRQ
make system                    # Phase 6a: batch runner 16 programs
make p6_compliance             # Phase 6b: compliance programs
make p6_all                    # Phase 6: cả 6a + 6b
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
| Branch/Jump | flush IF1/IF2 và IF2/ID | 2 slots flushed |
| Bus stall | stall toàn pipeline | N (đến khi xong) |
