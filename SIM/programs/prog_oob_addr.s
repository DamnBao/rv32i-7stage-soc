# prog_oob_addr.s — Out-of-Range Address → Load/Store Access Fault
#
# Address 0x4000_0000 matches none of the memory map regions:
#   IMEM  0x0000_0000–0x0000_FFFF   (addr[31:16] == 0x0000)
#   DMEM  0x0001_0000–0x0001_FFFF   (addr[31:16] == 0x0001)
#   PLIC  0x0C00_0000–0x0CFF_FFFF   (addr[31:24] == 0x0C)
#   AXI   0x2000_0000–0x2FFF_FFFF   (addr[31:28] == 0x2)
#   AHB   0x3000_0000–0x3FFF_FFFF   (addr[31:28] == 0x3)
# → fault_sel=1 → unmapped_fault → load_access_fault/store_access_fault
#
# Test 1: LW  at 0x4000_0000 → mcause=5 (Load Access Fault)
# Test 2: SW  at 0x4000_0000 → mcause=7 (Store/AMO Access Fault)
#
# Trap handler: check mcause == x20, advance mepc+4, increment x21
# Pass condition: x21 == 2 (both faults handled with correct mcause)

.section .text
.global _start

_start:
    la    x1, fault_handler
    csrw  mtvec, x1           # direct mode

    lui   x2, 0x40000         # x2 = 0x4000_0000 (unmapped)
    addi  x21, x0, 0          # x21 = pass counter

    # Test 1: LW at unmapped address → Load Access Fault (mcause=5)
    addi  x20, x0, 5
    lw    x0, 0(x2)

    # Test 2: SW at unmapped address → Store Access Fault (mcause=7)
    addi  x20, x0, 7
    sw    x0, 0(x2)

    # Verify counter
    addi  x22, x0, 2
    bne   x21, x22, fail      # must have handled exactly 2 faults

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
