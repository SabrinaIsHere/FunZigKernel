//! Defines the multiboot 2 header and tables for parsing the passed information

const arch = @import("arch/arch.zig").arch;
const IO = @import("io/io.zig");
const Console = IO.Console;

/// Magic number to make the binary mb2 compliant
const MB_HEADER_MAGIC = 0xE85250D6;
/// Architecture flag; Defines this as x86 32 bit
const MB_ARCHITECTURE = 0x0;

pub const MB2_ID_NUMBER: u32 = 0x36d76289;

const HeaderTagType = enum(u16) {
    END,
    INFORMATION_REQUEST,
};

const InfoTagType = enum(u32) {
    END,
    MMAP = 6,
    LOAD_BASE_ADDR = 21,
};

/// https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Header-layout
const MultibootHeader = extern struct {
    magic: u32 = MB_HEADER_MAGIC,
    architecture: u32 = MB_ARCHITECTURE,
    header_length: u32 = @sizeOf(MultibootHeader),
    checksum: u32,
    //info_tag: MultibootHeaderTagInfoRequest = MultibootHeaderTagInfoRequest{},
    end_tag: MultibootHeaderTagEnd = MultibootHeaderTagEnd{},
};

const MultibootHeaderTagInfoRequest = extern struct {
    type: HeaderTagType = HeaderTagType.INFORMATION_REQUEST,
    flags: u16 = 0,
    size: u32 = @sizeOf(MultibootHeaderTagInfoRequest),
    // It  really does not like ending on a u32 for whatever reason
    simple_mmap_request: u32 = 4,
    mmap_request: u32 = 6,
    framebuffer_request: u32 = 8,
    //acpi_old_request: u32 = 14,
    acpi_new_request: u32 = 15,
};

const MultibootHeaderTagEnd = extern struct {
    type: u32 = @intFromEnum(HeaderTagType.END),
    size: u32 = @sizeOf(MultibootHeaderTagEnd),
};

/// Actual header object exported in the compiled binary and linked at .multiboot
export var multiboot_header: MultibootHeader align(8) linksection(".multiboot") = .{
    // Here we are adding magic and flags and ~ to get 1's complement and by adding 1 we get 2's complement
    .checksum = ~@as(u32, (MB_HEADER_MAGIC + MB_ARCHITECTURE + @sizeOf(MultibootHeader))) + 1,
};

/// Information table passed to the kernel by the bootloader
pub const MultibootInfo = extern struct {
    total_size: u32,
    reserved: u32 = 0,
};

/// Fixed part of mb2 tags. Used to walk the struct, extracting tags I care about
pub const MultibootInfoTag = extern struct {
    type: InfoTagType,
    size: u32,
    val: u32,
    padding: u32,

    pub fn print(self: *MultibootInfoTag) void {
        Console.print("Tag: 0x{X}: {any}: {any} bytes\n", .{ @intFromPtr(self), self.type, self.size });
    }
};

/// Walk the info struct and get what I care about
pub fn init(magic: u32, info: *MultibootInfo) void {
    if (magic != MB2_ID_NUMBER) arch.k_panic("Bootloader is not multiboot2 compliant\n");
    if (@intFromPtr(info) & 7 != 0) arch.k_panic("MBI is not 8-byte aligned.\n");
    Console.print("MBI: 0x{X}:0x{X} bytes\n", .{ @intFromPtr(info), info.total_size });
    var bytesWalked: u32 = @sizeOf(MultibootInfo);
    const offset: usize = @intFromPtr(info);
    // NOTE: This is probably only going to work if I do a many item pointer, painful as that is
    var curr_tag: *MultibootInfoTag = @ptrFromInt(offset + bytesWalked);

    // TODO: Get rid of this
    Console.print("Test\n", .{});
    arch.enableInterrupts();
    const tst: *MultibootInfoTag = @ptrFromInt(offset + 24);
    //tst.print();
    _ = tst;

    outer: while (true) {
        curr_tag.print();
        switch (curr_tag.type) {
            InfoTagType.END => {
                if (curr_tag.size != 8) arch.k_panic("Invalid end tag: size differs from expectation\n");
                Console.print("EOS\n", .{});
                break :outer;
            },
            InfoTagType.LOAD_BASE_ADDR => {
                //const base_addr: *u32 = @ptrFromInt(offset + bytesWalked + 8);
                Console.print("Load base addr: 0x{X}\n", .{curr_tag.val});
                //bytesWalked += 4;
            },
            else => {
                curr_tag.print();
                break;
            },
        }
        //bytesWalked += currTag.size;
        bytesWalked += (curr_tag.size + 7) & ~@as(u32, 7); // Ensure 8 byte alignment (not that it's helping)
        if (bytesWalked & 7 != 0) Console.print("Error: not 8-byte aligned ({any})\n", .{bytesWalked});
        // Just in case mbi is mangled and there's no end tag
        if (bytesWalked >= info.total_size) break;
        Console.print("Tag Offset: {any}\n", .{bytesWalked});
        curr_tag = @ptrFromInt(offset + bytesWalked);
    }
}
