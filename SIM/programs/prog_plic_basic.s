    .text
    .global _start
_start:

# ── PLIC basic test: priority arbitration + claim/complete flow ──
#
# Setup: source 2 (axi_S1) = PRIORITY 5, source 1 (axi_S0) = PRIORITY 1.
# Trigger: write INTR_TEST on axi_S1 (base 0x2000_1000) → irq_src[1] rises.
# PLIC arbiter: source 2 wins (priority 5 > 1).
# Handler: verify claim=2, write COMPLETE=2, clear SFR, mret to pass.

    # Setup mtvec (Direct mode, aligned)
    la    x1, plic_handler
    csrw  mtvec, x1

    # === PLIC Init ===
    # Source 1 (axi_S0): PRIORITY[1]=1 — lower priority
    # Source 2 (axi_S1): PRIORITY[2]=5 — higher priority
    # ENABLE: bits[2:1]=1 → value=0b110=6
    # THRESHOLD=0 (forward priority > 0)
    lui   x6, 0x0C000          # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 4(x6)            # PRIORITY[1] = 1 (offset 0x04)
    addi  x7, x0, 5
    sw    x7, 8(x6)            # PRIORITY[2] = 5 (offset 0x08)
    lui   x9, 0x0C002          # x9 = 0x0C002000 (ENABLE)
    addi  x8, x0, 6            # value: bits[2:1]=1 → enable sources 1 and 2
    sw    x8, 0(x9)
    lui   x10, 0x0C200         # x10 = 0x0C200000 (THRESHOLD)
    sw    x0, 0(x10)           # THRESHOLD = 0

    # Enable MEIE and MIE
    addi  x2, x0, 1
    slli  x2, x2, 11           # x2 = 0x800 (MEIE bit)
    csrrs x0, mie, x2
    addi  x3, x0, 8
    csrrs x0, mstatus, x3

    # Trigger axi_S1 (source 2) via SFR standard map (base=0x2000_1000)
    lui   x4, 0x20001          # x4 = 0x2000_1000 (axi_S1 base)
    addi  x5, x0, 1
    sw    x5, 0x08(x4)         # INTR_ENABLE[0]=1
    sw    x5, 0x10(x4)         # INTR_TEST[0]=1  → irq_src[1] rises

    # NOPs: AXI bus_stall ends, then PLIC +1 cycle pending latency
    nop
    nop
    nop
    nop
    nop

    j     fail                 # Should not reach here

plic_handler:
    # Verify mcause = 0x8000_000B (Machine External Interrupt)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Read PLIC CLAIM (1-cycle latency, no bus_stall — treated like DMEM)
    # x12 = claim ID; forwarded via MEM2→EX path (gap-2) for the following bne
    lui   x11, 0x0C200         # x11 = 0x0C200000
    lw    x12, 4(x11)          # CLAIM register at 0x0C200004
    addi  x13, x0, 2           # expected source ID = 2 (axi_S1)
    bne   x12, x13, fail       # x12 forwarded from MEM2 (gap-2), x13 from MEM1

    # Write COMPLETE = 2 → clears pending[2]
    sw    x12, 4(x11)

    # Clear at SFR level: W1C write to INTR_STATE[0] (offset 0x0C)
    lui   x14, 0x20001         # axi_S1 base
    sw    x5,  0x0C(x14)       # x5=1; W1C clears INTR_STATE[0]

    # Disable MEIE to prevent re-interrupt on MRET
    csrrc x0, mie, x2         # x2 = 0x800

    la    x15, pass
    csrw  mepc, x15
    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
