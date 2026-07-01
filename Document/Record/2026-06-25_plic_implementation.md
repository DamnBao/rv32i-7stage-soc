# Change Log: PLIC Implementation (Platform-Level Interrupt Controller)

**Ngày:** 2026-06-25  
**Tác giả:** DamnBao  
**Trạng thái:** PLANNED — chưa bắt đầu

---

## Mục tiêu

Thay thế cơ chế OR-gate IRQ hiện tại bằng PLIC chuẩn RISC-V (SiFive spec, simplified).

**Vấn đề hiện tại:**
- 6 irq line từ peripheral bị OR lại → 1 bit MEIP trong `mip`
- CPU vào MEI handler không biết nguồn nào trigger
- Handler phải poll `INTR_STATE` của từng peripheral (6 LW instructions tối đa)
- Không có hardware priority

**Sau khi implement:**
- PLIC nhận 6 irq sources, so sánh priority, forward 1 winner lên CPU
- Handler: 1 LW (claim) → biết ID nguồn → dispatch → 1 SW (complete)
- Priority configurable qua register, threshold để mask IRQ tạm thời

---

## CDC: 2-FF Synchronizer cho AHB IRQ (BẮT BUỘC)

AHB peripherals chạy ở 500MHz, PLIC chạy ở 1GHz — crossing clock domain. Nếu AHB IRQ đi thẳng vào PLIC không qua sync sẽ gây **metastability**, logic PLIC có thể đọc sai giá trị.

**Giải pháp:** 3 bộ 2-FF synchronizer riêng biệt (1 bộ/source), đặt trong `soc_top.sv`, clocked by `clk_cpu` (1GHz):

```
ahb_S0_irq_i (500MHz) → [FF1 @ 1GHz] → [FF2 @ 1GHz] → ahb_irq0_sync → PLIC source 4
ahb_S1_irq_i (500MHz) → [FF1 @ 1GHz] → [FF2 @ 1GHz] → ahb_irq1_sync → PLIC source 5
ahb_S2_irq_i (500MHz) → [FF1 @ 1GHz] → [FF2 @ 1GHz] → ahb_irq2_sync → PLIC source 6
```

AXI IRQ (đã ở 1GHz) nối thẳng vào PLIC, không cần sync.

> **Lưu ý:** `zicsr.sv` hiện có 1 bộ 2-FF sync cho `ahb_irq_raw` (OR của 3 AHB IRQ).
> Khi refactor, bộ sync này sẽ bị **xóa** khỏi Zicsr, thay bằng 3 bộ sync riêng trong `soc_top`.
> Chi tiết implement ở Step 5a.

---

## Memory Map thêm mới

```
PLIC | 0x0C00_0000 – 0x0CFF_FFFF | 1GHz | Interrupt Controller (direct MMIO, no stall)
```

Decode: `addr[31:24] == 8'h0C`

**PLIC Register Layout (tại base 0x0C00_0000):**

| Offset | Tên | Access | Mô tả |
|--------|-----|--------|-------|
| `0x000004` | `PRIORITY[1]` | RW | Priority source 1 (axi_S0), 3-bit (0=disable) |
| `0x000008` | `PRIORITY[2]` | RW | Priority source 2 (axi_S1) |
| `0x00000C` | `PRIORITY[3]` | RW | Priority source 3 (axi_S2) |
| `0x000010` | `PRIORITY[4]` | RW | Priority source 4 (ahb_S0) |
| `0x000014` | `PRIORITY[5]` | RW | Priority source 5 (ahb_S1) |
| `0x000018` | `PRIORITY[6]` | RW | Priority source 6 (ahb_S2) |
| `0x001000` | `PENDING` | RO | bit[6:1] = pending flag mỗi source |
| `0x002000` | `ENABLE` | RW | bit[6:1] = enable mask mỗi source |
| `0x200000` | `THRESHOLD` | RW | Chỉ forward nếu priority > threshold (3-bit) |
| `0x200004` | `CLAIM` | RO | Đọc = ID source cao nhất đang pending (0=none) |
| `0x200004` | `COMPLETE` | WO | Ghi = complete source ID (PLIC clear pending) |

