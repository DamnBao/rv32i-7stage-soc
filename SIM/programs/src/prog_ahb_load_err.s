# prog_ahb_load_err.s — AHB Read Error → Load Access Fault Test
#
# Tests path: LW from AHB S0 → HRESP=ERROR (2-cycle AHB protocol)
#             → resp_fifo[32]=1 → mem1_stage bus_err=1
#             → load_access_fault=1 → zicsr exception → mcause=5
#
# AHB S0 base: 0x3000_0000  (addr[31:28]=3, addr[27:12]=0)
# mcause=5: Load access fault (RISC-V privileged spec §3.1.15)

.section .text
.global _start

_start:
    la    x1, fault_handler
    csrw  mtvec, x1

    lui   x2, 0x30000              # x2 = 0x3000_0000 (AHB S0)
    lw    x3, 0(x2)                # LW → AHB read → HRESP=ERROR → load_access_fault

    j     fail                     # must NOT reach here

fault_handler:
    csrr  x10, mcause
    addi  x11, x0, 5
    bne   x10, x11, fail           # mcause must be 5 (Load access fault)

    csrr  x12, mepc
    beq   x12, x0, fail            # mepc must be non-zero

    addi  x31, x0, 1               # PASS
    ebreak

fail:
    addi  x31, x0, 0               # FAIL
    ebreak
