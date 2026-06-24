    .text
    .global _start
_start:

# ── SLLI: shift left logical immediate ──
    addi  t0, x0, 1
    slli  t1, t0, 0          # 1 << 0 = 1
    addi  t2, x0, 1
    bne   t1, t2, fail

    slli  t1, t0, 4          # 1 << 4 = 16
    addi  t2, x0, 16
    bne   t1, t2, fail

    slli  t1, t0, 31         # 1 << 31 = 0x80000000
    lui   t2, 0x80000
    bne   t1, t2, fail

# ── SRLI: shift right logical immediate ──
    lui   t0, 0x80000        # t0 = 0x80000000
    srli  t1, t0, 1          # 0x40000000 (logical, no sign-extend)
    lui   t2, 0x40000
    bne   t1, t2, fail

    srli  t1, t0, 31         # 0x00000001
    addi  t2, x0, 1
    bne   t1, t2, fail

    srli  t1, t0, 0          # unchanged
    bne   t1, t0, fail

# ── SRAI: shift right arithmetic immediate ──
    lui   t0, 0x80000        # t0 = 0x80000000 (negative)
    srai  t1, t0, 1          # 0xC0000000 (sign bit replicated)
    lui   t2, 0xC0000
    bne   t1, t2, fail

    srai  t1, t0, 31         # 0xFFFFFFFF (all sign bits)
    addi  t2, x0, -1
    bne   t1, t2, fail

    addi  t0, x0, 8          # positive: SRAI same as SRLI
    srai  t1, t0, 2          # 2
    addi  t2, x0, 2
    bne   t1, t2, fail

# ── SLL: shift left logical (register amount) ──
    addi  t0, x0, 1
    addi  t3, x0, 4
    sll   t1, t0, t3         # 1 << 4 = 16
    addi  t2, x0, 16
    bne   t1, t2, fail

    addi  t3, x0, 0          # shift by 0 → unchanged
    sll   t1, t0, t3
    bne   t1, t0, fail

    addi  t3, x0, 33         # 33 mod 32 = 1 → shift left by 1
    sll   t1, t0, t3         # 1 << 1 = 2
    addi  t2, x0, 2
    bne   t1, t2, fail

# ── SRL: shift right logical (register amount) ──
    lui   t0, 0x80000        # t0 = 0x80000000
    addi  t3, x0, 4
    srl   t1, t0, t3         # 0x08000000
    lui   t2, 0x8000
    bne   t1, t2, fail

    addi  t3, x0, 31
    srl   t1, t0, t3         # 0x00000001
    addi  t2, x0, 1
    bne   t1, t2, fail

# ── SRA: shift right arithmetic (register amount) ──
    lui   t0, 0x80000        # t0 = 0x80000000 (negative)
    addi  t3, x0, 4
    sra   t1, t0, t3         # 0xF8000000
    lui   t2, 0xF8000
    bne   t1, t2, fail

    addi  t3, x0, 31
    sra   t1, t0, t3         # 0xFFFFFFFF
    addi  t2, x0, -1
    bne   t1, t2, fail

    addi  t0, x0, 8          # positive: SRA same as SRL
    addi  t3, x0, 2
    sra   t1, t0, t3         # 2
    addi  t2, x0, 2
    bne   t1, t2, fail

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
