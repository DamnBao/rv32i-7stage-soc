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

    # Write 1 to AXI_SFR0 REG7 (0x2000_001C) → asserts axi_irq
    # AXI transaction: bus_stall_req=1, take_interrupt gated until done
    lui   x4, 0x20000       # x4 = 0x2000_0000 (AXI_SFR0 base)
    addi  x5, x0, 1
    sw    x5, 0x1C(x4)      # REG7[0]=1 → axi_irq=1 after write completes

    # Interrupt fires at the WB cycle when SW commits (bus done, axi_irq=1)
    # mepc = SW_PC + 4; handler redirects to pass so NOPs are safety margin
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
    # (AXI REG7 is still 1; clearing mie.MEIE is simpler than another AXI write)
    csrrc x0, mie, x2       # x2 = 0x800 (MEIE bit)

    # Override return address to pass (skip NOPs that follow SW)
    la    x24, pass
    csrw  mepc, x24

    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
