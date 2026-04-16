//! 32 bit code called by grub

const main = @import("main.zig");
const arch = @import("arch/x86_32/arch.zig");
const GDT = arch.GDT;
const Console = arch.Console;
// If this isn't included neither is the multiboot header. Don't call into any functions
// from 32 bit it'll error out.
const Multiboot = @import("multiboot.zig");

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

/// Called into by _start. Calls hardware initialization functions and jumps to 64 bit
pub noinline fn bootstrapMain(multiboot_magic: u32, multiboot_info: *Multiboot.MultibootInfo) linksection(".boottext") callconv(.c) noreturn {
    _ = multiboot_magic;
    _ = multiboot_info;
    Console.init();
    Console.print("Entry loaded\n", .{});
    // Check for long mode via cpuid
    // Enable A20 line
    // Set up paging
    // Set up gdt
    GDT.init();
    // Jump to 64 bit code
    while (true) {
        asm volatile ("hlt");
    }
}
