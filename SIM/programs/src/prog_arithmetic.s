    .text
    .global _start
_start:

# ── ADD ──
    addi  x1, x0, 10
    addi  x2, x0, 20
    add   x3, x1, x2        # x3 = 30
    addi  x4, x0, 30
    bne   x3, x4, fail

# ── SUB ──
    sub   x5, x2, x1        # x5 = 10
    bne   x5, x1, fail

# ── AND ──
    addi  x6, x0, 15        # 0x0F
    addi  x7, x0, 255       # 0xFF
    and   x8, x6, x7        # x8 = 0x0F
    bne   x8, x6, fail

# ── OR ──
    or    x9, x6, x7        # x9 = 0xFF
    bne   x9, x7, fail

# ── XOR ──
    xor   x10, x7, x7       # x10 = 0
    bne   x10, x0, fail

# ── SLL ──
    addi  x11, x0, 1
    sll   x12, x11, x11     # x12 = 1 << 1 = 2
    addi  x13, x0, 2
    bne   x12, x13, fail

# ── SRL ──
    addi  x14, x0, 8
    addi  x15, x0, 1
    srl   x16, x14, x15     # x16 = 8 >> 1 = 4
    addi  x17, x0, 4
    bne   x16, x17, fail

# ── SRA: -4 >> 1 = -2 ──
    addi  x18, x0, -4
    addi  x19, x0, 1
    sra   x20, x18, x19     # x20 = -2
    addi  x21, x0, -2
    bne   x20, x21, fail

# ── SLT: signed ──
    addi  x22, x0, -1       # -1
    slt   x23, x22, x0      # -1 < 0 → 1
    addi  x24, x0, 1
    bne   x23, x24, fail

# ── SLTU: unsigned ──
    addi  x25, x0, 1
    sltu  x26, x25, x0      # 1 <u 0 → 0
    bne   x26, x0, fail

    # 0 <u 1 → 1
    sltu  x27, x0, x24      # x24 = 1
    bne   x27, x24, fail

# ── ADDI ──
    addi  x1, x0, 100
    addi  x2, x1, -100      # x2 = 0
    bne   x2, x0, fail

# ── ANDI ──
    addi  x1, x0, 255       # 0xFF
    andi  x2, x1, 15        # x2 = 0x0F
    addi  x3, x0, 15
    bne   x2, x3, fail

# ── ORI ──
    ori   x4, x0, 85        # x4 = 0x55
    addi  x5, x0, 85
    bne   x4, x5, fail

# ── XORI ──
    xori  x6, x0, -1        # x6 = 0xFFFFFFFF
    addi  x7, x0, -1
    bne   x6, x7, fail

# ── SLLI ──
    addi  x1, x0, 1
    slli  x2, x1, 3         # x2 = 8
    addi  x3, x0, 8
    bne   x2, x3, fail

# ── SRLI ──
    srli  x4, x2, 1         # x4 = 4
    addi  x5, x0, 4
    bne   x4, x5, fail

# ── SRAI: -8 >> 1 = -4 ──
    addi  x6, x0, -8
    srai  x7, x6, 1         # x7 = -4
    addi  x8, x0, -4
    bne   x7, x8, fail

# ── SLTI: signed ──
    addi  x1, x0, -1
    slti  x2, x1, 0         # -1 < 0 → 1
    addi  x3, x0, 1
    bne   x2, x3, fail

# ── SLTIU: unsigned ──
    sltiu x4, x0, 1         # 0 <u 1 → 1
    bne   x4, x3, fail

# ── LUI ──
    lui   x1, 1             # x1 = 0x1000 = 4096
    srli  x2, x1, 12        # x2 = 1
    addi  x3, x0, 1
    bne   x2, x3, fail

# ── AUIPC: two consecutive → delta = 4 ──
    auipc x1, 0
    auipc x2, 0
    sub   x3, x2, x1
    addi  x4, x0, 4
    bne   x3, x4, fail

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
