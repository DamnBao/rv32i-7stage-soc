    .text
    .global _start
_start:

    # Set mtvec = msi_handler (Direct mode)
    la    x1, msi_handler
    csrw  mtvec, x1

    # Enable MSIE: set mie[3] (x2=8, rd=x0 → no CSR stall)
    addi  x2, x0, 8
    csrrs x0, mie, x2

    # Enable MIE: set mstatus[3] (rd=x0 → no CSR stall)
    csrrs x0, mstatus, x2

    # Set mip.MSIP=1 via CSRRSI (imm=8, rd=x0 → no CSR stall)
    # mip_msip updates at this posedge (WB cycle of csrrsi)
    csrrsi x0, mip, 8

    # Interrupt fires when THIS nop reaches WB (mip_msip=1 from previous cycle)
    # mepc = nop_PC + 4 = addr of "addi x3,x0,1" below
    nop

    # After MRET lands here: check that handler set x28=1
    addi  x3, x0, 1
    bne   x28, x3, fail

pass:
    addi  x31, x0, 1
    ebreak

msi_handler:
    # Verify mcause = 0x80000003 (MSI: interrupt bit + cause=3)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 3
    bne   x20, x21, fail

    # Verify mstatus.MIE = 0 during trap
    csrr  x22, mstatus
    andi  x23, x22, 8
    bne   x23, x0, fail

    # Clear mip.MSIP to prevent re-interrupt on MRET (x2=8, rd=x0)
    csrrc x0, mip, x2

    # Signal success (x28 checked after MRET)
    addi  x28, x0, 1

    mret

fail:
    addi  x31, x0, 0
    ebreak
