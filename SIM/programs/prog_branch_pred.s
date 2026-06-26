    .text
    .global _start
_start:

# Branch predictor hit-rate test — 4 patterns.
#
# x8 (s0) is used as a phase sentinel — it is not used by any test
# pattern (all patterns use t0-t6 and a0-a2), so it stays stable
# between sentinels.  The testbench monitors registers[8].
# Sentinels are placed so register-file WB (6 cycles) completes
# before the first branch of the new phase reaches EX (IF1+3).
# Two NOP padding instructions ensure the 7-cycle margin needed.

# ── Phase sentinel: x30 = 1 → Test 1 starting ─────────────────────
    addi x8, x0, 1
# Distance to first branch: li t0, li t1, add, addi, bnez = 5 instr
# → bnez at EX = sentinel_IF1 + 8 > sentinel_WB + 1  ✓

# ── Test 1: Tight backward-branch loop (taken 9×, not-taken 1×) ────
# Predictor warms up after iteration 1; iterations 2-9 use 0-cycle penalty.
# Sum: 10+9+...+1 = 55
    li   t0, 0           # sum = 0
    li   t1, 10          # counter = 10
loop1:
    add  t0, t0, t1
    addi t1, t1, -1
    bnez t1, loop1       # taken 9×, not-taken 1×
    li   t2, 55
    bne  t0, t2, fail

# ── Phase sentinel: x30 = 2 → Test 2 starting ─────────────────────
    addi x8, x0, 2
    nop                  # padding (2 NOPs ensure WB before first branch EX)
    nop

# ── Test 2: JAL target prediction ──────────────────────────────────
# First JAL: BTB miss (2-cycle penalty), BTB learns target.
# Second JAL to same PC: BTB hit, 0-cycle penalty.
    li   t3, 0
    jal  ra, sub1        # BTB learns: PC → sub1
    addi t3, t3, 1       # executed after return
    jal  ra, sub1        # BTB hit: 0-cycle penalty
    addi t3, t3, 1
    li   t2, 2
    bne  t3, t2, fail    # t3 must be 2
    j    test3
sub1:
    jalr x0, ra, 0       # ret

test3:
# ── Phase sentinel: x30 = 3 → Test 3 starting ─────────────────────
    addi x8, x0, 3
# Distance to first branch: li t4, li t5, outer: li t6, addi t4, addi t6, bnez = 6 instr
# → bnez at EX = sentinel_IF1 + 9 > sentinel_WB + 1  ✓  (no NOPs needed)

# ── Test 3: Nested loops ────────────────────────────────────────────
# Outer loop 3×, inner loop 5× — total 15 iterations.
    li   t4, 0           # count
    li   t5, 3           # outer
outer:
    li   t6, 5           # inner
inner:
    addi t4, t4, 1
    addi t6, t6, -1
    bnez t6, inner       # 4 taken + 1 not-taken per outer
    addi t5, t5, -1
    bnez t5, outer       # 2 taken + 1 not-taken
    li   t2, 15
    bne  t4, t2, fail

# ── Phase sentinel: x30 = 4 → Test 4 starting ─────────────────────
    addi x8, x0, 4
    nop                  # padding
    nop

# ── Test 4: Alternating branch (stress hysteresis) ──────────────────
# Alternates taken/not-taken; 2-bit predictor converges to one state
# and misses every other branch → expected ~50% hit rate on this loop.
    li   a0, 0           # result
    li   a1, 8           # iterations
    li   a2, 0           # toggle (0=not-taken path, 1=taken path)
alt_loop:
    bnez a2, alt_taken
    addi a0, a0, 1
    j    alt_end
alt_taken:
    addi a0, a0, 2
alt_end:
    xori a2, a2, 1
    addi a1, a1, -1
    bnez a1, alt_loop
    # 4 not-taken paths (+1) + 4 taken paths (+2) = 4 + 8 = 12
    li   t2, 12
    bne  a0, t2, fail

pass:
    addi x31, x0, 1
    ebreak

fail:
    addi x31, x0, 0
    ebreak
