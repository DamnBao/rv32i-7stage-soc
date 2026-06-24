    .text
    .global _start
_start:

# ── AXI IRQ path: SFR REG7[0]=1 → axi_irq → mip.MEIP → MEI trap ──
# Handler clears the SFR via AXI write, then redirects to pass.

    # Set mtvec to handler (Direct mode, aligned)
    la    x1, axi_mei_handler
    csrw  mtvec, x1

    # Enable MEIE: mie[11] = 0x800
    addi  x2, x0, 1
    slli  x2, x2, 11      # x2 = 0x800
    csrrs x0, mie, x2

    # Enable MIE: mstatus[3] = 8
    addi  x3, x0, 8
    csrrs x0, mstatus, x3

    # Write 1 to AXI SFR0 REG7 (0x2000_001C) → asserts axi_irq
    # bus_stall holds pipeline until AXI write completes; after that axi_irq=1
    lui   x4, 0x20000       # x4 = 0x2000_0000
    addi  x5, x0, 1
    sw    x5, 0x1C(x4)

    # AXI is synchronous: axi_irq rises at the same cycle the write commits.
    # CPU samples mip.MEIP one cycle later. A few NOPs give the interrupt time to fire.
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

    # Clear IRQ: write 0 to AXI SFR0 REG7
    lui   x24, 0x20000
    sw    x0, 0x1C(x24)

    # Disable MEIE to prevent re-interrupt on MRET (AXI clears synchronously,
    # but the clear write is in-flight — disabling MEIE is the safe path)
    csrrc x0, mie, x2      # x2 = 0x800

    la    x25, pass
    csrw  mepc, x25
    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
