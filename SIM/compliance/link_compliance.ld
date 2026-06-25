/* link_compliance.ld — Linker script for RV32I compliance tests
 *
 * Memory map:
 *   IMEM: 0x0000_0000  64KB  code (.text.init, .text, .rodata)
 *   DMEM: 0x0001_0000  64KB  data (.data) — includes test data + signature region
 *
 * Entry point: rvtest_entry_point (defined by RVTEST_CODE_BEGIN macro)
 */

ENTRY(rvtest_entry_point)

MEMORY {
    IMEM (rx)   : ORIGIN = 0x00000000, LENGTH = 512K
    DMEM (rw)   : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
    /* Code sections → IMEM */
    .text.init : { *(.text.init) } > IMEM
    .text      : { *(.text*)     } > IMEM
    .rodata    : { *(.rodata*)   } > IMEM

    /* Data + signature region → DMEM */
    .data      : { *(.data*) *(.sdata*) } > DMEM

    /* BSS (zero-initialized — not explicitly loaded by testbench, DMEM starts at 0) */
    .bss       : { *(.bss*) *(.sbss*) } > DMEM

    /DISCARD/ : { *(.comment) *(.note*) }
}
