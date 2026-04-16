//! Defines the multiboot 2 header and tables for parsing the passed information

const arch = @import("arch/arch.zig").arch;
const IO = @import("io/io.zig");
const Console = IO.Console;

/// Magic number to make the binary mb2 compliant
const MB_HEADER_MAGIC = 0xE85250D6;
//const MB_HEADER_MAGIC = 0xD65052E8;
/// Architecture flag; Defines this as x86 32 bit
const MB_ARCHITECTURE = 0x0;

pub const MB2_ID_NUMBER: u32 = 0x36d76289;

const HeaderTagType = enum(u16) {
    END,
    INFORMATION_REQUEST,
    FLAGS = 4,
    FRAMEBUFFER = 5,
};

const InfoTagType = enum(u32) {
    END,
    BOOT_CMD_LINE,
    BOOT_LOADER_NAME,
    MODULES,
    BASIC_MEMINFO,
    BOOTDEV,
    MMAP,
    VBE,
    FRAMEBUFFER,
    ELF_SECTIONS,
    APM,
    EFI32,
    EFI64,
    SMBIOS,
    ACPI_OLD,
    ACPI_NEW,
    NETWORK,
    EFI_MMAP,
    EFI_BS,
    EFI32_IH,
    EFI64_IH,
    LOAD_BASE_ADDR,
};

/// https://www.gnu.org/software/grub/manual/multiboot/multiboot.html#Header-layout
const MultibootHeader = extern struct {
    magic: u32 = MB_HEADER_MAGIC,
    architecture: u32 = MB_ARCHITECTURE,
    header_length: u32 = @sizeOf(MultibootHeader),
    checksum: u32,
    //info_tag: MultibootHeaderTagInfoRequest = MultibootHeaderTagInfoRequest{},
    flags_tag: MultibootHeaderTagFlags = MultibootHeaderTagFlags{},
    framebuffer_tag: MultibootHeaderTagFramebuffer = MultibootHeaderTagFramebuffer{},
    end_tag: MultibootHeaderTagEnd = MultibootHeaderTagEnd{},
};

/// Tag in the mb header at the beginning of the kernel file
/// Requests info from the bootloader
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

const MultibootHeaderTagFlags = extern struct {
    type: HeaderTagType = HeaderTagType.FLAGS,
    flags: u16 = 0,
    size: u32 = @sizeOf(MultibootHeaderTagFlags),
    console_flags: u32 = 1,
    padding: u32 = 0,
};

/// Tag in the mb header at the beginning of the kernel file
/// Specifies data about the framebuffer
const MultibootHeaderTagFramebuffer = extern struct {
    type: HeaderTagType = HeaderTagType.FRAMEBUFFER,
    flags: u16 = 0,
    size: u32 = @sizeOf(MultibootHeaderTagFramebuffer),
    width: u32 = 0,
    height: u32 = 0,
    depth: u32 = 0,
    padding: u32 = 0,
};

/// Tag in the mb header at the beginning of the kernel file
/// Ends the tag structure
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
pub const MultibootInfoTag = packed struct(u64) {
    type: InfoTagType,
    size: u32,

    pub fn print(self: *MultibootInfoTag) void {
        Console.print("Tag: 0x{X}: {any}: {any} bytes\n", .{ @intFromPtr(self), self.type, self.size });
    }
};

/// Walk the info struct and get what I care about
pub fn init(magic: u32, info: *MultibootInfo) void {
    if (magic != MB2_ID_NUMBER) arch.k_panic("Bootloader is not multiboot2 compliant\n");
    if (@intFromPtr(info) & 7 != 0) arch.k_panic("MBI is not 8-byte aligned.\n");
    Console.print("MBI: 0x{X}:0x{X} bytes\n", .{ @intFromPtr(info), info.total_size });
    var tag_offset: u32 = @sizeOf(MultibootInfo);
    const mbi_offset: usize = @intFromPtr(info);
    const tags: [*]align(8) MultibootInfoTag align(8) = @ptrFromInt(mbi_offset + tag_offset);
    var curr_tag: *MultibootInfoTag = &tags[0];

    while (curr_tag.type != InfoTagType.END) {
        if (tag_offset & 7 != 0) arch.k_panic("Error: tag is not 8-byte aligned\n");
        curr_tag.print();
        tag_offset += (curr_tag.size + 7) & ~@as(u32, 7);
        curr_tag = &tags[(tag_offset / 8) - 1];
    }
}
