    .text
    .global _start
_start:

# DMEM endurance: write 64 different 32-bit patterns to consecutive words,
# then read back and verify each one.
# DMEM base: 0x0001_0000 (lui 0x10 = 0x10000)
# Pattern(i) = byte i replicated: 0x01010101, 0x02020202, ..., 0x3F3F3F3F
# (i=0 gives 0x00000000)

    lui   t0, 0x10           # t0 = DMEM base = 0x0001_0000
    addi  t1, x0, 0          # index = 0
    addi  t2, x0, 64         # limit

# ── Write phase ──
write_loop:
    bge   t1, t2, read_phase
    slli  t3, t1, 2          # byte offset = index * 4
    add   t4, t0, t3         # address = base + offset

    # Pattern = index replicated in 4 bytes
    addi  t5, t1, 0          # t5 = index (0..63, fits in 8 bits)
    slli  t6, t5, 8
    or    t5, t5, t6         # t5 = index | (index << 8)
    slli  t6, t5, 16
    or    t5, t5, t6         # t5 = pattern in all 4 bytes

    sw    t5, 0(t4)
    addi  t1, t1, 1
    j     write_loop

# ── Read and verify phase ──
read_phase:
    addi  t1, x0, 0

read_loop:
    bge   t1, t2, pass
    slli  t3, t1, 2
    add   t4, t0, t3
    lw    t5, 0(t4)          # read back

    # Recompute expected pattern
    addi  t6, t1, 0
    slli  a0, t6, 8
    or    t6, t6, a0
    slli  a0, t6, 16
    or    t6, t6, a0         # t6 = expected

    bne   t5, t6, fail
    addi  t1, t1, 1
    j     read_loop

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
