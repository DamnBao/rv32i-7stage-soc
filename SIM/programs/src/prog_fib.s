    .text
    .global _start
_start:

# Fibonacci(10) — representative real-compute workload.
#
# Phase 1 (fib_gen): generate fib[0..9] and store to DMEM.
#   fib[i] = fib[i-1] + fib[i-2]  — 8 iterations (i = 2..9)
#   Load-use stall pattern:  lw t3,-8(s1)  then  add t4,t2,t3
#   → 1 stall per iteration × 8 = 8 load-use stalls
#
# Phase 2 (sum_loop): load each element and accumulate.
#   Intentional load-use:  lw t2,0(s1)  then  add t0,t0,t2
#   → 1 stall per iteration × 10 = 10 load-use stalls
#
# Expected totals: 18 load-use stall cycles, 20 branch events.
# fib[9] = 34;  sum(fib[0..9]) = 0+1+1+2+3+5+8+13+21+34 = 88
#
# DMEM layout: fib[i] at DMEM_BASE + i*4  (base = 0x0001_0000)

    # ── Store fib[0] = 0 and fib[1] = 1 ──────────────────────────
    lui  s0, 0x10            # s0 = 0x0001_0000 (DMEM base)
    sw   zero, 0(s0)         # fib[0] = 0
    li   t0, 1
    sw   t0, 4(s0)           # fib[1] = 1

    # ── fib_gen: generate fib[2..9] ───────────────────────────────
    li   t1, 2               # loop index i = 2
    addi s1, s0, 8           # s1 → fib[2]
    li   t5, 10              # loop bound
fib_gen:
    lw   t2, -4(s1)          # t2 = fib[i-1]
    lw   t3, -8(s1)          # t3 = fib[i-2]  (no stall: t3 ≠ t2)
    add  t4, t2, t3          # t4 = fib[i]    ← LOAD-USE STALL on t3
    sw   t4, 0(s1)
    addi s1, s1, 4
    addi t1, t1, 1
    blt  t1, t5, fib_gen     # loop while i < 10  (taken 7×, exit 1×)

    # ── Verify fib[9] == 34 ───────────────────────────────────────
    lw   t6, 36(s0)          # offset = 9 * 4 = 36
    li   a0, 34
    bne  t6, a0, fail

    # ── sum_loop: sum fib[0..9]; immediate use after each load ────
    li   t0, 0               # accumulator
    li   t1, 0               # index i = 0
    addi s1, s0, 0           # s1 → fib[0]  (= mv s1, s0)
    li   t3, 10              # loop bound
sum_loop:
    lw   t2, 0(s1)           # t2 = fib[i]
    add  t0, t0, t2          # sum += t2    ← LOAD-USE STALL on t2
    addi s1, s1, 4
    addi t1, t1, 1
    blt  t1, t3, sum_loop    # loop while i < 10  (taken 9×, exit 1×)

    # ── Verify sum == 88 ──────────────────────────────────────────
    li   a0, 88
    bne  t0, a0, fail

pass:
    addi x31, x0, 1
    ebreak

fail:
    addi x31, x0, 0
    ebreak
