    .text
    .global _start
_start:

# ── AHB IRQ path: SFR standard map — INTR_ENABLE + INTR_TEST → ahb_irq → 2-FF sync → MEI ──
#
# Standard register map offsets in SFR (base=0x3000_0000):
#   INTR_ENABLE = 0x08  (RW)
#   INTR_STATE  = 0x0C  (RW1C: write 1 to clear)
#   INTR_TEST   = 0x10  (WO:   write 1 to force INTR_STATE[0]=1)
#
# Sequence:
#   1. Write INTR_ENABLE[0]=1 → bus_stall (CDC FIFO round-trip)
#   2. Write INTR_TEST[0]=1   → bus_stall (ahb_sfr sets INTR_STATE[0] in 500MHz domain)
#   3. After stall: ahb_irq_raw=1 (500MHz), 2-FF sync at 1GHz adds ~2 cycle latency
#   4. Extra NOPs bridge the synchronizer latency
# Handler W1C-clears INTR_STATE[0], disables MEIE to prevent re-interrupt during sync clearing.

    # Set mtvec to handler (Direct mode, aligned)
    la    x1, ahb_mei_handler
    csrw  mtvec, x1

    # === PLIC Init ===
    # Source 4 = ahb_S0 (irq_src[3], sau 2-FF sync); PRIORITY=1, ENABLE bit[4]=1, THRESHOLD=0
    lui   x6, 0x0C000          # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 16(x6)           # PRIORITY[4] = 1 (offset 0x10 = 16)
    lui   x9, 0x0C002          # x9 = 0x0C002000 (ENABLE)
    addi  x8, x0, 16           # value: bit[4]=1 → enable source 4
    sw    x8, 0(x9)
    lui   x10, 0x0C200         # x10 = 0x0C200000 (THRESHOLD)
    sw    x0, 0(x10)           # THRESHOLD = 0

    # Enable MEIE: mie[11] = 0x800
    addi  x2, x0, 1
    slli  x2, x2, 11      # x2 = 0x800
    csrrs x0, mie, x2

    # Enable MIE: mstatus[3] = 8
    addi  x3, x0, 8
    csrrs x0, mstatus, x3

    lui   x4, 0x30000       # x4 = 0x3000_0000
    addi  x5, x0, 1

    # Step 1: enable INTR_ENABLE[0]
    sw    x5, 0x08(x4)

    # Step 2: force INTR_STATE[0] via INTR_TEST
    # bus_stall holds until AHB response FIFO returns (write complete in 500MHz domain)
    sw    x5, 0x10(x4)

    # NOPs bridge: 2-FF sync (2 cycles) + PLIC pending register (+1 cycle) = 3 cycles total
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    j     fail              # Should not reach here

ahb_mei_handler:
    # Verify mcause = 0x8000_000B (MEI: interrupt=1, cause=11)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Verify mstatus.MIE = 0 (interrupts disabled during trap)
    csrr  x22, mstatus
    andi  x23, x22, 8
    bne   x23, x0, fail

    # Clear IRQ: W1C write 1 to INTR_STATE[0] (offset 0x0C) via AHB
    lui   x24, 0x30000
    sw    x5,  0x0C(x24)    # x5=1; clears INTR_STATE[0] in 500MHz domain

    # Disable MEIE: 2-FF sync clearing takes ~2 more 1GHz cycles; prevent re-interrupt on MRET
    csrrc x0, mie, x2       # x2 = 0x800

    la    x25, pass
    csrw  mepc, x25
    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
