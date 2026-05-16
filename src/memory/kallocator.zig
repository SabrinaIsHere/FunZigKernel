//! Basic early memory allocator for the kernel, for now. I plan to implement slab allocation later but for now it's
//! basically just intended to serve paging
//! This also really should not be used for anything that isn't a semipermanent structure, it WILL cause fragmentation
//! NOTE: Just write the fucking slab allocator if this is gonna take so much time
//! TODO: Slab allocation
//! TODO: Integrate with zig allocators

const main = @import("../main.zig");
const Console = main.Console;
const print = Console.print;
const arch = main.arch;
const limine = @import("limine");
const LimineMmapType = limine.MemoryMapType;

/// Error types thrown by this code
pub const MemError = error{
    NoMemoryAvailable,
    EntryNotFound,
    InvalidRequest,
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
pub const MemMapE = struct {
    base: usize = 0,
    length: usize = 0,
    type: MemType = .Free,
    /// Optional field, only relevant if this is an object mapping
    obj_len: u32 = 0,
};

/// Actual memory map buffer.
/// Public so it can be printed during error handling
pub var mmap: [128]MemMapE = [_]MemMapE{.{}} ** 128;
/// How many mmap entries have been initialized
var num_entries: u16 = 0;
/// How much physical memory is available
pub var total_phys_memory: usize = 0;
/// Length in bytes of the kernel binary
pub var kernel_length: usize = 0;
/// Not a source of truth, mostly to avoid allocating the wrong memory early in boot
var k_start: usize = 0;

/// Initialize data structure based on what limine passes
pub fn init() void {
    defer print("Total memory: {any}GB, {any}MB\n", .{ total_phys_memory / 1000000000, (total_phys_memory % 1000000000) / 1000000 });
    // Walk mmap response, filling out internal structure
    const limine_mmap = main.mmap_request.response orelse @panic("Memory map not provided");
    //Console.print("Limine mmap: {any}\n", .{limine_mmap.getEntries()});
    var highest_base = limine_mmap.getEntries()[0];
    for (limine_mmap.getEntries(), 0..limine_mmap.entry_count) |entry, _| {
        if (entry.type != .reserved and highest_base.base < entry.base) highest_base = entry;
        // Ignore anything under 1 MB for obvious reasons
        // NOTE: This will probably break if I try to load modules, I'll need to reference the base also passed
        if (entry.type == LimineMmapType.executable_and_modules) {
            kernel_length = entry.length;
            k_start = arch.physicalToVirtual(entry.base);
            continue;
        }
        if (entry.base < 1000000 or entry.type != LimineMmapType.usable) continue;
        total_phys_memory += entry.length;
        mmap[num_entries] = .{
            .base = arch.physicalToVirtual(entry.base),
            .length = entry.length,
            .type = .Free,
        };
        num_entries += 1;
    }
    total_phys_memory = highest_base.base + highest_base.length;
}

/// Allocate a regian of memory to create the requested object. If one can't be found, throws an error
/// Tries to allocate the memory right above the kernel
/// Zeroes out all memory allocated
pub fn get(obj: type, num: usize, alignment: usize) MemError![*]obj {
    if (num == 0) return MemError.InvalidRequest;
    const len = @sizeOf(obj) * num;
    for (mmap, 0..) |_, i| {
        var entry = &mmap[i];
        // Added to base to get requested alignment
        // Allocating up to the alignment as well because I'm lazy and this is only really for paging
        const align_val: usize = alignment - (entry.base % alignment);
        // Skip if invalid
        if (entry.length < len + align_val or entry.type != .Free) continue;
        const ret_base = entry.base + align_val;
        entry.base += len + align_val;
        entry.length -= len + align_val;
        const prev_entry = if (i > 0) &mmap[i - 1] else null;
        // Add new entry or extend existing
        if (prev_entry != null and prev_entry.?.type == .KData) {
            prev_entry.?.length += len + align_val;
        } else {
            insertEntry(i, .{
                .base = ret_base,
                .length = len + align_val,
                .type = .KData,
            });
            num_entries += 1;
        }
        const retval: [*]obj = @ptrFromInt(ret_base);
        switch (obj) {
            u8 => @memset(retval[0..num], 0),
            else => @memset(retval[0..num], .{}),
        }
        return retval;
    }
    return MemError.NoMemoryAvailable;
}

/// Helper function, inserts a memory map entry at the specified location
fn insertEntry(index: usize, entry: MemMapE) void {
    var i = num_entries;
    if (i >= 127) @panic("kallocator.zig: insertEntry: buffer overflow");
    while (i > index) {
        mmap[i] = .{
            .base = mmap[i - 1].base,
            .length = mmap[i - 1].length,
            .type = mmap[i - 1].type,
        };
        i -= 1;
    }
    mmap[index] = .{
        .base = entry.base,
        .length = entry.length,
        .type = entry.type,
    };
}

/// Mark the region of memory as free
/// base must be the bottom pointer of an entry, ideally just pass back the pointer obtained from get
/// This WILL cause fragmentation, I'll get around to something more permanent later
pub fn free(base: *anyopaque) MemError!void {
    arch.k_panic("kallocator.free doesn't work yet");
    for (mmap) |entry| {
        // TODO: Merge with surrounding entries if possible
        if (entry.base == @intFromPtr(base)) {
            entry.type = .Free;
            return;
        }
    }
    return MemError.EntryNotFound;
}

/// Debugging utility function
pub fn printMmap() void {
    Console.print("Mmap: {any}\n", .{mmap[0..num_entries]});
}
