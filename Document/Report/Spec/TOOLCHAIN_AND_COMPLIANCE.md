# Toolchain & RISC-V Compliance Testing

Phiên bản: 2026-06-19 | Môi trường: Ubuntu 24.04 LTS (WSL2)

---

## Phần 1 — RISC-V GNU Toolchain

### 1.1 Cài Đặt (2 phút)

Ubuntu 24.04 có sẵn `gcc-riscv64-unknown-elf` 13.2.0 trong kho chính thức.

```bash
sudo apt update
sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf
```

Sau khi cài, các công cụ có prefix `riscv64-unknown-elf-`:

| Lệnh | Mục đích |
|------|---------|
| `riscv64-unknown-elf-gcc` | Compile C/Assembly |
| `riscv64-unknown-elf-as`  | Assembler |
| `riscv64-unknown-elf-ld`  | Linker |
| `riscv64-unknown-elf-objcopy` | Chuyển đổi format (ELF → hex) |
| `riscv64-unknown-elf-objdump` | Disassemble, debug |
| `riscv64-unknown-elf-nm`  | Xem symbol table |

### 1.2 Kiểm Tra Cài Đặt

```bash
riscv64-unknown-elf-gcc --version
# GCC 13.x.x — OK

# Test compile một file assembly tối giản
cat > /tmp/hello_rv32.s << 'EOF'
.section .text
.global _start
_start:
    addi x1, x0, 42
    addi x2, x0, 8
    add  x3, x1, x2    # x3 = 50
    ebreak
EOF

riscv64-unknown-elf-gcc -march=rv32i -mabi=ilp32 -nostdlib \
    -Ttext=0x00000000 -o /tmp/hello_rv32.elf /tmp/hello_rv32.s

# Kiểm tra disassembly
riscv64-unknown-elf-objdump -d /tmp/hello_rv32.elf
```

### 1.3 Linker Script Chuẩn Cho Dự Án

Tạo `tb/link_default.ld` dùng cho tất cả chương trình test thông thường:

```ld
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rw) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text*)
    } > IMEM

    .rodata : { *(.rodata*) } > IMEM

    .data : { *(.data*) } > DMEM
    .bss  : {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    } > DMEM
}
```

### 1.4 Workflow Compile Assembly → Hex

```bash
# Bước 1: Compile .s → ELF
riscv64-unknown-elf-gcc \
    -march=rv32i -mabi=ilp32 \
    -nostdlib -nostartfiles \
    -T tb/link_default.ld \
    -o tb/programs/prog_forwarding.elf \
    tb/programs/prog_forwarding.s

# Bước 2: ELF → Verilog hex ($readmemh compatible)
riscv64-unknown-elf-objcopy \
    -O verilog \
    --verilog-data-width 4 \
    tb/programs/prog_forwarding.elf \
    tb/programs/prog_forwarding.hex

# Bước 3: Tùy chọn — xem nội dung hex
riscv64-unknown-elf-objdump -d -M numeric tb/programs/prog_forwarding.elf
```

> **Lưu ý `--verilog-data-width 4`**: mặc định objcopy xuất từng byte riêng lẻ (1-byte width), nhưng IMEM của chúng ta là word-addressed. Flag này gộp thành 4-byte words đúng thứ tự little-endian — dùng với `$readmemh(..., , , )` sẽ load đúng.

---

## Phần 2 — RISC-V Architecture Compliance Test (ACT 4.0)

### 2.1 Bối Cảnh: Framework Hiện Hành

> **RISCOF đã bị deprecated** (tháng 4/2026). Framework chính thức hiện nay là **ACT 4.0** (riscv-non-isa/riscv-arch-test v4.0.0, phát hành 16/4/2026).

ACT 4.0 thay đổi căn bản cách test:

