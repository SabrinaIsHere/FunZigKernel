//! 32 bit code called by grub

const main = @import("main.zig");
const arch = @import("arch/x86_32/arch.zig");
const GDT = arch.GDT;
const Paging = arch.Paging;
const Console = arch.Console;
// If this isn't included neither is the multiboot header. Don't call into any functions
// from 32 bit it'll error out.
//const Multiboot = @import("multiboot.zig"); // NOTE: Seems like calling into main made it actually compile the 64 bit side of this

var stack_bytes_32: [16 * 1024]u8 align(16) linksection(".bootbss") = undefined;

// TODO: Bootstrap into long mode

/// Called by grub, 32 bit code that bootstraps into long mode before calling into the kernel
export fn _start() linksection(".boottext") callconv(.naked) void {
    asm volatile (
        \\ movl %[stack_top], %%esp
        \\ movl %%esp, %%ebp
        // Reset EFLAGS
        \\ pushl $0
        \\ popf
        \\ pushl %%ebx
        \\ pushl %%eax
        \\ call %[kmain:P]
        :
        : [stack_top] "i" (stack_bytes_32[stack_bytes_32.len..].ptr),
          [kmain] "X" (&bootstrapMain),
    );
}

const entry_msg: []const u8 linksection(".bootrodata") = "Entry loaded\n";

pub extern fn farJump() callconv(.Naked) void;

/// Called into by _start. Calls hardware initialization functions and jumps to 64 bit
pub noinline fn bootstrapMain(multiboot_magic: u32, multiboot_info: *void) linksection(".boottext") callconv(.c) noreturn {
    //Console.init(); // This prints but doesn't error out
    //Console.printString(entry_msg);
    // Check for long mode
    // Enable A20 line
    //arch.enableA20(); // Qemu does this for me
    // Set up paging
    Paging.init();
    // Hardware stuff
    arch.setLMBit();
    arch.reloadSegmentRegs();
    // Set up gdt
    //GDT.init();
    // Far jump to 64 bit kmain
    //main.kmain(multiboot_magic, multiboot_info);
    asm volatile (
        \\ pushl %[mbi]
        \\ pushl %[magic]
        \\ jmp farJump
        // BUG: This is registered as '(bad)' in gdb. Compiles but isn't valid? Hard coded address doesn't work either
        //\\ ljmp $GDT + 0x8, %[kmain]
        //\\ ljmpl $2098708, %[kmain]
        :
        : [mbi] "m" (multiboot_info),
          [magic] "m" (multiboot_magic),
          //[kmain] "X" (&main.kmain),
    );
    // Force the compiler to compile this function
    //main.kmain(multiboot_magic, multiboot_info);
    while (true) {
        asm volatile ("hlt");
    }
}
