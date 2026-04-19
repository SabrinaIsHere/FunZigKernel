// I want to note that I've started and stopped a lot of OSDev projects, and with that in mind,
// I'm documenting this one very heavily so it'll be easy to pick back up in a few months

const IO = @import("io/io.zig");
const Console = IO.Console;
const Serial = @import("drivers/data/serial.zig");
//const arch = @import("arch/arch.zig").arch;
const Multiboot = @import("multiboot.zig");

// We use noinline to make sure it don't get inlined by compiler
// Linked to kmain because I need a predetermined address to long jump to
export fn kmain(multiboot_magic: u32, multiboot_info: *Multiboot.MultibootInfo) linksection(".kmain") callconv(.c) noreturn {
    // Initialize VGA and serial driver
    Console.init();
    Console.print("Kernel loaded\n", .{});
    Multiboot.init(multiboot_magic, multiboot_info);
    // Initialize architecture stuff
    //arch.init();
    // Loop forever as there is nothing to do
    while (true) {
        asm volatile ("hlt");
    }
}