| | RISCOF (cũ) | ACT 4.0 (hiện tại) |
|-|-------------|---------------------|
| Cơ chế | DUT chạy test → dump memory signature ra file → so với reference | **Self-checking ELF**: test tự so sánh kết quả với expected (nhúng trong ELF) |
| Kết quả | Script diff hai file signature | ELF in `RVCP-SUMMARY: TEST PASSED` hoặc `TEST FAILED` |
| Cần dump memory? | Bắt buộc | **Không cần** |
| Reference model | Spike | RISC-V Sail v0.10 |
| Toolchain yêu cầu | GCC 12+ | **GCC 15 / Binutils 2.44** |

### 2.2 Cách ACT 4.0 Hoạt Động (Self-Checking ELF)

```
ACT Framework                     DUT (SoC của bạn)
──────────────────                ──────────────────────
                                  
 [1] Generate test (Python/Ruby)
     dùng UDB config của DUT      
         │                        
         ▼                        
 [2] Compile test assembly         
     → ELF "signature-generating"  
         │                        
         ▼                        
 [3] Chạy trên Sail v0.10         
     → file .sig (expected values) 
         │                        
         ▼                        
 [4] Embed expected values         
     → Self-checking ELF          
         │                        
         ├──────────────────────► [5] Load ELF vào IMEM
         │                            (objcopy → $readmemh)
         │                                │
         │                            [6] Chạy simulation
         │                                │
         │                            [7] ELF tự so sánh
         │                                kết quả vs expected
         │                                │
         │                            [8] Nhảy tới
         │                         RVMODEL_HALT_PASS/FAIL
         │                                │
         │                            [9] Testbench detect
         │                                ebreak → print
         │◄──────────── TEST_PASS / TEST_FAIL ──────────
```

**Ý nghĩa quan trọng**: sau bước [4], bạn chỉ cần chạy một ELF duy nhất. Không cần Spike, không cần dump memory, không cần diff file.

### 2.3 Cài Đặt ACT 4.0

#### Bước 1: Cài mise (tool version manager)

```bash
curl https://mise.jdx.dev/install.sh | sh
echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc
source ~/.bashrc
```

#### Bước 2: Clone riscv-arch-test

```bash
cd ~/riscv_soc_thesis
git clone https://github.com/riscv-non-isa/riscv-arch-test
cd riscv-arch-test
```

#### Bước 3: Cài toolchain GCC 15 qua mise

ACT 4.0 yêu cầu **GCC 15 / Binutils 2.44** (Ubuntu 24.04 apt chỉ có GCC 13).

```bash
# Cài Ruby (cần cho riscv-unified-db)
mise install ruby@latest
mise use -g ruby@latest

# Cài Python
mise install python@3.12
mise use -g python@3.12

# Build RISC-V GCC 15 từ source (ACT 4.0 quản lý qua mise)
# File mise.toml trong repo đã khai báo version yêu cầu:
cat riscv-arch-test/mise.toml   # kiểm tra requirements

# Chạy mise install trong thư mục repo
cd riscv-arch-test
mise install   # tự động pull và build toolchain theo mise.toml
```

> **Cảnh báo**: Build GCC 15 từ source mất ~45–90 phút và cần ~8GB disk. Nếu chưa cần compliance testing ngay, dùng GCC 13 (apt) đủ để generate hex cho unit/integration tests.

#### Bước 4: Cài RISC-V Sail v0.10

Sail là reference model dùng để generate expected values.

```bash
# Qua opam (OCaml package manager)
sudo apt install opam libgmp-dev pkg-config zlib1g-dev
opam init --bare
eval $(opam env)
opam switch create sail-env ocaml-base-compiler.5.1.0
opam install sail

# Build riscv-sail model
git clone https://github.com/riscv/sail-riscv
cd sail-riscv
make c_emulator/riscv_sim_RV32    # build 32-bit simulator
# Binary: c_emulator/riscv_sim_RV32
```

> **Tóm tắt**: Phần 2.3 là setup one-time. Sau khi xong, các phần 2.4–2.6 là công việc cấu hình DUT (viết 5 file config). Nếu Sail mất quá nhiều thời gian build, xem mục 2.7 về alternative.

---

### 2.4 Cấu Hình DUT — 5 File

