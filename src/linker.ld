/* The bootloader will look at kernel and start execution at the symbol
   designated as the entry point. */
ENTRY(_start)

KERNEL_LMA = 2M;
/* This may need to be changed later */
KERNEL_VMA = 256M;

/* Tell where the various sections of the object files will be put in the
   final kernel image. */
SECTIONS {
	. = KERNEL_LMA;

    .boottext : {
		KEEP(*(.multiboot))
		bs64.o (.text)
		bs64.o (.rodata)
	}

	.bootdata : {
		bs64.o (.text)
	}

	.bootbss : {
		bs64.o (.bss)
	}

    /* Virtual address of the kernel */
	. = KERNEL_VMA;
    
    .text : AT(ADDR(.text) - KERNEL_VMA) {
		_code = .;
        *(.text)
		*(.rodata)
		. = ALIGN(4K);
    }

    /* Read-write data (initialized) */
    .data : AT(ADDR(.data) - KERNEL_VMA) {
		_data = .;
        *(.data)
		*(.data.rel.ro) /*Idk why it insists on linking this before multiboot if I don't do this*/
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
