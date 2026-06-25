    .text
    .global _start
_start:

# ── AXI IRQ path: SFR standard map — INTR_ENABLE + INTR_TEST → axi_irq → MEI trap ──
#
# Standard register map offsets in SFR (base=0x2000_0000):
#   INTR_ENABLE = 0x08  (RW)
#   INTR_STATE  = 0x0C  (RW1C: write 1 to clear)
#   INTR_TEST   = 0x10  (WO:   write 1 to force INTR_STATE[0]=1)
#
# Sequence: set INTR_ENABLE[0]=1, then write INTR_TEST[0]=1 to trigger IRQ.
# Handler W1C-clears INTR_STATE[0] and disables MEIE before MRET.

    # Set mtvec to handler (Direct mode, aligned)
    la    x1, axi_mei_handler
    csrw  mtvec, x1

    # === PLIC Init ===
    # Source 1 = axi_S0 (irq_src[0]); PRIORITY=1, ENABLE bit[1]=1, THRESHOLD=0
    lui   x6, 0x0C000          # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 4(x6)            # PRIORITY[1] = 1 (offset 0x04)
    lui   x9, 0x0C002          # x9 = 0x0C002000 (ENABLE)
    addi  x8, x0, 2            # value: bit[1]=1 → enable source 1
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

    lui   x4, 0x20000       # x4 = 0x2000_0000
    addi  x5, x0, 1

    # Step 1: enable INTR_ENABLE[0] (bus_stall until AXI write completes)
    sw    x5, 0x08(x4)

    # Step 2: force INTR_STATE[0] via INTR_TEST (AXI write → irq rises immediately)
    sw    x5, 0x10(x4)

    # AXI is synchronous: irq = |(INTR_STATE & INTR_ENABLE) rises after write commit.
    # Extra NOPs: PLIC adds +1 cycle pending latency vs old OR-gate path
    nop
    nop
    nop
    nop
    nop

    j     fail              # Should not reach here

axi_mei_handler:
    # Verify mcause = 0x8000_000B (MEI: interrupt=1, cause=11)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Verify mstatus.MIE = 0 (interrupts disabled during trap)
    csrr  x22, mstatus
    andi  x23, x22, 8
    bne   x23, x0, fail

    # Clear IRQ: W1C write 1 to INTR_STATE[0] (offset 0x0C)
    lui   x24, 0x20000
    sw    x5,  0x0C(x24)    # x5=1; clears INTR_STATE[0]

    # Disable MEIE to prevent re-interrupt on MRET
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
