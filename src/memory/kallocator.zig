//! I'm rewriting this as a physical page frame buddy allocator
//!
//! TODO: ArrayList memmap

const std = @import("std");
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
    ChildrenUnfree,
};

/// Type of memory for a region. Determines how if the region is likely to be freed or not
/// I don't need all of these types right now but later I will
const MemType = enum {
    Bad,
    Reserved,
    Framebuffer,
    UEFI,
    Bootloader,
    KCode,
    Free,
};

/// Memory map entry, very basic structure
pub const MemMapE = struct {
    /// Base of memory (physical)
    base: usize = 0,
    length: usize = 0,
    type: MemType = .Free,
};

/// Binary tree node
/// OSDev wiki uses a bitmap system for this but personally the binary tree seems a lot more readable
/// and I'm not crazy concerned about efficiency
const Buddy = struct {
    /// Physical base address
    base: usize = 0,
    /// Order 0 = 4096 bytes. Each additional order doubles this
    order: u8 = 0,
    /// Whether or not this buddy is free
    free: bool = true,
    /// Left child
    child1: ?*Buddy = null,
    /// Right child
    child2: ?*Buddy = null,

    /// Get the length of this buddy in bytes
    pub fn getLength(self: *Buddy) usize {
        return 1 << (self.order + 12);
    }

    /// Check if this block has children
    pub fn hasChildren(self: *Buddy) bool {
        return !(self.child1 == null or self.child2 == null);
    }

    /// Uses passed allocator to create child instances
    pub fn split(self: *Buddy) !void {
        self.child1 = &(try al.create(Buddy));
        self.child2 = &(try al.create(Buddy));
        self.child1.* = Buddy{
            .base = self.base,
            .order = self.order - 1,
            .free = self.free,
        };
        self.child2.* = Buddy{
            .base = self.base + std.math.pow(usize, 2, self.order - 1),
            .order = self.order - 1,
            .free = self.free,
        };
    }

    /// Remove children
    /// Errors out if either child is marked unfree
    pub fn consolidate(self: *Buddy) !void {
        if (self.hasChildren()) return MemError.ChildrenUnfree;
        al.destroy(self.child1);
        al.destroy(self.child2);
        self.child1 = null;
        self.child2 = null;
    }

    /// Recursively mark status of children and consolidate with sister block if both are now free
    pub fn markStatus(self: *Buddy, isFree: bool) void {
        if (!self.hasChildren()) {
            self.free = isFree;
            return;
        }
        self.child1.markStatus(isFree);
        self.child2.markStatus(isFree);
    }
};

/// Map of physical memory, doesn't reflect state of allocated memory
/// Public so it can be printed during error handling
pub var mmap: std.ArrayList(MemMapE) = .empty;
/// How much physical memory is available
pub var total_phys_memory: usize = 0;
/// Length in bytes of the kernel binary
pub var kernel_length: usize = 0;
/// Not a source of truth, mostly to avoid allocating the wrong memory early in boot
var k_start: usize = 0;
/// Root of the buddy tree representing the entire system
var buddy_tree_root: Buddy = .{};
/// Binary embedded memory for a zig allocator to use while initializing the buddy allocator
var tmp_buffer: [4096]u8 = 0 ** 4096;
/// First initialized with tmpBuffer, then later with buddy allocated memory
var al: std.mem.Allocator = undefined;

/// Initialize data structure based on what limine passes
pub fn init() void {
    var fba = std.heap.FixedBufferAllocator.init(&tmp_buffer);
    al = fba.allocator();
    // Parse limine memmap
    mmap.init(al, 64);
    defer print(
        "Total memory: {any}GB, {any}MB\n",
        .{ total_phys_memory / 1000000000, (total_phys_memory % 1000000000) / 1000000 },
    );
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
        mmap.append(al, .{
            .base = entry.base,
            .length = entry.length,
            .type = .Free,
        });
    }
    total_phys_memory = highest_base.base + highest_base.length;
    // Initialize buddy allocator
    buddy_tree_root = .{
        .base = 0,
        // NOTE: I'm not sure what the rounding situation is here
        .order = std.math.log(u8, 2, total_phys_memory) - 12,
        .free = true,
    };
    for (mmap.items) |entry| {
        if (entry.type != .Free) markRegionStatus(entry.base, entry.length, true);
    }
}

/// Mark a region as used
/// length: length in bytes of the region (meant to accomodate initialization code)
fn markRegionStatus(base: usize, length: usize, used: bool) void {
    // TODO: Safety check that base is within the block covered by the root node
    _ = used;
    // Round up to page size and find number of pages
    var remaining_pages = (length | 0xFFF) / 4096;
    var curr_buddy = buddy_tree_root;
    // NOTE: Use log to get the order of the block?
    //
    // Assume base is not greater than curr_buddy.base + curr_buddy.getLength()
    while (remaining_pages > 0) {
        // This is a mess and I hate it maybe I should just do a bitmap
        if (curr_buddy.base < base) {
            // Check if splitting would get to the base
            if (curr_buddy.base + curr_buddy.getLength() / 2 < base) {} else {}
        }
    }
}

/// Get a region of memory
/// length is a multiple of pages (4096 bytes)
pub fn get(base: usize, length: usize) MemError![]u8 {
    _ = base;
    _ = length;
    return MemError.NoMemoryAvailable;
}

/// Doesn't take a length argument because it seems safer to always free the smallest region possible
/// Otherwise I can imagine use after free issues
/// NOTE: Should this fail silently? Probably not but idk
pub fn free(base: usize) void {
    _ = base;
}
