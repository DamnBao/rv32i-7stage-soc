    .text
    .global _start
_start:
    # Minimal test: SW to AXI, then LW back, then EBREAK
    lui  t0, 0x20000
    li   t1, 0x12345678
    sw   t1, 0(t0)         # AXI write (stalls pipeline)
    lw   t2, 0(t0)         # AXI read (stalls pipeline)
    # Store results to DMEM for inspection
    lui  t3, 0x10010        # DMEM addr 0x10010 = 0x1001_0000? No...
    # DMEM base is 0x0001_0000. lui 0x10 = 0x10000. But we need 0x00010000.
    # lui 0x10 gives 0x10000, which is 65536 = 0x0001_0000 ✓
    lui  t3, 0x10           # t3 = 0x0001_0000 (DMEM base)
    sw   t2, 0(t3)          # store read-back value at DMEM[0]
    sw   t1, 4(t3)          # store expected value at DMEM[1]
    # Now check
    bne  t2, t1, fail

pass:
    addi x31, x0, 1
    ebreak

fail:
    addi x31, x0, 0
    ebreak