Tạo thư mục:
```bash
mkdir -p ~/riscv_soc_thesis/riscv-arch-test/config/cores/baoslinux/rv32i_soc
```

---

#### File 1: `test_config.yaml`

```yaml
# test_config.yaml — Đường dẫn công cụ và DUT info

DUT:
  name: rv32i_soc
  vendor: baoslinux
  version: "1.0"

tools:
  compiler: /path/to/mise/installs/riscv64-unknown-elf-gcc-15/bin/riscv64-unknown-elf-gcc
  assembler: /path/to/mise/installs/riscv64-unknown-elf-gcc-15/bin/riscv64-unknown-elf-as
  linker: /path/to/mise/installs/riscv64-unknown-elf-gcc-15/bin/riscv64-unknown-elf-ld
  objcopy: /path/to/mise/installs/riscv64-unknown-elf-gcc-15/bin/riscv64-unknown-elf-objcopy
  objdump: /path/to/mise/installs/riscv64-unknown-elf-gcc-15/bin/riscv64-unknown-elf-objdump

reference:
  sail_rv32: /path/to/sail-riscv/c_emulator/riscv_sim_RV32

udb_config: config/cores/baoslinux/rv32i_soc/rv32i_soc.yaml
```

---

#### File 2: `rv32i_soc.yaml` (UDB config — khai báo ISA)

```yaml
# rv32i_soc.yaml — Unified Database config: khai báo ISA của DUT

hart0:
  ISA: RV32IZicsr

  # Physical Memory Protection: không có
  PMP_regions: 0

  # Misaligned access: không hỗ trợ (access fault nếu misaligned)
  MISALIGNED_LDST: 0

  MXLEN: 32
  ILEN: 32

  # Reset vector
  reset_addr: 0x00000000

  # mtvec cố định ban đầu: test sẽ ghi lại
  mtvec_reset_val: 0x00000000

  # Supported privilege modes: M-mode only
  supported_priv_modes:
    - M
```

---

#### File 3: `rvmodel_macros.h` (cơ chế halt cho SoC này)

```c
/*
 * rvmodel_macros.h — DUT-specific halt và boot macros cho rv32i_soc
 *
 * Halt mechanism: EBREAK + x31 register
 *   x31 = 1 → TEST_PASS (testbench detects ebreak, reads x31=1)
 *   x31 = 0 → TEST_FAIL (testbench detects ebreak, reads x31=0)
 *
 * Testbench monitors wb_ebreak signal from zicsr module.
 */

#ifndef RVMODEL_MACROS_H
#define RVMODEL_MACROS_H

/* ---------- HALT ---------- */
#define RVMODEL_HALT_PASS    \
    addi x31, x0, 1;        \
    ebreak

#define RVMODEL_HALT_FAIL    \
    addi x31, x0, 0;        \
    ebreak

/* ---------- BOOT ----------
 * Chạy trước khi test body bắt đầu:
 *   1. Tắt tất cả interrupts (MIE=0, mie=0)
 *   2. Gán trap handler dự phòng (bắt unexpected exceptions → FAIL)
 */
#define RVMODEL_BOOT                              \
    .global rvtest_entry_point;                   \
    rvtest_entry_point:                           \
        csrwi mstatus, 0;    /* MIE=0 */          \
        csrwi mie,     0;    /* tắt mọi ngắt */   \
        la    t0, _rvtest_trap_handler;           \
        csrw  mtvec, t0;     /* trap → FAIL */

/* ---------- DATA SECTION ----------
 * Section DUT-specific data (đặt sau signature region trong .data)
 * Cho SoC này không cần extra data → section rỗng
 */
#define RVMODEL_DATA_SECTION                           \
    .pushsection .dut_data, "aw", @progbits;           \
    .align 4;                                          \
    .popsection;

#define RVMODEL_DATA_BEGIN                             \
    .global rvmodel_data_begin;                        \
    rvmodel_data_begin:

#define RVMODEL_DATA_END                               \
    .global rvmodel_data_end;                          \
    rvmodel_data_end:

/* ---------- TRAP HANDLER ----------
 * Đặt tại cuối file test (sau main test body).
 * Khi có unexpected exception → signal FAIL.
 *
 * Lưu ý: Các test cho ECALL/EBREAK/Zicsr cần handler phức tạp hơn.
 * Với RV32I base instructions: handler này chỉ là safety net.
 */
#define RVMODEL_TRAP_HANDLER                       \
    .global _rvtest_trap_handler;                  \
    _rvtest_trap_handler:                          \
        addi x31, x0, 0;  /* x31=0 = FAIL */      \
        ebreak;

#endif /* RVMODEL_MACROS_H */
```

