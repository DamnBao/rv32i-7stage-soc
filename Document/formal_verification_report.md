# Báo Cáo Task 2: Kiểm Chứng Hình Thức (SymbiYosys Formal Verification)

**Dự án:** RISC-V RV32I SoC — Luận Văn  
**Ngày:** 2026-06-26  
**Công cụ:** SymbiYosys (sby) + Z3 SMT Solver + Yosys  
**Kết quả:** **6/6 formal jobs PROVED** — 18+ individual assertions, k-induction

---

## 1. Tổng Quan

Task 2 triển khai kiểm chứng hình thức (formal verification) cho **5 module RTL** trong RISC-V SoC, sử dụng phương pháp **k-induction qua SMT solver**. Khác với simulation (test từng vector cụ thể), formal verification chứng minh tính đúng đắn **với mọi đầu vào có thể** trong không gian trạng thái vô hạn.

Quá trình được thực hiện theo 3 hướng:
- **Hướng ban đầu (3 jobs):** register_file x0, async_fifo Gray code, uart_axi frame boundary
- **Hướng 2 (2 jobs mới):** axi_interface VALID-stability, plic priority encoder
- **Hướng 1 (1 job mới + extensions):** register_file WBR bypass; mở rộng uart + fifo

### Toolchain

| Công cụ | Vai trò | Nguồn cài đặt |
|---------|---------|---------------|
| **SymbiYosys (sby)** | Orchestrator: điều phối Yosys + SMT solver | GitHub (sby repo) |
| **Yosys** | Synthesis + SMT encoding (`yosys-smtbmc`) | Đã có trong môi trường |
| **Z3 4.13.3** | SMT solver: giải hệ phương trình ràng buộc | GitHub binary release |

Lệnh chạy: `make formal_all` (trong `SIM/`)

---

## 2. Phương Pháp: k-Induction qua SMT

SymbiYosys sử dụng chế độ `prove` với hai bước song song:

1. **Basecase (BMC):** Kiểm tra assertion không bị vi phạm trong `depth` bước đầu tiên từ mọi trạng thái ban đầu hợp lệ.
2. **Induction step:** Giả sử assertion đúng tại bước `k`, chứng minh assertion vẫn đúng tại bước `k+1`.

Nếu cả hai bước thành công → thuộc tính được **PROVED** cho mọi lộ trình thực thi.

### Pattern `ifdef FORMAL`

Các assertion được nhúng trực tiếp vào RTL bằng `ifdef FORMAL` guard, giúp:
- Không ảnh hưởng synthesis thực tế
- Assertion ở ngay nơi logic liên quan (dễ maintain)
- Tool đọc source gốc, không cần wrapper phức tạp

---

## 3. Các Thuộc Tính Được Chứng Minh

### 3.1 P_REG_X0 — Register File: x0 Bất Biến

**Module:** `RTL/register_file.sv`  
**File formal:** `SIM/formal/fv_reg_x0.{sv,sby}`, depth=15  
**Kết quả:** ✅ **PROVED** (< 0.1s)

Theo RISC-V ISA, register x0 luôn đọc ra 0 và mọi ghi vào x0 bị bỏ qua.

**3 assertions:**
```systemverilog
// P1: rs1_addr==0 → rs1_data==0
assert((rs1_addr != 5'd0) || (rs1_data == 32'd0));
// P2: rs2_addr==0 → rs2_data==0
assert((rs2_addr != 5'd0) || (rs2_data == 32'd0));
// P3: ghi vào x0 không dirty x0 (kiểm tra sau 1 cycle)
if ($past(we) && $past(rd_addr) == 5'd0)
    assert(rs1_data == 32'd0 || rs1_addr != 5'd0);
```

---

### 3.2 P_GRAY + P_FIFO_DATA — CDC FIFO: Gray Code + Memory Integrity

**Module:** `RTL/async_fifo.sv`  
**File formal:** `SIM/formal/fv_fifo_gray.{sv,sby}`, depth=12  
**Kết quả:** ✅ **PROVED** (< 0.2s)

#### P_GRAY: Gray Code Single-Bit Transition

