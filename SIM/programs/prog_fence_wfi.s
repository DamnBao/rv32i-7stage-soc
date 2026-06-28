# prog_fence_wfi.s — FENCE and WFI treated as NOP for in-order CPU
#
# RISC-V Privileged Spec §3.3.3: "WFI MAY be treated as a NOP."
# For an in-order CPU with no sleep mode this is the correct behaviour.
#
# FENCE (opcode 0001111): treated as NOP in id_decoder — all control
#   signals stay 0 (no mem access, no reg write, no branch).
#
# WFI (0x10500073, SYSTEM/funct3=000/csr_addr=0x105): previously decoded
#   as illegal_instr. Fixed to be NOP (id_decoder.sv: csr_addr==0x105 → ;).
#
# Test sequence:
#   1. Execute FENCE — pipeline must continue (no exception, no stall)
#   2. Execute WFI   — same (no illegal-instruction exception after fix)
#   3. Arithmetic check: x10+x11 == x12 to verify no pipeline corruption
#   4. x31=1, ebreak → PASS
#
# Any illegal-instruction exception jumps to 'fail' → x31=0.

.section .text
.global _start

_start:
    la    x1, ill_handler
    csrw  mtvec, x1           # trap handler for unexpected exceptions

    # Pre-load values for pipeline integrity check
    addi  x10, x0, 42
    addi  x11, x0, 58

    # FENCE: in-order CPU → pure NOP; pipeline flushes only if OoO
    fence

    # WFI: NOP for in-order CPU (fixed in id_decoder.sv)
    wfi

    # Post-NOP arithmetic: must produce correct result
    add   x12, x10, x11       # x12 = 42 + 58 = 100

    addi  x13, x0, 100
    bne   x12, x13, fail      # arithmetic corrupted → FAIL

    addi  x31, x0, 1          # PASS
    ebreak

# ─── Unexpected exception handler (should never be reached) ──────────────────
ill_handler:
    addi  x31, x0, 0          # FAIL — exception should not have fired
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
