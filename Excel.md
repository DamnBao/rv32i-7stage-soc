# Excel Tables — RISC-V RV32I SoC (Luận Văn)

Tài liệu này chứa toàn bộ dữ liệu để tạo file Excel cho dự án.
Mỗi section là một Sheet riêng trong Excel.

Cấu trúc: **DESIGN** (Sheet 1–9, bottom-up từ ISA đến chip boundary) → **VERIFICATION** (Sheet 10–17, theo thứ tự unit → system → compliance → formal).

---

## ═══ PHẦN DESIGN ═══

---

## Sheet 1: Instruction Encoding (RV32I + Zicsr)

| Mnemonic | Type | Opcode (bin) | funct3 | funct7  | Imm Type | alu_op (4-bit) | alu_src_a | alu_src_b | mem_read | mem_write | reg_write | wb_sel | branch | jump | csr_we |
|----------|------|--------------|--------|---------|----------|----------------|-----------|-----------|----------|-----------|-----------|--------|--------|------|--------|
| LUI      | U    | 0110111      | —      | —       | U        | 1010 (PASSB)   | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| AUIPC    | U    | 0010111      | —      | —       | U        | 0000 (ADD)     | 1 (PC)    | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| JAL      | J    | 1101111      | —      | —       | J        | —              | —         | —         | 0        | 0         | 1         | 10     | 0      | 1    | 0      |
| JALR     | I    | 1100111      | 000    | —       | I        | —              | —         | —         | 0        | 0         | 1         | 10     | 0      | 1    | 0      |
| BEQ      | B    | 1100011      | 000    | —       | B        | —              | —         | —         | 0        | 0         | 0         | —      | 1      | 0    | 0      |
| BNE      | B    | 1100011      | 001    | —       | B        | —              | —         | —         | 0        | 0         | 0         | —      | 1      | 0    | 0      |
| BLT      | B    | 1100011      | 100    | —       | B        | —              | —         | —         | 0        | 0         | 0         | —      | 1      | 0    | 0      |
| BGE      | B    | 1100011      | 101    | —       | B        | —              | —         | —         | 0        | 0         | 0         | —      | 1      | 0    | 0      |
| BLTU     | B    | 1100011      | 110    | —       | B        | —              | —         | —         | 0        | 0         | 0         | —      | 1      | 0    | 0      |
| BGEU     | B    | 1100011      | 111    | —       | B        | —              | —         | —         | 0        | 0         | 0         | —      | 1      | 0    | 0      |
| LB       | I    | 0000011      | 000    | —       | I        | 0000 (ADD)     | 0         | 1         | 1        | 0         | 1         | 01     | 0      | 0    | 0      |
| LH       | I    | 0000011      | 001    | —       | I        | 0000 (ADD)     | 0         | 1         | 1        | 0         | 1         | 01     | 0      | 0    | 0      |
| LW       | I    | 0000011      | 010    | —       | I        | 0000 (ADD)     | 0         | 1         | 1        | 0         | 1         | 01     | 0      | 0    | 0      |
| LBU      | I    | 0000011      | 100    | —       | I        | 0000 (ADD)     | 0         | 1         | 1        | 0         | 1         | 01     | 0      | 0    | 0      |
| LHU      | I    | 0000011      | 101    | —       | I        | 0000 (ADD)     | 0         | 1         | 1        | 0         | 1         | 01     | 0      | 0    | 0      |
| SB       | S    | 0100011      | 000    | —       | S        | 0000 (ADD)     | 0         | 1         | 0        | 1         | 0         | —      | 0      | 0    | 0      |
| SH       | S    | 0100011      | 001    | —       | S        | 0000 (ADD)     | 0         | 1         | 0        | 1         | 0         | —      | 0      | 0    | 0      |
| SW       | S    | 0100011      | 010    | —       | S        | 0000 (ADD)     | 0         | 1         | 0        | 1         | 0         | —      | 0      | 0    | 0      |
| ADDI     | I    | 0010011      | 000    | —       | I        | 0000 (ADD)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SLTI     | I    | 0010011      | 010    | —       | I        | 0011 (SLT)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SLTIU    | I    | 0010011      | 011    | —       | I        | 0100 (SLTU)    | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| XORI     | I    | 0010011      | 100    | —       | I        | 0101 (XOR)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| ORI      | I    | 0010011      | 110    | —       | I        | 1000 (OR)      | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| ANDI     | I    | 0010011      | 111    | —       | I        | 1001 (AND)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SLLI     | I    | 0010011      | 001    | 0000000 | I        | 0010 (SLL)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SRLI     | I    | 0010011      | 101    | 0000000 | I        | 0110 (SRL)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SRAI     | I    | 0010011      | 101    | 0100000 | I        | 0111 (SRA)     | 0         | 1         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| ADD      | R    | 0110011      | 000    | 0000000 | —        | 0000 (ADD)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SUB      | R    | 0110011      | 000    | 0100000 | —        | 0001 (SUB)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SLL      | R    | 0110011      | 001    | 0000000 | —        | 0010 (SLL)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SLT      | R    | 0110011      | 010    | 0000000 | —        | 0011 (SLT)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SLTU     | R    | 0110011      | 011    | 0000000 | —        | 0100 (SLTU)    | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| XOR      | R    | 0110011      | 100    | 0000000 | —        | 0101 (XOR)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SRL      | R    | 0110011      | 101    | 0000000 | —        | 0110 (SRL)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| SRA      | R    | 0110011      | 101    | 0100000 | —        | 0111 (SRA)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| OR       | R    | 0110011      | 110    | 0000000 | —        | 1000 (OR)      | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| AND      | R    | 0110011      | 111    | 0000000 | —        | 1001 (AND)     | 0         | 0         | 0        | 0         | 1         | 00     | 0      | 0    | 0      |
| FENCE    | I    | 0001111      | 000    | —       | —        | — (NOP)        | —         | —         | 0        | 0         | 0         | —      | 0      | 0    | 0      |
| ECALL    | I    | 1110011      | 000    | —       | —        | — (exception)  | —         | —         | 0        | 0         | 0         | —      | 0      | 0    | 0      |
| EBREAK   | I    | 1110011      | 000    | —       | —        | — (exception)  | —         | —         | 0        | 0         | 0         | —      | 0      | 0    | 0      |
| MRET     | I    | 1110011      | 000    | —       | —        | — (exception)  | —         | —         | 0        | 0         | 0         | —      | 0      | 0    | 0      |
| CSRRW    | I    | 1110011      | 001    | —       | —        | —              | —         | —         | 0        | 0         | 1         | 11     | 0      | 0    | 1      |
| CSRRS    | I    | 1110011      | 010    | —       | —        | —              | —         | —         | 0        | 0         | 1         | 11     | 0      | 0    | 1*     |
| CSRRC    | I    | 1110011      | 011    | —       | —        | —              | —         | —         | 0        | 0         | 1         | 11     | 0      | 0    | 1*     |
| CSRRWI   | I    | 1110011      | 101    | —       | Z (zimm) | —              | —         | —         | 0        | 0         | 1         | 11     | 0      | 0    | 1      |
| CSRRSI   | I    | 1110011      | 110    | —       | Z (zimm) | —              | —         | —         | 0        | 0         | 1         | 11     | 0      | 0    | 1*     |
| CSRRCI   | I    | 1110011      | 111    | —       | Z (zimm) | —              | —         | —         | 0        | 0         | 1         | 11     | 0      | 0    | 1*     |