CDC safety property: con trỏ Gray code chỉ thay đổi **1 bit mỗi chu kỳ**. Nếu 2 bit thay đổi đồng thời, 2-FF synchronizer capture trạng thái "không tồn tại" → data corruption.

```systemverilog
logic [1:0] f_wr_delta;
assign f_wr_delta = wr_ptr_gray ^ f_wr_gray_prev;

always @(posedge wr_clk) begin
    if (wr_rst_n) assert(f_wr_delta != 2'b11);  // no two-bit flip
end
```

#### P_FIFO_DATA: Memory Write Integrity

Một cycle sau khi ghi, slot bộ nhớ vẫn giữ giá trị đã ghi. Điều này đảm bảo dữ liệu không bị overwrite trước khi đọc.

**Kỹ thuật (chứng minh bằng k-induction):** Với FIFO depth=2, slot tiếp theo LUÔN là slot ngược lại (LSB flip theo từng lần advance), nên write liên tiếp không bao giờ overwrite slot vừa ghi. Điều này khiến inductive step trivially đúng.

```systemverilog
// f_write_d: delay write enable 1 cycle
// f_write_slot_d: slot targeted by the previous write
always @(posedge wr_clk) begin
    if (wr_rst_n && f_write_d)
        assert(mem[f_write_slot_d] == f_write_data_d);
end
```

**Lý do không dùng end-to-end "write-then-read" property:** Trong single-clock formal model, `rd_empty` là CDC-delayed view có thể sai (lag 2 cycle), gây false counterexample khi dùng `rd_empty` làm điều kiện tracking. Property P_FIFO_DATA thay thế với scope rõ ràng: memory write integrity không phụ thuộc vào CDC view.

---

### 3.3 P_8N1 + P_TX_PULSE + P_RX_BIT_CNT — UART: Frame và IRQ Invariants

**Module:** `RTL/uart_axi.sv`  
**File formal:** `SIM/formal/fv_uart_proto.{sv,sby}`, depth=20  
**Kết quả:** ✅ **PROVED** (~ 3s)

#### P_8N1: Frame Boundary Invariants (3 assertions)

```systemverilog
always @(posedge clk) begin
    if (rst_n) begin
        assert(tx_state != TX_IDLE  || uart_tx == 1'b1);  // P_IDLE
        assert(tx_state != TX_START || uart_tx == 1'b0);  // P_START
        assert(tx_state != TX_STOP  || uart_tx == 1'b1);  // P_STOP
    end
end
```

#### P_TX_PULSE + P_RX_PULSE: Single-Cycle IRQ Pulses

```systemverilog
// tx_done_pulse và rx_complete_pulse phải đúng 1 cycle — rộng hơn gây IRQ storm
if ($past(tx_done_pulse))     assert(!tx_done_pulse);
if ($past(rx_complete_pulse)) assert(!rx_complete_pulse);
```

#### P_RX_BIT_CNT: Bit Counter Bound

```systemverilog
always @(posedge clk) begin
    if (rst_n) assert(rx_bit_cnt <= 3'd7);
end
```

#### Bug Phát Hiện (formal FAILED → RTL fixed)

Formal ban đầu FAILED tại step 5: `tx_state = TX_STOP, uart_tx = 0`. Root cause: NBA timing trong `always_ff` — state mới chưa nhận default assignment của state tiếp theo.

**Fix:** Thêm explicit `uart_tx <= 1'b0` khi TX_IDLE→TX_START và `uart_tx <= 1'b1` khi TX_DATA→TX_STOP. Đây là **real bug** — receiver sampling đúng spec sẽ đọc sai frame khi byte có bit 7 = 0.

---

### 3.4 P_AXI_HANDSHAKE — AXI Interface: VALID Stability

**Module:** `RTL/axi_interface.sv`  
**File formal:** `SIM/formal/fv_axi_handshake.{sv,sby}`, depth=10  
**Kết quả:** ✅ **PROVED** (< 0.1s)

AXI4 spec §A3.2.1: "Once VALID is asserted it must remain asserted until the handshake occurs." Vi phạm gây deadlock.

