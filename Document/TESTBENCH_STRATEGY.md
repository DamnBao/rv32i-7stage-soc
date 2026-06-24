# Testbench Strategy — RISC-V RV32I+Zicsr SoC

Phiên bản: 2026-06-19

---

## 1. Tổng Quan Chiến Lược

### 1.1 Triết lý chung

Mục tiêu là **functional correctness verification**, không phải coverage-driven verification theo phong cách công nghiệp. Do đây là đồ án luận văn, cách tiếp cận được chọn là:

- **Directed tests** (không phải random/constrained-random): viết testcase cụ thể, dự đoán được kết quả
- **Self-checking**: testbench tự so sánh kết quả và print PASS/FAIL — không cần xem waveform trừ khi fail
- **Lightweight**: không dùng UVM/OVM. Dùng `task`/`function` SystemVerilog thuần túy
- **Three-layer isolation**: (1) unit test từng module riêng lẻ → (2) integration test pipeline CPU → (3) full-system SoC smoke test

### 1.2 Công cụ

| Công cụ | Mục đích |
|---------|---------|
| **Icarus Verilog 11+** (`iverilog` + `vvp`) | Biên dịch và chạy simulation |
| **GTKWave** | Xem waveform VCD khi debug |
| **GNU Make** | Automation build + run |
| **RISC-V GNU toolchain** (riscv32-unknown-elf-gcc) | Compile assembly/C cho program loading |
| **Python 3** (tùy chọn) | Gen hex file, compare output |

---

## 2. Cấu Trúc Thư Mục

```
riscv_soc_thesis/
├── RTL/                    ← Source RTL (30 files)
├── tb/
│   ├── Makefile            ← Build automation
│   ├── models/             ← Behavioral models cho external blocks
│   │   ├── axi_slave_model.sv
│   │   └── ahb_slave_model.sv
│   ├── programs/           ← Hex files nạp vào IMEM
│   │   ├── prog_arithmetic.hex
│   │   ├── prog_forwarding.hex
│   │   ├── prog_load_use_stall.hex
│   │   ├── prog_branch_jump.hex
│   │   ├── prog_dmem_rw.hex
│   │   ├── prog_csr_ops.hex
│   │   ├── prog_ecall.hex
│   │   ├── prog_interrupt_mei.hex
│   │   └── prog_interrupt_msi.hex
│   ├── unit/               ← Unit tests
│   │   ├── tb_alu.sv
│   │   ├── tb_branch_comp.sv
│   │   ├── tb_id_decoder.sv
│   │   ├── tb_register_file.sv
│   │   ├── tb_forwarding_unit.sv
│   │   ├── tb_hazard_unit.sv
│   │   └── tb_async_fifo.sv
│   ├── integration/        ← Integration tests
│   │   ├── tb_pipeline_cpu.sv
│   │   ├── tb_axi_interface.sv
│   │   └── tb_ahb_interface.sv
│   └── system/             ← Full-system tests
│       └── tb_soc_top.sv
├── TESTPLAN.md
└── TESTBENCH_STRATEGY.md
```

---

## 3. Template Testbench Chuẩn

Mọi testbench đều theo cấu trúc sau:

```systemverilog
`timescale 1ns/1ps