*CSRRS/CSRRC: csr_we=0 nếu rs1==x0 (spec §9.1 — no side-effect)

**Ghi chú cột:**
- alu_op: ADD=0000, SUB=0001, SLL=0010, SLT=0011, SLTU=0100, XOR=0101, SRL=0110, SRA=0111, OR=1000, AND=1001, PASSB=1010
- alu_src_a: 0=rs1, 1=PC
- alu_src_b: 0=rs2, 1=imm
- wb_sel: 00=ALU result, 01=MEM rdata, 10=PC+4, 11=CSR rdata

---

## Sheet 2: Pipeline Stage

| Tầng | Tên       | Module chính         | Chức năng                                                      | Latency   |
|------|-----------|----------------------|----------------------------------------------------------------|-----------|
| 1    | IF1       | if1_stage            | Tính PC tiếp theo; tra cứu BHT+BTB (branch predictor)        | 1 cycle   |
| 2    | IF2       | if2_stage + imem     | IMEM trả lệnh; hội tụ PC; pass-through bp_taken/bp_target    | 1 cycle   |
| 3    | ID        | id_decoder + reg_file| Giải mã lệnh; đọc register file; tạo immediate               | 1 cycle   |
| 4    | EX        | ex_stage             | ALU + Branch Comparator + Addr Adder; Forwarding Unit; bp_mismatch detect | 1 cycle |
| 5    | MEM1      | mem1_stage           | Address decode; phát yêu cầu bus; stall nếu AXI/AHB         | 1+ cycle  |
| 6    | MEM2      | mem2_stage           | Nhận kết quả bus/DMEM/PLIC; detect load/store fault          | 1 cycle   |
| 7    | WB        | wb_stage             | Ghi kết quả vào register file                                 | 1 cycle   |

**Pipeline Registers:**

| Register      | Từ tầng | Đến tầng | Có flush? | Có stall? | Ghi chú |
|--------------|---------|----------|-----------|-----------|---------|
| if1_if2_reg  | IF1     | IF2      | Có        | Có        | Giữ bp_taken, bp_target |
| if2_id_reg   | IF2     | ID       | Có        | Có        | Giữ bp_taken, bp_target |
| id_ex_reg    | ID      | EX       | Có        | Có        | Bubble khi load-use/CSR hazard |
| ex_mem1_reg  | EX      | MEM1     | Có        | Có        | |
| mem1_mem2_reg| MEM1    | MEM2     | Có        | Có        | mem_src, precise exception |
| mem2_wb_reg  | MEM2    | WB       | Có        | Có        | |

---

## Sheet 3: Hazard Coverage

| Loại Hazard         | Ví dụ điển hình                | Cơ chế giải quyết                             | Cycles stall    | Module phụ trách         |
|---------------------|-------------------------------|------------------------------------------------|-----------------|--------------------------|
| Gap-1 RAW           | ADD x1,x2,x3 → ADD x4,x1,x5  | MEM1 forwarding (ex_mem1_reg.rd → EX input)   | 0               | forwarding_unit          |
| Gap-2 RAW           | ADD x1,... → NOP → ADD x4,x1  | MEM2 forwarding (mem1_mem2_reg.rd → EX input) | 0               | forwarding_unit          |
| Gap-3 RAW           | ADD x1,... → NOP,NOP → ADD    | WB forwarding (mem2_wb_reg.rd → EX input)     | 0               | forwarding_unit          |
| Gap-4 RAW           | ADD x1,... → 3 NOPs → ADD     | WBR bypass trong register_file                | 0               | register_file            |
| Load-use            | LW x1,0(x2) → ADD x3,x1,x4   | Stall IF1..ID 1 cycle, bubble EX              | 1               | hazard_unit              |
| CSR-use (gap-0)     | CSRRW x1,... → USE x1         | Stall 3 cycles (CSR at EX)                   | 3               | hazard_unit              |
| CSR-use (gap-1)     | CSRRW x1,... → NOP → USE x1   | Stall 2 cycles (CSR at MEM1)                 | 2               | hazard_unit              |
| CSR-use (gap-2)     | CSRRW x1,... → 2NOPs → USE x1 | Stall 1 cycle (CSR at MEM2)                  | 1               | hazard_unit              |
| Branch correct      | BEQ predicted taken, correct  | Không flush (0 penalty)                       | 0               | branch_predictor         |
| Branch mispredicted | BEQ predicted wrong           | Flush IF1/IF2 và IF2/ID (bp_mismatch=1)       | 2 slots flushed | hazard_unit + bp         |
| Bus stall (AXI)     | SW 0x20000000                 | Stall toàn pipeline đến BVALID/RVALID         | N (variable)    | mem1_stage + hazard_unit |
| Bus stall (AHB)     | SW 0x30000000                 | Stall toàn pipeline đến HREADYOUT             | N (variable)    | mem1_stage + hazard_unit |

---

## Sheet 4: CSR Register Map

