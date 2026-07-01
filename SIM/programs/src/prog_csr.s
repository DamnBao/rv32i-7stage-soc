    .text
    .global _start
_start:

# Use mie (0x304) as the primary test CSR — simple interrupt enable bits,
# no hardware side-effects in simulation when bus is idle.

# ── CSRRS with rs1=x0: read-only, mie reset = 0 ──
    csrrs x1, mie, x0      # read mie, no write (rs1=x0 → csr_we suppressed)
    bne   x1, x0, fail     # mie must be 0 after reset

# ── CSRRW: write 8 (MSIE bit), read old value ──
    addi  x2, x0, 8
    csrrw x3, mie, x2      # x3 = old mie (=0), mie = 8
    bne   x3, x0, fail     # old value must be 0

    csrrs x4, mie, x0      # read back
    bne   x4, x2, fail     # must be 8

# ── CSRRS: set MTIE bit (0x80 = 128) ──
    addi  x5, x0, 128      # 0x80 = MTIE
    csrrs x6, mie, x5      # x6 = old mie (=8), set MTIE → mie = 0x88
    bne   x6, x2, fail     # old value must be 8

    addi  x7, x0, 136      # 0x88 = MSIE | MTIE
    csrrs x8, mie, x0
    bne   x8, x7, fail     # mie must be 0x88

# ── CSRRC: clear MSIE (bit 3 = 8) ──
    csrrc x9, mie, x2      # x9 = old mie (=0x88), clear bit 3 → mie = 0x80
    bne   x9, x7, fail     # old value must be 0x88

    csrrs x10, mie, x0
    bne   x10, x5, fail    # mie must now be 0x80 (only MTIE)

# ── CSRRWI: write immediate 8 ──
    csrrwi x11, mie, 8     # mie = 8 (zimm), x11 = old mie (=0x80)
    bne    x11, x5, fail   # old value must be 0x80

    csrrs  x12, mie, x0
    bne    x12, x2, fail   # mie must be 8

# ── CSRRSI: set bits via immediate ──
    csrrsi x13, mie, 16    # mie |= 0x10 (zimm=16), x13 = old=8 → mie = 0x18
    bne    x13, x2, fail   # old must be 8
    addi   x14, x0, 24    # 0x18
    csrrs  x15, mie, x0
    bne    x15, x14, fail

# ── CSRRCI: clear bits via immediate ──
    csrrci x16, mie, 8     # mie &= ~8 → mie = 0x10 (0x18 & ~8 = 0x10), x16 = old=0x18
    bne    x16, x14, fail  # old must be 0x18
    addi   x17, x0, 16
    csrrs  x18, mie, x0
    bne    x18, x17, fail  # mie = 0x10

# ── Write mtvec, verify read-back ──
    addi  x19, x0, 64      # 0x40 (valid trap vector, Direct mode)
    csrrw x20, mtvec, x19  # x20 = old mtvec (=0 after reset)
    bne   x20, x0, fail

    csrrs x21, mtvec, x0
    bne   x21, x19, fail   # mtvec must be 0x40

# ── CSRRC with rs1=x0: mtvec unchanged ──
    csrrc x22, mtvec, x0   # read mtvec, no clear (rs1=x0)
    bne   x22, x19, fail   # must still be 0x40

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
