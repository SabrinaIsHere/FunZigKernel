//! I'm rewriting this as a physical page frame buddy allocator
//!
//! TODO: ArrayList memmap
//! TODO: Maximum order, arraylist of roots
//! TODO: If I ever come back to this file I need to reimplement with an array rather than pointers

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
    /// Parent (for consolidation)
    /// should only be null for the root
    parent: ?*Buddy = null,
    /// Left child
    child1: ?*Buddy = null,
    /// Right child
    child2: ?*Buddy = null,

    /// Get the length of this buddy in bytes
    pub fn getLength(self: *Buddy) usize {
        return @as(usize, 1) << @truncate(self.order + 12);
    }

    /// Check if this block has children
    pub fn hasChildren(self: *Buddy) bool {
        return !(self.child1 == null or self.child2 == null);
    }

    /// Are both children free
    pub fn childrenFree(self: *Buddy) bool {
        return self.hasChildren() and self.child1.?.free and self.child2.?.free;
    }

    /// Uses passed allocator to create child instances
    pub fn split(self: *Buddy) !void {
        if (self.hasChildren()) return MemError.ChildrenUnfree;
        if (self.order == 0) return MemError.InvalidRequest;
        self.child1 = (try al.create(Buddy));
        self.child2 = (try al.create(Buddy));
        self.child1.?.* = Buddy{
            .base = self.base,
            .order = self.order - 1,
            .free = self.free,
            .parent = self,
        };
        self.child2.?.* = Buddy{
            .base = self.base + std.math.pow(usize, 2, self.order - 1),
            .order = self.order - 1,
            .free = self.free,
            .parent = self,
        };
    }

    /// Remove children
    /// Errors out if either child is marked unfree
    pub fn consolidate(self: *Buddy) !void {
        if (!self.hasChildren()) return;
        if (!self.childrenFree()) return MemError.ChildrenUnfree;
        al.destroy(self.child1.?);
        al.destroy(self.child2.?);
        self.child1 = null;
        self.child2 = null;
        if (self.parent) |p| p.consolidate() catch {};
    }

    /// Recursively mark status of children and consolidate with sister block if both are now free
    pub fn markStatus(self: *Buddy, isFree: bool) void {
        if (!self.hasChildren()) {
            self.free = isFree;
            if (self.parent) |p| p.consolidate() catch {};
            return;
        }
        self.child1.?.markStatus(isFree);
        self.child2.?.markStatus(isFree);
        // consolidate() checks if this is allowed
        if (self.parent) |p| p.consolidate() catch {};
    }

    /// Recursively search children for a free block of the given order
    pub fn search(self: *Buddy, order: u8) ?*Buddy {
        if (!self.free) return null;
        if (self.order == order) return self;
        if (self.order < order) return null;
        if (!self.hasChildren()) self.split() catch @panic("kallocator: search: failed allocation");
        if (self.child1) |c| if (c.search(order)) |retval| return retval;
        if (self.child2) |c| if (c.search(order)) |retval| return retval;
        return null;
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
var tmp_buffer: [4096]u8 = [_]u8{0} ** 4096;
/// First initialized with tmpBuffer, then later with buddy allocated memory
var al: std.mem.Allocator = undefined;

/// Initialize data structure based on what limine passes
pub fn init() void {
    // TODO: Pass errors up (not doing it rn bc I'm expecting lots of bugs)
    var fba = std.heap.FixedBufferAllocator.init(&tmp_buffer);
    al = fba.allocator();
    // Parse limine memmap
    mmap = std.ArrayList(MemMapE).initCapacity(al, 64) catch @panic("kallocator: init(): can't init mmap");
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
        }) catch @panic("kallocator: init(): can't append entry");
    }
    total_phys_memory = highest_base.base + highest_base.length;
    // Initialize buddy allocator
    buddy_tree_root = .{
        .base = 0,
        .order = @truncate(std.math.log2(total_phys_memory) - 12),
        .free = true,
    };
    for (mmap.items) |entry| {
        if (entry.type != .Free) markRegionStatus(entry.base, entry.length, true);
    }
}

/// Mark a region as used
/// length: length in bytes of the region (meant to accomodate initialization code)
/// I'm aware this isn't the most efficient implementation but it's really not meant to run other than during initialization
fn markRegionStatus(base: usize, length: usize, used: bool) void {
    // Assume base is within the range of the block
    // TODO: Safety check that base is within the block covered by the root node
    // NOTE: Maybe I just mark every page individually and have an algorithm to handle that while recombining?
    // That's slower but if I'm only using it for initialization it wouldn't matter
    const remaining_pages = (length | 0xFFF) / 4096;
    for (0..remaining_pages) |i| markPageStatus(base + (i * 4096), used);
}

/// Mark the status a page, rounds base down. Handles splitting and merging
fn markPageStatus(base: usize, used: bool) void {
    const rounded_base = base & 0xFFFFFFFFFFFFF000;
    var root = &buddy_tree_root;
    while (root.order != 0) {
        root.split() catch |err| {
            if (err != MemError.ChildrenUnfree) @panic("markPageStatus: Not enough memory");
        };
        // Determine if address is in the higher or lower block and reassign accordingly
        if (rounded_base < root.base + (root.getLength() / 2)) {
            root = root.child1.?;
        } else {
            root = root.child2.?;
        }
    }
    root.markStatus(used);
}

/// Get a region of memory
/// Length = amount of memory to allocate. Gives closest exceeding match
pub fn get(length: usize) MemError![]u8 {
    var order: u8 = @truncate(std.math.log2(length));
    order = if (order < 12) 0 else order - 12;
    if (buddy_tree_root.search(order)) |b| return @as([*]u8, @ptrFromInt(b.base))[0..b.getLength()];
    return MemError.NoMemoryAvailable;
}

/// Doesn't take an order because the order is implied by the base
pub fn free(base: usize) void {
    // TODO: Safety checks
    var cur_buddy = buddy_tree_root;
    while (true) {
        if (cur_buddy.base == base) {
            cur_buddy.markStatus(true);
            return;
        }
        if (base < cur_buddy.base + (cur_buddy.getLength() / 2)) {
            if (cur_buddy.child1) |c| cur_buddy = c else return MemError.EntryNotFound;
        } else {
            if (cur_buddy.child2) |c| cur_buddy = c else return MemError.EntryNotFound;
        }
    }
}

/// Semi temporary until I make some decisions about the slab allocator
pub fn getObjects(obj: type, num: usize, alignment: usize) MemError![*]obj {
    _ = alignment;
    const bytes = num * @sizeOf(obj);
    return @ptrCast(@alignCast(try get(bytes)));
}

pub fn printMmap() void {
    print("todo: printMMap()", .{});
}
