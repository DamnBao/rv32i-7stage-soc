# IMPLEMENTATION.md — Quá Trình Thực Hiện Dự Án RISC-V SoC

**Dự án:** CPU RV32I + Zicsr SoC với ngoại vi AXI-Lite và AHB-Lite  
**Ngày hoàn thành:** 2026-06-20  
**Tổng thời gian:** Nhiều session trải dài qua nhiều ngày

---

## Mục Lục

1. [Môi Trường Phát Triển](#1-môi-trường-phát-triển)
2. [Công Cụ Sử Dụng](#2-công-cụ-sử-dụng)
3. [Cấu Trúc Thư Mục Dự Án](#3-cấu-trúc-thư-mục-dự-án)
4. [Tổng Quan Quy Trình](#4-tổng-quan-quy-trình)
5. [Giai Đoạn 1 — Thiết Kế Kiến Trúc](#5-giai-đoạn-1--thiết-kế-kiến-trúc)
6. [Giai Đoạn 2 — Triển Khai RTL (Bottom-Up)](#6-giai-đoạn-2--triển-khai-rtl-bottom-up)
7. [Giai Đoạn 3 — Viết Testbench và Test Programs](#7-giai-đoạn-3--viết-testbench-và-test-programs)
8. [Giai Đoạn 4 — Quy Trình Verify Từng Pha](#8-giai-đoạn-4--quy-trình-verify-từng-pha)
9. [Quy Trình Debug Khi Gặp Lỗi](#9-quy-trình-debug-khi-gặp-lỗi)
10. [Quản Lý Dự Án và Tài Liệu](#10-quản-lý-dự-án-và-tài-liệu)

---

## 1. Môi Trường Phát Triển

### 1.1 Hệ Điều Hành

```
OS:     Ubuntu 24.04 LTS (chạy dưới WSL2 trên Windows)
Kernel: Linux 5.15.167.4-microsoft-standard-WSL2
Shell:  bash
```

WSL2 (Windows Subsystem for Linux 2) cho phép chạy môi trường Linux đầy đủ trên Windows, phù hợp cho phát triển phần cứng vì các công cụ EDA (Electronic Design Automation) chủ yếu được thiết kế cho Linux.

### 1.2 Editor và IDE

Toàn bộ RTL và testbench được viết bằng **text editor** (không dùng GUI IDE chuyên dụng như Vivado hay Quartus). Kiểm tra lỗi cú pháp và semantic qua compiler Icarus Verilog — đây là cách tiếp cận thủ công nhưng hiệu quả cho dự án quy mô luận văn vì:

- Không phụ thuộc vào license của tool thương mại
- Vòng lặp compile-simulate rất nhanh (< 5 giây cho toàn bộ RTL)
- Dễ tích hợp với Makefile và script automation

---

## 2. Công Cụ Sử Dụng

### 2.1 Icarus Verilog (iverilog + vvp)

**Version:** Icarus Verilog 12  
**Cài đặt:** `sudo apt install iverilog`  
**Mục đích:** Compile và simulate SystemVerilog/Verilog

Icarus Verilog gồm hai thành phần:

| Công cụ | Chức năng |
|---------|-----------|
| `iverilog` | Compiler: phân tích cú pháp, type-checking, tạo file VVP (intermediate bytecode) |
| `vvp` | Runtime: thực thi simulation từ file VVP |

**Flag quan trọng:**

```bash
iverilog -g2012        # Bật SystemVerilog 2012 syntax
         -Wall         # Bật tất cả warning (net undeclared, width mismatch, ...)
         -o out.vvp    # Output file
         src1.sv src2.sv ...  # Source files (không cần thứ tự đặc biệt)

vvp out.vvp            # Chạy simulation
    +HEX=<path>        # Truyền plusarg (runtime argument) cho testbench
    +DUMP=<vcd>        # Kích hoạt VCD dump
```

**Hạn chế của Icarus Verilog 12 cần lưu ý:**

1. **Không hỗ trợ bit/part-select trong `always_*` block** — phải bóc tách ra `assign`:
   ```sv
   // SAI (Icarus báo lỗi):
   always_comb begin
       case (instr[14:12]) ...  // ERROR: part-select không cho phép
   end

   // ĐÚNG:
   logic [2:0] funct3;
   assign funct3 = instr[14:12];
   always_comb begin
       case (funct3) ...        // OK
   end
   ```

2. **Không hỗ trợ named task arguments** — phải dùng positional args:
   ```sv
   // SAI:
   check_output(.result(alu_out), .expected(32'h5));
   // ĐÚNG:
   check_output(alu_out, 32'h5);
   ```

3. **`always_ff`, `always_comb`, `always_latch`** được hỗ trợ với `-g2012`

4. **String handling** trong testbench (`string`, `$value$plusargs`) hoạt động với `-g2012`

### 2.2 GNU RISC-V Toolchain

**Version:** `riscv64-unknown-elf-gcc 13.2.0`  
**Cài đặt:** `sudo apt install gcc-riscv64-unknown-elf`  
**Mục đích:** Compile assembly programs → ELF → Verilog hex

Toolchain gồm các công cụ sử dụng trong dự án:

| Công cụ | Flag quan trọng | Chức năng |
|---------|----------------|-----------|
| `riscv64-unknown-elf-gcc` | `-march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T link.ld` | Compile `.s` → `.elf` |
| `riscv64-unknown-elf-objcopy` | `-O verilog --verilog-data-width 4` | Chuyển `.elf` → `.hex` (Verilog format) |
| `riscv64-unknown-elf-objdump` | `-d` | Disassemble `.elf` để kiểm tra encoding |

**Tại sao `riscv64-unknown-elf` cho target 32-bit?**  
Tên toolchain là 64-bit nhưng hỗ trợ cả 32-bit qua flag `-march=rv32i_zicsr -mabi=ilp32`. Không có package `riscv32-unknown-elf` riêng trên Ubuntu 24.04 apt.

**Linker Script (`link_default.ld`):**
```
MEMORY {
    ROM (rx)  : ORIGIN = 0x00000000, LENGTH = 64K   /* IMEM */
    RAM (rwx) : ORIGIN = 0x00010000, LENGTH = 64K   /* DMEM */
}
SECTIONS {
    .text : { *(.text) } > ROM
    .data : { *(.data) } > RAM
    .bss  : { *(.bss)  } > RAM
}
```

Đặt code tại 0x0000_0000 (IMEM) và data tại 0x0001_0000 (DMEM), phù hợp với memory map của SoC.

**Format `.hex` của Verilog:**
```
// Format xuất bởi objcopy -O verilog:
@00000000        // Địa chỉ (word-aligned, byte address / 4)
13 00 00 00      // Data: 4 bytes, little-endian
93 00 10 00      // ...
```
`$readmemh` trong testbench đọc format này và nạp vào mảng IMEM.

### 2.3 GNU Make

**Version:** Make 4.3  
**File:** `SIM/Makefile`  
**Mục đích:** Tự động hóa toàn bộ quy trình compile → simulate → report

Makefile tổ chức theo các phân nhóm target:

```makefile
# Khai báo công cụ và flags
IV      := iverilog -g2012 -Wall
VVP     := vvp
GCC     := riscv64-unknown-elf-gcc
OBJCOPY := riscv64-unknown-elf-objcopy
CFLAGS  := -march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -T link_default.ld

# Nhóm RTL source
RTL_CPU = $(RTL)/if1_stage.sv ... $(RTL)/zicsr.sv
RTL_AXI = $(RTL)/axi_interface.sv ...
RTL_ALL = $(RTL_INFRA) $(RTL_MEM) $(RTL_CPU) $(RTL_AXI) $(RTL_AHB) $(RTL)/soc_top.sv

# Pattern rule cho programs
programs/%.hex: programs/%.s
    $(GCC) $(CFLAGS) -o programs/$*.elf $<
    $(OBJCOPY) -O verilog --verilog-data-width 4 programs/$*.elf programs/$*.hex
```

Make sử dụng **dependency tracking**: nếu một `.s` file thay đổi, chỉ `.hex` tương ứng được rebuild, không cần rebuild toàn bộ.

### 2.4 GTKWave (Waveform Viewer)

**Version:** GTKWave 3.3.x  
**Cài đặt:** `sudo apt install gtkwave`  
**Mục đích:** Xem waveform từ VCD file để debug RTL

VCD (Value Change Dump) được tạo trong testbench:
```sv
$dumpfile("wave_debug.vcd");
$dumpvars(0, tb_module);  // Dump tất cả signal trong module và submodule
```

GTKWave cho phép zoom vào từng cycle, đặt cursor để đo timing, so sánh giá trị tín hiệu — rất hiệu quả khi debug pipeline hazard hoặc CDC timing issue.

### 2.5 Cấu Hình Makefile Cho VCD

```bash
make p3_wave_forwarding   # Compile + simulate với VCD dump
# → tạo integration/wave_forwarding.vcd
# → mở bằng: gtkwave integration/wave_forwarding.vcd
```

---

## 3. Cấu Trúc Thư Mục Dự Án

```
riscv_soc_thesis/
│
├── CLAUDE.md                    ← Tài liệu kiến trúc + trạng thái dự án
│
├── RTL/                         ← Toàn bộ source code RTL (SystemVerilog)
│   ├── reset_sync.sv
│   ├── async_fifo.sv
│   ├── imem.sv, dmem.sv
│   ├── if1_stage.sv, if1_if2_reg.sv
│   ├── if2_stage.sv, if2_id_reg.sv
│   ├── id_decoder.sv, register_file.sv, id_ex_reg.sv
│   ├── alu.sv, branch_comp.sv, addr_adder.sv
│   ├── ex_mem1_reg.sv
│   ├── mem1_stage.sv, mem1_mem2_reg.sv
│   ├── mem2_stage.sv, mem2_wb_reg.sv
│   ├── wb_stage.sv
│   ├── hazard_unit.sv, forwarding_unit.sv
│   ├── zicsr.sv
│   ├── axi_interface.sv, axi_interconnect.sv, axi_sfr.sv
│   ├── ahb_interface.sv, ahb_interconnect.sv, ahb_sfr.sv
│   └── soc_top.sv
│
├── SIM/                         ← Toàn bộ verification environment
│   ├── Makefile
│   ├── TEST_LOG.md              ← Nhật ký chi tiết từng session
│   ├── link_default.ld          ← Linker script
│   │
│   ├── unit/                    ← Phase 1+2: Unit testbenches
│   │   ├── tb_alu.sv
│   │   ├── tb_branch_comp.sv
│   │   ├── tb_register_file.sv
│   │   ├── tb_id_decoder.sv
│   │   ├── tb_forwarding_unit.sv
│   │   ├── tb_hazard_unit.sv
│   │   └── tb_async_fifo.sv
│   │
│   ├── integration/             ← Phase 3+4: Integration testbenches
│   │   ├── tb_pipeline_cpu.sv   ← Full CPU runner (Phase 3 + 5)
│   │   ├── tb_axi_interface.sv
│   │   ├── tb_ahb_interface.sv
│   │   ├── tb_axi_full.sv
│   │   └── tb_ahb_full.sv
│   │
│   ├── system/                  ← Phase 6: System testbenches
│   │   ├── tb_soc_top.sv        ← Batch runner 16 programs
│   │   └── tb_compliance.sv     ← Single-program compliance runner
│   │
│   ├── programs/                ← Test programs (assembly → hex)
│   │   ├── prog_arithmetic.s/.hex
│   │   ├── prog_forwarding.s/.hex
│   │   ├── prog_load_store.s/.hex
│   │   ├── prog_branch_jump.s/.hex
│   │   ├── prog_csr.s/.hex
│   │   ├── prog_ecall.s/.hex
│   │   ├── prog_interrupt_msi.s/.hex
│   │   ├── prog_interrupt_mei.s/.hex
│   │   ├── prog_load_fault.s/.hex
│   │   ├── prog_axi_sfr.s/.hex
│   │   ├── prog_ahb_sfr.s/.hex
│   │   ├── prog_axi_irq.s/.hex
│   │   ├── prog_ahb_irq.s/.hex
│   │   ├── prog_rv32i_shifts.s/.hex
│   │   ├── prog_rv32i_compare.s/.hex
│   │   └── prog_dmem_endurance.s/.hex
│   │
│   ├── models/                  ← Simulation-only slave models
│   │   ├── axi_slave_model.sv
│   │   └── ahb_slave_model.sv
│   │
│   └── scripts/
│       └── run_one_test.sh      ← Compliance runner script
│
└── Document/
    ├── SPEC.md                  ← Đặc tả kỹ thuật (file này + các file khác)
    ├── IMPLEMENTATION.md        ← Quá trình thực hiện (file này)
    ├── TESTPLAN.md              ← Kế hoạch test
    └── TESTBENCH_STRATEGY.md   ← Chiến lược testbench
```

---

## 4. Tổng Quan Quy Trình

Dự án được thực hiện theo mô hình **bottom-up design với incremental verification**: thiết kế và verify từng module nhỏ trước, sau đó ghép lại theo từng cấp độ. Mỗi cấp độ chỉ được tiến hành khi cấp thấp hơn đã ổn định.

```
┌─────────────────────────────────────────────────────────┐
│                    VÒNG LẶP THIẾT KẾ                    │
│                                                          │
│   Phân tích yêu cầu                                      │
│         ↓                                                │
│   Thiết kế kiến trúc (interface, FSM, timing)           │
│         ↓                                                │
│   Viết RTL (SystemVerilog synthesizable)                │
│         ↓                                                │
│   Compile (iverilog) → sửa lỗi cú pháp                  │
│         ↓                                                │
│   Viết testbench + test cases                            │
│         ↓                                                │
│   Simulate (vvp) → kiểm tra output                      │
│         ↓                                                │
│   PASS? ──YES──→ Tiến lên cấp tiếp theo                │
│    │                                                     │
│    NO                                                    │
│    ↓                                                     │
│   Debug (waveform / printf / assertion)                  │
│         ↓                                                │
│   Sửa RTL hoặc testbench                                │
│         ↓                                                │
│   Regression test (chạy lại tất cả test đã qua)        │
│         ↓                                                │
│   Quay về "Simulate"                                     │
└─────────────────────────────────────────────────────────┘
```

**Nguyên tắc quan trọng trong vòng lặp:**

- **Không tiến lên khi còn lỗi ở cấp thấp.** Lỗi trong unit không thể debug ở level integration — tín hiệu sai sẽ lan truyền và che giấu root cause.
- **Regression sau mỗi fix.** Bất kỳ thay đổi nào trong RTL đều phải chạy lại toàn bộ test suite đã pass trước đó để đảm bảo không gây regression.
- **Mỗi test program phải verify đúng một điều.** Chương trình quá lớn gộp nhiều feature sẽ khó isolate khi fail.

---

## 5. Giai Đoạn 1 — Thiết Kế Kiến Trúc

### 5.1 Xác Định Yêu Cầu

Trước khi viết bất kỳ dòng RTL nào, cần xác định rõ:

**Yêu cầu chức năng:**
- Tập lệnh: RV32I (47 lệnh) + Zicsr (6 lệnh CSR + exception handling)
- Pipeline: 7 tầng, in-order, đơn luồng (no superscalar)
- Tần số đích: 1GHz (CPU), 500MHz (AHB peripherals)
- Hazard resolution: hoàn toàn tự động (không cần compiler insert NOPs)
- Interrupt: M-mode, vectored, 2 nguồn (AXI và AHB)

**Yêu cầu kết nối:**
- IMEM và DMEM: tích hợp sẵn, 64KB mỗi loại
- AXI-Lite peripherals: 3 slave, cùng clock domain
- AHB-Lite peripherals: 3 slave, clock domain riêng (500MHz), cần CDC

### 5.2 Quyết Định Số Tầng Pipeline

Quyết định quan trọng nhất là **số tầng pipeline**. Dự án chọn 7 tầng vì:

| Cân nhắc | Lý do |
|----------|-------|
| 5 tầng là quá ít | Không đủ để tách biệt decode, execute, và memory — 1GHz yêu cầu critical path ngắn |
| 9+ tầng là quá nhiều | Branch penalty tăng, logic hazard phức tạp hơn, không cần thiết với ISA đơn giản |
| 7 tầng là phù hợp | IF1+IF2 để xử lý IMEM latency 1-cycle; MEM1+MEM2 để xử lý load latency và bus stall |

Quyết định tách IF thành IF1+IF2 và MEM thành MEM1+MEM2 là bắt buộc do:
- IMEM là synchronous (1-cycle latency) → cần IF2 để "thu" instruction
- Bus transactions (AXI/AHB) kéo dài nhiều cycle → cần MEM1 phát yêu cầu, MEM2 thu kết quả

### 5.3 Thiết Kế Interface Giữa Các Module

Trước khi viết RTL, xác định rõ interface (tất cả port names, widths, directions) của từng module:

**Nguyên tắc thiết kế interface:**
1. **Mỗi thanh ghi pipeline là module riêng** (không ghép vào stage module). Điều này giúp Hazard Unit có thể kết nối trực tiếp `stall`/`flush` vào đúng thanh ghi mà không cần routing qua stage module.
2. **Tín hiệu điều khiển propagate cùng với dữ liệu** qua pipeline registers. Ví dụ: `mem_read`, `reg_write`, `wb_sel` không chỉ ở ID — chúng được lưu trong mỗi thanh ghi pipeline và truyền qua từng tầng cho đến khi cần dùng.
3. **Bus stall và hazard stall là tín hiệu riêng biệt** — không merge sớm, để hazard_unit có thể xử lý priority logic.

### 5.4 Thiết Kế Hazard Strategy

Phân tích tất cả RAW hazard có thể xảy ra trong 7-tầng pipeline để quyết định forwarding scheme:

```
Pipeline:    IF1  IF2  ID   EX   MEM1  MEM2  WB
Producer:         ────────────────────────────→ ghi vào RF tại WB

Consumer sau 1 lệnh: khi đang ở EX, producer đang ở MEM1
  → MEM1 forwarding (gap-1)

Consumer sau 2 lệnh: khi đang ở EX, producer đang ở MEM2
  → MEM2 forwarding (gap-2)

Consumer sau 3 lệnh: khi đang ở EX, producer đang ở WB
  → WB forwarding (gap-3)

Consumer sau 4 lệnh: khi đang ở EX, producer đã ghi RF
  → WBR bypass trong register_file (gap-4)
  → Đặc biệt của pipeline 7-tầng (5-tầng không cần)
```

Lý do gap-4 đặc biệt: trong 5-tầng pipeline cổ điển, khi consumer ở EX, producer đã hoàn thành WB và RF đã cập nhật. Nhưng với 7 tầng, WB và ID có thể xảy ra CÙNG posedge (gap=4), khiến non-blocking assignment trong RF chưa cập nhật khi ID đọc trong cùng time-step. Cần WBR bypass combinational trong register_file để xử lý.

---

## 6. Giai Đoạn 2 — Triển Khai RTL (Bottom-Up)

### 6.1 Thứ Tự Thiết Kế

Module được thiết kế theo thứ tự **từ dưới lên**, đảm bảo mỗi module chỉ phụ thuộc vào các module đã hoàn thiện và verify:

```
Cấp 0 — Infrastructure:
  reset_sync.sv       (không phụ thuộc gì)
  async_fifo.sv       (không phụ thuộc gì)

Cấp 1 — Memories và leaf modules:
  imem.sv, dmem.sv
  alu.sv, branch_comp.sv, addr_adder.sv
  register_file.sv
  id_decoder.sv

Cấp 2 — Pipeline stages:
  if1_stage.sv, if2_stage.sv
  if1_if2_reg.sv, if2_id_reg.sv, id_ex_reg.sv
  ex_mem1_reg.sv, mem1_stage.sv
  mem1_mem2_reg.sv, mem2_stage.sv
  mem2_wb_reg.sv, wb_stage.sv

Cấp 3 — Control units:
  hazard_unit.sv, forwarding_unit.sv
  zicsr.sv

Cấp 4 — Bus interfaces:
  axi_interface.sv, axi_interconnect.sv, axi_sfr.sv
  ahb_interface.sv, ahb_interconnect.sv, ahb_sfr.sv

Cấp 5 — Top level:
  soc_top.sv
```

### 6.2 Thiết Kế Module Cơ Sở

#### `reset_sync.sv`

Module đơn giản nhất: 2 flip-flop nối tiếp để đồng bộ deassert của reset_n. Được viết trước vì cần dùng để tạo `rst_ahb_n` cho AHB domain.

```sv
// 2-FF synchronizer cho reset_n
always_ff @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) {sync_rst_n, ff1} <= 2'b00;  // async assert
    else              {sync_rst_n, ff1} <= {ff1, 1'b1};  // sync deassert
end
```

#### `async_fifo.sv`

Module CDC quan trọng nhất. Các quyết định thiết kế:

- **Depth = 2** (power-of-2 minimum): Đủ vì CPU bị stall khi giao dịch bus, đảm bảo không có thêm transaction nào được ghi trong khi FIFO đang xử lý transaction hiện tại. Depth lớn hơn tốn tài nguyên không cần thiết.

- **Không có `full` flag**: Vì CPU bị stall khi `bus_stall_req=1`, không bao giờ có tình huống producer viết liên tục khi FIFO đầy. Chỉ cần `empty` flag để biết khi nào có data để đọc.

- **Gray code pointer**: 2-bit binary counter (giá trị 0-3) được convert sang Gray code trước khi đồng bộ qua 2-FF synchronizer. Đảm bảo chỉ 1 bit thay đổi mỗi bước → an toàn khi lấy mẫu ở domain khác.

#### `id_decoder.sv`

Module lớn nhất và phức tạp nhất ở cấp 1, decode 47 lệnh RV32I + 6 lệnh CSR thành các tín hiệu điều khiển. Thiết kế dùng case statement phân cấp:

```
case(opcode):
  7'b0110011: R-type (ADD/SUB/AND/OR/XOR/SLL/SRL/SRA/SLT/SLTU)
    case(funct3, funct7):
      ...
  7'b0010011: I-type ALU (ADDI/ANDI/ORI/XORI/SLLI/SRLI/SRAI/SLTI/SLTIU)
  7'b0000011: Load (LW/LH/LB/LHU/LBU)
  7'b0100011: Store (SW/SH/SB)
  7'b1100011: Branch (BEQ/BNE/BLT/BGE/BLTU/BGEU)
  7'b1101111: JAL
  7'b1100111: JALR
  7'b0110111: LUI
  7'b0010111: AUIPC
  7'b1110011: System (ECALL/EBREAK/MRET/CSR*)
  default:    illegal_instr = 1
```

Vì Icarus không cho phép `instr[14:12]` trong `always_comb`, tất cả bit-select phải được bóc tách:

```sv
logic [6:0] opcode;
logic [2:0] funct3;
logic [6:0] funct7;
logic [4:0] rs1, rs2, rd;

assign opcode = instr[6:0];
assign funct3 = instr[14:12];
assign funct7 = instr[31:25];
assign rs1    = instr[19:15];
assign rs2    = instr[24:20];
assign rd     = instr[11:7];

always_comb begin
    case (opcode)
        7'b0110011: begin
            case (funct3)  // Dùng biến đã bóc tách, không phải instr[14:12]
```

### 6.3 Thiết Kế Pipeline Stages và Registers

#### Nguyên Tắc Chung Cho Tất Cả Pipeline Registers

Tất cả `*_reg.sv` follow cùng một template:

```sv
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)      begin /* reset all to 0/NOP */ end
    else if (flush)  begin /* clear to 0/NOP (insert bubble) */ end
    else if (!stall) begin /* latch new values from upstream */ end
    // else: stall=1, giữ nguyên (implicit)
end
```

**Tại sao flush trước stall?**  
Khi cả `flush=1` và `stall=1` đồng thời (ví dụ: bus stall + load-use):
- Nếu stall thắng: thanh ghi giữ nguyên instruction đang chờ. Khi stall giải phóng, instruction đó vào tầng tiếp theo — nhưng đây là instruction đáng lẽ bị cancel (ví dụ: wrong-path instruction sau branch).
- Nếu flush thắng: thanh ghi bị clear → NOP bubble. Instruction bị cancel đúng lúc.

**Exception:** Trong `id_ex_reg.sv`, flush kiểm tra trước stall là đặc biệt quan trọng vì hazard_unit có thể phát `flush_id_ex=1` (để insert bubble cho load-use) ĐỒNG THỜI với `stall_id_ex=1` (từ bus_stall). Flush phải thắng.

#### `mem1_stage.sv` — Module Phức Tạp Nhất Trong Pipeline

MEM1 là trung tâm của address decode, bus control, và stall generation. Quyết định thiết kế:

**Address decoder dùng bit-slicing, không dùng range comparison:**
```sv
// Kiểm tra địa chỉ DMEM (0x0001_xxxx):
logic [15:0] addr_31_16;
assign addr_31_16 = alu_result_in[31:16];  // Bóc tách theo rule Icarus
always_comb begin
    if (addr_31_16 == 16'h0001) begin
        // DMEM path
    end else if (addr_31_16[15:12] == 4'h2) begin
        // AXI path
    end ...
end
```

**Bus stall logic:**

`bus_stall_req` được set ngay khi address decode xác định đây là AXI/AHB access:
- Với AXI: `bus_stall_req = axi_req_valid && !axi_resp_valid` — stall cho đến khi AXI interface báo response hoàn tất.
- Với AHB: `bus_stall_req = req_fifo_sent && resp_fifo_rd_empty` — stall cho đến khi Response FIFO có data (AHB transaction hoàn tất từ 500MHz domain).

### 6.4 Thiết Kế Hazard Unit

Hazard unit là module "pure logic" (combinational, không có FF) — toàn bộ là `assign` statements. Điều này đảm bảo stall/flush tín hiệu update ngay trong cùng cycle mà hazard condition thay đổi.

**Quy trình thiết kế hazard_unit:**

1. **Liệt kê tất cả hazard conditions** từ spec pipeline
2. **Với mỗi hazard, xác định**: tầng nào bị stall, tầng nào bị flush, và bao nhiêu cycle
3. **Viết từng assign statement**, đặt tên rõ ràng cho từng điều kiện
4. **Combine signals** với ưu tiên đúng (zicsr_flush ưu tiên cao nhất)

```sv
// Load-use detection
assign load_use_stall = ex_mem_read &&
    ((ex_rd_addr == id_rs1_addr && id_rs1_addr != 5'd0) ||
     (ex_rd_addr == id_rs2_addr && id_rs2_addr != 5'd0));

// CSR-use detection (3 stages: EX, MEM1, MEM2)
assign csr_stall_ex   = (ex_wb_sel   == 2'b11) && ex_reg_write   && /* addr match */;
assign csr_stall_mem1 = (mem1_wb_sel == 2'b11) && mem1_reg_write && /* addr match */;
assign csr_stall_mem2 = (mem2_wb_sel == 2'b11) && mem2_reg_write && /* addr match */;

assign fetch_stall = load_use_stall | csr_stall_ex | csr_stall_mem1 | csr_stall_mem2;

// Branch/jump flush
assign ctrl_flush = branch_taken | jump;

// Flush với bus_stall suppression (quan trọng!)
assign flush_id_ex = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush;
```

### 6.5 Thiết Kế Zicsr

Zicsr là module state machine phức tạp nhất, xử lý:
- 6 thanh ghi CSR với read/write semantics khác nhau (RW/RS/RC)
- Priority giữa exception và interrupt
- 2-FF synchronizer nội bộ cho AHB IRQ
- Condition checking để không flush khi bus_stall active

**CSR write logic:**

```sv
// CSR write: hỗ trợ CSRRW/CSRRS/CSRRC và variant immediate
always_ff @(posedge clk or negedge rst_n) begin
    if (wb_csr_we) begin
        logic [31:0] src;
        src = wb_csr_imm_sel ? {27'd0, wb_imm[4:0]} : wb_rs1_data;
        case (wb_csr_op)
            2'b01: csr_regs[addr] <= src;            // CSRRW: replace
            2'b10: csr_regs[addr] <= csr_regs[addr] | src;  // CSRRS: set bits
            2'b11: csr_regs[addr] <= csr_regs[addr] & ~src; // CSRRC: clear bits
        endcase
    end
end
```

**Trap handling với precise exception:**
```sv
// Không trap khi đang có bus transaction
assign can_trap = !bus_stall_req;

always_ff @(posedge clk or negedge rst_n) begin
    if (can_trap && (exception_pending || interrupt_pending)) begin
        mepc    <= exception_pending ? wb_pc : next_pc;
        mcause  <= trap_cause;
        mstatus <= {mstatus[31:8], mstatus[3], mstatus[7:4], 1'b0, mstatus[2:0]};
        // MPIE ← MIE; MIE ← 0
        zicsr_flush <= 1;
        zicsr_pc    <= mtvec_base + (4 * cause_code);  // vectored
    end
end
```

### 6.6 Thiết Kế AXI Interface

AXI interface là FSM chuyển đổi giữa giao thức CPU-internal và AXI4-Lite. Các trạng thái FSM được thiết kế để minimal — không có trạng thái dư thừa:

**Write path (2 handshakes song song: AW+W → B):**
```
IDLE → WRITE_ADDR_DATA → WRITE_RESP → IDLE
```
- Trong WRITE_ADDR_DATA: phát AWVALID=WVALID=1 đồng thời (AXI4-Lite cho phép)
- Chuyển sang WRITE_RESP khi cả AWREADY=WREADY=1

**Read path (2 handshakes tuần tự: AR → R):**
```
IDLE → READ_ADDR → READ_DATA → IDLE
```
- Phát ARVALID=1, chờ ARREADY=1
- Chờ RVALID=1, latch RDATA, phát RREADY=1

`bus_stall_req` ở MEM1 được maintain cho đến khi `axi_resp_valid=1`.

### 6.7 Thiết Kế AHB Interface

AHB phức tạp hơn AXI ở điểm: AHB có pipelining giữa Address Phase và Data Phase. Tuy nhiên, vì mỗi lần CPU chỉ có 1 giao dịch (stall đảm bảo không có giao dịch tiếp theo khi giao dịch hiện tại chưa xong), FSM được đơn giản hóa thành sequential (không cần xử lý pipelining):

```
IDLE → ADDR_PHASE → DATA_PHASE → IDLE
```

Trong ADDR_PHASE: phát HADDR, HTRANS=NONSEQ, HSIZE, HWRITE.  
Trong DATA_PHASE: phát HWDATA (nếu write); chờ HREADY=1; latch HRDATA (nếu read) → ghi vào Response FIFO.

### 6.8 Thiết Kế soc_top.sv

`soc_top.sv` là file kết nối thuần túy — không có logic riêng (chỉ là wire declarations và module instantiations). Quy trình viết:

1. **Khai báo tất cả internal wires** theo từng nhóm (CPU signals, memory signals, AXI signals, AHB signals)
2. **Instantiate từng module** theo thứ tự: memories → CPU stages → bus interfaces → top-level
3. **Kết nối từng port** cẩn thận, chú ý:
   - `imem.stall` ← `stall_if1_if2` (không phải fetch_stall — quan trọng!)
   - `imem.flush` ← `flush_if1_if2`
   - `if1_stage.jump_addr` ← `zicsr_flush ? zicsr_pc : addr_adder_out`
   - `hazard_unit`: kết nối đầy đủ tất cả wb_sel signals từ pipeline registers
4. **Compile với tất cả RTL** để kiểm tra connectivity (Icarus báo unused port, unconnected wire)

Compile lần đầu thường có nhiều warning về "implicit wire". Phải giải quyết từng warning — implicit wire thường là bug kết nối (typo tên signal, missing connection).

---

## 7. Giai Đoạn 3 — Viết Testbench và Test Programs

### 7.1 Triết Lý Testbench

Dự án sử dụng hai loại testbench theo tầng:

**Unit testbench:** Test module đơn lẻ với các stimulus được tạo thủ công trong testbench. Kiểm tra từng corner case của từng tín hiệu output.

**Integration testbench:** Chạy chương trình assembly thực tế trên pipeline/SoC. Không kiểm tra từng cycle — chỉ kiểm tra kết quả cuối (x31=1 là PASS, ebreak là halt mechanism).

Hai loại bổ trợ nhau: unit test đảm bảo module behavior đúng về mặt logic; integration test đảm bảo các module tương tác đúng trong bối cảnh thực thi.

### 7.2 Viết Unit Testbench

Mỗi unit testbench follow cấu trúc:

```sv
module tb_<module_name>;
    // Instantiate DUT
    <module_name> DUT (...);

    // Task để check và report
    task check;
        input [31:0] result, expected;
        input string test_name;
        if (result === expected) begin
            $display("PASS [%s]", test_name);
            pass_cnt++;
        end else begin
            $display("FAIL [%s] got=%h exp=%h", test_name, result, expected);
            fail_cnt++;
        end
    endtask

    initial begin
        // Test case 1
        // Kích thích đầu vào
        operand_a = 32'h0000_0005;
        operand_b = 32'h0000_0003;
        alu_op    = 4'h0;  // ADD
        #1;  // Propagation delay cho combinational
        check(alu_result, 32'h0000_0008, "ADD basic");

        // ... nhiều test cases ...

        // Summary
        $display("=== %0d/%0d PASS ===", pass_cnt, pass_cnt + fail_cnt);
        $finish;
    end
endmodule
```

**Điểm chú ý khi viết unit testbench:**
- Dùng `===` thay vì `==` để phát hiện X/Z (don't-care) — `X === 1'b0` là false với `===`, nhưng true với `==`
- Combinational: chỉ cần `#1` (1ns) để cho propagation
- Sequential: cần `@(posedge clk)` để advance clock, kiểm tra sau `@(negedge clk)` để tránh race condition
- Không dùng `.portname(val)` trong task call — Icarus 12 báo lỗi

### 7.3 Viết Assembly Test Programs

Test programs là chương trình RISC-V assembly được thiết kế để verify pipeline behavior, không chỉ ISA correctness. Mỗi program:

1. **Thực hiện một tình huống cụ thể** (ví dụ: forwarding, load-use, branch, CSR)
2. **Kiểm tra kết quả** bằng cách compare với expected value
3. **Set x31=1** nếu tất cả đúng, **x31=0** nếu có lỗi
4. **Halt bằng EBREAK** để testbench phát hiện kết thúc

**Cấu trúc chung:**

```asm
    .text
    .global _start
_start:
    # Test case 1: <mô tả>
    addi  t0, x0, 5
    addi  t1, x0, 3
    add   t2, t0, t1     # t2 = t0 + t1 = 8
    addi  t3, x0, 8
    bne   t2, t3, fail   # Nếu sai, nhảy đến fail

    # Test case 2: ...

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
```

**Thiết kế test để bắt hazard cụ thể:**

```asm
# Test load-use hazard: LW kết quả phải đúng dù có 1-cycle stall
    lui   a0, 0x10       # a0 = DMEM base = 0x0001_0000
    addi  t0, x0, 42
    sw    t0, 0(a0)      # ghi 42 vào DMEM[0]
    lw    t1, 0(a0)      # load → t1 = 42 (load-use stall ở đây nếu next instr dùng t1)
    addi  t2, x0, 42     # ← lệnh này cách LW đúng 1 (gap-1, nhưng không dùng t1)
    addi  t3, t1, 0      # ← lệnh này dùng t1: gap-2 → MEM2 forwarding
    bne   t3, t2, fail
```

**Thiết kế test cho AXI/AHB:**

Programs AXI/AHB cần cẩn thận về:
- Không có gap giữa SW và LW trên cùng địa chỉ (SW stall + LW load-use có thể conflict)
- Với AHB IRQ: cần đủ NOP để CDC propagate (ít nhất 5 NOPs sau khi set REG7[0])

### 7.4 Halt Mechanism (EBREAK + x31)

Tất cả programs dùng cùng một cơ chế dừng:
- `addi x31, x0, 1; ebreak` — PASS
- `addi x31, x0, 0; ebreak` — FAIL

Testbench phát hiện EBREAK qua tín hiệu `wb_ebreak` (internal wire trong soc_top):
```sv
always @(posedge clk_cpu) begin
    if (rst_n && u_soc.wb_ebreak) begin
        if (u_soc.u_rf.registers[31] == 32'd1)
            $display("PASS");
        else
            $display("FAIL x31=%0d", u_soc.u_rf.registers[31]);
        $finish;
    end
end
```

Cách tiếp cận này cho phép test program tự report kết quả — testbench không cần biết chi tiết logic bên trong program.

---

## 8. Giai Đoạn 4 — Quy Trình Verify Từng Pha

Verification được tổ chức thành 6 phase tăng dần complexity:

### Phase 1: Unit Test — Combinational và Clocked

**Mục tiêu:** Verify từng module leaf hoạt động đúng spec trước khi ghép vào pipeline.

**Modules và test count:**

| Module | Testbench | Test cases | Nội dung chính |
|--------|-----------|-----------|----------------|
| `alu.sv` | `tb_alu.sv` | 38 | Tất cả alu_op, overflow, zero, negative |
| `branch_comp.sv` | `tb_branch_comp.sv` | 25 | BEQ/BNE/BLT/BGE/BLTU/BGEU với signed/unsigned edge cases |
| `register_file.sv` | `tb_register_file.sv` | 17 | Read/write, x0 hardwired, WBR bypass |
| `id_decoder.sv` | `tb_id_decoder.sv` | 112 | Tất cả 47 lệnh RV32I + 6 CSR + illegal |

**Quy trình:**
```bash
make unit_alu      # → tb_alu.vvp → simulate → 38/38 PASS
make unit_branch   # → 25/25 PASS
make unit_rf       # → 17/17 PASS
make unit_decoder  # → 112/112 PASS
make unit_all      # Chạy tất cả 4 cùng lúc
```

Tổng Phase 1: **192/192 PASS**.

---

### Phase 2: Unit Test — Control Units và CDC FIFO

**Mục tiêu:** Verify forwarding_unit, hazard_unit, và async_fifo — các module điều khiển.

| Module | Test cases | Nội dung chính |
|--------|-----------|----------------|
| `forwarding_unit.sv` | 19 | fwd_sel priority: MEM1 > MEM2 > WB > RF; x0 không forward |
| `hazard_unit.sv` | 60 | load-use, CSR-use, branch flush, bus_stall, combinations |
| `async_fifo.sv` | 22 | Timing write/read, empty detection, Gray code correctness |

**Thách thức với `tb_async_fifo.sv`:**  
Hai clock domain trong testbench cần `timescale` chính xác. Đọc `rd_data` phải trên negedge trước khi assert rd_en (tránh đọc slot đã advance):

```sv
// Đọc data TRƯỚC khi advance pointer:
@(negedge rd_clk);
check(rd_data, expected_val, "Read slot 0");
rd_en = 1;
@(posedge rd_clk);
rd_en = 0;
```

Tổng Phase 2: **101/101 PASS**.

---

### Phase 3: Integration Test — Full CPU Pipeline

**Mục tiêu:** Verify toàn bộ CPU pipeline qua `soc_top` với 9 chương trình assembly thực tế.

**Testbench design (`tb_pipeline_cpu.sv`):**

```sv
// Nhận tên hex file qua plusarg
$value$plusargs("HEX=%s", hex_file);
$readmemh(hex_file, u_soc.u_imem.mem);

// Reset protocol
rst_n = 0;
repeat(10) @(posedge clk_cpu);
@(negedge clk_cpu);
rst_n = 1;

// Detect halt
always @(posedge clk_cpu) begin
    if (rst_n && u_soc.wb_ebreak) begin
        $display(u_soc.u_rf.registers[31] == 1 ? "PASS" : "FAIL");
        $finish;
    end
end

// Timeout
initial #200000 $fatal(1, "TIMEOUT");
```

**9 Programs và mục tiêu verify:**

| Program | Mục tiêu |
|---------|---------|
| `prog_arithmetic` | ADD, SUB, AND, OR, XOR, SLT, SLTU, LUI, AUIPC |
| `prog_forwarding` | Gap-1/2/3/4 RAW, forwarding MUX chọn đúng source |
| `prog_load_store` | LW/LH/LB/LHU/LBU/SW/SH/SB với DMEM |
| `prog_branch_jump` | BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, JALR |
| `prog_csr` | CSRRW/CSRRS/CSRRC/CSRxI, đọc/ghi CSR, CSR-use stall |
| `prog_ecall` | ECALL → trap → handler → MRET → resume |
| `prog_interrupt_msi` | Software interrupt (mip.MSIP), vectored mode |
| `prog_interrupt_mei` | External interrupt (mip.MEIP) từ AXI |
| `prog_load_fault` | Load Access Fault (địa chỉ không hợp lệ) |

**Lệnh chạy:**
```bash
make p3_all            # Chạy 9 programs tuần tự
make p3_wave_csr       # Dump VCD để debug prog_csr
```

Tổng Phase 3: **9/9 PASS** (sau khi sửa 4 bugs, xem TESTRESULT.md).

---

### Phase 4: Integration Test — Bus Interfaces

**Mục tiêu:** Verify từng bus interface riêng biệt trước khi kết nối với CPU.

**Phase 4a — AXI Interface:**

`tb_axi_interface.sv` instantiate `axi_interface.sv` + `axi_slave_model.sv` (behavioral slave mô phỏng handshake AXI-Lite). Test bao gồm:
- Write với AWREADY/WREADY trễ 1/2/3 cycle
- Read với ARREADY trễ, RVALID trễ
- BRESP/RRESP = ERROR → `axi_resp_err=1`
- Address alignment, size variations

Slave model được viết behavioral — không synthesizable, chỉ dùng cho simulation.

**Phase 4b — AHB Interface:**

`tb_ahb_interface.sv` instantiate chain: `async_fifo` (Request) + `ahb_interface` + `ahb_slave_model` + `async_fifo` (Response). Test 2-domain clock: `clk_cpu` (1GHz) + `clk_ahb` (500MHz, phase offset 0.3ns).

Phase offset 0.3ns mô phỏng realistic asynchronous relationship giữa hai clock domain — nếu hai clock đồng pha hoàn toàn, timing của CDC có thể bị "lucky" và mask được metastability issues.

**Phase 4c — AXI Full Path:**

`tb_axi_full.sv` instantiate `axi_interface + axi_interconnect + 3×axi_sfr`. Test address routing đến đúng slave, cross-slave isolation.

**Phase 4d — AHB Full Path:**

Tương tự 4c với AHB + CDC FIFOs.

```bash
make integ_axi         # 49/49 PASS
make integ_ahb         # 29/29 PASS
make integ_axi_full    # 40/40 PASS
make integ_ahb_full    # 35/35 PASS
```

Tổng Phase 4: **153/153 PASS**.

---

### Phase 5: Full SoC Integration — CPU + Bus

**Mục tiêu:** Verify CPU thực tế truy cập AXI/AHB SFR và xử lý interrupt từ ngoại vi.

4 programs chạy qua `soc_top` hoàn chỉnh:

| Program | Verify |
|---------|--------|
| `prog_axi_sfr` | CPU SW→AXI SFR, CPU LW←AXI SFR, verify giá trị; 3 slaves |
| `prog_ahb_sfr` | CPU SW→AHB SFR qua CDC, CPU LW←AHB SFR; verify |
| `prog_axi_irq` | CPU kích hoạt AXI IRQ → MEI trap → handler → MRET |
| `prog_ahb_irq` | CPU kích hoạt AHB IRQ → CDC propagate → MEI trap → MRET |

Đây là pha khó nhất — phát hiện bug hazard nghiêm trọng khi `bus_stall_req=1` và `load_use_stall=1` đồng thời (xem chi tiết trong TESTRESULT.md).

```bash
make p5_all   # 4/4 PASS
```

---

### Phase 6: System Test và Compliance

**Phase 6a — Batch System Test:**

`tb_soc_top.sv` chạy tất cả 16 programs trong một lần, với reset SoC đầy đủ và clear DMEM giữa mỗi program. Đây là "smoke test" hệ thống hoàn chỉnh.

```bash
make system   # 16/16 PASS
```

**Phase 6b — Compliance Framework:**

`tb_compliance.sv` + `scripts/run_one_test.sh` tạo infrastructure cho compliance testing: nhận ELF file, convert sang hex, chạy simulation, parse `TEST_PASS`/`TEST_FAIL` output. 3 programs compliance mới verify coverage ISA còn thiếu.

```bash
make p6_compliance   # 3/3 TEST_PASS
```

---

## 9. Quy Trình Debug Khi Gặp Lỗi

### 9.1 Tổng Quan Workflow Debug

Khi một test FAIL hoặc TIMEOUT, quy trình debug bao gồm 5 bước:

```
1. Tái hiện lỗi (Reproduce)
        ↓
2. Isolate vùng có vấn đề (Narrow down)
        ↓
3. Quan sát chi tiết (Observe)
        ↓
4. Tìm root cause (Root cause analysis)
        ↓
5. Sửa và verify (Fix + Regression)
```

### 9.2 Bước 1: Tái Hiện và Phân Loại

Trước hết, phân biệt loại lỗi:

| Triệu chứng | Khả năng nguyên nhân |
|-------------|---------------------|
| Compile error | Lỗi cú pháp, type mismatch, missing port |
| TIMEOUT (không đến EBREAK) | Vòng lặp vô hạn, infinite loop do branch target sai, pipeline bị freeze |
| FAIL (x31=0) | Logic sai, hazard không được xử lý, wrong forwarding |
| PASS nhưng sai giá trị trung gian | Bug trong module cụ thể (phát hiện qua $display hoặc waveform) |

### 9.3 Bước 2: Isolate

**Chiến lược bisect:**
- Nếu integration FAIL: chạy lại unit tests của từng module liên quan. Nếu unit pass nhưng integration fail → bug ở integration (kết nối, timing interaction).
- Nếu một program trong nhiều programs FAIL: chạy riêng program đó với waveform dump.
- Nếu program dài FAIL: thêm `ebreak` intermediate để bisect — xác định phần nào của program fail trước.

**Ví dụ bisect program:**
```asm
_start:
    # Nhóm test 1: arithmetic
    addi t0, x0, 5
    ...
    addi x31, x0, 1
    ebreak      # ← Thêm ebreak intermediate; chạy: nếu PASS thì lỗi ở nhóm sau

    # Nhóm test 2: load-store
    ...
```

### 9.4 Bước 3: Quan Sát — VCD Waveform

Đây là công cụ mạnh nhất khi debug pipeline:

```bash
# Bật VCD trong testbench:
make p3_wave_csr     # Tạo wave_csr.vcd
gtkwave integration/wave_csr.vcd &
```

Trong GTKWave, thêm các tín hiệu cần quan sát:
- `clk_cpu`, `rst_n` — để xác định timing
- `if1_stage.pc_out` — PC hiện tại
- `if2_id_reg.pc`, `if2_id_reg.instr` — instruction đang ở ID
- `id_ex_reg.rd_addr`, `id_ex_reg.alu_op` — lệnh ở EX
- `hazard_unit.stall_if1_if2`, `flush_id_ex` — hazard signals
- `u_rf.registers[31]` — kết quả cuối

**Kỹ thuật trace trong simulation:**  
Khi VCD quá lớn (hàng nghìn cycle), thêm `$display` có điều kiện:

```sv
// Trong testbench, monitor key signals:
always @(posedge clk_cpu) begin
    if (rst_n)
        $display("[%0t] PC=%h INSTR=%h WB_PC=%h WB_EBREAK=%b",
                 $time, u_soc.if1_stage_inst.pc_out,
                 u_soc.if2_id_reg_inst.instr,
                 u_soc.u_zicsr.wb_pc,
                 u_soc.wb_ebreak);
end
```

### 9.5 Bước 4: Root Cause Analysis

Sau khi quan sát waveform, trace ngược từ triệu chứng đến nguyên nhân:

**Ví dụ trace ngược:**
1. `x31=0` → lệnh `addi x31, x0, 0` được thực thi thay vì `addi x31, x0, 1`
2. → Một `bne` đã nhảy vào `fail` thay vì fall-through
3. → Giá trị của một thanh ghi so sánh sai
4. → Thanh ghi đó nhận dữ liệu từ load-use nhưng forwarding path sai
5. → Root cause: forwarding_unit không phát hiện MEM2→EX forwarding vì điều kiện check sai

Trace ngược này đòi hỏi hiểu biết về pipeline timing — biết chính xác lệnh N đang ở đâu khi lệnh N+k đang ở EX.

### 9.6 Bước 5: Fix và Regression

Khi xác định root cause:

1. **Fix tối thiểu**: Chỉ sửa đúng vấn đề, không thêm feature hay cleanup không liên quan.
2. **Viết comment giải thích WHY** (không giải thích WHAT — code tự giải thích):
   ```sv
   // Suppress load-use flush khi bus_stall đang active:
   // bus_stall giữ toàn pipeline bao gồm EX, nên bubble tự nhiên khi stall giải phóng.
   // Không suppress sẽ cancel lệnh LW đang ở EX trong khi bus_stall giữ nó ở đó.
   assign flush_id_ex = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush;
   ```
3. **Chạy regression đầy đủ**: Toàn bộ test suite từ Phase 1 trở đi.
   ```bash
   make unit_all     # Phase 1+2
   make p3_all       # Phase 3
   make integ_axi integ_ahb integ_axi_full integ_ahb_full  # Phase 4
   make p5_all       # Phase 5
   ```
4. **Log bug vào TEST_LOG.md** với đầy đủ triệu chứng, root cause, fix.

### 9.7 Khi Gặp Compile Error Từ Icarus

Icarus warning/error message thường cryptic với modules lớn. Quy trình xử lý:

```bash
# Compile với full verbosity, capture stderr:
iverilog -g2012 -Wall -o /dev/null ../RTL/id_decoder.sv 2>&1 | head -20
```

Các lỗi phổ biến và cách fix:

| Lỗi Icarus | Nguyên nhân | Fix |
|-----------|-------------|-----|
| `error: Part select is not an lvalue` | Bit-select trong always block | Tách ra assign |
| `error: Undeclared identifier` | Typo tên wire hoặc thiếu khai báo | Kiểm tra wire declaration |
| `warning: implicit definition` | Port kết nối trong instantiation nhưng chưa declare wire | Thêm `wire` declaration |
| `error: Task port ... not found` | Named task arg (.portname) | Dùng positional args |
| `warning: timescale inherited` | Module không có timescale directive | Thêm `` `timescale 1ns/1ps `` hoặc chấp nhận warning |

---

## 10. Quản Lý Dự Án và Tài Liệu

### 10.1 Quản Lý Phiên Bản

Dự án không sử dụng Git version control trong quá trình phát triển (toàn bộ trong WSL2 local filesystem). Thay vào đó, trạng thái được theo dõi thông qua:

- **CLAUDE.md**: File markdown chứa kiến trúc thiết kế, trạng thái từng module, và kết quả test hiện tại. Được cập nhật sau mỗi milestone.
- **TEST_LOG.md**: Nhật ký chi tiết từng session làm việc: bug phát hiện, fix áp dụng, kết quả test.

### 10.2 Quy Tắc Duy Trì CLAUDE.md

`CLAUDE.md` được thiết kế để làm "single source of truth" cho toàn bộ dự án:
- Bảng trạng thái module cập nhật với mỗi thay đổi RTL
- Bảng kết quả test cập nhật sau mỗi phase pass
- Ghi chú về bug đặc biệt hoặc design decision không obvious từ code

### 10.3 Makefile Làm Điểm Trung Tâm

Makefile là giao diện duy nhất cần nhớ để chạy bất kỳ task nào:

```bash
# Unit tests
make unit_alu          # Phase 1: ALU
make unit_all          # Phase 1+2: tất cả unit tests

# Integration
make p3_all            # Phase 3: 9 programs CPU
make integ_axi         # Phase 4a: AXI interface
make integ_ahb         # Phase 4b: AHB interface
make integ_axi_full    # Phase 4c: AXI full path
make integ_ahb_full    # Phase 4d: AHB full path
make p5_all            # Phase 5: 4 programs SFR + IRQ

# System
make system            # Phase 6a: 16 programs batch
make p6_compliance     # Phase 6b: compliance programs
make p6_all            # Phase 6: 6a + 6b

# Debug
make p3_wave_csr       # Phase 3 với VCD dump (prog_csr)

# Clean
make clean             # Xóa tất cả .vvp, .vcd, .elf, .hex
```

### 10.4 Tip Hiệu Quả Trong Simulation

**Parallel compilation:**  
Icarus compile nhanh (< 5s cho 30 modules). Không cần incremental compilation — luôn compile toàn bộ để đảm bảo consistency.

**Timeout trên mọi testbench:**  
Mọi testbench đều có watchdog timer để phát hiện infinite loop:
```sv
initial begin
    #200000;  // 200,000 ns = 200 us
    $fatal(1, "TIMEOUT");
end
```

**Chạy nhiều tests parallel:**  
```bash
# Chạy Phase 1 và Phase 4 song song (không phụ thuộc nhau):
make unit_all & make integ_axi & wait
```

**Makefile với phụ thuộc:**  
Pattern rule `programs/%.hex: programs/%.s` cho phép Make tự động rebuild hex khi assembly source thay đổi, không cần manual intervention.

---

*Tài liệu này mô tả quy trình thực hiện dự án. Chi tiết về bugs cụ thể phát hiện và sửa trong từng phase xem trong TESTRESULT.md (sẽ hoàn thiện riêng). Kết quả test tổng hợp xem trong SIM/TEST_LOG.md.*