| Địa chỉ CSR | Tên      | Access | Bit fields                                                                  | Reset value  | Mô tả |
|-------------|---------|--------|-----------------------------------------------------------------------------|--------------|-------|
| 0x300       | mstatus  | RW     | [3]=MIE (global interrupt enable), [7]=MPIE, [12:11]=MPP (luôn 11=M-mode) | 0x0000_1800  | Machine status |
| 0x304       | mie      | RW     | [3]=MSIE (SW irq enable), [7]=MTIE (timer irq enable), [11]=MEIE (ext irq enable) | 0x0000_0000 | Machine interrupt enable |
| 0x305       | mtvec    | RW     | [31:2]=BASE (trap vector base), [1:0]=MODE (0=Direct, 1=Vectored)          | 0x0000_0000  | Machine trap-handler base |
| 0x341       | mepc     | RW     | [31:2]=EPC, [1:0]=00 (IALIGN forced 0 for RV32)                            | 0x0000_0000  | Machine exception PC |
| 0x342       | mcause   | RW     | [31]=Interrupt flag, [30:0]=Exception/interrupt code                        | 0x0000_0000  | Machine cause |
| 0x344       | mip      | RW/RO  | [3]=MSIP (RW), [7]=MTIP (RO, hw-driven từ timer_axi), [11]=MEIP (RO, driven by PLIC) | 0x0000_0000  | Machine interrupt pending |

**mcause codes:**

| mcause[31] | mcause[30:0] | Nguồn |
|-----------|-------------|-------|
| 1         | 11          | Machine External Interrupt (PLIC → MEIP) |
| 1         | 7           | Machine Timer Interrupt (timer_axi → MTIP) |
| 0         | 2           | Illegal Instruction |
| 0         | 4           | Load Address Misaligned |
| 0         | 5           | Load Access Fault |
| 0         | 6           | Store/AMO Address Misaligned |
| 0         | 7           | Store/AMO Access Fault |
| 0         | 11          | ECALL from M-mode |

---

## Sheet 5: PLIC Register Map

| Offset (hex) | Tên         | Access | Width | Mô tả |
|-------------|-------------|--------|-------|-------|
| 0x000004    | PRIORITY_1  | RW     | 3-bit | Priority source 1 (0=masked) |
| 0x000008    | PRIORITY_2  | RW     | 3-bit | Priority source 2 |
| 0x00000C    | PRIORITY_3  | RW     | 3-bit | Priority source 3 |
| 0x000010    | PRIORITY_4  | RW     | 3-bit | Priority source 4 |
| 0x000014    | PRIORITY_5  | RW     | 3-bit | Priority source 5 |
| 0x000018    | PRIORITY_6  | RW     | 3-bit | Priority source 6 |
| 0x001000    | PENDING     | RO     | [6:1] | Pending flag mỗi source (rising-edge set) |
| 0x002000    | ENABLE      | RW     | [6:1] | Enable mask mỗi source |
| 0x200000    | THRESHOLD   | RW     | 3-bit | Chỉ forward nếu priority > threshold |
| 0x200004    | CLAIM       | RO     | 3-bit | Đọc = ID source đang thắng (claim) |
| 0x200004    | COMPLETE    | WO     | 3-bit | Ghi = source ID vừa xử lý xong (clear pending) |

**PLIC Source Mapping:**

| Source ID | Kết nối               | Bus        | Sync cần?             |
|-----------|-----------------------|------------|-----------------------|
| 1         | axi_S0_irq            | AXI-Lite   | Không (1 GHz đồng bộ) |
| 2         | axi_S1_irq (Timer)    | AXI-Lite   | Không (1 GHz đồng bộ) |
| 3         | axi_S2_irq (UART)     | AXI-Lite   | Không (1 GHz đồng bộ) |
| 4         | ahb_S0_irq (GPIO AHB) | AHB-Lite   | Có (irq_sync2ff 2-FF) |
| 5         | ahb_S1_irq            | AHB-Lite   | Có (irq_sync2ff 2-FF) |
| 6         | ahb_S2_irq            | AHB-Lite   | Có (irq_sync2ff 2-FF) |

---

## Sheet 6: SFR Standard Register Map

Dùng chung cho tất cả peripheral (AXI và AHB). Chuẩn tham chiếu: OpenTitan-inspired.

| Offset (hex) | Tên         | Access | Bit fields                                  | Mô tả |
|-------------|-------------|--------|---------------------------------------------|-------|
| 0x00        | CTRL        | RW     | [0]=enable; [31:1]=peripheral-specific      | Control register |
| 0x04        | STATUS      | RO     | Peripheral-specific (do peripheral drive)   | Status read-only |
| 0x08        | INTR_ENABLE | RW     | Bit mask từng nguồn IRQ                     | Interrupt enable |
| 0x0C        | INTR_STATE  | RW1C   | Pending flags; ghi 1 để clear               | Interrupt state |
| 0x10        | INTR_TEST   | WO     | Ghi 1 để force-set INTR_STATE (debug)       | Interrupt test |
| 0x14        | DATA0       | RW     | General-purpose (peripheral-specific)       | Data register 0 |
| 0x18        | DATA1       | RW     | General-purpose (peripheral-specific)       | Data register 1 |
| 0x1C        | DATA2       | RW     | General-purpose (peripheral-specific)       | Data register 2 |
| 0xFC        | PERIPH_ID   | RO     | Hardcoded identifier (4 ASCII bytes)        | Peripheral ID |

**IRQ rule:** `irq = |(INTR_STATE & INTR_ENABLE)`

**Address decode:** `AWADDR[7:2]` (AXI) hoặc `HADDR[7:2]` (AHB) — 6-bit word index.

---

## Sheet 7: Peripheral Summary

| Tên module   | Bus      | Địa chỉ cơ sở | PLIC src | PERIPH_ID | Chức năng chính |
|--------------|----------|---------------|----------|-----------|-----------------|
| gpio_sfr     | AXI-Lite | 0x2000_0000   | 1        | "GPIO"    | 32-bit GPIO out; gpio_in→STATUS; edge-detect IRQ |
| timer_axi    | AXI-Lite | 0x2000_1000   | 2        | "TIMR"    | Prescaler+compare IRQ; DATA0=prescaler, DATA1=compare, STATUS=counter |
| uart_axi     | AXI-Lite | 0x2000_2000   | 3        | "UART"    | 8N1 TX/RX; DATA0=baud_div; DATA1 write=TX; DATA2 read=RX; INTR_STATE[1]=rx,[0]=tx |
| gpio_ahb     | AHB-Lite | 0x3000_0000   | 4        | "GPIA"    | AHB GPIO; 2-FF sync; DATA0=out, DATA1[0]=OE, DATA2[0]=edge-type; edge-detect IRQ |
| ahb_sfr (S1) | AHB-Lite | 0x3000_1000   | 5        | param     | Generic AHB SFR slave |
| ahb_sfr (S2) | AHB-Lite | 0x3000_2000   | 6        | param     | Generic AHB SFR slave |

