    .text
    .global _start
_start:

# ── AHB IRQ path: SFR REG7[0]=1 → ahb_irq_raw → 2-FF sync (1GHz) → mip.MEIP ──
# Extra NOP margin accounts for the 2-cycle synchronizer latency after SW completes.

    # Set mtvec to handler (Direct mode, aligned)
    la    x1, ahb_mei_handler
    csrw  mtvec, x1

    # Enable MEIE: mie[11] = 0x800
    addi  x2, x0, 1
    slli  x2, x2, 11      # x2 = 0x800
    csrrs x0, mie, x2

    # Enable MIE: mstatus[3] = 8
    addi  x3, x0, 8
    csrrs x0, mstatus, x3

    # Write 1 to AHB SFR0 REG7 (0x3000_001C) → asserts ahb_irq_raw (500MHz domain)
    # bus_stall holds pipeline until response FIFO returns (AHB write complete).
    # After stall releases: ahb_irq_raw=1 in 500MHz domain.
    # 2-FF sync at 1GHz adds ~2 extra clk_cpu cycles before mip.MEIP=1.
    lui   x4, 0x30000       # x4 = 0x3000_0000
    addi  x5, x0, 1
    sw    x5, 0x1C(x4)

    # Safety margin for 2-FF synchronizer latency
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

    # Clear IRQ: write 0 to AHB SFR0 REG7 (another AHB transaction)
    lui   x24, 0x30000
    sw    x0, 0x1C(x24)

    # Disable MEIE: ahb_irq_sync will stay 1 for ~2 more 1GHz cycles after
    # the AHB write completes (2-FF sync clearing takes time). Must prevent
    # re-interrupt on MRET.
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