---

#### File 4: `link.ld` (linker script cho compliance tests)

```ld
/* link.ld — Linker script cho ACT compliance tests
 * IMEM: 0x00000000..0x0000FFFF (64KB) — code
 * DMEM: 0x00010000..0x0001FFFF (64KB) — data + signature
 *
 * Signature region sẽ nằm tại 0x00010000 + offset (managed bởi ACT macros)
 */

OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)

MEMORY {
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rw) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
    /* Code */
    .text.init 0x00000000 : {
        *(.text.init)
    } > IMEM

    .text : {
        *(.text*)
    } > IMEM

    .rodata : {
        *(.rodata*)
    } > IMEM

    /* Data: bắt đầu tại 0x00010000 (DMEM base) */
    .data 0x00010000 : {
        *(.data*)
        . = ALIGN(4);
    } > DMEM

    /* Signature region: labels begin_signature / end_signature
     * được đặt bởi test assembly (RVTEST_SIG_BEGIN/END macros)
     * ACT tự manage section .rvtest_sig_begin/.rvtest_sig_end */
    .rvtest_sig_begin : { *(.rvtest_sig_begin) } > DMEM
    .rvtest_sig_end   : { *(.rvtest_sig_end)   } > DMEM

    /* DUT-specific data */
    .dut_data : { *(.dut_data*) } > DMEM

    .bss : {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    } > DMEM
}
```

---

#### File 5: `run_cmd.txt` (cách chạy một test trên Icarus Verilog)

```bash
bash /home/baoslinux/riscv_soc_thesis/tb/scripts/run_one_test.sh $elf
```

Tạo script `tb/scripts/run_one_test.sh`:

```bash
#!/bin/bash
# run_one_test.sh — Chạy một ACT compliance test ELF trên Icarus Verilog

set -e

ELF="$1"
BASENAME=$(basename "$ELF" .elf)
HEX="/tmp/act_${BASENAME}.hex"
TESTBENCH_VVP="/home/baoslinux/riscv_soc_thesis/tb/system/tb_compliance.vvp"
LOGFILE="/tmp/act_${BASENAME}.log"

# Bước 1: Compile testbench (nếu chưa có)
if [ ! -f "$TESTBENCH_VVP" ]; then
    echo "[run_one_test] Compiling testbench..."
    make -C /home/baoslinux/riscv_soc_thesis/tb compliance_compile
fi

# Bước 2: ELF → Verilog hex
riscv64-unknown-elf-objcopy \
    -O verilog \
    --verilog-data-width 4 \
    "$ELF" "$HEX"

# Bước 3: Chạy simulation
timeout 10s vvp "$TESTBENCH_VVP" +HEX="$HEX" > "$LOGFILE" 2>&1

# Bước 4: Kiểm tra kết quả
if grep -q "TEST_PASS" "$LOGFILE"; then
    echo "PASS: $BASENAME"
    exit 0
elif grep -q "TEST_FAIL" "$LOGFILE"; then
    echo "FAIL: $BASENAME"
    cat "$LOGFILE"    # in chi tiết để debug
    exit 1
else
    echo "ERROR: No PASS/FAIL marker — $BASENAME (possible timeout or deadlock)"
    cat "$LOGFILE"
    exit 2
fi
```

```bash
chmod +x tb/scripts/run_one_test.sh
```

---

### 2.5 Compliance Testbench (`tb/system/tb_compliance.sv`)

