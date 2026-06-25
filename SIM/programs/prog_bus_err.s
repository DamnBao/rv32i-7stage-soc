    .text
    .global _start

_start:

# AXI Bus Error → Store Access Fault Test
#
# Tests the path: AXI BRESP=SLVERR → mem1_stage bus_err=1
# → store_access_fault=1 → zicsr exception → mcause=7
#
# This program is designed to run with tb_soc_bus_err testbench,
# which connects an error-injecting AXI slave to S0 (base 0x2000_0000).
# The slave always returns BRESP=SLVERR for any write/read.
#
# Exception flow:
#   1. SW to 0x20000000 → AXI write → BRESP=SLVERR
#   2. mem1_stage: bus_err=1, store_access_fault=1 (propagates to WB)
#   3. zicsr: take_exception=1, mcause=7, mepc=SW_PC
#   4. Handler verifies mcause, sets x31=1, EBREAK

    # Setup exception handler (direct mode)
    la    x1, fault_handler
    csrw  mtvec, x1

    # Store to AXI S0 address range → error slave returns BRESP=SLVERR
    lui   x2, 0x20000
    sw    x0, 0(x2)              # SW to 0x2000_0000 → triggers bus error

    # Must NOT reach here: exception should fire during the store
    j     fail

fault_handler:
    # Verify mcause = 7 (Store/AMO access fault)
    csrr  x10, mcause
    addi  x11, x0, 7
    bne   x10, x11, fail

    # mepc should point to the faulting SW instruction (non-zero)
    csrr  x12, mepc
    beq   x12, x0, fail

    addi  x31, x0, 1             # PASS
    ebreak

fail:
    addi  x31, x0, 0             # FAIL
    ebreak
