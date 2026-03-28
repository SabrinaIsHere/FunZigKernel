const native_endian = @import("builtin").target.cpu.arch.endian();
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const arch = @import("arch.zig");
const Console = @import("../../io/io.zig").Console;

/// Base address of the GDT table
var GDT: [6]GDTEntry = undefined;

// TODO: Set granularity

/// Struct defining a GDT entry. GDTs are weird so variables are set with functions to abstract it, though they should never
/// be modified after the first stages of booting where they're defined with init() since I'm using paging.
pub const GDTEntry = packed struct {
    // TODO: should these be reversed?
    limit1: u16,
    base1: u16,
    base2: u8,
    access: u8,
    limit2: u4,
    flags: u4,
    base3: u8,

    /// Initialize the GDT entry at the given address. Abstract away the weirdness
    pub fn init(self: *GDTEntry, limit: u20, base: u32, access: u8, flags: u4) void {
        switch (native_endian) {
            .big => {
                // NOTE: Assuming limit2 is the most significant 4 bits
                // NOTE: This may not be right look out for that
                self.limit1 = @truncate(limit);
                self.limit2 = @truncate(limit << 16);
                self.base1 = @truncate(base);
                self.base2 = @truncate(base << 16);
                self.base3 = @truncate(base << 24);
                self.access = access;
                self.flags = flags;
            },
            .little => {
                self.limit1 = @truncate(limit);
                self.limit2 = @truncate(limit >> 16);
                self.base1 = @truncate(base);
                self.base2 = @truncate(base >> 16);
                self.base3 = @truncate(base >> 24);
                self.access = access;
                self.flags = flags;
            },
        }
    }
};

test "GDTEntry" {
    try expectEqual(8, @sizeOf(GDTEntry));
}

/// Functin the kernel calls into to initialize the GDT
/// This should NEVER be called without interrupts being disabled!
pub fn init() void {
    // BUG: This is causing a weird strobing in the serial terminal, check vga
    // Null descriptor
    GDT[0].init(0x0, 0x0, 0x0, 0x0);
    // Kernel code segment
    GDT[1].init(0xFFFFF, 0x0, 0x9A, 0xC);
    // Kernel data segment
    GDT[2].init(0xFFFFF, 0x0, 0x92, 0xC);
    // User code segment
    GDT[3].init(0xFFFFF, 0x0, 0xFA, 0xC);
    // User data segment
    GDT[4].init(0xFFFFF, 0x0, 0xFA, 0xC);
    // Task state segment
    const TSS: usize = @intFromPtr(&GDT[5]);
    GDT[5].init(@sizeOf(GDTEntry) - 1, TSS, 0x82, 0x0);
}