---

## Sheet 8: Memory Map

| Vùng nhớ    | Địa chỉ bắt đầu | Địa chỉ kết thúc | Kích thước | Clock domain | Stall CPU? | Ghi chú |
|-------------|-----------------|------------------|------------|--------------|------------|---------|
| IMEM        | 0x0000_0000     | 0x0000_FFFF      | 64 KB      | 1 GHz        | Không      | Instruction memory, sync 1-cycle |
| DMEM        | 0x0001_0000     | 0x0001_FFFF      | 64 KB      | 1 GHz        | Không      | Data memory, sync 1-cycle |
| PLIC        | 0x0C00_0000     | 0x0CFF_FFFF      | 16 MB      | 1 GHz        | Không      | 6 sources, 1-cycle latency |
| AXI-Lite S0 | 0x2000_0000     | 0x2000_0FFF      | 4 KB       | 1 GHz        | Có         | AXI FSM stall đến BVALID/RVALID |
| AXI-Lite S1 | 0x2000_1000     | 0x2000_1FFF      | 4 KB       | 1 GHz        | Có         | Timer AXI (timer_axi) |
| AXI-Lite S2 | 0x2000_2000     | 0x2000_2FFF      | 4 KB       | 1 GHz        | Có         | UART AXI (uart_axi) |
| AHB-Lite S0 | 0x3000_0000     | 0x3000_0FFF      | 4 KB       | 500 MHz      | Có         | GPIO AHB (gpio_ahb), qua CDC FIFO |
| AHB-Lite S1 | 0x3000_1000     | 0x3000_1FFF      | 4 KB       | 500 MHz      | Có         | AHB Slave 1, qua CDC FIFO |
| AHB-Lite S2 | 0x3000_2000     | 0x3000_2FFF      | 4 KB       | 500 MHz      | Có         | AHB Slave 2, qua CDC FIFO |

**Address decode tại MEM1 stage:**

| Điều kiện decode        | Vùng đích | mem_src | Stall |
|------------------------|-----------|---------|-------|
| addr[31:16] == 16'h0001 | DMEM      | 2'b00   | Không |
| addr[31:24] == 8'h0C    | PLIC      | 2'b11   | Không |
| addr[31:28] == 4'h2     | AXI-Lite  | 2'b01   | Có    |
| addr[31:28] == 4'h3     | AHB-Lite  | 2'b10   | Có    |
| Không khớp              | Exception | —       | —     |

---

## Sheet 9: soc_top Port List

| Tên port              | Direction | Width  | Clock domain | Mô tả |
|-----------------------|-----------|--------|--------------|-------|
| clk_cpu               | input     | 1-bit  | —            | 1 GHz — CPU + AXI domain |
| clk_ahb               | input     | 1-bit  | —            | 500 MHz — AHB peripheral domain |
| rst_n                 | input     | 1-bit  | —            | Async active-low reset |
| rst_cpu_n_o           | output    | 1-bit  | 1 GHz        | Sync reset output cho AXI peripherals |
| rst_ahb_n_o           | output    | 1-bit  | 500 MHz      | Sync reset output cho AHB peripherals |
| axi_S0_AWADDR         | output    | 32-bit | 1 GHz        | AXI S0 write address |
| axi_S0_AWPROT         | output    | 3-bit  | 1 GHz        | AXI S0 write protection |
| axi_S0_AWVALID        | output    | 1-bit  | 1 GHz        | AXI S0 write address valid |
| axi_S0_AWREADY        | input     | 1-bit  | 1 GHz        | AXI S0 write address ready |
| axi_S0_WDATA          | output    | 32-bit | 1 GHz        | AXI S0 write data |
| axi_S0_WSTRB          | output    | 4-bit  | 1 GHz        | AXI S0 write strobe |
| axi_S0_WVALID         | output    | 1-bit  | 1 GHz        | AXI S0 write data valid |
| axi_S0_WREADY         | input     | 1-bit  | 1 GHz        | AXI S0 write data ready |
| axi_S0_BRESP          | input     | 2-bit  | 1 GHz        | AXI S0 write response (00=OK, 10=SLVERR) |
| axi_S0_BVALID         | input     | 1-bit  | 1 GHz        | AXI S0 write response valid |
| axi_S0_BREADY         | output    | 1-bit  | 1 GHz        | AXI S0 write response ready |
| axi_S0_ARADDR         | output    | 32-bit | 1 GHz        | AXI S0 read address |
| axi_S0_ARPROT         | output    | 3-bit  | 1 GHz        | AXI S0 read protection |
| axi_S0_ARVALID        | output    | 1-bit  | 1 GHz        | AXI S0 read address valid |
| axi_S0_ARREADY        | input     | 1-bit  | 1 GHz        | AXI S0 read address ready |
| axi_S0_RDATA          | input     | 32-bit | 1 GHz        | AXI S0 read data |
| axi_S0_RRESP          | input     | 2-bit  | 1 GHz        | AXI S0 read response |
| axi_S0_RVALID         | input     | 1-bit  | 1 GHz        | AXI S0 read data valid |
| axi_S0_RREADY         | output    | 1-bit  | 1 GHz        | AXI S0 read ready |
| axi_S0_irq            | input     | 1-bit  | 1 GHz        | IRQ từ AXI S0 → PLIC src 1 |
| axi_S1_* (tương tự)   | —         | —      | 1 GHz        | AXI S1 (Timer) — cùng cấu trúc S0 |
| axi_S1_irq            | input     | 1-bit  | 1 GHz        | IRQ từ AXI S1 → PLIC src 2 |
| axi_S2_* (tương tự)   | —         | —      | 1 GHz        | AXI S2 (UART) — cùng cấu trúc S0 |
| axi_S2_irq            | input     | 1-bit  | 1 GHz        | IRQ từ AXI S2 → PLIC src 3 |
| ahb_HADDR_o           | output    | 32-bit | 500 MHz      | AHB shared bus address (broadcast) |
| ahb_HSIZE_o           | output    | 3-bit  | 500 MHz      | AHB transfer size |
| ahb_HTRANS_o          | output    | 2-bit  | 500 MHz      | AHB transfer type (00=IDLE, 10=NONSEQ) |
| ahb_HWRITE_o          | output    | 1-bit  | 500 MHz      | AHB write enable |
| ahb_HWDATA_o          | output    | 32-bit | 500 MHz      | AHB write data |
| ahb_S0_HSEL_o         | output    | 1-bit  | 500 MHz      | AHB S0 select |
| ahb_S0_HREADY_o       | output    | 1-bit  | 500 MHz      | AHB S0 ready (từ interconnect) |
| ahb_S0_HREADYOUT_i    | input     | 1-bit  | 500 MHz      | AHB S0 ready out (từ slave) |
| ahb_S0_HRDATA_i       | input     | 32-bit | 500 MHz      | AHB S0 read data |
| ahb_S0_HRESP_i        | input     | 1-bit  | 500 MHz      | AHB S0 response (0=OK, 1=ERROR) |
| ahb_S0_irq_i          | input     | 1-bit  | 500 MHz      | IRQ từ AHB S0 → irq_sync2ff → PLIC src 4 |
| ahb_S1_* (tương tự)   | —         | —      | 500 MHz      | AHB S1 → PLIC src 5 |
| ahb_S2_* (tương tự)   | —         | —      | 500 MHz      | AHB S2 → PLIC src 6 |

