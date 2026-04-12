// I want to note that I've started and stopped a lot of OSDev projects, and with that in mind,
// I'm documenting this one very heavily so it'll be easy to pick back up in a few months

const IO = @import("io/io.zig");
const Console = IO.Console;
const Serial = @import("drivers/data/serial.zig");
const arch = @import("arch/arch.zig").arch;
const Multiboot = @import("multiboot.zig");

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;

// We specify that this function is "naked" to let the compiler know
// not to generate a standard function prologue and epilogue, since
// we don't have a stack yet.
export fn _start() callconv(.naked) noreturn {
    // We use inline assembly to set up the stack before jumping to
    // our kernel entry point.
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
          [kmain] "X" (&kmain),
    );
}

// We use noinline to make sure it don't get inlined by compiler
noinline fn kmain(multiboot_magic: u32, multiboot_info: *Multiboot.MultibootInfo) callconv(.c) noreturn {
    // Initialize VGA and serial driver
    Console.init();
    Console.print("Kernel loaded\n", .{});
    // Initialize architecture stuff
    arch.init();
    Multiboot.init(multiboot_magic, multiboot_info);
    // Loop forever as there is nothing to do
    while (true) {
        asm volatile ("hlt");
    }
}
