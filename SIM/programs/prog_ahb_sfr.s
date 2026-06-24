    .text
    .global _start
_start:

# ── AHB SFR read/write through full SoC (CDC: 1GHz → 500MHz → 1GHz) ──
#
# Slave 0 base: 0x3000_0000  (lui 0x30000)
# Slave 1 base: 0x3000_1000  (lui 0x30001)
# Slave 2 base: 0x3000_2000  (lui 0x30002)

    # ── Write 0xABCD_1234 to Slave 0 REG0 ──
    lui  t0, 0x30000
    li   t1, 0xABCD1234
    sw   t1, 0(t0)

    # ── Read back and verify ──
    lw   t2, 0(t0)
    bne  t2, t1, fail

    # ── Write 0x5566_7788 to Slave 0 REG1 (offset 4) ──
    li   t1, 0x55667788
    sw   t1, 4(t0)
    lw   t2, 4(t0)
    bne  t2, t1, fail

    # ── Write 0x9988_AABB to Slave 1 REG0 ──
    lui  t3, 0x30001        # t3 = 0x3000_1000
    li   t4, 0x9988AABB
    sw   t4, 0(t3)
    lw   t5, 0(t3)
    bne  t5, t4, fail

    # ── Write 0x1122_3344 to Slave 2 REG0 ──
    lui  t3, 0x30002        # t3 = 0x3000_2000
    li   t4, 0x11223344
    sw   t4, 0(t3)
    lw   t5, 0(t3)
    bne  t5, t4, fail

    # ── Cross-slave isolation: Slave 0 REG0 still 0xABCD_1234 ──
    lui  t0, 0x30000
    li   t1, 0xABCD1234
    lw   t2, 0(t0)
    bne  t2, t1, fail

    # ── Cross-slave isolation: Slave 0 REG1 still 0x5566_7788 ──
    li   t1, 0x55667788
    lw   t2, 4(t0)
    bne  t2, t1, fail

pass:
    addi x31, x0, 1
    ebreak

fail:
    addi x31, x0, 0
    ebreak
