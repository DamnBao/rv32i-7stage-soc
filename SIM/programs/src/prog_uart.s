    .text
    .global _start
_start:

# ── UART AXI test — TX/RX loopback + dual interrupt ──────────────
#
# UART at AXI Slave 2 (0x2000_2000) → PLIC source 3
# Testbench wires uart_tx → uart_rx (loopback)
#
# Test flow:
#   1. Configure UART: baud_div=9 (10 cycles/bit), CTRL=1 (enable)
#   2. Setup PLIC source 3: priority=1, enable=8, threshold=0
#   3. Enable UART INTR_ENABLE=3 (bit0=tx_done, bit1=rx_complete)
#   4. Write DATA1=0x55 → starts TX; loopback sends same byte back to RX
#   5. Enable MEIE + MIE; spin until IRQ
#   6a. First IRQ: tx_done (INTR_STATE[0]=1) → clear, complete, mret to spin
#   6b. Second IRQ: rx_complete (INTR_STATE[1]=1) → read DATA2, verify=0x55, pass
#
# UART register offsets (AXI-Lite SFR standard):
#   CTRL        = base + 0x00
#   STATUS      = base + 0x04  [0]=tx_busy [1]=rx_data_ready
#   INTR_ENABLE = base + 0x08  [0]=tx_done_en [1]=rx_complete_en
#   INTR_STATE  = base + 0x0C  [0]=tx_done [1]=rx_complete (W1C)
#   DATA0       = base + 0x14  baud_div
#   DATA1       = base + 0x18  TX byte (write to send)
#   DATA2       = base + 0x1C  RX byte (received)
#
# PLIC register map (base 0x0C000000):
#   PRIORITY[3] = 0x0C00000C  (source 3 = axi_S2 = uart)
#   ENABLE      = 0x0C002000  (bit 3 = source 3 = 0x8)
#   THRESHOLD   = 0x0C200000
#   CLAIM/COMP  = 0x0C200004

    # Set mtvec to handler (Direct mode, word-aligned)
    la    x1, uart_handler
    csrw  mtvec, x1

    # ── UART configuration ─────────────────────────────────────────
    lui   x4, 0x20002            # x4 = 0x2000_2000 (UART base)
    addi  x5, x0, 9
    sw    x5, 0x14(x4)           # DATA0: baud_div = 9 (10 cycles per bit)
    addi  x5, x0, 1
    sw    x5, 0x00(x4)           # CTRL = 1 (uart_en)

    # ── PLIC Init (source 3 = UART AXI S2) ────────────────────────
    lui   x6, 0x0C000            # x6 = 0x0C000000 (PLIC base)
    addi  x7, x0, 1
    sw    x7, 0x0C(x6)           # PRIORITY[3] = 1 (offset 0x0C)
    lui   x9, 0x0C002            # x9 = 0x0C002000 (ENABLE)
    addi  x8, x0, 8              # bit 3 = source 3 = 0x8
    sw    x8, 0(x9)              # enable source 3
    lui   x10, 0x0C200           # x10 = 0x0C200000 (THRESHOLD)
    sw    x0, 0(x10)             # THRESHOLD = 0

    # ── Enable UART IRQs and send byte ────────────────────────────
    lui   x4, 0x20002            # reload UART base
    addi  x5, x0, 3
    sw    x5, 0x08(x4)           # INTR_ENABLE = 3 (tx_done + rx_complete)
    addi  x5, x0, 0x55
    sw    x5, 0x18(x4)           # DATA1 = 0x55 → starts TX

    # ── Enable CPU interrupts ──────────────────────────────────────
    addi  x2, x0, 1
    slli  x2, x2, 11             # x2 = 0x800 (MEIE bit)
    csrrs x0, mie, x2
    addi  x3, x0, 8
    csrrs x0, mstatus, x3        # MIE = 1

    # ── Spin until IRQ ────────────────────────────────────────────
spin:
    nop
    nop
    j     spin

    j     fail                   # unreachable

# ── UART interrupt handler ─────────────────────────────────────────
# Called for both tx_done (first) and rx_complete (second) IRQs
uart_handler:
    # Verify mcause = 0x8000_000B (Machine External Interrupt)
    csrr  x20, mcause
    lui   x21, 0x80000
    addi  x21, x21, 11
    bne   x20, x21, fail

    # Read PLIC CLAIM — expect 3 (source 3 = uart)
    lui   x11, 0x0C200           # x11 = 0x0C200000
    lw    x12, 4(x11)            # CLAIM
    addi  x13, x0, 3
    bne   x12, x13, fail

    # Read UART INTR_STATE
    lui   x14, 0x20002           # UART base = 0x2000_2000
    lw    x22, 0x0C(x14)        # INTR_STATE

    # Check rx_complete first (bit 1) — indicates loopback RX done
    andi  x23, x22, 2            # bit 1 = rx_complete
    beqz  x23, handle_tx_done    # if not set, must be tx_done only

    # rx_complete: read DATA2, verify loopback data = 0x55
    lw    x24, 0x1C(x14)        # DATA2 = received byte
    addi  x25, x0, 0x55
    bne   x24, x25, fail         # verify loopback == 0x55

    # Clear all INTR_STATE (W1C) and complete
    sw    x22, 0x0C(x14)        # W1C clear all pending bits
    sw    x12, 4(x11)            # PLIC COMPLETE = 3
    csrrc x0, mie, x2            # disable MEIE
    la    x15, pass
    csrw  mepc, x15
    mret

handle_tx_done:
    # tx_done only (bit 0): clear it and return to spin
    andi  x23, x22, 1            # bit 0 = tx_done
    beqz  x23, fail              # neither bit set → error
    sw    x22, 0x0C(x14)        # W1C clear tx_done
    sw    x12, 4(x11)            # PLIC COMPLETE = 3
    mret                         # back to spin; wait for rx_complete IRQ

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
