    .text
    .global _start
_start:

# ── BEQ: taken ──
    addi  x1, x0, 5
    addi  x2, x0, 5
    beq   x1, x2, beq_ok   # x1==x2 → taken
    jal   x0, fail
beq_ok:

# ── BEQ: not taken ──
    addi  x3, x0, 6
    beq   x1, x3, fail     # x1!=x3 → not taken

# ── BNE: taken ──
    bne   x1, x3, bne_ok   # x1!=x3 → taken
    jal   x0, fail
bne_ok:

# ── BNE: not taken ──
    bne   x1, x2, fail     # x1==x2 → not taken

# ── BLT: signed, taken ──
    addi  x4, x0, -1       # x4 = -1
    blt   x4, x0, blt_ok   # -1 < 0 → taken
    jal   x0, fail
blt_ok:

# ── BLT: signed, not taken (unsigned large < 0 is wrong, but 0 < -1 is false signed) ──
    blt   x0, x4, fail     # 0 < -1 (signed) → NOT taken

# ── BGE: signed, taken ──
    bge   x0, x4, bge_ok   # 0 >= -1 → taken
    jal   x0, fail
bge_ok:

# ── BGE: not taken ──
    bge   x4, x0, fail     # -1 >= 0 → NOT taken

# ── BGE: equal case ──
    bge   x1, x2, bge_eq   # 5 >= 5 → taken
    jal   x0, fail
bge_eq:

# ── BLTU: unsigned, taken ──
    addi  x5, x0, 1
    # x4 = -1 = 0xFFFFFFFF (large unsigned)
    bltu  x5, x4, bltu_ok  # 1 <u 0xFFFF_FFFF → taken
    jal   x0, fail
bltu_ok:

# ── BLTU: not taken ──
    bltu  x4, x5, fail     # 0xFFFFFFFF <u 1 → NOT taken

# ── BGEU: taken ──
    bgeu  x4, x5, bgeu_ok  # 0xFFFFFFFF >=u 1 → taken
    jal   x0, fail
bgeu_ok:

# ── BGEU: equal ──
    bgeu  x1, x2, bgeu_eq  # 5 >=u 5 → taken
    jal   x0, fail
bgeu_eq:

# ── BGEU: not taken ──
    bgeu  x5, x4, fail     # 1 >=u 0xFFFFFFFF → NOT taken

# ── JAL: jump and link ──
    jal   x10, jal_target  # x10 = PC+4, jump forward
    jal   x0, fail         # should be skipped
jal_target:
    beq   x10, x0, fail    # x10 must be non-zero (return address)

# ── JAL: x0 as rd (pure jump) ──
    jal   x0, jal0_land
    jal   x0, fail
jal0_land:

# ── Backward branch: loop 5 times ──
    addi  x11, x0, 5       # counter = 5
    addi  x12, x0, 0       # accumulator = 0
loop:
    addi  x12, x12, 1      # accumulator++
    addi  x11, x11, -1    # counter--
    bne   x11, x0, loop   # loop while counter != 0
    addi  x13, x0, 5
    bne   x12, x13, fail   # accumulator must be 5

# ── JALR: jump to computed address ──
    auipc x14, 0            # x14 = PC of this auipc
    addi  x14, x14, 16    # x14 = auipc_addr + 16 = jalr_target
    jalr  x15, x14, 0     # jump to x14, x15 = auipc_addr + 12 (next PC after jalr)
    jal   x0, fail         # auipc_addr + 12: SKIPPED by jalr
jalr_target:               # auipc_addr + 16
    beq   x15, x0, fail    # x15 must be non-zero (link address)

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
