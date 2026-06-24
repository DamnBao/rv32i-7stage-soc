OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    DMEM (rw) : ORIGIN = 0x00010000, LENGTH = 64K
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text*)
    } > IMEM

    .rodata : { *(.rodata*) } > IMEM

    .data : { *(.data*) } > DMEM
    .bss  : {
        __bss_start = .;
        *(.bss*)
        __bss_end = .;
    } > DMEM
}