module tb_xxx;

    //=========================================================
    // 1. Signals
    //=========================================================
    logic clk, rst_n;
    // ... DUT port signals

    //=========================================================
    // 2. DUT Instantiation
    //=========================================================
    xxx u_dut (.*);   // hoặc explicit port binding

    //=========================================================
    // 3. Clock Generation
    //=========================================================
    // CPU clock: 1GHz = period 10ns (half period = 5ns)
    initial clk = 0;
    always #5 clk = ~clk;

    //=========================================================
    // 4. VCD Dump (cho GTKWave khi debug)
    //=========================================================
    initial begin
        $dumpfile("tb_xxx.vcd");
        $dumpvars(0, tb_xxx);
    end

    //=========================================================
    // 5. Reset Task
    //=========================================================
    task automatic do_reset();
        rst_n = 0;
        repeat(5) @(posedge clk);   // Assert reset 5 cycles
        @(negedge clk);
        rst_n = 1;                  // Deassert synchronously (negedge)
        @(posedge clk);             // 1 cycle settle
    endtask

    //=========================================================
    // 6. Pass/Fail Counters
    //=========================================================
    int pass_cnt = 0, fail_cnt = 0;

    task automatic check(
        input string test_name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual === expected) begin
            $display("[PASS] %s: got 0x%08X", test_name, actual);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s: expected 0x%08X, got 0x%08X", 
                     test_name, expected, actual);
            fail_cnt++;
        end
    endtask

    //=========================================================
    // 7. Timeout Watchdog
    //=========================================================
    initial begin
        #100000;  // 100µs timeout
        $display("[TIMEOUT] Simulation hung after 100000ns");
        $fatal(1, "Deadlock detected");
    end

    //=========================================================
    // 8. Main Test Body
    //=========================================================
    initial begin
        do_reset();
        // ... test cases
        $display("========================");
        $display("RESULT: PASS=%0d FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt > 0) $fatal(1, "TEST FAILED");
        else              $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
```

**Lưu ý quan trọng:**
- Dùng `===` (4-state equality) thay vì `==` để phát hiện `X`/`Z`
- `$fatal` trả về exit code khác 0 → Makefile có thể detect fail tự động
- Không dùng `#delay` tuyệt đối để wait; luôn dùng `@(posedge clk)` để đồng bộ

---

## 4. Chiến Lược Test Từng Layer

### 4.1 Unit Tests

**Nguyên tắc:** Mỗi module được test **hoàn toàn độc lập** — không phụ thuộc vào module khác.

**Cách áp dụng vector test:**

```systemverilog
// Vector-driven unit test
typedef struct {
    logic [31:0] a, b;
    logic [3:0]  op;
    logic [31:0] expected;
    string       name;
} alu_test_t;

alu_test_t vectors[] = '{
    '{"ADD basic", 5, 3, 4'd0, 8},
    '{"ADD overflow", 32'hFFFF_FFFF, 1, 4'd0, 0},
    // ...
};

// Drive và check
foreach (vectors[i]) begin
    operand_a = vectors[i].a;
    operand_b = vectors[i].b;
    alu_op    = vectors[i].op;
    #1;  // Propagate combinational
    check(vectors[i].name, alu_result, vectors[i].expected);
end
```

**Với sequential modules** (register file, pipeline reg): cần `@(posedge clk)` để latch.

### 4.2 Pipeline Integration Test (`tb_pipeline_cpu.sv`)

Đây là testbench quan trọng nhất. Cấu trúc:

```
tb_pipeline_cpu
├── if1_stage
├── if1_if2_reg
├── if2_stage
├── if2_id_reg
├── imem                ← load từ .hex file
├── id_decoder
├── register_file       ← đọc kết quả từ đây
├── id_ex_reg
├── alu
├── branch_comp
├── addr_adder
├── ex_mem1_reg
├── mem1_stage          ← connects to dmem, và "stub" cho AXI/AHB
├── dmem
├── mem1_mem2_reg
├── mem2_stage
├── mem2_wb_reg
├── wb_stage
├── hazard_unit
├── forwarding_unit
└── zicsr
```

**Không cần AXI/AHB** trong pipeline test vì tất cả chương trình test chỉ dùng IMEM/DMEM. Các port AXI/AHB của `mem1_stage` sẽ được **stub** bằng tie-off:

```systemverilog
// AXI stub — không có AXI transaction nào xảy ra
logic axi_resp_valid = 0;
logic [31:0] axi_resp_rdata = 0;
logic axi_resp_err = 0;

// AHB stub
logic resp_fifo_rd_empty = 1;  // FIFO luôn rỗng → không có AHB response
logic [32:0] resp_fifo_rd_data = 0;
```

**Program loading:**

```systemverilog
// Load hex file vào IMEM internal memory
initial begin
    $readmemh("programs/prog_forwarding.hex", tb_pipeline_cpu.u_imem.mem);
end
```

**Đọc kết quả — cách 1: Observe regfile trực tiếp**

```systemverilog
// Wait đủ cycles cho pipeline drain (worst case: 20 cycles sau last instr)
repeat(30) @(posedge clk);
check("x3 = 15", tb_pipeline_cpu.u_rf.regs[3], 32'd15);
```

**Đọc kết quả — cách 2: Magic "done" register**

Cuối mỗi chương trình, viết một giá trị đặc biệt vào x31:
```asm
ADDI x31, x0, 0xDEAD   # Signal that program is done
```

Testbench monitor:
```systemverilog
// Wait for done signal
@(tb_pipeline_cpu.u_rf.regs[31] === 32'h0000DEAD);
// Now check results
```

**Đọc kết quả — cách 3: Trap on SW to magic address**

Viết kết quả ra một DMEM location đặc biệt và testbench dùng `$monitor` để theo dõi.

### 4.3 Bus Interface Tests

**AXI interface** (`tb_axi_interface.sv`): kết hợp `axi_interface.sv` với behavioral slave model.

**AHB interface** (`tb_ahb_interface.sv`): kết hợp `ahb_interface.sv` với behavioral slave model.

**Mục tiêu:** Test timing của interface FSM, không phụ thuộc vào SFR logic.

### 4.4 Full-System Test (`tb_soc_top.sv`)

Đây là smoke test, không cần chi tiết — chỉ verify end-to-end path hoạt động. Dùng `soc_top` nguyên vẹn.

---

## 5. Behavioral Models Cần Thiết

### 5.1 Có Cần Behavioral Model Không?

**Tóm tắt câu trả lời:**

| Layer | External blocks | Cần model? | Giải pháp |
|-------|-----------------|------------|-----------|
| Unit test (ALU, decoder…) | Không có | Không | — |
| Unit test (AXI interface) | AXI Slave | **Có** | `axi_slave_model.sv` |
| Unit test (AHB interface) | AHB Slave | **Có** | `ahb_slave_model.sv` |
| Unit test (Async FIFO) | Clock source | Không | Tạo 2 clock trong TB |
| Pipeline integration | IMEM, DMEM | Không | Dùng RTL + $readmemh |
| Pipeline integration | AXI, AHB | Không | Stub (tie-off) |
| Full SoC | AXI/AHB SFR | Không | Dùng RTL `axi_sfr`, `ahb_sfr` |
| Full SoC | IRQ stimulus | Không | Direct signal drive từ TB |

**Kết luận: chỉ cần 2 behavioral models.** Tất cả layers còn lại dùng RTL thực hoặc stub.

---

### 5.2 `axi_slave_model.sv` — Chi Tiết

**Mục đích:** Giả lập AXI4-Lite slave với latency có thể cấu hình, read data có thể lập trình, error injection.

**Interface:** Giống `axi_sfr.sv` về mặt pin nhưng behavior hoàn toàn controllable từ testbench.

```systemverilog
module axi_slave_model #(
    parameter AW_LATENCY  = 1,  // Số cycle trước khi assert AWREADY
    parameter W_LATENCY   = 1,  // Số cycle trước khi assert WREADY
    parameter AR_LATENCY  = 1,  // Số cycle trước khi assert ARREADY
    parameter R_LATENCY   = 2,  // Số cycle từ AR accepted đến RVALID
    parameter B_LATENCY   = 1   // Số cycle từ W accepted đến BVALID
)(
    input  logic        clk, rst_n,
    // AXI4-Lite Slave ports (giống axi_sfr)
    input  logic [31:0] AWADDR, ...
    // Testbench control interface
    input  logic [31:0] tb_rdata,     // Data trả về cho read
    input  logic        tb_inject_rerr, // Inject RRESP error
    input  logic        tb_inject_berr, // Inject BRESP error
    output logic [31:0] tb_waddr,     // Last write address (verify)
    output logic [31:0] tb_wdata,     // Last write data (verify)
    output logic [3:0]  tb_wstrb,     // Last write strobe
    output logic        tb_wr_valid   // Pulse khi write committed
);
```

**Behavior:**
- Nhận AW/W/AR channels
- Assert READY sau N cycles (theo parameter)
- Trả về `tb_rdata` trên R channel sau `R_LATENCY` cycles từ AR accepted
- Assert BRESP/RRESP error nếu `tb_inject_*err` = 1
- Expose `tb_waddr/wdata/wstrb` để testbench verify write content

**Internal logic:** Simple counter-based delays, không cần FSM phức tạp.

**Ví dụ dùng:**

```systemverilog
// Testbench: set up expected read data
assign tb_rdata = 32'hDEAD_BEEF;

// Trigger AXI read và verify
axi_req_valid = 1;
axi_req_we    = 0;
axi_req_addr  = 32'h2000_0000;
@(posedge axi_resp_valid);  // wait for response
check("AXI read data", axi_resp_rdata, 32'hDEAD_BEEF);
```

---

### 5.3 `ahb_slave_model.sv` — Chi Tiết

**Mục đích:** Giả lập AHB-Lite slave với wait state và error injection.

```systemverilog
module ahb_slave_model #(
    parameter WAIT_STATES = 0,   // Số cycle HREADY=0 sau address phase
    parameter FIXED_RDATA = 32'hA5A5_A5A5
)(
    input  logic        clk_ahb, rst_ahb_n,
    // AHB-Lite Slave interface
    input  logic        HSEL,
    input  logic [31:0] HADDR,
    input  logic [1:0]  HTRANS,
    input  logic        HWRITE,
    input  logic [31:0] HWDATA,
    input  logic        HREADY,     // HREADY từ interconnect (previous slave)
    output logic [31:0] HRDATA,
    output logic        HREADYOUT,
    output logic        HRESP,
    // Testbench control
    input  logic        tb_inject_error, // Assert HRESP=1 on next transfer
    input  logic [31:0] tb_rdata_override,
    output logic [31:0] tb_last_waddr,
    output logic [31:0] tb_last_wdata,
    output logic        tb_wr_valid
);
```

**Behavior:**
- Trong address phase: latch HADDR, HWRITE khi `HTRANS=NONSEQ && HSEL && HREADY`
- Trong data phase: assert `HREADY=0` cho `WAIT_STATES` cycles (wait states), sau đó `HREADY=1`
- Nếu write: capture HWDATA → expose ra `tb_last_wdata`
- Nếu read: trả `HRDATA = tb_rdata_override` (hoặc `FIXED_RDATA`)
- Nếu `tb_inject_error`: assert `HRESP=1` (2-cycle error response per AHB spec: cycle 1 HRESP=1+HREADY=0, cycle 2 HRESP=1+HREADY=1)

**Lưu ý quan trọng — AHB error response 2-cycle:**  
AHB-Lite spec yêu cầu error response kéo dài 2 cycles: `{HRESP=1, HREADY=0}` rồi `{HRESP=1, HREADY=1}`. `ahb_interface.sv` phải xử lý đúng điều này.

---

## 6. Chiến Lược Nạp Chương Trình Vào IMEM

### 6.1 Format File Hex

Dùng **Intel HEX format** (hoặc raw hex — `$readmemh` đều đọc được).

Mỗi word 32-bit viết theo little-endian (RISC-V convention):

```
// prog_arithmetic.hex
00000513   // ADDI x10, x0, 0       (PC=0x00)
00a00593   // ADDI x11, x0, 10      (PC=0x04)
00500613   // ADDI x12, x0, 5       (PC=0x08)
00b60633   // ADD  x12, x12, x11    (PC=0x0C)
00c58663   // BEQ  x11, x12, +12    (nếu x11==x12 jump)
...
0000_dead  // NOP / marker
```

### 6.2 Cách Tạo Hex File

**Option A — Encode thủ công (cho test đơn giản):**

Dùng bảng encoding RV32I để tạo từng word 32-bit. Ví dụ:

```
ADDI x1, x0, 42:
  opcode = 7'b0010011 (OP-IMM)
  funct3 = 3'b000 (ADDI)
  rs1    = 5'd0
  rd     = 5'd1
  imm    = 12'd42 = 0x02A
  → 0x02A00093
```

**Option B — Dùng RISC-V toolchain (khuyến nghị cho chương trình dài):**

```bash
# Viết file .s (assembly)
cat > prog_branch.s << 'EOF'
.section .text
.global _start
_start:
    addi  x1, x0, 5
    addi  x2, x0, 5
    beq   x1, x2, skip
    addi  x3, x0, 99   # should be flushed
skip:
    addi  x3, x0, 1    # x3 should be 1
    addi  x31, x0, 0xDEAD  # done marker
loop:
    j loop
EOF

# Compile
riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 \
    -T linker.ld -nostdlib -o prog_branch.elf prog_branch.s

# Extract hex (word-aligned, big-endian cho $readmemh)
riscv32-unknown-elf-objcopy -O verilog prog_branch.elf prog_branch.hex
```

**Linker script `linker.ld`:**
```
SECTIONS {
    . = 0x00000000;
    .text : { *(.text) }
}
```

**Option C — Python hex generator (cho test vectors):**

```python
# gen_hex.py — encode RV32I instructions programmatically
def addi(rd, rs1, imm): 
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0b000 << 12) | (rd << 7) | 0x13

program = [
    addi(1, 0, 10),  # ADDI x1, x0, 10
    addi(2, 0, 5),   # ADDI x2, x0, 5
    ...
]
with open("prog.hex", "w") as f:
    for word in program:
        f.write(f"{word:08x}\n")
```

### 6.3 Nạp Hex Vào IMEM Trong Testbench

```systemverilog
// Trong initial block của tb_pipeline_cpu
string hex_file;
initial begin
    if (!$value$plusargs("HEX=%s", hex_file))
        hex_file = "programs/prog_arithmetic.hex";
    $readmemh(hex_file, tb_pipeline_cpu.u_imem.mem);
    // Chú ý: tên 'mem' phải khớp với tên array bên trong imem.sv
end
```

Với `+HEX=<file>`, có thể chọn chương trình từ command line.

---

## 7. Chiến Lược Verify Kết Quả

### 7.1 Direct Register Read (Cho Pipeline Tests)

Sau khi chương trình kết thúc (đợi done marker ở x31), đọc trực tiếp:

```systemverilog
// Monitor x31 để detect chương trình xong
always @(posedge clk) begin
    if (tb_pipeline_cpu.u_rf.regs[31] === 32'h0000DEAD) begin
        program_done = 1;
    end
end

// Wait for done, then check
wait(program_done);
@(posedge clk); // 1 extra cycle settle
check("x3", tb_pipeline_cpu.u_rf.regs[3], 32'd15);
check("x4", tb_pipeline_cpu.u_rf.regs[4], 32'd5);
```

### 7.2 Waveform Annotation (Cho Debug)

Khi test fail, mở GTKWave với signals:
- `clk`, `rst_n`
- `if1_pc`, `if2_pc`, `id_pc`, `ex_pc`, `mem1_pc`, `mem2_pc`, `wb_pc` — track instruction flow
- `stall_pc`, `stall_if1if2`, `flush_if1if2`, `flush_id_ex` — hazard signals
- `fwd_sel_a`, `fwd_sel_b` — forwarding
- `u_rf.regs[*]` — register file values
- `zicsr_flush`, `zicsr_pc` — exception/interrupt

### 7.3 Cycle Count Verification (Cho Timing Tests)

```systemverilog
// Verify đúng số cycles cho load-use stall
int cycle_count = 0;
always @(posedge clk) cycle_count++;

// Expected: pipeline takes exactly N cycles for this program
// (N tính tay từ pipeline diagram)
int start_cycle = cycle_count;
wait(program_done);
int elapsed = cycle_count - start_cycle;
if (elapsed !== EXPECTED_CYCLES)
    $display("[WARN] Cycle count: expected %0d, got %0d", EXPECTED_CYCLES, elapsed);
```

---

## 8. Môi Trường Simulation Dual-Clock (SoC Top)

Cho `tb_soc_top.sv`, cần 2 clock không đồng bộ:

```systemverilog
logic clk_cpu, clk_ahb;

// CPU: 1GHz = 10ns period
initial clk_cpu = 0;
always #5 clk_cpu = ~clk_cpu;

// AHB: 500MHz = 20ns period — LỆCH PHA so với cpu để test CDC
initial clk_ahb = 0;        // ← Có thể đổi thành 3 hoặc 7 để lệch pha
always #10 clk_ahb = ~clk_ahb;

// Reset: 2 domain — rst_n từ TB, rst_ahb_n từ reset_sync trong DUT
logic rst_n;
initial begin
    rst_n = 0;
    repeat(10) @(posedge clk_cpu);  // Hold reset lâu hơn để reset_sync settle
    @(negedge clk_cpu);
    rst_n = 1;
    // Wait thêm cho rst_ahb_n propagate qua reset_sync (2 clk_ahb cycles)
    repeat(5) @(posedge clk_ahb);
end
```

**Lưu ý CDC testing:**  
Để stress test CDC, có thể thay đổi phase của `clk_ahb`:
```systemverilog
initial clk_ahb = 0;
// Option 1: aligned   — #10
// Option 2: 90° shift — initial clk_ahb = 0; initial #5 forever #10
// Option 3: prime ratio — clk_ahb period = 17ns (prime vs 10ns)
```

---

## 9. Makefile Automation

```makefile
# tb/Makefile

IVERILOG = iverilog -g2012 -Wall
VVP      = vvp
RTL      = ../RTL

# Common RTL sources
RTL_COMMON = $(RTL)/reset_sync.sv $(RTL)/async_fifo.sv \
             $(RTL)/imem.sv $(RTL)/dmem.sv

RTL_CPU = $(RTL)/if1_stage.sv $(RTL)/if1_if2_reg.sv \
          $(RTL)/if2_stage.sv $(RTL)/if2_id_reg.sv \
          $(RTL)/id_decoder.sv $(RTL)/register_file.sv $(RTL)/id_ex_reg.sv \
          $(RTL)/alu.sv $(RTL)/branch_comp.sv $(RTL)/addr_adder.sv \
          $(RTL)/ex_mem1_reg.sv $(RTL)/mem1_stage.sv \
          $(RTL)/mem1_mem2_reg.sv $(RTL)/mem2_stage.sv \
          $(RTL)/mem2_wb_reg.sv $(RTL)/wb_stage.sv \
          $(RTL)/hazard_unit.sv $(RTL)/forwarding_unit.sv $(RTL)/zicsr.sv

RTL_AXI = $(RTL)/axi_interface.sv $(RTL)/axi_interconnect.sv $(RTL)/axi_sfr.sv
RTL_AHB = $(RTL)/ahb_interface.sv $(RTL)/ahb_interconnect.sv $(RTL)/ahb_sfr.sv

RTL_ALL = $(RTL_COMMON) $(RTL_CPU) $(RTL_AXI) $(RTL_AHB) $(RTL)/soc_top.sv

# ─────────── Unit Tests ───────────
.PHONY: unit_alu unit_branch unit_decoder unit_rf unit_fwd unit_haz unit_fifo

unit_alu:
	$(IVERILOG) -o unit/tb_alu.vvp unit/tb_alu.sv $(RTL)/alu.sv && $(VVP) unit/tb_alu.vvp

unit_branch:
	$(IVERILOG) -o unit/tb_branch.vvp unit/tb_branch_comp.sv $(RTL)/branch_comp.sv && $(VVP) unit/tb_branch.vvp

unit_decoder:
	$(IVERILOG) -o unit/tb_decoder.vvp unit/tb_id_decoder.sv $(RTL)/id_decoder.sv && $(VVP) unit/tb_decoder.vvp

unit_rf:
	$(IVERILOG) -o unit/tb_rf.vvp unit/tb_register_file.sv $(RTL)/register_file.sv && $(VVP) unit/tb_rf.vvp

unit_fwd:
	$(IVERILOG) -o unit/tb_fwd.vvp unit/tb_forwarding_unit.sv $(RTL)/forwarding_unit.sv && $(VVP) unit/tb_fwd.vvp

unit_haz:
	$(IVERILOG) -o unit/tb_haz.vvp unit/tb_hazard_unit.sv $(RTL)/hazard_unit.sv && $(VVP) unit/tb_haz.vvp

unit_fifo:
	$(IVERILOG) -o unit/tb_fifo.vvp unit/tb_async_fifo.sv $(RTL)/async_fifo.sv && $(VVP) unit/tb_fifo.vvp

unit_all: unit_alu unit_branch unit_decoder unit_rf unit_fwd unit_haz unit_fifo

# ─────────── Integration Tests ───────────
.PHONY: integ_cpu integ_axi integ_ahb

integ_cpu: programs/prog_arithmetic.hex
	$(IVERILOG) -o integration/tb_pipeline.vvp \
	    integration/tb_pipeline_cpu.sv $(RTL_COMMON) $(RTL_CPU) && \
	$(VVP) integration/tb_pipeline.vvp +HEX=programs/prog_arithmetic.hex

integ_axi:
	$(IVERILOG) -o integration/tb_axi.vvp \
	    integration/tb_axi_interface.sv models/axi_slave_model.sv \
	    $(RTL)/axi_interface.sv && \
	$(VVP) integration/tb_axi.vvp

integ_ahb:
	$(IVERILOG) -o integration/tb_ahb.vvp \
	    integration/tb_ahb_interface.sv models/ahb_slave_model.sv \
	    $(RTL)/ahb_interface.sv && \
	$(VVP) integration/tb_ahb.vvp

integ_all: integ_cpu integ_axi integ_ahb

# ─────────── System Test ───────────
.PHONY: system

system:
	$(IVERILOG) -o system/tb_soc_top.vvp \
	    system/tb_soc_top.sv $(RTL_ALL) && \
	$(VVP) system/tb_soc_top.vvp

# ─────────── Run All ───────────
.PHONY: all clean

all: unit_all integ_all system
	@echo "=== ALL TESTS COMPLETE ==="

clean:
	rm -f unit/*.vvp integration/*.vvp system/*.vvp *.vcd unit/*.vcd integration/*.vcd system/*.vcd

# ─────────── Waveform Viewer ───────────
wave_%:
	gtkwave $*.vcd &
```

**Chạy toàn bộ test suite:**
```bash
cd tb && make all 2>&1 | tee test_results.log
grep -E "PASS|FAIL|ERROR" test_results.log
```

---

## 10. Cách Viết Chương Trình Test cho Pipeline

### 10.1 Quy ước chung

Mọi chương trình test đều tuân theo:

```asm
.org 0x0000_0000
_start:
    # --- Setup ---
    # (init registers nếu cần)
    
    # --- Test body ---
    # (các instruction cần test)
    
    # --- Write results ---
    # Ghi kết quả vào x10..x29 để TB đọc
    # x30 = error code (0 = pass, non-zero = fail number)
    
    # --- Done marker ---
    addi x31, x0, 0x0DEA    # x31 = 0x0DEA (lower)
    slli x31, x31, 4
    addi x31, x31, 0x00D    # x31 = 0xDEAD (done signal)
    
_end:
    j _end                   # Halt (spin forever)
```

### 10.2 Địa Chỉ Đặc Biệt

| Địa chỉ | Mục đích |
|---------|---------|
| `0x0000_0000` | Reset vector (IMEM start) |
| `0x0001_0000` | DMEM start — dùng làm scratch memory |
| `0x0001_FF00` | DMEM end area — test boundary |
| `0x0000_0100` | Exception handler vector (mtvec = 0x100) |
| `0x0000_0200` | Interrupt handler vector (mtvec = 0x200, vectored MEI = 0x22C) |

### 10.3 Exception/Interrupt Handler Template

```asm
# Tại địa chỉ 0x0000_0100 (mtvec base):
.org 0x100
exception_handler:
    csrr x20, mepc       # Save mepc
    csrr x21, mcause     # Save mcause
    # Process exception...
    csrw mepc, x20       # Restore/advance mepc
    mret                 # Return
```

---

## 11. Checklist Trước Khi Viết Testbench

- [ ] Đọc TESTPLAN.md và hiểu rõ từng test case
- [ ] Đọc port list của module cần test (xem file .sv)
- [ ] Xác định module cần stub/model hay dùng RTL thực
- [ ] Tính tay kết quả expected cho ít nhất 1 test case quan trọng
- [ ] Xác định số cycle cần đợi (pipeline depth + latency)
- [ ] Viết done marker vào cuối chương trình (nếu là pipeline test)
- [ ] Thêm timeout watchdog với giá trị hợp lý

---

## 12. Thứ Tự Phát Triển Testbench Khuyến Nghị

```
Phase 1 — Nền tảng (không có dependency)
├── tb_alu.sv          (purely combinational)
├── tb_branch_comp.sv  (purely combinational)
├── tb_id_decoder.sv   (purely combinational)
└── tb_register_file.sv (sequential, simple)

Phase 2 — Control
├── tb_forwarding_unit.sv  (cần hiểu fwd priority)
├── tb_hazard_unit.sv      (cần hiểu stall/flush logic)
└── tb_async_fifo.sv       (cần dual-clock setup)

Phase 3 — Pipeline Integration
└── tb_pipeline_cpu.sv     (cần Phase 1+2 đúng trước)
    ├── prog_arithmetic.hex
    ├── prog_forwarding.hex
    ├── prog_load_use_stall.hex
    ├── prog_branch_jump.hex
    ├── prog_dmem_rw.hex
    ├── prog_csr_ops.hex    ← verify CSR op fix (critical!)
    ├── prog_ecall.hex
    ├── prog_interrupt_mei.hex
    └── prog_interrupt_msi.hex

Phase 4 — Bus Interfaces
├── models/axi_slave_model.sv  (viết model trước)
├── models/ahb_slave_model.sv
├── tb_axi_interface.sv
└── tb_ahb_interface.sv

Phase 5 — Full System
└── tb_soc_top.sv
```

> **Nguyên tắc:** Không được tiếp tục lên Phase tiếp theo nếu còn FAIL ở Phase hiện tại. Mỗi phase là dependency của phase sau.

---

## 13. Ước Tính Effort

| Phase | Số file | Độ phức tạp | Ước tính |
|-------|---------|-------------|---------|
| 1 — Unit cơ bản | 4 TB | Thấp | 1–2 buổi |
| 2 — Control | 3 TB | Trung bình | 1 buổi |
| 3 — Pipeline | 1 TB + 9 hex | **Cao** (pipeline timing phức tạp) | 3–4 buổi |
| 4 — Bus | 2 models + 2 TB | Trung bình | 2 buổi |
| 5 — System | 1 TB | Thấp (dùng lại RTL) | 1 buổi |

**Tổng:** ~8–10 buổi làm việc.  
Phase 3 (pipeline) là phase tốn thời gian nhất và cũng quan trọng nhất — đặc biệt các test cho branch/jump (verify bug fix #1) và CSR operations (verify bug fix #2).
