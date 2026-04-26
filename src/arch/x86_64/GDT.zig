//! Handle GDT related operations
//! If I were wiling to make this uglier more of it could definitely be done at compile time

const native_endian = @import("builtin").target.cpu.arch.endian();
const std = @import("std");
const expectEqual = std.testing.expectEqual;
const arch = @import("arch.zig");
const Console = @import("../../io/io.zig").Console;

/// Base address of the GDT table
const GDT = packed struct {
    null: GDTEntry = GDTEntry{},
    k_code: GDTEntry = GDTEntry{},
    k_data: GDTEntry = GDTEntry{},
    u_code: GDTEntry = GDTEntry{},
    u_data: GDTEntry = GDTEntry{},
    tss: SSD = SSD{},
};

/// Actual gdt. Had to to do it this ugly way to accommodate the ssd
var gdt = GDT{};

// TODO: Set granularity

/// Struct defining a GDT entry. GDTs are weird so variables are set with functions to abstract it, though they should never
/// be modified after the first stages of booting where they're defined with init() since I'm using paging.
const GDTEntry = packed struct {
    limit1: u16 = 0,
    base1: u16 = 0,
    base2: u8 = 0,
    access: u8 = 0,
    limit2: u4 = 0,
    flags: u4 = 0,
    base3: u8 = 0,

    /// Initialize the GDT entry at the given address. Abstract away the weirdness
    /// Base and limit are ignored in 64 bit mode
    pub fn init(self: *GDTEntry, access: u8, flags: u4) void {
        self.access = access;
        self.flags = flags;
    }

    pub fn print(self: *GDTEntry) void {
        Console.print("Access: 0x{X}, Flags: 0x{X}\n", .{ self.access, self.flags });
    }
};

/// System segment descriptor. Long mode TSS or LDT descriptor
const SSD = packed struct(u128) {
    limit1: u16 = 0,
    base1: u24 = 0,
    access: u8 = 0,
    limit2: u4 = 0,
    flags: u4 = 0,
    base2: u40 = 0,
    reserved: u32 = 0,

    /// Convenience function to deal with bit stuff
    pub fn init(self: *align(8) SSD, limit: u20, base: u64, access: u8, flags: u4) void {
        self.limit1 = @truncate(limit);
        // I don't really need to mask the bits like this but I think it makes things more readable
        self.limit2 = @truncate((limit & 0xF) >> 16);
        self.base1 = @truncate(base);
        self.base2 = @truncate((base & 0xFFFFFFFFFFFF0000) >> 16);
        self.access = access;
        self.flags = flags;
    }
};

/// Global storing GDT information. Processor pointed at this to load the GDT
const GDTRt = packed struct {
    limit: u16,
    base: u64,
};

var gdtr: GDTRt = undefined;

/// Tells the processor where the GDT is
/// base: pointer to GDT[0], limit: number of entries
fn loadGDT(base: *GDT, limit: u8) void {
    defer Console.print("GDT loaded\n", .{});
    // LGDT wants a pointer to a 6 byte region of memory with the base and length of the gdt
    gdtr = .{
        .limit = limit * @sizeOf(GDTEntry),
        .base = @intFromPtr(base),
    };
    asm volatile ("lgdt (%[gdtr])"
        :
        : [gdtr] "{eax}" (&gdtr),
    );
    // Reload segment registers. Defined in arch.S
    arch.reloadSegments();
}

/// sgdt gets the data in the GDTR
fn storeGDT() GDTRt {
    var data = GDTRt{ .limit = 0, .base = 0 };
    asm volatile ("sgdt %[data]"
        : [data] "=m" (data),
    );
    return data;
}

pub const NULL_SEGMENT = 0x0;
pub const K_CODE_SEGMENT = 0x1;
pub const K_DATA_SEGMENT = 0x2;
pub const USER_CODE_SEGMENT = 0x3;
pub const USER_DATA_SEGMENT = 0x4;
pub const TSS_SEGMENT = 0x5;

/// Functin the kernel calls into to initialize the GDT
pub fn init() void {
    arch.disableInterrupts();
    gdt.k_code.init(0x9A, 0xA);
    gdt.k_data.init(0x92, 0xC);
    gdt.u_code.init(0xFA, 0xA);
    gdt.u_data.init(0xF2, 0xC);
    const TSS: usize = @intFromPtr(&gdt.tss);
    gdt.tss.init(@sizeOf(GDTEntry) - 1, TSS, 0x89, 0x0);
    loadGDT(&gdt, 6);
    runtimeTests();
}

fn runtimeTests() void {
    const GDTRegister = storeGDT();
    if (GDTRegister.limit / @sizeOf(GDTEntry) != 6) {
        Console.print(
            "Size of GDT differs from expected: {any}: {any}\n",
            .{ 6, GDTRegister.limit / @sizeOf(GDTEntry) },
        );
    }
    if (GDTRegister.base != @intFromPtr(&gdt)) {
        Console.print(
            "Base of GDT differs from expected: {any}: {any}\n",
            .{ GDTRegister.base, @intFromPtr(&gdt) },
        );
    }
    if (@sizeOf(GDTEntry) != 8) Console.print("GDTEntry has wrong number of bytes\n", .{});
}
