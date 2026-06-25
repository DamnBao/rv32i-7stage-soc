// model_test.h — Platform macros for RV32I compliance test (riscv-arch-test old-framework-2.x)
//
// Platform: RV32I+Zicsr 7-stage pipeline SoC, Icarus Verilog simulation
// Memory map: IMEM 0x0000_0000 (64KB), DMEM 0x0001_0000 (64KB)
//
// RVMODEL_HALT   → ebreak (testbench monitors wb_ebreak signal)
// RVMODEL_BOOT   → empty  (FENCE=NOP, no trap handling needed for RV32I tests)
// RVMODEL_DATA_* → begin_signature / end_signature labels in .data section (DMEM)

#ifndef MODEL_TEST_H
#define MODEL_TEST_H

// ── Halt ──────────────────────────────────────────────────────────────────────
#ifndef RVMODEL_HALT
#define RVMODEL_HALT \
    ebreak;
#endif

// ── Boot (no initialization needed for bare-metal RV32I tests) ────────────────
#ifndef RVMODEL_BOOT
#define RVMODEL_BOOT
#endif

// ── Signature region markers (placed in .data section → DMEM 0x10000+) ────────
#ifndef RVMODEL_DATA_BEGIN
#define RVMODEL_DATA_BEGIN \
    .align 4; \
    .global begin_signature; \
    begin_signature:
#endif

#ifndef RVMODEL_DATA_END
#define RVMODEL_DATA_END \
    .align 4; \
    .global end_signature; \
    end_signature:
#endif

// ── Interrupt / IO macros (not needed for base RV32I tests) ──────────────────
#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT
#define RVMODEL_IO_WRITE_STR(_SP, _STR)
#define RVMODEL_IO_ASSERT_GPR_EQ(_SP, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(...)
#define RVMODEL_IO_ASSERT_DFPR_EQ(...)

#endif
