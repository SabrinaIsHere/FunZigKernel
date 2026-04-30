//! Basic early memory allocator for the kernel, for now. I plan to implement slab allocation later but for now it's
//! basically just intended to serve paging
//! This also really should not be used for anything that isn't a semipermanent structure, it WILL cause fragmentation

const main = @import("../main.zig");
const Console = main.Console;
const arch = main.arch;
const limine = @import("limine");
const LimineMmapType = limine.MemoryMapType;

/// Error types thrown by this code
pub const MemError = error{
    NoMemoryAvailable,
    EntryNotFound,
};

/// Type of memory for a region. Determines how if the region is likely to be freed or not
/// I don't need all of these types right now but later I will
const MemType = enum {
    Bad,
    Reserved,
    Framebuffer,
    UEFI,
    Bootloader,
    KData,
    KCode,
    UData,
    UCode,
    Object,
    Free,
};

/// Memory map entry, very basic structure
const MemMapE = struct {
    phys_base: usize = 0,
    length: usize = 0,
    type: MemType = .Free,
    /// Optional field, only relevant if this is an object mapping
    obj_len: u32 = 0,
};

/// Actual memory map buffer.
var mmap: [128]MemMapE = [_]MemMapE{.{}} ** 128;
/// How many mmap entries have been initialized
var num_entries: u8 = 0;
/// How much physical memory is available
var total_phys_memory: usize = 0;

/// Initialize data structure based on what limine passes
pub fn init() void {
    defer Console.print("Memory: {any} KiB\n", .{total_phys_memory / 1024});
    // Walk mmap response, filling out internal structure
    const limine_mmap = main.mmap_request.response orelse @panic("Memory map not provided");
    for (limine_mmap.getEntries(), 0..limine_mmap.entry_count) |entry, _| {
        mmap[num_entries] = .{
            .phys_base = entry.base,
            .length = entry.length,
            .type = switch (entry.type) {
                LimineMmapType.usable => .Free,
                LimineMmapType.executable_and_modules => .KCode,
                else => .Reserved,
            },
        };
        total_phys_memory += entry.length;
        num_entries += 1;
    }
}

/// Allocate a regian of memory to create the requested object. If one can't be found, throws an error
/// Tries to allocate the memory right above the kernel
pub fn get(len: usize) MemError!*anyopaque {
    for (mmap) |entry| {
        if (entry.type == .Free and entry.len > len) {
            const ret_base = entry.base;
            entry.base += len;
            mmap[num_entries] = .{
                .phys_base = ret_base,
                .length = len,
                .type = .KData,
            };
            num_entries += 1;
            return @ptrFromInt(arch.physicalToVirtual(entry.phys_base));
        }
    }
}

/// Mark the region of memory as free
/// base must be the bottom pointer of an entry, ideally just pass back the pointer obtained from get
/// This WILL cause fragmentation, I'll get around to something more permanent later
pub fn free(base: *anyopaque) MemError!void {
    for (mmap) |entry| {
        if (entry.base == @intFromPtr(base)) {
            entry.type = .Free;
        }
    }
}
