    .text
    .global _start
_start:

    # Set mtvec = mei_handler (Direct mode)
    la    x1, mei_handler
    csrw  mtvec, x1

    # Enable MEIE: set mie[11] (bit 11 = 0x800)
    addi  x2, x0, 1
    slli  x2, x2, 11        # x2 = 0x800 (MEIE bit, preserved for handler)
    csrrs x0, mie, x2

    # Enable MIE: set mstatus[3]
    addi  x3, x0, 8
    csrrs x0, mstatus, x3

    # Trigger AXI SFR0 IRQ via standard register map:
    #   INTR_ENABLE (0x08): unmask bit0
    #   INTR_TEST   (0x10): force INTR_STATE[0]=1 → axi_irq=1 after write commits
    lui   x4, 0x20000       # x4 = 0x2000_0000 (AXI_SFR0 base)
    addi  x5, x0, 1
    sw    x5, 0x08(x4)      # INTR_ENABLE[0]=1
    sw    x5, 0x10(x4)      # INTR_TEST[0]=1 → sets INTR_STATE[0] → axi_irq=1

    # AXI is synchronous: irq rises at the cycle the INTR_TEST write commits.
    # A few NOPs give the interrupt time to sample.
    nop
    nop
    nop

    # Reaching here means interrupt did not fire — fail
    j     fail

mei_handler:
    # Verify mcause = 0x8000_000B (MEI: interrupt bit + cause=11)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Verify mstatus.MIE = 0 during trap
    csrr  x22, mstatus
    andi  x23, x22, 8
    bne   x23, x0, fail

    # Disable MEIE to prevent re-interrupt after MRET
    csrrc x0, mie, x2       # x2 = 0x800 (MEIE bit)

    # Override return address to pass
    la    x24, pass
    csrw  mepc, x24

    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