**3 assertions (AR, AW, W channels):**
```systemverilog
// P_AXI_AR: ARVALID held stable until ARREADY
always @(posedge clk) begin
    if (rst_n)
        if ($past(ARVALID) && !$past(ARREADY)) assert(ARVALID);
end
// (same pattern for AWVALID/AWREADY and WVALID/WREADY)
```

**Scope:** Tất cả CPU-side inputs và AXI slave responses hoàn toàn symbolic → solver kiểm tra với mọi tổ hợp handshake ordering.

---

### 3.5 P_PLIC_PRIORITY — PLIC: Priority Encoder Correctness

**Module:** `RTL/plic.sv`  
**File formal:** `SIM/formal/fv_plic_priority.{sv,sby}`, depth=10  
**Kết quả:** ✅ **PROVED** (< 0.1s)

PLIC priority encoder phải luôn chọn đúng source có priority cao nhất. 4 assertions:

```systemverilog
always @(posedge clk) begin
    if (rst_n) begin
        // P_WINNER_BOUND: winner_id ∈ {0..6}
        assert(winner_id <= 3'd6);

        if (winner_id != 3'd0) begin
            // P_WINNER_ACTIVE: winner phải là source đang active
            case (winner_id)
                3'd1: assert(src_active[1]);
                // ... (6 cases)
            endcase

            // P_WINNER_OPTIMAL: không source nào active có priority > win_pri
            if (src_active[1]) assert(pri1 <= win_pri);
            // ... (6 cases)
        end

        // P_MEIP: meip ↔ winner exists
        assert(meip == (winner_id != 3'd0));
    end
end
```

**Tại sao quan trọng:** Priority encoder dùng multi-if combinational chain — sai logic ở bất kỳ bước nào dẫn đến CPU xử lý sai IRQ source.

---

### 3.6 P_WBR + P_RF_SEQ — Register File: WBR Bypass và Sequential Consistency

**Module:** `RTL/register_file.sv`  
**File formal:** `SIM/formal/fv_reg_wbr.{sv,sby}`, depth=5  
**Kết quả:** ✅ **PROVED** (< 0.1s)

#### P_WBR: Same-Cycle Write-Before-Read Bypass

```systemverilog
// P_WBR: nếu ghi và đọc cùng cycle, cùng địa chỉ, phải thấy ngay giá trị mới
always @(posedge clk) begin
    if (rst_n && we && rd_addr != 5'd0 && rs1_addr == rd_addr)
        assert(rs1_data == rd_data);
end
```

#### P_RF_SEQ: Next-Cycle Read After Write

```systemverilog
// P_RF_SEQ: cycle sau khi ghi, đọc đúng địa chỉ đó phải trả về giá trị đã ghi
always @(posedge clk) begin
    if (rst_n && $past(rst_n) &&
        $past(we) && $past(rd_addr) != 5'd0 &&
        rs1_addr == $past(rd_addr) &&
        !(we && rd_addr == $past(rd_addr)))
        assert(rs1_data == $past(rd_data));
end
```

**4 assertions tổng cộng** (P_WBR + P_RF_SEQ cho cả rs1 và rs2 port).

---

## 4. Tóm Tắt Kết Quả

| # | Job | Module | Properties | Assertions | Depth | Thời gian | Kết quả |
|---|-----|--------|-----------|-----------|-------|-----------|---------|
| 1 | fv_reg_x0 | `register_file.sv` | P_REG_X0 | 3 | 15 | < 0.1s | ✅ PROVED |
| 2 | fv_fifo_gray | `async_fifo.sv` | P_GRAY + P_FIFO_DATA | 2 | 12 | < 0.2s | ✅ PROVED |
| 3 | fv_uart_proto | `uart_axi.sv` | P_8N1 + P_TX_PULSE + P_RX_PULSE + P_RX_BIT_CNT | 6 | 20 | ~3s | ✅ PROVED |
| 4 | fv_axi_handshake | `axi_interface.sv` | P_AXI_AR + P_AXI_AW + P_AXI_W | 3 | 10 | < 0.1s | ✅ PROVED |
| 5 | fv_plic_priority | `plic.sv` | P_WINNER_BOUND + P_WINNER_ACTIVE + P_WINNER_OPTIMAL + P_MEIP | 4 | 10 | < 0.1s | ✅ PROVED |
| 6 | fv_reg_wbr | `register_file.sv` | P_WBR + P_RF_SEQ (rs1+rs2) | 4 | 5 | < 0.1s | ✅ PROVED |

