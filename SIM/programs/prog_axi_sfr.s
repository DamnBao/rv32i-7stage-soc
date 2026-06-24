    .text
    .global _start
_start:

# ── AXI SFR read/write through full SoC pipeline ──
#
# Slave 0 base: 0x2000_0000  (lui 0x20000)
# Slave 1 base: 0x2000_1000  (lui 0x20001)
# Slave 2 base: 0x2000_2000  (lui 0x20002)

    # ── Write 0xDEAD_BEEF to Slave 0 REG0 ──
    lui  t0, 0x20000
    li   t1, 0xDEADBEEF
    sw   t1, 0(t0)

    # ── Read back and verify ──
    lw   t2, 0(t0)
    bne  t2, t1, fail

    # ── Write 0x1234_5678 to Slave 0 REG1 (offset 4) ──
    li   t1, 0x12345678
    sw   t1, 4(t0)
    lw   t2, 4(t0)
    bne  t2, t1, fail

    # ── Write 0xCAFE_BABE to Slave 1 REG0 ──
    lui  t3, 0x20001        # t3 = 0x2000_1000
    li   t4, 0xCAFEBABE
    sw   t4, 0(t3)
    lw   t5, 0(t3)
    bne  t5, t4, fail

    # ── Write 0x5A5A_A5A5 to Slave 2 REG0 ──
    lui  t3, 0x20002        # t3 = 0x2000_2000
    li   t4, 0x5A5AA5A5
    sw   t4, 0(t3)
    lw   t5, 0(t3)
    bne  t5, t4, fail

    # ── Cross-slave isolation: Slave 0 REG0 still 0xDEAD_BEEF ──
    lui  t0, 0x20000
    li   t1, 0xDEADBEEF
    lw   t2, 0(t0)
    bne  t2, t1, fail

    # ── Cross-slave isolation: Slave 0 REG1 still 0x1234_5678 ──
    li   t1, 0x12345678
    lw   t2, 4(t0)
    bne  t2, t1, fail

pass:
    addi x31, x0, 1
    ebreak

fail:
    addi x31, x0, 0
    ebreak