**Source ID mapping:**
- Source 1: `axi_S0_irq`
- Source 2: `axi_S1_irq`
- Source 3: `axi_S2_irq`
- Source 4: `ahb_S0_irq` (sau 2-FF sync)
- Source 5: `ahb_S1_irq` (sau 2-FF sync)
- Source 6: `ahb_S2_irq` (sau 2-FF sync)

**Tie-break:** source ID nhỏ hơn thắng khi priority bằng nhau.

---

## Danh sách Files thay đổi

| # | File | Loại | Mô tả thay đổi |
|---|------|------|----------------|
| 1 | `RTL/plic.sv` | NEW | PLIC module: 6 sources, 1 hart, 3-bit priority |
| 2 | `RTL/mem1_stage.sv` | MODIFY | Thêm `plic_sel` decode + PLIC access outputs + `mem_src=2'b11` |
| 3 | `RTL/mem2_stage.sv` | MODIFY | Thêm `plic_rdata` input + case `2'b11` trong data mux |
| 4 | `RTL/zicsr.sv` | MODIFY | Xóa `ahb_irq`/`axi_irq` inputs, thêm `meip_in`, xóa 2-FF sync nội bộ |
| 5 | `RTL/soc_top.sv` | MODIFY | Instantiate PLIC, thêm 3× 2-FF sync AHB IRQ, wire toàn bộ |
| 6 | `SIM/unit/tb_plic.sv` | NEW | Unit test PLIC: priority, claim, complete, threshold, tie-break |
| 7 | `SIM/programs/prog_plic_basic.s` | NEW | Program: setup PLIC, trigger IRQ via INTR_TEST, claim/complete |
| 8 | `SIM/system/tb_soc_top.sv` | MODIFY | Thêm prog_plic_basic vào batch (17 programs) |
| 9 | `SIM/Makefile` | MODIFY | Thêm `plic_unit`, cập nhật `system` target |
| 10 | `CLAUDE.md` | MODIFY | Cập nhật memory map, module list, trạng thái file, testing |

---

## Step-by-step thực hiện

> **Quy tắc:** Mỗi step: implement → verify (iverilog compile + run) → commit → step tiếp theo.

---

### STEP 1 — RTL: `plic.sv` (NEW)

**Implement:**

```
Ports:
  clk, rst_n
  irq_src[5:0]        — 6 nguồn IRQ đã sync về 1GHz
  re, we              — CPU access (synchronous)
  addr[23:0]          — địa chỉ bên trong PLIC (= cpu_addr[23:0])
  wdata[31:0]
  rdata[31:0]         — 1 cycle latency (latch ở clock edge giống DMEM)
  meip                — output → Zicsr

Internal registers:
  priority[6:1][2:0]  — 3-bit priority per source (0 = disabled)
  pending[6:1]        — set by irq_src edge, clear by complete write
  enable[6:1]
  threshold[2:0]
  claim_id[2:0]       — registered: winner source ID sau priority compare

Priority logic (combinational):
  active[i] = pending[i] & enable[i] & (priority[i] > threshold)
  winner = ID của active source có priority cao nhất
           tie-break: ID nhỏ hơn thắng

meip = (winner != 0)

Claim read:
  rdata = {29'd0, claim_id}  — claim_id cập nhật mỗi cycle

Complete write (addr==0x200004, we=1):
  pending[wdata[2:0]] <= 0
```

**Ràng buộc Icarus:**
- Mọi part-select `priority[i][2:0]`, `pending[6:1]` phải bóc tách bằng `assign` trước khi dùng trong `always_comb`
- Pending edge detect: dùng `irq_src_prev` FF để chỉ set pending khi rising edge

**Verify:**
```bash
iverilog -g2012 -o /tmp/plic_syn.vvp RTL/plic.sv && echo "OK"
```

**Commit:** `feat: add plic.sv — 6-source PLIC with priority encoder`

---

### STEP 2 — RTL: `mem1_stage.sv` (MODIFY)

**Thay đổi:**

1. Thêm decode cho PLIC:
```sv
logic [7:0] addr_31_24;
assign addr_31_24 = addr_in[31:24];
logic plic_sel;
assign plic_sel = (addr_31_24 == 8'h0C);
```

2. Cập nhật `fault_sel`:
```sv
assign fault_sel = ~dmem_sel & ~axi_sel & ~ahb_sel & ~plic_sel;
```

