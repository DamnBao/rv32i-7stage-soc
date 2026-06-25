# prog_csr_hazard.s — Kiểm tra CSR-use stall ở các khoảng cách gap 0..4
#
# Pipeline 7 tầng: CSR kết quả (old value) chỉ sẵn sàng tại WB.
# hazard_unit stall khi CSR@EX/MEM1/MEM2 và lệnh tiếp theo dùng rd.
#
# Mỗi nhóm: write giá trị biết trước vào CSR, csrr nó vào rx,
# dùng rx sau N NOP, verify kết quả đúng → stall hoạt động.
#
# Kết quả PASS: x31=1; FAIL: x31=0

.section .text
.global _start

_start:
    # --- Setup mtvec (catch any spurious exception) ---
    la    x1, fail
    csrw  mtvec, x1

    # =========================================================
    # Ghi giá trị biết trước vào mepc (CSR dễ đọc)
    # =========================================================
    li    x2, 0x12345670      # mepc[1:0] sẽ bị mask → 0x12345670
    csrw  mepc, x2

    # =========================================================
    # G1: Gap-0 — CSR đọc, dùng NGAY kết quả (3 stall cycles)
    # =========================================================
    csrr  x3, mepc            # x3 = old mepc = 0x12345670
    add   x4, x3, x0         # dùng x3 ngay (gap-0): hazard_unit stall 3 cycles
    li    x5, 0x12345670
    bne   x4, x5, fail

    # =========================================================
    # G2: Gap-1 — 1 NOP giữa (2 stall cycles)
    # =========================================================
    csrr  x6, mepc
    nop
    add   x7, x6, x0
    bne   x7, x5, fail

    # =========================================================
    # G3: Gap-2 — 2 NOP (1 stall cycle)
    # =========================================================
    csrr  x8, mepc
    nop
    nop
    add   x9, x8, x0
    bne   x9, x5, fail

    # =========================================================
    # G4: Gap-3 — 3 NOP (0 stall, WB forwarding)
    # =========================================================
    csrr  x10, mepc
    nop
    nop
    nop
    add   x11, x10, x0
    bne   x11, x5, fail

    # =========================================================
    # G5: Gap-4 — 4 NOP (0 stall, RF WBR bypass)
    # =========================================================
    csrr  x12, mepc
    nop
    nop
    nop
    nop
    add   x13, x12, x0
    bne   x13, x5, fail

    # =========================================================
    # G6: CSR-use với rd=x0 — TIDAK ADA STALL
    # Verify program vẫn chạy đúng thứ tự dù không stall
    # =========================================================
    csrw  mepc, x5            # rd=x0 → no stall
    add   x14, x5, x0        # x14 = 0x12345670 (không bị ảnh hưởng)
    bne   x14, x5, fail

    # =========================================================
    # G7: Đọc csr_rdata (giá trị CŨ) ngay sau CSRRW — old value
    # csrrw x15, mepc, x16: x15 = old_mepc TRƯỚC khi ghi
    # =========================================================
    li    x16, 0xABCDE000     # giá trị mới sẽ ghi vào mepc
    csrrw x15, mepc, x16      # x15=old_mepc(0x12345670), mepc=0xABCDE000
    add   x17, x15, x0       # gap-0 dùng x15 → stall
    bne   x17, x5, fail       # x17 phải = 0x12345670 (old value)

    # Verify mepc đã được cập nhật
    csrr  x18, mepc
    li    x19, 0xABCDE000
    bne   x18, x19, fail

    # =========================================================
    # G8: CSRRS — set bits, đọc kết quả mới ngay (gap-0 stall)
    # =========================================================
    li    x20, 0x00000008     # bit 3
    csrrs x21, mie, x20       # x21 = old mie (0), set MSIE
    nop                       # gap-1
    csrr  x22, mie
    add   x22, x22, x0       # gap-0 sau csrr
    bne   x22, x20, fail      # mie phải = 0x8

    # =========================================================
    # PASS
    # =========================================================
    li    x31, 1
    ebreak

fail:
    li    x31, 0
    ebreak
