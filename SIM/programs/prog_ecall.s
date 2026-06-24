    .text
    .global _start
_start:

    # Set mtvec = ecall_handler (Direct mode, rd=x0 so no CSR stall)
    la    x1, ecall_handler
    csrw  mtvec, x1

    # Set mstatus.MIE=1 via CSRRS to preserve MPP=11 from reset
    addi  x2, x0, 8
    csrrs x0, mstatus, x2

    # Trigger ECALL
ecall_target:
    ecall

    # POST-MRET: handler advanced mepc by 4, so we resume here

    # Verify mcause = 11 (x20 set by handler)
    addi  x3, x0, 11
    bne   x20, x3, fail

    # Verify mstatus.MIE restored to 1 after MRET
    csrr  x4, mstatus
    andi  x5, x4, 8
    addi  x6, x0, 8
    bne   x5, x6, fail

    # Verify mepc pointed at the ECALL instruction (x21 = original mepc from handler)
    la    x7, ecall_target
    bne   x21, x7, fail

pass:
    addi  x31, x0, 1
    ebreak

ecall_handler:
    # Trace: store mepc raw to DMEM[0x10000] so we can inspect
    lui   x29, 16               # x29 = 0x10000 (DMEM base)
    csrr  x28, mepc             # x28 = raw mepc
    sw    x28, 0(x29)           # DMEM[0] = raw mepc (expect 0x14)

    # Read and save mcause (expect 11 = ecall from M-mode)
    csrr  x20, mcause
    sw    x20, 4(x29)           # DMEM[1] = mcause (expect 11)

    # Read and save mepc (x21 = mepc, expect = ecall_target = 0x14)
    csrr  x21, mepc
    sw    x21, 8(x29)           # DMEM[2] = mepc (expect 0x14)

    # Verify mstatus.MIE = 0 during trap (MIE saved to MPIE, cleared)
    csrr  x8, mstatus
    andi  x9, x8, 8
    sw    x9, 12(x29)           # DMEM[3] = MIE during trap (expect 0)
    bne   x9, x0, fail

    # Advance mepc by 4 to skip ECALL on MRET
    addi  x10, x21, 4
    sw    x10, 16(x29)          # DMEM[4] = new mepc to write (expect 0x18)
    csrw  mepc, x10

    mret

fail:
    addi  x31, x0, 0
    ebreak
