    .text
    .global _start
_start:

    lui   x1, 16            # x1 = 0x10000 (DMEM base = 0x0001_0000)

# ── SW + LW: load-use stall detection ──
    addi  x2, x0, 0xAB     # 0xAB = 171
    sw    x2, 0(x1)
    lw    x3, 0(x1)         # pipeline inserts 1 bubble (load-use hazard)
    addi  x4, x3, 0        # x4 = x3 = 171 (x3 available via MEM2 forward after stall)
    addi  x5, x0, 0xAB
    bne   x4, x5, fail

# ── LW negative: sign stays 32-bit ──
    addi  x2, x0, -1       # 0xFFFFFFFF
    sw    x2, 4(x1)
    lw    x3, 4(x1)
    bne   x3, x2, fail

# ── SB + LBU: unsigned zero-extend ──
    addi  x2, x0, -1       # lower 8 bits = 0xFF
    sb    x2, 8(x1)
    lbu   x3, 8(x1)        # zero-extend → x3 = 255
    addi  x4, x0, 255
    bne   x3, x4, fail

# ── SB + LB: signed sign-extend ──
    lb    x5, 8(x1)        # sign-extend 0xFF → x5 = -1
    addi  x6, x0, -1
    bne   x5, x6, fail

# ── SH + LHU: unsigned half ──
    addi  x2, x0, -1       # lower 16 bits = 0xFFFF
    sh    x2, 12(x1)
    lhu   x3, 12(x1)       # zero-extend → x3 = 65535 = 0xFFFF
    lui   x4, 16
    addi  x4, x4, -1      # x4 = 0x10000 - 1 = 0xFFFF
    bne   x3, x4, fail

# ── SH + LH: signed half ──
    lh    x5, 12(x1)       # sign-extend 0xFFFF → x5 = -1
    addi  x6, x0, -1
    bne   x5, x6, fail

# ── Positive byte: LBU vs LB agree ──
    addi  x2, x0, 100      # 100 = 0x64 (positive byte)
    sb    x2, 16(x1)
    lbu   x3, 16(x1)       # zero-extend → 100
    lb    x4, 16(x1)       # sign-extend → 100 (positive, no sign bit)
    bne   x3, x2, fail
    bne   x4, x2, fail

# ── Positive half: LHU vs LH agree ──
    addi  x2, x0, 1000     # 0x3E8 (positive half)
    sh    x2, 20(x1)
    lhu   x3, 20(x1)
    lh    x4, 20(x1)
    bne   x3, x2, fail
    bne   x4, x2, fail

# ── Multiple words: independent offsets ──
    addi  x2, x0, 1
    addi  x3, x0, 2
    addi  x4, x0, 3
    sw    x2, 100(x1)
    sw    x3, 104(x1)
    sw    x4, 108(x1)
    lw    x5, 100(x1)
    lw    x6, 104(x1)
    lw    x7, 108(x1)
    bne   x5, x2, fail
    bne   x6, x3, fail
    bne   x7, x4, fail

# ── No spurious alias: adjacent stores don't overlap ──
    addi  x2, x0, 0x12     # x2 = 18
    addi  x3, x0, 0x34     # x3 = 52
    sw    x2, 200(x1)
    sw    x3, 204(x1)
    lw    x4, 200(x1)      # must still be 18, not corrupted by sw @204
    bne   x4, x2, fail

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