---

## ═══ PHẦN VERIFICATION ═══

---

## Sheet 10: Test Phase Summary

| Phase      | Testbench                          | Số testcase      | Kết quả  | Ghi chú |
|------------|------------------------------------|------------------|----------|---------|
| Phase 1    | tb_alu                             | 38               | PASS     | ALU 11 ops × corner cases (overflow, signed, shamt mask) |
| Phase 1    | tb_branch_comp                     | 25               | PASS     | 6 branch types × signed/unsigned corner cases |
| Phase 1    | tb_register_file                   | 17               | PASS     | Read/write, x0 immut, dual-port, we gate, reset |
| Phase 1    | tb_id_decoder                      | 107              | PASS     | 24 instructions × multi-field verify (mỗi chk*() = 1 testcase) |
| Phase 1    | **Tổng Phase 1**                   | **187**          | **PASS** | Verified từ source code (pass_cnt) |
| Phase 2    | tb_forwarding_unit                 | 19               | PASS     | MEM1>MEM2>WB priority; x0 invariant; simultaneous A+B |
| Phase 2    | tb_hazard_unit                     | 68               | PASS     | Load-use, CSR-use (EX/MEM1/MEM2), BP mismatch, bus stall, zicsr flush |
| Phase 2    | tb_async_fifo                      | 22               | PASS     | CDC Gray-code sync; pointer integrity; reset; multi-txn |
| Phase 2    | **Tổng Phase 2**                   | **109**          | **PASS** | Verified từ source code (pass_cnt) |
| Phase 7    | tb_plic                            | 31               | PASS     | PLIC unit: priority, threshold, claim/complete, multi-source |
| Phase 8    | tb_ex_stage                        | 23               | PASS     | EX stage: ALU op, forwarding path, branch/jump, CSR |
| Unit new   | tb_irq_sync2ff                     | 10               | PASS     | 2-FF synchronizer: metastability, multi-source |
| Unit new   | tb_gpio_sfr                        | 22               | PASS     | GPIO SFR: ctrl, data, irq edge-detect, INTR_TEST |
| Unit new   | tb_zicsr                           | 38               | PASS     | Zicsr: 6 CSR regs, exception entry/return, vectored mode |
| Branch pred| tb_branch_predictor                | 23               | PASS     | BHT/BTB cold/warm/hysteresis/tag/reset |
| Unit periph| tb_timer_axi                       | 23               | PASS     | Timer AXI: prescaler, compare-match IRQ, INTR_TEST |
| Unit periph| tb_gpio_ahb                        | 21               | PASS     | GPIO AHB: 2-FF sync, edge-detect, OE, AHB pipeline |
| Unit periph| tb_uart_axi                        | 27               | PASS     | UART AXI: TX/RX FSM, baud_div, 8N1 frame, dual IRQ |
| Phase 3    | tb_pipeline_cpu                    | 9                | PASS     | 9 programs qua soc_top; verdict = x31==1 tại EBREAK |
| Phase 4a   | tb_axi_interface                   | 49               | PASS     | AXI FSM, SLVERR |
| Phase 4b   | tb_ahb_interface                   | 29               | PASS     | AHB + CDC FIFO |
| Phase 4c   | tb_axi_full                        | 47               | PASS     | AXI + interconnect + 3×SFR |
| Phase 4d   | tb_ahb_full                        | 38               | PASS     | AHB + CDC + interconnect + 3×SFR |
| Phase 5    | tb_pipeline_cpu                    | 4                | PASS     | AXI/AHB SFR write/read + IRQ end-to-end via INTR_TEST → PLIC → MEI trap |
| integ_err  | tb_soc_bus_err                     | 2                | PASS     | AXI SLVERR→load/store fault |
| integ_err  | tb_soc_ahb_err                     | 2                | PASS     | AHB ERROR→load/store fault |
| Phase 6a   | tb_soc_top                         | 20               | PASS     | Batch runner 20 programs; verdict = x31==1 tại EBREAK |
| Phase 6b   | tb_compliance                      | 3                | PASS     | shifts, compare, dmem_endurance |
| Phase 7    | prog_plic_basic/priority/threshold | 3                | PASS     | PLIC system end-to-end |
| Phase 8    | prog_csr_hazard                    | 1                | PASS     | CSR-use stall gaps 0–4 |
| Periph sys | prog_timer / prog_gpio_ahb / prog_uart | 3            | PASS     | Timer IRQ, GPIO loopback+IRQ, UART loopback+dual IRQ |
| Branch pred| prog_branch_pred                   | 1                | PASS     | 1 program với 4 test patterns; verdict x31==1 |
| Metrics    | tb_metrics                         | 4 programs       | PASS     | IPC, stall, branch hit, AHB latency |
| **D2**     | **integ_misaligned** (prog_misaligned) | **1**        | **PASS** | Misaligned LH/LW/SH/SW → mcause 4/6; handler mepc+4; counter==4 |
| **D3**     | **integ_mtip** (prog_mtip)         | **1**            | **PASS** | MTIP path (mie[7]=MTIE only); mcause=0x8000_0007; mip[7] verified |
| Compliance | riscv-arch-test                    | 37 PASS + 1 SKIP | PASS     | jal-01 SKIP (~1.7MB > 64KB IMEM) |
| Formal     | formal_x0 / reg_wbr / stall / fifo / axi / plic / uart | 7 jobs | PROVED | SymbiYosys k-induction (smtbmc z3); original 7 infra jobs |
| **Formal D1** | **formal_alu / decoder / mem1_addr / axi_route / ahb_route** | **5 jobs** | **PROVED** | Datapath: ALU 12 props, decoder 8 props, mem1 addr 6 props, routing mutex |

