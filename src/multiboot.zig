//! Defines the multiboot 2 header and tables for parsing the passed information

const arch = @import("arch/arch.zig").arch;
const IO = @import("io/io.zig");
const Console = IO.Console;

/// Magic number to make the binary mb2 compliant
const MB_HEADER_MAGIC = 0xE85250D6;
/// Architecture flag; Defines this as x86 32 bit
const MB_ARCHITECTURE = 0x0;

pub const MB2_ID_NUMBER: u32 = 0x36d76289;

/// https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Header-layout
const MultibootHeader = packed struct {
    magic: u32 = MB_HEADER_MAGIC,
    architecture: u32 = MB_ARCHITECTURE,
    header_length: u32 = @sizeOf(MultibootHeader),
    checksum: u32,
};

/// Actual header object exported in the compiled binary and linked at .multiboot
export var multiboot_header: MultibootHeader align(4) linksection(".multiboot") = .{
    // Here we are adding magic and flags and ~ to get 1's complement and by adding 1 we get 2's complement
    .checksum = ~@as(u32, (MB_HEADER_MAGIC + MB_ARCHITECTURE + @sizeOf(MultibootHeader))) + 1,
};

/// Information table passed to the kernel by the bootloader
pub const MultibootInfo = packed struct {
    total_size: u32,
    reserved: u32,
    first_tag: MultibootInfoTag,
};

/// Fixed part of mb2 tags. Used to walk the struct, extracting tags I care about
pub const MultibootInfoTag = packed struct {
    type: u32,
    size: u32,
};

/// Walk the info struct and get what I care about
pub fn init(magic: u32, info: *MultibootInfo) void {
    if (magic != MB2_ID_NUMBER) arch.k_panic("Bootloader is not multiboot2 compliant\n");
    Console.print("Info size: {any}\n", .{info.total_size});
    var bytesWalked: u32 = 0;
    var currTag = &info.first_tag;
    while (true) {
        Console.print("Tag: {any}:{any}\n", .{ currTag.size, currTag.type });
        currTag = @ptrFromInt(@intFromPtr(currTag) + currTag.size);
        bytesWalked += currTag.size;
        if (bytesWalked >= info.total_size) break;
    }
}
