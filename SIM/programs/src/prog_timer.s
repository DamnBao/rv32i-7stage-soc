    .text
    .global _start
_start:

# ── Timer AXI test — compare-match interrupt ──────────────────────
#
# Timer at AXI Slave 1 (0x2000_1000) → PLIC source 2
#
# Test flow:
#   1. Configure timer: PRESCALER=0 (tick every cycle), COMPARE=20
#   2. Enable timer compare IRQ (INTR_ENABLE=1), start timer (CTRL=1)
#   3. Setup PLIC source 2 priority=1, enable=4, threshold=0
#   4. Enable MEIE + MIE; spin in loop
#   5. Handler: claim=2, clear INTR_STATE, complete, mret → pass
#
# Timer register offsets (AXI-Lite SFR standard):
#   CTRL        = base + 0x00
#   STATUS      = base + 0x04  (timer_cnt, read-only)
#   INTR_ENABLE = base + 0x08
#   INTR_STATE  = base + 0x0C  (W1C)
#   DATA0       = base + 0x14  (PRESCALER)
#   DATA1       = base + 0x18  (COMPARE)
#
# PLIC register map (base 0x0C000000):
#   PRIORITY[2] = 0x0C000008  (source 2 = axi_S1 = timer)
#   ENABLE      = 0x0C002000  (bit 2 = source 2)
#   THRESHOLD   = 0x0C200000
#   CLAIM/COMP  = 0x0C200004

    # Set mtvec to handler (Direct mode, word-aligned)
    la    x1, timer_handler
    csrw  mtvec, x1

    # ── PLIC Init (source 2 = timer) ──────────────────────────────
    lui   x6, 0x0C000            # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 8(x6)              # PRIORITY[2] = 1 (offset 0x08)
    lui   x9, 0x0C002            # x9 = 0x0C002000 (ENABLE)
    addi  x8, x0, 4              # bit 2 = source 2
    sw    x8, 0(x9)              # enable source 2
    lui   x10, 0x0C200           # x10 = 0x0C200000 (THRESHOLD)
    sw    x0, 0(x10)             # THRESHOLD = 0

    # ── Timer configuration ────────────────────────────────────────
    lui   x4, 0x20001            # x4 = 0x2000_1000 (timer base)
    sw    x0, 0x14(x4)           # DATA0: PRESCALER = 0 (tick every cycle)
    addi  x5, x0, 20
    sw    x5, 0x18(x4)           # DATA1: COMPARE = 20
    addi  x5, x0, 1
    sw    x5, 0x08(x4)           # INTR_ENABLE = 1 (compare match)
    sw    x5, 0x00(x4)           # CTRL = 1 (enable timer)

    # ── Enable interrupts ──────────────────────────────────────────
    addi  x2, x0, 1
    slli  x2, x2, 11             # x2 = 0x800 (MEIE bit)
    csrrs x0, mie, x2
    addi  x3, x0, 8
    csrrs x0, mstatus, x3        # MIE = 1

    # ── Spin (timer fires within ~21 cycles + bus latency) ────────
spin:
    nop
    nop
    j     spin                   # should not loop long before IRQ

    j     fail                   # unreachable

# ── Timer interrupt handler ────────────────────────────────────────
timer_handler:
    # Verify mcause = 0x8000_000B (Machine External Interrupt)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Read PLIC CLAIM
    lui   x11, 0x0C200           # x11 = 0x0C200000
    lw    x12, 4(x11)            # CLAIM → expect 2 (source 2 = timer)
    addi  x13, x0, 2
    bne   x12, x13, fail

    # Clear INTR_STATE at timer SFR (W1C bit 0)
    lui   x14, 0x20001           # timer base = 0x2000_1000
    addi  x15, x0, 1
    sw    x15, 0x0C(x14)         # W1C INTR_STATE[0]

    # Stop timer to prevent re-interrupt
    sw    x0, 0x00(x14)          # CTRL = 0 (disable timer)

    # Write PLIC COMPLETE = 2
    sw    x12, 4(x11)            # COMPLETE = claim id

    # Disable MEIE before MRET
    csrrc x0, mie, x2            # x2 = 0x800

    la    x15, pass
    csrw  mepc, x15
    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