---

## Sheet 11: Branch Predictor Metrics

Testbench: tb_metrics → prog_branch_pred (4 programs qua soc_top)

| Test | Chương trình            | Mô tả                      | Số branch events | Hit rate  | Ghi chú |
|------|------------------------|----------------------------|------------------|-----------|---------|
| T1   | Loop (backward branch) | Vòng lặp N lần, luôn taken | —                | 81.8%     | BHT warm sau vài lần đầu; 1 miss khi thoát loop |
| T2   | JAL indirect (BTB cold)| Nhiều target khác nhau     | —                | 16.7%     | BTB cold miss; indirect jump, tag mismatch |
| T3   | Nested branch          | 2 vòng lồng nhau           | —                | 68.4%     | Outer loop warm; inner loop có conflict |
| T4   | Alternating (adversarial)| T/N/T/N xen kẽ           | —                | 47.6%     | Worst case cho 2-bit BHT; xấp xỉ random |
| All  | **Overall**            | Tổng 57 branch events      | **57**           | **57.9%** | Workload đa dạng; predictor 16-entry 2-bit BHT + BTB |

**Branch predictor config:** 16-entry BHT (2-bit saturating counter) + BTB, lookup combinational tại IF1, update tại EX.

---

## Sheet 12: Performance Metrics

Testbench: tb_metrics (4 programs qua soc_top)

| Program           | Mô tả                               | CPI   | IPC   | Load-use stalls    | Branch miss penalty | AHB latency |
|------------------|-------------------------------------|-------|-------|--------------------|---------------------|-------------|
| prog_forwarding  | ALU-heavy, test forwarding paths    | 1.100 | 0.909 | 1 stall            | 0                   | 0           |
| prog_branch_pred | Mixed branch workload (57 branches) | —     | —     | —                  | 2 cycles/miss       | 0           |
| prog_ahb_sfr     | 10 AHB transactions                 | —     | —     | 0                  | 0                   | avg 9.4 cycles (min=9, max=10) |
| prog_fib         | Fibonacci recursive                 | 1.182 | 0.846 | 18 load-use stalls | 80% branch hit rate | 0           |

**Ghi chú:**
- CPI = Cycles Per Instruction; IPC = Instructions Per Cycle = 1/CPI
- Branch miss penalty = 2 pipeline slots flushed (IF1/IF2 + IF2/ID)
- AHB latency avg 9.4 CPU cycles/transaction (1 GHz CPU / 500 MHz AHB, round-trip qua CDC FIFO)

---

## Sheet 13: IRQ and Exception Coverage

| Nguồn / Sự kiện               | Loại      | mcause              | Test nào cover                                           | Kết quả |
|-------------------------------|-----------|---------------------|----------------------------------------------------------|---------|
| Machine External Interrupt     | Interrupt | 0x8000_000B (=11)   | prog_plic_basic, prog_timer, prog_gpio_ahb, prog_uart   | PASS    |
| **Machine Timer Interrupt (MTIP)** | **Interrupt** | **0x8000_0007 (=7)** | **prog_mtip** (mie[7]=MTIE; mtip_in từ timer_axi) | **PASS** |
| Illegal Instruction            | Exception | 2                   | tb_zicsr                                                 | PASS    |
| **Load Address Misaligned**   | **Exception** | **4**           | **prog_misaligned** (LH/LW tại địa chỉ lẻ/không căn)   | **PASS** |
| Load Access Fault (AXI SLVERR)| Exception | 5                   | tb_soc_bus_err                                           | PASS    |
| **Store Address Misaligned**  | **Exception** | **6**           | **prog_misaligned** (SH/SW tại địa chỉ lẻ/không căn)   | **PASS** |
| Store Access Fault (AXI SLVERR)| Exception | 7                   | tb_soc_bus_err                                           | PASS    |
| Load Access Fault (AHB ERROR) | Exception | 5                   | tb_soc_ahb_err                                           | PASS    |
| Store Access Fault (AHB ERROR)| Exception | 7                   | tb_soc_ahb_err                                           | PASS    |
| ECALL from M-mode             | Exception | 11                  | tb_zicsr, prog_csr_hazard                                | PASS    |
| MRET (trap return)            | System    | —                   | tb_zicsr, prog_plic_basic                                | PASS    |
| PLIC priority arbitration     | HW logic  | —                   | tb_plic (31 cases), formal_plic (P_PLIC_PRIORITY)       | PASS    |
| IRQ CDC (AHB 500MHz → 1GHz)  | CDC sync  | —                   | tb_irq_sync2ff (10 cases), prog_gpio_ahb                | PASS    |

---

## Sheet 14: Peripheral Test Coverage

| Peripheral | Testbench    | Feature được test                               | Kết quả    |
|-----------|--------------|-------------------------------------------------|------------|
| timer_axi | tb_timer_axi | Reset, enable/disable, prescaler                | 23/23 PASS |
| timer_axi | tb_timer_axi | Compare-match IRQ, INTR_STATE/ENABLE            | 23/23 PASS |
| timer_axi | tb_timer_axi | INTR_TEST force-set, PERIPH_ID read             | 23/23 PASS |
| timer_axi | prog_timer   | End-to-end: IRQ → PLIC → Zicsr → trap handler  | PASS       |
| gpio_ahb  | tb_gpio_ahb  | Reset, output enable, data write/read           | 21/21 PASS |
| gpio_ahb  | tb_gpio_ahb  | 2-FF sync input, edge-detect IRQ                | 21/21 PASS |
| gpio_ahb  | tb_gpio_ahb  | INTR_TEST, PERIPH_ID, AHB pipeline protocol     | 21/21 PASS |
| gpio_ahb  | prog_gpio_ahb| Loopback 0x55 + INTR_TEST IRQ via PLIC src 4   | PASS       |
| uart_axi  | tb_uart_axi  | TX FSM: idle→start→data→stop                    | 27/27 PASS |
| uart_axi  | tb_uart_axi  | RX FSM: start-detect→sample→done               | 27/27 PASS |
| uart_axi  | tb_uart_axi  | Baud divisor config (DATA0)                     | 27/27 PASS |
| uart_axi  | tb_uart_axi  | TX/RX IRQ, INTR_STATE, PERIPH_ID               | 27/27 PASS |
| uart_axi  | prog_uart    | TX/RX loopback 0x55 + dual IRQ via PLIC src 3  | PASS       |

