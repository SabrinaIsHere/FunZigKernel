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
const GDTEntry = packed struct {
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
        self.limit1 = @intCast(limit & 0xFFFF);
        self.limit2 = @intCast((limit >> 16) & 0x0F);
        self.base1 = @intCast(base & 0xFFFF);
        self.base2 = @intCast((base << 16) & 0xFF);
        self.base3 = @intCast((base << 24) & 0xFF);
        self.access = access;
        self.flags = flags;
    }
};

/// Global storing GDT information. Processor pointed at this to load the GDT
const GDTRt = packed struct {
    limit: u16,
    base: u32,
};

var gdtr: GDTRt = undefined;

/// Tells the processor where the GDT is
/// base: pointer to GDT[0], limit: number of entries
fn loadGDT(base: *GDTEntry, limit: u8) void {
    // LGDT wants a pointer to a 6 byte region of memory with the base and length of the gdt
    gdtr = .{
        .limit = limit * @sizeOf(GDTEntry),
        .base = @intFromPtr(base),
    };
    asm volatile ("lgdt (%[gdtr])"
        :
        : [gdtr] "{eax}" (&gdtr),
    );
}

pub const NULL_SEGMENT = 0x0;
pub const K_CODE_SEGMENT = 0x1;
pub const K_DATA_SEGMENT = 0x2;
pub const USER_CODE_SEGMENT = 0x3;
pub const USER_DATA_SEGMENT = 0x4;
pub const TSS_SEGMENT = 0x5;

/// Functin the kernel calls into to initialize the GDT
/// This should NEVER be called without interrupts being disabled!
pub fn init() void {
    arch.setInterruptsEnabled(false);
    GDT[NULL_SEGMENT].init(0x0, 0x0, 0x0, 0x0);
    GDT[K_CODE_SEGMENT].init(0xFFFFF, 0x0, 0x9A, 0xC);
    GDT[K_DATA_SEGMENT].init(0xFFFFF, 0x0, 0x92, 0xC);
    GDT[USER_CODE_SEGMENT].init(0xFFFFF, 0x0, 0xFA, 0xC);
    GDT[USER_DATA_SEGMENT].init(0xFFFFF, 0x0, 0xFA, 0xC);
    const TSS: usize = @intFromPtr(&GDT[TSS_SEGMENT]);
    GDT[TSS_SEGMENT].init(@sizeOf(GDTEntry) - 1, TSS, 0x82, 0x0);
    loadGDT(&GDT[0], 5);
    arch.setInterruptsEnabled(false);
}
