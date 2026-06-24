    .text
    .global _start
_start:

# ── SLT: signed less-than ──
    addi  t0, x0, -1         # t0 = 0xFFFFFFFF = -1 signed
    addi  t1, x0, 0
    slt   t2, t0, t1         # -1 < 0 (signed) → 1
    addi  t3, x0, 1
    bne   t2, t3, fail

    slt   t2, t1, t0         # 0 < -1 (signed) → 0
    bne   t2, x0, fail

    addi  t0, x0, 5
    addi  t1, x0, 5
    slt   t2, t0, t1         # 5 < 5 → 0
    bne   t2, x0, fail

    addi  t0, x0, 3
    addi  t1, x0, 7
    slt   t2, t0, t1         # 3 < 7 → 1
    addi  t3, x0, 1
    bne   t2, t3, fail

# ── SLTU: unsigned less-than ──
    addi  t0, x0, -1         # t0 = 0xFFFFFFFF (largest unsigned)
    addi  t1, x0, 0
    sltu  t2, t0, t1         # 0xFFFFFFFF < 0 unsigned → 0
    bne   t2, x0, fail

    sltu  t2, t1, t0         # 0 < 0xFFFFFFFF unsigned → 1
    addi  t3, x0, 1
    bne   t2, t3, fail

    sltu  t2, t1, t1         # 0 < 0 → 0
    bne   t2, x0, fail

    addi  t0, x0, 3
    addi  t1, x0, 7
    sltu  t2, t0, t1         # 3 < 7 unsigned → 1
    addi  t3, x0, 1
    bne   t2, t3, fail

# ── SLTI: signed immediate compare ──
    addi  t0, x0, 5
    slti  t1, t0, 10         # 5 < 10 → 1
    addi  t2, x0, 1
    bne   t1, t2, fail

    slti  t1, t0, 5          # 5 < 5 → 0
    bne   t1, x0, fail

    slti  t1, t0, -1         # 5 < -1 (signed) → 0
    bne   t1, x0, fail

    addi  t0, x0, -1         # t0 = -1
    slti  t1, t0, 0          # -1 < 0 → 1
    addi  t2, x0, 1
    bne   t1, t2, fail

    slti  t1, t0, -2         # -1 < -2 (signed) → 0
    bne   t1, x0, fail

# ── SLTIU: unsigned immediate compare ──
    addi  t0, x0, 5
    sltiu t1, t0, 10         # 5 < 10 unsigned → 1
    addi  t2, x0, 1
    bne   t1, t2, fail

    sltiu t1, t0, 0          # 5 < 0 unsigned → 0
    bne   t1, x0, fail

    sltiu t1, t0, 5          # 5 < 5 → 0
    bne   t1, x0, fail

    addi  t0, x0, 100
    sltiu t1, t0, -1         # 100 < 0xFFFFFFFF (unsigned -1) → 1
    addi  t2, x0, 1
    bne   t1, t2, fail

# ── AUIPC ──
    auipc t0, 0              # t0 = PC of this instruction
    auipc t1, 0              # t1 = PC of this instruction = t0 + 4
    addi  t2, t0, 4
    bne   t1, t2, fail

    auipc t0, 1              # t0 = PC + 0x1000
    auipc t1, 0              # t1 = PC (4 bytes after previous)
    lui   t2, 1              # t2 = 0x1000
    add   t2, t1, t2         # t2 = t1 + 0x1000
    addi  t2, t2, -4         # t2 = t1 + 0x1000 - 4 = expected t0
    bne   t0, t2, fail

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
