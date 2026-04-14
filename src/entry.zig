const main = @import("main.zig");

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

// TODO: Bootstrap into long mode

/// Called by grub, 32 bit code that bootstraps into long mode before calling into the kernel
export fn _bootstrap() linksection(".bootstrap") callconv(.naked) void {
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
        : [stack_top] "i" (stack_bytes[stack_bytes.len..].ptr),
          // We let the compiler handle the reference to kmain by passing it as an input operand as well.
          [kmain] "X" (&main.kmain),
    );
}