Testbench này dùng chung cho ACT compliance và full-system smoke test. Instantiate `soc_top` với AHB clock/IRQ stubbed.

```systemverilog
`timescale 1ns/1ps

module tb_compliance;

    //=========================================================
    // 1. Clocks và Reset
    //=========================================================
    logic clk_cpu, clk_ahb, rst_n;

    initial clk_cpu = 0;
    always  #5 clk_cpu = ~clk_cpu;     // 1GHz

    initial clk_ahb = 0;
    always  #10 clk_ahb = ~clk_ahb;    // 500MHz

    initial begin
        rst_n = 0;
        repeat(10) @(posedge clk_cpu);
        @(negedge clk_cpu);
        rst_n = 1;
    end

    //=========================================================
    // 2. DUT — soc_top (AHB IRQs stubbed = 0)
    //=========================================================
    soc_top u_soc (
        .clk_cpu  (clk_cpu),
        .clk_ahb  (clk_ahb),
        .rst_n    (rst_n)
    );
    // Không có external IRQ inputs trên soc_top (IRQ từ SFR internal)

    //=========================================================
    // 3. Program Loading
    //=========================================================
    string hex_file;
    initial begin
        if (!$value$plusargs("HEX=%s", hex_file)) begin
            $display("[ERROR] Must provide +HEX=<path>");
            $fatal(1, "Missing HEX argument");
        end
        // Đợi một chút để reset settle trước khi load
        #1;
        $readmemh(hex_file, u_soc.u_imem.mem);
        $display("[INFO] Loaded: %s", hex_file);
    end

    //=========================================================
    // 4. VCD Dump (tắt mặc định, bật khi debug với +DUMP)
    //=========================================================
    initial begin
        if ($test$plusargs("DUMP")) begin
            $dumpfile("tb_compliance.vcd");
            $dumpvars(0, tb_compliance);
        end
    end

    //=========================================================
    // 5. Timeout Watchdog
    //=========================================================
    initial begin
        // 50,000 cycles = 50µs @ 1GHz — đủ cho test programs dài nhất
        repeat(50000) @(posedge clk_cpu);
        $display("[TIMEOUT] Simulation exceeded 50000 cycles — possible deadlock");
        $fatal(1, "TIMEOUT");
    end

    //=========================================================
    // 6. EBREAK Monitor — Detect HALT từ test program
    //
    // wb_ebreak signal: output của mem2_wb_reg → input của zicsr
    // Khi ebreak đến WB stage, check x31 từ register file:
    //   x31 = 1 → PASS (RVMODEL_HALT_PASS)
    //   x31 = 0 → FAIL (RVMODEL_HALT_FAIL)
    //   x31 = khác → unexpected
    //=========================================================
    always @(posedge clk_cpu) begin
        // Hierarchical path: soc_top → zicsr.wb_ebreak
        // wb_ebreak là input của zicsr, đến từ mem2_wb_reg.ebreak_out
        if (u_soc.u_zicsr.wb_ebreak === 1'b1) begin
            // Register file đã commit x31 trước khi ebreak đến WB
            case (u_soc.u_rf.registers[31])
                32'd1: begin
                    $display("TEST_PASS");
                    $finish(0);
                end
                32'd0: begin
                    $display("TEST_FAIL");
                    $display("  mepc=0x%08X mcause=0x%08X",
                        u_soc.u_zicsr.mepc, u_soc.u_zicsr.mcause);
                    $finish(1);
                end
                default: begin
                    $display("TEST_FAIL (unexpected x31=0x%08X)",
                        u_soc.u_rf.registers[31]);
                    $finish(1);
                end
            endcase
        end
    end

endmodule
```

> **Lưu ý hierarchical paths**: `u_soc.u_rf.regs[31]` và `u_soc.u_zicsr.wb_ebreak` yêu cầu tên instance trong `soc_top.sv` khớp. Kiểm tra `soc_top.sv` để xác nhận tên instance `u_rf`, `u_zicsr`, `u_imem`.

---

### 2.6 Thêm Target vào Makefile

Trong `tb/Makefile`, thêm:

```makefile
# ─────────── Compliance Testbench ───────────
compliance_compile:
	$(IVERILOG) -o system/tb_compliance.vvp \
	    system/tb_compliance.sv $(RTL_ALL)

# Chạy một test cụ thể (dùng để debug)
compliance_single:
	bash scripts/run_one_test.sh $(ELF)
# Ví dụ: make compliance_single ELF=/path/to/add-01.elf

# Chạy toàn bộ RV32I compliance suite
compliance_rv32i: compliance_compile
	CONFIG_FILES=../riscv-arch-test/config/cores/baoslinux/rv32i_soc/test_config.yaml \
	    make -C ../riscv-arch-test --jobs $(shell nproc) 2>&1 | tee compliance_results.log
	@echo "=== Compliance Results ==="
	@grep -E "PASS|FAIL|ERROR" compliance_results.log | tail -20
```

---

### 2.7 Alternative: Dùng Trực Tiếp riscv-tests (Nếu ACT 4.0 Quá Phức Tạp)

`riscv-tests` là bộ test cũ hơn (không phải official compliance), nhưng đơn giản và không cần Sail. Phù hợp nếu muốn verify nhanh trước khi setup ACT 4.0.

```bash
git clone https://github.com/riscv-software-src/riscv-tests
cd riscv-tests
git submodule update --init --recursive

# Build với GCC 13 (apt)
autoconf
./configure --prefix=/tmp/riscv-tests-build \
    --with-xlen=32 \
    CC=riscv64-unknown-elf-gcc \
    CFLAGS="-march=rv32i -mabi=ilp32"
make
```

Sau khi build, mỗi test là một ELF file tại `isa/rv32ui-p-add`, `isa/rv32ui-p-beq`, etc.

**Cơ chế pass/fail**: `riscv-tests` dùng `tohost` address — khi test done, write 1 vào `tohost` (PASS) hoặc non-zero FAIL code. Cần adapt `tb_compliance.sv` để monitor DMEM write tới địa chỉ `tohost` thay vì monitor ebreak.

**Lựa chọn thực tế cho luận văn:**

| Lựa chọn | Setup time | Coverage | Acceptance |
|----------|-----------|---------|------------|
| **riscv-tests** | ~30 phút | RV32I đủ | Được chấp nhận, nhưng non-official |
| **ACT 4.0** | ~3–4 giờ | RV32I + Zicsr official | Compliance chính thức theo RISC-V Int'l |

---

### 2.8 Verify Instance Names Trong soc_top

Trước khi chạy `tb_compliance.sv`, xác nhận các hierarchical path:

```bash
grep -n "u_rf\|u_zicsr\|u_imem\|u_dmem" RTL/soc_top.sv | head -20
```

Tên đã xác nhận từ `soc_top.sv`: `u_imem`, `u_rf`, `u_zicsr`.
Array bên trong đã xác nhận: `imem.mem`, `register_file.registers`.

---

## Phần 3 — Thứ Tự Thực Hiện Khuyến Nghị

```
Tuần 1: Toolchain + viết programs hex cho unit tests
  ├── apt install gcc-riscv64-unknown-elf  ← 5 phút
  ├── Test compile + verify objdump        ← 15 phút
  └── Viết 2-3 programs hex đơn giản      ← 1-2 giờ

Tuần 2-4: Unit tests và pipeline tests (theo TESTBENCH_STRATEGY.md)
  └── Dùng GCC 13 (apt) cho toàn bộ phase này

Sau khi pipeline tests pass:
  ├── Setup riscv-tests (30 phút) → verify nhanh
  └── Setup ACT 4.0 đầy đủ (3-4 giờ) → official compliance claim
```

> **Khuyến nghị cho luận văn**: Làm tốt unit/integration tests trước. ACT 4.0 compliance là "bonus" chứng minh thiết kế đúng chuẩn — nên đặt vào cuối timeline khi các test tự viết đã pass hết.
