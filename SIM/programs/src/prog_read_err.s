# prog_read_err.s — AXI Read Error → Load Access Fault Test
#
# Tests path: LW from AXI S0 → RRESP=SLVERR → axi_resp_err=1
#             → mem1_stage bus_err=1, load_access_fault=1
#             → zicsr exception → mcause=5 → handler → x31=1
#
# Runs with tb_soc_bus_err testbench (S0 = error slave, always RRESP=SLVERR).
#
# mcause=5: Load access fault (RISC-V privileged spec §3.1.15)

.section .text
.global _start

_start:
    # Setup exception handler (direct mode — exceptions go to mtvec BASE)
    la    x1, fault_handler
    csrw  mtvec, x1

    # Load from AXI S0 address range → error slave returns RRESP=SLVERR
    lui   x2, 0x20000              # x2 = 0x2000_0000
    lw    x3, 0(x2)                # LW → AXI read → RRESP=SLVERR → load_access_fault

    # Must NOT reach here: exception fires at WB of the LW
    j     fail

fault_handler:
    # Verify mcause = 5 (Load access fault)
    csrr  x10, mcause
    addi  x11, x0, 5
    bne   x10, x11, fail

    # mepc must point to the faulting LW instruction (non-zero)
    csrr  x12, mepc
    beq   x12, x0, fail

    addi  x31, x0, 1               # PASS
    ebreak

fail:
    addi  x31, x0, 0               # FAIL
    ebreak
