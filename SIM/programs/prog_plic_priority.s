    .text
    .global _start

_start:

# PLIC Priority Arbitration Test
#
# Configures 2 simultaneous IRQ sources with different priorities:
#   Source 1 (axi_S0): PRIORITY = 1 (lower)
#   Source 2 (axi_S1): PRIORITY = 2 (higher)
#
# Forces both IRQs simultaneously via INTR_TEST, then in a single handler
# invocation performs three claims to verify the priority-ordered grant:
#   Claim 1 → expect 2 (highest priority wins)
#   Claim 2 → expect 1 (source 1 still pending)
#   Claim 3 → expect 0 (no more pending)
#
# Results stored in DMEM[0x10000..0x10008] for post-handler verification.
#
# PLIC register addresses:
#   PRIORITY[1] = 0x0C000004   PRIORITY[2] = 0x0C000008
#   ENABLE      = 0x0C002000   (bit[1]=src1, bit[2]=src2)
#   THRESHOLD   = 0x0C200000   CLAIM/COMPLETE = 0x0C200004
#
# AXI SFR offsets:
#   INTR_ENABLE = 0x08   INTR_STATE = 0x0C (W1C)   INTR_TEST = 0x10 (WO)

    # ── Setup exception handler ──────────────────────────────────────────
    la    x1, plic_handler
    csrw  mtvec, x1              # direct mode (mtvec[1:0]=0)

    # ── PLIC init ────────────────────────────────────────────────────────
    lui   x6, 0x0C000            # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 4(x6)              # PRIORITY[1] = 1 (source 1 = axi_S0)
    addi  x7, x0, 2
    sw    x7, 8(x6)              # PRIORITY[2] = 2 (source 2 = axi_S1)

    lui   x8, 0x0C002            # x8 = 0x0C002000 (ENABLE)
    addi  x9, x0, 6              # 0b110: enable bit[1] and bit[2]
    sw    x9, 0(x8)              # enable sources 1 and 2

    lui   x10, 0x0C200           # x10 = 0x0C200000 (THRESHOLD)
    sw    x0, 0(x10)             # THRESHOLD = 0

    # ── Enable MEIE (mie[11] = 0x800) ───────────────────────────────────
    addi  x2, x0, 1
    slli  x2, x2, 11             # x2 = 0x800
    csrrs x0, mie, x2

    # ── Force IRQs on both AXI SFR slaves ───────────────────────────────
    lui   x4, 0x20000            # x4 = 0x2000_0000 (S0 base)
    lui   x5, 0x20001            # x5 = 0x2000_1000 (S1 base)
    addi  x3, x0, 1

    sw    x3, 0x08(x4)           # S0 INTR_ENABLE[0] = 1
    sw    x3, 0x08(x5)           # S1 INTR_ENABLE[0] = 1

    sw    x3, 0x10(x4)           # S0 INTR_TEST → INTR_STATE[0] = 1 → irq rises
    sw    x3, 0x10(x5)           # S1 INTR_TEST → INTR_STATE[0] = 1 → irq rises

    # Both IRQs now pending in PLIC.
    # Enable global interrupts — interrupt fires at the next instruction.
    addi  x11, x0, 8
    csrrs x0, mstatus, x11       # mstatus.MIE = 1

    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    j     fail                   # should not reach here

    # ── Post-handler verification ────────────────────────────────────────
after_handler:
    # Handler stores: DMEM[0]=claim1, DMEM[4]=claim2, DMEM[8]=claim3
    lui   x12, 0x10              # x12 = 0x0001_0000 (DMEM base)
    lw    x13, 0(x12)            # claim1 (expect 2)
    lw    x14, 4(x12)            # claim2 (expect 1)
    lw    x15, 8(x12)            # claim3 (expect 0)

    addi  x1, x0, 2
    bne   x13, x1, fail          # claim1 must be 2 (higher priority source)
    addi  x1, x0, 1
    bne   x14, x1, fail          # claim2 must be 1
    bne   x15, x0, fail          # claim3 must be 0 (no more pending)

    addi  x31, x0, 1             # PASS
    ebreak

fail:
    addi  x31, x0, 0             # FAIL
    ebreak


    # ── Interrupt Handler ────────────────────────────────────────────────
plic_handler:
    # Verify mcause = 0x8000_000B (MEI: machine external interrupt)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    lui   x20, 0x0C200           # x20 = 0x0C200000 (PLIC THRESHOLD)
    lui   x24, 0x10              # x24 = 0x0001_0000 (DMEM base)

    # ── Claim 1: expect source 2 (higher priority) ───────────────────────
    lw    x21, 4(x20)            # read CLAIM (0x0C200004) → should return 2
    sw    x21, 0(x24)            # store first claim to DMEM[0]

    # Clear S1 (source 2) IRQ by W1C on INTR_STATE
    lui   x25, 0x20001           # S1 base
    addi  x26, x0, 1
    sw    x26, 0x0C(x25)        # S1 INTR_STATE W1C clear

    # Complete claim 1 (writes PLIC COMPLETE register with claimed ID)
    sw    x21, 4(x20)            # COMPLETE = 2

    # ── Claim 2: source 2 done; source 1 still pending → expect 1 ───────
    lw    x22, 4(x20)            # second claim → should return 1
    sw    x22, 4(x24)            # store to DMEM[4]

    # Clear S0 (source 1) IRQ
    lui   x25, 0x20000           # S0 base
    sw    x26, 0x0C(x25)        # S0 INTR_STATE W1C clear

    # Complete claim 2
    sw    x22, 4(x20)            # COMPLETE = 1

    # ── Claim 3: no more pending → expect 0 ─────────────────────────────
    lw    x23, 4(x20)            # third claim → should return 0
    sw    x23, 8(x24)            # store to DMEM[8]

    # Update mepc to after_handler label (skip the fail/nop zone)
    la    x27, after_handler
    csrw  mepc, x27

    mret