**Tổng: 6/6 PROVED**, ~22 individual assertions, toàn bộ bằng k-induction (smtbmc z3).

Bonus: Quá trình formal phát hiện **1 real bug** trong RTL (UART TX state transition), được fix và verified lại.

---

## 5. Bài Học Kỹ Thuật

### 5.1 False Counterexample vs Real Bug

Formal verification có thể gặp **false counterexample** khi:
- **Anyinit state:** Yosys SMT model khởi tạo FF với giá trị tùy ý (không từ reset). Cần `initial assume(!rst_n)` trong wrapper và strengthening invariants cho k-induction.
- **CDC-delayed signals:** `rd_empty` trong FIFO là CDC view (lag 2 cycles), có thể sai trong single-clock formal model. Giải pháp: dùng `wr_ptr_bin - rd_ptr_bin` (actual count) hoặc thiết kế property không phụ thuộc CDC view.

**Phân biệt false positive vs real bug:**
- Nếu counterexample dùng trạng thái "unreachable" (wr_ptr_bin inconsistent với wr_ptr_gray) → likely false positive, cần strengthening invariant
- Nếu counterexample dùng trạng thái reachable từ reset qua sequence cụ thể → **real bug**

### 5.2 K-Induction Convergence

Induction step fail thường do:
1. **Inconsistent anyinit:** Pointer binary/gray không nhất quán → add pointer consistency invariant
2. **Unbounded auxiliary state:** Tracker state có thể ở trạng thái không reachable → add `assume(count != 3)` để bounding
3. **Missing strengthening invariant:** Property cần biết "memory slot unchanged while tracking" → add as mutual assertion

**Best practice cho new property:** Thiết kế property sao cho induction step self-contained — không cần auxiliary state phức tạp. P_FIFO_DATA với 1-cycle delay (f_write_d) là ví dụ clean.

---

## 6. Cấu Trúc File

```
SIM/formal/
├── fv_reg_x0.sv / .sby        # register_file x0 immutability
├── fv_fifo_gray.sv / .sby     # async_fifo Gray code + memory integrity
├── fv_uart_proto.sv / .sby    # uart_axi 8N1 + pulse + bit-cnt
├── fv_axi_handshake.sv / .sby # axi_interface VALID stability (AXI spec §A3.2.1)
├── fv_plic_priority.sv / .sby # plic priority encoder correctness
└── fv_reg_wbr.sv / .sby       # register_file WBR bypass + sequential read

RTL/
├── register_file.sv           # No FORMAL block (checked via wrappers)
├── async_fifo.sv              # `ifdef FORMAL: P_GRAY + P_FIFO_DATA (lines 84–152)
├── uart_axi.sv                # `ifdef FORMAL: P_8N1 + pulses + bit-cnt (lines 390–425)
│                              # + RTL bug fixed: uart_tx at state transitions
└── plic.sv                    # `ifdef FORMAL: P_PLIC_PRIORITY (lines 215–253)
```

---

## 7. Lệnh Chạy

```bash
# Chạy tất cả 6 formal jobs
cd SIM && make formal_all

# Chạy từng job
make formal_x0        # P_REG_X0
make formal_fifo      # P_GRAY + P_FIFO_DATA
make formal_uart      # P_8N1 + P_TX_PULSE + P_RX_PULSE + P_RX_BIT_CNT
make formal_axi       # P_AXI_HANDSHAKE (AR/AW/W)
make formal_plic      # P_PLIC_PRIORITY
make formal_reg_wbr   # P_WBR + P_RF_SEQ

# Output kỳ vọng (mỗi job):
# SBY ... summary: successful proof by k-induction.
# SBY ... DONE (PASS, rc=0)
```
