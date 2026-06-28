# prog_misaligned.s — Misaligned Address Exception Test
#
# Exercises the misaligned detection added to mem1_stage:
#
#   Test 1: LH  at DMEM+1  (byte-odd)   → mcause=4 (Load  Address Misaligned)
#   Test 2: LW  at DMEM+2  (2B-aligned) → mcause=4 (Load  Address Misaligned)
#   Test 3: SH  at DMEM+1  (byte-odd)   → mcause=6 (Store Address Misaligned)
#   Test 4: SW  at DMEM+2  (2B-aligned) → mcause=6 (Store Address Misaligned)
#
# Trap handler:
#   - checks mcause == expected (in x20)
#   - advances mepc by 4 (skip faulting instruction)
#   - increments x21 (pass counter)
#   - mrets back to the instruction after the fault
#
# Pass condition: x21 == 4 (all four faults handled with correct mcause)

.section .text
.global _start

_start:
    la    x1, fault_handler
    csrw  mtvec, x1           # direct mode

    # DMEM aligned base: 0x0001_0000 + 0x10 = 0x0001_0010
    lui   x2, 0x10            # x2 = 0x0001_0000 (lui: 0x10 << 12)
    addi  x2, x2, 0x10       # x2 = 0x0001_0010 (16-byte aligned buffer)

    addi  x21, x0, 0          # x21 = pass counter (incremented in handler)

    # Test 1: LH at addr+1 → Load Address Misaligned (mcause=4)
    addi  x20, x0, 4
    lh    x0, 1(x2)

    # Test 2: LW at addr+2 → Load Address Misaligned (mcause=4)
    addi  x20, x0, 4
    lw    x0, 2(x2)

    # Test 3: SH at addr+1 → Store Address Misaligned (mcause=6)
    addi  x20, x0, 6
    sh    x0, 1(x2)

    # Test 4: SW at addr+2 → Store Address Misaligned (mcause=6)
    addi  x20, x0, 6
    sw    x0, 2(x2)

    # All four faults handled; verify counter
    addi  x22, x0, 4
    bne   x21, x22, fail      # must be exactly 4

    addi  x31, x0, 1          # PASS
    ebreak

# ─── Trap handler ────────────────────────────────────────────────────────────
fault_handler:
    csrr  x3, mcause
    bne   x3, x20, fail       # wrong mcause → FAIL
    csrr  x3, mepc
    beq   x3, x0,  fail       # mepc must be non-zero
    addi  x3, x3, 4           # skip faulting instruction
    csrw  mepc, x3
    addi  x21, x21, 1         # increment pass counter
    mret

fail:
    addi  x31, x0, 0          # FAIL
    ebreak
