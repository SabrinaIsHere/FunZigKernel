/* The bootloader will look at kernel and start execution at the symbol
   designated as the entry point. */
ENTRY(_bootstrap)

KERNEL_LMA = 0x0;
/* This may need to be changed later */
KERNEL_VMA = 0x2000000;

/* Tell where the various sections of the object files will be put in the
   final kernel image. */
SECTIONS {
    /* Virtual address of the kernel */
    . = KERNEL_LMA;

	.bootstrap : {
        /* We need to specify KEEP to prevent the linker from removing the
           multiboot section. */
        KEEP(*(.multiboot))
		*(.bootstrap)
		/*./entry.s (.text)*/
	}

	. += KERNEL_VMA;

    .text : AT(ADDR(.text) - KERNEL_VMA) {
		_code = .;
		/**(EXCLUDE_FILE(*./entry.s) .text)*/
        *(.text)
		*(.rodata)
		. = ALIGN(4K);
    }

    /* Read-only data. 
    .rodata : AT(ADDR()) {
        *(.rodata)
		. = ALIGN(4K);
    }*/

    /* Read-write data (initialized) */
    .data : AT(ADDR(.data) - KERNEL_VMA) {
		_data = .;
        *(.data)
		. = ALIGN(4K);
    }

	.eh_frame : AT(ADDR(.eh_frame) - KERNEL_VMA) {
		_ehframe = .;
		*(.eh_frame)
		. = ALIGN(4K);
	}

    /* Read-write data (uninitialized i.e. undefined) */
    .bss : AT(ADDR(.bss) - KERNEL_VMA) {
		_bss = .;
        *(COMMON)
        *(.bss)
		. = ALIGN(4K);
    }

    /* The compiler may produce other sections, by default it will put them
       in a segment with the same name. Simply add stuff here as needed. */
}
