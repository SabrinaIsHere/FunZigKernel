// I want to note that I've started and stopped a lot of OSDev projects, and with that in mind,
// I'm documenting this one very heavily so it'll be easy to pick back up in a few months

const IO = @import("io/io.zig");
const Console = IO.Console;
const arch = @import("arch/arch.zig").arch;
const limine = @import("limine");

export var start_marker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var end_marker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

export var base_revision: limine.BaseRevision linksection(".limine_requests") = .init(3);
export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};

// We use noinline to make sure it don't get inlined by compiler
// Linked to kmain because I need a predetermined address to long jump to
export fn kmain() linksection(".kmain") callconv(.c) noreturn {
    // Initialize VGA and serial driver
    Console.init();
    Console.print("\n\n\nKernel loaded\n", .{});
    // Initialize architecture stuff
    arch.init();
    while (true) {
        asm volatile ("hlt");
    }
}