3. Thêm PLIC access outputs (không cần FSM — synchronous như DMEM):
```sv
output logic        plic_re,
output logic        plic_we,
output logic [23:0] plic_addr,
output logic [31:0] plic_wdata,

assign plic_re    = is_mem_access & plic_sel & mem_read_in;
assign plic_we    = is_mem_access & plic_sel & mem_write_in;
assign plic_addr  = addr_in[23:0];
assign plic_wdata = wdata_in;
```

4. Cập nhật `mem_src_out` (thêm case PLIC = 2'b11):
```sv
assign mem_src_out = dmem_sel  ? 2'b00 :
                     axi_sel   ? 2'b01 :
                     ahb_sel   ? 2'b10 : 2'b11; // 2'b11 = PLIC
```

**Verify:** Compile soc_top (sẽ fail ở bước này vì soc_top chưa cập nhật, OK — chỉ compile plic + mem1 riêng)
```bash
iverilog -g2012 -o /tmp/m1.vvp RTL/plic.sv RTL/mem1_stage.sv && echo "OK"
```

**Commit:** `feat: mem1_stage: add PLIC decode (0x0C000000, no stall)`

---

### STEP 3 — RTL: `mem2_stage.sv` (MODIFY)

**Thay đổi:**

1. Thêm input `plic_rdata`:
```sv
input  logic [31:0] plic_rdata,
```

2. Trong data select mux (thêm case 2'b11):
```sv
// Trong always_comb hoặc assign
2'b11: mem_rdata_out = plic_rdata_aligned;  // PLIC rdata (đã có 1-cycle latency từ mem1_stage)
```

**Commit:** `feat: mem2_stage: add PLIC rdata path (mem_src=2'b11)`

---

### STEP 4 — RTL: `zicsr.sv` (MODIFY)

**Thay đổi:**

1. Xóa `ahb_irq` input, xóa `axi_irq` input
2. Thêm `meip_in` input:
```sv
input  logic        meip_in,    // Từ PLIC (đã qua 2-FF sync, 1GHz domain)
```

3. Xóa toàn bộ block 2-FF sync (lines 70–78 hiện tại)

4. Thay dòng:
```sv
assign mip_meip = ahb_irq_sync | axi_irq;  // CŨ
```
bằng:
```sv
assign mip_meip = meip_in;  // MỚI
```

**Verify:**
```bash
iverilog -g2012 -o /tmp/zicsr.vvp RTL/zicsr.sv && echo "OK"
```

**Commit:** `refactor: zicsr: replace ahb_irq/axi_irq OR with meip_in from PLIC`

---

### STEP 5 — RTL: `soc_top.sv` (MODIFY)

Đây là step lớn nhất — nối tất cả lại.

**5a. Thêm 3× 2-FF sync cho AHB IRQs:**
```sv
logic ahb_irq0_ff1, ahb_irq0_sync;
logic ahb_irq1_ff1, ahb_irq1_sync;
logic ahb_irq2_ff1, ahb_irq2_sync;

always_ff @(posedge clk_cpu or negedge rst_cpu_n) begin
    if (!rst_cpu_n) begin
        ahb_irq0_ff1 <= 0; ahb_irq0_sync <= 0;
        ahb_irq1_ff1 <= 0; ahb_irq1_sync <= 0;
        ahb_irq2_ff1 <= 0; ahb_irq2_sync <= 0;
    end else begin
        ahb_irq0_ff1 <= ahb_irq0; ahb_irq0_sync <= ahb_irq0_ff1;
        ahb_irq1_ff1 <= ahb_irq1; ahb_irq1_sync <= ahb_irq1_ff1;
        ahb_irq2_ff1 <= ahb_irq2; ahb_irq2_sync <= ahb_irq2_ff1;
    end
end
```

> Lưu ý: `ahb_irq0/1/2` là các local signals từ ahb_interconnect (ahb_irq0, ahb_irq1, ahb_irq2 đã khai báo trong soc_top).

**5b. Instantiate PLIC:**
```sv
logic        plic_re, plic_we;
logic [23:0] plic_addr;
logic [31:0] plic_wdata, plic_rdata;
logic        plic_meip;

plic u_plic (
    .clk     (clk_cpu),
    .rst_n   (rst_cpu_n),
    .irq_src ({ahb_irq2_sync, ahb_irq1_sync, ahb_irq0_sync,
               axi_S2_irq,    axi_S1_irq,    axi_S0_irq}),  // [5:0]
    .re      (plic_re),
    .we      (plic_we),
    .addr    (plic_addr),
    .wdata   (plic_wdata),
    .rdata   (plic_rdata),
    .meip    (plic_meip)
);
```

**5c. Cập nhật mem1_stage instance** — thêm PLIC ports:
```sv
.plic_re    (plic_re),
.plic_we    (plic_we),
.plic_addr  (plic_addr),
.plic_wdata (plic_wdata),
```

**5d. Cập nhật mem2_stage instance** — thêm:
```sv
.plic_rdata (plic_rdata),
```

**5e. Cập nhật Zicsr instance** — xóa `ahb_irq`/`axi_irq`, thêm `meip_in`:
```sv
.meip_in  (plic_meip),   // MỚI
// .ahb_irq  (ahb_irq_raw),  // XÓA
// .axi_irq  (axi_irq),      // XÓA
```

**5f. Xóa các local wires không còn dùng:**
- `logic ahb_irq_raw, axi_irq;` — xóa
- (axi_irq trước đây được tạo bởi axi_interconnect; sẽ cần xóa hoặc để floating port đó)
- `axi_interconnect` port `.axi_irq(axi_irq)` → xóa luôn hoặc giữ nhưng không kết nối vào Zicsr

> **Chú ý:** `axi_interconnect` hiện có output port `.axi_irq(axi_irq)`. Port này sẽ không còn kết nối đến Zicsr. Để giữ RTL clean, có thể đơn giản kết nối sang plic_irq_src thay vì khai báo dây `axi_irq` riêng — hoặc giữ `axi_irq` local và đưa vào PLIC thay vì Zicsr.

**Verify:**
```bash
cd /home/baoslinux/riscv_soc_thesis/SIM
make system  # 16/16 PASS expected (các programs cũ không dùng PLIC trực tiếp)
```

**Commit:** `feat: soc_top: integrate PLIC — 6 sources, 3x AHB IRQ sync, meip wired`

---

### STEP 6 — SIM: `tb_plic.sv` (NEW UNIT TEST)

**Test cases (~25 cases):**

| TC | Mô tả |
|----|-------|
| TC01–06 | Reset: tất cả priority=0, pending=0, meip=0 |
| TC07 | Ghi priority[1]=3, enable[1]=1; raise irq_src[0] → meip=1, claim=1 |
| TC08 | Complete source 1 → pending[1]=0, meip=0 |
| TC09 | 2 source cùng raise: priority[2]=5 > priority[1]=3 → claim=2 |
| TC10 | Tie-break: priority[1]=3 = priority[3]=3 → claim=1 (ID nhỏ hơn) |
| TC11 | Threshold=4: priority[1]=3 < threshold → không forward |
| TC12 | Threshold=0: mọi enabled source đều forward |
| TC13 | Disable source (enable[i]=0): không forward dù priority cao |
| TC14 | Priority=0: source bị disable theo priority |
| TC15 | AHB source (irq_src[3]): raise → forward, complete → clear |
| TC16–20 | Tất cả 6 sources raise cùng lúc → claim trả đúng winner |
| TC21–25 | Sequential claim: sau complete, claim lần 2 trả winner tiếp theo |

**Verify:**
```bash
make plic_unit  # Thêm target vào Makefile
```

**Commit:** `test: add tb_plic unit test (25 cases)`

---

### STEP 7 — SIM: `prog_plic_basic.s` (NEW PROGRAM)

**Kịch bản:**
```asm
; 1. Setup PLIC
;    priority[1]=1 (axi_S0), priority[2]=5 (axi_S1), priority[3..6]=1
;    enable = 0b111110 (all 6 sources)
;    threshold = 0

; 2. Enable global IRQ (mstatus.MIE=1, mie.MEIE=1)

; 3. Trigger IRQ từ axi_S1 (source 2, priority=5) qua INTR_TEST
;    SW 1 → axi_S1.INTR_ENABLE = 1
;    SW 1 → axi_S1.INTR_TEST = 1

; 4. CPU trap vào MEI handler

; Handler:
;    LW  a0, PLIC_CLAIM      → a0 = 2  (source 2 = axi_S1)
;    Verify a0 == 2
;    SW  a0, PLIC_COMPLETE   → clear pending[2]
;    W1C axi_S1.INTR_STATE
;    mret

; 5. Sau mret: ghi result vào DMEM, ecall

; Pass condition: DMEM[0] = source_id = 2
```

**Verify:**
```bash
make prog_plic_basic  # Assemble
cd SIM && iverilog ... && vvp ...  # Chạy qua tb_pipeline_cpu hoặc tb_soc_top
```

**Commit:** `test: add prog_plic_basic — PLIC claim/complete via hardware priority`

---

### STEP 8 — SIM: Cập nhật `tb_soc_top.sv` + Makefile

**tb_soc_top.sv:** Thêm `prog_plic_basic` vào batch list (total 17 programs).

**Makefile:**
```makefile
# Thêm:
plic_unit:
	iverilog -g2012 -o unit/tb_plic.vvp \
		../RTL/plic.sv \
		unit/tb_plic.sv
	vvp unit/tb_plic.vvp

# Cập nhật system: source file list thêm plic.sv
```

**Verify:**
```bash
make system  # 17/17 PASS
make plic_unit  # 25/25 PASS
```

**Commit:** `test: system batch now includes prog_plic_basic (17/17); plic_unit target added`

---

### STEP 9 — Cập nhật tài liệu

**`CLAUDE.md`:**
- Memory map: thêm dòng PLIC `0x0C00_0000 – 0x0CFF_FFFF`
- Module list: thêm `plic.sv` vào nhóm CPU (hoặc nhóm riêng)
- Trạng thái file: thêm `plic.sv`, cập nhật `mem1_stage.sv`, `mem2_stage.sv`, `zicsr.sv`, `soc_top.sv`
- Testing: cập nhật Phase 7 (mới) với PLIC unit + system

**Verify cuối:** Chạy toàn bộ test suite
```bash
make p6_all    # 19/19 cũ vẫn pass
make plic_unit # 25/25 pass
make system    # 17/17 pass
```

**Commit:** `docs: update CLAUDE.md — PLIC integration complete`

---

## Rủi ro và Cẩn trọng

| Rủi ro | Cách xử lý |
|--------|-----------|
| `mem_src_out` 2-bit hiện tại đang được dùng ở nhiều chỗ | Đọc kỹ `mem2_stage.sv` và `mem1_mem2_reg.sv` trước khi thay đổi |
| `axi_interconnect` có output `axi_irq` → Zicsr đang dùng | Step 5: cẩn thận disconnect `axi_irq` khỏi Zicsr, kết nối qua PLIC thay vì OR |
| `ahb_irq_raw` đang được produce bởi `ahb_interconnect` | Giữ nguyên wire, nhưng đưa vào 3 sync riêng thay vì 1 sync |
| Pending edge-detect trong PLIC: nếu dùng level-sensitive có thể set pending liên tục | Dùng rising-edge detect (`irq & ~irq_prev`) để chỉ set 1 lần |
| Claim trả 0 khi không có source → handler phải check | Document rõ trong prog_plic_basic.s |

---

## Thứ tự dependency

```
Step 1 (plic.sv)
    ↓
Step 2 (mem1_stage) ── Step 3 (mem2_stage)
    ↓                       ↓
Step 4 (zicsr) ─────────────┘
    ↓
Step 5 (soc_top)    ← compile check tổng thể
    ↓
Step 6 (tb_plic)    ← unit test độc lập, có thể làm song song với Step 5
    ↓
Step 7 (prog_plic_basic.s)
    ↓
Step 8 (system batch)
    ↓
Step 9 (docs)
```

Steps 2, 3, 4 có thể làm song song (không phụ thuộc nhau).  
Step 5 phải sau 1, 2, 3, 4.  
Step 6 có thể làm song song với Step 5.

---

## Ước lượng số dòng RTL

| File | Ước lượng |
|------|----------|
| `plic.sv` | 200–230 dòng |
| `mem1_stage.sv` delta | +15 dòng |
| `mem2_stage.sv` delta | +5 dòng |
| `zicsr.sv` delta | −10 dòng (net xóa) |
| `soc_top.sv` delta | +30 dòng |
| `tb_plic.sv` | 200–250 dòng |
| `prog_plic_basic.s` | 60–80 dòng |

**Tổng RTL mới:** ~250 dòng — tương đương `async_fifo.sv`.
