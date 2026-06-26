    .text
    .global _start
_start:

# ── GPIO AHB test — loopback data + IRQ via INTR_TEST ─────────────
#
# GPIO at AHB Slave 0 (0x3000_0000) → PLIC source 4
#
# Test flow:
#   1. Write DATA0=0x55 (gpio_out value), DATA1=1 (output enable)
#   2. Read STATUS (gpio_in = loopback); verify = 0x55
#   3. Enable GPIO IRQ (INTR_ENABLE=1), setup PLIC source 4
#   4. Force interrupt via INTR_TEST=1
#   5. Enable MEIE+MIE; spin until handler fires
#   6. Handler: claim=4, clear INTR_STATE, complete, mret → pass
#
# GPIO register offsets (AHB-Lite SFR standard):
#   CTRL        = base + 0x00
#   STATUS      = base + 0x04  (gpio_in, sync'd, read-only)
#   INTR_ENABLE = base + 0x08
#   INTR_STATE  = base + 0x0C  (W1C)
#   INTR_TEST   = base + 0x10  (force-set INTR_STATE)
#   DATA0       = base + 0x14  (gpio_out value)
#   DATA1       = base + 0x18  (output enable)
#
# PLIC register map (base 0x0C000000):
#   PRIORITY[4] = 0x0C000010  (source 4 = ahb_S0 = gpio)
#   ENABLE      = 0x0C002000  (bit 4 = source 4 = 0x10)
#   THRESHOLD   = 0x0C200000
#   CLAIM/COMP  = 0x0C200004

    # Set mtvec to handler (Direct mode)
    la    x1, gpio_handler
    csrw  mtvec, x1

    # ── GPIO: write gpio_out and read back ─────────────────────────
    lui   x4, 0x30000            # x4 = 0x3000_0000 (GPIO base)
    addi  x5, x0, 0x55
    sw    x5, 0x14(x4)           # DATA0 = 0x55 (gpio_out value)
    addi  x6, x0, 1
    sw    x6, 0x18(x4)           # DATA1 = 1 (output enable)

    # Read STATUS (gpio_in via 2-FF sync + CDC loopback)
    # CDC + 2-FF sync completes during AHB bus_stall of the preceding writes
    lw    x7, 0x04(x4)           # STATUS = gpio_in (sync'd)
    addi  x8, x0, 0x55
    bne   x7, x8, fail           # verify loopback == 0x55

    # ── PLIC Init (source 4 = GPIO AHB S0) ────────────────────────
    lui   x6, 0x0C000            # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 0x10(x6)           # PRIORITY[4] = 1 (offset 0x10)
    lui   x9, 0x0C002            # x9 = 0x0C002000 (ENABLE)
    addi  x8, x0, 16             # bit 4 = source 4 = 0x10
    sw    x8, 0(x9)              # enable source 4
    lui   x10, 0x0C200           # x10 = 0x0C200000 (THRESHOLD)
    sw    x0, 0(x10)             # THRESHOLD = 0

    # ── GPIO IRQ: enable and force via INTR_TEST ──────────────────
    lui   x4, 0x30000            # GPIO base
    addi  x5, x0, 1
    sw    x5, 0x08(x4)           # INTR_ENABLE = 1 (enable edge IRQ)
    sw    x5, 0x10(x4)           # INTR_TEST = 1 (force INTR_STATE[0])

    # ── Enable CPU interrupts ──────────────────────────────────────
    addi  x2, x0, 1
    slli  x2, x2, 11             # x2 = 0x800 (MEIE)
    csrrs x0, mie, x2
    addi  x3, x0, 8
    csrrs x0, mstatus, x3        # MIE = 1

    # ── Spin until IRQ ────────────────────────────────────────────
spin:
    nop
    nop
    j     spin

    j     fail

# ── GPIO interrupt handler ─────────────────────────────────────────
gpio_handler:
    # Verify mcause = 0x8000_000B
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Read PLIC CLAIM — expect 4 (source 4 = gpio)
    lui   x11, 0x0C200
    lw    x12, 4(x11)
    addi  x13, x0, 4
    bne   x12, x13, fail

    # Clear INTR_STATE at GPIO SFR (W1C)
    lui   x14, 0x30000           # GPIO base = 0x3000_0000
    addi  x15, x0, 1
    sw    x15, 0x0C(x14)         # W1C INTR_STATE[0]

    # Write PLIC COMPLETE = 4
    sw    x12, 4(x11)

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
