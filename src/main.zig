//! Main file, called into by limine in 64 bit

// I want to note that I've started and stopped a lot of OSDev projects, and with that in mind,
// I'm documenting this one very heavily so it'll be easy to pick back up in a few months
// I have never used AI to generate code nor will I ever. I do not give permission for any of this
// to be used as training data

const IO = @import("io/io.zig");
pub const Console = IO.Console;
const Panic = @import("panic.zig");
pub const arch = @import("arch/arch.zig").arch;
const KAllocator = @import("memory/kallocator.zig");
const limine = @import("limine");

export var start_marker: limine.RequestsStartMarker linksection(".limine_requests_start") = .{};
export var end_marker: limine.RequestsEndMarker linksection(".limine_requests_end") = .{};

export var base_revision: limine.BaseRevision linksection(".limine_requests") = .init(3);
pub export var framebuffer_request: limine.FramebufferRequest linksection(".limine_requests") = .{};
pub export var hhdm_request: limine.HhdmRequest linksection(".limine_requests") = .{};
pub export var mmap_request: limine.MemoryMapRequest linksection(".limine_requests") = .{};
pub export var k_address: limine.ExecutableAddressRequest linksection(".limine_requests") = .{};

pub const panic = Panic.panic;

// We use noinline to make sure it don't get inlined by compiler
// Linked to kmain because I need a predetermined address to long jump to
export fn kmain() linksection(".kmain") callconv(.c) noreturn {
    // Initialize VGA and serial driver
    Console.init();
    Console.print("\n\n\nKernel loaded\n", .{});
    // Initialize the ultra basic memory allocator
    KAllocator.init();
    // Initialize architecture stuff
    arch.init();
    while (true) {
        asm volatile ("hlt");
    }
}
