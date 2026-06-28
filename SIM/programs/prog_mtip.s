# prog_mtip.s — Machine Timer Interrupt (MTIP path) Test
#
# Tests the MTIP path distinct from MEIP:
#   axi_S1_irq  →  soc_top mtip_wire  →  zicsr.mtip_in  →  mip[7]
#
# Setup:
#   - Enable MTIE (mie[7]=1), NOT MEIE (mie[11])
#   - PLIC not configured: timer src[1] priority=0, threshold=0 → meip_in=0
#   - Timer: PRESCALER=0, COMPARE=20, INTR_ENABLE=1, CTRL=1
#   - MIE (mstatus[3]) enabled after timer start
#
# Expected: interrupt taken via MTIP with mcause = 0x8000_0007
#
# Requires tb_periph testbench (timer_axi at AXI S1 = 0x2000_1000)

.section .text
.global _start

_start:
    la    x1, mtip_handler
    csrw  mtvec, x1           # direct mode: all traps → mtip_handler

    # ── Configure timer at 0x2000_1000 ────────────────────────────────────
    lui   x4, 0x20001         # x4 = 0x2000_1000
    sw    x0, 0x14(x4)        # DATA0: PRESCALER = 0 (tick every cycle)
    addi  x5, x0, 20
    sw    x5, 0x18(x4)        # DATA1: COMPARE = 20
    addi  x5, x0, 1
    sw    x5, 0x08(x4)        # INTR_ENABLE[0] = 1 (compare-match IRQ)
    sw    x5, 0x00(x4)        # CTRL[0] = 1 (start timer)

    # ── Enable MTIE only (mie[7] = 1; MEIE = mie[11] stays 0) ────────────
    addi  x2, x0, 128         # x2 = 0x80 = MTIE bit (bit 7)
    csrrs x0, mie, x2         # set MTIE

    # ── Enable global interrupt (mstatus.MIE = 1) ─────────────────────────
    addi  x3, x0, 8
    csrrs x0, mstatus, x3     # set MIE bit

    # ── Spin: timer fires within ~20 cycles of CTRL write ─────────────────
spin:
    nop
    nop
    j     spin

    j     fail                # unreachable

# ─── MTIP handler ────────────────────────────────────────────────────────────
mtip_handler:
    # Verify mcause = 0x8000_0007 (Machine Timer Interrupt)
    csrr  x20, mcause
    lui   x21, 0x80000        # x21 = 0x8000_0000
    addi  x21, x21, 7         # x21 = 0x8000_0007
    bne   x20, x21, fail

    # Verify mip.MTIP is set: read mip, check bit 7
    csrr  x22, mip
    addi  x23, x0, 128        # 0x80 = bit 7
    and   x22, x22, x23
    bne   x22, x23, fail      # bit 7 must be 1

    # Clear timer: stop and W1C INTR_STATE
    lui   x10, 0x20001        # timer base
    sw    x0,  0x00(x10)      # CTRL = 0 (stop timer → axi_S1_irq goes low)
    addi  x11, x0, 1
    sw    x11, 0x0C(x10)      # W1C INTR_STATE[0]

    # Disable MTIE to prevent re-entry
    addi  x12, x0, 128
    csrrc x0, mie, x12

    la    x13, pass
    csrw  mepc, x13
    mret

pass:
    addi  x31, x0, 1          # PASS
    ebreak

fail:
    addi  x31, x0, 0          # FAIL
    ebreak
