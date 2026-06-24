    .text
    .global _start
_start:

# 7-stage pipeline: IF1→IF2→ID→EX→MEM1→MEM2→WB
# When instr N is in EX: N-1 is in MEM1 (forward=01), N-2 in MEM2 (10), N-3 in WB (11)

# ── MEM1 forward: immediate dependency (0 gap) ──
    addi  x1, x0, 5
    addi  x2, x1, 3        # x1 forwarded from MEM1 → x2 = 8
    addi  x3, x0, 8
    bne   x2, x3, fail

# ── MEM2 forward: 1-instruction gap ──
    addi  x4, x0, 10
    addi  x0, x0, 0        # gap (NOP)
    addi  x6, x4, 5        # x4 forwarded from MEM2 → x6 = 15
    addi  x7, x0, 15
    bne   x6, x7, fail

# ── WB forward: 2-instruction gap ──
    addi  x8, x0, 20
    addi  x0, x0, 0        # gap 1
    addi  x0, x0, 0        # gap 2
    addi  x11, x8, 5       # x8 forwarded from WB → x11 = 25
    addi  x12, x0, 25
    bne   x11, x12, fail

# ── Double forward: rs1 from MEM2, rs2 from MEM1 ──
    addi  x13, x0, 7       # x13=7, cycle N
    addi  x14, x0, 3       # x14=3, cycle N+1
    add   x15, x13, x14   # cycle N+2: x13 from MEM2(01→10), x14 from MEM1(01)
    addi  x16, x0, 10
    bne   x15, x16, fail

# ── Chain: x17→x18→x19, each consecutive ──
    addi  x17, x0, 1
    addi  x18, x17, 1      # x18 = 2 (x17 from MEM1)
    addi  x19, x18, 1      # x19 = 3 (x18 from MEM1)
    addi  x20, x0, 3
    bne   x19, x20, fail

# ── Forward into branch comparator: branch uses forwarded value ──
    addi  x21, x0, 42
    beq   x21, x0, fail    # x21 forwarded to EX → branch comparator
    # If forwarding into branch works, we skip to next test

# ── Forward of load result (MEM2 forward after load-use stall) ──
    lui   x22, 16          # DMEM base
    addi  x23, x0, 99
    sw    x23, 0(x22)
    lw    x24, 0(x22)      # load-use stall: 1 bubble, result at MEM2
    add   x25, x24, x24   # x25 = 99+99 = 198 (x24 from MEM2 after stall)
    addi  x26, x0, 198
    bne   x25, x26, fail

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
