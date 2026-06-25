# prog_plic_threshold.s — Kiểm tra PLIC threshold filtering
#
# src_active[N] = pending[N] & enable[N] & (priority[N] > threshold)
# meip chỉ fire khi có ít nhất 1 src_active.
#
# Kịch bản:
#   Phase 0: priority[1]=1, priority[2]=2, threshold=2 → KHÔNG interrupt
#   Phase 1: threshold=1 → src2 (2>1) fires, claim=2
#   Phase 2: threshold=0 → src1 (1>0) fires, claim=1
#
# x29 = số lần handler đã chạy (bắt đầu = 0)
# x28 = phase hiện tại (bắt đầu = 0)

.section .text
.global _start

_start:
    # --- mtvec → plic_handler ---
    la    x1, plic_handler
    csrw  mtvec, x1

    # --- x29=0 (interrupt counter), x28=0 (phase) ---
    li    x29, 0
    li    x28, 0

    # --- PLIC registers ---
    lui   x5, 0x0C000          # 0x0C000000
    lui   x6, 0x0C002          # 0x0C002000
    lui   x7, 0x0C200          # 0x0C200000

    # priority[1]=1, priority[2]=2
    li    x8, 1
    sw    x8, 4(x5)
    li    x8, 2
    sw    x8, 8(x5)

    # enable bits [2:1] → write 6 = 0b110
    li    x8, 6
    sw    x8, 0(x6)

    # threshold = 2 (block both sources)
    li    x8, 2
    sw    x8, 0(x7)

    # Enable MEIE
    li    x8, 1
    slli  x8, x8, 11
    csrs  mie, x8

    # AXI SFR: enable interrupts and trigger both sources via INTR_TEST
    lui   x10, 0x20000
    lui   x11, 0x20001
    li    x12, 1
    sw    x12, 8(x10)          # S0 INTR_ENABLE = 1
    sw    x12, 8(x11)          # S1 INTR_ENABLE = 1
    sw    x12, 16(x10)         # S0 INTR_TEST → src1 pending in PLIC
    sw    x12, 16(x11)         # S1 INTR_TEST → src2 pending in PLIC

    # MIE=1 in mstatus — threshold=2 so no interrupt should fire
    li    x8, 8
    csrs  mstatus, x8

    # Phase 0: wait, verify no interrupt
    nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop
    bne   x29, x0, fail        # if handler ran → FAIL (threshold blocked them)

    # ---- Phase 1: lower threshold to 1 → src2 fires ----
    li    x28, 1               # tell handler to expect claim=2
    li    x8, 1
    sw    x8, 0(x7)            # threshold = 1
    nop; nop; nop; nop; nop; nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop; nop; nop; nop; nop; nop
    li    x8, 1
    bne   x29, x8, fail        # handler must have run exactly once

    # ---- Phase 2: lower threshold to 0 → src1 fires ----
    li    x28, 2               # tell handler to expect claim=1
    li    x8, 0
    sw    x8, 0(x7)            # threshold = 0
    nop; nop; nop; nop; nop; nop; nop; nop; nop; nop
    nop; nop; nop; nop; nop; nop; nop; nop; nop; nop
    li    x8, 2
    bne   x29, x8, fail        # handler must have run exactly twice

    # PASS
    li    x31, 1
    ebreak

# =============================================
# plic_handler: entered via vectored MEI
# Checks phase, verifies claim, clears source
# =============================================
plic_handler:
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    lui   x22, 0x0C200
    lw    x23, 4(x22)          # CLAIM

    li    x24, 1
    beq   x28, x24, ph_expect2

    # Phase 2: expect claim=1, clear S0 INTR_STATE
    li    x24, 1
    bne   x23, x24, fail
    lui   x25, 0x20000
    li    x26, 1
    sw    x26, 12(x25)         # S0 INTR_STATE W1C
    sw    x23, 4(x22)          # COMPLETE = 1
    j     ph_done

ph_expect2:
    # Phase 1: expect claim=2, clear S1 INTR_STATE
    li    x24, 2
    bne   x23, x24, fail
    lui   x25, 0x20001
    li    x26, 1
    sw    x26, 12(x25)         # S1 INTR_STATE W1C
    sw    x23, 4(x22)          # COMPLETE = 2

ph_done:
    addi  x29, x29, 1
    mret                       # returns to mepc = interrupted_pc + 4

fail:
    li    x31, 0
    ebreak