---

## Sheet 15: RV32I Instruction Coverage

| Mnemonic | Category     | Compliance Test | Unit Test (tb_alu/branch_comp/id_decoder) | System Test (tb_soc_top/prog) | Kết quả |
|----------|--------------|-----------------|-------------------------------------------|-------------------------------|---------|
| ADD      | R-type ALU   | add-01          | tb_alu, tb_id_decoder                     | prog_basic_alu                | PASS    |
| SUB      | R-type ALU   | sub-01          | tb_alu, tb_id_decoder                     | prog_basic_alu                | PASS    |
| SLL      | R-type shift | sll-01          | tb_alu                                    | prog_rv32i_shifts             | PASS    |
| SLT      | R-type ALU   | slt-01          | tb_alu, tb_id_decoder                     | prog_rv32i_compare            | PASS    |
| SLTU     | R-type ALU   | sltu-01         | tb_alu, tb_id_decoder                     | prog_rv32i_compare            | PASS    |
| XOR      | R-type ALU   | xor-01          | tb_alu                                    | prog_basic_alu                | PASS    |
| SRL      | R-type shift | srl-01          | tb_alu                                    | prog_rv32i_shifts             | PASS    |
| SRA      | R-type shift | sra-01          | tb_alu                                    | prog_rv32i_shifts             | PASS    |
| OR       | R-type ALU   | or-01           | tb_alu                                    | prog_basic_alu                | PASS    |
| AND      | R-type ALU   | and-01          | tb_alu                                    | prog_basic_alu                | PASS    |
| ADDI     | I-type ALU   | addi-01         | tb_alu, tb_id_decoder                     | nhiều chương trình            | PASS    |
| SLTI     | I-type ALU   | slti-01         | tb_alu                                    | prog_rv32i_compare            | PASS    |
| SLTIU    | I-type ALU   | sltiu-01        | tb_alu                                    | prog_rv32i_compare            | PASS    |
| XORI     | I-type ALU   | xori-01         | tb_alu                                    | prog_basic_alu                | PASS    |
| ORI      | I-type ALU   | ori-01          | tb_alu                                    | prog_basic_alu                | PASS    |
| ANDI     | I-type ALU   | andi-01         | tb_alu                                    | prog_basic_alu                | PASS    |
| SLLI     | I-type shift | slli-01         | tb_alu                                    | prog_rv32i_shifts             | PASS    |
| SRLI     | I-type shift | srli-01         | tb_alu                                    | prog_rv32i_shifts             | PASS    |
| SRAI     | I-type shift | srai-01         | tb_alu                                    | prog_rv32i_shifts             | PASS    |
| LUI      | U-type       | lui-01          | tb_id_decoder                             | nhiều chương trình            | PASS    |
| AUIPC    | U-type       | auipc-01        | tb_id_decoder                             | prog_rv32i_compare            | PASS    |
| JAL      | J-type       | jal-01 (SKIP)   | tb_id_decoder                             | prog_branch_pred              | PASS*   |
| JALR     | I-type jump  | jalr-01         | tb_id_decoder                             | nhiều chương trình            | PASS    |
| BEQ      | B-type       | beq-01          | tb_branch_comp                            | nhiều chương trình            | PASS    |
| BNE      | B-type       | bne-01          | tb_branch_comp                            | nhiều chương trình            | PASS    |
| BLT      | B-type       | blt-01          | tb_branch_comp                            | prog_basic_branch             | PASS    |
| BGE      | B-type       | bge-01          | tb_branch_comp                            | prog_basic_branch             | PASS    |
| BLTU     | B-type       | bltu-01         | tb_branch_comp                            | prog_basic_branch             | PASS    |
| BGEU     | B-type       | bgeu-01         | tb_branch_comp                            | prog_basic_branch             | PASS    |
| LB       | Load         | lb-align-01     | tb_id_decoder                             | prog_dmem_endurance           | PASS    |
| LH       | Load         | lh-align-01     | tb_id_decoder                             | prog_dmem_endurance           | PASS    |
| LW       | Load         | lw-align-01     | tb_id_decoder                             | nhiều chương trình            | PASS    |
| LBU      | Load         | lbu-align-01    | tb_id_decoder                             | prog_dmem_endurance           | PASS    |
| LHU      | Load         | lhu-align-01    | tb_id_decoder                             | prog_dmem_endurance           | PASS    |
| SB       | Store        | sb-align-01     | tb_id_decoder                             | prog_dmem_endurance           | PASS    |
| SH       | Store        | sh-align-01     | tb_id_decoder                             | prog_dmem_endurance           | PASS    |
| SW       | Store        | sw-align-01     | tb_id_decoder                             | nhiều chương trình            | PASS    |
| FENCE    | System       | fence-01        | tb_id_decoder                             | (treated as NOP)              | PASS    |
| ECALL    | System       | —               | tb_zicsr                                  | prog_csr_hazard               | PASS    |
| MRET     | System       | —               | tb_zicsr                                  | prog_plic_basic               | PASS    |
| CSRRW    | Zicsr        | —               | tb_zicsr, tb_ex_stage                     | prog_csr_hazard               | PASS    |
| CSRRS    | Zicsr        | —               | tb_zicsr                                  | prog_plic_basic               | PASS    |
| CSRRC    | Zicsr        | —               | tb_zicsr                                  | prog_csr_hazard               | PASS    |
| CSRRWI   | Zicsr        | —               | tb_zicsr                                  | —                             | PASS    |
| CSRRSI   | Zicsr        | —               | tb_zicsr                                  | —                             | PASS    |
| CSRRCI   | Zicsr        | —               | tb_zicsr                                  | —                             | PASS    |

*jal-01: SKIP do test vector ~1.7MB vượt 64KB IMEM. JAL functionality verified via prog_branch_pred.

---

## Sheet 16: RV32I Compliance Test Results

Framework: riscv-arch-test v2.x (old framework), chạy qua tb_compliance_run.sv

