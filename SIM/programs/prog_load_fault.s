    .text
    .global _start
_start:

    # Set mtvec = fault_handler (Direct mode)
    la    x1, fault_handler
    csrw  mtvec, x1

    # Load from unmapped address → load_access_fault
    # 0x4000_0000: addr[31:28]=4 → not DMEM/AXI/AHB → fault_sel=1
    # No bus_stall_req: fault is immediate in MEM1, no bus transaction
    lui   x2, 0x40000       # x2 = 0x4000_0000
load_instr:
    lw    x3, 0(x2)         # load_access_fault → mcause=5, mepc=load_instr

    # Handler redirects mepc to pass; reaching here means handler failed
    j     fail

fault_handler:
    # Verify mcause = 5 (load access fault)
    csrr  x20, mcause
    addi  x21, x0, 5
    bne   x20, x21, fail

    # Verify mepc = addr of load_instr
    csrr  x22, mepc
    la    x23, load_instr
    bne   x22, x23, fail

    # Verify mstatus.MIE = 0 during trap (was 0 at reset, trap clears it)
    csrr  x24, mstatus
    andi  x25, x24, 8
    bne   x25, x0, fail

    # Override return to pass (advancing mepc by 4 would return to "j fail")
    la    x26, pass
    csrw  mepc, x26

    mret

pass:
    addi  x31, x0, 1
    ebreak

fail:
    addi  x31, x0, 0
    ebreak
