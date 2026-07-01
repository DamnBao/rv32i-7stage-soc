# SPEC.md — Đặc Tả Kỹ Thuật Hệ Thống RISC-V SoC

**Dự án:** CPU RV32I + Zicsr tích hợp trên SoC với ngoại vi AXI-Lite và AHB-Lite  
**Phiên bản:** 1.0  
**Ngày:** 2026-06-20  
**Ngôn ngữ RTL:** SystemVerilog (synthesizable)  
**Bộ mô phỏng:** Icarus Verilog 12 (`iverilog -g2012`)

---

## Mục Lục

1. [Tổng Quan Dự Án](#1-tổng-quan-dự-án)
2. [Cơ Sở Lý Thuyết](#2-cơ-sở-lý-thuyết)
3. [Kiến Trúc Hệ Thống](#3-kiến-trúc-hệ-thống)
4. [Bản Đồ Bộ Nhớ](#4-bản-đồ-bộ-nhớ)
5. [Pipeline CPU — Mô Tả Từng Tầng](#5-pipeline-cpu--mô-tả-từng-tầng)
6. [Đơn Vị Điều Khiển Hazard và Forwarding](#6-đơn-vị-điều-khiển-hazard-và-forwarding)
7. [Hệ Thống Bộ Nhớ](#7-hệ-thống-bộ-nhớ)
8. [Bus Interface AXI-Lite](#8-bus-interface-axi-lite)
9. [Bus Interface AHB-Lite và CDC](#9-bus-interface-ahb-lite-và-cdc)
10. [Khối Xử Lý Ngắt và Ngoại Lệ (Zicsr)](#10-khối-xử-lý-ngắt-và-ngoại-lệ-zicsr)
11. [Module Tổng Hợp soc_top](#11-module-tổng-hợp-soc_top)
12. [Luồng Hoạt Động Hệ Thống](#12-luồng-hoạt-động-hệ-thống)
13. [Phủ Sóng Hazard Pipeline](#13-phủ-sóng-hazard-pipeline)

---

## 1. Tổng Quan Dự Án

### 1.1 Mục Đích

Dự án này thiết kế và xác minh một **hệ thống trên chip (SoC)** hoàn chỉnh dựa trên kiến trúc tập lệnh RISC-V, phục vụ mục đích nghiên cứu và học thuật trong khuôn khổ luận văn tốt nghiệp. Hệ thống chứng minh khả năng triển khai một vi xử lý pipeline hiệu suất cao, tích hợp với các giao thức bus công nghiệp chuẩn (AXI4-Lite, AHB-Lite), và xử lý ngắt/ngoại lệ theo đặc tả RISC-V Privileged Architecture.

### 1.2 Phạm Vi

Hệ thống bao gồm:

- **CPU lõi:** Pipeline 7 tầng, kiến trúc RV32I (32-bit RISC-V Integer), phần mở rộng Zicsr
- **Bộ nhớ tích hợp:** IMEM 64KB và DMEM 64KB đồng bộ 1 chu kỳ
- **Bus AXI4-Lite:** Kết nối 3 slave ngoại vi, cùng miền xung nhịp 1GHz với CPU
- **Bus AHB-Lite:** Kết nối 3 slave ngoại vi, chạy ở 500MHz với cơ chế CDC
- **Ngoại vi SFR:** 6 slave SFR (Special Function Register), mỗi slave 8 thanh ghi 32-bit; REG7[0] sinh ngắt
- **Xử lý ngắt:** M-mode interrupts (MEI từ ngoại vi, MSI từ phần mềm), vectored interrupt mode
- **Xử lý ngoại lệ:** Illegal instruction, ECALL, EBREAK, Load/Store Access Fault, Bus Error

### 1.3 Ý Nghĩa Kỹ Thuật

| Khía cạnh | Đóng góp |
|-----------|----------|
| **Pipeline 7 tầng** | Tăng throughput bằng cách chồng chéo thực thi nhiều lệnh đồng thời |
| **Forwarding unit** | Giải quyết RAW hazard không cần stall ở gap-1/2/3/4 |
| **Dual-clock integration** | Minh chứng kỹ thuật CDC dùng FIFO Gray-code để kết nối 1GHz ↔ 500MHz |
| **AXI & AHB co-existence** | CPU truy cập hai bus khác nhau thông qua cùng một địa chỉ vật lý |
| **Precise exception** | Không hủy giao dịch bus đang diễn ra; ngoại lệ được báo cáo đúng lệnh |

---

## 2. Cơ Sở Lý Thuyết

### 2.1 Kiến Trúc Tập Lệnh RISC-V (ISA)

RISC-V là một kiến trúc tập lệnh mở (open ISA), được thiết kế theo triết lý **RISC (Reduced Instruction Set Computer)**: số lượng lệnh nhỏ, định dạng cố định, thực thi trong 1 chu kỳ trên pipeline lý tưởng.

#### Đặc điểm RV32I (base integer, 32-bit)

- **Độ rộng thanh ghi:** 32 thanh ghi nguyên x0–x31, mỗi thanh ghi 32-bit. Thanh ghi x0 luôn bằng 0 (hardwired zero).
- **Chiều rộng lệnh:** 32-bit cố định (không hỗ trợ compressed trong dự án này)
- **Địa chỉ:** 32-bit, byte-addressable, word-aligned fetch
- **Số lượng lệnh:** 47 lệnh cơ bản

#### Định dạng lệnh RV32I

RISC-V định nghĩa 6 định dạng mã hóa, tất cả đều 32-bit:

```
R-type: [funct7|rs2|rs1|funct3|rd|opcode]  — Arithmetic register-register
I-type: [imm[11:0]|rs1|funct3|rd|opcode]   — Load, ALU-immediate, JALR, CSR
S-type: [imm[11:5]|rs2|rs1|funct3|imm[4:0]|opcode] — Store
B-type: [imm[12|10:5]|rs2|rs1|funct3|imm[4:1|11]|opcode] — Branch
U-type: [imm[31:12]|rd|opcode]             — LUI, AUIPC
J-type: [imm[20|10:1|11|19:12]|rd|opcode] — JAL
```

Immediate values luôn được **sign-extended** lên 32-bit trước khi sử dụng.

#### Nhóm lệnh RV32I

| Nhóm | Lệnh | Chức năng |
|------|------|-----------|
| Arithmetic | ADD, SUB, ADDI | Cộng/trừ thanh ghi và immediate |
| Logical | AND, OR, XOR, ANDI, ORI, XORI | Phép logic bit |
| Shift | SLL, SRL, SRA, SLLI, SRLI, SRAI | Dịch trái/phải logic/số học |
| Compare | SLT, SLTU, SLTI, SLTIU | So sánh có dấu/không dấu, ghi kết quả 0/1 |
| Load | LW, LH, LB, LHU, LBU | Đọc từ bộ nhớ (word/half/byte, có/không sign-extend) |
| Store | SW, SH, SB | Ghi vào bộ nhớ |
| Branch | BEQ, BNE, BLT, BGE, BLTU, BGEU | Rẽ nhánh có điều kiện |
| Jump | JAL, JALR | Nhảy không điều kiện, ghi PC+4 vào rd |
| PC-relative | AUIPC | Cộng immediate dịch 12-bit vào PC hiện tại |
| Immediate | LUI | Nạp 20-bit immediate vào phần cao thanh ghi |
| System | ECALL, EBREAK | Gọi hệ điều hành / gỡ lỗi |

### 2.2 Phần Mở Rộng Zicsr (Control and Status Register)

Phần mở rộng **Zicsr** thêm 6 lệnh để đọc/ghi các thanh ghi điều khiển-trạng thái (CSR), và định nghĩa cơ chế xử lý ngắt/ngoại lệ ở M-mode (Machine mode — đặc quyền cao nhất).

#### Lệnh CSR

| Lệnh | Mã hóa | Hoạt động |
|------|--------|-----------|
| CSRRW | funct3=001 | Đọc CSR → rd; ghi rs1 vào CSR |
| CSRRS | funct3=010 | Đọc CSR → rd; set các bit 1 trong rs1 |
| CSRRC | funct3=011 | Đọc CSR → rd; clear các bit 1 trong rs1 |
| CSRRWI | funct3=101 | Đọc CSR → rd; ghi zimm (5-bit zero-extended) vào CSR |
| CSRRSI | funct3=110 | Đọc CSR → rd; set bits theo zimm |
| CSRRCI | funct3=111 | Đọc CSR → rd; clear bits theo zimm |

#### Thanh Ghi CSR Hỗ Trợ

| CSR | Địa chỉ | Chức năng |
|-----|---------|-----------|
| `mstatus` | 0x300 | Machine Status: `MIE` bit 3 (global interrupt enable), `MPIE` bit 7 |
| `mie` | 0x304 | Machine Interrupt Enable: `MSIE` bit 3, `MEIE` bit 11 |
| `mtvec` | 0x305 | Machine Trap Vector: base address + mode (00=direct, 01=vectored) |
| `mepc` | 0x341 | Machine Exception PC: PC của lệnh gây ra trap |
| `mcause` | 0x342 | Nguyên nhân trap: bit 31=interrupt, bits[30:0]=exception code |
| `mip` | 0x344 | Machine Interrupt Pending (read-only): phản ánh trạng thái IRQ |

#### Cơ Chế Trap (Ngắt và Ngoại Lệ)

Khi xảy ra trap:
1. `mepc ← PC` của lệnh gây ra trap (hoặc lệnh kế tiếp với interrupt)
2. `mcause ← {is_interrupt, cause_code}`
3. `mstatus.MPIE ← mstatus.MIE` (lưu trạng thái cũ)
4. `mstatus.MIE ← 0` (tắt ngắt toàn cục)
5. `PC ← mtvec + 4×cause` (vectored mode) hoặc `PC ← mtvec` (direct mode)

Khi `MRET`:
1. `PC ← mepc`
2. `mstatus.MIE ← mstatus.MPIE`

#### Bảng Mã mcause

| mcause | Loại | Nguyên nhân |
|--------|------|-------------|
| 0x0000_0000 | Exception | Instruction Address Misaligned |
| 0x0000_0002 | Exception | Illegal Instruction |
| 0x0000_0003 | Exception | Breakpoint (EBREAK) |
| 0x0000_0005 | Exception | Load Access Fault |
| 0x0000_0007 | Exception | Store/AMO Access Fault |
| 0x0000_000B | Exception | Environment Call from M-mode (ECALL) |
| 0x8000_0003 | Interrupt | Machine Software Interrupt |
| 0x8000_000B | Interrupt | Machine External Interrupt |

### 2.3 Pipeline Processor

**Pipeline** là kỹ thuật tổ chức CPU theo nhiều tầng (stage), mỗi tầng thực hiện một phần của chu trình thực thi. Các tầng hoạt động song song, xử lý các lệnh khác nhau cùng một lúc (instruction-level parallelism).

**Throughput lý tưởng:** 1 lệnh/chu kỳ (1 IPC — Instructions Per Cycle).

**Vấn đề hazard:** Do các lệnh liên tiếp có thể phụ thuộc dữ liệu hoặc điều khiển lẫn nhau, pipeline phải có cơ chế xử lý:

- **RAW (Read After Write) hazard:** Lệnh sau đọc thanh ghi mà lệnh trước chưa ghi xong → giải quyết bằng **forwarding** (bypass dữ liệu từ tầng trước về đầu vào tầng EX)
- **Load-use hazard:** LW + lệnh ngay sau dùng kết quả LW → cần stall 1 chu kỳ (dữ liệu load có sẵn từ MEM2 nhưng lệnh kế cần đọc ở EX)
- **Control hazard:** Branch/Jump → flush các lệnh đã nạp sai vào pipeline (2 chu kỳ flush)

### 2.4 Giao Thức AXI4-Lite

**AXI4-Lite** (Advanced eXtensible Interface 4, Lite version) là giao thức bus của ARM, phần của tiêu chuẩn AMBA 4.0. Được thiết kế cho giao tiếp đơn giản với các thanh ghi điều khiển (control/status registers).

#### Kênh Giao Tiếp (5 kênh độc lập)

| Kênh | Hướng | Tín hiệu chính | Mô tả |
|------|-------|----------------|-------|
| **AW** | Master→Slave | AWADDR, AWVALID, AWREADY | Write Address |
| **W** | Master→Slave | WDATA, WSTRB, WVALID, WREADY | Write Data |
| **B** | Slave→Master | BRESP, BVALID, BREADY | Write Response |
| **AR** | Master→Slave | ARADDR, ARVALID, ARREADY | Read Address |
| **R** | Slave→Master | RDATA, RRESP, RVALID, RREADY | Read Data |

#### Giao Thức Handshake

Giao dịch xảy ra khi **cả VALID và READY đều = 1** tại cùng một cạnh xung nhịp:

```
Master: VALID=1 (data ready to send)
Slave:  READY=1 (ready to accept)
→ Transfer happens on next posedge clk
```

#### Chu Trình Ghi AXI-Lite

```
Cycle 1: AWADDR+AWVALID=1, WDATA+WVALID=1 (phát đồng thời)
Cycle 2: AWREADY=1, WREADY=1 (slave chấp nhận — handshake thành công)
Cycle 3: BVALID=1, BRESP=OKAY (slave báo ghi xong)
Cycle 4: BREADY=1 (master nhận response)
```

#### Chu Trình Đọc AXI-Lite

```
Cycle 1: ARADDR+ARVALID=1
Cycle 2: ARREADY=1 (handshake — slave chấp nhận địa chỉ)
Cycle 3: RDATA+RVALID=1 (slave trả dữ liệu)
Cycle 4: RREADY=1 (master nhận)
```

**Tín hiệu PROT/RESP trong dự án:**
- `AWPROT = ARPROT = 3'b000` (unprivileged, non-secure, data access)
- `WSTRB = 4'b1111` (full 32-bit word write)
- `BRESP = RRESP = 2'b00` (OKAY)

### 2.5 Giao Thức AHB-Lite

**AHB-Lite** (Advanced High-performance Bus Lite) là phiên bản đơn master của AHB (AMBA 3.0). Đặc trưng bởi bus shared (một bus dùng chung cho tất cả slave) và cơ chế pipelining address/data phase.

#### Tín Hiệu AHB-Lite

| Tín hiệu | Hướng | Mô tả |
|----------|-------|-------|
| `HADDR[31:0]` | Master→Slave | Địa chỉ (phát trong Address Phase) |
| `HTRANS[1:0]` | Master→Slave | Loại giao dịch: 00=IDLE, 10=NONSEQ |
| `HSIZE[2:0]` | Master→Slave | Kích thước: 000=byte, 001=half, 010=word |
| `HWRITE` | Master→Slave | 1=Write, 0=Read |
| `HWDATA[31:0]` | Master→Slave | Dữ liệu ghi (phát trong Data Phase) |
| `HRDATA[31:0]` | Slave→Master | Dữ liệu đọc |
| `HREADY` | Slave→Master | 1=Bus sẵn sàng, 0=Insert wait state |
| `HRESP` | Slave→Master | 0=OKAY, 1=ERROR |
| `HSEL` | Decode→Slave | 1=Slave được chọn |

#### Pipelining AHB

AHB sử dụng pipelining giữa Address Phase và Data Phase:

```
Cycle N:   HADDR=A, HTRANS=NONSEQ (Address Phase of transaction at A)
Cycle N+1: HWDATA=D (Data Phase of transaction at A)
           HADDR=B (Address Phase of NEXT transaction, if any)
```

Trong dự án này, giao dịch đơn lẻ (non-pipelined) được dùng, nên:
```
Cycle 1: HADDR=A, HTRANS=NONSEQ, HWRITE=1/0
Cycle 2: HWDATA=D (nếu ghi), HREADY=1 (slave ready)
```

### 2.6 Clock Domain Crossing (CDC)

Khi hai miền xung nhịp khác tần số và pha cần giao tiếp, cần cơ chế CDC để tránh **metastability** (trạng thái không xác định của flip-flop khi tín hiệu vi phạm setup/hold time).

#### Nguy Cơ Metastability

Flip-flop bị metastability khi dữ liệu thay đổi quá gần cạnh xung nhịp lấy mẫu. Tuy MTBF (Mean Time Between Failures) rất cao, vẫn phải dùng cơ chế đồng bộ hóa.

#### 2-FF Synchronizer (cho tín hiệu điều khiển đơn bit)

```
async_signal → [FF1] → [FF2] → sync_signal
               clk_dest  clk_dest
```
- Xác suất metastability giảm theo hàm mũ qua mỗi tầng FF
- Phù hợp cho tín hiệu 1-bit (như IRQ line)
- **Không dùng** cho dữ liệu nhiều bit (có thể bị tear/skew)

#### Async FIFO (cho dữ liệu nhiều bit)

Sử dụng **FIFO với Gray-code pointer** để truyền dữ liệu nhiều bit qua hai miền xung nhịp:
- Write side: clk_wr; Read side: clk_rd
- Gray code đảm bảo chỉ 1 bit thay đổi mỗi bước → an toàn khi đồng bộ qua 2-FF synchronizer
- Cơ chế `full`/`empty` từ so sánh con trỏ đã đồng bộ

---

## 3. Kiến Trúc Hệ Thống

### 3.1 Sơ Đồ Khối Tổng Thể

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SoC Top (soc_top.sv)                              │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │              CPU Pipeline (1GHz)                                      │   │
│  │                                                                       │   │
│  │  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌──────┐  ┌──────┐  ┌────┐  │   │
│  │  │ IF1 │→│ IF2 │→│  ID │→│  EX │→│ MEM1 │→│ MEM2 │→│ WB │  │   │
│  │  └──┬──┘  └──┬──┘  └──┬──┘  └──┬──┘  └──┬───┘  └──┬───┘  └──┬─┘  │   │
│  │     │        │        │        │         │          │          │     │   │
│  │  ┌──▼────────▼────────▼────────▼─────────┘          │          │     │   │
│  │  │        Hazard Unit + Forwarding Unit               │          │     │   │
│  │  └────────────────────────────────────────────────────┘          │     │   │
│  │                                                                   │     │   │
│  │  ┌────────────────────────────────────────────────────────────────▼──┐ │   │
│  │  │                    Zicsr (CSR + Interrupt/Exception)               │ │   │
│  │  └───────────────────────────────────────────────────────────────────┘ │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌────────────┐      ┌──────────────────────────────────────────────────┐   │
│  │  IMEM 64KB │      │          AXI-Lite Subsystem (1GHz)               │   │
│  │  (1GHz)    │      │  ┌──────────────┐   ┌─────────────────────────┐ │   │
│  └────────────┘      │  │ axi_interface│→ │    axi_interconnect      │ │   │
│                       │  └──────────────┘   │  (addr decode, 3 slaves) │ │   │
│  ┌────────────┐      │                       └──┬──────┬──────┬───────┘ │   │
│  │  DMEM 64KB │      │                         S0    S1    S2           │   │
│  │  (1GHz)    │      │                    ┌────┘  ┌──┘  ┌──┘           │   │
│  └────────────┘      │                    │axi_sfr│     │axi_sfr       │   │
│                       │                    └───────┘     └──────────────┘   │
│                       └──────────────────────────────────────────────────┘   │
│                                                                               │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │                    AHB-Lite Subsystem                                 │   │
│  │                                                                       │   │
│  │  ┌────────────────────────────────────┐ (1GHz side)                  │   │
│  │  │   Request FIFO (1GHz→500MHz, 67b) │                              │   │
│  │  │   Response FIFO (500MHz→1GHz, 33b)│                              │   │
│  │  └────────────────────────────────────┘ (CDC)                        │   │
│  │                                                                       │   │
│  │  ┌───────────────┐   ┌──────────────────────────────────────────┐   │   │
│  │  │ ahb_interface │→ │   ahb_interconnect (addr decode, 3 slaves) │   │   │
│  │  │   (500MHz)    │   └─────────────┬──────────┬─────────────────┘   │   │
│  │  └───────────────┘                S0         S1,S2                  │   │
│  │                                ┌──┘          ┌──┘                   │   │
│  │                               ahb_sfr×3      ...                    │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Thanh Ghi Pipeline

Giữa mỗi cặp tầng liên tiếp là một **thanh ghi pipeline** (register stage) lưu trữ tất cả tín hiệu dữ liệu và điều khiển cần thiết cho tầng kế tiếp:

| Thanh ghi | Giữa tầng | File |
|-----------|-----------|------|
| `if1_if2_reg` | IF1 → IF2 | `if1_if2_reg.sv` |
| `if2_id_reg` | IF2 → ID | `if2_id_reg.sv` |
| `id_ex_reg` | ID → EX | `id_ex_reg.sv` |
| `ex_mem1_reg` | EX → MEM1 | `ex_mem1_reg.sv` |
| `mem1_mem2_reg` | MEM1 → MEM2 | `mem1_mem2_reg.sv` |
| `mem2_wb_reg` | MEM2 → WB | `mem2_wb_reg.sv` |

Tất cả thanh ghi pipeline hỗ trợ:
- **Stall:** Giữ nguyên giá trị khi `stall=1`
- **Flush:** Reset về NOP/0 khi `flush=1`
- **Ưu tiên:** `flush` > `stall` > `normal capture` (trong `id_ex_reg.sv`, flush kiểm tra trước stall)

### 3.3 Miền Xung Nhịp

| Miền | Tần số | Các module |
|------|--------|-----------|
| **clk_cpu** | 1GHz (chu kỳ 1ns) | Toàn bộ CPU pipeline, IMEM, DMEM, AXI interface, Zicsr |
| **clk_ahb** | 500MHz (chu kỳ 2ns, offset 0.3ns) | AHB interface FSM, ahb_interconnect, ahb_sfr |
| **CDC** | Async FIFO Gray-code | Ranh giới giữa clk_cpu và clk_ahb |

Reset: `rst_n` (async assert) → `reset_sync` đồng bộ về mỗi miền → `rst_ahb_n` cho AHB domain.

---

## 4. Bản Đồ Bộ Nhớ

CPU sử dụng không gian địa chỉ 32-bit (4GB). Chỉ các vùng sau được decode:

| Vùng | Địa chỉ bắt đầu | Địa chỉ kết thúc | Kích thước | Bus | Latency |
|------|-----------------|------------------|------------|-----|---------|
| **IMEM** | `0x0000_0000` | `0x0000_FFFF` | 64KB | Direct | 1 cycle |
| **DMEM** | `0x0001_0000` | `0x0001_FFFF` | 64KB | Direct | 1 cycle |
| **AXI Region** | `0x2000_0000` | `0x2FFF_FFFF` | 256MB | AXI-Lite | 4–6 cycles |
| **AHB Region** | `0x3000_0000` | `0x3FFF_FFFF` | 256MB | AHB-Lite | 6–12 cycles |

#### AXI Slave Decode (`addr[27:12]`)

| Slave | `addr[27:12]` | Địa chỉ đầy đủ | Offset | Module |
|-------|--------------|-----------------|--------|--------|
| S0 | `16'h0000` | `0x2000_0000` | 0x00–0x1C | `axi_sfr` #0 |
| S1 | `16'h0001` | `0x2000_1000` | 0x00–0x1C | `axi_sfr` #1 |
| S2 | `16'h0002` | `0x2000_2000` | 0x00–0x1C | `axi_sfr` #2 |

#### AHB Slave Decode (`addr[27:12]`)

| Slave | `addr[27:12]` | Địa chỉ đầy đủ | Offset | Module |
|-------|--------------|-----------------|--------|--------|
| S0 | `16'h0000` | `0x3000_0000` | 0x00–0x1C | `ahb_sfr` #0 |
| S1 | `16'h0001` | `0x3000_1000` | 0x00–0x1C | `ahb_sfr` #1 |
| S2 | `16'h0002` | `0x3000_2000` | 0x00–0x1C | `ahb_sfr` #2 |

#### Bố Cục SFR Slave (mỗi AXI/AHB SFR)

| Offset | Thanh ghi | Chức năng |
|--------|-----------|-----------|
| 0x00 | REG0 | General-purpose read/write |
| 0x04 | REG1 | General-purpose read/write |
| ... | ... | ... |
| 0x18 | REG6 | General-purpose read/write |
| 0x1C | REG7 | IRQ control: **REG7[0]=1 → assert irq** |

---

## 5. Pipeline CPU — Mô Tả Từng Tầng

### 5.1 Tầng IF1 — Instruction Fetch Stage 1

**File:** `if1_stage.sv`  
**Chức năng:** Tính toán và duy trì **Program Counter (PC)**. PC được gửi đến IMEM ngay trong cùng chu kỳ.

#### Ports

| Port | Hướng | Độ rộng | Mô tả |
|------|-------|---------|-------|
| `clk` | Input | 1 | Xung nhịp 1GHz |
| `rst_n` | Input | 1 | Reset async active-low |
| `stall` | Input | 1 | Từ hazard_unit: giữ PC hiện tại |
| `flush` | Input | 1 | Từ hazard_unit: reset PC (sau jump/branch đã resolve) |
| `jump_addr` | Input | 32 | Địa chỉ đích (từ addr_adder khi branch taken, hoặc từ zicsr) |
| `pc_out` | Output | 32 | PC hiện tại → IMEM và if1_if2_reg |

#### Hành Vi

```
always_ff @(posedge clk or negedge rst_n):
  if (!rst_n)  pc ← 0x00000000
  else if (flush) pc ← jump_addr   // redirect to branch/trap target
  else if (!stall) pc ← pc + 4     // normal advance
  // stall: pc unchanged
```

**Tín hiệu `flush_pc`** từ hazard_unit được sử dụng khi:
- Branch taken (branch_taken=1, sau khi tính toán ở EX)
- Jump instruction (jump=1, đã biết target ở EX)
- Zicsr trap/mret (zicsr_flush=1, target từ zicsr_pc)

**Ưu tiên nguồn `jump_addr`** (giải quyết trong `soc_top`): Zicsr > Branch/Jump EX.

---

### 5.2 Thanh Ghi IF1/IF2 (`if1_if2_reg`)

**File:** `if1_if2_reg.sv`  
**Lưu trữ:** `{pc, valid_flag}` sau IF1, chuyển sang IF2.

- Khi `flush`: ghi NOP indicator (valid=0)
- Khi `stall`: giữ nguyên (PC và IMEM output phải đồng bộ)

---

### 5.3 Tầng IF2 — Instruction Fetch Stage 2

**File:** `if2_stage.sv`  
**Chức năng:** Tiếp nhận kết quả từ IMEM (1-cycle latency) và PC từ thanh ghi IF1/IF2, hội tụ thành một đầu ra duy nhất chuyển sang ID.

#### Ports

| Port | Hướng | Độ rộng | Mô tả |
|------|-------|---------|-------|
| `pc_in` | Input | 32 | PC từ thanh ghi IF1/IF2 |
| `instr_in` | Input | 32 | Mã lệnh từ IMEM |
| `pc_out` | Output | 32 | PC chuyển tiếp xuống ID |
| `instr_out` | Output | 32 | Mã lệnh chuyển tiếp xuống ID |

**Lưu ý:** IF2 là tầng hội tụ — nó không thực hiện tính toán mà chỉ đảm bảo PC và instruction đến ID cùng thời điểm (IMEM có độ trễ 1 cycle, trong khi PC từ IF1 đã đi qua 1 thanh ghi).

---

### 5.4 Module IMEM

**File:** `imem.sv`  
**Chức năng:** Instruction Memory — ROM synchronous 64KB chứa mã chương trình.

#### Ports

| Port | Hướng | Độ rộng | Mô tả |
|------|-------|---------|-------|
| `clk` | Input | 1 | 1GHz |
| `stall` | Input | 1 | Giữ output khi stall (đồng bộ với if1_if2_reg freeze) |
| `flush` | Input | 1 | Output NOP (0x0000_0013 = addi x0,x0,0) khi zicsr_flush |
| `addr` | Input | 32 | PC từ if1_stage (kết nối trực tiếp) |
| `instr_out` | Output | 32 | Lệnh tương ứng với addr |

#### Hành Vi

```
// Synchronous read (output registered)
always_ff @(posedge clk):
  if (flush)      instr_out ← NOP   // Chặn ghost instruction
  else if (!stall) instr_out ← mem[addr[15:2]]
  // stall: giữ output cũ
```

**Quan trọng:** IMEM dùng `addr[15:2]` để index mảng word (64KB / 4 = 16384 words). IMEM hỗ trợ `stall` để giữ output khi pipeline bị đóng băng — nếu không có stall, IMEM sẽ đọc địa chỉ mới trong khi if1_if2_reg vẫn giữ địa chỉ cũ, dẫn đến mismatch.

---

### 5.5 Tầng ID — Instruction Decode

**File:** `id_decoder.sv` (decode), `register_file.sv` (đọc thanh ghi)  
**Chức năng:** Giải mã lệnh thành tín hiệu điều khiển, đọc dữ liệu nguồn từ register file.

#### Ports của id_decoder

| Port | Hướng | Mô tả |
|------|-------|-------|
| `instr[31:0]` | Input | Mã lệnh 32-bit |
| `rs1_addr[4:0]` | Output | Địa chỉ thanh ghi nguồn 1 |
| `rs2_addr[4:0]` | Output | Địa chỉ thanh ghi nguồn 2 |
| `rd_addr[4:0]` | Output | Địa chỉ thanh ghi đích |
| `csr_addr[11:0]` | Output | Địa chỉ CSR (bits [31:20] của lệnh) |
| `funct3[2:0]` | Output | Subtype của lệnh (từ bits [14:12]) |
| `imm[31:0]` | Output | Immediate value đã sign-extend |
| `alu_op[3:0]` | Output | Mã phép tính ALU |
| `alu_src_a` | Output | 0=rs1, 1=PC (cho AUIPC/JAL) |
| `alu_src_b` | Output | 0=rs2, 1=imm (cho I/S/B/U/J type) |
| `branch` | Output | 1 nếu là lệnh B-type |
| `jump` | Output | 1 nếu là JAL hoặc JALR |
| `jump_reg` | Output | 1 nếu là JALR (dùng rs1 + imm, không dùng PC) |
| `mem_read` | Output | 1 nếu là lệnh Load |
| `mem_write` | Output | 1 nếu là lệnh Store |
| `mem_size[1:0]` | Output | 00=byte, 01=half, 10=word |
| `mem_ext` | Output | 0=zero-extend, 1=sign-extend (cho LH/LB) |
| `reg_write` | Output | 1 nếu lệnh ghi kết quả vào rd |
| `wb_sel[1:0]` | Output | Nguồn dữ liệu ghi: 00=ALU, 01=MEM, 10=PC+4, 11=CSR |
| `csr_we` | Output | 1 nếu ghi CSR |
| `csr_op[1:0]` | Output | 01=RW, 10=RS, 11=RC |
| `csr_imm_sel` | Output | 0=dùng rs1, 1=dùng zimm (cho CSRxI) |
| `ecall` | Output | 1 nếu là ECALL |
| `ebreak` | Output | 1 nếu là EBREAK |
| `mret` | Output | 1 nếu là MRET |
| `illegal_instr` | Output | 1 nếu lệnh không hợp lệ |

#### ALU Op Encoding

| `alu_op` | Phép tính | Lệnh điển hình |
|----------|-----------|----------------|
| 4'h0 | ADD | ADD, ADDI, LW, SW, AUIPC |
| 4'h1 | SUB | SUB |
| 4'h2 | AND | AND, ANDI |
| 4'h3 | OR | OR, ORI |
| 4'h4 | XOR | XOR, XORI |
| 4'h5 | SLL | SLL, SLLI |
| 4'h6 | SRL | SRL, SRLI |
| 4'h7 | SRA | SRA, SRAI |
| 4'h8 | SLT | SLT, SLTI |
| 4'h9 | SLTU | SLTU, SLTIU |
| 4'hA | LUI pass-through | LUI (ALU passes imm unchanged) |

#### Register File

**File:** `register_file.sv`

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk`, `rst_n` | Input | Clock/reset |
| `rs1_addr[4:0]` | Input | Địa chỉ đọc port 1 |
| `rs1_data[31:0]` | Output | Dữ liệu ra port 1 (tổ hợp) |
| `rs2_addr[4:0]` | Input | Địa chỉ đọc port 2 |
| `rs2_data[31:0]` | Output | Dữ liệu ra port 2 (tổ hợp) |
| `we` | Input | Write enable |
| `rd_addr[4:0]` | Input | Địa chỉ ghi (từ WB stage) |
| `rd_data[31:0]` | Input | Dữ liệu ghi (từ WB stage) |

**WBR Bypass (gap-4 hazard):** Đọc kết hợp bypass combinational — nếu WB stage đang ghi vào cùng địa chỉ đang được đọc (và rd ≠ x0):
```
rs_data = (we && rd_addr == rs_addr && rs_addr != 0) ? rd_data : registers[rs_addr]
```

Điều này xử lý trường hợp lệnh cách nhau 4 tầng pipeline (gap-4), khi kết quả đang trong tầng WB nhưng chưa kịp cập nhật vào mảng register đồng bộ.

---

### 5.6 Tầng EX — Execute

**File:** `alu.sv`, `branch_comp.sv`, `addr_adder.sv`  
**Chức năng:** Thực thi phép tính ALU, đánh giá điều kiện branch, tính địa chỉ đích branch/jump/load/store.

#### ALU (`alu.sv`)

| Port | Hướng | Mô tả |
|------|-------|-------|
| `operand_a[31:0]` | Input | Toán hạng A (rs1 hoặc PC, sau forwarding MUX) |
| `operand_b[31:0]` | Input | Toán hạng B (rs2 hoặc imm, sau forwarding MUX) |
| `alu_op[3:0]` | Input | Mã phép tính |
| `alu_result[31:0]` | Output | Kết quả (tổ hợp) |

#### Branch Comparator (`branch_comp.sv`)

| Port | Hướng | Mô tả |
|------|-------|-------|
| `rs1_data[31:0]` | Input | Sau forwarding MUX |
| `rs2_data[31:0]` | Input | Sau forwarding MUX |
| `funct3[2:0]` | Input | Điều kiện: BEQ(000), BNE(001), BLT(100), BGE(101), BLTU(110), BGEU(111) |
| `branch` | Input | 1 nếu là lệnh B-type |
| `branch_taken` | Output | 1 nếu branch đúng điều kiện |

#### Address Adder (`addr_adder.sv`)

| Port | Hướng | Mô tả |
|------|-------|-------|
| `pc[31:0]` | Input | PC của lệnh hiện tại (từ id_ex_reg) |
| `rs1_data[31:0]` | Input | Sau forwarding (dùng cho JALR) |
| `imm[31:0]` | Input | Immediate (B-type, J-type, hoặc I-type) |
| `branch`, `jump`, `jump_reg` | Input | Phân biệt loại |
| `addr_out[31:0]` | Output | Địa chỉ đích → hazard_unit → if1_stage |

Tính toán:
- Branch: `addr_out = pc + imm_b` (PC-relative)
- JAL: `addr_out = pc + imm_j`
- JALR: `addr_out = (rs1_data + imm_i) & ~1` (mask bit 0)
- Load/Store (qua ALU): `alu_result = rs1_data + imm_i/s`

#### MUX Forwarding tại EX

Trước khi vào ALU và branch_comp, dữ liệu rs1 và rs2 đi qua **forwarding MUX 4-to-1**:

```
fwd_sel = 2'b00: dữ liệu từ register file (qua id_ex_reg)
fwd_sel = 2'b01: forward từ MEM1 (ALU result của lệnh trước 1 bước)
fwd_sel = 2'b10: forward từ MEM2 (ALU result hoặc load data của lệnh trước 2 bước)
fwd_sel = 2'b11: forward từ WB  (rf_wr_data của lệnh trước 3 bước)
```

---

### 5.7 Tầng MEM1 — Memory Access Stage 1

**File:** `mem1_stage.sv`  
**Chức năng:** Phát sinh tín hiệu điều khiển bộ nhớ. Decode địa chỉ để chọn DMEM, AXI, hoặc AHB. Phát sinh `bus_stall_req` khi truy cập bus.

#### Ports chính

| Port | Hướng | Mô tả |
|------|-------|-------|
| `addr_in[31:0]` | Input | Địa chỉ (= alu_result: địa chỉ load/store) |
| `wdata_in[31:0]` | Input | Dữ liệu ghi Store (rs2 sau forward) |
| `rs1_data_in[31:0]` | Input | Nguồn dữ liệu CSR write |
| `imm_in[31:0]` | Input | zimm cho CSR-immediate |
| `csr_addr_in[11:0]` | Input | Địa chỉ CSR |
| `mem_read_in / mem_write_in` | Input | Loại truy cập |
| `mem_size_in[1:0]` | Input | Kích thước word/half/byte |
| `dmem_re/we` | Output | Điều khiển DMEM |
| `dmem_addr[31:0]` | Output | Địa chỉ DMEM |
| `axi_req_valid` | Output | Yêu cầu AXI interface |
| `axi_req_addr/we/wdata/size` | Output | Tham số yêu cầu AXI |
| `axi_resp_valid/rdata/err` | Input | Kết quả từ AXI interface |
| `req_fifo_wr_en` | Output | Ghi vào Request FIFO (AHB) |
| `req_fifo_wr_data[66:0]` | Output | Dữ liệu: `{addr(32), wdata(32), write(1), size(2)}` |
| `resp_fifo_rd_empty` | Input | Response FIFO còn trống? |
| `resp_fifo_rd_en` | Output | Đọc từ Response FIFO |
| `bus_stall_req` | Output | Yêu cầu stall toàn pipeline |
| `csr_req_valid` | Output | Lệnh CSR tại MEM1 |
| `load_fault/store_fault` | Output | Fault signal khi addr không decode được |

#### Address Decoder tại MEM1

```
addr[31:16] == 16'h0001  →  DMEM (không stall)
addr[31:28] == 4'h2      →  AXI Interface (bus_stall_req = 1)
addr[31:28] == 4'h3      →  AHB Async FIFO (bus_stall_req = 1)
Không khớp + mem_read/write = 1  →  load_fault / store_fault
```

Bóc tách slave ID và offset:
```
slave_id   = addr[27:12]  // để axi/ahb_interconnect decode tiếp
reg_offset = addr[11:0]   // offset trong slave (0x00–0x1C cho SFR)
```

---

### 5.8 Tầng MEM2 — Memory Access Stage 2

**File:** `mem2_stage.sv`  
**Chức năng:** Thu kết quả từ DMEM (1-cycle latency) hoặc bus (AXI/AHB response), xử lý sign/zero extension cho load, chuyển tiếp dữ liệu xuống WB.

#### Nguồn dữ liệu

| `mem_src` | Nguồn | Điều kiện |
|-----------|-------|-----------|
| 2'b00 | `dmem_rdata` | Lệnh Load DMEM |
| 2'b01 | `rdata_in` | Lệnh Load AXI (từ axi_resp_rdata) |
| 2'b10 | `rdata_in` | Lệnh Load AHB (từ resp_fifo_rd_data) |

#### Sign/Zero Extension

Sau khi chọn nguồn raw data (32-bit), MEM2 áp dụng extension dựa trên `mem_size` và `mem_ext`:
- `LW`: dùng nguyên 32-bit
- `LH` (`mem_ext=1`): bits[15:0] sign-extend → 32-bit
- `LHU` (`mem_ext=0`): bits[15:0] zero-extend → 32-bit
- `LB` (`mem_ext=1`): bits[7:0] sign-extend → 32-bit
- `LBU` (`mem_ext=0`): bits[7:0] zero-extend → 32-bit

Địa chỉ `alu_result[1:0]` xác định byte offset trong word để lấy đúng byte/half.

---

### 5.9 Tầng WB — Write Back

**File:** `wb_stage.sv`  
**Chức năng:** Chọn dữ liệu kết quả cuối cùng và ghi vào register file.

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `pc_in[31:0]` | Input | PC+4 (cho JAL/JALR: wb_sel=10) |
| `alu_result_in[31:0]` | Input | Kết quả ALU (wb_sel=00) |
| `mem_rdata_in[31:0]` | Input | Dữ liệu load đã xử lý (wb_sel=01) |
| `csr_rdata_in[31:0]` | Input | Dữ liệu đọc từ CSR (wb_sel=11) |
| `rd_addr_in[4:0]` | Input | Địa chỉ thanh ghi đích |
| `reg_write_in` | Input | Cho phép ghi |
| `wb_sel_in[1:0]` | Input | Chọn nguồn |
| `rf_rd_addr[4:0]` | Output | → register_file.rd_addr |
| `rf_we` | Output | → register_file.we |
| `rf_wr_data[31:0]` | Output | → register_file.rd_data |

`wb_sel` encoding:
- `2'b00`: ALU result (ADD, SUB, AND, OR, ...)
- `2'b01`: Memory read data (LW, LH, LB, ...)
- `2'b10`: PC+4 (JAL, JALR — link register)
- `2'b11`: CSR read data (CSRRW, CSRRS, ...)

---

## 6. Đơn Vị Điều Khiển Hazard và Forwarding

### 6.1 Forwarding Unit

**File:** `forwarding_unit.sv`  
**Chức năng:** Phát hiện và giải quyết RAW hazard bằng cách chỉ định nguồn forwarding cho ALU input.

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `ex_rs1_addr[4:0]` | Input | Địa chỉ rs1 đang ở EX |
| `ex_rs2_addr[4:0]` | Input | Địa chỉ rs2 đang ở EX |
| `mem1_rd_addr[4:0]` | Input | Địa chỉ rd của lệnh ở MEM1 |
| `mem1_reg_write` | Input | Lệnh ở MEM1 có ghi thanh ghi không |
| `mem2_rd_addr[4:0]` | Input | Địa chỉ rd của lệnh ở MEM2 |
| `mem2_reg_write` | Input | Lệnh ở MEM2 có ghi thanh ghi không |
| `wb_rd_addr[4:0]` | Input | Địa chỉ rd của lệnh ở WB |
| `wb_reg_write` | Input | Lệnh ở WB có ghi thanh ghi không |
| `fwd_sel_a[1:0]` | Output | Forwarding selector cho rs1 |
| `fwd_sel_b[1:0]` | Output | Forwarding selector cho rs2 |

#### Logic Ưu Tiên

```
for rs1:
  if (mem1_reg_write && mem1_rd_addr==ex_rs1_addr && mem1_rd_addr!=0)
      fwd_sel_a = 2'b01  // MEM1 forwarding (gap-1, highest priority)
  elif (mem2_reg_write && mem2_rd_addr==ex_rs1_addr && mem2_rd_addr!=0)
      fwd_sel_a = 2'b10  // MEM2 forwarding (gap-2)
  elif (wb_reg_write && wb_rd_addr==ex_rs1_addr && wb_rd_addr!=0)
      fwd_sel_a = 2'b11  // WB forwarding (gap-3)
  else
      fwd_sel_a = 2'b00  // No forwarding — dùng register file
```

Tương tự cho rs2 với `fwd_sel_b`.

**Lưu ý:** MEM1 forwarding có ưu tiên cao nhất vì dữ liệu mới nhất (lệnh chỉ cách 1 tầng). WB forwarding (gap-3) kết hợp với WBR bypass trong register_file để phủ gap-3 và gap-4.

---

### 6.2 Hazard Unit

**File:** `hazard_unit.sv`  
**Chức năng:** Phát hiện mọi loại hazard và tạo ra các tín hiệu stall/flush cho từng thanh ghi pipeline và PC.

#### Các Loại Hazard Được Xử Lý

**1. Load-Use Hazard**

Khi lệnh Load ở EX và lệnh tiếp theo ở ID cần kết quả load:

```
load_use_stall = ex_mem_read && (
    (ex_rd_addr == id_rs1_addr && id_rs1_addr != 0) ||
    (ex_rd_addr == id_rs2_addr && id_rs2_addr != 0))
```

Hành động: Stall IF1, IF2, ID (giữ 3 tầng đầu); Insert bubble vào EX (flush id_ex_reg). 1 cycle stall.

**2. CSR-Use Hazard**

Lệnh CSR ghi thanh ghi rd với độ trễ 2 thêm cycle (vì đọc CSR xảy ra ở WB thông qua Zicsr, nhưng forwarding MEM1/MEM2 không bắt được — CSR data được cung cấp riêng từ zicsr). Phải stall khi CSR ở EX/MEM1/MEM2:

```
csr_stall_ex   = (ex_wb_sel == 2'b11) && ex_reg_write && (id uses rs1/rs2 == ex_rd)
csr_stall_mem1 = (mem1_wb_sel == 2'b11) && mem1_reg_write && (...)
csr_stall_mem2 = (mem2_wb_sel == 2'b11) && mem2_reg_write && (...)
```

→ 3/2/1 cycle stall tương ứng.

**3. Branch/Jump Hazard**

Branch và Jump resolve ở EX (sau khi `branch_comp` và `addr_adder` tính xong). Trong 2 cycle đó (IF1→IF2, IF2→ID), 2 lệnh sai đã được nạp vào pipeline:

Hành động: `flush_if1_if2 = flush_if2_id = 1` → clear 2 tầng đầu = 2 cycle penalty.

**4. Bus Stall**

Khi `bus_stall_req=1` (AXI/AHB giao dịch đang diễn ra): Stall toàn bộ pipeline từ IF1 đến MEM1 (không stall MEM2, WB để chúng vẫn tiến).

**5. Critical Fix: Bus Stall + Load-Use Đồng Thời**

Khi `bus_stall_req=1` VÀ `load_use_stall=1` cùng lúc (SW ở MEM1 stall bus, LW ở EX có load-use, BNE ở ID đọc kết quả LW):

```sv
// WRONG (original):
assign flush_id_ex = zicsr_flush | fetch_stall | ctrl_flush;
// fetch_stall = load_use_stall=1 → flush LW khỏi EX → LW bị cancel!

// CORRECT (fixed):
assign flush_id_ex = zicsr_flush | (fetch_stall & ~bus_stall_req) | ctrl_flush;
```

Lý do: Khi bus_stall=1, toàn pipeline bị hold bao gồm EX. Không cần insert bubble — bubble sẽ tự fire khi bus_stall giải phóng và load_use_stall bắt đầu tác động bình thường.

#### Outputs Của Hazard Unit

| Signal | Tác động |
|--------|----------|
| `stall_if1_if2` | Freeze thanh ghi IF1/IF2 |
| `stall_if2_id` | Freeze thanh ghi IF2/ID |
| `stall_id_ex` | Freeze thanh ghi ID/EX |
| `stall_ex_mem1` | Freeze thanh ghi EX/MEM1 |
| `stall_mem1_mem2` | Freeze thanh ghi MEM1/MEM2 |
| `stall_mem2_wb` | Freeze thanh ghi MEM2/WB |
| `stall_pc` | Freeze PC trong IF1 |
| `flush_if1_if2` | Clear thanh ghi IF1/IF2 → NOP bubble |
| `flush_if2_id` | Clear thanh ghi IF2/ID → NOP bubble |
| `flush_id_ex` | Clear thanh ghi ID/EX → NOP bubble (cancel lệnh ở EX) |
| `flush_ex_mem1` | Clear thanh ghi EX/MEM1 (dùng khi zicsr) |
| `flush_mem1_mem2` | Clear thanh ghi MEM1/MEM2 (dùng khi zicsr) |
| `flush_mem2_wb` | Clear thanh ghi MEM2/WB (dùng khi zicsr) |
| `flush_pc` | Cho phép PC load địa chỉ mới |

---

## 7. Hệ Thống Bộ Nhớ

### 7.1 IMEM

Đã mô tả ở mục 5.4. Tóm tắt:
- 64KB = 16384 words × 32-bit
- Synchronous read (1 cycle latency) — output xuất hiện ở IF2
- Hỗ trợ stall (giữ output) và flush (output NOP)
- Nội dung nạp bằng `$readmemh` trong testbench

### 7.2 DMEM

**File:** `dmem.sv`

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk` | Input | 1GHz |
| `re` | Input | Read enable (từ mem1_stage) |
| `addr[31:0]` | Input | Địa chỉ byte |
| `rdata[31:0]` | Output | Dữ liệu đọc (registered, có ở MEM2) |
| `we` | Input | Write enable |
| `wdata[31:0]` | Input | Dữ liệu ghi (full 32-bit, CPU không align trước) |
| `size[1:0]` | Input | 00=byte, 01=half, 10=word |

**Index:** `mem[addr[15:2]]` (word-addressed, 64KB = 16384 words)

**Ghi byte/half:** DMEM nội bộ xử lý byte-enable dựa trên `size` và `addr[1:0]`:
- Word (size=10): ghi nguyên `mem[idx]`
- Half (size=01): chỉ ghi 16-bit tương ứng theo `addr[1]`
- Byte (size=00): chỉ ghi 8-bit tương ứng theo `addr[1:0]`

**Đọc:** Luôn đọc 32-bit; MEM2 stage xử lý byte extraction và sign/zero extension.

### 7.3 Register File

Đã mô tả ở mục 5.5. Đặc điểm:
- 32 thanh ghi × 32-bit
- x0 hardwired = 0 (không ghi được)
- Đọc combinational (asynchronous read) với WBR bypass
- Ghi synchronous (posedge clk, khi rst_n=1 và we=1)
- Reset: tất cả registers ← 0

---

## 8. Bus Interface AXI-Lite

### 8.1 AXI Interface FSM (`axi_interface.sv`)

**Chức năng:** Chuyển đổi từ giao thức CPU-internal (req_valid/resp_valid) sang AXI4-Lite 5-kênh. Phát `bus_stall_req` ngầm thông qua `axi_resp_valid` chưa active.

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk, rst_n` | Input | 1GHz clock/reset |
| `axi_req_valid` | Input | CPU có yêu cầu mới |
| `axi_req_addr[31:0]` | Input | Địa chỉ |
| `axi_req_we` | Input | 1=Write, 0=Read |
| `axi_req_wdata[31:0]` | Input | Dữ liệu ghi |
| `axi_req_size[1:0]` | Input | Kích thước |
| `axi_resp_valid` | Output | Phản hồi sẵn sàng |
| `axi_resp_rdata[31:0]` | Output | Dữ liệu đọc |
| `axi_resp_err` | Output | Bus error (BRESP/RRESP ≠ OKAY) |
| AW channel (AWADDR,...) | Output | AXI Write Address |
| W channel (WDATA,...) | Output | AXI Write Data |
| B channel (BRESP,...) | Input | AXI Write Response |
| AR channel (ARADDR,...) | Output | AXI Read Address |
| R channel (RDATA,...) | Input | AXI Read Data |

#### FSM States

**Write path:**
```
IDLE → AW_W_PHASE (AWVALID=WVALID=1) → B_PHASE (BREADY=1) → IDLE (resp_valid=1)
```

**Read path:**
```
IDLE → AR_PHASE (ARVALID=1) → R_PHASE (RREADY=1) → IDLE (resp_valid=1, rdata captured)
```

`axi_resp_valid = 1` → mem1_stage nhận, giải phóng `bus_stall_req`.

---

### 8.2 AXI Interconnect (`axi_interconnect.sv`)

**Chức năng:** Decode địa chỉ AXI và route đến đúng slave. Hỗ trợ 3 slave (S0, S1, S2). Không có arbitration (chỉ 1 master).

#### Decode Logic

```
addr[27:12] == 16'h0000 → S0 (HSEL_S0=1)
addr[27:12] == 16'h0001 → S1 (HSEL_S1=1)
addr[27:12] == 16'h0002 → S2 (HSEL_S2=1)
Không khớp → DECERR (RRESP/BRESP = 2'b11)
```

Tín hiệu AXI từ master được duplicate đến slave đã chọn; response được MUX ngược lại.

---

### 8.3 AXI SFR Slave (`axi_sfr.sv`)

**Chức năng:** 8 thanh ghi 32-bit có thể đọc/ghi qua AXI-Lite. REG7[0] là IRQ output.

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk, rst_n` | Input | 1GHz |
| AXI slave interface | I/O | Kết nối từ axi_interconnect |
| `irq` | Output | = `sfr_reg[7][0]` |

#### Địa Chỉ Thanh Ghi

```
AWADDR[11:2] / ARADDR[11:2] = word offset (0–7)
→ reg[0] = offset 0x00, reg[7] = offset 0x1C
```

**Ghi:** Khi AW+W handshake hoàn thành → `sfr_reg[offset] ← WDATA` → `BRESP=OKAY`.  
**Đọc:** Khi AR handshake → `RDATA = sfr_reg[offset]` → `RVALID=1`.  
**IRQ:** Combinational: `irq = sfr_reg[7][0]`.

---

## 9. Bus Interface AHB-Lite và CDC

### 9.1 Async FIFO (`async_fifo.sv`)

**File:** `async_fifo_depth2` (depth=2, width parameterizable)  
**Chức năng:** Truyền dữ liệu an toàn qua biên giới xung nhịp 1GHz ↔ 500MHz.

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `wr_clk` | Input | Xung nhịp bên ghi |
| `wr_rst_n` | Input | Reset đồng bộ bên ghi |
| `wr_en` | Input | Cho phép ghi |
| `wr_data[W-1:0]` | Input | Dữ liệu ghi |
| `rd_clk` | Input | Xung nhịp bên đọc |
| `rd_rst_n` | Input | Reset đồng bộ bên đọc |
| `rd_en` | Input | Cho phép đọc |
| `rd_data[W-1:0]` | Output | Dữ liệu đọc |
| `rd_empty` | Output | FIFO trống (bên đọc) |

**Không có `full` flag:** CPU bị stall khi giao dịch, đảm bảo không overflow — chỉ 1 giao dịch được phép đồng thời.

**Gray Code:** Con trỏ write/read (2-bit, depth=2→1 bit counter + 1 bit msb Gray) được đồng bộ qua 2-FF synchronizer từ miền này sang miền kia để tính `empty`.

#### Hai FIFO trong Hệ Thống

| FIFO | Hướng | Độ rộng | Nội dung |
|------|-------|---------|---------|
| **Request FIFO** | 1GHz → 500MHz | 67-bit | `{addr(32), wdata(32), write(1), size(2)}` |
| **Response FIFO** | 500MHz → 1GHz | 33-bit | `{HRESP(1), HRDATA(32)}` |

---

### 9.2 AHB Interface FSM (`ahb_interface.sv`)

**Chức năng:** Đọc từ Request FIFO, thực thi giao dịch AHB-Lite trên 500MHz domain, ghi kết quả vào Response FIFO.

#### Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk_ahb` | Input | 500MHz |
| `rst_ahb_n` | Input | Reset đã đồng bộ 500MHz |
| `req_empty` | Input | Request FIFO trống? |
| `req_rd_en` | Output | Đọc từ Request FIFO |
| `req_rd_data[66:0]` | Input | `{addr(32), wdata(32), write(1), size(2)}` |
| `resp_wr_en` | Output | Ghi vào Response FIFO |
| `resp_wr_data[32:0]` | Output | `{HRESP(1), HRDATA(32)}` |
| AHB Master signals | I/O | HADDR, HTRANS, HSIZE, HWRITE, HWDATA, HREADY, HRDATA, HRESP |

#### FSM States

```
IDLE: req_empty=0 → đọc req → chuyển ADDR
ADDR: phát HADDR, HTRANS=NONSEQ → chuyển DATA
DATA: phát HWDATA (nếu Write); chờ HREADY=1 → đọc HRDATA (nếu Read)
      → ghi resp_fifo → chuyển IDLE
```

---

### 9.3 AHB Interconnect (`ahb_interconnect.sv`)

Tương tự AXI interconnect nhưng dùng giao thức AHB:
- Decode `HADDR[27:12]` → HSEL_S0/S1/S2
- Tổng hợp `HREADYOUT` từ các slave thành `HREADY` chung
- MUX `HRDATA` từ slave được chọn

---

### 9.4 AHB SFR Slave (`ahb_sfr.sv`)

**Chức năng:** Giống AXI SFR nhưng giao thức AHB. 8 × 32-bit registers, REG7[0] = irq.

#### Cơ Chế AHB 2-Phase

```
Cycle N (Address Phase): HSEL=1, HTRANS=NONSEQ, HWRITE=1, HADDR=A
Cycle N+1 (Data Phase):  HWDATA=D → sfr_reg[A[4:2]] ← D
```

Dữ liệu HWDATA luôn đến 1 chu kỳ sau HADDR. Module lưu HADDR trong thanh ghi (`haddr_lat`) để dùng trong Data Phase.

`HREADYOUT = 1` luôn (0 wait state). `HRESP = 0` (OKAY).

---

### 9.5 Reset Synchronizer (`reset_sync.sv`)

**Chức năng:** Đồng bộ `rst_n` (async assert, unclocked) về miền xung nhịp `clk_ahb`.

#### Hoạt Động

```
Async assert: rst_n=0 → sync_rst_n=0 ngay lập tức (async path)
Sync deassert: rst_n=1 → cần 2 posedge clk_ahb để sync_rst_n=1 (2-FF chain)
```

Dùng để tạo `rst_ahb_n` từ `rst_n` của hệ thống.

---

## 10. Khối Xử Lý Ngắt và Ngoại Lệ (Zicsr)

**File:** `zicsr.sv`  
**Chức năng:** Quản lý 6 thanh ghi CSR, xử lý trap (ngắt + ngoại lệ), đồng bộ IRQ từ AHB domain.

### 10.1 Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk, rst_n` | Input | 1GHz |
| `wb_pc[31:0]` | Input | PC của lệnh đang ở WB |
| `wb_rs1_data[31:0]` | Input | Dữ liệu nguồn CSR write (đã forward) |
| `wb_imm[31:0]` | Input | zimm cho CSRxI |
| `wb_csr_addr[11:0]` | Input | Địa chỉ CSR (bits[31:20]) |
| `wb_csr_we` | Input | Cho phép ghi CSR |
| `wb_csr_op[1:0]` | Input | Loại CSR op: 01=RW, 10=RS, 11=RC |
| `wb_csr_imm_sel` | Input | 0=rs1, 1=zimm |
| `wb_ecall` | Input | ECALL ở WB |
| `wb_ebreak` | Input | EBREAK ở WB |
| `wb_mret` | Input | MRET ở WB |
| `wb_illegal_instr` | Input | Lệnh bất hợp lệ ở WB |
| `wb_load_fault` | Input | Load Access Fault ở WB |
| `wb_store_fault` | Input | Store Access Fault ở WB |
| `ahb_irq` | Input | IRQ từ AHB domain (cần 2-FF sync) |
| `axi_irq` | Input | IRQ từ AXI domain (cùng 1GHz, kết nối thẳng) |
| `bus_stall_req` | Input | Không flush khi đang có bus transaction |
| `csr_rdata[31:0]` | Output | Dữ liệu CSR đọc (→ WB stage, rồi → forwarding) |
| `zicsr_flush` | Output | Flush toàn pipeline khi trap/mret |
| `zicsr_pc[31:0]` | Output | PC mới: mtvec (trap) hoặc mepc (mret) |

### 10.2 Thanh Ghi CSR Bên Trong

| CSR | Địa chỉ | Reset | Mô tả |
|-----|---------|-------|-------|
| `mstatus` | 0x300 | 0 | [7]=MPIE, [3]=MIE |
| `mie` | 0x304 | 0 | [11]=MEIE, [3]=MSIE |
| `mtvec` | 0x305 | 0 | [31:2]=BASE, [1:0]=MODE (01=vectored) |
| `mepc` | 0x341 | 0 | PC của lệnh gây trap |
| `mcause` | 0x342 | 0 | [31]=interrupt, [30:0]=cause code |
| `mip` | 0x344 | 0 | Read-only: [11]=MEIP, [3]=MSIP |

### 10.3 AHB IRQ Synchronizer (2-FF nội bộ)

`ahb_irq` đến từ `ahb_sfr.irq` — miền 500MHz. Bên trong `zicsr.sv`, tín hiệu này đi qua 2-FF synchronizer trước khi được sử dụng:

```sv
always_ff @(posedge clk or negedge rst_n):
  if (!rst_n) {ahb_irq_sync1, ahb_irq_sync2} <= 2'b0;
  else        {ahb_irq_sync2, ahb_irq_sync1} <= {ahb_irq_sync1, ahb_irq};
```

`ahb_irq_sync2` là tín hiệu đã an toàn về 1GHz domain.

### 10.4 Trap Priority và Vectored Mode

Khi nhiều nguồn trap xảy ra cùng lúc, zicsr xử lý theo ưu tiên:
1. Exception (ECALL, EBREAK, Illegal, Load/Store Fault) — tại WB stage
2. Interrupt (MEI, MSI) — kiểm tra mỗi chu kỳ khi `mstatus.MIE=1`

Với vectored mode (`mtvec[1:0]=01`):
```
PC = (mtvec & ~3) + 4 × cause_code
```

Ví dụ:
- MEI (cause=11): `PC = mtvec_base + 44`
- MSI (cause=3): `PC = mtvec_base + 12`
- ECALL (cause=11 exception): `PC = mtvec_base + 44`

### 10.5 CSR Read Path

Đọc CSR xảy ra ở WB stage (lệnh CSR ở WB, zicsr nhận `wb_csr_addr` và trả `csr_rdata`). Vì đọc/ghi xảy ra muộn (WB), kết quả `csr_rdata` cần phải được forward sớm hơn cho các lệnh kế tiếp — đây là lý do CSR-use hazard cần nhiều stall cycle hơn load-use.

### 10.6 Precise Exception

Zicsr kiểm tra `bus_stall_req` trước khi flush. Khi đang có giao dịch bus (AXI/AHB), **không flush** pipeline ngay cả khi có trap signal — chờ giao dịch hoàn tất để tránh cancel giao dịch giữa chừng (gây lỗi bus hoặc trạng thái không nhất quán).

---

## 11. Module Tổng Hợp soc_top

**File:** `soc_top.sv`  
**Chức năng:** Kết nối tất cả 30 module thành một SoC hoàn chỉnh.

### 11.1 Ports

| Port | Hướng | Mô tả |
|------|-------|-------|
| `clk_cpu` | Input | 1GHz — CPU, IMEM, DMEM, AXI, Zicsr |
| `clk_ahb` | Input | 500MHz — AHB interface và slaves |
| `rst_n` | Input | Async reset active-low (global) |

**Lưu ý:** SoC không có I/O ngoài vì đây là thiết kế thử nghiệm tích hợp sẵn IMEM, DMEM, và các SFR ngoại vi nội bộ.

### 11.2 Danh Sách Module Nội Bộ

| Instance | Module | Chức năng |
|----------|--------|-----------|
| `u_reset_sync` | `reset_sync` | Đồng bộ rst_n về 500MHz domain |
| `u_imem` | `imem` | Instruction memory 64KB |
| `u_dmem` | `dmem` | Data memory 64KB |
| `u_rf` | `register_file` | 32 × 32-bit registers |
| `u_if1` | `if1_stage` | IF1: PC management |
| `u_if1_if2` | `if1_if2_reg` | Pipeline register IF1/IF2 |
| `u_if2` | `if2_stage` | IF2: instruction convergence |
| `u_if2_id` | `if2_id_reg` | Pipeline register IF2/ID |
| `u_id` | `id_decoder` | ID: decode |
| `u_id_ex` | `id_ex_reg` | Pipeline register ID/EX |
| `u_alu` | `alu` | EX: ALU |
| `u_bc` | `branch_comp` | EX: branch condition |
| `u_aa` | `addr_adder` | EX: address/target calculation |
| `u_ex_mem1` | `ex_mem1_reg` | Pipeline register EX/MEM1 |
| `u_mem1` | `mem1_stage` | MEM1: bus decode and control |
| `u_mem1_mem2` | `mem1_mem2_reg` | Pipeline register MEM1/MEM2 |
| `u_mem2` | `mem2_stage` | MEM2: data aggregation |
| `u_mem2_wb` | `mem2_wb_reg` | Pipeline register MEM2/WB |
| `u_wb` | `wb_stage` | WB: write-back |
| `u_hazard` | `hazard_unit` | Hazard detection and stall/flush |
| `u_fwd` | `forwarding_unit` | Data forwarding |
| `u_zicsr` | `zicsr` | CSR + interrupt/exception |
| `u_axi_if` | `axi_interface` | AXI-Lite master interface |
| `u_axi_ic` | `axi_interconnect` | AXI address decoder/MUX |
| `u_axi_sfr0/1/2` | `axi_sfr` | 3 × AXI SFR slaves |
| `u_req_fifo` | `async_fifo_depth2` | Request FIFO 1GHz→500MHz |
| `u_resp_fifo` | `async_fifo_depth2` | Response FIFO 500MHz→1GHz |
| `u_ahb_if` | `ahb_interface` | AHB-Lite master interface |
| `u_ahb_ic` | `ahb_interconnect` | AHB address decoder/MUX |
| `u_ahb_sfr0/1/2` | `ahb_sfr` | 3 × AHB SFR slaves |

### 11.3 Kết Nối Đặc Biệt trong soc_top

**IMEM stall connection:**
```sv
// IMEM nhận tín hiệu stall từ hazard_unit để giữ output đồng bộ với if1_if2_reg
.stall(stall_if1_if2)
```

**Jump address MUX (zicsr ưu tiên):**
```sv
// Nếu zicsr_flush, PC nhảy về zicsr_pc; nếu không thì đến branch/jump target
wire [31:0] jump_addr = zicsr_flush ? zicsr_pc : addr_adder_out;
```

**AHB IRQ path:**
```sv
// ahb_sfr[0].irq → (2-FF sync bên trong zicsr) → xử lý
.ahb_irq(ahb_sfr0_irq)
```

**CSR stall ports:**
```sv
// hazard_unit cần biết wb_sel tại EX/MEM1/MEM2 để detect CSR-use
.ex_wb_sel(idex_wb_sel),   .mem1_wb_sel(exmem1_wb_sel), .mem2_wb_sel(mem1mem2_wb_sel)
```

---

## 12. Luồng Hoạt Động Hệ Thống

### 12.1 Thực Thi Lệnh Bình Thường (Không Hazard)

```
Cycle   Stage      Action
  1     IF1        PC=0x0000_0000, output PC đến IMEM
  2     IF2        IMEM trả instr[0], lưu vào if2_id_reg
  3     ID         decode instr[0], đọc rf[rs1], rf[rs2]
  4     EX         ALU tính, branch_comp đánh giá
  5     MEM1       decode address, phát bus signals
  6     MEM2       thu kết quả (DMEM/bus)
  7     WB         ghi kết quả vào register file
```

Mỗi cycle, 7 lệnh khác nhau đang ở 7 tầng đồng thời (pipeline đầy) → throughput lý tưởng = 1 lệnh/cycle.

### 12.2 Load-Use Hazard (LW + Lệnh Kế)

```
Cycle   IF1     IF2     ID      EX      MEM1    MEM2    WB
  N     I3      I2      I1      LW      ...     ...     ...
  N+1   I4      I3      I2      USE     LW(bub) ...     ...
                         ↑stall   ↑stall
  N+2   I4      I3      I2      USE     LW      ...     ...   <- stall 1 cycle
                                  ↑bubble↑
  N+3   I5      I4      I3      USE     BUBBLE  LW      ...   <- LW có data ở MEM2
                                                 ↑forward
```

Stall: IF1, IF2, ID bị giữ 1 cycle. EX nhận bubble (NOP). USE đọc kết quả LW qua MEM2 forwarding.

### 12.3 Truy Cập AXI Bus (LW/SW tới 0x2000_xxxx)

Ví dụ: `lw t0, 0(a0)` với `a0 = 0x2000_0000`

```
Cycle   MEM1 Stage                          AXI FSM
  N     addr decode → AXI path             IDLE → phát ARADDR, ARVALID=1
        bus_stall_req=1                    
  N+1   Pipeline stall (toàn bộ)           ARREADY=1 (handshake) → chờ RVALID
  N+2   Pipeline stall                      RVALID=1 → latch RDATA
  N+3   Pipeline stall                      RREADY=1 → gửi resp_valid, rdata
  N+4   bus_stall_req=0                    IDLE
        lw tiến sang MEM2 với rdata
```

Tổng ~4 cycle stall cho read AXI. Write AXI: ~4-6 cycle (AW+W phase + B response).

### 12.4 Truy Cập AHB Bus (LW/SW tới 0x3000_xxxx)

AHB thêm độ trễ do CDC (Async FIFO):

```
Phase 1 (1GHz): MEM1 ghi vào Request FIFO
Phase 2 (CDC): Gray code sync từ 1GHz → 500MHz (2 clk_ahb cycles)
Phase 3 (500MHz): AHB FSM đọc FIFO, thực thi AHB transaction (2-3 clk_ahb cycles)
Phase 4 (CDC): Gray code sync từ 500MHz → 1GHz (2 clk_cpu cycles)
Phase 5 (1GHz): MEM1 đọc Response FIFO, giải phóng bus_stall
```

Tổng: ~6-12 cycle (do tần số AHB thấp hơn 2× và CDC latency).

### 12.5 Xử Lý Ngắt MEI (Machine External Interrupt)

```
1. CPU ghi REG7[0]=1 vào AXI SFR → axi_irq=1
2. Trong zicsr: mip[11]=1 (MEIP)
3. Khi mstatus.MIE=1 và mie[11]=1: trap được kích hoạt
4. Điều kiện: ~bus_stall_req (không trap giữa bus transaction)
5. zicsr_flush=1: flush toàn pipeline
6. mepc ← PC của lệnh tiếp theo (interrupted, not faulted)
7. mcause ← 0x8000_000B (MEI)
8. mstatus.MPIE ← MIE; mstatus.MIE ← 0
9. PC ← mtvec_base + 4×11 = mtvec_base + 44
10. Thực thi ISR
11. Ghi REG7[0]=0 để clear IRQ
12. MRET: PC←mepc, MIE←MPIE
```

### 12.6 Xử Lý Ngắt AHB (2-FF Sync Latency)

AHB IRQ từ `ahb_sfr.irq` (500MHz) cần được đồng bộ về 1GHz trước khi Zicsr có thể xử lý. 2-FF synchronizer thêm 2 clk_cpu cycles. Để đảm bảo IRQ đã active khi kiểm tra, chương trình phải có ít nhất 5 NOP sau lệnh ghi REG7[0]=1:

```asm
sw   t1, 0x1c(a0)    # REG7[0]=1 → ahb_sfr.irq=1 (500MHz)
nop                  # CDC transit (2 clk_ahb ≈ 4 clk_cpu)
nop
nop
nop
nop                  # 2-FF sync trong zicsr (2 clk_cpu)
# Interrupt arrives here
```

### 12.7 Xử Lý Ngoại Lệ

Ngoại lệ (exception) phát sinh từ lệnh cụ thể và được phát hiện ở các tầng khác nhau:

| Ngoại lệ | Phát hiện tại | Báo cáo tại |
|-----------|---------------|-------------|
| Illegal Instruction | ID (id_decoder) | WB (zicsr) |
| ECALL | ID (id_decoder) | WB (zicsr) |
| EBREAK | ID (id_decoder) | WB (zicsr) |
| Load Access Fault | MEM1 (address decode) | WB (mem1_mem2→mem2_wb→zicsr) |
| Store Access Fault | MEM1 (address decode) | WB (mem1_mem2→mem2_wb→zicsr) |
| Bus Error (BRESP/HRESP≠OK) | MEM1/MEM2 | WB (thông qua resp pipeline) |

**Precise exception:** Khi lệnh đến WB với fault flag, zicsr flush toàn pipeline (vì lệnh đó là lệnh gây lỗi, các lệnh sau trong pipeline là sau lệnh lỗi nên phải bị cancel).

---

## 13. Phủ Sóng Hazard Pipeline

### 13.1 Bảng Tổng Kết Hazard

| Hazard | Điều kiện | Cơ chế | Penalty |
|--------|-----------|--------|---------|
| **Gap-1 RAW** | Lệnh N ghi rd; Lệnh N+1 đọc rd | MEM1 forwarding | 0 cycle |
| **Gap-2 RAW** | Lệnh N ghi rd; Lệnh N+2 đọc rd | MEM2 forwarding | 0 cycle |
| **Gap-3 RAW** | Lệnh N ghi rd; Lệnh N+3 đọc rd | WB forwarding | 0 cycle |
| **Gap-4 RAW** | Lệnh N ghi rd; Lệnh N+4 đọc rd | WBR bypass trong register_file | 0 cycle |
| **Load-Use** | LW ở EX; lệnh kế đọc rd của LW | Stall 1 cycle; MEM2 fwd | 1 cycle |
| **CSR-Use (EX)** | CSR ở EX; kế đọc rd | Stall 3 cycles | 3 cycles |
| **CSR-Use (MEM1)** | CSR ở MEM1; kế đọc rd | Stall 2 cycles | 2 cycles |
| **CSR-Use (MEM2)** | CSR ở MEM2; kế đọc rd | Stall 1 cycle | 1 cycle |
| **Branch Taken** | Branch resolve ở EX | Flush IF1/IF2, IF2/ID | 2 cycles |
| **JAL/JALR** | Jump resolve ở EX | Flush IF1/IF2, IF2/ID | 2 cycles |
| **Bus Stall (AXI)** | AXI transaction | Stall toàn pipeline | ~4-6 cycles |
| **Bus Stall (AHB)** | AHB transaction + CDC | Stall toàn pipeline | ~6-12 cycles |
| **Trap/Exception** | zicsr_flush=1 | Flush toàn pipeline | 5+ cycles |

### 13.2 Phủ Sóng Forwarding

```
Pipeline position when instruction uses result:

    IF1  IF2  ID  EX  MEM1  MEM2  WB
     N   N-1  N-2  N-3  N-4  N-5  N-6   ← current instruction positions

When instruction at EX reads rs1:
  MEM1 (N-4) has result → fwd_sel = 2'b01  [gap-1 from producer's EX]
  MEM2 (N-5) has result → fwd_sel = 2'b10  [gap-2]
  WB   (N-6) has result → fwd_sel = 2'b11  [gap-3]
  RF          (updated) → fwd_sel = 2'b00  [gap-4+ via WBR bypass]
```

---

## Phụ Lục A — Quy Tắc Coding SystemVerilog

1. **Không dùng package.** Mọi `localparam` khai báo trực tiếp trong module.

2. **Không dùng bit/part-select trong `always_*`** (Icarus báo lỗi). Phải tách ra `assign`:
   ```sv
   logic [1:0] instr_13_12;
   assign instr_13_12 = instr[13:12];
   always_comb begin
       case (instr_13_12) ...  // OK
   end
   ```

3. **Reset: async assert, sync deassert:**
   ```sv
   always_ff @(posedge clk or negedge rst_n) begin
       if (!rst_n) begin ... end  // async assert
       else        begin ... end  // sync deassert
   end
   ```

4. **Chỉ synthesizable constructs.** Không dùng OOP, `$display` trong RTL.

5. **Thanh ghi pipeline — ưu tiên flush > stall:**
   ```sv
   always_ff @(posedge clk or negedge rst_n) begin
       if (!rst_n)       begin /* reset */ end
       else if (flush)   begin /* NOP bubble */ end
       else if (!stall)  begin /* capture */ end
       // stall: giữ nguyên
   end
   ```

---

## Phụ Lục B — Tham Số Cấu Hình

| Module | Parameter | Giá trị | Mô tả |
|--------|-----------|---------|-------|
| `imem` | `SIZE_KB` | 64 | Kích thước IMEM |
| `dmem` | `SIZE_KB` | 64 | Kích thước DMEM |
| `async_fifo_depth2` | `DATA_WIDTH` | 67 (req) / 33 (resp) | Độ rộng FIFO |
| `if1_stage` | `RESET_PC` | 32'h0 | Địa chỉ reset |
| `axi_sfr` | — | — | 8 × 32-bit regs |
| `ahb_sfr` | — | — | 8 × 32-bit regs |

---

*Tài liệu này là phiên bản 1.0 — kết hợp với các file bổ sung: block diagrams (DIAGRAM.md), quá trình test (TESTPLAN.md), và toolchain (TOOLCHAIN_AND_COMPLIANCE.md).*