| STT | Test name    | Category | Kết quả | Ghi chú |
|-----|-------------|----------|---------|---------|
| 1   | add-01      | R-type   | PASS    | |
| 2   | addi-01     | I-type   | PASS    | |
| 3   | and-01      | R-type   | PASS    | |
| 4   | andi-01     | I-type   | PASS    | |
| 5   | auipc-01    | U-type   | PASS    | |
| 6   | beq-01      | B-type   | PASS    | |
| 7   | bge-01      | B-type   | PASS    | |
| 8   | bgeu-01     | B-type   | PASS    | |
| 9   | blt-01      | B-type   | PASS    | |
| 10  | bltu-01     | B-type   | PASS    | |
| 11  | bne-01      | B-type   | PASS    | |
| 12  | fence-01    | System   | PASS    | Treated as NOP |
| 13  | jal-01      | J-type   | SKIP    | ~1.7MB > 64KB IMEM |
| 14  | jalr-01     | I-type   | PASS    | |
| 15  | lb-align-01 | Load     | PASS    | |
| 16  | lbu-align-01| Load     | PASS    | |
| 17  | lh-align-01 | Load     | PASS    | |
| 18  | lhu-align-01| Load     | PASS    | |
| 19  | lui-01      | U-type   | PASS    | |
| 20  | lw-align-01 | Load     | PASS    | |
| 21  | or-01       | R-type   | PASS    | |
| 22  | ori-01      | I-type   | PASS    | |
| 23  | sb-align-01 | Store    | PASS    | |
| 24  | sh-align-01 | Store    | PASS    | |
| 25  | sll-01      | R-type   | PASS    | |
| 26  | slli-01     | I-type   | PASS    | |
| 27  | slt-01      | R-type   | PASS    | |
| 28  | slti-01     | I-type   | PASS    | |
| 29  | sltiu-01    | I-type   | PASS    | |
| 30  | sltu-01     | R-type   | PASS    | |
| 31  | sra-01      | R-type   | PASS    | |
| 32  | srai-01     | I-type   | PASS    | |
| 33  | srl-01      | R-type   | PASS    | |
| 34  | srli-01     | I-type   | PASS    | |
| 35  | sub-01      | R-type   | PASS    | |
| 36  | sw-align-01 | Store    | PASS    | |
| 37  | xor-01      | R-type   | PASS    | |
| 38  | xori-01     | I-type   | PASS    | |

**Tổng:** 37 PASS / 1 SKIP / 0 FAIL

---

## Sheet 17: Formal Verification Properties

Tool: SymbiYosys k-induction (smtbmc backend, solver z3)

| Job name        | Module(s)                     | Property        | Loại assertion                                              | Depth k | Kết quả |
|----------------|------------------------------|-----------------|-------------------------------------------------------------|---------|---------|
| formal_x0      | register_file                 | P_REG_X0        | x0 luôn đọc ra 0 dù ghi gì                                 | 15      | PROVED  |
| formal_reg_wbr | register_file                 | P_WBR           | WBR bypass: đọc ngay sau ghi trả đúng giá trị mới          | 5       | PROVED  |
| formal_reg_wbr | register_file                 | P_RF_SEQ        | Ghi rồi đọc lại ra đúng giá trị                            | 5       | PROVED  |
| formal_stall   | hazard_unit + 3 pipeline regs | P_STALL_COHERENCE| Khi stall: IF1/IF2/ID registers giữ nguyên                | 8       | PROVED  |
| formal_stall   | hazard_unit + 3 pipeline regs | P_FLUSH         | Khi flush: pipeline registers cleared về NOP               | 8       | PROVED  |
| formal_fifo    | async_fifo                    | P_GRAY          | Gray-code pointer increment đúng 1 bit thay đổi            | 12      | PROVED  |
| formal_fifo    | async_fifo                    | P_FIFO_DATA     | Dữ liệu ra = dữ liệu vào đã push (FIFO integrity)         | 12      | PROVED  |
| formal_axi     | axi_interface                 | P_AXI_HANDSHAKE | AWVALID/WVALID/ARVALID stable sau khi assert (AXI §A3.2.1) | 10      | PROVED  |
| formal_plic    | plic                          | P_PLIC_PRIORITY | Winner luôn là source có priority cao nhất (tie: ID nhỏ hơn)| 10     | PROVED  |
| formal_uart    | uart_axi                      | P_8N1           | TX output đúng frame 8N1 (start+8bit+stop)                 | 20      | PROVED  |
| formal_uart    | uart_axi                      | P_TX_PULSE      | TX_DONE pulse đúng 1 cycle sau khi hoàn thành              | 20      | PROVED  |
| formal_uart    | uart_axi                      | P_RX_PULSE      | RX_DONE pulse đúng 1 cycle                                 | 20      | PROVED  |
| formal_uart    | uart_axi                      | P_RX_BIT_CNT    | Bit counter không vượt quá 8                               | 20      | PROVED  |
| **formal_alu** | **alu**                       | **P_ADD..P_PASSB** | **12 props: mỗi alu_op cho đúng kết quả với mọi 32-bit input** | **3** | **PROVED** |
| **formal_decoder** | **id_decoder**            | **P_MEM_MUTEX..P_UNKNOWN_SAFE** | **8 props: class decode, mem_read&write never both 1, unknown opcode safe** | **3** | **PROVED** |
| **formal_mem1_addr** | **mem1_stage**          | **P_BUS_MUTEX..P_FAULT_MUTEX** | **6 props: bus interfaces mutex, misaligned block, flags, byte always aligned** | **5** | **PROVED** |
| **formal_axi_route** | **axi_interconnect**    | **P_AW_MUTEX..P_AR_ROUTE_S2** | **6 props: AW/AR mutex, routing S0/S1/S2 đúng địa chỉ** | **5** | **PROVED** |
| **formal_ahb_route** | **ahb_interconnect**    | **P_AHB_HSEL_MUTEX..P_AHB_IDLE_NO_SEL** | **5 props: HSEL one-hot, routing đúng, no HSEL when IDLE** | **5** | **PROVED** |

**Ghi chú:** Phát hiện và sửa 1 RTL bug trong uart_axi (TX FSM) trong quá trình chạy formal.
**Ghi chú D1:** formal_mem1_addr trực tiếp xác nhận tính đúng đắn của misaligned detection (P_MISALIGN_BLOCK, P_MISALIGN_LOAD/STORE_FLAG) được thêm vào trong session này.

---

*File tạo tự động từ dữ liệu RTL + testbench của project RISC-V RV32I SoC.*
*Dùng file này để import vào Excel: mỗi section "## Sheet N" = 1 worksheet.*
