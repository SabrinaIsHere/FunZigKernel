//! 32 bit code called by grub

const main = @import("main.zig");
const Multiboot = @import("multiboot.zig");
const arch = @import("arch/x86_32/arch.zig");
const Console = arch.Console;

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
        // The stack grows downwards on x86, so we need to point ESP register
        // to one element past the end of `stack_bytes`.
        //
        // Finally, we pass the whole expression as an input operand with the
        // "immediate" constraint to force the compiler to encode this as an
        // absolute address. This prevents the compiler from doing unnecessary
        // extra steps to compute the address at runtime (especially in Debug mode),
        // which could possibly clobber registers that are specified by multiboot
        // to hold special values (e.g. EAX).
        : [stack_top] "i" (stack_bytes_32[stack_bytes_32.len..].ptr),
          // We let the compiler handle the reference to kmain by passing it as an input operand as well.
          [kmain] "X" (&bootstrapMain),
    );
}

pub noinline fn bootstrapMain(multiboot_magic: u32, multiboot_info: *Multiboot.MultibootInfo) linksection(".boottext") callconv(.c) noreturn {
    Console.init();
    Console.print("Entry loaded\n", .{});
    Multiboot.init(multiboot_magic, multiboot_info);
    while (true) {
        asm volatile ("hlt");
    }
}
